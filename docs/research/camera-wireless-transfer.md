# 카메라 → 아이폰 무선 전송 브랜드 비교 조사

- 작성: 2026-10-17, sbsn_research 세션(sbsn_main 요청)
- 대상: 십분스냅 작가 앱 `sbsnPhotographer`(최소 iOS 17)
- 확인 날짜: 따로 적지 않은 출처는 모두 2026-10-17에 확인했다.
- 표시 규칙
  - **[확인됨]**: 1차 출처(제조사 공식 문서, Apple 문서, Apple DTS 답변, 앱스토어 원문)에서 직접 확인했다.
  - **[일부 확인]**: 2차 출처(판매점, 기사, 포럼, 서드파티 문서)로만 확인했다. 1차 출처끼리 충돌하거나 일부 기종만 확인한 경우도 여기에 넣었다.
  - **[확인 못 함]**: 찾지 못했다. 또는 가입이나 문의를 해야만 볼 수 있다.
  - **(추측)**: 근거로부터 추론한 판단이다.
  - `SNY-3` 같은 출처 ID는 6장의 출처 목록을 가리킨다. ★ 표시는 이 문서를 쓰면서 원문을 다시 열어 교차 확인한 출처다.
- 조사 한계
  - 실기 검증은 하지 않았다. 이 문서에서 "가능"은 모두 문서상 가능하다는 뜻이다.
  - 조사 도중 세션이 함께 쓰는 WebSearch 한도(200회)가 바닥났다. 그 뒤로는 이미 알고 있던 URL만 WebFetch로 열었다. 그래서 Sony C3 Portal, Canon Camera Connect의 백그라운드 동작, iOS 18 사진 권한 UX 등은 확인하지 못했다.
  - 열지 못한 페이지가 있다. leica-camera.com의 PDF(502 오류), api.ricoh(DNS 실패), developer.sony.com(차단)이다. Canon 개발자 커뮤니티는 JS 렌더링이 필요해서 Playwright로 읽기만 했다.
  - iOS 27이 2026-09-14에 출시됐다 ★IOS-31. 요청서에 적힌 "iOS 26 Wi-Fi Aware" 같은 표현은 "iOS 26 이상" 기준으로 썼다.
- **보완(2026-10-19)**: Android 기준 조사와 "카메라 → 폰 핫스팟 → 우리 클라우드 FTPS 직행" 대안은 [camera-wireless-transfer-android.md](camera-wireless-transfer-android.md)에 있다. 권장 구조는 그 문서 5장에서 iOS·Android 통합안으로 갱신했다.
- **결정(2026-10-19, 사용자)**: 초기에는 서버 없이 이 문서의 1차안(핫스팟 + 앱 내장 FTP 수신)으로 간다. 클라우드 직행은 파일럿에서 R1(포그라운드 필수)이 실제 문제로 드러날 때 다시 검토한다.

---

## 0. 요약

1. **서드파티 iOS 앱이 무선으로 카메라를 다룰 수 있는 공식 API는 적다.**
   - iOS 지원을 명시한 곳은 Canon CCAPI 하나다 ★CAN-1.
   - Sony Camera Remote Command(PTP/PTP-IP 명령 사양)는 OS를 가리지 않지만 법인만 쓸 수 있다 ★SNY-2.
   - Nikon, Fujifilm, Panasonic, Sigma의 SDK는 데스크톱 전용이다(Fujifilm은 Android USB도 지원).
2. **여러 브랜드를 한 번에 덮는 공식 경로는 카메라 내장 "FTP 자동 전송"이다.**
   - Sony: a7C II를 포함한 중급기 이상
   - Canon: R1, R3, R5, R5 II, R6, R6 II, R6 III, R6 V
   - Nikon: Z9, Z8, Z6III, Zf, Z5II, Z50II, ZR, Z5IIC
   - Fujifilm 일부: GFX100 II, GFX100S II, 그리고 FT-XH를 단 X-H2/X-H2S
   - Panasonic, OM System, Leica, Ricoh, Sigma, Hasselblad는 FTP가 없거나 확인되지 않았다.
3. **"카메라 → 아이폰 핫스팟 → 앱이 FTP 서버로 수신" 구조는 이미 동작하는 사례가 있다.**
   - Sony가 자사 iOS 앱 Transfer & Tagging으로 이 구조를 공식 제공하고 원본 크기로 보낸다 ★SNY-3.
   - 서드파티 iOS 앱 TetherDrop, ShutterSnitch, PhotoSync도 같은 수신 방식을 구현했다 ★COM-18.
   - 따라서 십분스냅이 직접 구현할 수 있다고 본다(추측). 근거는 문서와 앱 사례다.
4. **무선 수신은 어떤 방식이든 작가 앱이 화면 앞에 떠 있고(포그라운드) 화면이 켜져 있어야 한다.**
   - Apple DTS는 "백그라운드에서 도는 네트워크 서버는 만들 수 없다(You can't)"고 답했다 ★IOS-18.
   - Sony도 iOS에서는 수신하는 동안 앱을 포그라운드에 두라고 안내한다 ★SNY-3.
5. **연결 구조는 "카메라가 아이폰 개인용 핫스팟에 붙는 방식"을 권한다.**
   - 반대로 아이폰이 카메라 Wi-Fi(AP)에 붙으면, 업로드를 셀룰러로 강제해야 한다. 그런데 URLSession과 Firebase Storage에는 셀룰러를 강제하는 수단이 없다.
   - `joinOnce` 연결은 앱이 15초 넘게 백그라운드에 있거나 기기가 잠들면 끊긴다 ★IOS-8.
   - 핫스팟 방식에서는 셀룰러가 유일한 인터넷 경로라서 이런 문제가 없다.
6. **2차안(촬영 후 일괄 전송)은 USB-C 유선 + ImageCaptureCore가 가장 유력하다.**
   - 브랜드를 가리지 않고, 원본을 받으며, 무료다.
   - 다만 iOS 18과 26.1 베타에서 권한 결함이 보고됐으므로 실기 검증을 먼저 한다.
   - 업로드는 파일 기반 백그라운드 URLSession으로 하고, iOS 26 이상에서는 `BGContinuedProcessingTask`로 보강한다.
7. **"제조사 앱 → 사진 앱 → PhotoKit 감지" 우회는 주 경로로 맞지 않는다.**
   - 즉시성이 약하다. 앱이 백그라운드면 사진 라이브러리 변경 알림이 오지 않는다.
   - 원본도 보장되지 않는다. 예를 들어 Nikon 자동 전송은 2MP/8MP다.
8. **Frame.io C2C는 파일럿 이상으로 권하지 않는다.**
   - Fujifilm, Panasonic, Leica SL3 계열의 원본 업로드 경로이긴 하다.
   - 하지만 사람 없이 서버끼리 인증하려면 Enterprise 플랜이 필요해 보이고, 웹훅은 아직 베타다.
   - Adobe 약관 6.4(제3자 대행·호스팅 금지)와 충돌할 위험도 있다.
9. **상용 SDK CascableCore는 FTP가 없는 기종을 메울 후보다.**
   - Canon, Nikon, Sony는 최신 기종까지 지원한다.
   - Fujifilm은 X-T4 세대, Panasonic은 GH5 세대에서 지원이 멈췄다. 가격도 공개하지 않는다.
   - Canon R8, R50, Sony a6700처럼 FTP가 없는 기종을 메울 후보로 평가판 검토를 권한다(사용자 확인 필요).

---

## 1. 브랜드 × 전송 방식 매트릭스

### 1-1. 서드파티 앱용 공식 SDK·API

| 브랜드 | 공식 SDK·API | iOS 앱에서 사용 | 가입·라이선스 조건 | 상업적 사용 |
|---|---|---|---|---|
| **Sony** | Camera Remote SDK 2.02.00 (macOS·Windows·Linux) / Camera Remote Command (PTP 확장 명령 사양, 2024-10에 PTP-IP 추가) | SDK는 불가 [확인됨 SNY-1]. Command는 "OS 무관"이라고 하지만 iOS를 명시하지는 않는다 ★SNY-2. iOS 앱 Camera Connect & Control이 2020년 이후 Sony 기종을 "PTP (Camera Remote Command)"로 연결한다 ★COM-17 | SDK: 무료, 지역별 신청. Command: **법인 전용**("only available for corporate customers"), 한국은 이메일(dimkt@sony.co.kr)로 신청 ★SNY-2 | 앱 판매 가능("Developers can sell their apps for legitimate purposes") ★SNY-2. 계약서 본문은 가입해야 볼 수 있다 [확인 못 함] |
| **Canon** | CCAPI (HTTP REST) / EDSDK (USB, 데스크톱) | CCAPI는 iOS 공식 지원("supports Android, iOS, and Linux") ★CAN-1. EDSDK는 불가 [확인됨] | 지역마다 조건이 다르다. USA: 북·남미·카리브 거주 개인 [확인됨 CAN-5]. Asia: 법인만, 신청 국가에 한국 없음 ★CAN-1. Japan: 법인 한정이지만 개인에게도 줄 수 있음 [확인됨 CAN-2]. **한국 법인이 신청할 경로는 확인 못 함** | 계약서 본문 미확인 [확인 못 함] |
| **Nikon** | Nikon SDK (Remote Module, Windows 11·macOS) | 불가 [확인됨 NIK-1] | 무료, 신청 절차 안에서 계약에 동의, 기술지원 없음 | 계약서 본문은 신청해야 볼 수 있다 [확인 못 함] |
| **Fujifilm** | X Series/GFX Camera Control SDK 1.34 (Windows·macOS·Linux, Android는 USB만) | 불가 [확인됨 FUJ-1] | 로열티 없는 EULA. object code로만 배포할 수 있고 역공학은 금지 [확인됨 FUJ-2] | 앱에 넣어 배포하는 것은 허용. 법인 조건은 문의해야 알 수 있다 [확인 못 함] |
| **Panasonic** | LUMIX SDK Windows 베타(USB, 일부 기종 Ethernet) | 불가 [확인됨 PAN-1] | 동의 후 카메라의 11자리 코드를 입력해 내려받는다. 지원은 보장하지 않는다 | 미확인 [확인 못 함] |
| **OM System** | 현행 SDK 없음. 구 OPC SDK는 OLYMPUS AIR와 함께 종료 | 공식 경로 없음 [확인됨 OM-1, OM-2]. 비공식 HTTP 프로토콜은 있다 [일부 확인 OM-3] | — | — |
| **Leica** | 공개 SDK 없음. Capture One과 파트너 단위로 통합 | 공식 경로 없음 [확인 못 함, 부재로 판단] | — | — |
| **Ricoh/Pentax** | RICOH Camera SDK(2018). USB SDK와 Wireless SDK(iOS·Android). 대상은 K-1 II, K-1, KP, K-70 | 구형 PENTAX 4기종만 [일부 확인 RIC-1]. GR 시리즈는 비공식 HTTP API만 있다 [확인됨 RIC-2, RIC-3] | 무료, 기술지원 없음 | 미확인 |
| **Sigma** | Camera Control SDK (Windows·Mac, USB, fp·fp L) | 불가 [확인됨 SIG-1] | 보증 없음 | 앱 개발 목적에 한함 |
| **Hasselblad** | X 시스템용 공개 SDK 없음 | 불가 [확인 못 함, 부재로 판단 HAS-4] | — | — |

### 1-2. 전송 방식별 지원

전송 방식은 다섯 가지로 나눴다.
- (a) 카메라가 AP가 되고 폰이 접속한다.
- (b) 카메라가 외부 AP(아이폰 핫스팟)에 붙어 FTP로 자동 전송한다.
- (c) 제조사 공식 앱이 자동 전송한다.
- (d) 카메라가 클라우드로 직접 보낸다.
- (e) USB-C 유선으로 연결한다.

표의 기호는 다음 뜻이다.
- ● 공식 지원을 확인했다.
- ◐ 조건부다(일부 기종만, 축소본만, 또는 공식 앱 전용).
- ○ 지원하지 않음을 확인했다.
- ? 확인하지 못했다.

