# 작가 선별 업로드 — iOS 설계(D036·D037·D038)

- 작성: `sbsn_ios`, 2026-11-21. 상태: **설계 보고(구현 전)**. 총괄이 웹 세션 설계와 합쳐 공통 명세로 만들고, 사용자가 승인한 뒤 구현한다.
- 결정
  - **D036:** 촬영 중 실시간 FTP 전달 대신 작가가 촬영 뒤 사진을 골라 올리고 공개한다. 목표는 종료 뒤 5~15분 안 공개. (FTP를 숨기던 처음 방침은 D039로 바뀌었다.)
  - **D037:** 고화질본 메타데이터를 전부 유지한다(GPS·일련번호·소유자·MakerNote·IPTC·XMP 포함). 회전·색 공간·크기만 출력값으로 고친다. 미리보기는 지금처럼 메타데이터가 없다.
  - **D038:** 백엔드 계약을 따른다. 웹 저장소 `firebase/docs/photo-curated-delivery-design.md`.
  - **D039:** 실시간 FTP는 숨기지 않고 두 앱에서 걷어낸다. 지우기 직전 커밋에 태그 `archive/live-ftp-v1`을 달고, `docs/archive/live-ftp.md`에 다시 살리는 방법을 적는다.
  - **D040:** ① 끝난 촬영을 고객 내 사진 탭이 따로 기억한다(1차). ② 작가는 공개 전에도 다음 매칭을 받는다. 작가 잠금은 촬영 종료 때 풀린다. ③ 입력은 JPEG·HEIC/HEIF만 받고 RAW는 막는다.
  - 공통 명세: 총괄 `Docs/PRODUCT_SPEC.md` "선별 전달 공통 명세". 이 문서는 iOS 동작 정본이다.
- 근거로 읽은 코드
  - 작가 앱: `PhotographerSession.swift`, `CameraTransferTestModel.swift`, `PhotographerTicketView.swift`
  - 공용 패키지: `TicketPhotoUploader.swift`, `PhotoPreviewRenderer.swift`, `DeliveryPlanner.swift`, `Photo.swift`, `Ticket.swift`, `TicketService.swift`
  - 고객 앱: `CustomerTicketView.swift`, `TicketBackgroundWork.swift`, `TicketPhotoCatalog.swift`, `TicketPhotoDownloader.swift`, `CustomerPush.swift`
  - 웹 저장소(읽기만): `firestore.rules`, `storage.rules`, `storage.lifecycle.json`
- Apple 문서로 확인한 것
  - `PHPickerFilter`는 종류(사진·라이브 포토·스크린숏 등)로만 거르고 **날짜로는 거르지 못한다.**
  - `PhotosPickerItem.itemIdentifier`는 선택기를 `photoLibrary:`와 함께 만들 때만 값이 있다.
  - `PHAsset` 조회는 사진 보관함 권한이 필요하다.
  - `.current` 표현은 가능하면 변환하지 않은 현재 표현을 준다.
  - 새 OS에는 `PHPickerConfiguration.metadataOptions`(기본값 없음, `removeLocation`을 고르면 위치를 뗀다)가 있다. 배포 대상인 iOS 17에서는 없다.
- 맥에서 한 ImageIO 실험(2026-11-21): 4.2절. 스크립트와 결과 파일은 임시 폴더 `scratchpad/meta/`(`forge.py`, `exp.swift`, `inspect.py`)에 있다.

## 1. 한눈에 보기

| 단계 | 작가 앱 | 고객 앱 | 서버(D038) |
|---|---|---|---|
| 매칭 | 기존 | 확정할 때 티켓에 `deliveryMode: "curatedV1"`를 쓴다 | 신규 티켓은 선별 모드 강제(전환 뒤) |
| 촬영(10분) | 타이머·채팅·"촬영 종료". FTP·핫스팟 없음 | "작가가 촬영 중" + 10분 표시 | 기존 |
| 옮기기·보정 | 작가가 앱 밖에서(소니 앱·카드 리더·라이트룸·사진 앱) | "작가가 사진을 고르는 중" | — |
| 고르기 | 선택기로 추가 → **고르는 즉시** 검사·렌더·업로드(미리보기·고화질본 병렬) | 같음 | 작가만 사진 초안 문서·객체를 만든다(만들기만, 덮어쓰기·삭제 불가) |
| 공개(1회) | 5~8장, 화면 순서대로 `publishGallery(ticketId, photoIds)` | 공개 알림 → 갤러리 | `galleryPublishedAt`, `galleryPhotoIds`, 고객 알림 |
| 찜·구매 | 구매 알림(`curatedPhotoPurchased`)만 받는다. 올릴 것 없음 | 찜·구매 → 즉시 내려받기·사진 앱 저장(기존) | 기한 = 공개 + 168시간(서버가 강제) |
| 마무리 | 공개하고 업로드가 끝나면 그 티켓 끝. 공개 전에도 다음 매칭 가능(D040) | 내 사진 탭에 남음, 기한 표시 | 30일 뒤 객체 삭제(기존 정책) |

가장 큰 단순화: **공개 전에 고른 사진의 고화질본까지 다 올린다**(서버도 공개할 때 두 객체가 있는지 확인한다). 그러면 구매는 언제나 바로 내려받기가 되고, 작가 앱은 공개 뒤 꺼져도 된다. 지금 구조에서 가장 까다로운 부분들이 기본 흐름에서 빠진다.
- 구매 알림으로 백그라운드에서 깨워 올리기
- 미리 올리기 시간
- 원본 나중 전달
- 앱을 쓸어 올려 끈 뒤 구매분을 올리는 복원

## 2. 작가 앱

### 2.1 화면 흐름

```
[만나기(기존)] ──둘 다 시작──▶ [촬영 중]
                               ┌───────────────────────────┐
                               │ 촬영 중 · 고객 하린        │
                               │        07:42               │  둘 다 시작한 시각부터 10분(서버 시각)
                               │ ▓▓▓▓▓▓▓▓░░░░               │
                               │ 10분이 지나면 알려 드려요  │  햅틱·문구, 자동 종료 없음
                               │ [채팅]          [촬영 종료]│
                               └───────────────────────────┘
                                         │ 촬영 종료(확인)
                                         ▼
┌──────────────────────────────────────────┐
│ 사진 고르기 · 고객 하린                    │
│ 촬영 14:02~14:12 · 종료 3분 지남           │
│ ① 카메라 사진을 폰으로 옮기세요 [방법 ▸]   │  P7 카메라 가이드 자리
│ ② 고객에게 보일 사진 5~8장을 고르세요      │
│ [사진 앱에서 추가]   [파일에서 추가]       │
│                                            │
│ 고른 사진 6장 · 순서대로 보입니다(끌어서 이동)│
│ ┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐       │
│ │1 ✓ ││2 ✓ ││3 ⟳ ││4 ⟳ ││5 ! ││6 ✓ │       │  ✓ 올라감  ⟳ 올리는 중  ! 실패(눌러서 다시)
│ └─✕──┘└─✕──┘└─✕──┘└─✕──┘└─✕──┘└─✕──┘       │  ✕ 빼기(공개 전만)
│ ⚠ 5번: 이 촬영 시간대 밖에서 찍은 사진     │  경고만
│                                            │
│ ⓘ 올린 사진의 메타데이터(촬영 위치, 카메라·│  D037 고지(정책 세션 최소 고지안, 동의 체크 없음)
│   렌즈 일련번호, 소유자 이름, 저작권 표시  │
│   등)는 구매한 고객에게 그대로 전달됩니다. │
│   빼고 싶은 항목은 편집 앱에서 내보낼 때   │
│   지워 주세요.                             │
│                                            │
│ [   고객에게 공개 (6장)   ]                │  다 올라갔을 때
│ [ 다 올라가면 공개 (4/6) ]                 │  올리는 중일 때 = 공개 예약
│ 고화질 4/6 · 약 1분 남음                   │
└──────────────────────────────────────────┘
                                         │ 공개(1회, 이후 목록·순서 고정)
                                         ▼
┌──────────────────────────────────────────┐
│ 공개함 6장 · 14:19 · 구매 기한 11/28 14:19 │
│ 1 ♥찜   2 구매·전달 완료   3 —   …         │
│ [완료 — 새 촬영 받기]                      │
└──────────────────────────────────────────┘
```

