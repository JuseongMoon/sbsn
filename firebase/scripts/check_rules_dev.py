"""sbsn-dev 보안 규칙 실전 검증. 익명 사용자 A(티켓 소유자)와 B(다른 사용자)로 허용·거부를 확인한다.

사용(저장소 루트에서):
  python3 -I firebase/scripts/check_rules_dev.py \
    "$(/usr/libexec/PlistBuddy -c 'Print API_KEY' sbsnPhotographer/Config/GoogleService-Info.plist)" \
    "$(gcloud auth application-default print-access-token)"

규칙을 바꿔 배포한 뒤 실제 개발 프로젝트(sbsn-dev)에 대해 돌린다.
토큰은 출력하지 않는다. 끝나면 시험 데이터와 시험 사용자를 관리자 권한으로 지운다.
"""
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API_KEY, ADMIN = sys.argv[1], sys.argv[2]
PROJECT = "sbsn-dev"
BUCKET = "sbsn-dev.firebasestorage.app"
FS = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
TICKET = f"rules-check-{int(time.time())}"


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


def sign_up():
    status, data = call("POST", f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={API_KEY}", {"returnSecureToken": True})
    assert status == 200, f"익명 가입 실패 {status}"
    return data["localId"], data["idToken"]


def fs_write(token, path, fields, merge=False):
    # merge=True면 준 항목만 바꾼다(앱의 setData(merge: true)와 같음). 아니면 문서를 통째로 덮어쓴다.
    mask = "?" + "&".join(f"updateMask.fieldPaths={key}" for key in fields) if merge else ""
    return call("PATCH", f"{FS}/{path}{mask}", {"fields": fields}, {"Authorization": f"Bearer {token}"})[0]


def fs_read(token, path):
    return call("GET", f"{FS}/{path}", headers={"Authorization": f"Bearer {token}"})[0]


def upload(token, name, content_type="image/jpeg", size=None):
    url = f"https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o?name={urllib.parse.quote(name, safe='')}"
    body = b"\xff\xd8" + (b"\0" * size if size else b"test") + b"\xff\xd9"
    return call("POST", url, headers={"Authorization": f"Firebase {token}", "Content-Type": content_type}, raw=body)[0]


def read_object(token, name):
    url = f"https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o/{urllib.parse.quote(name, safe='')}"
    return call("GET", url, headers={"Authorization": f"Firebase {token}"})[0]


results = []


def expect(label, status, allowed):
    ok = (status == 200) == allowed
    results.append(ok)
    print(f"{'통과' if ok else '실패'}  {label}: HTTP {status} (기대: {'허용' if allowed else '거부'})")


a_uid, a = sign_up()
b_uid, b = sign_up()
ticket = f"tickets/{TICKET}"
photo = f"{ticket}/photos/DSC00001.JPG"
original = f"{ticket}/originals/DSC00001.JPG"

expect("B가 A 명의로 티켓 생성", fs_write(b, ticket, {"photographerUid": {"stringValue": a_uid}}), False)
expect("A가 자기 티켓 생성", fs_write(a, ticket, {"photographerUid": {"stringValue": a_uid}}), True)
expect("A가 자기 티켓 읽기", fs_read(a, ticket), True)
expect("B가 A의 티켓 읽기", fs_read(b, ticket), False)
expect("B가 A의 티켓을 자기 것으로 변경", fs_write(b, ticket, {"photographerUid": {"stringValue": b_uid}}), False)
expect("A가 티켓 소유자를 B로 변경", fs_write(a, ticket, {"photographerUid": {"stringValue": b_uid}}), False)
expect("A가 원본 업로드", upload(a, original), True)
expect("B가 A의 티켓에 원본 업로드", upload(b, f"{ticket}/originals/B.JPG"), False)
expect("A가 이미지가 아닌 파일 업로드", upload(a, f"{ticket}/originals/x.txt", "text/plain"), False)
expect("A가 원본 읽기", read_object(a, original), True)
expect("B가 A의 원본 읽기", read_object(b, original), False)
preview = f"{ticket}/previews/DSC00001.JPG.jpg"
expect("A가 미리보기 업로드", upload(a, preview), True)
expect("B가 A의 티켓에 미리보기 업로드", upload(b, f"{ticket}/previews/B.jpg"), False)
expect("A가 JPEG가 아닌 미리보기 업로드", upload(a, f"{ticket}/previews/x.png", "image/png"), False)
expect("A가 미리보기 읽기", read_object(a, preview), True)
expect("B가 A의 미리보기 읽기", read_object(b, preview), False)
expect("A가 사진 문서 기록", fs_write(a, photo, {"fileName": {"stringValue": "DSC00001.JPG"}}), True)
expect("B가 A의 티켓에 사진 문서 기록", fs_write(b, f"{ticket}/photos/B.JPG", {"fileName": {"stringValue": "B"}}), False)
expect("A가 1MB 넘는 미리보기 업로드", upload(a, f"{ticket}/previews/big.jpg", size=1024 * 1024), False)
fullres = f"{ticket}/fullres/DSC00001.JPG.heic"
expect("A가 고화질본 업로드", upload(a, fullres, "image/heic"), True)
expect("A가 HEIC가 아닌 고화질본 업로드", upload(a, f"{ticket}/fullres/x.jpg"), False)
expect("B가 A의 티켓에 고화질본 업로드", upload(b, f"{ticket}/fullres/B.heic", "image/heic"), False)
expect("A가 고화질본 읽기", read_object(a, fullres), True)
expect("B가 A의 고화질본 읽기", read_object(b, fullres), False)

# 찜·구매는 작가 앱이 쓸 수 없다. 관리자(결제 서버 대신)가 구매를 기록한 뒤에도 작가 앱은 다른 항목만 고칠 수 있다.
purchase = {"purchasedAt": {"timestampValue": "2026-10-22T06:00:00Z"}}
expect("A가 구매 기록을 넣어 사진 문서 생성", fs_write(a, f"{ticket}/photos/DSC00002.JPG", {"fileName": {"stringValue": "DSC00002.JPG"}, **purchase}), False)
admin_headers = {"Authorization": f"Bearer {ADMIN}", "x-goog-user-project": PROJECT}
status = call("PATCH", f"{FS}/{photo}?updateMask.fieldPaths=purchasedAt", {"fields": purchase}, admin_headers)[0]
assert status == 200, f"관리자 구매 기록 실패 {status}"
expect("A가 구매된 사진 문서에 고화질본 정보 병합", fs_write(a, photo, {"fullresPath": {"stringValue": fullres}}, merge=True), True)
expect("A가 구매 시각 바꾸기", fs_write(a, photo, {"purchasedAt": {"timestampValue": "2026-10-22T07:00:00Z"}}, merge=True), False)
expect("A가 찜 기록", fs_write(a, photo, {"favoritedAt": {"timestampValue": "2026-10-22T06:00:00Z"}}, merge=True), False)
expect("A가 사진 문서를 덮어써 구매 기록 지우기", fs_write(a, photo, {"fileName": {"stringValue": "DSC00001.JPG"}}), False)

# 정리: 관리자 권한(ADC)으로 시험 데이터와 시험 사용자 삭제
admin = {"Authorization": f"Bearer {ADMIN}", "x-goog-user-project": PROJECT}
cleanup = [
    call("DELETE", f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o/{urllib.parse.quote(original, safe='')}", headers=admin)[0],
    call("DELETE", f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o/{urllib.parse.quote(preview, safe='')}", headers=admin)[0],
    call("DELETE", f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o/{urllib.parse.quote(fullres, safe='')}", headers=admin)[0],
    call("DELETE", f"{FS}/{photo}", headers=admin)[0],
    call("DELETE", f"{FS}/{ticket}", headers=admin)[0],
    call("POST", f"https://identitytoolkit.googleapis.com/v1/projects/{PROJECT}/accounts:batchDelete", {"localIds": [a_uid, b_uid], "force": True}, admin)[0],
]
print(f"정리 응답: {cleanup}")
print(f"결과: {sum(results)}/{len(results)} 통과")