| 브랜드 | (a) 카메라 AP | (b) 핫스팟 + FTP 자동 | (c) 공식 앱 자동 전송 | (d) 클라우드 직접 | (e) USB-C 유선 |
|---|---|---|---|---|---|
| **Sony** | ◐ Creators' App 전용이고 프로토콜은 비공개. 서드파티는 Camera Remote Command PTP-IP를 쓴다(a7C II의 무선 지원 여부는 가입 후 받는 README에만 있음) | ● **내장.** a7C II, a7 IV, a7R V, a9 III, a1 II, a7 V, a7S III, a7CR 등. 원본, JPEG/HEIF/RAW 선택, FTPES 켜고 끄기, Passive 모드 ★SNY-3~7 | ◐ Creators' App이 촬영하면서 전송한다(a7C II는 Ver.2.00 이상). 원본/2M 선택, 기본값은 2M. 백그라운드 전송은 [일부 확인] | ◐ Creators' Cloud(등록한 AP를 거쳐 업로드). Frame.io는 지원 안 함 [확인됨 FIO-1] | ? Creators' App의 USB-C 연결에 iPhone이 명시돼 있지 않다. iOS에서 PTP로 접근되는지는 실증해야 한다 |
| **Canon** | ◐ Camera Connect 전용이고 프로토콜은 비공개. CCAPI는 R5 II, R6 III에서 **인프라 모드(외부 AP)만** 설명돼 있다 [확인됨 CAN-6, CAN-7] | ● **내장.** R1, R3, R5, R5 II(SFTP 포함), R6, R6 II, R6 III, R6 V. 원본, JPEG/HEIF 크기 선택, RAW+JPEG 조합 선택, 실패하면 자동 재시도 [확인됨 CAN-8~14]. **R7, R8, R50, R50 V는 지원 안 함** [확인됨 CAN-15] | ◐ "Send to smartphone after shot", 크기 선택 가능(선택지와 포맷은 확인 못 함) [일부 확인 CAN-16] | ◐ image.canon에 원본을 30일 보관 [확인됨 CAN-17]. Frame.io는 시네마 기종(C80, C400, C50)의 프록시 영상만 [확인됨 FIO-5] | ◐ R5 II, R6 III에 "iOS 사진 앱용" USB 모드가 있다 [확인됨 CAN-18]. ImageCaptureCore로 접근되는지는 실증해야 한다 |
| **Nikon** | ◐ SnapBridge AP 모드. 자동 다운로드는 안 되고, 수동으로는 원본과 NEF를 받을 수 있다 [확인됨 NIK-5, NIK-6] | ● **내장.** Z9, Z8, Z6III, Zf, Z5II, Z50II, ZR, Z5IIC. 구형(Z7II, Z6II 등)은 WT-7이 필요하다. 원본을 보내고, Z9는 FTP/SFTP/FTPS를 지원한다. **매뉴얼에 "서드파티 소프트웨어로 돌아가는 FTP 서버와 인터넷 FTP는 지원하지 않는다"고 적혀 있다** [확인됨 NIK-8, NIK-9] | ◐ SnapBridge 자동 전송은 **2MP/8MP만, 원본 불가** [확인됨 NIK-6]. NX MobileAir는 원본을 FTP로 중계하지만 백그라운드 동작은 불명 [일부 확인 NIK-4] | ◐ Nikon Imaging Cloud가 원본을 직접 올린다(Z8, Z9 제외). 개발자 API는 없다 [확인됨 NIK-11]. Frame.io는 NX MobileAir를 거쳐야 한다 [확인됨 FIO-4] | ? [iPhone] USB 모드는 NX MobileAir 전용으로 보인다(추측). [MTP/PTP] 모드는 "컴퓨터·Android용"이라고 적혀 있다 [확인됨 NIK-10] |
| **Fujifilm** | ◐ XApp 전용, 프로토콜 비공개. 무선 테더링은 PC만 지원 [확인됨 FUJ-4, FUJ-5] | ◐ GFX100 II, GFX100S II는 **내장**, X-H2/X-H2S는 **FT-XH가 필요**하다. FTP/FTPS 지원. **X-T5, X100VI, X-T50, GFX100RF에는 FTP가 없다** [확인됨 FUJ-6~8] | ◐ XApp이 촬영 즉시 전송한다. 원본/압축 선택, JPEG/RAW/HEIF 선택 [확인됨 FUJ-9]. iOS 백그라운드 동작은 문서에 없다 | ● **Frame.io 내장** 12기종: X-H2/H2S, X-T5, X-T50, X100VI, GFX100 II/S II/RF, X-S20, X-M5, X-E5, X-T30 III [확인됨 FIO-2] | ● **표준 PTP.** iOS 사진 앱으로 가져오기를 공식 안내한다 [확인됨 FUJ-11] |
| **Panasonic** | ◐ LUMIX Lab 전용(비공개 HTTP). BLE로 페어링한 뒤 앱이 Wi-Fi 연결을 시작한다 [확인됨 PAN-2, PAN-4] | ○ **FTP 없음.** 대신 PC 공유 폴더(SMB 방식으로 보임)로 "촬영하면서 전송"이 있다 [일부 확인 PAN-5, PAN-7] | ◐ Auto Transfer: 촬영할 때마다 전송, 원본/축소 선택, JPG/HEIF/RAW 선택 [확인됨 PAN-5, PAN-6]. iOS 백그라운드 동작은 확인 못 함 | ● **Frame.io**: S5II, S5IIX, GH7, S1RII, S1II, S1IIE. JPEG/RAW, 자동으로 대기열에 올림 [확인됨 PAN-8, FIO-3] | ? PC(Tether) 모드가 iOS에서 인식되는지는 확인 못 함. 앱 유선 연결은 S9, L10만 [일부 확인 PAN-9] |
| **OM System** | ◐ 비공식 HTTP(192.168.0.10). 원본을 GET으로 받을 수 있지만 새 사진 이벤트는 없다 [일부 확인 OM-3] | ○ FTP 없음(매뉴얼 기준). 외부 AP 연결은 PC용 OM Capture만 쓴다 [일부 확인 OM-4] | ◐ Share Order로 미리 고른 뒤 **알림을 탭해야** 전송된다. 즉시 전송이 아니다 [확인됨 OM-4] | ○ [확인됨 FIO-1] | ○ Storage/MTP 모드에서는 연결 중에 촬영할 수 없다 [확인됨 OM-4] |
| **Leica** | ◐ FOTOS 전용. M10이 PTP/IP를 쓴다는 보고가 있다 [일부 확인 LEI-4] | ? 공식 자료에서 FTP를 찾지 못했다 | ◐ M11 계열만 BLE로 **프리뷰만** 백그라운드 전송한다 [확인됨 LEI-1] | ● **Frame.io**: SL3, SL3-S, SL3-P. DNG/JPG, 자동 업로드가 기본 [확인됨 LEI-3] | ◐ Q3는 MFi. 서드파티 iOS 앱 Evoto가 PTP 모드로 M11과 SL을 테더링한다 [일부 확인 LEI-6, LEI-7] |
| **Ricoh/Pentax** | ◐ 공식 앱(Image Sync, GR WORLD). GR은 비공식 HTTP API가 있다 [확인됨 RIC-2, RIC-5] | ? 찾지 못했다(없을 가능성이 높음, 추측) | ◐ 예약해 둔 사진을 전송하고, JPEG는 XS 크기로 줄일 수 있다(K-3 III, GR III/IIIx) [확인됨 RIC-7] | ○ [확인됨 FIO-1] | ? 사양에는 MTP만 있다 [확인됨 RIC-6] |
| **Sigma** | ○ fp와 BF에 무선이 없다 [일부 확인 SIG-2] | ○ | ○ | ◐ fp만 Atomos 장비를 거쳐 영상 프록시를 올린다 [확인됨] | ◐ Mass Storage. BF는 파일 앱에서 수동으로 다룬다 [일부 확인 SIG-3] |
| **Hasselblad** | ◐ Phocus Mobile 2 전용(iOS 17 이상, 프로토콜 비공개) [확인됨 HAS-1] | ? 찾지 못했다 | ◐ BT로 카메라를 깨워 접속한다. 자동 전송은 문서에 없다 [확인됨 HAS-1] | ○ [확인됨 FIO-1] | ◐ Phocus Mobile 2가 USB-C로 직결된다(v3.6.0). 서드파티 앱 사용 가능 여부는 불명 [확인됨 HAS-2] |

### 1-3. 원본 해상도와 포맷

| 브랜드 | 촬영 즉시 **원본**을 받을 수 있는 경로 | 축소본만 받는 경로 | 비고 |
|---|---|---|---|
| Sony | FTP(원본, JPEG/HEIF/RAW 선택) ★SNY-7. Creators' App에서 [Original]을 고른 경우 | Creators' App 기본값 2M | HEIF 지원 |
| Canon | FTP(원본, JPEG/HEIF 크기 선택 가능). CCAPI contents [일부 확인] | Camera Connect 축소 설정 | R5 II는 SFTP 지원 |
| Nikon | FTP(원본, Z9는 HEIF로 변환하는 옵션도 있음). NX MobileAir FTP 중계 | SnapBridge 자동 전송(2MP/8MP) | 영상은 FTP 자동 전송 대상이 아니다 |
| Fujifilm | FTP 기종. XApp에서 리사이즈 OFF. Frame.io | XApp에서 리사이즈 ON(권장값) | Wi-Fi로 RAW를 받을 수 있는 범위는 기종에 따라 다르다 |
| Panasonic | Auto Transfer에서 Original 선택. Frame.io | Auto Transfer 축소(L/M/S/XS/VGA) | |
| OM System | 비공식 HTTP GET | OI.Share 가져오기 크기 선택 | |
| Leica | Frame.io(SL3 계열) | FOTOS 백그라운드 전송(M11 프리뷰) | |
| Ricoh/Pentax | 공식 앱 수동 가져오기 | Image Sync 자동 리사이즈(XS) | HEIF 없음 |
| Hasselblad | Phocus Mobile 2(3FR/HEIF/JPG) | 내보낼 때 크기 선택 | |

### 1-4. 브랜드별 노트

**Sony**(요약, 세부 실증은 sbsn_main 담당)
- a7C II의 FTP 자동 전송 설정 항목 ★SNY-5, SNY-6, SNY-7
  - `FTP Function` On → `Auto FTP Transfer` On으로 켠다.
  - 서버 등록 항목: Host(IP 가능), **Secure Protocol On/Off**(FTPES), Root Certificate Error 처리, Port, 디렉터리(Standard / Same as in Camera), 같은 파일명 처리, User/Password, **Passive Mode On/Off**.
  - 전송 대상: `JPEG & HEIF` / `RAW` / `RAW+J & RAW+H`.
  - 연결 실패 처리: "FTP 서버 연결이 수립되지 않으면, 연결이 복구된 뒤 전송 대상 이미지를 자동으로 보낸다." 전송 도중 끊긴 경우는 문서에 없다.
- Transfer & Tagging(iOS)은 "works as an FTP server"로 원본 크기를 받는다 ★SNY-3. 지원하는 연결은 개인용 핫스팟, AP, USB 테더링이고, iOS에서는 "keep Transfer & Tagging in the foreground"라고 안내한다.
- Camera Remote SDK의 Wi-Fi 지원 기종(2024-04 공지)은 ILCE-1, 9M3, 7SM3, 7M4다. a7C II는 이 목록에 없다 [확인됨 SNY-1].
- Camera Remote Command 문서에 "Camera Control PTP 2 commands may become unusable on some models from 2027"이라는 경고가 있다 ★SNY-2.
- 구 Camera Remote API는 2020년에 종료됐다 [일부 확인 SNY-14].

**Canon**
- CCAPI 지원 기종 [확인됨 CAN-3, 2026-07-23 갱신]
  - 출고 시 이미 활성화된 기종: R1, R5 II, R6 III, PowerShot V10.
  - 활성화 작업이 필요한 기종: R6 II, R8, R50, R7, R10, R100, R3, R6 등. 개발자 사이트의 도구로 USB 연결해 활성화한다 [일부 확인 CAN-20].
  - R5는 내장 Wi-Fi로만 CCAPI를 쓸 수 있고, WFT-R10 그립으로는 안 된다.
- CCAPI 이벤트 API: `/ccapi/[ver]/event/polling`(long polling), `/event/monitoring`(chunked). 파일 접근은 `/contents` [확인됨 CAN-4].
  - 새 파일 이벤트의 필드 이름과 원본 다운로드 세부는 레퍼런스를 받아야 알 수 있다 [확인 못 함].
  - 커뮤니티 보고: 동시 요청을 큐잉하지 못하고, 3초보다 짧은 간격으로 연속 촬영하면 누락될 수 있다 [일부 확인 CAN-21].
- 2019년에 SpotMyPhotos가 CCAPI로 "촬영 약 5초 뒤 스마트폰 전달" 서비스를 운영했다 [일부 확인 CAN-22]. 십분스냅과 비슷한 상용 선례다.
- Canon 중계 앱 Mobile File Transfer는 JPEG만 보낸다. iOS USB 연결은 R3, R6 II만 되고, 유료화가 예고됐다 [확인됨 CAN-19].

**Nikon**
- 내장 FTP의 공식 지원 범위는 좁다. 매뉴얼 원문: "Internet FTP connections and connection to FTP servers running third-party software are not supported." [확인됨 NIK-8]
  - ShutterSnitch, PhotoSync 같은 iOS 앱이 Nikon FTP 수신을 내세운다 [확인됨 COM-14, COM-15]. 기술적으로는 될 가능성이 높지만 공식 지원 밖이다(추측). 실증이 필요하다.
- 카메라는 한 번에 한 종류의 기기(컴퓨터, FTP, 스마트기기)에만 연결된다 [확인됨, Z5II·Z50II 매뉴얼]. 그래서 FTP를 쓰는 동안 SnapBridge는 쓸 수 없다.
- SnapBridge App Store 원문: "Download is not available when the app is running in the background"(Wi-Fi 다운로드 기준) [확인됨 NIK-7].
- NX MobileAir(iOS 15 이상, 2026-07부터 무료)는 카메라에서 받아 FTP와 Frame.io로 올린다. 무선 지원 기종은 Z9, Z8, Z6III, Z5II, Zf, Z50II, ZR이고, JPEG와 NEF를 다루며 HEIF는 안 된다 [확인됨 NIK-4].

**Fujifilm**
- SDK는 iOS를 지원하지 않는다. 지원 카메라 목록에 X100VI, X-T50, X-E5, X-T30 III가 없다 [확인됨 FUJ-1]. EULA에는 "SDK로 카메라를 연결·제어하면 카메라 보증이 무효가 된다"는 경고가 있다 [확인됨 FUJ-2].
- FTP는 고급기에만 있다. X-H2/X-H2S의 FTP는 FT-XH가 필요하다는 것이 매뉴얼 원문이다 [확인됨 FUJ-8].
- XApp v2.3.5부터 폰이 잠자기 상태여도 Bluetooth 연결을 유지한다 [확인됨 FUJ-3].
- USB는 표준 PTP다. Android에서 "Connected to USB PTP"로 표시되고, iOS는 사진 앱으로 가져온다고 안내한다 [확인됨 FUJ-11].

