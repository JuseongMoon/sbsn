# 실시간 FTP 전달 보관 기록(D039)

카메라가 촬영하는 동안 작가 폰으로 사진을 FTP로 보내고, 작가 앱이 받는 즉시 미리보기를 올리던 흐름이다. 2026-10-19부터 실증했고, 2026-11-21 사용자 결정 D036·D039로 작가 선별 업로드(`docs/design/curated-upload.md`)로 바꾸면서 두 앱에서 걷어냈다.

- **보관 태그**: `archive/live-ftp-v1`. 걷어내기 직전 커밋이다. 이 태그에서 FTP 흐름이 끝까지 돈다.
- **바꾼 이유**: 첫 카메라 연결(핫스팟·FTP 설정)이 작가에게 너무 복잡했다. FTP가 없는 카메라는 쓸 수 없었다. 작가가 고르고 보정하면 품질이 오른다. 원래 사업 기획(PROV-04)의 선별 갤러리와도 같다.

## 지운 것과 진입점(iOS)

| 위치 | 파일·심볼 | 하던 일 |
|---|---|---|
| `Packages/SBSNKit/Sources/SBSNCameraTransfer/` | `FTPServer.swift`, `FTPSession.swift` | `Network.framework`으로 만든 FTP 서버(포트 2121, 고정 계정, 패시브 모드). 받는 중 파일은 `.<이름>.part`로 두고, 다 받으면 이름을 바꾼다. 접속·로그인·수신 사건을 알린다 |
| `Packages/SBSNKit/Tests/SBSNCameraTransferTests/` | `FTPServerTests.swift` | FTP 명령·패시브 전송·재접속 시험 |
| `Packages/SBSNKit/Sources/SBSNCore/` | `DeliveryPlanner.swift`(+ `Tests/SBSNCoreTests/DeliveryPlannerTests.swift`) | 큰 파일 업로드 순서: 구매 → 찜 → 구매 원본(와이파이) → 미리 올리기(마지막 수신 뒤 N분) |
| `Packages/SBSNKit/Sources/SBSNBackend/TicketPhotoUploader.swift` | `uploadOriginal`, 원본 MIME 판별 | 구매한 사진의 카메라 원본(`originals/`) 업로드 |
| `sbsnPhotographer/CameraTransferTest/` | `CameraTransferTestModel.swift`(1,073줄), `CameraTransferTestView.swift`, `ShootingModeView.swift` | 티켓 하나의 수신·전달 엔진, 촬영 화면(카메라 연결 상태·핫스팟 주소·측정), 촬영 모드(화면 잠금 막기·근접 센서) |
| `sbsnPhotographer/PhotographerSession.swift` | `startDelivery`, `handleRemoteNotification`의 구매 분기, `waitForRestoration`, `watchDeliveryUntilDone`, 생명주기 관찰(`suspendForBackground`·`resumeFromBackground`) | 촬영 시작 때 FTP를 열고, 구매 알림으로 깨어나 그 한 장을 올리고, 백그라운드로 갈 때 서버를 닫고 다시 열었다 |
| `sbsnPhotographer/PhotographerTicketView.swift` | shooting·ended 분기의 `CameraTransferTestView` | 촬영 화면 |
| `sbsnPhotographer/Tabs/PhotographerTabs.swift` | 개발 메뉴 "카메라 전송 측정" | 측정 화면 |
| `sbsn.xcodeproj` | 작가 앱 `INFOPLIST_KEY_NSLocalNetworkUsageDescription` | 로컬 네트워크 권한 문구 |
| `sbsnUITests/CycleDriverUITests.swift` | FTP로 사진을 보내는 단계 | 실기기 한 사이클 드라이버(맥에서 `curl -T`로 작가 앱 FTP에 전송) |

남긴 것: `PhotoPreviewRenderer`(미리보기·고화질본), `TicketPhotoUploader`의 미리보기·고화질본 업로드, 작가 위치·매칭·채팅·시작·종료, `DeviceConditionLog`.

## 실측 기록 위치

- `docs/roadmap.md` "실증 결과": 2026-10-27 실기기 한 사이클, 2026-10-28 작가 숨김·시스템 종료 뒤 복원·알림 배너, 리허설 전 개발, 교차 시험, JPEG 최종본 확인. 실측값(LTE 업로드 3~4Mbps, 고화질본 17~23초, 백그라운드 12분 뒤 수신 소켓 회수)도 여기에 있다.
- `docs/field-test.md`: 카메라 FTP 설정(P3·P5), 실내 리허설·현장 순서. 걷어낸 뒤 선별 흐름으로 바꿀 때 이 문서를 가리킨다.
- `docs/research/camera-wireless-transfer.md`, `camera-direct-connection.md`, `camera-wireless-transfer-android.md`: 카메라 기종별 무선 전송 조사
- 작가 앱 티켓 폴더 `session-log.txt`·`received.csv`·`uploads.csv`: 기기마다 남은 FTP·업로드 기록(저장소 밖)

## 다시 살리는 방법

1. 필요한 파일을 보관 태그에서 꺼낸다.
   ```sh
   git checkout archive/live-ftp-v1 -- \
     Packages/SBSNKit/Sources/SBSNCameraTransfer/FTPServer.swift \
     Packages/SBSNKit/Sources/SBSNCameraTransfer/FTPSession.swift \
     Packages/SBSNKit/Tests/SBSNCameraTransferTests/FTPServerTests.swift \
     Packages/SBSNKit/Sources/SBSNCore/DeliveryPlanner.swift \
     Packages/SBSNKit/Tests/SBSNCoreTests/DeliveryPlannerTests.swift \
     sbsnPhotographer/CameraTransferTest
   ```
2. 같이 되돌릴 것
   - 작가 앱 로컬 네트워크 권한 문구(`INFOPLIST_KEY_NSLocalNetworkUsageDescription`)
   - `PhotographerSession`의 전달 엔진 연결: 태그의 `startDelivery`·구매 알림 분기·생명주기 관찰을 참고한다
   - `TicketPhotoUploader.uploadOriginal`
3. 백엔드
   - 걷어낸 뒤의 규칙은 `deliveryMode: "curatedV1"`만 받는다. 실시간 흐름을 다시 쓰려면 웹 세션과 새 전달 모드를 합의해야 한다(예: 촬영 중 공개, 원본 쓰기 허용).
   - 옛 분기는 웹 저장소 `firebase/` 기록에 있다.
4. 지금 엔진과 다른 점
   - 선별 흐름은 사진 ID(`^p[a-z0-9]{12}$`)와 표시용 `fileName`을 나눈다.
   - 옛 흐름은 카메라 파일 이름이 곧 문서 ID였다.
   - 되살릴 때 ID 발급을 맞춘다.