- 촬영 화면은 지금처럼 루트에 고정한다. 연장(+5분)은 범위 밖이다(P6 예시로 남김).
- "사진 고르기"는 종료 뒤에 연다. 서버도 종료된 티켓만 공개를 받는다.
- 공개 고지 문구는 총괄이 보낸 문장을 그대로 쓴다(근거 `Docs/policy/00_DECISIONS_NEEDED.md` U11).

### 2.2 사진 선택기

- **기본은 SwiftUI `PhotosPicker`**다. 앱 밖 프로세스에서 돌아 권한 창이 없다.
  - 설정: `matching: .all(of: [.images, .not(.screenshots)])`, `preferredItemEncoding: .current`(변환 없이 현재 표현, 편집했으면 편집본), `photoLibrary: .shared()`
  - `photoLibrary`는 `itemIdentifier`를 받으려고 넘긴다. 같은 사진을 두 번 고르지 않게 막는 데 쓴다. 식별자를 받는 데는 권한이 필요 없고 `PHAsset`을 조회할 때만 필요한데, 조회는 하지 않는다.
  - `maxSelectionCount`는 `8 - 이미 고른 장수`다. 선택기는 "추가"에만 쓰고, 고른 목록·빼기·순서는 우리 화면이 맡는다.
- **티켓 시간대 사진 먼저 보여 주기**는 선택기로 할 수 없다(날짜 필터 없음). 대신 아래처럼 한다.
  1. 선택기는 날짜순이라 방금 찍은 사진이 가장 최근 쪽에 모인다(카메라 시계가 맞을 때).
  2. 고른 파일의 EXIF `DateTimeOriginal`이 `[촬영 시작 - 10분, 지금]` 밖이면 **경고만** 한다.
  - 날짜로 거른 화면을 직접 만들려면 사진 보관함 권한이 필요하다. 작가 개인 보관함 전체를 읽게 되므로 1차에서는 하지 않는다.
- **권한 없이 촬영 시각 얻기**: `PHAsset.creationDate` 대신 파일 안의 EXIF를 ImageIO로 읽는다. 지금 FTP 경로의 `captureDate(from:)`와 같은 방법이다. EXIF가 없으면 시각 없이 진행하고 경고도 생략한다.
- **보조 경로 `fileImporter`(파일 앱)**: 카드 리더 SD 카드(DCIM)에서 사진 보관함을 거치지 않고 고른다. 권한 창이 없다. 파일 바이트가 그대로 오므로 4.3절의 GPS 대안도 된다. 중복은 크기 + 앞 1MB 해시로 막는다.
- **고른 사진에 GPS·XMP가 남는지(D037 보충 1)는 맥에서 확인할 수 없어 실기기 시험으로 정한다**(4.3절).

### 2.3 고른 파일 처리

1. **가져오기**: `loadTransferable`로 파일 표현을 받는다. 형식은 JPEG → HEIC → HEIF 순으로 명시해서 요청한다(`.image` 하나로 받지 않는다). 그러면 RAW+JPEG 묶음에서는 JPEG가 온다. RAW 표현만 있으면 막는다(5번). 임시 파일을 티켓 폴더 `Tickets/<티켓>/originals/<photoId>.<확장자>`로 복사한다. 지금 FTP 수신 폴더와 같은 구조라 복원 스캔을 옮겨 쓸 수 있다. 진행은 장마다 보인다.
2. **검사**: 디코드 없이 `CGImageSource` 속성만 읽는다.
   - 형식: ImageIO가 읽으면 받는다.
   - **해상도**: 긴 변이 4,000px 미만이면 막는다. 안내는 "긴 변 4,000px 이상만 올릴 수 있습니다(이 사진 3,024px). 잘라 내지 않은 원본 크기로 다시 내보내 주세요."이다.
     - 회전과 상관없이 `max(가로, 세로)`로 잰다.
     - 1,200만 화소 아이폰(4032)은 통과하고, 라이트룸 내보내기 기본값인 긴 변 2048은 막힌다.
   - 촬영 시각과 시간대 경고, 중복
3. **사진 ID(D038)**
   - 파일(정확히는 파일 내용)마다 새로 발급한다.
   - 재시도할 때는 같은 ID를 쓴다. 작가가 다시 보정해서 고른 파일은 새 ID다.
   - 형식 제안: `p` + 영숫자 12자(무작위), 예 `p7k2m9q4x1abc`. 점이 없어 Storage 이름이 `<photoId>.jpg`로 정확히 맞는다.
   - 원래 파일 이름은 문서의 표시용 필드에 둔다(허용 필드는 6절에서 확인).
4. **렌더**(고르는 즉시, 1장씩 차례로)
   - 미리보기: `PhotoPreviewRenderer.renderJPEG`. 긴 변 1024, 워터마크, **메타데이터 없음**(변경 없음).
   - 고화질본: `renderFullResolutionJPEG`. sRGB 8비트 JPEG이고 6,000만 화소를 넘으면 긴 변 8192(D013)다. **메타데이터는 4절 방식으로 전부 옮긴다(D037).**
   - 렌더는 앱이 앞에 있을 때 끝낸다. 백그라운드로 가면 `beginBackgroundTask`로 지금 장만 마친다.
   - **50 MiB 확인**: 고화질본 파일 전체(메타데이터 포함)가 50 MiB 이상이면 품질 0.80, 0.75로 한 번씩 다시 인코딩한다. 그래도 넘으면 "이 사진은 50MB를 넘어 올릴 수 없습니다. 해상도를 낮춰 다시 내보내 주세요."로 막는다. 상한이 8192라 실제로는 드물다.
5. **형식(D040 ③)**
   - **JPEG·HEIC/HEIF만 받는다.** 고객 최종본은 언제나 우리가 만든 sRGB 8비트 JPEG다.
   - RAW는 막는다. 안내는 "RAW 사진은 올릴 수 없습니다. JPEG로 내보내 주세요."이다. `fileImporter`도 같은 형식만 허용한다.
   - HDR HEIF는 iOS 18 이상에서 SDR로 톤 매핑된다. iOS 17에서는 경고만 한다.
   - 라이브 포토는 정지 사진만 받는다.

