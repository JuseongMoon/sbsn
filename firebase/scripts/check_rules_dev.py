"""보안 규칙 검증. 익명 사용자 A(작가)·B(다른 사람)·C(고객)·D(다른 고객)·E(두 번째 작가)로 허용·거부를 확인한다.

실제 프로젝트(규칙을 배포한 뒤, 저장소 루트에서):
  python3 -I firebase/scripts/check_rules_dev.py \\
    "$(/usr/libexec/PlistBuddy -c 'Print API_KEY' sbsnPhotographer/Config/GoogleService-Info.plist)" \\
    "$(gcloud auth application-default print-access-token)"

에뮬레이터(배포하기 전, firebase/ 안에서):
  npx --yes firebase-tools@15.34.1 emulators:exec --only firestore,storage --project sbsn-dev \\
    "python3 -I scripts/check_rules_dev.py --emulator"

고객 확정처럼 앱이 트랜잭션으로 보내는 쓰기는 REST의 documents:commit(원자)으로 보낸다. batchWrite는 원자가 아니라
규칙의 getAfter 검증에 쓸 수 없다. 토큰은 출력하지 않는다. 끝나면 시험 데이터와 시험 사용자를 관리자 권한으로 지운다.
"""
import base64
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

EMULATOR = "--emulator" in sys.argv
PROJECT = "sbsn-dev"
BUCKET = f"{PROJECT}.firebasestorage.app"
ROOT = f"projects/{PROJECT}/databases/(default)/documents"
if EMULATOR:
    FS = f"http://127.0.0.1:8080/v1/{ROOT}"
    STORAGE = f"http://127.0.0.1:9199/v0/b/{BUCKET}/o"
    ADMIN = "owner"
else:
    API_KEY, ADMIN = sys.argv[1], sys.argv[2]
    FS = f"https://firestore.googleapis.com/v1/{ROOT}"
    STORAGE = f"https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o"
RUN = int(time.time())
OLD = "2026-01-01T00:00:00Z"
SEOUL = {"geoPointValue": {"latitude": 37.5796, "longitude": 126.977}}


