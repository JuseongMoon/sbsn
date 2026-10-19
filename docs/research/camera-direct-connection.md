# 카메라 ↔ 폰 직결 조사: 빠른 연결·재연결, 연결한 채 촬영

- 작성: 2026-10-19, sbsn_research 세션.
- 요청(사용자): "핸드폰과 카메라를 직결해서 초기 연결이나 기존 연결을 빠르게 다시 붙이는 방법이나, 아예 연결한 상태로 촬영을 해서 더 편하거나 빠르게 전송할 수 있는 방법"을 찾는다.
- 전제(결정, 2026-10-19): 초기에는 서버 없이 B안으로 간다. B안은 카메라 → 작가 폰 핫스팟 → 작가 앱 내장 FTP 서버(`SBSNCameraTransfer/FTPServer.swift`) → Firebase Storage 경로다. 이 문서는 그 위에 얹을 직결 방안을 다룬다.
- 함께 볼 문서
  - [camera-wireless-transfer.md](camera-wireless-transfer.md)(이하 "iOS 보고서")
  - [camera-wireless-transfer-android.md](camera-wireless-transfer-android.md)(이하 "Android 보고서")
- 확인 날짜: 출처는 모두 2026-10-19에 확인했다.
- 표시 규칙은 두 보고서와 같다.
  - **[확인됨]**: 1차 출처(제조사 매뉴얼·도움말, Apple·Android 공식 문서, iOS SDK 헤더, AOSP 소스)에서 확인했다.
  - **[일부 확인]**: 2차 출처만 있거나 검색 요약으로만 봤다.
  - **[확인 못 함]**: 찾지 못했다.
  - **(추측)**: 근거에서 추론한 판단이다.
  - ★: 이 문서를 쓰면서 원문을 다시 열어 교차 확인한 출처다.
  - 출처 ID는 10장 목록을 가리킨다.
- 조사 한계
  - 실기 검증은 하지 않았다.
  - 열지 못한 페이지가 있다: Capture One 지원 문서(403), Sony 지역 지원 사이트(403), Canon 커뮤니티(401).
- 이 조사로 기존 문서 두 곳을 정정했다.
  - iPhone 핫스팟 "약 90초 뒤 꺼짐" → Apple 공식 문구는 "트래픽 없는 서드파티 기기를 90초 뒤 끊는다"이다(5-1).
  - Android Wi-Fi Direct 그룹 IP → OEM 설정과 관계없이 기본이 192.168.49.1이다(5-2).

---

## 0. 요약

1. **직결 방식은 세 가지다.**
   - **D1 USB 테더링 FTP**
     - 카메라를 케이블로 폰의 테더링 네트워크에 붙인다. 카메라 FTP가 지금의 앱 FTP 서버로 보내므로 앱 코드는 거의 그대로다(추측).
     - 되는 기종은 둘뿐이다: Sony 신형 10기종 ★DC-S6, ★DC-S8, 그리고 FT-XH를 단 Fujifilm X-H2·X-H2S [확인됨 DC-F1].
   - **D2 USB PTP 수신**
     - 카메라를 사진 장치(PTP)로 붙이고, 앱이 새 사진을 가져온다.
     - FTP가 없는 기종(Canon R8·R50, Fujifilm X-T5·X100VI, Sony a6700)도 대상이 된다.
     - 대신 브랜드마다 새 사진을 알리는 방식이 달라서 따로 구현해야 한다 [확인됨 DC-A2].
   - **D3 무선 재연결 개선**: 케이블 없이 재연결을 빠르게 하는 방법이다.
     - Android는 앱이 만든 Wi-Fi Direct 그룹을 쓴다. SSID·비밀번호를 고정할 수 있고 IP는 192.168.49.1이다 ★DC-A10.
     - iOS는 핫스팟의 90초 규칙에 맞춰 카메라 쪽 재연결 설정과 앱 안내로 다룬다.
2. **유선으로 바꾸면 사라지는 것**
   - 핫스팟 켜기와 검색
   - 트래픽이 없을 때 90초 뒤 끊기는 문제. Apple 문서의 대상은 Wi-Fi 핫스팟이다. USB에도 적용되는지는 확인 못 함.
   - 혼잡한 관광지의 Wi-Fi 간섭. Sony도 혼잡한 곳에서는 유선을 권한다 [확인됨 DC-S12].
3. **유선으로도 안 풀리는 것: iOS 포그라운드**
   - ImageCaptureCore는 앱이 백그라운드로 가면 카메라와의 통신을 멈춘다 ★DC-I3.
   - 다만 세션을 닫지 않으므로 앱으로 돌아오면 이어진다 ★DC-I3.
   - Nikon 공식 앱도 백그라운드에서는 자동 가져오기를 하지 않는다 ★DC-N2.
4. **"찍는 즉시 폰으로 유선 전송"은 이미 하는 앱이 있다.** 플랫폼 차원에서 막혀 있지는 않다.
   - 공식 앱: Nikon NX MobileAir(iOS·Android) ★DC-N2, Sony Transfer & Tagging(USB PC Remote. iOS 지원은 일부 확인) [확인됨 DC-S9]
   - 서드파티: TetherDrop, Evoto, Capture One, Cascable [확인됨 DC-X1, DC-X2, DC-X4, DC-X7]
   - iOS에서도 제조사 전용 PTP 명령을 보낼 수 있다. `requestSendPTPCommand(_:outData:completion:)`가 iOS 13부터 있다 ★DC-I3.
5. **권장(추측, 실증 뒤 확정)**
   - **iOS + Sony 신형**: D1을 "유선 모드"로 먼저 실증한다. 지금 FTP 수신 코드를 그대로 쓴다.
   - **Android**: D3 Wi-Fi Direct 그룹을 기본 무선 방식 후보로 실증 1순위에 둔다. Android 보고서의 A4 위험(핫스팟 IP 무작위)을 직접 푼다.
   - **D2**: FTP가 없는 기종을 받는 경로로 둔다. Nikon(iOS·Android)과 Fujifilm(Android)부터 실증한다.
   - **공통**: 앱이 받은 목록과 카메라의 미전송분을 대조해 놓친 사진을 회수하는 흐름을 둔다.

---

## 1. 직결 방식 세 가지

| 방식 | 연결 | 사진이 오는 길 | 우리 앱 변경 | 장점 | 약점 |
|---|---|---|---|---|---|
| **D1** USB 테더링 FTP | 카메라 USB-C ↔ 폰. 폰이 테더링을 켠다 | 카메라 FTP 자동 전송 → 앱 FTP 서버 | 거의 없음. 카메라에 넣을 서버 주소만 달라진다(추측) | Wi-Fi 간섭과 핫스팟 검색이 없다. 기존 코드를 쓴다 | 지원 기종이 좁다. Sony는 케이블을 빼거나 전원을 끄면 메뉴에서 다시 연결해야 한다 [확인됨 DC-S3] |
| **D2** USB PTP 수신 | 카메라 USB-C ↔ 폰. 카메라는 PTP·MTP·PC Remote 모드 | 앱이 새 사진 알림을 받거나 목록을 폴링해 원본을 내려받는다 | 새 수신 경로. iOS는 ImageCaptureCore, Android는 USB Host | FTP가 없는 기종도 된다. 연결이 끊긴 동안 찍은 사진을 앱이 직접 찾아 회수할 수 있다 | 브랜드별 PTP 구현. Sony는 법인 전용 규격일 수 있다. 권한·전력·케이블 변수가 있다 |
| **D3** 무선 재연결 개선 | Wi-Fi(핫스팟 또는 Wi-Fi Direct 그룹) | B안과 같다 | Android는 그룹 생성 코드. iOS는 안내 화면 | 케이블이 없다 | iOS는 OS 규칙을 바꿀 수 없다. Android 그룹은 실기 미확인 |

---

## 2. 브랜드 × 방식 매트릭스

●: 지원, ◐: 조건부·일부, ○: 미지원, ?: 확인 못 함.