### 2.4 업로드(D038)

- 재사용: `TicketPhotoUploader.uploadPreview`·`uploadFullResolution`(객체 메타데이터의 참여자 uid 포함, 사진 문서 기록)
- 한 사진의 **미리보기와 고화질본을 병렬로** 올린다. 사진 사이는 고른 순서대로다. **원본은 올리지 않는다**(선별 티켓은 `originals/` 쓰기가 거부된다).
- 전송 방식: 고화질본은 `putFile`(iOS 백그라운드 전송)로 보낸다. 작가가 라이트룸으로 돌아가 다음 사진을 보정하는 동안에도 이어 가야 한다. 미리보기는 기존 규칙(`transportForNewUpload`)을 따른다.
- **만들기만 허용**되는 객체 다루기
  - 재시도하기 전에 `getMetadata`로 객체가 있는지 본다. 있으면(앞선 시도가 사실 성공한 경우) 문서만 채운다. 기존 `fullResolutionExists`·`recordFullResolution`을 미리보기에도 같은 방식으로 넓힌다.
  - 한쪽만 올라갔으면 나머지만 올린다.
  - 앱을 다시 켜서 렌더를 다시 하면 바이트가 달라질 수 있다. 이미 올라간 객체가 있으면 그대로 쓴다(같은 원본에서 만든 것이다).
- 진행 표시는 장마다 대기·렌더·올리는 중·완료·실패, 합계는 "고화질 4/6 · 약 1분 남음"이다.
- 실패와 재시도: 기존 규칙을 옮긴다(5초에서 30초까지 백오프, 인터넷이 돌아오거나 앱이 앞으로 오면 다시). 칸을 누르면 바로 다시 한다. 계속 실패하는 사진은 빼고 다른 사진을 고를 수 있다.
- 앱이 뒤로 가거나 꺼질 때
  - 렌더가 끝난 장의 `putFile`은 이어진다.
  - 다시 켜면 `originals/` 스캔과 서버 사진 문서로 복원한다(기존 `restore` 방식).
  - 고른 순서와 공개 예약은 티켓 폴더의 `selection.json`에 저장한다.
  - 22일이 넘은 객체는 서버가 공개를 막으므로 새 ID로 다시 올린다. 오래된 초안을 복원할 때만 해당된다.
- 예상 시간(LTE 3~4Mbps 실측 기준)
  - 고화질본은 장당 17~23초다. 메타데이터를 다 넣으면 수십~수백 KB 늘어난다.
  - 6장이면 약 2분이다. 고르는 동안 앞 장이 올라가므로, 마지막 장을 고른 뒤 공개까지 1분 안쪽으로 본다(실측 필요).

### 2.5 공개(D038: 티켓당 1회)

- 5~8장이어야 한다. 서버가 강제하고, 앱도 버튼을 막고 "5장 이상 골라 주세요"라고 안내한다. 목표 장수 6은 안내만 한다.
- 순서는 화면 순서다. 기본은 촬영 시각순이고 끌어서 바꾼다. `publishGallery(ticketId, photoIds)`가 이 순서를 고정한다.
- "고객에게 공개"는 고른 사진이 **모두 미리보기와 고화질본까지 올라간 뒤**에 켜진다. 올리는 중이면 "다 올라가면 공개"(공개 예약)로 바뀐다.
  - 앱이 앞에 있으면 마지막 업로드가 끝나는 즉시 호출한다.
  - 뒤에 있으면 백그라운드 전송 완료로 깨어날 때 호출한다. 실패하면 다음에 앞으로 올 때 호출한다.
- 같은 목록의 재호출은 기존 결과가 돌아오므로 그냥 다시 부른다. 다른 목록으로 충돌하면 티켓을 다시 읽어 서버의 공개 목록을 보여 준다.
- **공개한 뒤에는 추가·빼기·순서 변경을 하지 않는다**(1차). 늦게 고른 사진의 빈도는 실기기 시험에서 본다.
- 마무리: 공개하고 업로드가 끝나면 그 티켓의 공개 대기가 끝나고 로컬 복사본을 지운다. 사진은 작가 보관함이나 SD 카드에 남아 있다.
- 작가가 공개하지 않으면 종료 30분 뒤 로컬 알림으로 다시 알린다(티켓마다). 고객 안내는 3절에 있다.
- 구매 알림 `curatedPhotoPurchased`(`ticketId`, `photoId`, `eventId`)
  - 누르면 그 티켓의 공개 화면에서 해당 사진으로 간다. 업로드 작업은 하지 않는다.
  - `eventId`는 최근 200개를 `UserDefaults`에 두고 한 번만 처리한다.

### 2.6 엔진 구조와 바뀌는 파일

**새 엔진 `CuratedDeliveryModel`(가칭) 하나로 간다(D039).** FTP 엔진(`CameraTransferTestModel`, 1,073줄)은 지우므로 엔진 선택 분기와 공통 프로토콜은 두지 않는다. 쓸 조각만 새 엔진으로 옮긴다. 티켓마다 엔진이 하나씩 생기고, 업로드는 앱 전체의 큐 하나로 보낸다(2.7절). `deliveryMode`가 `curatedV1`이 아닌 티켓(전환 전 기존 티켓)은 "이전 방식 촬영은 이 버전에서 이어 갈 수 없습니다"라고 안내하고 종료·취소만 할 수 있게 한다.