**Panasonic**
- 공식 SDK는 Windows USB 베타 하나뿐이다. 무선 HTTP 프로토콜은 구형 기종을 리버스 엔지니어링한 자료만 있고, 파일당 약 10초가 걸리며 자주 실패한다는 보고가 있다 [일부 확인 PAN-11].
- Auto Transfer를 켜면 Frame.io와 다른 Wi-Fi 기능을 함께 쓸 수 없다 [확인됨 PAN-5].
- Frame.io 연결 방식은 출처끼리 충돌한다. GH7 매뉴얼은 iOS 개인용 핫스팟을 USB 테더링으로 쓸 수 있다고 하고, Frame.io 가이드는 "Tether only supported by S5IIX"라고 한다 [일부 확인 PAN-8, FIO-3].

**OM System**
- OI.Share 리버스 엔지니어링 자료: `get_imglist.cgi`로 목록을 받고, 원본은 `http://192.168.0.10/DCIM/...`로 직접 GET한다. 대상은 E-M10, TG-5이고, OM-1/OM-3에서 통하는지는 확인 못 했다 [일부 확인 OM-3].
- 외부 AP로 촬영 즉시 업로드하는 기능은 PC용 OM Capture 전용이다. 연결이 끊기면 아직 올리지 못한 데이터는 사라진다 [확인됨 OM-4].

**Leica**
- FOTOS 6.2.0은 iOS 18 이상이 필요하다. M11 계열의 백그라운드 전송은 프리뷰만 보내고, 원본 DNG는 나중에 수동으로 받아야 한다 [확인됨 LEI-1].
- Frame.io 지원은 SL3 계열뿐이고 M11과 Q3는 지원하지 않는다 [확인됨 LEI-3].

**Ricoh/Pentax, Sigma, Hasselblad**
- GR 시리즈: 공식 공개 API는 없다. 비공식 HTTP(thumb/view/full)로 동작하는 iOS 앱 GR Linker가 있다 [확인됨 RIC-3].
- Sigma fp와 BF는 무선이 없다. BF는 내장 메모리 230GB를 쓰고, iPhone에서 외부 드라이브로 보인다 [일부 확인 SIG-3].
- Hasselblad X2D II, X2D, CFV 100C는 Phocus Mobile 2 v3.6.0(2025-12)부터 iPhone USB-C 직결을 지원한다. Capture One 테더링은 2026년 말에 나올 예정이다 [확인됨 HAS-2, HAS-3].

---

## 2. 브랜드 공통 해법 비교

### 2-1. 비교표

| 해법 | 지원 범위 | 즉시성 | 원본 | 비용·라이선스 | App Store 위험 | 구현 난이도 |
|---|---|---|---|---|---|---|
| **A. 카메라 FTP → 앱 내장 FTP 서버** (핫스팟) | FTP 내장 중급기 이상(Sony, Canon R5/R6급, Nikon 신형, Fujifilm 고급기) | 높음. **포그라운드에서만** | 원본(카메라 설정을 따름) | 자체 구현이면 무료 | 낮음. 백그라운드를 억지로 유지하는 편법을 쓰면 2.5.4 위반 위험 | 중간 |
| **B. CascableCore SDK** (Wi-Fi/USB) | Canon, Nikon, Sony는 최신 기종까지. Fujifilm은 X-T4 세대, Panasonic은 GH5 세대까지 | 높음(셔터 이벤트를 받음). 포그라운드 필요(추측) | Canon, Nikon, 최신 Sony는 원본 | 상용, 가격 비공개, 번들 ID 단위 구독으로 추정 | 낮음. 다만 multicast entitlement 승인이 필요하다 | 낮음~중간 |
| **C. Canon CCAPI 직접 사용** | Canon CCAPI 기종(R8, R50처럼 FTP 없는 기종 포함) | 높음(long polling) | 원본 [일부 확인] | 무료. **한국 법인 신청 경로 불명** | 낮음 | 중간 |
| **D. Sony Camera Remote Command 직접 사용** | Sony 2020년 이후 기종 | 높음 | 원본(Background File Transfer) | 무료, 법인 한정 | 낮음 | 높음(PTP-IP를 직접 구현) |
| **E. libgphoto2 iOS 포트** (PTP/IP) | Canon EOS, Nikon, Fuji(실험적), 구형 Sony | 중간~높음 | 원본 | LGPL-2.1 | **중간~높음**(재링크 요건 논쟁) | 높음(포트가 낡았고 최신 기종 검증이 없음) |
| **F. USB-C + ImageCaptureCore** | PTP를 지원하는 대부분의 카메라 | 높음(기종마다 확인 필요) | 원본 | Apple 프레임워크, 무료 | 낮음 | 중간 |
| **G. 제조사 앱 → 사진 앱 → PhotoKit 감지** | 제조사 앱이 있는 전 브랜드 | **낮음**(백그라운드에서는 알림 없음) | Nikon 자동 전송은 축소본, Fujifilm·Sony는 원본 설정 가능 | 무료 | 낮음. 사진 전체 접근 권한이 필요 | 낮음. 대신 작가가 설정할 것이 많다 |
| **H. PHBackgroundResourceUploadExtension** (iOS 26.1 이상) | G와 같다 | 낮음~중간(시스템이 조건이 맞을 때 실행) | 사진 앱에 저장된 상태 그대로 | 무료 | 낮음 | 중간(이어받기 업로드를 받는 서버 필요) |
| **I. Frame.io C2C → 백엔드** | Fujifilm 12기종, Panasonic 6기종, Leica SL3 계열, Nikon(NX MobileAir 경유) | 중간(사진 업로드 목표는 10초 이내) | 원본 | Frame.io 요금. 서버끼리 인증은 Enterprise 필요로 보임 | 해당 없음. 대신 **Adobe 약관 위험** | 중간 |

### 2-2. A안: 카메라 FTP → 앱 내장 FTP 서버

- **선례**
  - Sony 공식 Transfer & Tagging(iOS)이 FTP 서버로 동작한다 ★SNY-3.
  - TetherDrop(iOS 16 이상)은 "USB-C, Wi-Fi (PTP/IP), or FTP"로 JPEG를 자동으로 받는다. 연결을 확인한 기종은 Canon EOS, Sony α, Nikon Z, Fujifilm GFX 일부다 ★COM-18.
  - ShutterSnitch는 내장 FTP와 WebDAV 서버를 둔다. 설정 가이드는 서버 주소 172.20.10.1, 포트 26000을 쓴다 [확인됨 COM-14].
  - PhotoSync는 FTP 서버 "Receive" 모드를 쓴다 [확인됨 COM-15].
- **iOS 제약**
  - 앱이 일시 중단(suspend)되면 리스닝 소켓이 처리를 멈춘다. 자원이 회수되면 앱이 다시 깨어나도 더는 리슨하지 않는다 [확인됨 IOS-19].
  - ShutterSnitch 가이드도 같은 운영을 요구한다. 자동 잠금 "안 함", 앱을 화면에 계속 띄워 두기, 저전력 모드 끄기다 [일부 확인 COM-14].
- **로컬 네트워크 권한**: 들어오는 TCP 연결을 받기만 하면 권한이 필요 없다 [확인됨 IOS-17]. 패시브 모드에서는 데이터 연결도 카메라 쪽에서 들어오므로 권한 팝업이 뜨지 않을 것으로 본다(추측). 액티브 모드는 앱이 밖으로 연결하므로 권한이 필요하다(추측).
- **자가 복구의 근거**: Sony a7C II는 FTP 서버 연결이 복구되면 미전송분을 자동으로 보낸다 ★SNY-5. Canon R5 II, R6 III는 실패하면 자동으로 재시도한다 [확인됨 CAN-8, CAN-10]. 앱이 잠깐 백그라운드로 가도 다시 돌아오면 카메라가 밀린 사진을 다시 밀어 넣을 수 있다(추측, 실증 필요).
- **구현 메모**(추측)
  - `NWListener`로 제어 포트(예: 2121)와 패시브 데이터 포트를 연다.
  - 최소 명령 세트는 `USER/PASS/SYST/FEAT/PWD/CWD/MKD/TYPE/PASV/EPSV/STOR/SIZE/NOOP/QUIT`이다. 카메라마다 실제로 쓰는 명령은 실측으로 확인한다.
  - FTPES는 카메라에 루트 인증서를 설치해야 해서 부담이 크다. Secure Protocol Off(평문)로 쓰되, 핫스팟 자체의 WPA2/WPA3 암호화에 기댄다. 계정은 작가별 무작위 비밀번호로 둔다.
  - 받은 파일은 앱 컨테이너에 저장하고 사진 앱에는 저장하지 않는다. 고객 사진의 개인정보를 보호하기 위해서다.
  - 서버 IP는 하드코딩하지 않는다. `getifaddrs`로 핫스팟 인터페이스 주소를 찾아 화면에 보여 준다. 핫스팟 대역 172.20.10.0/28은 [일부 확인]이다.

### 2-3. B안: CascableCore

- **지원과 배포**
  - 8개 제조사 250개 이상 기종을 Wi-Fi 또는 USB로 지원한다. SPM 바이너리로 배포하고, 최소 iOS 14, 최신 버전 18.0.2(2026-09-25)다 [확인됨 COM-1, COM-2].
- **새 사진 수신**
  - "Camera-Initiated Transfer" API는 셔터를 누를 때마다 요청 객체를 보낸다. preview(약 2~3MP)와 original 중에서 고른다 [확인됨 COM-4].
  - `executionRequiredToClearBuffer`가 true인 요청은 반드시 처리해야 한다. 처리하지 않으면 카메라가 멈춘다 [확인됨 COM-2, 15.0 릴리스 노트].
- **최신 기종 지원**
  - R5 II(14.1, 동작에 "eccentricities"가 있다고 명시), R6 II, R8, R50, a7C II, a7R V, a6700, Z8, Zf가 들어 있다 [확인됨 COM-2].
  - Sony 메모리카드 파일 전송은 17.0(2025-12)에 추가됐다. a7C II는 카메라 펌웨어 2.0.0 이상이 필요하다 [확인됨].
- **지원 공백**
  - Fujifilm은 X-T4, X100V가 마지막이다. Wi-Fi로 RAW를 받을 수 없고 촬영 즉시 표시도 지원하지 않는다. Panasonic은 G9, GH5가 마지막이다 [확인됨 COM-5].
- **라이선스와 가격**
  - 30일 평가판이 있다. 17.1(2026-03)부터 번들 ID 단위로 온라인 활성화를 하고, 구독형 과금으로 보인다 [일부 확인].
  - **가격은 공개하지 않는다. 사용자 확인이 필요하다.**
- **통합 요건**
  - Info.plist에 `NSLocalNetworkUsageDescription`, `NSBonjourServices`(`_ptp._tcp`), `NSAllowsLocalNetworking`을 넣는다.
  - SSDP를 쓰는 카메라(Canon 스마트폰 모드, 일부 Sony, 대부분의 Panasonic)는 **Apple이 승인해야 하는 multicast entitlement**가 필요하다.
  - SDK는 메인 스레드에서만 호출해야 한다 [확인됨 COM-1].

### 2-4. E안: libgphoto2와 LGPL

- **PTP/IP 지원 범위** [확인됨 COM-7]
  - 지원 대상: 범용 PTP/IP, Ricoh Theta, Nikon (WLAN), Canon EOS (WLAN), Fuji X (WLAN, 소스에 "might be buggy"라고 적혀 있음).
  - Panasonic은 별도 HTTP 드라이버를 쓰는데, 촬영 기능이 완성되지 않았다.
  - 최신 Sony의 암호화된 Wi-Fi 연결을 지원하는지는 확인 못 했다.
- **iOS 포트**
  - touchbyte/GPhoto2Framework는 PTP/IP만 지원하고, 마지막 갱신이 2022-08이다. PhotoSync가 이것을 쓴다. 다만 PhotoSync의 Canon Wi-Fi 지원 목록은 EOS R, RP 같은 구형에서 멈춰 있다 [확인됨 COM-8].
- **LGPL-2.1 제6조**(법률 자문 아님)
  - 사용자가 직접 수정하고 다시 링크할 수 있게 해야 한다. 방법은 셋 중 하나다. (a) 앱 오브젝트 파일과 소스를 제공한다. (b) 사용자가 교체할 수 있는 공유 라이브러리로 넣는다. (c) 3년간 유효한 서면 제공 약속을 한다 [확인됨 COM-9].
  - iOS에서는 서명 때문에 사용자가 프레임워크를 교체할 수 없다. 그래서 (b)를 충족하기 어렵다는 견해가 많다 [일부 확인 COM-10].
  - 선례: FSF 대 GNU Go(2010, GPL), VLC(2011년 철수 → 재라이선스 → 2013년 복귀) [확인됨 COM-12].
  - **출시하려면 법무 검토가 필요하다.**

### 2-5. 그 밖의 오픈소스

- petabyt/libpict(구 camlib): C 언어 PTP 라이브러리로 **Apache-2.0**이다. README에 "PTP/IP tested on … iOS"라고 적혀 있다. 안정 릴리스는 없다 [확인됨 COM-13].
- Fujifilm용 리버스 엔지니어링 프로젝트(fudge, fuji-cam-wifi-tool, ptp-ip Go 구현)는 라이선스가 불명확하거나 활동이 멈췄다 [확인됨 COM-13].
- Swift 네이티브 PTP/IP 패키지는 찾지 못했다 [확인 못 함].

### 2-6. F안: USB-C + ImageCaptureCore