| 기종 | D1 USB 테더링 FTP | D2 USB 수신(공식 앱 선례) | 연결한 채 촬영 | 설정 저장·불러오기 | 재연결·미전송 재개 | Wi-Fi용 QR·NFC |
|---|---|---|---|---|---|---|
| Sony a7C II | ● iPhone·Android ★DC-S1 | ● T&T USB PC Remote 자동 가져오기, 펌웨어 2.00 이상 [확인됨 DC-S6, DC-S9] | ● 저장 위치 3종, 전송 크기 Original/2M [확인됨 DC-S13] | ● 카드에 10개. T&T가 Bluetooth로 서버 설정을 써넣는다 [확인됨 DC-S4, DC-S11] | Wi-Fi는 복구되면 미전송분 자동 전송 [확인됨 DC-S12]. USB 테더링은 수동 재연결 [확인됨 DC-S3] | QR은 MAC 주소용, NFC 없음 [확인됨 DC-S15] |
| Sony a7 IV·a7R V·a1·a1 II·a9 III(+a7 V, a7R VI, a7S III, a7CR) | ● ★DC-S8 | ● T&T(PC Remote 펌웨어 조건 있음) [확인됨 DC-S6] | ◐ a7C II와 같을 것(추측) | ● (a7 IV는 카드 저장 가이드 못 찾음) [확인됨 DC-S18] | a7C II와 같을 것(추측) | ? |
| Sony a6700 | ○ FTP 없음 [확인됨 DC-S19] | ○ T&T 미지원 [확인됨 DC-S6] | ◐ PC Remote 메뉴는 있음 [확인됨 DC-S19] | ○ | — | NFC 없음 |
| Canon R1·R5 II | ○ FTP는 유선 LAN·Wi-Fi만 [확인됨 DC-C1, DC-C2] | ◐ Canon CTP(iOS·Android 유선). 찍는 즉시인지는 확인 못 함 [확인됨 DC-C10] | ◐ Photo Import/Remote Control(PTP) 모드 [확인됨 DC-C3] | ● 카드에 10개, 같은 기종만 [확인됨 DC-C4] | ◐ 실패분 자동 재시도. 전원을 끄면 재시도 안 함 [확인됨 DC-C5] | QR은 MAC 주소용 [확인됨 DC-C10] |
| Canon R6 II | ○ FTP는 Wi-Fi만 [확인됨 DC-C6] | ◐ CTP, Mobile File Transfer(iOS 유선은 R3·R6 II만) [확인됨 DC-C10, DC-C11] | ◐ 같음 | ? | ◐ 연결 기록 10개에서 수동 선택 [확인됨 DC-C7] | QR은 앱 다운로드용 [확인됨 DC-C8] |
| Canon R8·R50 | ○ FTP 없음 [확인됨 DC-C9] | ◐ Camera Connect USB "일부 기종" [일부 확인 DC-C15] | ◐ PTP 모드 있음(R50) [확인됨 DC-C3] | ○ | ◐ 연결 기록에서 재연결 [확인됨 DC-C9] | QR은 앱 다운로드용 |
| Nikon Z8·Z9·Z6III·Zf·Z5II | ○ USB 메뉴는 MTP/PTP, iPhone, USB-LAN(이더넷 어댑터 전용)뿐 [확인됨 DC-N1] | ● NX MobileAir. 찍는 즉시 자동 가져오기, 백그라운드에서는 안 함 ★DC-N2 | ● [Shooting] 우선 설정, 저장 위치 Computer/Computer+Card/Card [확인됨 DC-N3, DC-N4] | ● Copy to/from Card(Z9 C4.00부터 99개). WTU 프로필에는 키·비밀번호가 빠짐 [확인됨 DC-N6, DC-N7] | ● Keep connection이 약 15초마다 재시도. 전원을 껐다 켜면 업로드 재개 [확인됨 DC-N8] | Wi-Fi용 QR 없음(클라우드 주소용) [확인됨 DC-N5] |
| Fujifilm X-H2·X-H2S + FT-XH | ● 폰을 **FT-XH의 USB 단자**에 연결(카메라 단자는 안 됨) [확인됨 DC-F1] | ◐ XApp 2.3.0부터 USB 전송. 대상 기종 지원은 확인 못 함 [일부 확인 DC-F2] | ? CARD READER 모드에서 촬영할 수 있는지 문서 없음 | ◐ 연결 프로필 16슬롯(7~16 사용자용). 카드 저장 없음 [확인됨 DC-F5] | ◐ 전원을 꺼도 전송, 대기열 9999장. 끊긴 뒤 재접속은 문서 없음 [확인됨 DC-F6] | 없음 |
| Fujifilm GFX100 II | ○ [일부 확인 DC-F6] | X-H2와 같음 | X-H2와 같음 | 16슬롯 [확인됨 DC-F5] | X-H2와 같음 | 없음 |
| Fujifilm X-T5·X100VI | — FTP 메뉴 없음 [확인됨 DC-F7] | ◐ USB 연결 시 iOS 사진 앱 / Android Camera Importer [확인됨 DC-F3] | ? | — | Bluetooth 페어링 뒤 앱을 열면 자동 연결 [확인됨 DC-F8] | 없음 |
| Panasonic S5II·GH7 | ◐ GH7은 Frame.io만 폰 USB 테더링. FTP 없음 [확인됨 DC-P1] | ◐ LUMIX Lab 유선(3.0.0은 L10·S9 표기) [일부 확인 DC-P2] | USB Mode PC(Storage)/PC(Tether) [확인됨 DC-P3] | 카드 백업에 네트워크 설정이 들어가는지 불명 | ● Remote Wakeup, Auto Transfer 재개 [확인됨 DC-P5] | ● LUMIX Sync가 카메라 QR 스캔 [확인됨 DC-P4] |
| OM System OM-1 II | ○ | ○ | ○ Storage/MTP 중 촬영 불가(iOS 보고서 OM-4) | ? | 끌 때 공유 표시한 사진은 알림을 탭해야 전송 [확인됨 DC-O2] | ● QR 하나로 Bluetooth·Wi-Fi 정보 전달 [확인됨 DC-O1] |

**정리**
- **D1은 Sony 신형에서만 현실적이다.** Fujifilm은 FT-XH가 있어야 한다.
- **D2 공식 선례가 가장 넓은 것은 Nikon이다.** iOS·Android 모두 "찍는 즉시"가 문서에 있다.
- **Canon은 직결 상태로 카메라 FTP를 쓸 수 없다.** 직결하려면 D2를 써야 하고, R8·R50에는 D2가 사실상 유일한 즉시 전송 후보다.
- **Wi-Fi 접속용 QR은 OM System과 Panasonic(LUMIX Sync)에만 있다.** 둘 다 제조사 앱용이라 우리 앱이 쓸 수는 없다(추측). NFC는 대상 기종 문서에서 찾지 못했다 [일부 확인].

---

## 3. D1: USB 테더링 FTP

### 3-1. Sony

- **메뉴와 폰 설정** ★DC-S1
  - 카메라: MENU → (Network) → [USB-LAN/Tethering] → [Tethering Connection]
  - iPhone: "Enable the internet sharing function under Settings."(개인용 핫스팟)
  - Android(모바일 회선): "Enable USB tethering in the Network/Internet menu under Settings."
  - Android(Wi-Fi 사용, Android 전용): 폰의 Wi-Fi를 켜면 카메라에서 Wi-Fi 설정을 하지 않아도 된다.
- **조건**
  - "We recommend using a smartphone and USB cable that support USB-PD" ★DC-S1
  - T&T 안내는 변환 어댑터 없이 케이블 한 가닥으로 연결하라고 한다 [확인됨 DC-S7].
- **지원 카메라**: ILCE-1M2, 1, 9M3, 7RM6, 7RM5, 7SM3, 7M5, 7M4, 7CR, 7CM2. a6700은 없다 [확인됨 DC-S6].
- **Sony가 검증한 폰**(T&T "Importing via USB tethering" 열) ★DC-S8
  - iPhone: XS, XR, 11 Pro, 12 Pro Max, 13, 13 mini, 14 Pro, 15, 15 Pro, 16, 16 Pro, SE 3세대. iOS 17.5~26.0이고 Lightning 모델도 들어 있다.
  - Samsung: S10+, S21, S22 Ultra, S24, Z Flip5, M23 모두 ✓
  - **Google Pixel 6·6a·7·7 Pro·7a·8 Pro·9는 "–"**(미검증 또는 미지원). Pixel 2·5만 ✓다.