| 구분 | 파일 | 내용 |
|---|---|---|
| 새로 | `sbsnPhotographer/Curation/CuratedDeliveryModel.swift` | 가져오기·검사·렌더·병렬 업로드·만들기 전용 재시도·공개(예약)·복원·구매 표시 |
| 새로 | `sbsnPhotographer/Curation/PhotoSelectionView.swift` | 고르기·순서·공개 화면(P8 실제화), 메타데이터 고지 |
| 새로 | `sbsnPhotographer/Curation/ShootingTimerView.swift` | 촬영 중 10분 타이머(P6 실제화) |
| 새로 | `sbsnPhotographer/Curation/PickedPhotoFile.swift` | `Transferable`(파일 표현) |
| 새로 | `SBSNCore/PhotoCuration.swift` | 장수 5~8, 긴 변 4000, 시간대, 구매 기한(공개 + 168시간) 판단(순수 함수, 단위 테스트) |
| 새로 | `SBSNCameraTransfer/JPEGMetadataTransplant.swift` | 원본 메타데이터 세그먼트 이식과 고칠 값 수정(4.1절) |
| 바뀜 | `PhotoPreviewRenderer.swift` | 고화질본의 허용 목록(`deliverableTIFFKeys`·`deliverableExifKeys`·`deliverableMetadata`)을 없애고 이식으로 바꾼다. `inspect(url)`(크기·촬영 시각·형식·HDR)를 더한다 |
| 옮김 | `CameraTransferTestModel`의 `captureDate(from:)`·재시도 백오프·`withBackgroundTime`·`transportForNewUpload`·`restore`의 폴더 스캔 | 새 엔진으로 옮기고 원래 파일은 지운다 |
| 추가 | `SBSNBackend`: `TicketGallery.publish(ticketId:photoIds:)` | callable 호출. **`FirebaseFunctions` 제품을 패키지 의존성에 더한다** |
| 추가 | `TicketRecord.deliveryMode`·`galleryPublishedAt`·`galleryPhotoIds`, `FirestoreCodec` | 새 필드 읽기 |
| 추가 | `PhotographerPush`: `.curatedPurchase(ticketID:photoID:eventID:)` | 새 알림 종류 |
| 바뀜 | `PhotographerSession.swift` | 진행 중 티켓(1개)과 공개 대기 티켓(여럿) 분리(2.7절), shooting에서 FTP 없음, 촬영 시작 때 위치 추적을 끔, 구매 깨우기·복원 대기 경로 삭제 |
| 바뀜 | `PhotographerTicketView.swift` | shooting → 타이머, ended → 그 티켓의 고르기·공개 화면(공개 대기 목록으로 넘김) |
| 새로 | 촬영 탭 홈 "공개 대기" 카드, 내역 탭 "공개한 촬영"(기한 7일 동안) | 2.7절 |
| 바뀜 | `PhotographerFeatures.swift`·`Samples/` | P6·P8을 예시 목록에서 빼고 실제 화면으로 바꾼다. P8 예시의 AI 후보·검토 배지는 버린다 |
| 시험 | 단위 테스트, `CycleDriverUITests`, 스크래치패드 `drive.sh` | 선택기는 다른 프로세스라 UI 테스트로 누르기 어렵다. 선별 시험은 개발 메뉴 "시험 사진 가져오기"(앱 번들·Documents)로 넣는다 |

### 2.7 여러 공개 대기 티켓(D040 ②)

- **지금 구조**
  - `PhotographerSession`은 티켓 하나(`ticket`·`delivery`·저장값 `SBSNActiveTicketID`)만 든다.
  - `canGoAvailable`은 `ticket == nil`일 때만 참이다. 종료된 티켓은 전달이 끝날 때까지 붙어 있다(`releaseIfDelivered`).
  - 고객 앱의 `TicketWorkspaceStore`도 티켓 하나만 든다(3절).
- **바꾸는 구조**
  - `ticket` = **진행 중 티켓**(매칭~촬영, 최대 1개, 작가 잠금과 짝)이다. 종료되면 공개 대기 목록으로 옮기고 `ticket`을 비운다. 그러면 바로 "촬영 가능"을 다시 켤 수 있다.
    - 종료 때 잠금을 풀고 "촬영 가능"을 끄는 지금 코드는 그대로 둔다(서버도 종료 때 잠금을 푼다). 다음 촬영은 작가가 홈에서 직접 켠다.
  - `galleries: [티켓 ID: CuratedDeliveryModel]` = 공개 대기·업로드 중 티켓들이다. ID 목록은 `UserDefaults`(`SBSNPendingGalleryTicketIDs`)에, 고른 순서·공개 예약은 티켓 폴더 `selection.json`에 둔다.
  - 앱을 켤 때 진행 중 티켓을 복원(기존)하고, 공개 대기 티켓마다 티켓 문서를 한 번 읽는다(공개 여부·`galleryPhotoIds`). 그다음 폴더 스캔과 서버 사진 문서로 엔진을 되살린다.
  - **업로드 큐는 앱 전체에 하나**다(티켓끼리 대역을 다투지 않게).
    - 순서: 공개를 예약한 티켓 → 지금 화면에 열린 티켓 → 나머지. 같은 티켓 안에서는 고른 순서다.
    - 새 촬영 중에도 이어 간다. 만나기 위치 공유는 작은 쓰기라 영향이 적다.
  - 알림 이동: `curatedPhotoPurchased`와 지연 로컬 알림은 그 티켓 ID의 공개 화면을 연다. 진행 중 티켓이 아니어도 된다.
  - 지연 알림: 티켓마다 종료 30분 뒤에 걸고, 공개하면 취소한다.
- **화면**
  - 촬영 탭 홈 위에 "공개 대기 n건" 카드를 둔다. 카드에는 고객 이름, 종료 시각, 상태("고른 사진 3/6", "공개 예약 · 올리는 중")가 보인다. 누르면 그 티켓의 고르기 화면이 열린다.
  - 진행 중 티켓이 촬영 중이면 카드를 접어 둔다. 업로드는 계속된다.
  - 내역 탭에는 "공개한 촬영"을 구매 기한(7일) 동안 남긴다. 사진별 찜·구매·전달을 보여 주는 읽기 전용 화면이다(P9·P10 예시 일부의 실제화). 구매 알림을 누르면 여기로 온다.
- **범위**
  - `PhotographerSession` 분리·저장·복원·알림 이동: 중간 규모 수정
  - 업로드 큐(`GalleryUploadQueue`)와 티켓별 엔진
  - 홈 카드, 내역 탭 목록, 지연 알림
  - 시험: 공개 대기 2건과 새 촬영을 동시에 진행하고 앱을 다시 켜 복원
- **위험**
  - 작가가 오래된 공개 대기를 잊을 수 있다 → 지연 알림과 홈 카드로 알린다. 22일이 넘으면 다시 올린다.
  - 공개 대기가 쌓이면 기기 공간이 는다(티켓당 원본 복사 8장 + 렌더 결과, 수백 MB) → 공개가 끝나면 바로 지운다.

## 3. 고객 앱

```
[촬영 중]                         [종료, 공개 전]                    [공개 뒤]
┌──────────────────────┐   ┌──────────────────────────┐   ┌──────────────────────────┐
│ 작가 하린이 촬영 중    │   │ 작가가 사진을 고르는 중   │   │ 사진 6장 · 구매 기한      │
│       07:42           │   │ 보통 5~15분 걸립니다.     │   │ 11월 28일 14:19까지       │
│ ▓▓▓▓▓▓▓▓░░░░          │   │ 공개되면 알림으로 알려    │   │ ┌──┐┌──┐┌──┐ 작가가 정한 순서│
│ 사진은 촬영이 끝나면   │   │ 드립니다. 종료 6분 지남   │   │ │♥ ││  ││✓ │ 찜·구매·저장 │
│ 작가가 골라서 보내요   │   │ [채팅]                    │   │ └──┘└──┘└──┘             │
│ [채팅]                │   │ (30분 넘으면) 늦어지고    │   │ 산 사진은 사진 앱에 자동  │
└──────────────────────┘   │ 있어요 · 채팅 안내        │   │ 저장됩니다                │
                            └──────────────────────────┘   └──────────────────────────┘
```

- **티켓 생성**: `TicketService.confirm` 트랜잭션에 `deliveryMode: "curatedV1"`를 더한다. 전환 뒤에는 규칙이 강제하므로 업데이트하지 않은 고객 앱은 확정이 거부된다.
- **화면 갈래**(`CustomerTicketView`, 선별 티켓)
  - shooting: 촬영 중 화면(타이머는 작가 앱과 같은 기준)
  - ended + `galleryPublishedAt` 없음: 고르는 중 화면
  - 공개 뒤: 갤러리
  - 기존 티켓(`deliveryMode` 없음)은 지금 화면 그대로다.