- **API 가용 범위** [확인됨 IOS-28]
  - iOS 13 이상: `ICDeviceBrowser`, `ICCameraDevice`, `cameraDevice(_:didAdd:)`, `requestDownloadFile`, `ptpEventHandler`, `requestSendPTPCommand`
  - iOS 14 이상: `requestContentsAuthorization`, `requestControlAuthorization`
  - **`requestTakePicture()`는 macOS 전용이다.** iOS에는 공식 원격 셔터가 없다.
- **알려진 결함** [일부 확인 IOS-29]
  - iOS 13.6에서 `requestSendPTPCommand`가 "NotAuthorized" 오류를 냈다.
  - iOS 18에서는 권한 요청이 팝업 없이 바로 `denied`로 끝났다.
  - iOS 26.1 베타에서는 요청이 항상 `notDetermined`로 끝났다(FB20415228).
  - 현재 해결됐는지는 확인 못 했다.
- **상용 사례**: Capture One iOS(550개 이상 기종 유선·무선 테더링)와 TetherDrop(USB-C)이 있다 [확인됨 COM-19, COM-18].
- **속도**: USB 3는 iPhone 15 Pro 이후 Pro 모델만 지원하고, 나머지는 USB 2다. iPhone은 USB-C로 연결한 기기에 최대 4.5W를 공급한다 [확인됨 IOS-30].
- **판단**(추측): 촬영 즉시 수신용으로 쓰려면 작가가 카메라와 폰을 케이블로 묶고 다녀야 한다. 관광지 스냅에서는 일괄 전송(2차안) 용도가 현실적이다.

### 2-7. G·H안: 제조사 앱 → 사진 앱 → PhotoKit

- **변경 알림이 오는 시점**
  - `PHPhotoLibraryChangeObserver`는 앱이 백그라운드이거나 종료된 동안에는 알림을 주지 않는다. 포그라운드로 돌아오면 그동안의 변경을 한꺼번에 알려 준다(Apple Frameworks Engineer 답변) [확인됨 COM-21].
  - iOS 16 이상의 `fetchPersistentChanges(since:)`로 나중에 따라잡을 수는 있다.
- **권한**: 제한 접근(limited library) 상태에서는 사용자가 고른 에셋만 보인다. 따라서 이 우회에는 **사진 전체 접근 권한이 필수**다 [확인됨 COM-22].
- **PHBackgroundResourceUploadExtension**(iOS 26.1 이상, iOS 27에서는 async Job 확장으로 대체) [확인됨 COM-23]
  - 시스템이 대신 업로드하지만 "조건이 허락할 때" 실행하므로 즉시성이 없다.
  - 사진 전체 접근 권한이 있어야 한다.
  - iCloud 사진이 켜져 있으면 확장이 스케줄되지 않는다는 버그 보고가 있다 [일부 확인].
- **제조사 앱 자체도 백그라운드 제약을 받는다.**
  - SnapBridge는 iOS가 백그라운드 자동 다운로드를 멈출 수 있다고 직접 안내한다 [확인됨 NIK-6].
- **판단**: 즉시 전송 경로로는 부적합하다. 다만 앞의 해법들이 막힌 브랜드(Fujifilm 보급기, Panasonic)에서 "작가 앱이 포그라운드인 동안 사진 앱 변경을 감지해 올리는" 보조 수단으로는 쓸 수 있다(추측).

### 2-8. I안: Frame.io C2C를 백엔드와 연동

- **C2C 지원 스틸 카메라** [확인됨 FIO-1~5]
  - Fujifilm 12기종, Panasonic 6기종, Leica SL3·SL3-S·SL3-P
  - Nikon Z9·Z8·Z6III·ZR(NX MobileAir 경유)
  - Canon은 시네마 기종의 프록시 영상만, Sony는 네이티브 지원 없음
- **웹훅** [확인됨 FIO-9]
  - V4 웹훅은 **베타**다. 이벤트는 `file.created`, `file.upload.completed`, `file.ready` 등이고, 워크스페이스 단위로 받는다.
  - 서명은 HMAC-SHA256이다. 재시도는 5회이고, 5초 안에 응답하지 않으면 실패로 본다.
  - 페이로드에는 ID만 들어 있어서 내용은 API로 다시 조회해야 한다.
- **원본 다운로드**: `include=media_links.original`을 붙이면 서명된 URL을 준다. 최대 24시간 뒤 만료된다 [확인됨 FIO-10].
- **인증**
  - Adobe IMS OAuth를 쓴다.
  - 사람 없이 서버끼리 연동(Server-to-Server)하는 것은 Adobe Admin Console이 관리하는 계정에서만 된다. 포럼 스태프는 "Enterprise만"이라고 답했다. 개발자 FAQ와 포럼 답변이 서로 충돌한다 [일부 확인 FIO-11].
- **티켓과 매핑**
  - C2C 디바이스는 프로젝트 하나에 묶이고, 업로드 경로는 `Cloud_Devices > 날짜 > 디바이스`로 고정된다 [확인됨 FIO-14, 레거시 문서 기준].
  - 티켓별로 업로드할 폴더를 지정할 수는 없다. 백엔드가 디바이스, 촬영 시각, 티켓 시간 창을 대조해 매핑해야 한다(추측).
- **약관**: Adobe 일반 약관 6.4는 "호스팅 서비스의 일부로 쓰는 것"과 "제3자를 대신해 쓰는 것"을 금지한다 [확인됨 FIO-16]. B2C 서비스의 중간 저장소로 쓰면 충돌할 위험이 있다(추측, 법률 검토 필요).
- **요금**: Pro는 멤버당 월 $15, Team은 멤버당 월 $25이고 최대 15명이다. C2C는 "모든 플랜에 포함"이라고 하지만, Fujifilm 페이지는 "any paid account"라고 써서 서로 다르다 [일부 확인 FIO-8].
- **판단**: 해당 기종을 쓰는 작가용 보조 경로나 파일럿에 한정해 검토한다.

### 2-9. 참고: 같은 문제를 이미 푼 iOS 앱

| 앱 | 수신 방식 | 확인된 점 | 출처 |
|---|---|---|---|
| Sony Transfer & Tagging | 앱 내장 FTP 서버 | 원본, 핫스팟·AP·USB 테더링, iOS는 포그라운드 필요 | ★SNY-3 |
| TetherDrop | USB-C, PTP/IP, FTP | JPEG 자동 수신, Canon·Sony·Nikon·Fujifilm GFX 일부, 구독제 | ★COM-18 |
| Camera Connect & Control | PTP/IP, Sony는 Camera Remote Command | 폰 핫스팟 연결 지원, 자동 다운로드 설정 | ★COM-17 |
| ShutterSnitch | FTP, WebDAV, PTP/IP | 핫스팟 172.20.10.1, 화면 켜 두기 필요(가이드 기준) | COM-14 |
| PhotoSync | FTP 수신, libgphoto2 PTP/IP | 카메라 Wi-Fi에 붙어 있으면서 셀룰러로 업로드하는 설정을 안내 | COM-15 |
| Cascable Studio | CascableCore | Storage Links로 받는 즉시 다른 저장소로 복사 | COM-6 |
| Capture One iOS | 유선·무선 테더링 | 550개 이상 기종, iOS 17 이상 | COM-19 |
| Camera Port - Background FTP | FTP | "화면이 잠겨도 백그라운드 동작"을 주장하지만 방식은 비공개. 2.5.4 위험이 있을 수 있다(추측) | COM-16 |

---

## 3. iOS 제약

### 3-1. 요약표

| 항목 | 판정 | 핵심 근거 | 십분스냅 영향 |
|---|---|---|---|
| Wi-Fi Direct 직접 사용 | **불가** | Quinn: "not Wi-Fi Direct" [확인됨 IOS-1], TN3111 | 제조사가 말하는 "Wi-Fi Direct"는 실제로 카메라 AP 접속(a)이다 [확인됨 SNY-15] |
| Wi-Fi Aware (iOS 26 이상) | **현재 사실상 불가** | iPhone 12 이상, 카메라가 Wi-Fi Aware 4.0 인증을 받고 PIN 페어링을 구현해야 함 [확인됨 IOS-3, IOS-4]. 지원을 발표한 카메라는 찾지 못함 | 장기적으로 추적만 한다 |
| AccessorySetupKit (iOS 18 이상) | 조건부 | `joinAccessoryHotspot`은 `joinOnce`가 강제됨 [확인됨 IOS-6] | 카메라 AP 접속 UX를 개선할 수 있다. iOS 17은 대체 경로가 필요하다 |
| NEHotspotConfiguration | 조건부 | 적용할 때마다 사용자 팝업. `joinOnce`는 백그라운드 15초나 슬립 때 해제 ★IOS-8 | (a) 방식은 포그라운드에서 화면을 켜 둬야 한다 |
| 카메라 Wi-Fi 접속 중 셀룰러 업로드 | 조건부 | `NWParameters.requiredInterfaceType = .cellular`는 가능. 기본 경로가 어디로 갈지는 기종과 iOS 버전에 따라 다름(DTS) [확인됨 IOS-12] | (a) 방식에서 업로드가 실패할 위험이 있다 |
| URLSession·Firebase Storage 셀룰러 강제 | **불가** | `allowsCellularAccess`는 막는 용도뿐 [확인됨 IOS-12]. Firebase는 GTMSessionFetcher(URLSession) 기반 [확인됨 IOS-15] | 핫스팟 방식을 택하는 핵심 이유다 |
| 로컬 네트워크 권한 | 나가는 연결에만 필요 | 수신 전용 TCP는 필요 없음 [확인됨 IOS-17] | FTP 수신은 팝업이 없을 것으로 본다. CCAPI, PTP/IP처럼 앱이 나가서 연결하면 팝업이 뜬다 |
| 백그라운드 FTP 리스닝 / PTP/IP 유지 | **불가** | "You can't" ★IOS-18, TN2277 [확인됨 IOS-19] | 촬영하는 동안 앱을 포그라운드에 두고 화면을 켜 둬야 한다 |
| 백그라운드 URLSession 업로드 | 가능(파일 기반, 지연될 수 있음) | 백그라운드에서 시작한 전송은 시스템 재량(discretionary)으로 처리 [확인됨 IOS-20] | 받은 파일은 포그라운드에 있을 때 바로 업로드 작업으로 등록한다 |
| BGContinuedProcessingTask (iOS 26 이상) | 조건부 | 사용자가 시작해야 하고 진행률을 보고해야 함. 화면 잠금 시 멈추는 버그 보고 [확인됨 IOS-21] | 2차안 일괄 업로드를 보강한다 |
| 오디오·위치 백그라운드 모드 | **불가**(거절 위험) | 가이드라인 2.5.4 [확인됨 IOS-22] | 쓰지 않는다 |
| Live Activity로 앱 유지 | **불가** | 자체 샌드박스에서 돌고 실행 시간을 주지 않음 [일부 확인 IOS-23] | 진행 상태를 표시하는 데만 쓴다 |
| 개인용 핫스팟 제어 | **불가** | "has no API surface"(Quinn) [확인됨 IOS-25] | 작가가 직접 켜야 한다 |
| 핫스팟 클라이언트 → 앱 FTP 서버 | 조건부(DTS는 권장하지 않음) | 지원 API가 없고 IP에 의존 [확인됨 IOS-25]. 서드파티 앱 사례는 있음 | 실기 검증이 필요하다 |
| USB-C ImageCaptureCore | 조건부 | iOS 13 이상 API. 권한 결함 보고 [일부 확인 IOS-29] | 2차안의 유력 후보 |
| USB 원격 셔터 | **불가** | `requestTakePicture`는 macOS 전용 [확인됨 IOS-28] | 셔터는 카메라에서 직접 누른다 |

### 3-2. Wi-Fi Direct, Wi-Fi Aware, AccessorySetupKit

- **Wi-Fi Direct**: iOS는 서드파티 앱에 Wi-Fi Direct를 제공하지 않는다.
  - TN3111이 정리한 P2P 선택지는 Wi-Fi Aware와 Apple 기기 전용 P2P뿐이다 [확인됨 IOS-1, IOS-2].
  - Sony가 말하는 "Wi-Fi Direct"는 카메라가 `DIRECT-xxxx` SSID를 띄우는 AP 방식이다 [확인됨 SNY-15].
- **Wi-Fi Aware 앱 쪽 요건** [확인됨 IOS-3]
  - iOS 26 이상, iPhone 12 이상
  - entitlement `com.apple.developer.wifi-aware`와 Info.plist의 `WiFiAwareServices`. 서비스 이름이 잘못되면 앱이 크래시한다.
  - 연결 전에 AccessorySetupKit이나 DeviceDiscoveryUI로 페어링해야 한다.
- **Wi-Fi Aware 카메라 쪽 요건** [확인됨 IOS-4]
  - Apple Accessory Design Guidelines R31 56장에 Wi-Fi Aware Specification 4.0 인증, NIK 캐싱, 6자리 PIN 페어링이 요구사항으로 나온다.
  - 사용 예시로 "Smart cameras transferring photos or videos"를 들고 있어 의도는 맞는다.
  - 하지만 카메라 펌웨어가 직접 구현해야 한다. 지원을 발표한 제조사는 찾지 못했다 [확인 못 함].
- **알려진 버그**: iOS 26.5에서 ASError 450이 발생했고, 26.6 beta 4에서 고쳐졌다 [확인됨 IOS-5].
- **AccessorySetupKit**
  - `ssid` 또는 `ssidPrefix`로 액세서리를 찾는다. 둘 다 지정하면 크래시한다.
  - 접속할 때는 `joinAccessoryHotspot`을 써야 한다. 기존 `apply()`를 쓰면 Code 17 오류가 난다.
  - `joinOnce`가 강제되므로 백그라운드 제약은 똑같이 적용된다 [확인됨 IOS-6].