- **폰 앱이 FTP 서버가 되는 구성**
  - T&T가 바로 "USB 테더링 + 앱 내장 FTP 서버" 구조다. 카메라에는 T&T 화면에 표시된 Host Name과 Port를 넣는다 [확인됨 DC-S7].
  - 우리 앱도 같은 방식으로 받을 수 있을 것이다(추측).
  - iPhone은 USB 테더링에서도 폰 주소가 172.20.10.1일 것으로 본다(추측, 실기 확인 필요).
- **재연결 약점**
  - USB 테더링과 유선 LAN은 케이블이 빠지거나 전원을 끄면 [Tethering Connection]을 다시 골라야 한다 [확인됨 DC-S3].
  - 전원을 껐다 켠 뒤 자동으로 재전송하는지는 확인 못 함. 일괄 전송의 "Only Non-transfer"로 미전송분을 보낼 수 있다 [확인됨 DC-S17].
  - [Tethering Connection]을 My Menu에 넣어 조작을 줄일 수 있는지는 실기로 확인한다(추측).

### 3-2. Fujifilm X-H2·X-H2S + FT-XH

- 원문: "Connect to Internet FTP servers via a network connection on your smartphone.", "The camera's USB connector cannot be used for this purpose." [확인됨 DC-F1]
- 위저드: CREATE USING WIZARD > FTP TRANSFER > USB SMARTPHONE TETHERING. 여기서 서버 주소, 포트, PASV, 계정을 넣는다 [확인됨 DC-F1].
- Apple Lightning Camera Adapter와 OTG 케이블은 쓸 수 없다. 폰이 FT-XH에서 전력을 끌어갈 수 있다 [확인됨 DC-F1].
- 서버 주소로 폰 자신의 IP(앱 FTP 서버)를 넣을 수 있는지는 문서에 없다 [확인 못 함].
- FT-XH는 별매 그립형 전송기다. 작가가 이 장비를 갖고 있을 가능성은 낮다(추측).

### 3-3. iOS와 Android에서 달라지는 점

| 항목 | iOS | Android |
|---|---|---|
| 폰 쪽 IP | 172.20.10.1로 추정(추측) | **무작위.** USB 테더링도 핫스팟과 같은 무작위 /24 대역을 쓴다. 같은 부팅 안에서만 재사용한다 ★DC-A10 |
| 케이블을 다시 꽂을 때 | 개인용 핫스팟이 켜져 있으면 다시 붙을 것(추측) | 케이블을 뽑으면 테더링이 꺼지고, 다시 꽂으면 테더링을 다시 켜야 한다는 보고가 있다 [일부 확인 DC-A20] |
| 기기 차이 | Sony가 iOS 17.5 이상 12기종 검증 ★DC-S8 | 삼성은 검증, 최근 Pixel은 "–" ★DC-S8 |
| 앱 백그라운드 | B안과 같은 포그라운드 제약이 남는다(추측) | FGS로 수신 유지(Android 보고서 0장) |

- Android의 USB 테더링 주소는 일반 앱이 고정할 수 없다. 고정 수단(`TetheringRequest`)은 시스템 API다 [일부 확인].
- 그래서 **Android에서는 D1보다 D3 Wi-Fi Direct 그룹이 낫다**(추측).

### 3-4. 판단(추측)

- iOS + Sony 신형 작가에게 D1은 비용이 가장 적은 개선이다. 앱 코드는 거의 그대로이고, 핫스팟 검색과 Wi-Fi 간섭이 없어진다.
- 대가는 둘이다. 카메라와 폰을 케이블로 묶고 다녀야 하고, 카메라를 켤 때마다 메뉴를 한 번 조작해야 한다.
- 실증에서 볼 것: 90초 무트래픽 끊김이 USB 테더링에도 적용되는지, 셀룰러 업로드를 동시에 할 수 있는지, 배터리 소모(7장 1번).

---

## 4. D2: USB PTP 수신

### 4-1. iOS: ImageCaptureCore

- **API**(iOS 27.0 SDK 헤더) ★DC-I3
  - `cameraDevice(_:didAdd:)`, `cameraDevice(_:didReceivePTPEvent:)`: iOS 13 이상
  - `requestSendPTPCommand(_:outData:completion:)`: iOS 13 이상. 제조사 전용 PTP 명령(Canon·Nikon GetEvent 등)을 보낼 수 있다. 셀렉터 방식은 iOS 15.2 이상이다.
  - `requestTakePicture`는 iOS에서 쓸 수 없다. 셔터는 작가가 카메라에서 누르면 되므로 문제가 없다(추측).
- **촬영 중 `didAdd`가 오는가**
  - 헤더 설명은 "objects are added to the device"뿐이다. iOS에서 촬영 중에 받았다는 개발자 증언은 찾지 못했다 [확인 못 함].
  - 서드파티 앱들이 iOS에서 찍는 즉시 유선으로 받고 있으므로 플랫폼 차원에서는 가능하다 [확인됨 DC-X1, DC-X2, DC-X4].
  - 그 앱들이 표준 이벤트를 쓰는지 제조사 명령을 쓰는지는 확인 못 함.
- **권한** [확인됨 DC-I1, DC-I3]
  - 테더링에는 Info.plist의 `NSCameraUsageDescription`이 필요하다.
  - `requestContentsAuthorization`, `requestControlAuthorization`은 iOS 14 이상이다.
  - 알려진 결함이 있다. 해결 여부는 확인 못 함.
    - iOS 18: 팝업 없이 바로 거부 [확인됨 DC-I5]
    - iOS 26.1 베타: 계속 notDetermined [확인됨 DC-I6]
  - Nikon은 "USB 급전을 지원하는 카메라를 연결하면 권한 요청이 반복될 수 있으니 USB 급전을 끄라"고 안내한다 [확인됨 DC-N11].
- **백그라운드** ★DC-I3
  - 앱이 백그라운드로 가면 `deviceBrowserWillSuspendOperations`가 온다.
  - `deviceBrowserDidSuspendOperations`: "All communication with the attached device will remain suspended until the application has entered the foreground. In no way does this suspension modify the state of the connected device, nor does it issue a close session of any kind."
  - 대기 시간 안에 돌아오면 `deviceBrowserDidCancelSuspendOperations`가 온다. 대기 시간 길이는 문서에 없다.
  - 결론: 백그라운드에서는 받지 못한다. 대신 돌아오면 세션이 이어지므로, 그동안 찍은 사진은 카드 목록과 비교해 회수한다(추측).
- **잠금과 유선 액세서리 설정** [확인됨 DC-I7]
  - USB-C iPhone의 "유선 액세서리" 기본값은 "잠금 해제 시 자동 허용"이다. 잠금을 푼 상태에서 꽂아야 한다.
  - 연결한 뒤 화면이 잠겨도 연결은 유지된다. 잠긴 상태에서는 새 액세서리와 통신하지 않는다.
  - Nikon 앱은 화면을 어둡게 하는 앱 안 잠금 기능으로 이 문제를 다룬다 [확인됨 DC-N2].
- **케이블을 다시 꽂을 때**: `ICDeviceBrowser`를 켜 둔 상태면 꽂을 때 `didAdd`(기기), 뽑을 때 `didRemove`가 온다 [확인됨 DC-I3]. 앱을 다시 켤 필요는 없을 것이다(추측).
- **하드웨어**
  - USB 속도
    - iPhone 15 Pro 이후 Pro 모델: USB 3(10Gb/s). 단, USB 3 케이블을 따로 써야 한다 [확인됨 DC-I8].
    - 그 밖의 모델: USB 2 [확인됨 DC-I9].
    - JPEG 몇 MB는 USB 2로도 충분할 것이다(추측).
  - iOS 17을 지원하는 Lightning iPhone(XS~14, SE 2·3세대)은 Lightning to USB 3 Camera Adapter로 연결한다 [확인됨 DC-I10]. Sony는 Lightning 기기를 직결하면 인식하지 않는다고 한다 [확인됨 DC-S10].
  - 전력
    - iPhone 15 이상은 액세서리에 최대 4.5W를 공급한다 [확인됨 DC-I8]. 카메라 쪽 급전을 꺼야 폰 배터리를 지킨다.
    - 설정 이름: Sony [USB Power Supply] Off, Nikon [USB power delivery] Disable, Fujifilm POWER SUPPLY OFF/COMM ON [확인됨 DC-X13, DC-N13, DC-F11].
  - 촬영 중 충전
    - Apple USB-C Digital AV Multiport Adapter는 카메라 연결과 iPhone 충전을 함께 안내한다 [확인됨 DC-I11]. PTP 통신이 그동안 유지되는지는 확인 못 함.