- **갤러리 읽기(D038)**: 컬렉션 목록을 조회할 수 없다. 티켓 문서의 `galleryPhotoIds` 순서대로 사진 문서마다 실시간 리스너를 붙인다(5~8개). `TicketPhotoCatalog`에 `galleryPhotos(ticketId:ids:)`를 더한다. 기존 티켓은 지금 컬렉션 리스너를 쓴다.
- 내려받기는 지금처럼 인증된 SDK 읽기(`data(maxSize:)`, 파일 쓰기)만 쓴다. 다운로드 URL·토큰은 받지도 저장하지도 않는다(`TicketPhotoDownloader` 확인).
- **공개 알림**: `type: "ticket"`, `change: "galleryPublished"`, `ticketId`, `eventId`
  - `CustomerPush.Notification.ticket`에 `change`를 더한다.
  - 탭하면 그 티켓 갤러리로 간다. 공개 여부는 언제나 티켓 문서로 다시 확인한다.
  - 같은 `eventId`는 한 번만 처리한다. 앱이 앞에 있으면 배너를 띄우지 않는다(기존 `.ticket`과 같다).
- **"고르는 중"에 고객이 떠나는 경우**
  - 지금 종료 화면의 "새 촬영 찾기"는 티켓을 잊는다(`forgetLocalTicket`). 공개 전에 누르면 사진을 못 찾게 된다.
  - 그래서 끝난 선별 티켓은 **내 사진 탭이 따로 기억한다**(D040 ①, 1차). 지금 `TicketWorkspaceStore`는 진행 중 티켓 하나만 들므로, 갤러리는 따로 둔다.
    - `GalleryStore`: 티켓 ID 목록을 최근 순으로 저장한다(`SBSNGalleryTicketIDs`, 기한 뒤 30일까지).
    - 목록 화면은 티켓 문서만 듣는다(고르는 중 / 공개됨·기한 / 기한 지남). 갤러리를 열면 사진 문서 리스너와 `PhotoDeliveryManager`를 붙인다.
    - 사진 앱 저장이 중간에 끊기면 다음에 열 때 이어 간다.
  - 촬영 탭의 "새 촬영 찾기"는 진행 중 티켓만 잊고, 갤러리 목록에서는 지우지 않는다. 내 사진 탭은 지난 촬영 목록 → 갤러리 구조가 된다(C10 앨범 예시의 일부를 실제로 만든다).
- **구매 기한과 보관**
  - 기한은 `galleryPublishedAt + 168시간`(서버가 강제)이다. 갤러리 위에 날짜로 보이고, 하루 남으면 강조한다.
  - 기한이 지나면 구매 버튼을 끈다. 경계에서 늦게 도착한 요청이 거부되면 "기한이 지났습니다"를 보인다.
  - 객체는 만든 뒤 30일에 삭제된다(웹 저장소 `storage.lifecycle.json`). 산 사진은 구매 즉시 사진 앱에 자동 저장되므로(기존) 30일 삭제는 다시 받기에만 영향을 준다. 오래된 구매는 객체가 실제로 있는지 보고 저장 가능 여부를 표시한다.
- 찜·구매·내려받기·저장(`PhotoDeliveryManager`)은 그대로다. 공개된 사진은 언제나 고화질본이 있어 구매 즉시 내려받는다.
- **사진 앱 저장 뒤에도 메타데이터가 남는지(D037 보충)**: 4.4절의 실기기 확인 항목이다.

## 4. 고화질본 메타데이터 전부 유지(D037)

### 4.1 방식: 원본 메타데이터 세그먼트를 그대로 옮기고 고칠 값만 제자리에서 바꾼다(JPEG 입력)

1. 픽셀은 지금처럼 만든다. 빠른 경로는 디코드 그대로, 그 밖에는 회전·sRGB·톤 매핑·8192 축소다. ImageIO로 **메타데이터 없이** JPEG을 인코딩한다(sRGB ICC는 인코더가 넣는다).
2. 원본 JPEG에서 아래 세그먼트를 **바이트 그대로** 꺼내 새 JPEG의 SOI 뒤에 넣는다.
   - APP1 Exif(TIFF 블록 통째로: IFD0·Exif·GPS·Interop·MakerNote)
   - APP1 XMP와 확장 XMP(`http://ns.adobe.com/xmp/extension/`)
   - APP13 Photoshop/IPTC
   - COM
   - 원본의 ICC(APP2)·MPF(APP2, 원본 파일 기준 오프셋)·JFIF·Adobe(APP14)는 옮기지 않는다. 앞의 둘은 출력과 맞지 않고, 뒤의 둘은 인코더 것을 쓴다.
3. **고칠 값만 제자리에서 바꾼다.** TIFF 블록은 길이를 바꾸지 않는다. MakerNote 오프셋이 TIFF 머리 기준이라 블록을 그대로 두어야 깨지지 않는다.
   - IFD0 `Orientation` → 1
   - Exif `PixelXDimension`·`PixelYDimension` → 출력 크기(SHORT/LONG 칸 그대로)
   - Exif `ColorSpace` → 1. Interop `R03`(Adobe RGB) → `R98`
   - 회전했거나 줄였으면 IFD1(썸네일) 연결을 끊는다. 원본 방향의 썸네일이 남아 엉뚱하게 보이지 않게 하려는 것이다.
   - XMP 텍스트의 `tiff:Orientation`, `exif:PixelXDimension`·`PixelYDimension`, `tiff:ImageWidth`·`ImageLength`, `photoshop:ICCProfile`을 출력값으로 바꾼다.
     - 숫자 자릿수가 바뀔 수 있다(10240 → 8192). XMP는 텍스트라 같은 길이를 지킬 필요가 없고 세그먼트 길이를 다시 계산한다. 같은 길이 제약은 TIFF 블록에만 둔다.
   - **원본에 없는 태그는 새로 넣지 않는다**(공통 명세). 원본에 `ColorSpace`·`PixelXDimension`이 없으면 그대로 없다.
4. 일련번호(본체·렌즈)·소유자 이름·MakerNote도 **전부 유지**한다(D037 확정). 빼는 선택지는 두지 않는다.
- **HEIC·RAW 입력**: 세그먼트 구조가 달라 `CGImageDestinationAddImageAndMetadata`(원본 `CGImageMetadata` + 고칠 값)를 쓴다. EXIF·GPS·일련번호·소유자·XMP(편집 정보 포함)는 남는다. **MakerNote는 남지 않을 수 있다**(4.2 실험의 C·D2).
- 안드로이드와 맞추는 방법: 같은 방식을 강제하지 않고 **결과 계약**으로 맞춘다. 같은 시험 원본(아래 `forge.py`와 같은 구조)을 넣었을 때 남아야 할 항목과 바뀌어야 할 값이 같은지 본다.

### 4.2 실험 결과(맥 ImageIO, 2026-11-21)