### 3-3. NEHotspotConfiguration

- **권한과 팝업**
  - Hotspot Configuration capability는 승인 없이 쓸 수 있는 unmanaged entitlement다.
  - 구성을 적용할 때마다 사용자 승인 팝업이 뜬다.
  - completion이 호출됐다고 해서 IP 설정까지 끝난 것은 아니다 [확인됨 IOS-7].
- **`joinOnce=true`가 해제되는 조건** ★IOS-8
  - 앱이 백그라운드에 15초 넘게 있을 때
  - 기기가 잠들 때
  - 앱이 크래시하거나 종료되거나 삭제될 때
  - 다른 Wi-Fi에 접속할 때
- **인터넷 없는 액세서리 네트워크**
  - `joinOnce=true`가 맞다. `false`면 연결이 붙었다 떨어지기를 반복할 수 있다 [확인됨 IOS-9, Quinn 2026].
  - iOS 26에서 세션 도중 인터넷이 되는 저장 네트워크로 넘어가 버리는 문제가 보고됐다. DTS는 이를 막는 방법을 제시하지 않았다.
- **SSID 접두어 접속**: `ssidPrefix`(예: `DIRECT-`)로 접속할 수 있다 [확인됨 IOS-9].
- **현재 SSID 확인**: `fetchCurrent`는 wifi-info entitlement가 필요하다. 그리고 정밀 위치 권한이 있거나, 그 네트워크를 이 앱이 NEHotspotConfiguration으로 구성했어야 한다 [확인됨 IOS-11].

### 3-4. 카메라 Wi-Fi에 붙은 상태에서 셀룰러로 업로드하기

- **기본 경로**
  - Wi-Fi와 셀룰러 인터페이스는 동시에 살아 있을 수 있다.
  - 인터넷이 없는 네트워크에 수동으로 접속하면 보통 기본 경로는 셀룰러에 남는다.
  - 하지만 카메라가 DHCP로 게이트웨이를 알려 주면 기본 경로를 가져갈 수 있다.
  - Quinn은 "특정 iOS 버전과 특정 액세서리 조합으로 시험하는 것만이 확실한 방법"이라고 했다 [확인됨 IOS-12].
- **연결 계층별로 할 수 있는 것**
  - Network.framework: `requiredInterfaceType = .cellular`로 강제할 수 있고, 카메라 연결에는 `prohibitedInterfaceTypes = [.cellular]`를 쓸 수 있다 [확인됨 IOS-12].
  - URLSession: 셀룰러를 강제할 수 없다. 우회책은 MPTCP(entitlement와 서버 지원 필요)나 HTTP를 직접 구현하는 것이다 [확인됨 IOS-12, IOS-13].
  - Firebase Storage: 인터페이스를 지정할 통로가 없다(추측, IOS-15).
  - AWS SDK for Swift: `httpClientEngine`에 직접 만든 HTTP 클라이언트를 넣을 수 있다 [확인됨 IOS-16]. Network.framework 기반 셀룰러 전용 클라이언트를 만들어 넣는 것은 가능해 보이지만 구현량이 크다(추측).
  - 서명된 업로드 URL을 받아 직접 만든 `NWConnection` HTTP로 올리는 방법도 있다(추측).
- **PhotoSync 우회**: 카메라 Wi-Fi에서 IP를 수동으로 설정해 iOS가 셀룰러로 인터넷을 쓰게 한다 [확인됨 COM-15]. 작가에게 시키기에는 부담이 크다(추측).

### 3-5. 로컬 네트워크 권한 (TN3179)

- **권한이 필요한 동작과 아닌 동작**
  - 필요: 로컬 주소로 나가는 TCP 연결, UDP 송신, Bonjour, `.local` 이름 해석
  - 불필요: 들어오는 TCP 연결을 받기만 하는 것
  - 멀티캐스트를 쓰면 별도로 `com.apple.developer.networking.multicast` entitlement가 필요하다 [확인됨 IOS-17].
- **팝업과 거부 처리**
  - 팝업은 앱이 포그라운드일 때만 뜬다. 권한을 미리 확인하거나 띄우는 API는 없다.
  - 거부되면 `NWConnection`이 `.waiting` 상태가 되고 이유는 `.localNetworkDenied`로 나온다.
  - iOS 18에는 권한 상태가 꼬이는 버그가 있었고 18.6에서 고쳐졌다 [확인됨 IOS-17].
- **십분스냅에 적용하면**
  - FTP 수신 전용이면 팝업이 뜨지 않을 것으로 본다.
  - CCAPI, CascableCore, PTP/IP처럼 앱이 나가서 연결하면 첫 연결 때 팝업이 뜬다. 연결 마법사 안에서 이 팝업을 유도하는 편이 좋다(추측).

### 3-6. 백그라운드 실행

- **범용 백그라운드 실행은 없다.** 네트워크 요청이 와도 앱을 깨우는 일반 메커니즘이 없다 ★IOS-18.
- **소켓**: 리스닝 소켓은 백그라운드로 갈 때 닫으라고 권한다. 데이터 소켓도 회수될 수 있고, 화면 잠금이 회수를 일으킨다 [확인됨 IOS-19].
- **백그라운드 URLSession**
  - 별도 프로세스에서 전송하고, 파일 기반 업로드만 된다.
  - 사용자가 앱을 강제 종료하면 취소된다.
  - 앱이 백그라운드일 때 시작한 전송은 늦어질 수 있다 [확인됨 IOS-20].
- **BGProcessingTask**: 주로 밤사이에 실행되므로 즉시 업로드에는 맞지 않는다 [확인됨 IOS-18].
- **BGContinuedProcessingTask**(iOS 26 이상)
  - 버튼 탭 같은 사용자 동작으로 포그라운드에서 제출해야 한다. 시스템 UI에 진행률이 표시되고 사용자가 취소할 수 있다.
  - 화면이 잠기면 멈추는 버그가 있었다. DTS는 26.1에서 고쳐졌어야 한다고 했지만, S3 업로드 사례에서는 26.2 beta 3에서도 재현됐다는 보고가 있다 [확인됨 IOS-21, 최종 해결 여부는 확인 못 함].
- **오디오·위치 백그라운드 모드를 카메라 수신에 쓰는 것**은 가이드라인 2.5.4의 "의도된 목적" 조항에 어긋난다 [확인됨 IOS-22].
- **`isIdleTimerDisabled`**: 포그라운드에서 자동 잠금을 막을 수 있다. 촬영 세션 동안에만 켜고 끝나면 되돌린다 [확인됨 IOS-24].

### 3-7. 개인용 핫스팟

- **앱이 할 수 없는 것**: 앱은 핫스팟을 켜거나 끌 수 없고 상태도 조회할 수 없다 [확인됨 IOS-25].
- **DTS 입장**
  - 아이폰을 서버처럼 쓰는 구조는 권장하지 않는다. 지원 API가 없고, IP에 의존해야 하고, 연결 유지가 불안정하기 때문이다.
  - 대신 AccessorySetupKit이나 Wi-Fi Aware로 아이폰이 액세서리 쪽에 붙는 구조를 권한다 [확인됨 IOS-25].
- **사용자 조작**: 다른 기기가 접속하려면 "다른 사용자의 연결 허용"을 켜고, 연결될 때까지 그 설정 화면에 머물러야 한다 [확인됨 IOS-26].
- **자동 꺼짐**: 연결된 기기가 없으면 약 90초 뒤 핫스팟이 꺼진다는 보고가 있다. Apple 공식 문서는 아니다 [일부 확인 COM-14].
  - 2026-10-19 정정: Apple 공식 문서(2025-10-22 게시)의 원문은 "Third-party devices automatically disconnect after 90 seconds without network traffic."이다. 핫스팟이 꺼지는 것이 아니라, **트래픽이 90초 없으면 카메라 같은 서드파티 기기의 연결이 끊긴다** ★DC-I12. 상세는 [camera-direct-connection.md](camera-direct-connection.md) 5-1에 있다.
- **호환성 최대화**: 켜면 2.4GHz로 동작하고 성능과 보안이 낮아질 수 있다 [확인됨 IOS-26].
- **통신사**: 통신사가 핫스팟을 활성화했고 요금제가 이를 지원해야 한다 [확인됨 IOS-26].
  - 국내 요금제별 테더링 한도는 2022년 기사로만 확인했다 [일부 확인 IOS-27].
  - 카메라에서 아이폰으로 가는 전송은 로컬 구간이라 셀룰러를 쓰지 않는다. 그래서 테더링 한도에 잡히지 않을 것으로 본다(추측).
- **IP 대역**: 172.20.10.0/28, 게이트웨이 172.20.10.1(아이폰)이다 [일부 확인, Apple 공식 문서 없음].

### 3-8. USB-C ImageCaptureCore

2-6에서 정리했다. 덧붙일 점은 다음과 같다.
- iOS에서 테더링하려면 Info.plist에 `NSCameraUsageDescription`을 넣어야 한다 [확인됨 IOS-28].
- 백그라운드에서 동작하는지는 확인 못 했다. 앱이 일시 중단되면 멈출 것으로 본다(추측).

---

## 4. 십분스냅에 권하는 구조

### 4-1. 결론

> **보완(2026-10-19)**: 이 절을 쓸 때는 카메라가 핫스팟의 셀룰러 인터넷을 써서 우리 서버의 FTPS로 직접 올리는 경로를 비교하지 않았다. 이 경로는 아래 R1(포그라운드 필수) 위험을 피한다. 대신 테더링 데이터 한도, 서버 비용, TLS 세션 재개 호환성 같은 새 위험이 생긴다. 비교와 실증 순서는 [Android 문서](camera-wireless-transfer-android.md) 4·5장에 있다. 사용자는 초기에 서버 없이 이 절의 1차안으로 가기로 정했다(2026-10-19).

- **1차안(즉시 전송)**: 핫스팟에서 앱 내장 FTP 서버로 받는다.
  - 카메라를 아이폰 개인용 핫스팟에 붙이고, 카메라 내장 FTP 자동 전송으로 원본을 작가 앱의 내장 FTP 서버에 밀어 넣는다.
  - 작가 앱은 받은 파일을 그 순간 활성화된 촬영 티켓에 묶어 셀룰러로 업로드한다.
  - FTP가 없는 기종은 Pull 어댑터(CCAPI 또는 CascableCore)로 보완할지 따로 결정한다.
- **2차안(일괄 전송)**: USB-C 유선에서 ImageCaptureCore로 가져온다.
  - 촬영이 끝나면 케이블을 연결하고, 티켓 시간 창에 든 파일을 골라 원본을 가져와 업로드 큐에 넣는다.
  - FTP 기종은 카메라의 "일괄 전송" 메뉴로 Wi-Fi 일괄 전송도 할 수 있다.
- **공통**: 업로드는 파일 기반 큐로 하고, 포그라운드에서 백그라운드 URLSession 작업으로 등록한다. iOS 26 이상에서는 일괄 전송 버튼에 `BGContinuedProcessingTask`를 붙인다.

### 4-2. 연결 구조: 핫스팟을 중심에 두는 이유

| 비교 | (a) 아이폰이 카메라 AP에 접속 | (b) 카메라가 아이폰 핫스팟에 접속 |
|---|---|---|
| 서버 업로드 경로 | 셀룰러로 강제해야 한다. URLSession과 Firebase로는 불가. 기본 경로는 기종과 iOS 버전에 따라 다르다 | 셀룰러가 유일한 인터넷 경로다. 기존 SDK를 그대로 쓴다 |
| 서드파티 프로토콜 | 제조사 앱 전용이 대부분이다. Sony Camera Remote Command(법인)와 CascableCore만 남는다 | 카메라 FTP(공식 기능)와 Canon CCAPI(인프라 모드)를 쓸 수 있다 |
| 연결 유지 | `joinOnce`는 백그라운드 15초나 잠금 때 끊긴다 | 핫스팟은 연결된 기기가 있으면 유지된다. 앱 수신은 여전히 포그라운드가 필요하다 |
| 작가가 할 일 | 앱이 NEHotspotConfiguration으로 자동 접속한다(팝업 1회) | 설정에서 핫스팟을 켜고, 카메라에 FTP 서버를 처음 한 번 등록한다 |
| 요금제 | 상관없다 | 요금제가 핫스팟을 막으면 쓸 수 없다 |
| 공식 선례 | — | Sony Transfer & Tagging |

(b) 방식이 업로드 경로, 브랜드 범위, 공식 선례 세 가지에서 앞선다. 단점은 작가가 직접 조작해야 하는 것과 요금제에 따라 막힐 수 있다는 것이다. 이 둘은 첫 연결 마법사와 사전 점검으로 줄인다(추측).

### 4-3. 1차안: 즉시 전송 흐름(초안)

1. **티켓 승인 → 촬영 세션 시작**
   - 앱이 `isIdleTimerDisabled`를 켜서 자동 잠금을 막는다.
   - 수신 화면을 띄운다(현재 티켓, 수신 장수, 업로드 상태).
2. **연결 점검**
   - 앱이 핫스팟 인터페이스 주소를 확인해 화면에 보여 준다.
   - 카메라에 등록할 FTP 값(IP, 포트, 계정, Passive On, Secure Off)을 한 화면에 정리해 둔다. 이 값은 처음 한 번만 설정하면 된다.
3. **수신**
   - `NWListener` 기반 FTP 서버로 `STOR`를 받는다.
   - 파일을 `Application Support/Inbox/<ticketId>/`에 원자적으로 저장한다.
   - 메타데이터를 기록한다: 원본 파일명, 수신 시각, EXIF `DateTimeOriginal`, 카메라 `Make`/`Model`/시리얼(있으면).