### 4-2. Android: USB Host

- **`MtpDevice.readEvent`는 브랜드 공통 해법이 아니다.**
  - AOSP 구현은 interrupt endpoint로 오는 표준 PTP 이벤트만 읽는다 [확인됨, 소스 DC-A1].
  - 브랜드별 실제 동작은 4-3 표.
- **권한과 자동 실행** [확인됨 DC-A4, 소스 DC-A5~A7]
  - 공식 문서: "If users accept, your application automatically has permission to access the device until the device is disconnected."
  - AOSP 동작
    - 확인 창에서 "항상 사용"을 체크하면 이 앱이 기본 앱으로 저장된다. 다음 연결부터는 창 없이 권한을 주고 앱을 띄운다.
    - 저장 키에 시리얼 번호가 들어가므로 **카메라 한 대마다 한 번씩** 체크해야 한다.
    - 삼성 갤러리 같은 다른 앱도 같은 장치를 받겠다고 하면 앱 선택 창이 뜬다.
  - 선례: Evoto는 "Gallery wants to access your camera"가 뜨면 취소하고 케이블을 다시 꽂으라고 안내한다 [확인됨 DC-X7].
- **백그라운드**
  - `connectedDevice` FGS의 시작 조건 목록에 `UsbManager.requestPermission()`이 명시돼 있다 [확인됨 DC-A8].
  - 화면이 꺼져도 USB 호스트 연결이 유지된다는 직접 근거는 찾지 못했다 [확인 못 함].
  - Nikon NX MobileAir Android는 "all in the background while you shoot"라고 한다 [확인됨 DC-N10].
- **Android 16 고급 보호**를 켜면 잠금 중에 새로 꽂은 USB는 충전만 된다 [일부 확인 DC-A9]. 기본은 꺼져 있다.
- **하드웨어**
  - 카메라 급전 끄기는 iOS와 같다.
  - PD 허브로 충전하면서 쓰는 것은 기종·허브마다 다르다. 충전기를 꽂는 순간 장치가 끊겼다는 보고가 있다 [일부 확인 DC-A21].

### 4-3. 브랜드별 새 사진 알림 방식

근거는 libgphoto2 `camera_wait_for_event` 구현이다 [확인됨, 소스 DC-A2, DC-A3].

| 브랜드 | 새 사진을 알아내는 방식 | 표준 API만으로 되는가 |
|---|---|---|
| Canon EOS | 제조사 명령 GetEvent를 반복 호출(폴링)한다 | 안 될 것(추측). iOS는 `requestSendPTPCommand`, Android는 USB 직접 통신으로 구현한다 |
| Nikon | 제조사 GetEvent 폴링 결과에서 ObjectAdded(0x4002)·ObjectAddedInSDRAM(0xC101)을 처리한다 | 표준 이벤트가 interrupt로도 오는지는 확인 못 함. 공식 앱 선례가 가장 많다 |
| Sony | PC Remote 모드에서 0xd215 속성을 폴링하고, 0xffffc001 핸들로 사진을 가져온다. Sony의 ObjectAdded는 "너무 일찍 올 수 있다"며 일부러 무시한다 | 안 된다. 제조사 확장(Camera Remote Command, 법인 전용 [확인됨 DC-S21])이 필요할 수 있다 |
| Fujifilm | 소스 주석: "camera does not send us ObjectAdded events". 파일 목록을 폴링한다 | 공개 API로 목록을 폴링하면 흉내 낼 수 있을지도 모른다(추측). 연결한 채 촬영이 되는 모드인지는 확인 못 함 |

### 4-4. 선례 앱

| 앱 | 플랫폼 | 유선 즉시 수신 | 근거 |
|---|---|---|---|
| Nikon NX MobileAir(2026-07-09부터 무료) | iOS·Android | ● "Pictures are automatically imported as they are shot". 백그라운드·4GB 초과는 제외. 끊긴 동안 찍은 사진은 다시 연결할 때 OK를 눌러 받는다 | ★DC-N2, DC-N10 |
| Sony Transfer & Tagging | iOS·Android | ● USB PC Remote 자동 가져오기, "You can continue to shoot while importing images". HEIF 불가 | [확인됨 DC-S9]. iOS 지원은 일부 확인 |
| Canon CTP / Mobile File Transfer | iOS·Android | ◐ USB 유선 지원, 받은 뒤 FTP 업로드. 찍는 즉시인지는 확인 못 함 | [확인됨 DC-C10, DC-C11] |
| TetherDrop(2026-07 출시) | iOS 16+ | ● USB-C·PTP/IP·FTP, JPEG. Canon·Sony·Nikon Z·Fujifilm GFX 일부 검증. 앱 복귀 시 재연결, 남은 사진 수신 | [확인됨 DC-X4] |
| Capture One | iPhone·iPad, iOS 17+ | ● 유선·무선 테더링, 550개 이상 기종 | [확인됨 DC-X1]. 브랜드별 유선 목록은 403 |
| Cascable Studio / CascableCore | iOS | ● USB로 PTP 카메라 전 기종 가져오기. Canon·Nikon·Sony는 원격 제어 | [확인됨 DC-X2, DC-X3] |
| Evoto Instant | Android 9+ | ● FTP 무선 + USB 유선. 유선에서 Sony·Fuji는 PC Remote 모드 | [확인됨 DC-X7] |
| Lightroom 모바일 | — | ○ 유선 테더링 미지원 | [일부 확인 DC-X5] |

**Evoto Instant는 우리와 거의 같은 구조다.** 폰 앱이 카메라 FTP와 USB를 둘 다 받는다. 이 앱도 "네트워크를 바꾸면 서버 주소와 포트를 카메라에 다시 넣으라"고 안내한다 [확인됨 DC-X7]. B안의 Android IP 문제가 실제 운영에서도 부담이라는 근거다.

### 4-5. 구현 선택지(추측)

- **iOS**
  - (a) ImageCaptureCore로 직접 구현한다. 표준 `didAdd`를 먼저 시험하고, 안 되는 브랜드는 `requestSendPTPCommand`로 제조사 명령을 보낸다.
  - (b) CascableCore를 쓴다. USB를 지원하지만(visionOS 제외) [확인됨 DC-X3] 가격은 문의해야 한다.
- **Android**
  - (a) USB Host로 PTP를 직접 구현한다(`UsbDeviceConnection`).
  - (b) libgphoto2를 쓴다. LGPL 문제는 Android 보고서 A10과 같다.
- **Sony**
  - D2보다 D1(USB 테더링 FTP)이 훨씬 싸다.
  - D2로 직접 구현하려면 Camera Remote Command를 법인으로 신청해야 할 수 있다. 신청은 하지 않았다(9장).

---

## 5. D3: 빠른 초기 설정과 재연결

### 5-1. iPhone 개인용 핫스팟

- **90초 규칙**(정정): "Third-party devices automatically disconnect after 90 seconds without network traffic." ★DC-I12(Apple Platform Support, 2025-10-22 게시)
  - 핫스팟 자체가 꺼지는 것이 아니다. 트래픽이 없는 카메라의 연결이 끊긴다.
  - 촬영이 뜸한 동안 카메라가 FTP 연결을 닫고 조용히 있으면 90초 뒤 끊길 수 있다(추측).
- **다시 붙을 때** ★DC-I12, [확인됨 DC-I13]
  - "Make sure that Allow Others to Join is on."
  - "Stay on this screen until you connect the other device to the Wi-Fi network."
  - 설정 화면을 떠나면 핫스팟이 검색되지 않는다는 공식 문구는 없다 [확인 못 함]. 실기로 재연결 시간을 잰다.