시험 원본: a7C II 픽셀(7008×4672)에 EXIF를 붙였다. EXIF에는 기종·렌즈, `DateTimeOriginal`, GPS, 본체·렌즈 일련번호, 소유자, Artist·Copyright, 가짜 MakerNote 1,036바이트를 넣었다. 여기에 XMP(`dc:creator`, 라이트룸 `crs:Exposure2012`, 임의 이름공간)와 IPTC(By-line)도 붙였다. 가로(Orientation 1)와 세로(Orientation 6) 두 장이다.

| 방식 | EXIF·GPS·일련번호·소유자 | MakerNote | XMP(편집 정보·임의 이름공간) | IPTC | 고칠 값 |
|---|---|---|---|---|---|
| A. `AddImageFromSource` + 고칠 값(빠른 경로) | 남음 | **사라짐** | **사라짐** | 다시 만들어짐 | 맞음 |
| B. 렌더 + `AddImage`(원본 속성 사전 전체 + 고칠 값) | 남음 | 사라짐 | `dc:creator`만 | 사라짐 | 맞음(세로 4672×7008, Orientation 1) |
| C. 렌더 + `AddImageAndMetadata`(원본 `CGImageMetadata` + 고칠 값) | 남음 | 사라짐 | **남음** | XMP로만 | 맞음 |
| D1·D2. HEIC 원본 → JPEG(B·C 방식) | 남음 | 사라짐 | `dc:creator`만(시험용 HEIC를 만들 때 이미 빠짐) | — | 맞음 |
| E. 원본에서 꺼낸 CGImage + 속성 없음 | **전부 사라짐** | — | — | — | — |

- **"덮어쓰기 문제를 거꾸로 이용"은 안 된다.** A는 EXIF는 옮기지만 XMP와 MakerNote를 버린다. E처럼 원본과 이어진 이미지를 넘겨도 메타데이터가 따라오지 않는다. 전에 본 현상은 넘긴 속성으로 IPTC 날짜를 다시 만든 것뿐이었다.
- ImageIO의 어떤 방식으로도 MakerNote가 남지 않았다. 그래서 JPEG 입력은 4.1의 세그먼트 이식으로 한다.
- 가짜 MakerNote라 ImageIO가 알아보지 못해 버렸을 가능성이 있다. **실제 a7C II JPEG로 다시 확인한다.** 이식 방식은 바이트를 그대로 옮기므로 결과가 같다.
- 세로 사진은 회전을 픽셀에 반영해야 하므로 빠른 경로를 탈 수 없다. 스냅 촬영은 세로 사진이 많아 이식 방식이 꼭 필요하다.

### 4.3 고른 사진에 GPS·XMP가 남는지(실기기 확인, D037 보충 1)

- 맥에서는 선택기 동작을 재현할 수 없다. 작가 폰에서 아래를 비교한다. 같은 사진을 네 경로로 받아 4.2의 검사 스크립트로 GPS·XMP·MakerNote·일련번호를 본다.
  - `.current`
  - `.compatible`
  - `PHPickerResult.itemProvider` 직접(`loadFileRepresentation`)
  - `fileImporter`
- 사진은 두 종류로 고른다.
  - (a) 소니 앱으로 옮긴 GPS 있는 JPEG(카메라 위치 연동)
  - (b) 라이트룸에서 메타데이터 "전체"로 내보낸 JPEG(XMP 편집 정보)
- 새 OS의 `metadataOptions` 기본값이 "아무것도 빼지 않음"이라 선택기도 기본으로는 위치를 남길 것으로 보지만, 확인 전이다.
- GPS가 빠질 때의 선택지(권한 창이 적은 순서)
  1. **`fileImporter`**: 권한 창이 없다. SD 카드에서 바로 고르거나, 사진 앱의 "수정되지 않은 원본 내보내기"로 파일 앱에 둔 파일을 고른다. 바이트가 그대로 오므로 GPS가 남는다(실기기 확인).
  2. 사진 보관함 **제한된 접근**: 권한 창이 한 번 뜬다. 작가가 고른 사진만 앱이 볼 수 있고, `PHImageManager.requestImageDataAndOrientation`으로 원본 바이트를 받는다. 선택기와 권한 화면이 두 번 나오는 불편이 있다.
  3. 전체 접근: 권장하지 않는다. 작가 개인 보관함 전체를 읽게 된다.
- 권장: 실기기에서 선택기가 GPS를 남기면 그대로 간다. 빠지면 1을 기본 경로로 올리고 2는 설정 화면에서 켜는 선택지로 둔다(D028 편의 우선).

### 4.3.1 위치가 지워진 채 들어온 사진 안내(I008, 2026-11-22, Android 먼저 c68c342)

- 판별(`SBSNCameraTransfer.PhotoLocation`, Android `PhotoLocation`과 같음): 가져올 때 Exif의 GPS IFD를 본다.
  - GPS IFD가 있는데 위도·경도 중 하나라도 "유리수 3개가 아님(형식·개수가 다름)" 또는 "분모가 0"이면 `removed`
  - 위도·경도가 온전하면 `present`, GPS IFD가 없거나 좌표 항목이 없거나 Exif를 읽을 수 없으면 `absent`(안내 없음)
  - JPEG는 이미지 데이터(SOS) 앞까지만 읽어 Exif APP1을 찾는다. HEIC는 `meta` → `iinf`(종류 `Exif`) → `iloc`(파일 오프셋 방식)로 Exif 아이템만 읽는다.
  - ImageIO의 GPS 사전은 쓰지 않는다. 형식이 깨진 항목을 버리거나 0/0을 0으로 읽어 "없음"과 "지워짐"을 가릴 수 없다.