4. **티켓 귀속**
   - 수신하는 순간 활성화된 티켓에 묶는다.
   - 카메라의 FTP 디렉터리 설정은 티켓마다 바꾸기 어렵다. 그래서 디렉터리로 구분하지 않고 앱의 세션 상태로 귀속한다(추측).
   - 세션을 닫은 뒤 늦게 들어온 파일은 EXIF 촬영 시각과 티켓 시간 창을 대조해 귀속한다. 맞는 티켓이 없으면 "미분류"로 둔다.
5. **업로드**
   - 받은 즉시 업로드 큐에 넣는다. 포그라운드에서는 바로 올리고, 실패하면 파일 기반 백그라운드 URLSession으로 재시도한다.
   - 서버 쪽은 업로드가 끝나면 티켓 컨테이너에 연결한다. 고객 앱에 알릴지는 메인 설계에서 정한다.
6. **백그라운드로 갔을 때**
   - 리스너를 닫는다. 다시 포그라운드로 오면 리스너를 다시 연다.
   - 카메라가 미전송분을 자동으로 다시 보내는지 실증한다. Sony는 연결 수립 실패 시 복구 후 자동 전송, Canon은 자동 재시도가 문서에 있다.
7. **(선택) Pull 어댑터**
   - FTP가 없는 Canon 기종: CCAPI의 `event/polling`으로 새 파일을 감지하고 `/contents`에서 받는다.
   - 또는 CascableCore의 Camera-Initiated Transfer를 쓴다.
   - 수신 계층을 "어댑터 프로토콜 + FTP 구현체" 구조로 두면, 나중에 Pull 어댑터를 더할 때 업로드와 귀속 코드를 다시 쓸 필요가 없다(추측).

### 4-4. 2차안: 일괄 전송 흐름(초안)

1. 작가가 "한 번에 전송"을 누른다.
2. 수집 방법
   - **USB-C**: `ICDeviceBrowser`로 카메라를 찾는다 → `requestContentsAuthorization` → 파일 목록 중 티켓 시간 창에 든 것만 고른다 → `requestDownloadFile`로 원본을 받는다.
   - **Wi-Fi(FTP 기종)**: 카메라의 일괄 전송 메뉴(Sony `batch_transfer` 등)로 앱 FTP 서버에 보낸다.
   - **제조사 앱 경유(나머지 기종)**: 작가가 제조사 앱으로 사진 앱에 원본을 저장하게 한다 → 앱이 PhotoKit에서 시간 창에 든 에셋을 골라 가져온다. 사진 전체 접근 권한이 필요하다.
3. 업로드: 파일 기반 백그라운드 URLSession으로 올린다. iOS 26 이상에서는 `BGContinuedProcessingTask`로 진행률을 보여 주며 계속 진행한다.
4. 중복 제거: 원본 파일명, 촬영 시각, 크기를 조합한 키로 1차에서 이미 올린 파일을 건너뛴다(추측).

### 4-5. 기종별 경로 배정(초안)

| 기종군 | 1차 즉시 | 2차 일괄 | 근거 |
|---|---|---|---|
| Sony FTP 내장기(a7C II, a7 IV, a7R V, a9 III, a1 II, a7 V, a7S III, a7CR 등) | 핫스팟 + 앱 FTP | USB-C(실증 필요) 또는 FTP 일괄 전송 | SNY-3~7 |
| Canon R1, R3, R5, R5 II, R6, R6 II, R6 III, R6 V | 핫스팟 + 앱 FTP | USB-C(R5 II, R6 III는 iOS 사진 앱용 모드) | CAN-8~14, CAN-18 |
| Nikon Z9, Z8, Z6III, Zf, Z5II, Z50II, ZR, Z5IIC | 핫스팟 + 앱 FTP(**서드파티 FTP 서버는 공식 지원 밖**, 실증 필요) | USB-C(MTP/PTP 모드의 iOS 동작 확인 필요) | NIK-8~10 |
| Fujifilm GFX100 II, GFX100S II, X-H2/X-H2S(FT-XH 장착) | 핫스팟 + 앱 FTP | USB-C(표준 PTP) | FUJ-6~8, FUJ-11 |
| Canon R7, R8, R50, R50 V / Sony a6700 등 FTP 미지원기 | 선택: Canon CCAPI(가입 경로 확인 필요) 또는 CascableCore(평가 필요). 하지 않으면 즉시 전송 미지원 | USB-C | CAN-3, COM-2 |
| Fujifilm X-T5, X100VI, X-T50, X-S20 등 | 즉시 경로 없음(공식 앱 경유만 가능) | USB-C(표준 PTP) | FUJ-1, COM-5 |
| Panasonic, OM System, Leica, Ricoh/Pentax, Sigma, Hasselblad | 즉시 경로 없음 | USB-C(기종마다 PTP 여부 확인) 또는 제조사 앱 경유 | 1-2 표 |

Sony a6700에 FTP가 없다는 것은 공통 해법 조사 에이전트가 매뉴얼 목차로 확인했다는 보고만 있다. 원문 URL은 확보하지 못해 [일부 확인]으로 둔다.

### 4-6. Sony a7C II 실증 체크리스트(sbsn_main 참고)

1. **기준선 확보**: 먼저 Sony 공식 **Transfer & Tagging**으로 핫스팟 + FTP 수신이 되는지 확인한다. 그러면 카메라·핫스팟 설정 문제와 우리 앱 구현 문제를 나눠 볼 수 있다.
2. **핫스팟 설정**: "다른 사용자의 연결 허용"을 켠다. "호환성 최대화"(2.4GHz)가 필요한지 확인한다.
3. **카메라 FTP 설정**: Host는 핫스팟 인터페이스 IP, Port는 앱 리스닝 포트, Secure Protocol Off, Passive Mode On, 전송 대상은 `JPEG & HEIF`, `Auto FTP Transfer` On.
4. **지연 측정**
   - 셔터를 누른 뒤 앱이 파일을 다 받을 때까지
   - 앱이 받은 뒤 서버 업로드가 끝날 때까지
   - 연속 10장, 30장
5. **FTP 명령 기록**: 카메라가 실제로 보내는 FTP 명령 순서를 로그로 남긴다. 최소 명령 세트를 정하는 근거가 된다.
6. **복구 동작**
   - 앱을 10초, 20초, 60초 백그라운드에 둔 뒤 돌아와서, 리스너를 다시 연 후 미전송분이 자동으로 다시 오는지 본다.
   - 화면 잠금 후 해제했을 때도 같은 것을 확인한다.
7. **핫스팟 유지**: 카메라를 끄거나 절전 상태로 둔 뒤 핫스팟이 꺼지는지(약 90초) 보고, 다시 연결하는 절차를 정리한다.
8. **업로드 경로**: 핫스팟이 켜진 상태에서 Firebase Storage나 S3 업로드가 정상인지 확인한다.
9. **권한**: 로컬 네트워크 권한 팝업이 뜨는지 확인한다. 수신 전용이면 뜨지 않을 것으로 예상한다.
10. **USB-C**: 카메라 USB 연결 모드별로 다음을 확인한다.
    - ImageCaptureCore가 카메라를 인식하는지
    - 촬영할 때 `cameraDevice(_:didAdd:)`가 오는지
    - 원본 다운로드 속도
    - 권한 요청이 정상으로 동작하는지(iOS 18·26 결함 보고가 있음)
11. **배터리·발열**: 30분 세션(핫스팟 + 화면 켜짐 + 업로드) 동안 아이폰 배터리가 얼마나 줄어드는지 잰다.
12. **iOS 버전**: 실증 기기의 iOS 버전을 기록한다. iOS 27이 출시됐으므로 동작이 버전마다 다를 수 있다.

### 4-7. 위험 요소

| # | 위험 | 영향 | 완화책 |
|---|---|---|---|
| R1 | **포그라운드·화면 켜짐 필수.** 작가가 폰을 주머니에 넣거나 다른 앱을 쓰면 수신이 멈춘다 | 즉시 전송이 끊긴다 | 촬영 세션 화면에서 자동 잠금을 막는다. 카메라의 재전송이나 재시도에 기댄다(실증 필요). 2차안으로 빠진 사진을 보완한다. 운영 가이드에 "세션 중에는 앱 화면 유지"를 명시한다 |
| R2 | 작가가 핫스팟을 직접 켜야 한다. 기기가 없으면 자동으로 꺼지고, 요금제가 막을 수 있다 | 연결에 실패한다 | 연결 마법사를 둔다. 작가 온보딩 때 요금제를 확인한다. 핫스팟 꺼짐을 감지하면 안내한다 |
| R3 | 보급기에는 FTP가 없다(Canon R8·R50, Fujifilm X-T5·X100VI, Sony a6700, Panasonic 전 기종) | 즉시 전송을 쓸 수 있는 작가가 줄어든다 | 기종별 지원표를 앱에서 관리한다. 2차안을 기본으로 제공한다. 필요하면 CCAPI나 CascableCore를 추가한다 |
| R4 | Nikon은 서드파티 FTP 서버를 공식 지원하지 않는다 | 펌웨어가 바뀌면 동작이 달라질 수 있다 | 실기로 검증하고 기종·펌웨어 호환 목록을 관리한다 |
| R5 | SDK 가입 장벽: Canon CCAPI의 한국 경로 불명, Sony Command는 법인 한정, Cascable은 가격 비공개 | Pull 어댑터를 도입하기까지 시간이 든다 | 회사 명의로 문의한다(사용자 확인 필요) |
| R6 | iOS 버전 회귀: ImageCaptureCore 권한 결함, BGContinuedProcessingTask 잠금 버그, Wi-Fi Aware 오류 | 특정 버전에서 기능이 깨진다 | 버전별 실증 매트릭스를 둔다. 기능 플래그로 끌 수 있게 한다 |
| R7 | 평문 FTP | 같은 핫스팟에 붙은 기기가 엿들을 수 있다 | 핫스팟 비밀번호(WPA2/WPA3)를 쓴다. 작가별 무작위 FTP 계정을 쓴다. 다른 기기가 붙어 있으면 경고한다(추측) |
| R8 | 셀룰러 데이터 사용량: 원본 JPEG를 수십 장 올리면 세션당 수백 MB가 될 수 있다(추측) | 작가 요금 부담 | 전송 대상을 JPEG로 제한한다. 서버에서 리사이즈한다. 요금제를 안내한다 |
| R9 | 배터리·발열(핫스팟 + 화면 + 업로드) | 긴 세션을 버티지 못한다 | 실측한 뒤 보조배터리 운영을 안내한다 |
| R10 | App Review 2.5.4 | 백그라운드 편법을 쓰면 거절된다 | 오디오·위치 모드를 쓰지 않는다 |
| R11 | 고객 사진 개인정보 | 작가 폰에 원본이 남는다 | 앱 컨테이너에만 저장하고 사진 앱에는 저장하지 않는다. 업로드가 확인되면 지운다. 보관 기간 정책을 둔다 |
| R12 | libgphoto2(LGPL)를 쓰는 경우 | 배포가 법적으로 다퉈질 수 있다 | 쓰지 않는 쪽을 권한다. 쓴다면 법무 검토를 받는다 |
| R13 | Frame.io를 쓰는 경우 | 약관(6.4), Enterprise 요구, 웹훅 베타 | 파일럿에 한정한다 |

### 4-8. 사용자 확인이 필요한 항목

- Canon CCAPI를 한국 법인이 신청할 경로(캐논코리아 문의)와 사용 허락 계약의 상업 이용 조건
- Sony Camera Remote Command 법인 신청(dimkt@sony.co.kr) 여부와, README에 적힌 a7C II의 Wi-Fi(PTP-IP) 지원 여부
- CascableCore 평가판 신청과 가격·과금 단위
- Nikon SDK와 Fujifilm SDK 계약서 본문(상업 이용 조건). 다만 두 SDK 모두 iOS를 지원하지 않으므로 우선순위는 낮다.
- Frame.io를 검토한다면 Enterprise 견적과 약관 해석(법무)
- 작가 대상 요금제의 핫스팟 허용 여부(운영 정책)

---

## 5. 출처

모두 2026-10-17에 확인했다. ★는 이 문서를 쓰면서 원문을 다시 열어 교차 확인한 출처다. "(보조)"는 2차 출처다.

### Sony
- SNY-1 Camera Remote SDK: https://support.d-imaging.sony.co.jp/app/sdk/en/index.html
- SNY-2 ★ Camera Remote Command: https://support.d-imaging.sony.co.jp/app/cameraremotecommand/en/index.html
- SNY-3 ★ Transfer & Tagging FTP 가져오기: https://support.d-imaging.sony.co.jp/app/transfer/en/instruction/21_ftp.php
- SNY-4 ★ α7C II 헬프가이드 FTP 전송: https://helpguide.sony.net/ilc/2360/v1/en/contents/0704L_ftp_transfer.html
- SNY-5 ★ α7C II FTP Help Guide 자동 전송: https://helpguide.sony.net/di/ftp_2360/v1/en/contents/auto_transfer.html
- SNY-6 ★ α7C II FTP 서버 등록: https://helpguide.sony.net/di/ftp_2360/v1/en/contents/FTP_server_registration.html
- SNY-7 ★ α7C II 정지 화면 전송 대상: https://helpguide.sony.net/di/ftp_2360/v1/en/contents/target_file_setting.html
- SNY-8 Creators' App: https://creatorscloud.sony.net/catalog/en-us/creatorsapp/ , https://creatorscloud.sony.net/news/en-us/20240912.html
- SNY-9 α6700 헬프가이드 전송 크기: https://helpguide.sony.net/ilc/2320/v1/en/contents/201h_transfer_select_on_camera.html
- SNY-10 Creators' App 가져오기: https://helpguide.sony.net/di-app/ca/v1/en/contents/CA_import_from_camera.html
- SNY-11 Creators' Cloud 직접 업로드: https://helpguide.sony.net/di-app/ca/v1/en/contents/CA_direct_upload.html
- SNY-12 Creators' App USB 연결: https://helpguide.sony.net/di-app/ca/v1/en/contents/CA_usb_connect.html
- SNY-13 a7C II 제품 페이지(백그라운드 전송 문구, 403으로 검색 요약만 확인): https://www.sony.com.tw/en/interchangeable-lens-cameras/products/ilce-7cm2/feature5
- SNY-14 (보조) 구 Camera Remote API 종료: https://www.vision-systems.com/boards-software/article/14175325/sony-new-camera-remote-sdk-released
- SNY-15 Sony 스마트폰 Wi-Fi 연결(DIRECT- SSID): https://helpguide.sony.net/ilc/1940/v1/en/contents/TP0002670836.html