- **호환성 최대화**: 2.4GHz 연결을 쓰게 한다. 원문은 성능과 보안이 떨어질 수 있다고 적는다 ★DC-I12. 카메라가 5GHz를 쓰지 못할 때 켠다(추측).
- iOS 26 사용 설명서에는 "Allow Others to Join" 대신 "누가 쓸 수 있는지 선택" 문구가 있다 [확인됨 DC-I14]. 실제 화면은 실기로 확인한다.
- **우리 앱이 할 수 있는 것**(추측)
  - 촬영 세션 화면에 "카메라 연결 끊김" 표시를 두고, 끊기면 핫스팟 설정 화면으로 가는 안내를 띄운다.
  - Nikon은 Keep connection을 켜게 안내한다. 카메라가 15초마다 재시도하므로 90초 끊김의 영향이 줄 수 있다 [재시도 간격은 확인됨 DC-N8, 효과는 추측].
  - Sony 안내: iPhone 핫스팟이 다시 붙지 않으면 핫스팟을 껐다 켜고 카메라 전원을 껐다 켠다 [확인됨 DC-S12].

### 5-2. Android: 앱이 만든 Wi-Fi Direct 그룹

- **그룹 오너(GO) IP는 기본으로 192.168.49.1이다** ★DC-A10
  - `PrivateAddressCoordinator` 생성자가 P2P용 주소로 192.168.49.1/24를 미리 넣어 둔다("Reserved static addresses for bluetooth and wifi p2p").
  - `requestStickyDownstreamAddress`는 이 주소가 업스트림 네트워크와 충돌하지 않으면 그대로 준다.
  - 업스트림이 같은 192.168.49.x 대역일 때만 무작위 주소로 바뀐다. 국내 이동통신 대역과 겹칠 가능성은 낮다(추측).
  - android-13 태그에서도 같다 [확인됨, 소스 DC-A11].
  - 실측 정황: NetShare가 192.168.49.1:8282를 고정 안내한다 [일부 확인 DC-A16]. 삼성 실측은 확인 못 함.
- **SSID·비밀번호 고정**: `WifiP2pConfig.Builder`로 정한다(Android 보고서 AP-2). 보안 기본값은 WPA2-Personal, 밴드는 AUTO다 [확인됨, 소스 DC-A15]. 카메라 호환을 위해 2.4GHz로 지정하는 편이 안전하다(추측).
- **그룹 수명** [확인됨, 소스 DC-A14]
  - 앱이 직접 만든 그룹은 마지막 기기가 나가도 지워지지 않는다.
  - 앱 프로세스가 죽으면 그룹도 지워진다. 그래서 FGS가 필수다.
- **카메라 재연결**: SSID·비밀번호가 같으면 카메라가 저장한 AP처럼 다시 붙을 것이다(추측). 그룹을 다시 만들 때 BSSID가 바뀌는지, 카메라가 BSSID를 따지는지는 확인 못 함.
- **이것으로 풀리는 것**(추측)
  - 카메라 FTP 서버 주소를 한 번만 넣으면 된다. Android 보고서 A4가 풀린다.
  - 작가가 시스템 핫스팟을 켜지 않아도 되고, 핫스팟 자동 꺼짐과도 관계없다.
  - 그룹은 인터넷을 공유하지 않으므로 업로드는 셀룰러로 나간다. 테더링 데이터 한도와도 관계없을 것이다.
- **남는 제약**
  - 권한: Android 13 이상은 `NEARBY_WIFI_DEVICES`, target 37부터는 `ACCESS_LOCAL_NETWORK`이 필요하다(Android 보고서 A7).
  - 카메라가 "DIRECT-" SSID에 일반 AP처럼 붙는지는 실기로 확인한다.
- **시스템 핫스팟을 계속 쓴다면**: Pixel은 "Turn off hotspot automatically"를 끌 수 있다 [확인됨 DC-A17]. 삼성은 Android 보고서 CL-H6과 같다.

### 5-2-1. Nikon 카메라 AP 모드 FTP(추가 후보)

- Nikon Z9 매뉴얼에서 카메라 AP 모드로 FTP를 설정하는 단계에는 **서버 주소 입력 칸이 없다** [확인됨 DC-N14].
- 카메라 AP에 붙은 기기로 알아서 보내는 것으로 보인다(추측). 그렇다면 폰이 카메라 AP에 붙고 앱 FTP 서버가 받는 구성에서 IP 문제가 아예 없어진다.
- 단, 같은 매뉴얼에 "FTP servers running third-party software are not supported"라고 적혀 있다 [확인됨 DC-N14]. 공식 지원 밖이다.
- 폰이 카메라 AP에 붙어 있는 동안 업로드 경로
  - Android는 셀룰러로 나간다(Android 보고서 0장).
  - iOS는 그렇지 않다. 인터넷 없는 Wi-Fi에 붙은 상태에서 Firebase 업로드 경로를 강제할 수 없다(iOS 보고서 3장). 그래서 iOS에서는 쓰기 어렵다(추측).

### 5-3. 카메라 설정을 빠르게 넣기

| 브랜드 | 카드 저장·불러오기 | 폰·PC에서 넣기 | 제약 |
|---|---|---|---|
| Sony | [Save/Load FTP Settings], 카드당 10개, 비밀번호 16~32자 [확인됨 DC-S4] | T&T FTP Upload Preset(최대 30개)을 Bluetooth "Write to the camera"로 서버 슬롯(최대 9개)에 쓴다 [확인됨 DC-S11, DC-S5] | 다른 기종 파일은 못 불러오고, 같은 기종도 펌웨어가 다르면 실패할 수 있다 [확인됨 DC-S4] |
| Canon | [Save/Load Communication Settings on Card], 카드당 10개 [확인됨 DC-C4] | 확인 못 함 | 다른 기종 파일은 못 불러온다 |
| Nikon | Copy to/from Card. 암호 보호 프로필은 복사 불가 [확인됨 DC-N6] | Wireless Transmitter Utility(PC)로 FTP 프로필 txt를 만든다 [확인됨 DC-N7] | WTU 파일에는 무선 키와 FTP 비밀번호가 빠진다 |
| Fujifilm | 없음. 루트 인증서만 카드에서 읽는다 [확인됨 DC-F5] | XApp 백업은 네트워크 설정을 빼고 저장한다 [확인됨 DC-F10] | 16슬롯에 손으로 넣는다 |

**우리 쪽에서 할 수 있는 것**(추측)
- 우리가 설정 파일을 만들어 배포하는 방식은 어렵다. Sony·Canon은 같은 기종 파일만 받고, Nikon WTU에는 비밀번호가 빠지며, 핫스팟 SSID·비밀번호가 작가마다 다르기 때문이다.
- 대신 **값을 고정**하면 카메라 설정은 한 번으로 끝난다.
  - iOS: 172.20.10.1, 고정 포트, 작가별 계정
  - Android: Wi-Fi Direct 그룹을 쓰면 192.168.49.1, 고정 SSID·비밀번호
- 첫 설정 뒤 카메라에서 카드로 백업하게 안내한다(Sony, Canon, Nikon). 카메라를 초기화하거나 펌웨어를 올린 뒤 다시 불러오는 용도다.
- Sony T&T의 Bluetooth 쓰기는 Sony 앱 기능이다. 서드파티 앱은 Sony의 Bluetooth 프로토콜이 없어 같은 방식을 쓸 수 없다(추측). 온보딩 때 작가가 T&T로 우리 서버 값을 써넣게 안내하는 방법은 있다.

### 5-4. 카메라 쪽 자동 재연결과 미전송 재개

| 브랜드 | 연결 복구 시 | 전원을 껐다 켤 때 | 근거 |
|---|---|---|---|
| Sony | Wi-Fi는 "un-transferred images will be transferred when the connection resumes" | 자동 재전송 확인 못 함. "Only Non-transfer" 일괄 전송 | [확인됨 DC-S12, DC-S17] |
| Canon | 실패·중단분을 연결이 복구되면 자동 전송 | "if you cancel transfer or turn the camera off, auto retry is not attempted". "Select transfer failed images"로 보낸다 | [확인됨 DC-C5, DC-C6] |
| Nikon | Keep connection이 약 15초마다 재시도한다. 배터리를 더 쓴다 | "The camera saves transfer marking when turned off and resumes upload when next turned on." | [확인됨 DC-N8] |
| Fujifilm | 문서 없음 | IMAGE TRANSFER WHILE POWER OFF, 대기열 최대 9999장 | [확인됨 DC-F6] |