def call(method, url, body=None, headers=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as res:
            return res.status, json.loads(res.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {}


# ---- 사용자 ----

def unsigned_token(uid):
    # 에뮬레이터는 서명 없는 ID 토큰을 받아 규칙의 request.auth로 쓴다.
    def encode(data):
        return base64.urlsafe_b64encode(json.dumps(data).encode()).decode().rstrip("=")
    now = int(time.time())
    claims = {"sub": uid, "user_id": uid, "iat": now, "exp": now + 3600, "aud": PROJECT,
              "iss": f"https://securetoken.google.com/{PROJECT}", "firebase": {"sign_in_provider": "anonymous"}}
    return encode({"alg": "none", "typ": "JWT"}) + "." + encode(claims) + "."


def user(name):
    if EMULATOR:
        uid = f"{name}-{RUN}"
        return uid, unsigned_token(uid)
    status, data = call("POST", f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={API_KEY}", {"returnSecureToken": True})
    assert status == 200, f"익명 가입 실패 {status}"
    return data["localId"], data["idToken"]


def auth(token):
    return {"Authorization": f"Bearer {token}"}


ADMIN_HEADERS = {"Authorization": f"Bearer {ADMIN}", "x-goog-user-project": PROJECT}


# ---- Firestore 값과 쓰기 ----

def S(value):
    return {"stringValue": value}


def B(value):
    return {"booleanValue": value}


def T(value):
    return {"timestampValue": value}


NULL = {"nullValue": None}


def w(path, fields=None, mask=None, server=(), exists=None):
    """commit에 넣을 쓰기 하나. mask가 있으면 그 항목만 바꾸고(없는 항목은 지움), 없으면 문서를 통째로 쓴다.
    server는 서버 시각으로 채울 항목이다(앱의 FieldValue.serverTimestamp()와 같음)."""
    write = {"update": {"name": f"{ROOT}/{path}", "fields": fields or {}}}
    if mask is not None:
        write["updateMask"] = {"fieldPaths": mask}
    if server:
        write["updateTransforms"] = [{"fieldPath": key, "setToServerValue": "REQUEST_TIME"} for key in server]
    if exists is not None:
        write["currentDocument"] = {"exists": exists}
    return write


def commit(token, *writes):
    return call("POST", f"{FS}:commit", {"writes": list(writes)}, auth(token))[0]


def merge(token, path, fields, server=()):
    # 준 항목만 바꾼다(앱의 setData(merge: true)·updateData와 같음).
    return commit(token, w(path, fields, mask=list(fields) + list(server), server=server))


def unset(token, path, *keys):
    # 항목을 지운다(앱의 FieldValue.delete()와 같음).
    return commit(token, w(path, {}, mask=list(keys)))


def read(token, path):
    return call("GET", f"{FS}/{path}", headers=auth(token))[0]


def query(token, collection, field=None, value=None, limit=None):
    structured = {"from": [{"collectionId": collection}]}
    if field is not None:
        structured["where"] = {"fieldFilter": {"field": {"fieldPath": field}, "op": "EQUAL", "value": value}}
    if limit is not None:
        structured["limit"] = limit
    return call("POST", f"{FS}:runQuery", {"structuredQuery": structured}, auth(token))[0]


def admin_merge(path, fields, server=()):
    return commit(ADMIN, w(path, fields, mask=list(fields) + list(server), server=server))


def admin_delete(path):
    return call("DELETE", f"{FS}/{path}", headers=ADMIN_HEADERS)[0]


# ---- Storage ----

def jpeg_bytes(size=None):
    return b"\xff\xd8" + (b"\0" * size if size else b"test") + b"\xff\xd9"


def upload(token, name, content_type="image/jpeg", metadata=None, size=None):
    """메타데이터가 있으면 앱의 putFile/putData처럼 multipart로 올린다."""
    body = jpeg_bytes(size)
    headers = {"Authorization": f"Firebase {token}"}
    if metadata is None:
        url = f"{STORAGE}?name={urllib.parse.quote(name, safe='')}"
        headers["Content-Type"] = content_type
        return call("POST", url, headers=headers, raw=body)[0]
    boundary = uuid.uuid4().hex
    meta = json.dumps({"name": name, "contentType": content_type, "metadata": metadata}).encode()
    raw = (f"--{boundary}\r\nContent-Type: application/json; charset=utf-8\r\n\r\n".encode() + meta
           + f"\r\n--{boundary}\r\nContent-Type: {content_type}\r\n\r\n".encode() + body
           + f"\r\n--{boundary}--\r\n".encode())
    url = f"{STORAGE}?name={urllib.parse.quote(name, safe='')}&uploadType=multipart"
    headers.update({"Content-Type": f"multipart/related; boundary={boundary}", "X-Goog-Upload-Protocol": "multipart"})
    return call("POST", url, headers=headers, raw=raw)[0]


def admin_upload_without_metadata(name):
    if EMULATOR:
        return call("POST", f"{STORAGE}?name={urllib.parse.quote(name, safe='')}",
                    headers={"Authorization": "Bearer owner", "Content-Type": "image/jpeg"}, raw=jpeg_bytes())[0]
    url = f"https://storage.googleapis.com/upload/storage/v1/b/{BUCKET}/o?uploadType=media&name={urllib.parse.quote(name, safe='')}"
    return call("POST", url, headers={**ADMIN_HEADERS, "Content-Type": "image/jpeg"}, raw=jpeg_bytes())[0]


def read_object(token, name):
    return call("GET", f"{STORAGE}/{urllib.parse.quote(name, safe='')}", headers={"Authorization": f"Firebase {token}"})[0]


def admin_delete_object(name):
    if EMULATOR:
        return call("DELETE", f"{STORAGE}/{urllib.parse.quote(name, safe='')}", headers={"Authorization": "Bearer owner"})[0]
    return call("DELETE", f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o/{urllib.parse.quote(name, safe='')}", headers=ADMIN_HEADERS)[0]


# ---- 시나리오 ----

results = []


def expect(label, status, allowed):
    ok = (status == 200) == allowed
    results.append(ok)
    print(f"{'통과' if ok else '실패'}  {label}: HTTP {status} (기대: {'허용' if allowed else '거부'})")


a_uid, a = user("photographer")
b_uid, b = user("stranger")
c_uid, c = user("customer")
d_uid, d = user("customer2")
e_uid, e = user("photographer2")
T1 = f"rules-{RUN}-1"
T2 = f"rules-{RUN}-2"
T3 = f"rules-{RUN}-3"
presence_a = f"photographerPresence/{a_uid}"
presence_e = f"photographerPresence/{e_uid}"


def presence_fields(name="작가"):
    return {"displayName": S(name), "isAvailable": B(True), "location": SEOUL, "expiresAt": T("2026-12-31T00:00:00Z"), "activeTicketId": NULL}


def set_presence(token, path, fields):
    return commit(token, w(path, fields, server=["updatedAt"]))


def new_ticket(ticket, photographer_uid, display_name, customer):
    return w(f"tickets/{ticket}", {"customerUid": customer, "photographerUid": S(photographer_uid), "photographerDisplayName": S(display_name)},
             server=["createdAt"], exists=False)


def lock_presence(path, ticket):
    return w(path, {"activeTicketId": S(ticket)}, mask=["activeTicketId"])


def claim_customer(uid, ticket):
    return w(f"customers/{uid}", {"activeTicketId": S(ticket)})


def release(path):
    return w(path, {"activeTicketId": NULL}, mask=["activeTicketId"])


print("--- 작가 기기 토큰(기존) ---")
device = {"fcmToken": S("rules-check-token"), "fcmTokenUpdatedAt": T("2026-10-24T00:00:00Z")}
expect("A가 자기 기기 토큰 등록", commit(a, w(f"photographers/{a_uid}", device)), True)
expect("B가 A의 기기 토큰 읽기", read(b, f"photographers/{a_uid}"), False)
expect("A가 기기 문서에 다른 항목 쓰기", commit(a, w(f"photographers/{a_uid}", {**device, "role": S("admin")})), False)

print("--- 작가 공개 상태 ---")
expect("A가 자기 상태 발행", set_presence(a, presence_a, presence_fields()), True)
expect("B가 A의 상태 쓰기", set_presence(b, presence_a, presence_fields("가짜")), False)
expect("A가 허용 외 항목(fcmToken) 포함", set_presence(a, presence_a, {**presence_fields(), "fcmToken": S("x")}), False)
expect("A가 40자 이름", set_presence(a, presence_a, presence_fields("가" * 40)), False)
expect("A가 서버 시각 없이 갱신", commit(a, w(presence_a, {**presence_fields(), "updatedAt": T(OLD)})), False)
expect("C가 작가 상태 읽기", read(c, presence_a), True)
expect("C가 촬영 가능 작가 목록(limit 50)", query(c, "photographerPresence", "isAvailable", B(True), limit=50), True)
expect("C가 목록을 limit 없이", query(c, "photographerPresence", "isAvailable", B(True)), False)
expect("C가 목록을 limit 500으로", query(c, "photographerPresence", "isAvailable", B(True), limit=500), False)
expect("E가 자기 상태 발행", set_presence(e, presence_e, presence_fields("작가2")), True)

print("--- 고객 확정(트랜잭션) ---")
expect("C가 티켓만 쓰기", commit(c, new_ticket(T1, a_uid, "작가", S(c_uid))), False)
expect("C가 작가 잠금만 쓰기", commit(c, lock_presence(presence_a, T1)), False)
expect("C가 고객 문서 없이", commit(c, new_ticket(T1, a_uid, "작가", S(c_uid)), lock_presence(presence_a, T1)), False)
expect("C가 표시 이름을 바꿔서", commit(c, new_ticket(T1, a_uid, "다른이름", S(c_uid)), lock_presence(presence_a, T1), claim_customer(c_uid, T1)), False)
expect("C가 B 명의로", commit(c, new_ticket(T1, a_uid, "작가", S(b_uid)), lock_presence(presence_a, T1), claim_customer(c_uid, T1)), False)
expect("C가 상태 문서 없는 작가로", commit(c, new_ticket(T1, "nobody", "작가", S(c_uid)), lock_presence("photographerPresence/nobody", T1), claim_customer(c_uid, T1)), False)
expect("A가 작가 단독으로 티켓 생성", commit(a, w(f"tickets/{T1}", {"photographerUid": S(a_uid)}, server=["createdAt"], exists=False)), False)
expect("A가 자기를 고객으로 자기 티켓 생성", commit(a, new_ticket(T1, a_uid, "작가", S(a_uid)), lock_presence(presence_a, T1), claim_customer(a_uid, T1)), False)
expect("C가 정상 확정", commit(c, new_ticket(T1, a_uid, "작가", S(c_uid)), lock_presence(presence_a, T1), claim_customer(c_uid, T1)), True)
expect("D가 같은 작가를 확정", commit(d, new_ticket(T2, a_uid, "작가", S(d_uid)), lock_presence(presence_a, T2), claim_customer(d_uid, T2)), False)
expect("C가 기존 티켓으로 다른 작가 잠그기", commit(c, lock_presence(presence_e, T1)), False)
expect("C가 활성 티켓이 있는 채로 두 번째 작가 확정", commit(c, new_ticket(T2, e_uid, "작가2", S(c_uid)), lock_presence(presence_e, T2), claim_customer(c_uid, T2)), False)
assert admin_merge(presence_e, {"updatedAt": T(OLD)}) == 200
expect("D가 10분 넘게 조용한 작가를 확정", commit(d, new_ticket(T2, e_uid, "작가2", S(d_uid)), lock_presence(presence_e, T2), claim_customer(d_uid, T2)), False)
expect("E가 자기 상태를 다시 발행", set_presence(e, presence_e, presence_fields("작가2")), True)
expect("D가 E를 확정", commit(d, new_ticket(T2, e_uid, "작가2", S(d_uid)), lock_presence(presence_e, T2), claim_customer(d_uid, T2)), True)
expect("C가 자기 고객 문서 읽기", read(c, f"customers/{c_uid}"), True)
expect("B가 C의 고객 문서 읽기", read(b, f"customers/{c_uid}"), False)

print("--- 티켓 읽기·불변 항목 ---")
expect("A가 티켓 읽기", read(a, f"tickets/{T1}"), True)
expect("C가 티켓 읽기", read(c, f"tickets/{T1}"), True)
expect("B가 티켓 읽기", read(b, f"tickets/{T1}"), False)
expect("C가 작가를 B로 변경", merge(c, f"tickets/{T1}", {"photographerUid": S(b_uid)}), False)
expect("A가 고객을 B로 변경", merge(a, f"tickets/{T1}", {"customerUid": S(b_uid)}), False)
expect("C가 생성 시각 변경", merge(c, f"tickets/{T1}", {"createdAt": T(OLD)}), False)

print("--- 전이: 받음 → 시작 → 촬영 중 ---")
expect("A가 받음 표시", merge(a, f"tickets/{T1}", {}, server=["photographerAckAt"]), True)
expect("A가 받음 표시 다시", merge(a, f"tickets/{T1}", {}, server=["photographerAckAt"]), False)
expect("C가 받음 표시", merge(c, f"tickets/{T1}", {}, server=["photographerAckAt"]), False)
expect("양쪽 시작 전 A가 종료", merge(a, f"tickets/{T1}", {}, server=["endedAt"]), False)
expect("C가 시작을 과거 시각으로", merge(c, f"tickets/{T1}", {"customerStartedAt": T(OLD)}), False)
expect("C가 시작", merge(c, f"tickets/{T1}", {}, server=["customerStartedAt"]), True)
expect("C가 시작 다시", merge(c, f"tickets/{T1}", {}, server=["customerStartedAt"]), False)
expect("C가 작가 시작 대신 쓰기", merge(c, f"tickets/{T1}", {}, server=["photographerStartedAt"]), False)
expect("고객만 시작한 뒤 C가 종료", merge(c, f"tickets/{T1}", {}, server=["endedAt"]), False)
expect("A가 시작", merge(a, f"tickets/{T1}", {}, server=["photographerStartedAt"]), True)
expect("촬영 중 C가 취소", merge(c, f"tickets/{T1}", {"cancelledBy": S(c_uid)}, server=["cancelledAt"]), False)
expect("촬영 중 C가 바로 종료(60분 전)", merge(c, f"tickets/{T1}", {}, server=["endedAt"]), False)

print("--- 위치·채팅 ---")
location = {"location": SEOUL}
expect("A가 자기 위치", merge(a, f"tickets/{T1}/locations/{a_uid}", location, server=["updatedAt"]), True)
expect("C가 A의 위치 쓰기", merge(c, f"tickets/{T1}/locations/{a_uid}", location, server=["updatedAt"]), False)
expect("C가 자기 위치", merge(c, f"tickets/{T1}/locations/{c_uid}", location, server=["updatedAt"]), True)
expect("B가 자기 위치를 남의 티켓에", merge(b, f"tickets/{T1}/locations/{b_uid}", location, server=["updatedAt"]), False)
expect("A가 문자열 위치", merge(a, f"tickets/{T1}/locations/{a_uid}", {"location": S("x")}, server=["updatedAt"]), False)
expect("A가 위치에 다른 항목", merge(a, f"tickets/{T1}/locations/{a_uid}", {**location, "note": S("x")}, server=["updatedAt"]), False)
expect("C가 A의 위치 읽기", read(c, f"tickets/{T1}/locations/{a_uid}"), True)
expect("B가 A의 위치 읽기", read(b, f"tickets/{T1}/locations/{a_uid}"), False)
message = f"tickets/{T1}/messages/m1"
expect("C가 메시지", commit(c, w(message, {"senderUid": S(c_uid), "text": S("정문 앞이에요")}, server=["sentAt"], exists=False)), True)
expect("C가 A 이름으로 메시지", commit(c, w(f"tickets/{T1}/messages/m2", {"senderUid": S(a_uid), "text": S("x")}, server=["sentAt"], exists=False)), False)
expect("B가 남의 티켓에 메시지", commit(b, w(f"tickets/{T1}/messages/m3", {"senderUid": S(b_uid), "text": S("x")}, server=["sentAt"], exists=False)), False)
expect("C가 1,001자 메시지", commit(c, w(f"tickets/{T1}/messages/m4", {"senderUid": S(c_uid), "text": S("가" * 1001)}, server=["sentAt"], exists=False)), False)
expect("C가 빈 메시지", commit(c, w(f"tickets/{T1}/messages/m5", {"senderUid": S(c_uid), "text": S("")}, server=["sentAt"], exists=False)), False)
expect("A가 메시지 읽기", read(a, message), True)
expect("B가 메시지 읽기", read(b, message), False)
expect("C가 자기 메시지 수정", merge(c, message, {"text": S("수정")}), False)
expect("C가 자기 메시지 삭제", call("DELETE", f"{FS}/{message}", headers=auth(c))[0], False)

print("--- 사진 문서 ---")
photo1, photo2, photo3 = (f"tickets/{T1}/photos/DSC0000{n}.JPG" for n in (1, 2, 3))
expect("A가 사진 문서 생성(미리보기 정보)", merge(a, photo1, {"fileName": S("DSC00001.JPG"), "previewPath": S("p")}, server=["previewUploadedAt"]), True)
expect("A가 구매 기록을 넣어 생성", merge(a, photo2, {"fileName": S("DSC00002.JPG"), "purchasedAt": T(OLD)}), False)
expect("C가 사진 문서 생성", merge(c, photo2, {"fileName": S("DSC00002.JPG")}, server=["favoritedAt"]), False)
expect("A가 두 번째 사진 문서 생성", merge(a, photo2, {"fileName": S("DSC00002.JPG")}, server=["previewUploadedAt"]), True)
expect("A가 세 번째 사진 문서 생성(고화질본까지)", merge(a, photo3, {"fileName": S("DSC00003.JPG")}, server=["previewUploadedAt", "fullresUploadedAt"]), True)
expect("C가 찜", merge(c, photo1, {}, server=["favoritedAt"]), True)
expect("C가 찜을 과거 시각으로", merge(c, photo1, {"favoritedAt": T(OLD)}), False)
expect("C가 찜 해제", unset(c, photo1, "favoritedAt"), True)
expect("B가 찜", merge(b, photo1, {}, server=["favoritedAt"]), False)
expect("A가 찜", merge(a, photo1, {}, server=["favoritedAt"]), False)
expect("C가 구매(구매 항목이 없던 문서)", merge(c, photo1, {}, server=["purchasedAt"]), True)
expect("C가 구매 다시", merge(c, photo1, {}, server=["purchasedAt"]), False)
expect("C가 구매 지우기", unset(c, photo1, "purchasedAt"), False)
expect("C가 고화질본 경로 쓰기", merge(c, photo1, {"fullresPath": S("x")}), False)
expect("C가 고화질본 전에 전달 기록", merge(c, photo1, {}, server=["deliveredAt"]), False)
expect("A가 구매된 사진에 고화질본 정보 병합", merge(a, photo1, {"fullresPath": S("f")}, server=["fullresUploadedAt"]), True)
expect("A가 구매 시각 바꾸기", merge(a, photo1, {"purchasedAt": T(OLD)}), False)
expect("A가 전달 기록", merge(a, photo1, {}, server=["deliveredAt"]), False)
expect("C가 전달 기록", merge(c, photo1, {}, server=["deliveredAt"]), True)
expect("C가 전달 기록 다시", merge(c, photo1, {}, server=["deliveredAt"]), False)
expect("B가 사진 문서 읽기", read(b, photo1), False)
expect("C가 사진 문서 읽기", read(c, photo1), True)

print("--- Storage ---")
participants = {"customerUid": c_uid, "photographerUid": a_uid}
preview = f"tickets/{T1}/previews/DSC00001.JPG.jpg"
fullres1, fullres2, fullres9 = (f"tickets/{T1}/fullres/DSC0000{n}.JPG.heic" for n in (1, 2, 9))
original = f"tickets/{T1}/originals/DSC00001.JPG"
expect("A가 미리보기 업로드(참여자 메타데이터)", upload(a, preview, metadata=participants), True)
expect("A가 메타데이터 없이 업로드", upload(a, f"tickets/{T1}/previews/x.jpg"), False)
expect("A가 고객을 틀리게 적어 업로드", upload(a, f"tickets/{T1}/previews/y.jpg", metadata={"customerUid": b_uid, "photographerUid": a_uid}), False)
expect("B가 미리보기 업로드", upload(b, f"tickets/{T1}/previews/z.jpg", metadata=participants), False)
expect("A가 1MB 넘는 미리보기", upload(a, f"tickets/{T1}/previews/big.jpg", metadata=participants, size=1024 * 1024), False)
expect("A가 JPEG 아닌 미리보기", upload(a, f"tickets/{T1}/previews/x.png", "image/png", metadata=participants), False)
expect("C가 미리보기 읽기", read_object(c, preview), True)
expect("A가 미리보기 읽기", read_object(a, preview), True)
expect("B가 미리보기 읽기", read_object(b, preview), False)
nometa = f"tickets/{T1}/previews/nometa.jpg"
assert admin_upload_without_metadata(nometa) == 200
expect("C가 메타데이터 없는 미리보기 읽기", read_object(c, nometa), False)
expect("A가 고화질본 업로드", upload(a, fullres1, "image/heic", metadata=participants), True)
expect("A가 미구매 고화질본 업로드", upload(a, fullres2, "image/heic", metadata=participants), True)
expect("A가 사진 문서 없는 고화질본 업로드", upload(a, fullres9, "image/heic", metadata=participants), True)
expect("A가 HEIC 아닌 고화질본", upload(a, f"tickets/{T1}/fullres/x.jpg", metadata=participants), False)
expect("C가 고화질본 업로드", upload(c, f"tickets/{T1}/fullres/c.heic", "image/heic", metadata=participants), False)
expect("C가 구매한 고화질본 읽기", read_object(c, fullres1), True)
expect("C가 구매 안 한 고화질본 읽기", read_object(c, fullres2), False)
expect("C가 사진 문서 없는 고화질본 읽기", read_object(c, fullres9), False)
expect("A가 고화질본 읽기", read_object(a, fullres2), True)
expect("B가 구매된 고화질본 읽기", read_object(b, fullres1), False)
expect("A가 원본 업로드", upload(a, original, metadata=participants), True)
expect("A가 이미지 아닌 원본", upload(a, f"tickets/{T1}/originals/x.txt", "text/plain", metadata=participants), False)
expect("A가 원본 읽기", read_object(a, original), True)
expect("C가 원본 읽기", read_object(c, original), False)

print("--- 종료 뒤 ---")
expect("A가 종료", merge(a, f"tickets/{T1}", {}, server=["endedAt"]), True)
expect("종료 뒤 A가 시작 다시", merge(a, f"tickets/{T1}", {}, server=["photographerStartedAt"]), False)
expect("종료 뒤 고화질본 없는 사진 구매", merge(c, photo2, {}, server=["purchasedAt"]), False)
expect("종료 뒤 고화질본 있는 사진 구매", merge(c, photo3, {}, server=["purchasedAt"]), True)
expect("종료 뒤 A가 사진 정보 병합", merge(a, photo2, {"fullresPath": S("f")}, server=["fullresUploadedAt"]), True)
expect("A가 자기 잠금 해제", set_presence(a, presence_a, presence_fields()), True)
expect("C가 끝난 티켓의 고객 잠금 해제", commit(c, release(f"customers/{c_uid}")), True)
expect("C가 잠금 해제 다시(이미 비어 있음)", commit(c, release(f"customers/{c_uid}")), False)

print("--- 취소(두 번째 매칭) ---")
expect("D가 취소 없이 작가 잠금 해제", commit(d, release(presence_e)), False)
expect("B가 D의 티켓 취소", merge(b, f"tickets/{T2}", {"cancelledBy": S(b_uid)}, server=["cancelledAt"]), False)
expect("D가 남 이름으로 취소", merge(d, f"tickets/{T2}", {"cancelledBy": S(e_uid)}, server=["cancelledAt"]), False)
expect("E가 시작(한쪽만)", merge(e, f"tickets/{T2}", {}, server=["photographerStartedAt"]), True)
expect("D가 취소 트랜잭션(티켓+작가 잠금+고객 잠금)",
       commit(d, w(f"tickets/{T2}", {"cancelledBy": S(d_uid)}, mask=["cancelledBy", "cancelledAt"], server=["cancelledAt"]),
              release(presence_e), release(f"customers/{d_uid}")), True)
expect("취소 뒤 D가 시작", merge(d, f"tickets/{T2}", {}, server=["customerStartedAt"]), False)
expect("취소 뒤 E가 종료", merge(e, f"tickets/{T2}", {}, server=["endedAt"]), False)
expect("취소 뒤 D가 메시지", commit(d, w(f"tickets/{T2}/messages/m1", {"senderUid": S(d_uid), "text": S("x")}, server=["sentAt"], exists=False)), True)
expect("해제된 작가를 C가 다시 확정", commit(c, new_ticket(T3, e_uid, "작가2", S(c_uid)), lock_presence(presence_e, T3), claim_customer(c_uid, T3)), True)
expect("C가 바로 취소 트랜잭션",
       commit(c, w(f"tickets/{T3}", {"cancelledBy": S(c_uid)}, mask=["cancelledBy", "cancelledAt"], server=["cancelledAt"]),
              release(presence_e), release(f"customers/{c_uid}")), True)

# 정리: 관리자 권한으로 시험 데이터와 시험 사용자 삭제
cleanup = [admin_delete_object(name) for name in (preview, nometa, fullres1, fullres2, fullres9, original)]
for ticket in (T1, T2, T3):
    for sub in ("photos/DSC00001.JPG", "photos/DSC00002.JPG", "photos/DSC00003.JPG", f"locations/{a_uid}", f"locations/{c_uid}",
                "messages/m1"):
        admin_delete(f"tickets/{ticket}/{sub}")
    cleanup.append(admin_delete(f"tickets/{ticket}"))
cleanup += [admin_delete(path) for path in (presence_a, presence_e, f"customers/{c_uid}", f"customers/{d_uid}", f"photographers/{a_uid}")]
if not EMULATOR:
    cleanup.append(call("POST", f"https://identitytoolkit.googleapis.com/v1/projects/{PROJECT}/accounts:batchDelete",
                        {"localIds": [a_uid, b_uid, c_uid, d_uid, e_uid], "force": True}, ADMIN_HEADERS)[0])
print(f"정리 응답: {cleanup}")
print(f"결과: {sum(results)}/{len(results)} 통과")
sys.exit(0 if all(results) else 1)