### Canon
- CAN-1 ★ Canon Asia CAP(CCAPI): https://asia.canon/en/campaign/developerresources/camera/cap
- CAN-2 Canon Japan API 패키지: https://personal.canon.jp/product/camera/software/api-package
- CAN-3 CCAPI Supported Cameras: https://developercommunity.usa.canon.com/s/article/CCAPI-Supported-Cameras
- CAN-4 CCAPI Function List: https://developercommunity.usa.canon.com/s/article/CCAPI-Function-List
- CAN-5 Canon USA Developer Community 약관: https://developercommunity.usa.canon.com/s/legal-main
- CAN-6 R6 Mark III CCAPI 연결: https://cam.start.canon/en/C022/manual/html/UG-07_Network_0080.html
- CAN-7 R5 Mark II CCAPI 연결: https://cam.start.canon/en/C017/manual/html/UG-06_Network_0130.html
- CAN-8 R6 Mark III FTP: https://cam.start.canon/en/C022/manual/html/UG-07_Network_0070.html
- CAN-9 R6 V FTP: https://cam.start.canon/en/C023/manual/html/UG-07_Network_0070.html
- CAN-10 R5 Mark II FTP: https://cam.start.canon/en/C017/manual/html/UG-06_Network_0060.html
- CAN-11 R6 Mark II 네트워크: https://cam.start.canon/en/C012/manual/html/UG-07_Network_0010.html
- CAN-12 R5 FTP: https://cam.start.canon/en/C003/manual/html/UG-06_Network_0030.html
- CAN-13 R6 FTP: https://cam.start.canon/en/C004/manual/html/UG-06_Network_0030.html
- CAN-14 R3 네트워크: https://cam.start.canon/en/C010/manual/html/UG-06_Network_0010.html
- CAN-15 R7/R8/R50/R50 V 통신 기능 목록: https://cam.start.canon/en/C005/manual/html/UG-07_Network_0010.html , https://cam.start.canon/en/C013/manual/html/UG-07_Network_0010.html , https://cam.start.canon/en/C011/manual/html/UG-08_Network_0010.html , https://cam.start.canon/en/C021/manual/html/UG-07_Network_0010.html
- CAN-16 Camera Connect 자동 전송: https://cam.start.canon/en/C022/manual/html/UG-07_Network_0030.html
- CAN-17 image.canon: https://cam.start.canon/en/C017/manual/html/UG-06_Network_0080.html
- CAN-18 R6 Mark III USB 앱 선택: https://cam.start.canon/en/C022/manual/html/UG-07_Network_0180.html
- CAN-19 Mobile File Transfer: https://cam.start.canon/en/S001/manual/html/UG-00_Before_0020.html , https://th.canon/en/consumer/mobile-file-transfer/main/product
- CAN-20 (보조) Canomate: https://horshack-dpreview.github.io/Canomate/
- CAN-21 (보조) canon-ccapi-node: https://github.com/camerahacks/canon-ccapi-node
- CAN-22 (보조) SpotMyPhotos(2019): https://thedeadpixelssociety.com/spotmyphotos-brings-instant-photo-sharing-to-canon-dslrs/
- CAN-23 (보조) Canon Developer Community 등급(2019): https://thedeadpixelssociety.com/canon-launches-developer-community-program-and-wifi-based-camera-control-api/
- CCAPI 최신 레퍼런스(SSL 오류로 못 염): https://developers.canon-europe.com/developers/s/article/Latest-CCAPI

### Nikon
- NIK-1 Nikon SDK: https://sdk.nikonimaging.com/information/ja/ , https://sdk.nikonimaging.com/apply/ , https://sdk.nikonimaging.com/apply/guide
- NIK-2 Z9 무선 LAN 컴퓨터 연결: https://onlinemanual.nikonimglib.com/z9/en/computers_connecting_via_ethernet_or_wireless_lan_66.html
- NIK-3 Wireless Transmitter Utility 지원 기종: https://nikonimglib.com/wt4su/onlinehelp/en/05_using_settings_01.html
- NIK-4 NX MobileAir: https://nikonimglib.com/nxmoba/onlinehelp/en/01_about_01.html , https://nikonimglib.com/nxmoba/onlinehelp/en/01_about_02.html , https://apps.apple.com/us/app/-/id1561345097
- NIK-5 Z6III 스마트기기 연결: https://onlinemanual.nikonimglib.com/z6III/en/nwm_connect_to_smart_device_359.html
- NIK-6 SnapBridge 다운로드: https://nikonimglib.com/snbr/onlinehelp/en/downloading_pictures_as_they_are_taken_10.html , https://nikonimglib.com/snbr/onlinehelp/en/download_size_50.html , https://nikonimglib.com/snbr/onlinehelp/en/compatible_cameras_44.html
- NIK-7 SnapBridge App Store: https://apps.apple.com/us/app/-/id1121563450
- NIK-8 Z9 FTP: https://onlinemanual.nikonimglib.com/z9/en/11_connecting_to_computers_or_ftp_servers_04.html , https://onlinemanual.nikonimglib.com/z9/en/nwm_connect_to_ftp_server_325.html
- NIK-9 Z6III FTP: https://onlinemanual.nikonimglib.com/z6III/en/nwm_connect_to_ftp_server_365.html
- NIK-10 Z50II 네트워크·USB: https://onlinemanual.nikonimglib.com/z50II/en/09-09.html , https://onlinemanual.nikonimglib.com/z50II/en/09-09-10.html
- NIK-11 Nikon Imaging Cloud: https://nikonusa.com/content/nikon-imaging-cloud
- NIK-12 (보조) PTP/IP 발표(2004): https://www.photographyblog.com/news/nikon_introduces_new_protocol_for_digicam_data_transfer
- NIK-13 (보조) Z50 gphoto2: https://discuss.pixls.us/t/nikon-z50-wireless/21208

### Fujifilm
- FUJ-1 Camera Control SDK: https://www.fujifilm-x.com/global/special/camera-control-sdk/
- FUJ-2 SDK EULA: https://www.fujifilm-x.com/global/camera-control-sdk/agreement/
- FUJ-3 XApp: https://www.fujifilm-x.com/global/support/compatibility/software/xapp/ , https://apps.apple.com/app/id1586089681 , https://www.fujifilm-x.com/global/products/software/xapp/
- FUJ-4 X-M5 스마트폰 앱 연결: https://fujifilm-dsc.com/en/manual/x-m5/connections/usage_smartphone_app/
- FUJ-5 X-T5 테더 촬영: https://fujifilm-dsc.com/en/manual/x-t5/connections/tethere/
- FUJ-6 GFX100 II FTP: https://fujifilm-dsc.com/en/manual/gfx100ii/connections/ftp_upload/
- FUJ-7 GFX100S II FTP: https://fujifilm-dsc.com/en/manual/gfx100s-ii/connections/ftp_upload/
- FUJ-8 X-H2 FTP: https://fujifilm-dsc.com/en/manual/x-h2_connection/overview_usage/ftp_upload/
- FUJ-9 X-T5 네트워크/USB 메뉴: https://fujifilm-dsc.com/en/manual/x-t5/connections/network_usb_menu/
- FUJ-10 X-H2 Frame.io: https://fujifilm-dsc.com/en/manual/x-h2_connection/overview_usage/frameio_upload/
- FUJ-11 X-T5 USB: https://fujifilm-dsc.com/en/manual/x-t5/connections/usage_usb/
- FUJ-12 X-T5 스마트폰 앱: https://fujifilm-dsc.com/en/manual/x-t5/connections/usage_smartphone_app/
- FUJ-13 Fujifilm × Frame.io: https://www.fujifilm-x.com/global/lp/fujifilm-x-frame-io/

### Panasonic
- PAN-1 LUMIX SDK: https://av.jpn.support.panasonic.com/support/global/cs/soft/tool/sdk.html
- PAN-2 LUMIX Lab: https://av.jpn.support.panasonic.com/support/global/cs/soft/lumix_lab/en/index.html , https://av.jpn.support.panasonic.com/support/global/cs/soft/lumix_lab/en/faq.html , https://apps.apple.com/us/app/panasonic-lumix-lab/id6499262377
- PAN-3 LUMIX Sync: https://av.jpn.support.panasonic.com/support/software/lumix_sync/frd.html
- PAN-4 S1RII Direct 연결: https://eww.pavc.panasonic.co.jp/dscoi/DC-S1RM2/html/DC-S1RM2_DVQP3245_eng/0196.html
- PAN-5 S1RII 메뉴와 Auto Transfer: https://eww.pavc.panasonic.co.jp/dscoi/DC-S1RM2/html/DC-S1RM2_DVQP3245_eng/0200.html , https://eww.pavc.panasonic.co.jp/dscoi/DC-S1RM2/html/DC-S1RM2_DVQP3245_eng/0192.html
- PAN-6 L10 Auto Transfer: https://eww.pavc.panasonic.co.jp/dscoi/DC-L10/html/DC-L10_DVQP3497_eng/0133.html
- PAN-7 S5II, GH5II PC 전송: https://eww.pavc.panasonic.co.jp/dscoi/DC-S5M2/html/DC-S5M2_DVQP2839_eng/0129.html , https://eww.pavc.panasonic.co.jp/dscoi/DC-GH5M2/html/DC-GH5M2_DVQP2477_eng/0123.html
- PAN-8 GH7, S5II Frame.io: https://eww.pavc.panasonic.co.jp/dscoi/DC-GH7/html/DC-GH7_DVQP3109_eng/0148.html , https://eww.pavc.panasonic.co.jp/dscoi/DC-GH7/html/DC-GH7_DVQP3109_eng/0150.html , https://eww.pavc.panasonic.co.jp/dscoi/DC-S5M2/html/DC-S5M2_DVQP2839_eng/0171.html
- PAN-9 GH7 USB: https://eww.pavc.panasonic.co.jp/dscoi/DC-GH7/html/DC-GH7_DVQP3109_eng/0160.html
- PAN-10 LUMIX C2C, LUMIX Lab: https://shop.panasonic.com/pages/lumix-camera-to-cloud , https://shop.panasonic.com/pages/lumix-lab-app
- PAN-11 (보조) libgphoto2 Lumix 이슈: https://github.com/gphoto/libgphoto2/issues/409 , https://flows.nodered.org/flow/adef1418e457c4e4d2320b3c9f0dd86b

### OM System
- OM-1 공식 소프트웨어: https://explore.omsystem.com/c/en/software
- OM-2 (보조) PlayOPC: https://github.com/ura14h/PlayOPC
- OM-3 (보조) OI.Share 리버스 엔지니어링: https://0l.de/projects/omd/ , https://olympus-wifi.readthedocs.io/en/latest/usage.html
- OM-4 OM-1 Mark II 매뉴얼: https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/pairing_smartphone_wifi_274.html , https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/adjusting_wifi_settings_287.html , https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/uploading_shooting_wifi_288.html , https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/auto_upload_images_camera_off_278.html , https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/wireless_settings_camera_off_276.html , https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/copying_pictures_computer_300.html , https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/uploading_shooting_usb_298.html
- OM-5 OM-3 매뉴얼: https://learning.omsystem.com/OM-3/zz_html_manual/en/transferring_images_smartphone_274.html
- OM-6 OI.Share: https://software.omsystem.com/oishare/en/ , https://support.jp.omsystem.com/en/support/imsg/digicamera/qa/products/oishare/index02.html

### Leica
- LEI-1 Leica FOTOS App Store: https://apps.apple.com/us/app/leica-fotos/id1356061526
- LEI-2 Capture One 파트너십: https://leica-camera.com/en-GB/press/leica-camera-ag-announces-strategic-partnership-capture-one
- LEI-3 Frame.io Leica 가이드: https://help.frame.io/en/articles/13162126-c2c-leica-quickstart-guide
- LEI-4 (보조) M10 PTP/IP: https://www.l-camera-forum.com/topic/276865-wireless-transfer/page/2
- LEI-5 FOTOS Cable: https://leica-camera.com/en-AU/product/leica-fotos-cable , (보조) https://www.cliftoncameras.co.uk/leica-fotos-cable
- LEI-6 (보조) Q3 MFi: https://www.glazerscamera.com/collections/cameras/products/leica-q3
- LEI-7 (보조) Evoto 유선 테더링: https://support.evoto.ai/leica-wired-tethered-shooting-mobile/
- LEI-8 (보조) M11 백그라운드 전송 사용자 보고: https://www.reddotforum.com/4kto , https://www.l-camera-forum.com/topic/429717-leica-fotos-oddness-with-m11d/
- SL3-S Content Credentials(보조): https://www.diyphotography.net/?p=290141