**의미**(추측): 전원을 껐다 켤 때의 재전송은 브랜드마다 다르다. 그래서 앱이 직접 미전송분을 알려야 한다.
- 앱이 받은 파일명·촬영 시각 목록을 갖고 있다가, 세션이 끝날 때 카메라 쪽 미전송분을 보내라고 안내한다. Sony "Only Non-transfer", Canon "Select transfer failed images"를 쓴다.
- D2로 연결돼 있으면 앱이 카드 목록을 직접 대조해 빠진 파일을 가져올 수 있다.

### 5-5. QR·NFC·Bluetooth

- **Wi-Fi 접속용 QR**
  - Sony·Canon·Nikon·Fujifilm에는 없다. QR은 MAC 주소용, 앱 다운로드용, 클라우드 주소용이다 [확인됨 DC-S15, DC-C8, DC-C10, DC-N5].
  - OM System(OM Image Share)과 Panasonic(LUMIX Sync)은 카메라 QR로 연결 정보를 넘긴다 [확인됨 DC-O1, DC-P4]. 둘 다 FTP가 없어 B안 대상이 아니다.
- **NFC**: 대상 기종 문서에서 찾지 못했다 [일부 확인].
- **Bluetooth로 깨우기**
  - Sony "Cnct. while Power OFF"는 Creators' App 가져오기용이다. FTP 깨우기가 아니다 [확인됨 DC-S19].
  - Panasonic Remote Wakeup은 꺼진 카메라를 켜고 Wi-Fi에 자동 연결한다 [확인됨 DC-P5].
  - Bluetooth 깨우기와 자동 재연결은 모두 제조사 앱 전용이다. 서드파티가 쓸 수 있는 공개 BLE 문서는 찾지 못했다(추측).

---

## 6. 권장 구조(추측, 실증 뒤 확정)

### 6-1. 플랫폼 × 기종군

| 기종군 | iOS | Android |
|---|---|---|
| Sony 신형(a7C II 등 10기종) | B안 Wi-Fi FTP + **D1 USB 테더링 FTP "유선 모드"** | **D3 Wi-Fi Direct 그룹** + FTP. D1은 IP 무작위·재연결 약점으로 보조 |
| Canon FTP 기종(R1, R5 II, R6 II 등) | B안 Wi-Fi FTP. 직결이 필요하면 D2(ImageCaptureCore + 제조사 명령) | D3 + FTP. 직결은 D2 |
| Nikon Z(Z8, Z9, Z6III, Zf, Z5II) | B안 Wi-Fi FTP(공식 지원 밖, iOS 보고서 1-4). **D2 실증 1순위**: 공식 선례(NX MobileAir)가 있다 | D3 + FTP. D2 실증 1순위 |
| Fujifilm FTP 기종(X-H2·X-H2S + FT-XH, GFX100 II) | B안 Wi-Fi FTP | D3 + FTP |
| FTP 없는 기종(Canon R8·R50, Fujifilm X-T5·X100VI, Sony a6700) | D2만 즉시 전송 후보. 실증 결과를 보고 지원 여부를 정한다 | D2. Fujifilm은 목록 폴링 방식 시험 |

### 6-2. 앱 구조 메모(추측)

- **수신 경로와 업로드 큐**
  - 수신 경로(FTP, USB PTP)를 여러 개 두고, 받은 파일은 모두 같은 업로드 큐(`TicketPhotoUploader`)로 보낸다.
  - 축소본 먼저, 원본 나중 흐름도 경로와 관계없이 같다.
- **놓친 사진 회수**
  - 세션 중 받은 파일 목록을 남긴다.
  - D2 연결이면 카드 목록과 대조해 빠진 파일을 가져온다.
  - FTP 연결이면 카메라에서 미전송분을 보내라고 안내한다.
- **연결 마법사**: 기종을 고르면 그 기종의 USB 모드, 급전 끄기, FTP 값, 카드 백업 단계를 보여 준다.
- **iOS 세션 화면**: 자동 잠금을 막고, Nikon 앱처럼 화면을 어둡게 하는 "촬영 중 잠금" 모드를 둔다. 연결 끊김 표시도 넣는다.

### 6-3. 작가 장비 가이드(추측)

- 짧은 USB-C 케이블. Sony D1은 USB-PD 지원 케이블 한 가닥 ★DC-S1
- Lightning iPhone은 Lightning to USB 3 Camera Adapter [확인됨 DC-I10]
- 카메라 USB 급전 끄기 [확인됨 DC-X13, DC-N13, DC-F11]
- 폰을 카메라에 고정하는 거치대(핫슈·그립 마운트)
- 장시간 촬영용 보조 배터리. 충전하면서 쓰는 허브는 실증에서 검증된 것만 권한다.

---

## 7. 실증 순서

B안 실증(Android 보고서 5-3)에 더한다.

1. **a7C II + iPhone, D1**: USB-C 모델과 Lightning 모델에서 각각 시험한다.
   - 카메라·폰이 받는 IP, 앱 리스너가 USB 쪽에서 받는지
   - 셀룰러 업로드를 동시에 할 수 있는지
   - 촬영 없이 3분 둔 뒤에도 연결이 유지되는지(90초 규칙)
   - 케이블을 다시 꽂거나 전원을 다시 켤 때의 절차와 시간
   - 30분 배터리 소모
2. **갤럭시 Wi-Fi Direct 그룹(D3)**
   - `createGroup`(SSID·비밀번호 고정, 2.4GHz)으로 만든 그룹의 GO IP(재부팅 전후)
   - a7C II·Canon·Nikon이 DIRECT- 그룹에 붙어 FTP로 보내는지, 그룹을 다시 만든 뒤 자동으로 다시 붙는지
   - 화면이 꺼지고 FGS만 남은 상태로 30분
3. **Nikon Z(Z6III 또는 Z8) + USB-C iPhone, D2**
   - MTP/PTP 모드에서 ImageCaptureCore가 인식하는지, 셔터를 누를 때 `didAdd`·`didReceivePTPEvent`가 오는지(이벤트 원문 기록)
   - 원본 다운로드 속도, 백그라운드에 10·30·60초 있다가 돌아왔을 때 세션이 이어지는지
4. **Nikon Z + 갤럭시, D2**: `readEvent`로 ObjectAdded가 오는지, "항상 사용" 체크 뒤 다시 꽂으면 창 없이 앱이 뜨는지, 삼성 갤러리와 충돌하는지. 같은 기기로 카메라 AP 모드 FTP(5-2-1)를 앱 FTP 서버가 받는지도 본다.
5. **iPhone 핫스팟 재연결(B안)**: 카메라를 3분 대기시켜 90초 끊김을 재현한다. 설정 화면을 떠난 상태에서 다시 붙는지, 다시 붙는 데 걸리는 시간, 호환성 최대화 On/Off 차이를 본다.
6. **Canon R6 II·R8, D2**: Photo Import/Remote Control 모드로 ImageCaptureCore가 인식하는지, 연결한 채 본체로 찍을 수 있는지, 새 사진 이벤트가 오는지.
7. **Fujifilm X-T5, D2(Android)**: CARD READER 모드로 연결한 채 촬영이 되는지, 목록 폴링으로 새 파일이 보이는지.
8. **Sony D2(iPhone)**: PC Remote(Dest.+Camera)와 MTP 모드에서 ImageCaptureCore가 인식하는지 본다. 기준선은 T&T USB PC Remote 자동 가져오기의 지연이다.
9. **권한 대화상자**: iOS 17·18·26·27별로, 카메라 급전 On/Off에 따라, 첫 연결 때만 뜨는지 본다.
10. **전력·충전**: 멀티포트 어댑터나 PD 허브로 충전하면서 PTP·테더링이 유지되는지.

---

## 8. 위험

