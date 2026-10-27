"""sbsn-dev의 보존 정책을 건다. 둘 다 처음 한 번만 실행하면 된다.

1. Storage 수명 주기(storage.lifecycle.json): 미리보기(previews/*.jpg)와 고화질본(fullres/*.heic)은 30일 뒤 지운다.
   서울 버킷은 무료 할당이 없어 지우지 않으면 티켓마다 수백 MB가 매달 쌓인다. 구매한 고화질본도 지워지므로
   고객 앱은 받자마자 사진 앱에 저장한다. 원본(originals/)은 확장자가 달라 이 규칙에 걸리지 않는다(원본 전달은 2차).
2. Firestore TTL: 작가 공개 상태(photographerPresence)의 expiresAt이 지나면 문서를 지운다(보통 24시간 안).
   작가 앱을 지운 작가처럼 다시 갱신되지 않는 문서가 고객 지도 쿼리에 쌓이지 않게 한다. 작가 앱은 발행할 때마다 24시간 뒤로 민다.

이 맥의 `gcloud storage` 명령은 Python ssl 오류로 크래시하므로 REST API로 건다.

사용(저장소 루트에서, 토큰은 출력하지 않는다):
  python3 -I firebase/scripts/set_retention_dev.py "$(gcloud auth application-default print-access-token)"
"""
import json
import os
import sys
import urllib.error
import urllib.request

PROJECT = "sbsn-dev"
BUCKET = f"{PROJECT}.firebasestorage.app"
TOKEN = sys.argv[1]
HEADERS = {"Authorization": f"Bearer {TOKEN}", "x-goog-user-project": PROJECT, "Content-Type": "application/json"}
RULES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "storage.lifecycle.json")


def call(method, url, body=None):
    request = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, method=method, headers=HEADERS)
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        sys.exit(f"HTTP {error.code}: {error.read().decode()[:300]}")


with open(RULES, encoding="utf-8") as file:
    lifecycle = json.load(file)
result = call("PATCH", f"https://storage.googleapis.com/storage/v1/b/{BUCKET}?fields=lifecycle", {"lifecycle": lifecycle})
print(f"버킷 {BUCKET} 수명 주기: {json.dumps(result.get('lifecycle'), ensure_ascii=False)}")

field = f"projects/{PROJECT}/databases/(default)/collectionGroups/photographerPresence/fields/expiresAt"
operation = call("PATCH", f"https://firestore.googleapis.com/v1/{field}?updateMask=ttlConfig", {"ttlConfig": {}})
print(f"photographerPresence.expiresAt TTL 요청: {operation.get('name', operation)}")
print("TTL은 켜지는 데 몇 분 걸린다. 확인: GET", f"https://firestore.googleapis.com/v1/{field}")