### Ricoh/Pentax, Sigma, Hasselblad
- RIC-1 (보조) RICOH Camera SDK(2018): https://thedeadpixelssociety.com/ricoh-releases-four-software-development-kits-for-the-remote-operation-of-pentax-dslrs/ , https://www.pentaxforums.com/articles/pentax-news/ricoh-releases-sdk-for-pentax-cameras.html
- RIC-2 (보조) GR 비공식 API: https://github.com/jakubroztocil/grfs , https://github.com/metalunk/GRsync
- RIC-3 GR Linker: https://apps.apple.com/app/id1600925588
- RIC-4 RICOH THETA theta-client: https://github.com/ricohapi/theta-client
- RIC-5 GR IV 사양, GR WORLD: https://www.ricoh-imaging.co.jp/english/products/gr-4/spec/ , https://www.ricoh-imaging.co.jp/japan/products/app/gr-world/
- RIC-6 GR III, K-3 III 사양: https://www.ricoh-imaging.co.jp/english/products/gr-3/spec/ , https://www.ricoh-imaging.co.jp/english/products/k-3-3/spec/
- RIC-7 Image Sync: https://www.ricoh-imaging.co.jp/japan/products/app/image-sync2/manual-00.html , (보조) https://gigazine.net/gsc_news/en/20210922-gr-iiix-image-sync
- RIC-8 (보조) K-3 III 펌웨어: https://www.pentaxforums.com/articles/firmware-updates/pentax-k-3-iii-firmware-update-v120-released.html
- SIG-1 Sigma SDK: https://www.sigma-global.com/en/news/2020/07/02/10916/ , https://www.sigma-global.com/en/cameras/fp-series/download/sdk/
- SIG-2 fp, BF 제품: https://www.sigma-global.com/en/cameras/fp/ , https://www.sigma-global.com/en/cameras/bf/ , (보조) https://www.lensrentals.com/rent/sigma-bf-mirrorless-black
- SIG-3 BF: (보조) https://amateurphotographer.com/review/sigma-bf-review/ , https://www.sigma-global.com/en/news/2026/02/19/012040/
- HAS-1 Phocus Mobile 2: https://www.hasselblad.com/phocus/phocus-mobile-2/ , https://www.hasselblad.com/products/compare-x1d-907x/
- HAS-2 Phocus Mobile 2 v3.6.0 USB-C: https://thecamerastore.com/blogs/blog/phocus-mobile-2-v3-6-0-is-here
- HAS-3 Capture One 협업: https://master.hasselblad.com/press/press-releases/2026/hasselblad-and-capture-one-partner-to-bring-native-hasselblad-raw-support , https://petapixel.com/2026/07/02/capture-one-now-supports-hasselblad-photos-with-tethering-coming-soon/
- HAS-4 (보조) A6D SDK(2017): https://www.imaging-resource.com/?p=16656

### Frame.io
- FIO-1 C2C 시작하기(지원 기기): https://help.frame.io/en/articles/8896457-c2c-getting-started-with-camera-to-cloud
- FIO-2 Fujifilm 가이드: https://help.frame.io/en/articles/7156603-c2c-fujifilm-quickstart-guide
- FIO-3 Panasonic 가이드: https://help.frame.io/en/articles/9179663-c2c-panasonic-lumix-quickstart-guide
- FIO-4 Nikon 가이드: https://help.frame.io/en/articles/10273793-c2c-nikon-quickstart-guide
- FIO-5 Canon 가이드: https://help.frame.io/en/articles/10070093-c2c-canon-quickstart-guide
- FIO-6 C2C FAQ: https://help.frame.io/en/articles/4887091-c2c-frame-io-camera-to-cloud-faqs
- FIO-7 인터넷 연결 가이드: https://help.frame.io/en/articles/8571967-c2c-complete-internet-connection-guide
- FIO-8 요금: https://frame.io/pricing , https://frame.io/c2c
- FIO-9 웹훅: https://next.developer.frame.io/platform/docs/guides/webhooks , https://help.frame.io/en/articles/15382181-set-up-webhooks-in-frame-io
- FIO-10 파일 조회와 원본 링크: https://next.developer.frame.io/platform/v4/api-reference/files/show , https://next.developer.frame.io/platform/docs/resources/faq
- FIO-11 인증: https://next.developer.frame.io/platform/docs/guides/authentication/overview , (보조) https://forum.frame.io/t/frame-io-v4-api-not-available-in-adobe-developer-console-how-to-enable-entitlement/3462
- FIO-12 V2 API 제거 공지: https://developer.frame.io/
- FIO-13 V4 마이그레이션: https://next.developer.frame.io/platform/docs/resources/migration
- FIO-14 C2C 파일 위치와 문제 해결: https://support.frame.io/en/articles/4885999-c2c-viewing-frame-io-c2c-files , https://help.frame.io/en/articles/4886926-c2c-troubleshooting
- FIO-15 C2C 디바이스 통합: https://next.developer.frame.io/camera-to-cloud/getting-started-with-cloud-device-integrations , https://next.developer.frame.io/camera-to-cloud/integrator-checklist
- FIO-16 Adobe 약관, Frame.io 약관: https://www.adobe.com/legal/terms.html , https://www.adobe.com/go/frameio-terms
- FIO-17 file.created 시점: https://developer.adobe.com/frameio/guides/Zapier/Frame.io%20Resources%20in%20Zapier%20V4
- FIO-18 Fujifilm C2C 연결 저장: https://shopusa.fujifilm-x.com/camera-to-cloud/

### 브랜드 공통 해법
- COM-1 CascableCore: https://developer.cascable.se/
- COM-2 CascableCore 배포·릴리스 노트: https://github.com/Cascable/cascablecore-distribution/releases , https://raw.githubusercontent.com/Cascable/cascablecore-distribution/main/Package.swift
- COM-3 CascableCoreSwift: https://github.com/Cascable/cascablecore-swift
- COM-4 Getting Started: https://github.com/Cascable/cascablecore-demo/blob/master/Getting%20Started%20With%20CascableCore.md
- COM-5 Cascable 호환성: https://compatibility.cascable.se/
- COM-6 Cascable Studio: https://cascable.se/studio/features/ , https://apps.apple.com/us/app/cascable-studio-camera-tether/id974193500 , https://cascable.se/help/wired-cameras/ , https://cascable.se/help/studio/sony-modern-connection-guide/
- COM-7 libgphoto2: https://github.com/gphoto/libgphoto2 , https://github.com/gphoto/libgphoto2/blob/master/camlibs/ptp2/library.c , https://raw.githubusercontent.com/gphoto/libgphoto2/master/NEWS
- COM-8 GPhoto2Framework, PhotoSync Canon 목록: https://github.com/touchbyte/GPhoto2Framework , https://www.photosync-app.com/support/camera/answers/supported-canon-wi-fi-cameras
- COM-9 LGPL-2.1: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
- COM-10 (보조) LGPL과 App Store 논쟁: https://trac.ffmpeg.org/ticket/1229 , https://lists.qt-project.org/pipermail/interest/2012-February/000984.html , https://www.ebb.org/bkuhn/blog/2012/11/22/vlc-lgpl.html
- COM-11 Apple 표준 EULA: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
- COM-12 FSF·VLC 선례: https://www.fsf.org/news/2010-05-app-store-compliance , https://www.engadget.com/2011-01-09-the-gpl-the-app-store-and-you.html , https://news.slashdot.org/story/13/07/18/1943202/vlc-for-ios-returns-on-july-19-rewritten-and-fully-open-sourced
- COM-13 오픈소스 대안: https://github.com/petabyt/libpict , https://github.com/petabyt/fudge
- COM-14 ShutterSnitch: https://apps.apple.com/us/app/shuttersnitch/id364176211 , (보조) 설정 가이드 https://sites.google.com/site/rdctphoto
- COM-15 PhotoSync: https://www.photosync-app.com/support/camera/answers/how-to-configure-photosync-to-receive-photos-videos-from-cameras-over-ftp.html , https://www.photosync-app.com/support/camera/answers/how-to-get-internet-being-connecetd-to-camera
- COM-16 Camera Port - Background FTP: https://apps.apple.com/us/app/camera-port-background-ftp/id6757133927
- COM-17 ★ Camera Connect & Control: https://apps.apple.com/us/app/camera-connect-control/id1457548017
- COM-18 ★ TetherDrop: https://apps.apple.com/app/id6788720660
- COM-19 Capture One iOS: https://apps.apple.com/us/app/capture-one/id1514081672
- COM-20 qDslrDashboard 공지(2018): https://dslrdashboard.info/?p=905
- COM-21 PhotoKit 백그라운드 변경 알림: https://developer.apple.com/forums/thread/132441
- COM-22 PhotoKit 제한 접근: https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app
- COM-23 PHBackgroundResourceUploadExtension: https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background , (보조) https://developer.apple.com/forums/thread/822256

### iOS (Apple)
- IOS-1 Wi-Fi Direct 미지원(Quinn): https://developer.apple.com/forums/thread/12885
- IOS-2 TN3111 iOS Wi-Fi API overview: https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview
- IOS-3 Wi-Fi Aware: https://developer.apple.com/documentation/wifiaware , https://developer.apple.com/documentation/wifiaware/adopting-wi-fi-aware
- IOS-4 Accessory Design Guidelines R31: https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf
- IOS-5 Wi-Fi Aware 포럼: https://developer.apple.com/forums/thread/837110 , https://developer.apple.com/forums/thread/828136
- IOS-6 AccessorySetupKit: https://developer.apple.com/documentation/accessorysetupkit/discovering-and-configuring-accessories , https://developer.apple.com/forums/thread/759225 , https://developer.apple.com/forums/thread/775955 , https://developer.apple.com/forums/thread/775503
- IOS-7 NEHotspotConfigurationManager.apply: https://developer.apple.com/documentation/networkextension/nehotspotconfigurationmanager/apply(_:completionhandler:)
- IOS-8 ★ NEHotspotConfiguration.joinOnce: https://developer.apple.com/documentation/networkextension/nehotspotconfiguration/joinonce
- IOS-9 인터넷 없는 액세서리 네트워크(포럼): https://developer.apple.com/forums/thread/848895 , https://developer.apple.com/forums/thread/668318 , https://developer.apple.com/forums/thread/734344 , https://developer.apple.com/forums/thread/734361 , https://developer.apple.com/forums/thread/774340
- IOS-10 NEHotspotHelper: https://developer.apple.com/documentation/networkextension/nehotspothelper
- IOS-11 NEHotspotNetwork.fetchCurrent: https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent(completionhandler:)
- IOS-12 다중 인터페이스, 셀룰러 지정(포럼): https://developer.apple.com/forums/thread/734293 , https://developer.apple.com/forums/thread/666276 , https://developer.apple.com/forums/thread/712896 , https://developer.apple.com/forums/thread/655183 , https://developer.apple.com/forums/thread/734359 , https://developer.apple.com/forums/thread/734343
- IOS-13 Multipath TCP: https://developer.apple.com/documentation/foundation/improving-network-reliability-using-multipath-tcp
- IOS-14 Wi-Fi Assist(Connectivity Assist): https://support.apple.com/127686
- IOS-15 FirebaseStorage podspec: https://raw.githubusercontent.com/firebase/firebase-ios-sdk/main/FirebaseStorage.podspec
- IOS-16 AWS SDK for Swift HTTP 구성: https://docs.aws.amazon.com/sdk-for-swift/latest/developer-guide/http.html
- IOS-17 TN3179 Local Network Privacy: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- IOS-18 ★ iOS Background Execution Limits(Quinn, 2021-07 작성, 2026-01-09 수정): https://developer.apple.com/forums/thread/685525
- IOS-19 TN2277 Networking and Multitasking: https://developer.apple.com/library/archive/technotes/tn2277/_index.html
- IOS-20 백그라운드 URLSession: https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:) , https://developer.apple.com/documentation/foundation/urlsessionconfiguration/isdiscretionary , https://developer.apple.com/forums/thread/849761
- IOS-21 BGContinuedProcessingTask: https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados , https://developer.apple.com/forums/thread/796138
- IOS-22 App Review Guidelines 2.5.4: https://developer.apple.com/app-store/review/guidelines/
- IOS-23 Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- IOS-24 isIdleTimerDisabled: https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled
- IOS-25 개인용 핫스팟 API 부재(포럼): https://developer.apple.com/forums/thread/689992 , https://developer.apple.com/forums/thread/749966 , https://developer.apple.com/forums/thread/801998 , https://developer.apple.com/forums/thread/127509
- IOS-26 개인용 핫스팟 지원 문서: https://support.apple.com/en-us/HT203302 , https://support.apple.com/guide/platform-support/sup025284ac0/web
- IOS-27 (보조) 국내 테더링 한도 기사(2022): https://www.newsis.com/view/NISX20220801_0001963445
- IOS-28 ImageCaptureCore: https://developer.apple.com/documentation/imagecapturecore , https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requesttakepicture() , https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand(_:outdata:completion:)
- IOS-29 ImageCaptureCore 결함(포럼): https://developer.apple.com/forums/thread/656878 , https://developer.apple.com/forums/thread/756960 , https://developer.apple.com/forums/thread/760090 , https://developer.apple.com/forums/thread/802285
- IOS-30 iPhone USB-C: https://support.apple.com/118280 , https://support.apple.com/en-us/105099
- IOS-31 ★ (보조) iOS 27 출시일: https://macrumors.com/2026/09/09/apple-announces-ios-27-release-date/