| # | 위험 | 영향 | 완화책 |
|---|---|---|---|
| DR1 | iOS 포그라운드 제약은 유선에서도 남는다 ★DC-I3 | 작가가 다른 앱을 쓰면 수신이 멈춘다 | 세션 유지 화면, 돌아오면 놓친 사진 회수(6-2) |
| DR2 | 브랜드별 PTP 구현 비용 | D2 개발 기간이 길어진다 | Nikon부터 한 브랜드씩. Sony는 D1로 대신한다. CascableCore 비용과 비교한다 |
| DR3 | Sony D2는 법인 전용 규격이 필요할 수 있다 [확인됨 DC-S21] | 신청 조건·기간 | D1을 쓴다. 필요하면 사용자 확인 뒤 신청한다 |
| DR4 | ImageCaptureCore 권한 결함(iOS 18, 26.1 베타) [확인됨 DC-I5, DC-I6] | 연결이 안 된다 | iOS 버전별 실증, 실패 시 B안 안내 |
| DR5 | 폰 배터리 소모와 카메라 급전 | 촬영 중 폰이 꺼진다 | 카메라 급전 끄기, 보조 배터리, 검증된 충전 허브 |
| DR6 | 케이블이 빠지면 Sony D1은 메뉴를 다시 조작해야 한다 [확인됨 DC-S3] | 재연결이 느리다 | 케이블 고정 가이드, My Menu 등록 실증 |
| DR7 | Android D1·D2의 기기 차이(Pixel "–", 삼성 갤러리 충돌) ★DC-S8, [확인됨 DC-X7] | 일부 기기에서 안 된다 | 검증 기기 목록을 관리하고, 안 되면 D3 무선으로 안내한다 |
| DR8 | Wi-Fi Direct 그룹을 카메라가 받아들이는지 미확인 | D3가 막힌다 | 실증 2번. 막히면 시스템 핫스팟 + IP 표시(Android 보고서 3-3) |
| DR9 | 작가가 케이블 직결을 불편해할 수 있다(추측) | 유선 모드를 쓰지 않는다 | 유선은 선택 모드로 두고 무선을 기본으로 한다 |

---

## 9. 사용자 확인이 필요한 항목

- 작가에게 유선 모드를 권할지, 선택지로만 둘지(운영 정책)
- D2를 Sony까지 직접 구현할 경우 Camera Remote Command 법인 신청. 외부 신청이라 하지 않았다.
- iOS D2를 여러 브랜드로 넓힐 경우 CascableCore 가격 문의. 하지 않았다.
- 실증 기기: a7C II, USB-C iPhone과 Lightning iPhone, 갤럭시, Nikon Z 한 대, 가능하면 Canon R6 II·R8과 Fujifilm X-T5. 짧은 USB-C 케이블, Lightning to USB 3 Camera Adapter.

---

## 10. 출처

### iOS (DC-I)
- DC-I1 https://developer.apple.com/documentation/imagecapturecore
- DC-I2 https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand(_:outdata:completion:)
- DC-I3 ★ iOS 27.0 SDK(로컬 Xcode)의 ImageCaptureCore 헤더 `ICDeviceBrowser.h`, `ICCameraDevice.h`. Apple 문서 주석 원문
- DC-I4 https://developer.apple.com/forums/thread/765768
- DC-I5 https://developer.apple.com/forums/thread/756960
- DC-I6 https://developer.apple.com/forums/thread/802285
- DC-I7 https://support.apple.com/111806
- DC-I8 https://support.apple.com/en-us/105099
- DC-I9 https://support.apple.com/118280
- DC-I10 https://www.apple.com/shop/product/MX5J3AM/A/lightning-to-usb-3-camera-adapter
- DC-I11 https://www.apple.com/shop/product/MW5M3AM/A/usb-c-digital-av-multiport-adapter
- DC-I12 ★ https://support.apple.com/guide/platform-support/sup025284ac0/web (2025-10-22 게시)
- DC-I13 https://support.apple.com/en-us/HT203302
- DC-I14 https://support.apple.com/guide/iphone/iph45447ca6/ios
- DC-I15 (보조) https://www.macrumors.com/2025/09/09/iphone-air-usb-2/
- DC-I16 (보조) https://discussions.apple.com/thread/254591096

### Android (DC-A)
- DC-A1 https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/media/mtp/MtpDevice.cpp
- DC-A2 https://raw.githubusercontent.com/gphoto/libgphoto2/master/camlibs/ptp2/library.c
- DC-A3 https://raw.githubusercontent.com/gphoto/libgphoto2/master/camlibs/ptp2/ptp.h
- DC-A4 https://developer.android.com/develop/connectivity/usb/host
- DC-A5 https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/packages/SystemUI/src/com/android/systemui/usb/UsbConfirmActivity.java
- DC-A6 https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/services/usb/java/com/android/server/usb/UsbProfileGroupSettingsManager.java
- DC-A7 https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/hardware/usb/DeviceFilter.java
- DC-A8 https://developer.android.com/develop/background-work/services/fgs/service-types
- DC-A9 (보조) https://www.androidauthority.com/android-16-usb-data-advanced-protection-3548018
- DC-A10 ★ https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/staticlibs/device/com/android/net/module/util/PrivateAddressCoordinator.java
- DC-A11 https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/tags/android-13.0.0_r1/Tethering/src/com/android/networkstack/tethering/PrivateAddressCoordinator.java
- DC-A12 https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/Tethering/src/android/net/ip/IpServer.java
- DC-A13 https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/Tethering/src/com/android/networkstack/tethering/TetheringConfiguration.java
- DC-A14 https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/service/java/com/android/server/wifi/p2p/WifiP2pServiceImpl.java
- DC-A15 https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/java/android/net/wifi/p2p/WifiP2pConfig.java
- DC-A16 (보조) https://apkmirror.com/apk/netshare-softwares/netshare-no-root-tethering/netshare-no-root-tethering-2-1-release
- DC-A17 https://support.google.com/pixelphone/answer/2812516
- DC-A18 (보조) https://community.e.foundation/t/usb-tethering-assigning-static-ip-addresses/45446
- DC-A19 https://android.googlesource.com/platform/packages/apps/Settings/+/refs/heads/main/src/com/android/settings/connecteddevice/usb/UsbDefaultFragment.java
- DC-A20 (보조) https://bugzilla.mozilla.org/show_bug.cgi?id=1017461
- DC-A21 (보조) https://www.virtualhere.com/node/2782
- DC-A22 (보조) https://www.phonearena.com/phones/compare/Google-Pixel-9,Samsung-Galaxy-A56-5G/phones/12284,12470

### Sony (DC-S)
- DC-S1 ★ https://helpguide.sony.net/di/ftp_2360/v1/en/contents/smartphone_connection.html
- DC-S2 https://helpguide.sony.net/di/ftp_2440/v1/en/contents/smartphone_connection.html
- DC-S3 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/FTP_server_connection.html
- DC-S4 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/save_load.html
- DC-S5 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/smartphone_FTP_server_setting.html
- DC-S6 https://support.d-imaging.sony.co.jp/app/transfer/en/devices/cameras.php
- DC-S7 https://support.d-imaging.sony.co.jp/app/transfer/en/instruction/21_ftp.php
- DC-S8 ★ https://support.d-imaging.sony.co.jp/app/transfer/en/devices/index.php
- DC-S9 https://support.d-imaging.sony.co.jp/app/transfer/en/instruction/23_usbpc.php
- DC-S10 https://support.d-imaging.sony.co.jp/app/transfer/en/instruction/22_usb.php
- DC-S11 https://support.d-imaging.sony.co.jp/app/transfer/en/instruction/51_ftp.php
- DC-S12 https://support.d-imaging.sony.co.jp/app/transfer/en/faqs/index.php
- DC-S13 https://helpguide.sony.net/ilc/2360/v1/en/contents/201h_remote_shoot_setting.html
- DC-S14 https://helpguide.sony.net/ilc/2360/v1/en/contents/0601_usb_connection.html
- DC-S15 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/WiFi_connection.html
- DC-S16 https://helpguide.sony.net/ilc/2360/v1/en/contents/0706_access_point_manual.html
- DC-S17 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/auto_transfer.html (같은 가이드의 batch_transfer.html, power_save.html 포함)
- DC-S18 https://helpguide.sony.net/di/ftp_2230/v1/en/index.html (a7R V). ftp_2380(a9 III), ftp_2420(a1), ftp_2440(a1 II)도 같은 구성
- DC-S19 https://helpguide.sony.net/ilc/2320/v1/en/index.html (a6700. contents/221h_usb_lan_tether.html, contents/0703_connect_while_power_off.html)
- DC-S20 https://helpguide.sony.net/di-app/ca/v1/en/contents/CA_usb_connect.html
- DC-S21 https://support.d-imaging.sony.co.jp/app/cameraremotecommand/en/index.html