- 안내: 고르기 화면 메타데이터 고지 아래에 "위치 정보가 지워진 채 들어온 사진 n장: 고객 사진에 촬영 위치가 남지 않습니다(나머지 정보는 그대로)."(`gallery.locationRemoved`). Android 뒤 문장("위치 포함"을 고르면 남음)은 넣지 않는다. 권한 창은 없다.
- 기록: 사진마다 `selection.json`의 `locationRemoved`(I008 전 기록에는 없어 `false`로 읽는다), `events.csv`의 `locationRemoved` 행, 세션 로그 `added … location=…`. 고화질본 이식은 그대로다(D037).
- 시험: `PhotoLocationTests` 7개. Android와 같은 사례(0/0과 Ref 0, 실제 좌표 리틀·빅 엔디언, GPS IFD 없음, 좌표 없는 GPS IFD, 읽을 수 없는 Exif, COM이 앞이라 밀린 지움, 경도만 0/0)에 더해 맥 ImageIO로 만든 HEIC·JPEG에서 값만 0으로 지운 파일을 본다.
- **iOS 사진 선택기 실측(iOS 27.0 시뮬레이터, 가짜 좌표 합성 JPEG·HEIC, `.current`)**
  - 선택기 아래 가운데에 "선택된 항목 표시(n개) · 위치가 포함됨"이 있다. 누르면 선택한 사진 화면이 나오고 왼쪽 아래 "옵션"에 "포함: 위치(기본 켬)·캡션(켬)·레퍼런스(끔)"와 "포맷: 자동(기본)·현재·높은 호환성"이 있다.
  - 위치 켬(기본): 받은 파일이 원본과 바이트까지 같다(MD5 같음). 4.3의 "기본으로는 위치를 남길 것"을 시뮬레이터에서 확인했다.
  - 위치 끔: **GPS IFD를 통째로 뺀다**(0으로 채우지 않는다). JPEG Exif APP1이 260 → 146바이트가 됐고, 이미지 데이터·기종·촬영 시각은 같았다. APP13(IPTC)은 54 → 94바이트로 바뀌었다. HEIC도 GPS IFD가 없고 기종·촬영 시각은 남았다.
  - 그래서 iOS 선택기에서 위치를 끈 사진은 판별이 `absent`이고 **안내가 뜨지 않는다**(카메라가 위치를 안 남긴 사진과 파일로 가릴 수 없다). iOS에서 안내가 뜨는 것은 값만 0으로 지운 파일(다른 기기·앱이 지운 파일을 파일 앱으로 가져온 경우 등)뿐이다.
  - 결정(I008 보충, 총괄 2026-11-22): iOS 선택기 경로에는 고정 안내를 더하지 않는다. 위치 옵션 기본이 켬이고 기존 메타데이터 고지가 촬영 위치 전달을 알리므로 한 줄을 더하면 화면만 번거롭다(D028).
  - 확인 전: 실기기에서도 같은지, 위치를 끄면 선택기가 메타데이터를 다시 쓰면서 MakerNote·XMP·IPTC 등 다른 항목도 바뀌는지(합성 사진에는 MakerNote가 없다). 현장 실증에서 실제 a7C II JPEG로 본다(`docs/field-test.md` 끝난 뒤 5). 시뮬레이터 시험은 `MetadataProbeUITests.testPickerLocationOption`(`TEST_RUNNER_SBSN_PICKER_LOCATION=off`)으로 다시 할 수 있다.

### 4.4 고객 사진 앱 저장 뒤에도 남는지(실기기 확인)

- 지금 저장은 `PHAssetCreationRequest`로 파일 자체를 원본 리소스로 넣는다(`PhotoDeliveryManager.saveToPhotoLibrary`, `shouldMoveFile`). 그래서 원본 바이트가 그대로 보관될 것으로 본다.
- 확인 방법: 저장 뒤 사진 앱 정보 화면에서 위치·기종이 보이는지 본다. 원본 리소스를 꺼내(`PHAssetResourceManager`, 개발 메뉴) 4.2 검사 스크립트로 GPS·XMP·MakerNote·일련번호를 맞춰 본다.
- 사진 앱에서 다시 공유할 때 위치가 빠지는지는 고객 쪽 공유 옵션의 몫이다. 결과만 기록한다.

### 4.4.1 실기기 한 사이클에서 산 사진(2026-11-22, sbsn-dev, 작가 iOS 27.2)

- 합성 시험 사진(4.2와 같은 구조, ICC 없음) 7장을 고르기 화면에 넣어 공개했고, 고객이 3장을 샀다. 가로(회전 1), 세로(회전 6), 세로(회전 8)다. 산 고화질본을 관리자 권한으로 받아 원본과 맞춰 봤다.
  - MakerNote·XMP·IPTC 바이트 해시가 원본과 같았다. GPS는 태그 4개의 값이 같았고, 일련번호·소유자·Artist·Copyright·렌즈도 같았다.
  - 세로 2장은 Orientation 1, 4672×7008로 바뀌었다. 회전을 적용한 원본과 축소본 픽셀 차이는 평균 0.15~0.32/255였다(틀린 짝은 81.6).
  - ExifTool `-validate` 경고는 원본과 같았다(합성 원본에 없는 필수 태그 4개, 가짜 MakerNote minor 1개). 원본에 없는 태그를 더하지 않았다.
- 인코더가 넣는 세그먼트는 회전 여부에 따라 다르다.
  - 회전하지 않은 출력: JFIF(APP0)
  - 회전한 출력: JFIF 대신 애플 전용 APP10 `AROT`(1,774바이트)를 넣는다. 하드웨어 인코더로 보인다(양자화·허프만 표 구성도 다르다). ImageIO는 이것을 게인맵으로 읽지 않는다.
  - 입력에 ICC가 없으면 출력에도 ICC가 없었다(Exif ColorSpace 1). ICC가 있는 실제 카메라 원본은 현장 실증에서 본다.
- 개발 메뉴 저장 시험이 쓰던 정렬 키 `addedDate`는 iOS 27 실기기 Photos가 받지 않고 예외를 던져 앱이 죽었다. 원본 파일 이름으로 찾도록 바꿨다(구매 저장본은 `<사진 ID>.jpg`로 들어간다).

### 4.5 테스트 변경

- 미리보기: `dropsLocationAndCameraMetadata`는 그대로 둔다(미리보기는 계속 메타데이터 없음).
- 고화질본
  - `fullResolutionJPEGBakesRotationKeepsShotDetailsAndDropsPrivateData` → `…KeepsAllMetadata`로 바꾼다. 회전이 픽셀에 반영되고, EXIF·XMP의 Orientation이 1이고, IFD1이 끊겼는지 본다.
  - `plainSRGBJPEGKeepsOriginalResolutionAndDropsPrivateData` → 전부 유지로 바꾼다.
  - `fullResolutionKeepsOnlyAllowListedMetadata` → `fullResolutionKeepsEveryMetadataSegment`로 바꾼다. MakerNote 바이트가 같은지, XMP 임의 이름공간, IPTC, GPS, 일련번호·소유자, 고칠 값을 본다.
  - `allowListMatchesAndroidCount`는 지운다(허용 목록이 없어진다).
  - 새 테스트: Adobe RGB 원본의 Interop `R03` → `R98`, 확장 XMP 이식, 50 MiB 초과 시 품질 단계, HEIC 입력은 C 방식(MakerNote 제외 유지)
- 시험 원본은 테스트 안에서 만든다. `forge.py`와 같은 구조를 Swift 도우미로 옮긴다.

## 5. 실시간 FTP 걷어내기(D039)

- **보관**: 지우기 직전 커밋에 태그 `archive/live-ftp-v1`을 단다(태그 푸시는 D029대로 승인 뒤). `docs/archive/live-ftp.md`에 아래를 적는다.
  - 지운 파일과 진입점
  - 실측 기록 위치: `docs/field-test.md`·`docs/roadmap.md`·`docs/research/camera-*.md`의 해당 절
  - 다시 살리는 방법: `git checkout archive/live-ftp-v1 -- <경로>`, 그리고 함께 되돌릴 설정
- **지우는 것(iOS)**

