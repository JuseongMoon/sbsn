"""sbsn-dev에서 고객 쪽 동작을 관리자 권한으로 흉내 내고, 구매부터 고화질본이 올라가기까지 걸린 시간을 정리한다.

작가 앱만 자동으로 시험할 때 쓴다. 고객 앱 없이 시험 티켓을 만들고(create-ticket), 찜(favoritedAt)과 구매(purchasedAt)를
사진 문서에 기록한다. 보안 규칙상 작가 앱은 찜·구매를 쓸 수 없고 읽기만 한다. 시각은 Firestore 서버 시각으로 남긴다.
실증 중 고객 앱에서 잘못 누른 구매도 clear로 지운다(앱에서는 구매를 되돌릴 수 없다).

사용(저장소 루트에서, 토큰은 출력하지 않는다):
  export SBSN_ADMIN_TOKEN="$(gcloud auth application-default print-access-token)"
  python3 -I firebase/scripts/simulate_demand_dev.py create-ticket <작가 uid> [고객 uid]
    → 둘 다 시작한(촬영 중) 시험 티켓을 만들고 ID를 출력한다. 작가 앱을 -SBSNTicketID <ID>로 실행한다.
  python3 -I firebase/scripts/simulate_demand_dev.py latest
  python3 -I firebase/scripts/simulate_demand_dev.py favorite <티켓 ID> DSC00001.JPG [...]
  python3 -I firebase/scripts/simulate_demand_dev.py purchase <티켓 ID> DSC00002.JPG [...]
  python3 -I firebase/scripts/simulate_demand_dev.py clear <티켓 ID> DSC00001.JPG [...]
  python3 -I firebase/scripts/simulate_demand_dev.py report <티켓 ID>
"""
import json
import os
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


def latest_ticket():
    rows = call("POST", f"{API}:runQuery", {"structuredQuery": {
        "from": [{"collectionId": "tickets"}],
        "orderBy": [{"field": {"fieldPath": "createdAt"}, "direction": "DESCENDING"}],
        "limit": 1,
    }})
    return rows[0]["document"]["name"].rsplit("/", 1)[1] if rows and "document" in rows[0] else None


def create_ticket(photographer_uid, customer_uid):
    # 작가 단독 시험용. 고객 확정 트랜잭션과 작가 presence 잠금은 거치지 않으므로 매칭 알림 함수도 고객 uid가 있을 때만 돈다.
    ticket = f"TEST-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    fields = {"photographerUid": {"stringValue": photographer_uid}, "customerUid": {"stringValue": customer_uid},
              "photographerDisplayName": {"stringValue": "시험 작가"}}
    writes = [{"update": {"name": f"{ROOT}/tickets/{ticket}", "fields": fields},
               "updateTransforms": [{"fieldPath": key, "setToServerValue": "REQUEST_TIME"}
                                    for key in ("createdAt", "customerStartedAt", "photographerStartedAt", "photographerAckAt")],
               "currentDocument": {"exists": False}}]
    call("POST", f"{API}:commit", {"writes": writes})
    print(ticket)


def mark(ticket, files, field):
    # 문서가 있을 때만(작가 앱이 미리보기를 올린 사진만) 서버 시각을 기록한다.
    writes = [{
        "transform": {"document": f"{ROOT}/tickets/{ticket}/photos/{name}",
                      "fieldTransforms": [{"fieldPath": field, "setToServerValue": "REQUEST_TIME"}]},
        "currentDocument": {"exists": True},
    } for name in files]
    result = call("POST", f"{API}:commit", {"writes": writes})
    print(f"{field} 기록: {', '.join(files)} ({result.get('commitTime', '?')})")


def clear(ticket, files):
    writes = [{
        "update": {"name": f"{ROOT}/tickets/{ticket}/photos/{name}", "fields": {}},
        "updateMask": {"fieldPaths": ["favoritedAt", "purchasedAt"]},
        "currentDocument": {"exists": True},
    } for name in files]
    call("POST", f"{API}:commit", {"writes": writes})
    print(f"찜·구매 지움: {', '.join(files)}")


def parse(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")) if value else None


def report(ticket):
    documents = call("GET", f"{API}/tickets/{ticket}/photos?pageSize=300").get("documents", [])
    print(f"티켓 {ticket}: 사진 {len(documents)}장 (시각은 한국 시각, 괄호는 구매·찜에서 고화질본 저장까지)")
    for document in sorted(documents, key=lambda d: d["name"]):
        fields = document["fields"]
        times = {key: parse(fields.get(key, {}).get("timestampValue")) for key in
                 ["previewUploadedAt", "favoritedAt", "purchasedAt", "fullresUploadedAt", "originalUploadedAt"]}

        def short(key):
            value = times[key]
            return value.astimezone().strftime("%H:%M:%S") if value else "-"

        def after(start_key):
            start, end = times[start_key], times["fullresUploadedAt"]
            if not start or not end:
                return ""
            seconds = (end - start).total_seconds()
            return " (이미 올라가 있음)" if seconds <= 0 else f" (+{seconds:.0f}초)"

        name = document["name"].rsplit("/", 1)[1]
        print(f"  {name}  미리보기 {short('previewUploadedAt')}  찜 {short('favoritedAt')}{after('favoritedAt')}"
              f"  구매 {short('purchasedAt')}{after('purchasedAt')}  고화질 {short('fullresUploadedAt')}  원본 {short('originalUploadedAt')}")


command = sys.argv[1]
if command == "create-ticket":
    create_ticket(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "test-customer")
elif command == "latest":
    print(latest_ticket())
elif command in ("favorite", "purchase"):
    mark(sys.argv[2], sys.argv[3:], "favoritedAt" if command == "favorite" else "purchasedAt")
elif command == "clear":
    clear(sys.argv[2], sys.argv[3:])
elif command == "report":
    report(sys.argv[2])
else:
    sys.exit(__doc__)