### Canon (DC-C)
- DC-C1 https://cam.start.canon/en/C017/manual/html/UG-06_Network_0030.html (R5 II)
- DC-C2 https://cam.start.canon/en/C018/manual/html/UG-06_Network_0030.html (R1)
- DC-C3 https://cam.start.canon/en/C017/manual/html/UG-06_Network_0300.html , https://cam.start.canon/en/C011/manual/html/UG-09_Set-up_0230.html (R50)
- DC-C4 https://cam.start.canon/en/C017/manual/html/UG-06_Network_0310.html
- DC-C5 https://cam.start.canon/en/C017/manual/html/UG-06_Network_0060.html
- DC-C6 https://cam.start.canon/en/C012/manual/html/UG-07_Network_0070.html
- DC-C7 https://cam.start.canon/en/C012/manual/html/UG-07_Network_0100.html
- DC-C8 https://cam.start.canon/en/C012/manual/html/UG-07_Network_0030.html
- DC-C9 https://cam.start.canon/en/C013/manual/html/UG-07_Network_0030.html (R8)
- DC-C10 https://cam.start.canon/en/S013/manual/html/UG-00_Before_0020.html (CTP)
- DC-C11 https://cam.start.canon/en/S001/manual/html/UG-00_Before_0020.html , https://cam.start.canon/en/S001/manual/html/UG-01_MFT-i_0050.html (Mobile File Transfer)
- DC-C12 https://cam.start.canon/ko/H001/supplement_0140.html (iPhone 케이블 확인 기종)
- DC-C13 https://asia.canon/en/consumer/multi-function-shoe-adapter-for-smartphone-link-ad-p1/main/product
- DC-C14 https://asia.canon/en/support/8200044600
- DC-C15 (보조) https://www.apkmirror.com/?p=3520158
- DC-C16 (보조) https://www.manualslib.com/products/Canon-Eos-R1-14326318.html

### Nikon (DC-N)
- DC-N1 https://onlinemanual.nikonimglib.com/z8/en/nwm_usb_%20data_connection_363.html , https://onlinemanual.nikonimglib.com/z6III/en/nwm_usb_data_connection_368.html , https://onlinemanual.nikonimglib.com/z5II/en/nwm_usb_data_connection_360.html
- DC-N2 ★ https://nikonimglib.com/nxmoba/onlinehelp/en/05_import_02.html
- DC-N3 https://onlinemanual.nikonimglib.com/z9/en/15_menu_guide_06_27.html
- DC-N4 https://nikonimglib.com/nx_tether/onlinehelp/en/01_the_nx_tether_window_2.html
- DC-N5 https://onlinemanual.nikonimglib.com/z6III/en/nwm_cloud_361.html
- DC-N6 https://onlinemanual.nikonimglib.com/z6III/en/nwm_connect_to_ftp_server_365.html , https://onlinemanual.nikonimglib.com/z9/en/adding_updating_ftp_connection_358.html , https://onlinemanual.nikonimglib.com/z8/en/nwm_connect_to_ftp_server_360.html
- DC-N7 https://nikonimglib.com/wt4su/onlinehelp/en/04_creating_settings_01.html
- DC-N8 https://onlinemanual.nikonimglib.com/z6III/en/uploading_pictures_97.html
- DC-N9 https://www.nikonusa.com/content/z-9-firmware-5-point-0
- DC-N10 https://nikonusa.com/content/nx-mobileair
- DC-N11 https://nikonimglib.com/nxmoba/onlinehelp/en/03_connect_01.html
- DC-N12 https://nikonimglib.com/nxmoba/onlinehelp/en/03_connect_02.html
- DC-N13 https://onlinemanual.nikonimglib.com/zf/en/sum_usb_power_delivery_316.html
- DC-N14 https://onlinemanual.nikonimglib.com/z9/en/11_connecting_to_computers_or_ftp_servers_04.html

### Fujifilm (DC-F)
- DC-F1 https://fujifilm-dsc.com/en/manual/x-h2_connection/overview_usage/ftp_upload/index.html
- DC-F2 https://apps.apple.com/app/id1586089681
- DC-F3 https://fujifilm-dsc.com/en/manual/x100vi/connections/usage_usb/
- DC-F4 https://fujifilm-dsc.com/en/manual/x-t5/connections/tethere/
- DC-F5 https://fujifilm-dsc.com/en/manual/gfx100ii/connections/network_usb_menu/ , https://fujifilm-dsc.com/en/manual/x-h2_connection/network_usb_menu/network_usb_menu/index.html
- DC-F6 https://fujifilm-dsc.com/en/manual/gfx100ii/connections/ftp_upload/
- DC-F7 https://fujifilm-dsc.com/en/manual/x-t5/connections/network_usb_menu/ , https://fujifilm-dsc.com/en/manual/x100vi/connections/network_usb_menu/
- DC-F8 https://fujifilm-dsc.com/en/manual/x100vi/connections/usage_smartphone_app/
- DC-F9 https://fujifilm-dsc.com/en/manual/x-m5/connections/usage_smartphone_app/
- DC-F10 https://www.fujifilm-x.com/global/products/software/xapp/
- DC-F11 https://fujifilm-dsc.com/en/manual/x-t5/connections/usage_usb/index.html

### Panasonic·OM System (DC-P, DC-O)
- DC-P1 https://eww.pavc.panasonic.co.jp/dscoi/DC-GH7/html/DC-GH7_DVQP3109_eng/0148.html , https://eww.pavc.panasonic.co.jp/dscoi/DC-S5M2/html/DC-S5M2_DVQP2839_eng/0171.html
- DC-P2 (보조) https://apps.apple.com/us/app/panasonic-lumix-lab/id6499262377
- DC-P3 https://eww.pavc.panasonic.co.jp/dscoi/DC-GH7/html/DC-GH7_DVQP3109_eng/0129.html
- DC-P4 https://eww.pavc.panasonic.co.jp/dscoi/DC-GH7/html/DC-GH7_DVQP3109_eng/0141.html
- DC-P5 https://eww.pavc.panasonic.co.jp/dscoi/DC-GH7/html/DC-GH7_DVQP3109_eng/0142.html
- DC-O1 https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/pairing_smartphone_wifi_274.html
- DC-O2 https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/auto_upload_images_camera_off_278.html

### 서드파티 앱·기타 (DC-X)
- DC-X1 Capture One: https://apps.apple.com/us/app/capture-one/id1514081672
- DC-X2 Cascable Studio: https://apps.apple.com/us/app/cascable-studio-tether-more/id974193500
- DC-X3 CascableCore: https://developer.cascable.se/
- DC-X4 TetherDrop: https://apps.apple.com/app/id6788720660
- DC-X5 (보조) Lightroom 기능 요청: https://community.adobe.com/feature-requests-681/p-tethering-to-an-ipad-pro-661297
- DC-X6 (보조) Camera Connect & Control: https://apps.apple.com/us/app/camera-connect-control/id1457548017 , https://www.apkmirror.com/apk/rupiapps/camera-connect-control/camera-connect-control-6-6-1-release/camera-connect-control-6-6-1-android-apk-download/
- DC-X7 Evoto Instant: https://support.evoto.ai/?p=13778 , https://support.evoto.ai/?p=13846 , https://support.evoto.ai/?p=13941 , https://support.evoto.ai/?p=17517
- DC-X8 (보조) Helicon Remote: https://cafebazaar.ir/app/com.HeliconSoft.HeliconRemote2?l=en
- DC-X9 (보조) qDslrDashboard: https://dslrdashboard.info/?p=2
- DC-X10 Sony Creators' App: https://creatorscloud.sony.net/catalog/en-ie/creatorsapp/index.html
- DC-X13 Sony USB Power Supply: https://www.sony.co.in/electronics/support/articles/00302174