| 위치 | 대상 |
|---|---|
| `SBSNCameraTransfer` | `FTPServer.swift`, `FTPSession.swift`, 테스트 `FTPServerTests.swift`. `PhotoPreviewRenderer`는 남는다(모듈 이름은 그대로 둔다) |
| `SBSNCore` | `DeliveryPlanner.swift`, 테스트 `DeliveryPlannerTests.swift` |
| `SBSNBackend` | `TicketPhotoUploader.uploadOriginal`, 구매 업로드 알림 `PhotographerPush.purchase`(새 `curatedPurchase`로 바꿈) |
| 작가 앱 | `CameraTransferTest/` 폴더 전체(`CameraTransferTestModel`·`CameraTransferTestView`·`ShootingModeView`) |
| 작가 앱 세션 | 구매 깨우기(`handleWake`), 백그라운드 서버 닫기·다시 열기, 복원 대기(`waitForRestoration`의 구매 경로), 미리 올리기 감시(`watchDeliveryUntilDone`) |
| 작가 앱 설정 | `INFOPLIST_KEY_NSLocalNetworkUsageDescription`(로컬 네트워크 권한 문구). `UIBackgroundModes`의 `location`(만나기)·`remote-notification`(매칭 받음)은 남긴다 |
| 시험 | `CycleDriverUITests`의 FTP 단계와 스크래치패드 `drive.sh`의 FTP 전송 → "시험 사진 가져오기" 개발 메뉴로 바꾼다 |
| 문서 | `docs/roadmap.md`·`docs/field-test.md`의 FTP 절을 선별 흐름으로 바꾸고 보관 문서를 가리킨다 |

- **남기는 것**
  - 로그인, 촬영 가능·위치 발행, 매칭·받음, 만나기 위치·채팅
  - 시작·종료·취소, 알림 등록·탭 이동, 고객 취소 안내
  - 기기 상태 기록(`DeviceConditionLog`): 선별 흐름의 배터리·발열 측정에도 쓴다
- `deliveryMode`가 없는 기존 티켓은 앱이 더 이어 가지 않는다(2.6절 안내). `sbsn-dev`의 옛 티켓 정리는 사용자 승인 뒤에 한다.

## 6. 웹 설계(D038)와 맞춰 본 것

정해진 것(2026-11-21 공통 명세)
1. FTP 비교 → D039로 FTP를 걷어내므로 비교 모드는 두지 않는다.
2. 사진 ID `^p[a-z0-9]{12}$`
3. 초안 필드(웹이 허용 목록으로 확정)
   - `fileName`(원래 파일 이름, 표시용)과 `capturedAt`
   - `previewPath`·`previewByteCount`·`previewUploadedAt`
   - `fullresPath`·`fullresByteCount`·`fullresUploadedAt`
   - 코드 영향: 지금 `PhotoRecord.fileName`은 문서 ID이자 파일 이름이다. 선별 흐름에서는 `id`(= photoId)와 표시용 `fileName`을 나눈다. 고객 앱의 저장 기록·캐시 경로도 photoId를 기준으로 바꾼다.
4. callable `publishGallery`, 리전 `asia-northeast3`. iOS 패키지에 `FirebaseFunctions` 의존성을 더한다.

아직 남은 것
5. 공개 실패 오류 코드: 웹이 확정한다. 앱은 장수·ID 형식, 객체 없음·불일치, 22일 초과, 다른 목록으로 이미 공개됨, 종료 전·취소됨을 나눠 안내한다.
6. 다운로드 토큰: iOS 앱은 다운로드 URL을 부르지 않는다. 업로드 때 토큰이 자동으로 붙는지는 클라이언트가 막을 수 없어 웹이 개발 버킷에서 확인한다.
7. 메타데이터를 다 넣은 크기: 50 MiB 상한 안이다(2.3). 라이트룸 XMP가 크면 확장 XMP가 여러 세그먼트가 되고, 이것도 그대로 옮긴다.

웹 설계와 같게 맞춘 것
8. 공개 1회, 5~8장과 화면 순서 고정
9. 고객은 공개 전 아무것도 못 보고, 공개 뒤 개별 `get`
10. 기한 168시간, 구매 알림은 업로드 요청이 아님
11. 같은 ID 재시도, 만들기만 허용, 원본 제외
12. 작가 잠금은 종료 때 풀림(D040)

## 7. 위험·확인할 것·열린 질문

**실기기에서 확인할 것**
1. 선택기 경로별 GPS·XMP·MakerNote 보존(4.3)
2. 사진 앱에서 편집한 사진이 편집본으로 오는지
3. RAW+JPEG 묶음에서 JPEG가 오는지, RAW 단독은 막히는지
4. iCloud "저장 공간 최적화"로 원본이 기기에 없을 때 받는 시간
5. 실제 a7C II JPEG의 MakerNote가 이식 뒤 바이트 그대로인지
6. 고객 사진 앱 저장 뒤 메타데이터(4.4)
7. 작가가 다른 앱을 쓰는 동안 백그라운드 전송(`putFile`)이 끝까지 가는지, 공개 예약이 깨어남에서 호출되는지
8. 시간 예산 실측: 종료, 파일 업로드 완료, 서버 공개, 푸시 도착 시각을 따로 기록한다(웹 설계 시험 계획과 같다)

**호환성**

9. 전환하면 업데이트 전 고객 앱(iOS TestFlight 0.1, 안드로이드)은 확정이 거부되고, 선별 티켓 사진을 볼 수 없다. 웹 설계대로 모든 내부 기기를 업데이트한 뒤 한꺼번에 전환한다.

**정해진 것(2026-11-21)**

10. FTP는 걷어낸다(D039).
11. 끝난 촬영은 고객 내 사진 탭이 따로 기억한다(D040 ①, 1차).
12. 작가는 공개 전에도 다음 매칭을 받는다(D040 ②, 2.7절).
13. 입력은 JPEG·HEIC/HEIF만 받고 RAW는 막는다(D040 ③).

**남은 질문**

14. 작가가 끝내 공개하지 않을 때: 지금은 고객 지연 안내(30분)와 작가 지연 알림만 한다. 운영 알림을 더할지 정해야 한다.

**한계**

15. 선택기에 날짜 필터가 없어, 권한 없이 "티켓 시간대 사진만 보기"를 할 수 없다. 경고로 대신한다.

## 8. P8 "사진 검수·공개" 예시를 실제 기능으로 바꾸는 범위

| 예시 화면에 있는 것 | 실제로 | 비고 |
|---|---|---|
| 사진 그리드, 공개 여부 표시 | 만든다 | 고른 사진·상태 칸·순서 번호 |
| "공개 n장(최소 5 · 목표 6 · 최대 8)" | 만든다 | 5 미만·8 초과는 막는다 |
| "고객에게 공개" | 만든다 | 1회, 공개 예약 포함 |
| 제외·복원 토글 | 공개 전 "빼기"만 | 공개 뒤에는 고정 |
| 필터(전체·추천·검토 필요·제외), AI 후보 배지 | 만들지 않는다 | 작가가 골라서 올린다. AI 추천은 범위 밖 |
| "지금은 받은 사진이 바로 고객에게 보입니다" | 지운다 | 선별 흐름에서는 사실이 아니다 |
| (예시에 없음) 추가(선택기·파일), 순서 바꾸기, 해상도·시간대 검사, 업로드 진행·재시도, 메타데이터 고지, 공개 뒤 찜·구매·전달 표시, 완료 | 더한다 | |

P6 "10분 타이머"도 실제 촬영 화면으로 옮긴다. 연장은 범위 밖이다.
