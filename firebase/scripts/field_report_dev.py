"""현장 실증이 끝난 뒤 sbsn-dev 서버 기록으로 한 사이클의 시각표를 뽑는다(관리자 권한, 읽기만 한다).

티켓 전이(확정 → 작가 앱 받음 → 양측 시작 → 종료·취소), 채팅 시각, 위치 공유 마지막 갱신,
사진별 촬영·미리보기·찜·구매·고화질본·전달 시각과 걸린 시간을 한국 시각으로 출력한다. 채팅 내용은 출력하지 않는다.
알림 도착 시각은 서버에 남지 않아 대리 지표를 쓴다: 매칭 알림은 확정 → 작가 앱 받음(photographerAckAt),
구매 알림은 구매 → 고화질본 저장(구매 때 고화질본이 이미 올라가 있던 사진은 뺀다).
촬영 → 미리보기는 카메라 시계 기준이라 카메라 시계가 틀린 만큼 어긋난다.

사용(저장소 루트에서, 토큰은 출력하지 않는다):
  export SBSN_ADMIN_TOKEN="$(gcloud auth application-default print-access-token)"
  python3 -I firebase/scripts/field_report_dev.py <티켓 ID>
  python3 -I firebase/scripts/field_report_dev.py latest [작가 uid]
    → 가장 최근에 만든 티켓. 다른 시험(안드로이드 교차 시험 등)이 sbsn-dev에 티켓을 만들 수 있으니
      작가 uid(작가 앱 홈 "개발"의 작가 ID)를 주면 그 작가의 가장 최근 티켓을 고른다.
"""
import json
import os
import statistics
import sys
import urllib.error
import urllib.request
from datetime import datetime

PROJECT = "sbsn-dev"
ROOT = f"projects/{PROJECT}/databases/(default)/documents"
API = f"https://firestore.googleapis.com/v1/{ROOT}"
HEADERS = {"Authorization": f"Bearer {os.environ['SBSN_ADMIN_TOKEN']}", "x-goog-user-project": PROJECT,
           "Content-Type": "application/json"}


def call(method, url, body=None):
    request = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, method=method, headers=HEADERS)
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        sys.exit(f"HTTP {error.code}: {error.read().decode()[:300]}")


def latest_ticket(photographer_uid=None):
    query = {"from": [{"collectionId": "tickets"}]}
    if photographer_uid:
        # 다른 필드로 정렬하면 복합 인덱스가 필요해서, 작가 티켓을 모두 받아 여기서 정렬한다.
        query["where"] = {"fieldFilter": {"field": {"fieldPath": "photographerUid"}, "op": "EQUAL",
                                          "value": {"stringValue": photographer_uid}}}
    else:
        query["orderBy"] = [{"field": {"fieldPath": "createdAt"}, "direction": "DESCENDING"}]
        query["limit"] = 1
    found = [row["document"] for row in call("POST", f"{API}:runQuery", {"structuredQuery": query}) if "document" in row]
    if not found:
        return None
    newest = max(found, key=lambda document: document["fields"].get("createdAt", {}).get("timestampValue", ""))
    return newest["name"].rsplit("/", 1)[1]


def documents(path):
    return call("GET", f"{API}/{path}?pageSize=300").get("documents", [])


def time_of(fields, key):
    value = fields.get(key, {}).get("timestampValue")
    return datetime.fromisoformat(value.replace("Z", "+00:00")) if value else None


def text_of(fields, key):
    return fields.get(key, {}).get("stringValue")


def clock(value):
    return value.astimezone().strftime("%H:%M:%S") if value else "-"


def gap(start, end):
    if not start or not end:
        return ""
    seconds = (end - start).total_seconds()
    if abs(seconds) < 120:
        return f"{seconds:+.1f}초"
    return f"{seconds / 60:+.1f}분" if abs(seconds) < 7200 else f"{seconds / 3600:+.1f}시간"


def with_gap(start, end):
    return f"{clock(end)}({gap(start, end)})" if gap(start, end) else clock(end)


def summary(label, values):
    if not values:
        print(f"  {label}: 없음")
        return
    print(f"  {label}: 중앙값 {statistics.median(values):.1f}초, 최대 {max(values):.1f}초 ({len(values)}장)")


ticket_id = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__)
if ticket_id == "latest":
    ticket_id = latest_ticket(sys.argv[2] if len(sys.argv) > 2 else None) or sys.exit("티켓이 없습니다")
ticket = call("GET", f"{API}/tickets/{ticket_id}").get("fields", {})
customer, photographer = text_of(ticket, "customerUid"), text_of(ticket, "photographerUid")
created = time_of(ticket, "createdAt")
started = [time_of(ticket, key) for key in ("customerStartedAt", "photographerStartedAt")]
shooting = max(started) if all(started) else None

print(f"티켓 {ticket_id} (작가 {text_of(ticket, 'photographerDisplayName')}, 시각은 한국 시각)")
print(f"  확정            {clock(created)}")
print(f"  작가 앱 받음    {clock(time_of(ticket, 'photographerAckAt'))}  {gap(created, time_of(ticket, 'photographerAckAt'))}")
print(f"  고객 시작       {clock(started[0])}")
print(f"  작가 시작       {clock(started[1])}")
print(f"  촬영 시작       {clock(shooting)}  확정부터 {gap(created, shooting) or '-'}")
print(f"  종료            {clock(time_of(ticket, 'endedAt'))}")
if time_of(ticket, "cancelledAt"):
    print(f"  취소            {clock(time_of(ticket, 'cancelledAt'))}  ({text_of(ticket, 'cancelledBy') or '?'})")

messages = sorted((time_of(m["fields"], "sentAt"), text_of(m["fields"], "senderUid")) for m in documents(f"tickets/{ticket_id}/messages"))
if messages:
    by_customer = sum(1 for _, sender in messages if sender == customer)
    print(f"채팅 {len(messages)}개(고객 {by_customer}, 작가 {len(messages) - by_customer}): 처음 {clock(messages[0][0])}, 마지막 {clock(messages[-1][0])}")
else:
    print("채팅 없음")

for document in documents(f"tickets/{ticket_id}/locations"):
    uid = document["name"].rsplit("/", 1)[1]
    role = "고객" if uid == customer else "작가" if uid == photographer else "?"
    print(f"위치 {role}: 마지막 갱신 {clock(time_of(document['fields'], 'updatedAt'))}")

photos = documents(f"tickets/{ticket_id}/photos")
print(f"사진 {len(photos)}장: 파일  촬영  미리보기(촬영부터)  찜  구매  고화질본(구매부터)  고객 저장(구매부터)")
shot_to_preview, purchase_to_fullres, purchase_to_delivery = [], [], []
clock_mismatch = 0
rows = []
for document in photos:
    fields = document["fields"]
    times = {key: time_of(fields, key) for key in
             ("capturedAt", "previewUploadedAt", "favoritedAt", "purchasedAt", "fullresUploadedAt", "deliveredAt")}
    rows.append((times["capturedAt"] or times["previewUploadedAt"], document["name"].rsplit("/", 1)[1], times))
for _, name, times in sorted(rows, key=lambda row: (row[0] is None, row[0] or 0, row[1])):
    captured, preview, purchased = times["capturedAt"], times["previewUploadedAt"], times["purchasedAt"]
    fullres, delivered = times["fullresUploadedAt"], times["deliveredAt"]
    if captured and preview:
        seconds = (preview - captured).total_seconds()
        # 카메라 시계가 크게 틀렸거나 예전에 찍은 사진을 보낸 경우는 요약에서 뺀다.
        if 0 <= seconds <= 3600:
            shot_to_preview.append(seconds)
        else:
            clock_mismatch += 1
    fullres_note = ""
    if purchased and fullres:
        if fullres <= purchased:
            fullres_note = "(미리 올라감)"
        else:
            fullres_note = f"({gap(purchased, fullres)})"
            purchase_to_fullres.append((fullres - purchased).total_seconds())
    if purchased and delivered:
        purchase_to_delivery.append((delivered - purchased).total_seconds())
    print(f"  {name}  {clock(captured)}  {with_gap(captured, preview)}  {clock(times['favoritedAt'])}"
          f"  {clock(purchased)}  {clock(fullres)}{fullres_note}  {with_gap(purchased, delivered)}")

print("요약")
summary("촬영 → 미리보기(카메라 시계 기준)", shot_to_preview)
if clock_mismatch:
    print(f"    {clock_mismatch}장은 뺐다: 촬영 시각이 미리보기보다 늦거나 1시간 넘게 이르다(카메라 시계 확인).")
summary("구매 → 고객 사진 앱 저장", purchase_to_delivery)
summary("구매 때 고화질본이 없던 사진의 구매 → 고화질본 저장", purchase_to_fullres)
