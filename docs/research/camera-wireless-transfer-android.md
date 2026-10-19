# 카메라 → 안드로이드폰 무선 전송 조사 (iOS 보고서 보완)

- 작성: 2026-10-19, sbsn_research 세션. 작가가 안드로이드폰을 쓰는 경우를 추가로 조사해 달라는 사용자 요청에 따른 문서다.
- 함께 볼 문서: [camera-wireless-transfer.md](camera-wireless-transfer.md)(iOS 기준, 이하 "iOS 보고서"). 카메라 쪽 사실(FTP 지원 기종 등)은 iOS 보고서를 따르고, 여기서는 **안드로이드폰을 쓸 때 달라지는 점**만 다룬다.
- 범위 추가: 폰 OS와 무관한 **"카메라 → 폰 핫스팟 → 우리 클라우드 FTPS로 직접 업로드"** 경로를 4장에 넣었다. iOS 보고서에서는 이 경로를 충분히 비교하지 않았다.
- **결정(2026-10-19, 사용자)**: 초기에는 서버 없이 B안(작가 앱 FTP 수신)으로 간다. 클라우드 직행(4장)은 파일럿에서 iOS 작가의 "앱 화면 유지"가 실제 문제로 드러날 때 다시 검토한다. 0장 6항, 4-3, 5장을 이 결정에 맞춰 고쳤다.
- 확인 날짜: 출처는 모두 2026-10-17에 확인했다.
- 표시 규칙은 iOS 보고서와 같다.
  - **[확인됨]**: 1차 출처(Android 공식 문서, AOSP 소스, Google Play 정책 센터, 제조사 매뉴얼, AWS 문서·공개 요금 파일)에서 확인했다. AOSP 소스로 확인한 것은 "[확인됨, 소스]"라고 적었다.
  - **[일부 확인]**: 2차 출처만 있거나 출처끼리 충돌한다.
  - **[확인 못 함]**: 찾지 못했다.
  - **(추측)**: 근거에서 추론한 판단이다.
  - ★: 이 문서를 쓰면서 원문을 다시 열어 교차 확인한 출처다.
  - 출처 ID는 6장 목록을 가리킨다.
- 조사 한계
  - 실기 검증은 하지 않았다. 갤럭시 실기 동작은 특히 확인이 필요하다.
  - 열지 못한 페이지가 있다: Sony 지역 지원 사이트(403), Google Play 상세 본문, api.ricoh, l-camera-forum.
  - AWS 요금 조회 MCP는 기본 AWS 프로필(`footagemanager-deployer`)에 `pricing:GetProducts` 권한이 없어 실패했다. 인증 없이 받는 공개 요금 파일로 대신 확인했다 ★CL-A13.

---

## 0. 요약: iOS와 무엇이 달라지나

1. **iOS의 두 가지 큰 제약이 Android에서는 풀린다.**
   - **카메라 Wi-Fi에 붙어 있어도 인터넷은 셀룰러로 나간다.** `WifiNetworkSpecifier`로 붙은 카메라 네트워크는 "앱이나 기기에 인터넷을 제공하지 않는다" ★AN-1. 그래서 기본 인터넷 경로가 셀룰러에 남고, 경로를 지정할 수 없는 Firebase Storage도 그대로 셀룰러로 올라간다 [일부 확인 AN-1, AN-7, AN-10, 갤럭시 실기 확인 필요].
   - **화면이 꺼져도 수신을 유지할 수 있다.** `connectedDevice` 타입 포그라운드 서비스(FGS)로 화면이 꺼진 상태에서도 FTP 수신과 카메라 연결을 붙잡아 둘 수 있다.
     - 이 타입에는 시간 제한이 없다. 6시간 제한은 `dataSync`와 `mediaProcessing`에만 있다 ★AF-2.
     - FGS를 실행 중인 앱은 Doze 상태에서도 네트워크 제한을 받지 않는다 [확인됨 AF-5].
     - 같은 조건에서 Sony Transfer & Tagging도 Android에서는 앱을 절전 예외로 두면 화면이 꺼져도 계속 받는다 ★BR-S3.
2. **대신 Android만의 부담이 생긴다.**
   - Play Console에 FGS 타입을 신고하고 시연 영상을 내야 한다 [확인됨 AF-3].
   - **Android 17(target 37)부터는 들어오는 TCP 연결을 받는 데에도 `ACCESS_LOCAL_NETWORK` 권한이 필요하다** ★AV-4. iOS는 수신 전용이면 권한이 필요 없었다.
   - 핫스팟 IP가 고정되지 않는다. AOSP는 무작위 /24 대역을 쓰고 약 94%가 10.x다 [확인됨, 소스 AH-7]. iOS는 172.20.10.1로 고정이다.
   - 앱은 시스템 핫스팟을 켜거나 끌 수 없다 [확인됨, 소스 AH-6].
   - 배터리 최적화 예외를 앱이 직접 요청하는 것은 Play 정책상 이 용도에 허용되기 어렵다 ★AF-4.
3. **제조사 공식 경로는 대체로 Android가 유리하다.**
   - Nikon 매뉴얼은 표준 USB 모드 [MTP/PTP]를 "computers or Android devices"용이라고 적는다. [iPhone] 모드는 NX MobileAir 전용이다 ★BR-N1.
   - Canon 슈 어댑터 AD-P1은 "Android 스마트폰만" 지원한다. R5, R5 C, R6, 1D X III는 Canon 앱에서도 iOS 유선 연결이 안 된다 ★BR-C4.
   - Sony 카메라의 USB 테더링은 Android에서는 폰의 Wi-Fi와 모바일 회선을 모두 쓸 수 있고, iPhone에서는 모바일만 된다 [확인됨 BR-S5].
   - Fujifilm SDK는 Android를 USB 연결로만 공식 지원한다 [확인됨 BR-F1].
   - 반대로 불리한 경우도 있다. Hasselblad Android 앱은 USB 직결이 X2D II 한 기종뿐이고, Sony Transfer & Tagging Android는 HEIF를 받지 못한다 [확인됨 BR-H1, BR-S1].
4. **브랜드 공통 해법은 Android 쪽이 더 비어 있다.**
   - CascableCore는 Android를 지원하지 않고, Android용 상용 멀티브랜드 SDK도 찾지 못했다 [확인됨 CM-1].
   - 대신 쓸 수 있는 것
     - Apache-2.0 FTP 서버 라이브러리(Apache FtpServer, MinimalFTP) [확인됨 CM-14~16]
     - Android 기본 API `MtpDevice`(USB 목록 조회, 원본 다운로드, `readEvent`) [확인됨, 소스 AU-2]
     - libgphoto2: 2.5.32(2025-07)부터 Android의 USB 파일 디스크립터(fd) 전달을 공식 지원한다 [확인됨 CM-3]. 다만 LGPL 문제가 남는다.
5. **폰 OS와 무관한 대안은 카메라에서 클라우드 FTPS로 직접 올리는 것이다.**
   - 장점: 폰은 핫스팟만 켜 두면 된다. 그래서 iOS의 "앱을 화면에 띄워 둬야 함"과 Android의 "핫스팟 IP가 바뀜" 문제가 함께 사라진다.
   - 프로토콜: Explicit FTPS가 Sony, Canon, Nikon, Fujifilm FTP 기종의 공통분모다 [확인됨 CL-S2, CL-C1~C5, CL-N2, CL-F1].
   - AWS Transfer Family 서울 리전: 프로토콜당 시간당 $0.30, GB당 $0.04다 ★CL-A13. FTPS 하나를 상시 켜 두면 엔드포인트만 월 약 $219다.
   - 위험
     - FTPS의 TLS 세션 재개 설정이 기본값으로 "강제(`ENFORCED`)"다. 카메라 FTPS 클라이언트가 세션을 재개하지 않으면 데이터 연결이 거부된다 ★CL-A6.
     - 카메라 업로드가 **테더링 데이터 한도**에서 빠진다. 예를 들어 SKT 5GX 프라임은 테더링·공유 통합 월 60GB다 [확인됨 CL-H8].
     - Nikon은 인터넷 FTP를 공식 지원하지 않는다고 명시한다 [확인됨 CL-N2].
6. **결정된 구조(2026-10-19): 초기에는 서버 없이 B안**
   - **1차(초기 기본 경로) B**: 카메라 → 폰 앱 FTP 수신. iOS는 포그라운드에서만, Android는 FGS로 화면이 꺼져도 된다. 서버 고정비가 없다.
   - **2차(일괄 전송)**: USB-C 유선. iOS는 ImageCaptureCore, Android는 `MtpDevice`를 쓴다.
   - **보류 A**: 카메라 → 클라우드 FTPS 직행. 파일럿에서 iOS의 포그라운드 제약이 실제 문제로 확인되면 다시 검토한다. 그때도 Transfer Family가 아니라 월 $0~12 수준의 서울 리전 서버부터 시작한다(4-3).

---

## 1. 브랜드 × Android 경로

### 1-1. 매트릭스

| 브랜드 | 서드파티 SDK·API의 Android 지원 | 공식 앱 Android판의 차이 | 카메라가 폰의 USB 테더링으로 인터넷 접속 | Android USB-C 직결 | iOS 대비 |
|---|---|---|---|---|---|
| **Sony** | Camera Remote SDK: 지원 OS 목록에 Android 없음. Camera Remote Command: "environment-independent PTP"라고만 하고 Android는 명시하지 않음, 법인 전용 [확인됨 BR-S9] | Transfer & Tagging: **절전 예외로 두면 화면이 꺼지거나 홈으로 나가도 계속 수신** ★BR-S3, **Ethernet 테더링은 Android 전용**, **HEIF 미지원**(Android는 JPEG·RAW·WAV), 카메라를 찾으려면 정밀 위치 권한 필요 [확인됨 BR-S1~S3] | ● Android는 폰의 Wi-Fi와 모바일 회선 모두, iPhone은 모바일만. USB-PD 권장. 검증 목록에서 Pixel 6~9는 "–" 표시 [확인됨 BR-S4, BR-S5] | Creators' App이 C-C 케이블로 연결(OS 구분 없음). 서드파티가 PTP로 붙으려면 Camera Remote Command 계약 필요 [확인됨 BR-S7] | **유리**(백그라운드 수신, 망 선택). HEIF는 불가 |
| **Canon** | CCAPI는 Android 공식 지원(iOS와 같음). EDSDK는 Windows·macOS·Linux만 [확인됨 BR-C1] | Content Transfer Professional·Mobile File Transfer: **Android 유선 지원 기종이 더 많다**(R5, R5 C, R6, 1D X III는 iOS 유선 불가) ★BR-C4. **AD-P1은 Android 전용**(R1부터 R50까지 12기종) [확인됨 BR-C6]. Camera Connect는 문서상 차이 없음 | ○ 카메라 쪽 기능은 찾지 못함. 폰 앱(CTP)이 중계해 FTP로 올린다 [확인 못 함 BR-C8] | ● "Photo Import/Remote Control" 모드가 Android 앱용 표준 PTP 모드다 [확인됨 BR-C2] | **유리**(AD-P1, 유선 기종 범위, 표준 PTP 모드) |
| **Nikon** | Nikon SDK는 Windows·macOS만 [확인됨] | NX MobileAir: **Frame.io를 Android판에 먼저 제공**(2024-12), Micro-B 폰은 OTG로 연결 [확인됨 BR-N3, BR-N4]. SnapBridge: 백그라운드 링크 모드, "중단될 수 있음" 단서는 iOS에만 [확인됨 BR-N5] | ○ USB-LAN 어댑터(유선 LAN)만 있다 [확인됨 BR-N2] | ● [MTP/PTP] = "computers or Android devices". [iPhone]은 NX MobileAir 전용 ★BR-N1 | **유리**(공식 PTP 모드, 백그라운드) |
| **Fujifilm** | **Camera Control SDK가 Android 11~15를 USB로만 지원**(Ver.1.32~1.34). Android 16은 목록에 없고 배포 형태도 공개돼 있지 않다 [확인됨 BR-F1] | XApp: Android 11~16, 문서상 OS별 차이 없음. 백그라운드 동작은 확인 못 함 [확인됨 BR-F4] | ◐ FT-XH(X-H2/H2S)만. Type-C, Micro B, Lightning 케이블을 모두 적어 두었다 [확인됨 BR-F3] | ● 폰에 "Connected to USB PTP"가 뜨고 Camera Importer 앱을 추천한다 [확인됨 BR-F2] | **유리**(공식 SDK로 USB 제어 가능) |
| **Panasonic** | LUMIX SDK는 Windows만 [확인됨 BR-P1] | LUMIX Lab: Android 11~16, OS별 차이 없음. USB로 연결하면 Auto Transfer가 안 된다 [확인됨 BR-P3] | ● GH7 Frame.io: Android는 "USB Tethering", iOS는 "Personal Hotspot" [확인됨 BR-P2] | ◐ LUMIX Lab 유선은 S9, L10만 [확인됨 BR-P3] | **같음** |
| **OM System** | 없음 | 카메라를 끈 상태의 자동 업로드에서 "앱 실행" 단계는 iOS에만 적혀 있다 [확인됨 BR-O1] | 없음 | Storage/MTP만 있고 연결 중에는 촬영할 수 없다 [확인됨 BR-O1] | **약간 유리(추측)** |
| **Leica** | 없음 | FOTOS Android판은 있다. Android 백그라운드 전송은 확인 못 함(포럼에서 옵션이 안 보인다는 보고) [일부 확인 BR-L1] | 없음 | FOTOS Cable은 iPhone용 [일부 확인 BR-L1] | **불리 또는 불명** |
| **Ricoh/Pentax** | PENTAX Wireless SDK Android(2018, 구형 4기종) [일부 확인 BR-R1]. THETA용 theta-client는 Android 지원 [확인됨 BR-R2] | GR WORLD Android 13~16, OS별 차이 없음 [확인됨 BR-R2] | 없음 | MTP만 | **같음** |
| **Hasselblad** | 없음 | **Phocus Mobile Android V1.0.0(2026-07)**: RAM 12GB 이상, Android 12 이상 [확인됨 BR-H1] | 없음 | ◐ X2D II(펌웨어 1.3.16.1 이상)만. iOS는 세 기종 모두 [확인됨 BR-H1] | **불리** |

### 1-2. 브랜드별 메모

- **Sony**
  - Sony의 휴대용 전송기 PDT-FP1이 Transfer & Tagging의 Android 15 검증 기기 목록에 있다. 카메라를 USB나 Ethernet으로 꽂으면 앱이 자동 실행되고 FTP 가져오기가 시작된다 [확인됨 BR-S2, BR-S4]. Sony 자신이 업무용 수신 장비를 Android로 만든다는 뜻이다.
  - Transfer & Tagging FAQ 원문: "It stops when the smartphone enters sleep mode (panel off) or when you press the Home button. For Android, you can avoid this by setting the application as a power-saving exception." ★BR-S3
- **Canon**
  - Content Transfer Professional은 Android 12~16, iOS 17·18·26을 지원한다. 지원 카메라는 R1, R3, R5, R5 C, R5 II, R6, R6 II, R6 III, R6 V, 1D X II/III 등이다. Android에는 Play 결제를 쓸 수 없는 사용자를 위한 APK 배포도 있다 [확인됨 BR-C3].
  - AD-P1은 안드로이드폰을 카메라 슈에 고정하고 고속 데이터 통신과 카메라 급전을 함께 한다. 접이식 폰, iPhone, USB 호스트 기능이 없는 폰은 쓸 수 없다 [확인됨 BR-C6].
  - FTP가 없는 R7, R8, R50에도 AD-P1로 붙는 공식 경로가 있다. 다만 이 기종들은 CTP를 지원하지 않아 Camera Connect를 쓰라고 안내한다. 이 조합으로 촬영 즉시 전송이 되는지는 확인 못 했다 [확인 못 함].
- **Nikon**
  - NX MobileAir 원문: "Screen timeout is disabled while NX MobileAir is running." 이 앱만 쓰는 전용 기기를 권한다 [확인됨 BR-N4].
- **Fujifilm**
  - SDK EULA에는 "SDK로 카메라를 연결·제어하면 카메라 보증이 무효"라는 문구가 있다(iOS 보고서 FUJ-2). 법인 조건은 문의 창구가 따로 있다 [확인됨 BR-F1].

---

## 2. Android 공통 해법

### 2-1. 비교표

| 해법 | 지원 범위 | 즉시성 | 원본 | 비용·라이선스 | Play 정책 위험 | 구현 난이도 | iOS 대비 |
|---|---|---|---|---|---|---|---|
| **A. 카메라 FTP → 앱 FTP 서버 + `connectedDevice` FGS** | iOS A안과 같다(FTP 내장 중급기 이상) | 높음. **화면이 꺼져도 가능**(FGS, 삼성 실기 확인 필요) | 원본 | Apache-2.0 라이브러리를 쓰거나 직접 구현, 무료 | 중간: FGS 신고와 영상, Android 17 로컬 네트워크 권한 | 중간 | iOS는 포그라운드에서만. 대신 Android는 핫스팟 IP가 무작위다 |
| **B. CascableCore** | **Android 없음** [확인됨 CM-1] | — | — | — | — | — | Android용 상용 대체품을 찾지 못했다 |
| **C/D. Canon CCAPI·Sony Camera Remote Command를 Kotlin으로 직접 구현** | 해당 브랜드 | 높음 | 원본 | 무료. 신청 조건은 iOS와 같다(한국 경로 불명, 법인 한정) | 낮음~중간 | 중간~높음 | Apple 멀티캐스트 entitlement 심사가 없다. 대신 Android 17 권한이 필요하다(추측) |
| **E. libgphoto2 NDK 빌드**(USB fd, PTP/IP) | Canon, Nikon, Fuji(실험적), 구형 Sony | 중간~높음 | 원본 | LGPL-2.1 | 중간: 재링크 요건 논쟁. 앱이 .so를 런타임에 바꿔 넣는 장치는 Play 실행 코드 정책과 충돌할 수 있다 | 높음(클로즈드 소스 Play 앱 선례 없음) | 사이드로딩이 되므로 iOS보다는 부담이 작다(견해가 갈림) |
| **E′. libpict(C) 코어 + JNI** | 범용 PTP/IP, Canon 기본 기능 | 중간~높음 | 원본 | Apache-2.0 | 낮음 | 높음(안정 릴리스 없음) | iOS와 코어를 공유할 수 있다 |
| **F. USB-C + `MtpDevice`** | PTP를 지원하는 대부분의 카메라 | 높음(`readEvent`로 ObjectAdded 수신) | 원본 | 무료 | 낮음 | 중간 | iOS ImageCaptureCore에 대응한다. 벤더 명령은 `bulkTransfer`로 직접 구현해야 한다 |
| **G. 제조사 앱 → 갤러리(MediaStore) 감지** | 제조사 앱이 있는 전 브랜드 | 낮음~중간 | 제조사 앱 설정에 따름 | 무료 | **높음**: `READ_MEDIA_IMAGES`는 갤러리처럼 사진 전반 접근이 핵심 기능인 앱만 허용 [확인됨 CM-20] | 낮음 | iOS에는 이런 Play 심사 같은 장벽이 없다 |
| **G′. 제조사 앱 저장 폴더를 SAF 폴더 권한으로 접근** | 같음 | 낮음~중간(폴링) | 같음 | 무료 | 낮음 | 낮음~중간 | iOS에는 없는 우회로다 |
| **I. Frame.io C2C** | iOS 보고서와 같음 | 중간 | 원본 | Frame.io 요금, Adobe 약관 위험 | 해당 없음 | 중간 | 플랫폼과 무관하다 |

### 2-2. A안 구현 수단

- **FTP 서버 라이브러리**
  - Apache FtpServer(ftpserver-core 1.2.1, Apache-2.0): Android에서 동작하는 사례가 있다. primitive ftpd 앱이 minSdk 26, targetSdk 36으로 쓴다 [확인됨 CM-14, CM-15].
  - MinimalFTP: Apache-2.0, 의존성 없는 순수 Java, TLS를 지원한다. Android 언급은 없다 [확인됨 CM-16].
  - SwiFTP는 GPL v3라 클로즈드 앱에 넣기 어렵다 [확인됨].
  - 카메라가 쓰는 FTP 명령은 소수라서 Kotlin으로 직접 구현해도 작다(추측).
- **화면 꺼짐 상태의 실사례**
  - primitive ftpd는 FTP 서버 서비스를 `foregroundServiceType="specialUse"`로 돌린다 [확인됨 CM-14].
  - Camera Pro Control(RupiApps)은 "파일 다운로드에 FGS를 쓰고 화면이 꺼져도 동작"한다고 밝힌다 [확인됨 CM-11].
  - CameraSync는 핫스팟 FTP 수신과 "background receiving"을 내세운다. 다운로드 100건 이상 수준의 소규모 앱이다 [확인됨 CM-11].
- **iOS 보고서에서 참고로 든 앱들의 Android 상황**
  - TetherDrop: iOS 전용으로 보인다 [일부 확인].
  - PhotoSync: 카메라 FTP 수신은 iOS판 기능이다 [확인됨 CM-13].
  - Capture One: Android판을 찾지 못했다 [일부 확인 CM-12].

### 2-3. E안: libgphoto2와 LGPL(Android)

- **Android 지원**
  - PR #918(2023-10 병합)이 `gp_port_usb_set_sys_device(int fd)`를 추가했다. 2.5.32(2025-07-06) 릴리스 노트에 정식 기능으로 올라 있다 [확인됨 CM-3].
  - libusb의 Android 사용법: `UsbDeviceConnection.getFileDescriptor()`로 fd를 얻고 `libusb_wrap_sys_device`로 감싼다 [확인됨 CM-4].
  - 실사용 앱 OpenLiveStacker는 GPL-3.0 앱이고 DSLR 지원은 "개발 중"이다. 클로즈드 앱의 선례가 되지 않는다 [확인됨 CM-5].
- **LGPL-2.1을 Play 앱에 넣는 문제**(법률 자문 아님)
  - LGPL-2.1에는 LGPLv3의 "Installation Information" 조항이 없다 [확인됨 CM-6].
  - 부정적 견해: Xebia 블로그는 "클로즈드 Android 앱에서 LGPL 준수는 불가능하다"고 본다. 라이브러리를 바꾸면 다시 서명해야 하고, 그러면 업데이트와 앱 데이터가 이어지지 않는다는 이유다.
  - 긍정적 견해: Qt 포럼 답변은 "Android는 서명 안 된 APK를 쉽게 설치할 수 있다"고 본다 [확인됨, 개인 견해 CM-6].
  - Play 정책은 Play 밖에서 실행 코드(.so 포함)를 내려받는 것을 금지한다 [확인됨 CM-7].
  - **출시 전에 법무 검토가 필요하다.**

### 2-4. F안: `MtpDevice`

- 쓸 수 있는 공개 메서드: `getObjectHandles`, `getObjectInfo`, `getObject`, `importFile`, `getThumbnail`, `readEvent(CancellationSignal)` [확인됨, 소스 AU-2].
- `MtpEvent`에 `EVENT_OBJECT_ADDED`(0x4002)와 `EVENT_CAPTURE_COMPLETE`(0x400D)가 있다 [확인됨, 소스 AU-2].
- 벤더 PTP 명령을 보내는 공개 메서드는 없다. `claimInterface`와 `bulkTransfer`로 직접 구현해야 한다 [확인됨 AU-1, AU-3].
- 권한
  - `USB_DEVICE_ATTACHED`와 `device_filter`로 꽂을 때 앱을 띄울 수 있다.
  - 이미 꽂혀 있는 장치는 `requestPermission()`으로 권한을 받는다 [확인됨 AU-1].
- 시스템 MTP 제공자는 파일 앱이 열람할 때 장치를 연다. 삼성 내 파일 앱과 충돌하는지는 실기로 확인해야 한다 [일부 확인, 소스 AU-4].

### 2-5. G·G′안: 갤러리 감시

- **Play 사진·동영상 권한 정책**: 2025-05-28부터 전면 시행됐다. 사진 전반 접근이 핵심 기능인 앱(갤러리 등)만 `READ_MEDIA_IMAGES`를 쓸 수 있고, 나머지는 시스템 사진 선택기(Photo Picker)를 써야 한다 [확인됨 CM-20].
  - 다른 앱이 저장한 사진을 감지해 올리는 앱이 허용되는지는 문서에 직접 나오지 않는다. 작가 업무 앱은 반려될 위험이 있다(추측).
- **우회**: `ACTION_OPEN_DOCUMENT_TREE`로 제조사 앱의 저장 폴더만 고르게 하고 `takePersistableUriPermission`으로 권한을 유지한다. Android 11 이후 막힌 곳은 저장소 루트, Download, Android/data 등뿐이다 [확인됨 CM-21]. 폴더 변경 알림이 없어서 주기적으로 확인해야 한다(추측).
- **2차안**: "한 번에 전송"은 Photo Picker로 여러 장을 고르게 하면 정책상 안전하다(추측).

### 2-6. 크로스플랫폼 관점

- **Kotlin Multiplatform**: ktor-network의 iOS 빌드는 있다. 하지만 Ktor 서버 Native 문서에 iOS 타깃이 없다 [확인됨 CM-17]. KMP로 짜도 iOS의 백그라운드 제약은 그대로다.
- **Flutter·React Native**
  - Flutter용 PTP 카메라 플러그인은 찾지 못했다 [확인됨].
  - React Native에는 Sony 전용 실험 단계 패키지(`expo-sony-camera`)가 있다 [확인됨 CM-18].
- **C 공통 코어**: libpict(Apache-2.0)가 PTP/IP를 Android와 iOS 양쪽에서 시험했다 [확인됨 CM-8].
- **판단**(추측)
  - FTP 수신은 플랫폼마다 따로 구현해도 비용이 작다. 공유해서 이득이 큰 부분은 PTP/IP다.
  - 클라우드 직행(4장)이 1차안이 되면 앱 쪽 카메라 코드가 거의 사라진다. 그만큼 Android 작가 앱의 기술 스택을 고를 여지가 커진다.

---

## 3. Android 플랫폼 제약

### 3-1. 요약표

| 항목 | 판정 | 핵심 근거 | iOS와의 차이 | 십분스냅 영향 |
|---|---|---|---|---|
| 현행 버전 | Android 17(API 37) | Pixel 배포 2026-06, 삼성 등은 2026-10~11 예정 [확인됨 AV-1, 배포 일정은 일부 확인 AV-6] | — | target 37 대응을 계획해야 한다 |
| Play target 요구 | API 36 이상(2026-08-31부터) | [확인됨 AV-8] | — | target 36으로 시작한다 |
| 카메라 AP 접속(`WifiNetworkSpecifier`) | **가능**(API 29+) | 첫 연결 때 다이얼로그. 특정 AP 요청은 승인이 저장되고, SSID 패턴 요청은 매번 승인 ★AN-1 | NEHotspotConfiguration과 비슷하다 | (a) 방식의 연결 UX가 무난하다 |
| 카메라 AP 접속 중 기본 경로 | **셀룰러 유지**(조건부) | 인터넷을 제공하지 않는 local-only 연결이고, 검증된 Wi-Fi일 때만 셀룰러보다 우선 ★AN-1, AN-7 | iOS는 기종과 버전마다 다르다 | Firebase SDK를 그대로 쓸 수 있다(실기 확인) |
| 카메라 트래픽만 카메라망으로 보내기 | **가능** | `Network.getSocketFactory()`, `bindSocket`, `openConnection` [확인됨, 소스 AN-8]. OkHttp는 `socketFactory`와 `dns`로 지정 [확인됨 AN-9] | iOS는 Network.framework만 된다 | PTP/IP·HTTP 클라이언트를 해당 Network에 묶는다 |
| 카메라 AP 연결 수명 | 조건부 | 포그라운드 앱이나 FGS에서 요청할 수 있다. 해제하거나 프로세스가 죽으면 끊긴다. 백그라운드로 갔다는 이유로 끊는 코드는 없다 [확인됨, 소스 AN-3~5] | iOS joinOnce는 백그라운드 15초 뒤 해제 | FGS로 화면이 꺼진 채 유지할 수 있다(실기 확인) |
| CompanionDeviceManager | 조건부 | 연결해 둔 AP는 승인 다이얼로그를 건너뛰고 백그라운드 FGS 시작 권한도 준다 [확인됨, 소스 AN-3, AN-12] | AccessorySetupKit과 비슷하다 | 카메라를 "동반 기기"로 등록하는 UX를 검토한다 |
| Wi-Fi Direct 그룹을 앱이 직접 생성 | **조건부(실기 필요)** | API 29+에서 SSID와 비밀번호를 고정할 수 있고, 일반 Wi-Fi 기기도 접속할 수 있다고 명시. GO IP는 무작위일 수 있다 [확인됨, 소스 AP-2~4] | iOS에는 없다 | 고정 AP로 쓰는 대안 후보(3-3) |
| 시스템 핫스팟 켜기·끄기 | **불가** | Device Owner와 통신사 권한 앱만 예외 [확인됨, 소스 AH-6] | 같다 | 작가가 직접 켠다 |
| LocalOnlyHotspot | 조건부(비현실적) | 시작할 때 앱이 화면에 보여야 한다. SSID와 비밀번호는 매번 무작위이고, API 36에서도 채널만 지정할 수 있다 [확인됨, 소스 AH-3~5] | iOS에는 없다 | 카메라 FTP 등록용으로 맞지 않는다 |
| 핫스팟 IP | **무작위** | 10/8 대역 93.7%, 같은 부팅 안에서는 재사용 [확인됨, 소스 AH-7] | iOS는 172.20.10.1 고정 | 카메라 FTP 주소가 바뀔 위험(3-3) |
| 핫스팟 자동 꺼짐 | 조건부 | AOSP 기본은 기기가 없으면 10분 뒤 종료. 삼성은 설정에서 바꿀 수 있다 [확인됨 AH-8, AH-9] | iOS는 트래픽 없는 서드파티 기기를 90초 뒤 끊는다(Apple 공식, 2026-10-19 정정) | 대기 중 꺼지지 않게 안내한다 |
| 로컬 네트워크 권한 | target 37부터 필요 | `ACCESS_LOCAL_NETWORK`, **수신 TCP 포함**. 거부하면 TCP는 타임아웃이 난다. 셀룰러는 제외 ★AV-4 | iOS는 나가는 연결에만 필요 | FTP 수신에도 "근처 기기" 권한 팝업이 뜬다 |
| 백그라운드 FTP 수신과 카메라 연결 유지 | **가능** | `connectedDevice` FGS(시간 제한 없음) ★AF-2, AF-1. FGS는 Doze에서 네트워크 제한 없음 [확인됨 AF-5] | iOS는 불가 | 화면을 끈 채 촬영할 수 있다(삼성 실기 확인) |
| FGS Play 신고 | 필수 | 타입마다 설명, 영향, 시연 영상 [확인됨 AF-3] | — | 출시 준비 항목에 넣는다 |
| 백그라운드 FGS 시작 | 제한(target 31+) | 촬영 세션을 시작할 때 앱 화면에서 시작해야 한다 [확인됨 AF-8] | — | 티켓 승인 화면에서 FGS를 시작한다 |
| 배터리 최적화 직접 예외 요청 | 조건부(위험) | 주변기기 동반 앱은 "주변기기에 인터넷을 제공"할 때만 허용 ★AF-4 | — | 설정 화면으로 안내하는 방식을 쓴다 |
| 삼성 FGS 신뢰성 | 조건부 | One UI 6+에서 Android 14 대상 앱의 FGS 보장을 약속 [확인됨 AF-9]. 사용자 보고는 엇갈린다 [일부 확인 AF-10] | — | 실측하고 "제한 없음" 설정을 안내한다 |
| 일괄 업로드(UIDT) | 가능(API 34+) | 앱이 보이는 상태에서 예약, 알림 필요, 쿼터 면제 [확인됨 AF-6] | iOS BGContinuedProcessingTask와 비슷 | 2차안 "한 번에 전송"에 쓴다 |
| USB `MtpDevice` | **가능** | 2-4 참조 | iOS ImageCaptureCore와 비슷 | 2차안 유선 경로 |
| 갤러리 감시 | 조건부(정책 위험) | 2-5 참조 | Play 심사가 더 엄격하다 | 1차 경로로 쓰지 않는다 |

### 3-2. 버전과 최소 SDK

- **Android 버전 점유율**(2025-12 Google 자료를 기사에서 재인용, 누적은 직접 계산) [일부 확인 AV-7]

  | 버전 | 누적 점유율 |
  |---|---|
  | 16 이상 | 7.5% |
  | 15 이상 | 26.8% |
  | 14 이상 | 44.0% |
  | 12 이상 | 69.3% |
  | 10 이상 | 90.8% |

  한국과 삼성의 비중은 확인 못 했다.
- **API별로 쓸 수 있게 되는 기능** [확인됨 AV, AN, AF, AH 각 출처]

  | API | 쓸 수 있게 되는 것 |
  |---|---|
  | 29 | `WifiNetworkSpecifier`, Wi-Fi Direct 그룹 이름 고정 |
  | 31 | STA+STA 로컬 전용 동시 연결, 백그라운드 FGS 시작 제한 |
  | 33 | `NEARBY_WIFI_DEVICES` |
  | 34 | FGS 타입 강제, UIDT |
  | 36 | `TetheringManager` 공개, LocalOnlyHotspot 채널 지정 |

- **판단**(추측): minSdk는 29~31, target은 36으로 시작하고, target 37로 올릴 때 `ACCESS_LOCAL_NETWORK`에 대응한다.

### 3-3. 핫스팟 IP 문제와 대안

- **문제**
  - 카메라 FTP 설정에는 서버 주소를 고정값으로 넣는다.
  - Android 시스템 핫스팟의 IP는 AOSP 기준으로 무작위 /24이고, 같은 부팅 안에서만 재사용한다 [확인됨, 소스 AH-7].
  - 그래서 재부팅 뒤에는 바뀔 수 있다(추측). 삼성이 고정 대역을 쓰는지는 확인 못 했다.
- **대안**
  - 앱이 현재 핫스팟 IP를 찾아 화면에 보여 주고, 바뀌었으면 카메라 설정을 다시 하게 안내한다. API 36 이상은 `TetheringManager` 이벤트로 인터페이스를 찾는다 [확인됨, 소스 AH-6].
  - **앱이 Wi-Fi Direct 그룹을 직접 만든다.**
    - SSID(`DIRECT-xy…`)와 비밀번호를 고정할 수 있다 [확인됨, 소스 AP-2].
    - 그룹 오너(GO) IP는 기본으로 192.168.49.1이다. 폰의 업스트림 네트워크가 같은 대역일 때만 무작위로 바뀐다 ★AH-7(2026-10-19 재확인). 삼성 실측은 확인 못 했다.
      - 2026-10-19 정정: 처음에는 "OEM이 고정 설정을 켰을 때만 고정"이라고 적었는데 틀렸다. `PrivateAddressCoordinator` 생성자가 P2P용으로 192.168.49.1/24를 미리 넣어 두고, `requestStickyDownstreamAddress`는 업스트림과 충돌하지 않으면 이 주소를 그대로 준다. OEM 플래그 `config_tether_enable_legacy_wifi_p2p_dedicated_ip`는 충돌이 나도 49.1을 강제하는 옵션이다.
      - 상세와 실증 항목은 [camera-direct-connection.md](camera-direct-connection.md)에 있다.
    - 이 그룹에는 인터넷 공유가 없다. 업로드는 폰의 셀룰러로 하면 된다(추측).
  - **카메라 AP에 폰이 붙고 앱이 PTP/IP나 HTTP로 가져온다(a).** 카메라가 서버이므로 IP 문제가 없다. 다만 프로토콜이 비공개라는 문제는 iOS와 같다.
  - **클라우드 직행(4장).** 호스트명이 고정되므로 IP 문제가 없다.

---

## 4. 플랫폼 무관 대안: 카메라 → 클라우드 FTPS 직행

**구조**
- 작가가 폰 핫스팟을 켜고, 카메라가 그 핫스팟의 셀룰러 인터넷으로 우리 FTPS 엔드포인트에 원본을 올린다.
- 작가 앱은 티켓 시작과 종료만 서버에 알린다.
- 서버는 업로드 이벤트를 받아 티켓에 귀속시킨다.

### 4-1. 브랜드 × 클라우드 직행 가능성

| 기종 | 프로토콜 | 인터넷 서버 공식 지원 | 서버 주소 | 루트 인증서 | 예상 |
|---|---|---|---|---|---|
| Sony a7C II | FTP, FTPES | 명시 없음. DNS 오류 문구가 있어 호스트명 해석을 전제로 한다 [확인됨 CL-S2, CL-S4] | 호스트명 가능, 255자 [확인됨 CL-S2] | 카드에서 PEM 1개(`cacert.pem`)를 가져온다 [확인됨 CL-S3] | FTPS 가능 예상. 권장 cipher가 AWS 정책과 일치 [확인됨 CL-A9, CL-S15]. TLS 세션 재개는 실증 필요 |
| Sony a1, a1 II, a7S III(v3+), a7R VI | FTP, FTPES, SFTP | 명시 없음 | 가능 [확인됨 CL-S11~S14] | FTPES는 루트 인증서 | SFTP를 쓰려면 ECDSA나 ED25519 호스트 키가 필요할 것(카메라 쪽에 rsa-sha2가 없다) [확인됨 CL-S15, 판단은 추측] |
| Canon R5 II, R6 II, R1 | FTP, FTPS, SFTP | 명시 없음 | 도메인 가능(R6 II 명시) [확인됨 CL-C4] | ROOT.CER/CRT/PEM 중 1개 [확인됨 CL-C1] | FTPS와 SFTP 모두 실증 필요. SFTP도 비밀번호 인증뿐 |
| Canon R6 III, R6 V | FTP, FTPS | 명시 없음 | 주소 설정 [확인됨 CL-C2, CL-C3] | 위와 같음 | FTPS 실증 필요 |
| Nikon Z9, Z8, Z6III | FTP, SFTP, FTPS | **미지원 명시** [확인됨 CL-N2, CL-N5] | URL 또는 IP | ROOT.* 1개 | 클라우드 FTP 서비스(Rilavek)의 핫스팟 설정 가이드가 있다 [일부 확인 CL-P2]. 공식 지원 밖 |
| Fujifilm GFX100 II, X-H2 + FT-XH | FTP, FTPS | **X-H2는 "Internet FTP servers"를 명시** [확인됨 CL-F3] | 형식 미기재 | 자체 서명 루트를 가져올 수 있다 [확인됨 CL-F1] | FTPS 실증 필요 |

연결이 끊긴 동안 찍은 사진은 4사 모두 카메라가 들고 있다가 다시 연결되면 보낸다. 다만 전원을 끈 경우는 다르다 [확인됨 CL-S5, CL-C1, CL-N2, CL-F1].
- Canon: 전원을 끄면 자동 재시도가 사라진다.
- Nikon: 전원을 꺼도 업로드 표시가 남는다.
- Fujifilm: 전원이 꺼진 상태에서도 전송한다.
- Sony: 전원을 껐을 때의 동작이 문서에 없다.

### 4-2. AWS Transfer Family

- **엔드포인트**
  - FTPS는 "VPC 호스팅 + 인터넷 연결(Elastic IP)" 엔드포인트로만 인터넷에 열 수 있다. Public 엔드포인트는 SFTP만 된다.
  - 평문 FTP는 VPC 내부 전용이다.
  - Explicit FTPS와 패시브 모드만 지원한다. 데이터 포트는 8192~8200이다 [확인됨 CL-A2~A5, CL-A11].
- **TLS 세션 재개** ★CL-A6
  - `TlsSessionResumptionMode`는 따로 지정하지 않으면 `ENFORCED`다. 이때 세션을 재개하지 않는 클라이언트의 데이터 연결은 거부한다.
  - 원문: "Not all FTPS clients perform TLS session resumption … you need to test your clients."
  - 카메라가 세션을 재개하는지는 4사 문서 모두에 없다 [확인 못 함].
  - 실증할 때 `ENFORCED`로 먼저 시험하고, 실패하면 `ENABLED`로 바꾼다(추측).
- **PassiveIp**: 기본값 `AUTO`는 PASV 응답에 엔드포인트 IP 하나를 돌려준다 ★CL-A6. 인터넷 연결 엔드포인트에서 이 값이 Elastic IP인지는 실증해야 한다 [확인 못 함].
- **인증**
  - 서비스가 직접 관리하는 사용자에는 비밀번호를 저장할 수 없다. 카메라는 비밀번호 인증뿐이므로 **Lambda 커스텀 IdP가 필수**다 [확인됨 CL-A11, CL-A7].
  - Lambda는 `username`, `password`, `protocol`, `sourceIp`를 받아 사용자별 S3 경로와 세션 정책을 돌려준다 [확인됨 CL-A7].
- **후처리**: EventBridge `FTPS Server File Upload Completed` 이벤트에 `username`, `file-path`, `bytes`, `session-id`, 시작·종료 시각이 들어 있다 [확인됨 CL-A8]. 티켓 귀속에 필요한 정보가 모두 있다.
- **요금(서울)** ★CL-A13
  - 프로토콜마다 시간당 $0.30, 업로드·다운로드 GB당 $0.04.
  - 서버를 정지해도 과금되고, 삭제해야 멈춘다 [확인됨 CL-A14].

  | 구성 | 월 비용(730시간) |
  |---|---|
  | FTPS 하나, 월 50GB | 약 $228 (엔드포인트 $219 + 데이터 $2 + Elastic IP 추정 $7.3) |
  | FTPS 하나, 월 300GB | 약 $238 |
  | FTPS + SFTP, 월 300GB | 약 $457 |
  | 실증용으로 하루 켰다가 삭제 | 약 $7.2 |

  Elastic IP 요금 $0.005/시간이 적용되는지는 문서에 명시되지 않았다(추측) [CL-A15].

### 4-3. 직접 운영하는 대안

- **SFTPGo**
  - 라이선스: AGPL-3.0-only에 추가 조건이 붙는다 [확인됨 CL-O1].
  - 지원: SFTP, FTP/S, S3·GCS 백엔드, 외부 인증 훅, 업로드 이벤트 훅, ACME 인증서 자동화 [확인됨 CL-O1~O4].
  - Lightsail $12 번들 + S3로 월 $15~25 수준이 될 것으로 본다 [요금은 확인됨 CL-A16, 합계는 추측].
  - 대신 패치, 장애, 브루트포스 방어를 직접 운영해야 한다(추측).
  - AGPL 의무 범위는 법무에 확인한다.
- **Google Cloud**
  - 관리형 Cloud FTP(SFTP)는 SSH 공개키 인증만 받고 IP 허용 목록이 필수다 [확인됨 CL-G2, CL-G3]. 그래서 카메라에 쓸 수 없다(추측, 근거 강함).
  - Firebase에는 FTP 수단이 없다(추측).
- **더 싼 서버 후보**(2026-10-19 추가)

  | 서버 | 월 비용 | 확인 | 주의점 |
  |---|---|---|---|
  | Oracle Cloud Always Free(서울을 홈 리전으로) | $0 | AMD Micro 2대, 아웃바운드 월 10TB, 홈 리전 한정 [확인됨 CL-O5] | 7일간 CPU 95퍼센타일·네트워크가 20% 미만이면 유휴로 보고 회수할 수 있다 [확인됨 CL-O5]. 카메라 수신 전용 서버는 이 조건에 걸리기 쉽다(추측). 상업적 사용 조건은 확인 못 함 |
  | Vultr 서울 Cloud Compute 1 vCPU·1GB | 약 $5 | 제3자 가격 집계만 [일부 확인 CL-O6] | 공식 가격 페이지는 열지 못했다 |
  | AWS Lightsail 서울 | $12 번들 | [확인됨 CL-A16] | AWS 안에서 끝난다 |
  | GCP 무료 e2-micro | $0 | us-west1, us-central1, us-east1만 [확인됨 CL-O7] | 한국에서 멀고, 외부 IPv4는 무료 범위 밖일 수 있다 [일부 확인] |
  | 집 맥미니·NAS | 전기료 | KT 약관은 승인 없는 사업용 서버(FTP 포함) 설치를 이용 제한 사유로 든다 [확인됨 CL-K1] | 실증용으로만 쓴다. 정전·회선 장애가 전체 장애가 되고, 집 네트워크가 인터넷에 열린다. NAS는 개인 자료가 있어 더 위험하다(추측) |

- **판단**(2026-10-19 갱신, 추측)
  - 클라우드 직행을 다시 검토하게 되면, 실증은 맥미니나 Oracle 무료 서버에서 SFTPGo로 한다. 우리끼리 시험하는 동안에는 외부 사용자가 없어 AGPL 문제도 생기지 않는다.
  - 운영은 Vultr나 Lightsail 같은 월 $5~12 서버에서 시작한다. SFTPGo의 GCS 백엔드로 Firebase Storage 버킷에 바로 저장하면 사진 경로는 B안과 같아진다.
  - Transfer Family는 작가가 많아져 고정비가 작가 1인당 몇 달러로 내려가고, 서버를 운영할 인력이 없을 때 검토한다. 처음 쓴 판단("운영은 Transfer Family")은 비용을 초기 규모와 비교하지 않은 것이라 바꿨다.

### 4-4. 핫스팟 유지와 데이터

- **iPhone**
  - 화면이 잠기거나 앱이 백그라운드일 때 핫스팟이 유지되는지는 Apple 공식 문서에 없다 [확인 못 함 CL-H1, CL-H2].
  - 저전력 모드의 공식 제한 목록에 핫스팟은 없다 [확인됨 CL-H3]. 실측해야 한다.
- **삼성**: "연결된 기기가 없을 때 끄기"에서 시간 간격을 고를 수 있다 [확인됨 CL-H6].
- **테더링 데이터 한도**
  - 카메라 업로드 전체가 테더링 데이터로 잡힌다(추측). SKT 5GX 프라임은 테더링·공유 통합 월 60GB다 [확인됨 CL-H8, 이 요금제는 2026-07-02 신규 가입 중단].
  - 추정(추측): 원본 JPEG 장당 10~20MB × 티켓당 40장 × 하루 6건 × 월 25일 ≈ 60~120GB. 한도를 넘을 수 있다.
  - 폰 앱 수신 방식은 앱이 직접 올리므로 폰 자신의 데이터로 잡힌다. 테더링 한도와는 무관할 것이다(추측).

### 4-5. 서버 쪽 티켓 귀속(추측, 설계안)

1. **계정**: 작가마다, 가능하면 카메라 바디마다 FTPS 계정을 하나씩 발급한다. 카메라 FTP의 업로드 디렉터리는 고정값이라 티켓마다 바꾸게 할 수 없다 [확인됨 CL-S2, CL-C1].
2. **작가 앱**: 티켓 시작과 종료 시각만 서버에 기록한다. 포그라운드를 계속 유지할 필요가 없다.
3. **귀속 함수**: 업로드 완료 이벤트에서 계정으로 작가를 찾는다. 그다음 EXIF `DateTimeOriginal`(1순위)과 수신 시각(보조)을 티켓 시간 창과 대조한다. 맞는 티켓이 없으면 "미분류"로 둔다.
4. **카메라 시계 오차**: 첫 파일의 EXIF 시각과 서버 수신 시각의 차이로 오프셋을 추정한다.
5. **저장 키**: 원본 파일명이 겹쳐도 덮어쓰지 않도록 `inbox/<photographerId>/<session-id>/<원본명>`으로 받고, 귀속 단계에서 티켓 경로로 연결한다.

같은 귀속 규칙은 폰 앱 수신 경로(앱이 올린 파일)에도 그대로 쓸 수 있다. 서버 귀속 로직을 하나로 두면 경로를 바꾸기 쉽다.

### 4-6. 보안

- 평문 FTP는 인터넷에 열지 않는다. AWS도 막고, Config 규칙으로도 비준수 판정을 한다 [확인됨 CL-A2, CL-A17].
- 카메라 안에 계정이 저장되는 방식은 문서에 없다 [확인 못 함]. 카메라를 잃어버리면 계정이 유출된 것으로 보고 다룬다(추측).
- 완화책(추측)
  - 바디별 계정을 쓰고 즉시 끌 수 있게 한다.
  - 세션 정책을 **쓰기 전용**으로 준다(목록 조회·다운로드 금지).
  - 로그인 실패 횟수를 제한한다.
  - 활성 티켓이 없는데 업로드가 들어오면 경보를 낸다.
- 카메라의 "인증서 오류 무시" 옵션(Sony Connect, Canon Trusting target servers, Nikon Connect if authentication fails)은 쓰지 않는다 [확인됨 CL-S2, CL-C1, CL-N1].
- Canon과 Nikon은 루트 인증서를 1개만 넣을 수 있다. ACM 공개 인증서를 쓰면 Amazon Root CA 1(만료 2038-01-17)을 넣는 방식이 장기 운영에 유리하다(추측) [만료일은 확인됨 CL-A18].

### 4-7. 폰 앱 수신 vs 클라우드 직행

| 항목 | 폰 앱 FTP 수신 | 클라우드 직행 |
|---|---|---|
| 앱 포그라운드 | iOS 필수, Android는 FGS로 해결 | **불필요**(핫스팟만 유지) |
| 서버 주소 | iOS는 172.20.10.1 고정, **Android는 무작위 IP** | 호스트명 고정 |
| 데이터 집계 | 폰 자체 데이터(추측) | **테더링 한도에서 차감** |
| 서버 비용 | 기존 업로드 비용 | 직접 운영 월 $0~25 + 운영 부담, 또는 Transfer Family 월 약 $228~ (4-3) |
| 고객이 첫 사진을 보는 속도 | 앱이 원본을 받은 뒤 축소본부터 먼저 올릴 수 있다 | 원본 전체가 셀룰러로 올라간 뒤 서버가 축소본을 만든다. 더 느릴 수 있다(추측) |
| 작가가 보내기 전에 고르기 | 사진이 폰에 있어 바로 할 수 있다 | 서버에서 축소본을 다시 내려받아야 한다(추측) |
| 보안 | 평문 FTP가 핫스팟 내부에만 있음 | 인터넷 노출, FTPS 필수, 카메라에 장기 계정 저장 |
| 티켓 귀속 | 앱 세션 상태로 바로 | 계정 + 시간 창 + EXIF로 서버가 추론 |
| 공식 지원 범위 | Nikon은 서드파티 FTP 서버를 공식 지원하지 않음 | Nikon은 인터넷 FTP를 공식 지원하지 않음. Fujifilm X-H2는 명시적으로 지원 |
| 플랫폼 차이 | 큼 | 작음 |

---

## 5. 권장 구조 (iOS + Android 통합)

### 5-1. 결론

| 구분 | iOS | Android | 비고 |
|---|---|---|---|
| **1차(결정) B**: 앱 FTP 수신 | 포그라운드·화면 켜짐 필수(iOS 보고서 4장). 촬영 세션 중 자동 잠금을 막는다 | `connectedDevice` FGS로 화면이 꺼져도 된다. 핫스팟 IP 변경에 대응해야 한다 | 초기 기본 경로. 서버 고정비가 없다 |
| **보완 C**: 카메라 AP + Pull 방식 | Sony Camera Remote Command, CascableCore | Kotlin으로 직접 구현(CCAPI, Camera Remote Command) | FTP가 없는 기종용. 신청 조건 확인이 필요하다 |
| **2차**: 일괄 전송 | USB-C + ImageCaptureCore, BGContinuedProcessingTask | USB-C + `MtpDevice`, UIDT. 제조사 앱을 거친 사진은 Photo Picker로 고른다 | 브랜드를 가리지 않는다 |
| **보류 A**: 클라우드 FTPS 직행 | 핫스팟만 유지하면 된다 | 같음 | 재검토 조건: 파일럿에서 iOS 작가가 앱 화면 유지를 감당하지 못할 때. 서버는 4-3의 저비용 후보부터 |

**결정(2026-10-19, 사용자)**: 초기에는 서버 없이 B안으로 간다. 사진을 티켓에 연결하는 규칙(4-5)은 서버 쪽 한곳에 두는 것을 권한다. 그러면 나중에 A안을 붙여도 다시 만들 부분이 적다(추측).

### 5-2. Android 작가 앱 구현 메모(초안, 추측)

- **SDK 버전**: minSdk 29~31, target 36으로 시작한다. target 37로 올릴 때 `ACCESS_LOCAL_NETWORK` 요청 흐름을 넣는다.
- **촬영 세션**
  - 티켓을 승인하는 화면에서 `connectedDevice|dataSync` FGS를 시작한다. 알림에 수신 장수와 업로드 상태를 보여 준다.
  - 매니페스트: `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `CHANGE_WIFI_STATE`, `CHANGE_NETWORK_STATE`, `NEARBY_WIFI_DEVICES`(`neverForLocation`).
- **B안 수신**
  - Apache FtpServer나 MinimalFTP, 또는 직접 구현한 최소 FTP 서버로 패시브 모드만 받는다.
  - 앱이 현재 핫스팟 인터페이스 IP를 화면에 보여 준다.
  - `bindProcessToNetwork`는 쓰지 않는다.
- **(a) 방식을 쓸 때**: `WifiNetworkSpecifier`로 정확한 SSID를 지정해 요청한다. 카메라 소켓은 `network.socketFactory`로 묶고, 업로드는 기본 경로(셀룰러)로 둔다.
- **배터리**: `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` 화면으로 안내하고, 삼성 "제한 없음" 설정 가이드를 앱 안에 둔다.
- **Play 제출**: `connectedDevice` FGS 신고와 시연 영상을 준비한다. 앱 안에서 카메라를 연결하고 주고받는 장면이 들어가야 한다 [확인됨 AF-3].

### 5-3. 실증 순서(iOS 보고서 4-6 체크리스트에 더해)

B안이 초기 기본 경로로 정해졌으므로 B안 실증을 앞에 둔다(2026-10-19 순서 변경).

1. **갤럭시 + a7C II, B안**: 시스템 핫스팟 + 앱 FTP + FGS, 화면 꺼진 상태 30분. 핫스팟을 껐다 켤 때와 재부팅 후 IP가 어떻게 바뀌는지.
2. **갤럭시 Wi-Fi Direct 그룹**: 앱이 만든 고정 SSID 그룹에 카메라 FTP가 붙는지, 그때 GO IP는 무엇인지. 붙으면 A4(IP 무작위)가 풀린다.
3. **iPhone B안 세션 유지**: 앱 화면을 켠 채 30분 촬영할 때 배터리 소모와 발열, 화면이 꺼졌다 돌아온 뒤 카메라 재전송이 되는지.
4. **갤럭시 USB**: `MtpDevice.readEvent`로 촬영 시 ObjectAdded가 오는지, 삼성 내 파일 앱과 충돌하는지.
5. **갤럭시 (a) 방식**: 카메라 AP(`WifiNetworkSpecifier`)에 붙은 채 Firebase Storage 업로드가 셀룰러로 되는지.
6. **기준선**: Sony Transfer & Tagging Android에서 절전 예외를 켠 채 화면을 끄고 FTP를 받는다.
7. **Canon R5 II/R6 III, Nikon Z6III**: 1번과 같은 시험.
8. **(보류 A안을 재검토할 때만) 클라우드 직행 a7C II**
   - 핫스팟 → 맥미니나 Oracle 무료 서버의 SFTPGo FTPS. AWS 비용 없이 시험한다.
   - TLS 세션 재개를 강제한 설정과 끈 설정, PASV IP, 루트 인증서 검증
   - 카메라가 보내는 명령(MKD, LIST, SIZE)과 쓰기 전용 정책이 호환되는지
   - iPhone 잠금 상태 30분에서 핫스팟과 카메라 업로드가 유지되는지(저전력 모드 유무별)

### 5-4. 추가 위험 요소(iOS 보고서 4-7에 더해)

| # | 위험 | 영향 | 완화책 |
|---|---|---|---|
| A1 | FTPS 데이터 채널의 TLS 세션 재개 비호환 | 클라우드 직행이 막힌다 | `ENABLED`로 바꾸거나 SFTPGo 설정으로 시험한다 |
| A2 | 테더링 데이터 한도 | 작가 요금 초과 | 전송 대상을 JPEG로 제한한다. Canon은 FTP 전송 크기를 줄일 수 있다. 요금제 기준을 정한다. 폴백으로 B안을 둔다 |
| A3 | 서버 고정비(Transfer Family 월 약 $219~) | 초기 비용 부담 | 초기에는 서버를 쓰지 않는다(결정). A안을 재검토할 때도 월 $0~12 서버부터 시작한다(4-3) |
| A4 | Android 핫스팟 IP 무작위 | B안에서 카메라 재설정이 필요하다 | IP 표시와 재설정 안내, Wi-Fi Direct 그룹 실증. B안이 기본 경로가 됐으므로 우선순위가 올라갔다 |
| A5 | 삼성 배터리 최적화·FGS 종료 | 화면을 끈 상태의 수신이 끊긴다 | 실측, 설정 가이드, FGS 정책 준수 |
| A6 | Play FGS 신고·사진 권한 정책 | 심사 지연이나 반려 | 시연 영상을 준비한다. `READ_MEDIA_IMAGES`를 쓰지 않는다 |
| A7 | Android 17 `ACCESS_LOCAL_NETWORK` | target 37부터 FTP 수신과 카메라 연결이 막힌다 | 연결 마법사에서 권한을 요청하고, 거부되면 안내한다 |
| A8 | Nikon 인터넷 FTP 공식 미지원 | 펌웨어가 바뀌면 동작이 달라질 수 있다 | 기종·펌웨어 호환 목록을 관리한다 |
| A9 | 카메라에 계정이 장기 저장됨 | 분실하면 유출 | 바디별 계정, 쓰기 전용, 즉시 폐기 |
| A10 | libgphoto2를 쓰는 경우 | LGPL과 Play 정책 | 쓰지 않는 쪽을 권한다. 쓴다면 법무 검토를 받는다 |

### 5-5. 사용자 확인이 필요한 항목

- ~~클라우드 직행 실증용 AWS 리소스 생성과 비용 승인~~: 초기에 서버를 쓰지 않기로 해서 필요 없어졌다(2026-10-19).
- (A안을 재검토할 때) SFTPGo를 외부 사용자에게 운영한다면 AGPL 의무 범위 법무 확인
- 원본 전송 정책(고객에게 원본 JPEG를 줄지, 축소본을 줄지). B안에서는 폰 자체 데이터로 잡히므로 테더링 한도 기준은 A안을 재검토할 때 정한다(추측).
- Android 작가 앱의 기술 스택과 최소 지원 버전
- Fujifilm SDK Android 배포 형태 확인(EULA 동의 후 다운로드)
- 갤럭시 실증 기기 확보(One UI 버전 기록)

---

## 6. 출처

모두 2026-10-17에 확인했다. ★는 원문을 다시 열어 교차 확인한 출처, "(보조)"는 2차 출처다.

### 브랜드별 Android 경로 (BR)
- BR-S1 Transfer & Tagging 지원 환경·형식: https://support.d-imaging.sony.co.jp/app/transfer/en/index.php
- BR-S2 Transfer & Tagging FTP 가져오기: https://support.d-imaging.sony.co.jp/app/transfer/en/instruction/21_ftp.php
- BR-S3 ★ Transfer & Tagging FAQ: https://support.d-imaging.sony.co.jp/app/transfer/en/faqs/index.php
- BR-S4 Transfer & Tagging 검증 기기: https://support.d-imaging.sony.co.jp/app/transfer/en/devices/
- BR-S5 α7C II 스마트폰 USB 테더링: https://helpguide.sony.net/di/ftp_2360/v1/en/contents/smartphone_connection.html
- BR-S6 FX3 USB 테더링: https://helpguide.sony.net/di/ftp_2035/v1/en/contents/TP0003032502.html
- BR-S7 Creators' App: https://helpguide.sony.net/di-app/ca/v1/en/index.html , https://helpguide.sony.net/di-app/ca/v1/en/contents/CA_usb_connect.html
- BR-S8 (보조, 403으로 검색 요약만) Creators' App Android 백그라운드 알림: https://www.sony.co.in/electronics/support/articles/CCCA99018
- BR-S9 Sony SDK·Camera Remote Command: https://support.d-imaging.sony.co.jp/app/sdk/en/index.html , https://support.d-imaging.sony.co.jp/app/cameraremotecommand/en/index.html
- BR-C1 Canon CCAPI·EDSDK: https://asia.canon/en/campaign/developerresources/camera/cap
- BR-C2 R6 Mark III USB 앱 선택: https://cam.start.canon/en/C022/manual/html/UG-07_Network_0180.html
- BR-C3 Content Transfer Professional: https://app.ssw.imaging-saas.canon/app/en/ctp.html
- BR-C4 ★ CTP 매뉴얼(유선 제한, AD-P1): https://cam.start.canon/en/S013/manual/html/UG-00_Before_0020.html , https://cam.start.canon/en/S013/manual/html/UG-01_CTP-i_0030.html
- BR-C5 Mobile File Transfer: https://cam.start.canon/en/S001/manual/html/UG-00_Before_0020.html , https://personal.canon.jp/product/camera/software/content-transfer-pro
- BR-C6 AD-P1: https://personal.canon.jp/product/camera/accessory/multispadapter-ad-p1
- BR-C7 Camera Connect: https://cam.start.canon/en/C022/manual/html/UG-07_Network_0030.html , https://asia.canon/asia/en/consumer/camera-connect/main/specification?category=&subCategory=
- BR-C8 R5 Mark II 통신 기능 목차: https://cam.start.canon/en/C017/manual/html/UG-06_Network_0010.html
- BR-N1 ★ Z8 USB 데이터 연결: https://onlinemanual.nikonimglib.com/z8/en/nwm_usb_%20data_connection_357.html
- BR-N2 Z8 USB-LAN: https://onlinemanual.nikonimglib.com/z8/en/ftp_servers_connecting_via_ethernet_93.html
- BR-N3 NX MobileAir Frame.io(2024-12): https://www.nikonusa.com/press-room/nx-mobile-air-frame-io
- BR-N4 NX MobileAir 연결: https://nikonimglib.com/nxmoba/onlinehelp/en/03_connect_01.html , https://nikonimglib.com/nxmoba/onlinehelp/en/01_about_02.html
- BR-N5 SnapBridge 자동 다운로드: https://nikonimglib.com/snbr/onlinehelp/en/downloading_pictures_as_they_are_taken_10.html , https://www.nikonimglib.com/snbr/onlinehelp/en/auto_download_49.html
- BR-F1 Fujifilm SDK: https://www.fujifilm-x.com/global/special/camera-control-sdk/ , https://www.fujifilm-x.com/global/camera-control-sdk/contact/
- BR-F2 Fujifilm USB: https://fujifilm-dsc.com/en/manual/x-t5/connections/usage_usb/ , https://fujifilm-dsc.com/en/manual/x-h2_connection/overview_usage/usage_usb/index.html
- BR-F3 FT-XH FTP: https://fujifilm-dsc.com/en/manual/x-h2_connection/overview_usage/ftp_upload/
- BR-F4 XApp: https://www.fujifilm-x.com/global/support/compatibility/software/xapp/ , https://www.fujifilm-x.com/global/products/software/xapp/
- BR-P1 LUMIX SDK: https://av.jpn.support.panasonic.com/support/global/cs/soft/tool/sdk.html
- BR-P2 GH7 Frame.io 테더링: https://eww.pavc.panasonic.co.jp/dscoi/DC-GH7/html/DC-GH7_DVQP3109_eng/0148.html
- BR-P3 LUMIX Lab: https://av.jpn.support.panasonic.com/support/global/cs/soft/lumix_lab/en/index.html , https://av.jpn.support.panasonic.com/support/global/cs/soft/lumix_lab/en/cts/b0_usb_l10_s9.html
- BR-O1 OM System: https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/auto_upload_images_camera_off_278.html , https://software.omsystem.com/oishare/en/ , https://learning.omsystem.com/OM-1MarkII/zz_html_manual/en/copying_pictures_computer_300.html
- BR-L1 (보조) Leica: https://www.l-camera-forum.com/topic/418870-background-transfer-survey-your-opinion/page/2 , https://www.bhphotovideo.com/c/product/1683019-REG/leica_24031_fotos_cable.html
- BR-R1 (보조) PENTAX SDK: https://petapixel.com/2018/05/17/ricohs-new-camera-sdks-open-the-door-to-3rd-party-apps/ , https://www.pentaxforums.com/articles/pentax-news/ricoh-releases-sdk-for-pentax-cameras.html
- BR-R2 GR WORLD, Image Sync, theta-client: https://www.ricoh-imaging.co.jp/japan/products/app/gr-world/ , https://www.ricoh-imaging.co.jp/japan/products/app/image-sync2/manual-00.html , https://github.com/ricohapi/theta-client
- BR-H1 Hasselblad Phocus Mobile Android: https://master.hasselblad.com/press/press-releases/2026/hasselblad-brings-phocus-mobile-to-android , https://www.hasselblad.com/phocus/phocus-mobile-2/ , (보조) https://www.techno-edge.net/release/prtimes2/20260716/23955.html

### Android 공통 해법 (CM)
- CM-1 CascableCore: https://developer.cascable.se/ , https://github.com/Cascable/cascablecore-distribution
- CM-2 (보조) Sony SDK 라이선스, GoPro: https://support.d-imaging.sony.co.jp/app/sdk/licenseagreement_d/ja.html , https://gopro.com/en/au/info/open-gopro
- CM-3 libgphoto2 Android: https://github.com/gphoto/libgphoto2/pull/918 , https://github.com/gphoto/libgphoto2/releases/tag/v2.5.32 , https://github.com/gphoto/libgphoto2/releases/tag/v2.5.34 , https://github.com/gphoto/libgphoto2/issues/683 , https://raw.githubusercontent.com/gphoto/libgphoto2/master/COPYING
- CM-4 libusb Android: https://github.com/libusb/libusb/blob/master/android/README
- CM-5 libgphoto2android, OpenLiveStacker: https://github.com/thebino/libgphoto2android , https://github.com/artyom-beilis/OpenLiveStacker
- CM-6 LGPL 견해: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt , https://xebia.com/blog/the-lgpl-on-android/ , https://forum.qt.io/post/35604 , https://forum.qt.io/post/518096 , https://ffmpeg.org/legal.html
- CM-7 Play Device and Network Abuse: https://support.google.com/googleplay/android-developer/answer/16559646
- CM-8 libpict, libfuji, fudge: https://github.com/petabyt/libpict , https://github.com/petabyt/libfuji , https://github.com/petabyt/fudge
- CM-9 소규모 PTP 프로젝트: https://github.com/michaelzoech/remoteyourcam-usb , https://github.com/mvpzac/Imagedge
- CM-10 MtpDevice 레퍼런스: https://developer.android.com/reference/android/mtp/MtpDevice
- CM-11 Android 앱 사례(Play): https://play.google.com/store/apps/details?id=eu.chainfire.dslrcontroller , https://play.google.com/store/apps/details?id=info.qdd , https://dslrdashboard.info/downloads/ , https://play.google.com/store/apps/details?id=com.HeliconSoft.HeliconRemote2 , https://play.google.com/store/apps/details?id=com.rupiapps.cameraconnectcast , https://play.google.com/store/apps/details?id=com.rupiapps.cameraprocontrol , https://play.google.com/store/apps/details?id=top.xlxs.camerasync
- CM-12 (보조) Capture One Mobile: https://petapixel.com/2026/07/15/capture-one-brings-wireless-tethering-to-mobile/
- CM-13 PhotoSync: https://www.photosync-app.com/support/camera/answers/how-to-configure-photosync-to-receive-photos-videos-from-cameras-over-ftp.html , https://www.photosync-app.com/features
- CM-14 primitive ftpd: https://github.com/wolpi/prim-ftpd , https://raw.githubusercontent.com/wolpi/prim-ftpd/master/gradle/libs.versions.toml
- CM-15 Apache FtpServer: https://repo1.maven.org/maven2/org/apache/ftpserver/ftpserver-core/maven-metadata.xml , https://mina.apache.org/ftpserver-project/embedding_ftpserver.html
- CM-16 MinimalFTP, Flutter ftp_server: https://github.com/Guichaguri/MinimalFTP , https://pub.dev/packages/ftp_server
- CM-17 Ktor 서버 Native: https://ktor.io/docs/server-native.html
- CM-18 expo-sony-camera: https://github.com/jongan69/expo-sony-camera
- CM-19 JobInfo 콘텐츠 트리거, Immich: https://developer.android.com/reference/android/app/job/JobInfo.Builder , https://docs.immich.app/features/automatic-backup
- CM-20 Play 사진·동영상 권한 정책, 부분 접근: https://support.google.com/googleplay/android-developer/answer/14115180 , https://support.google.com/googleplay/android-developer/answer/16935362 , https://developer.android.com/about/versions/14/changes/partial-photo-video-access
- CM-21 SAF 폴더 접근: https://developer.android.com/training/data-storage/shared/documents-files

### Android 플랫폼 (AV·AN·AP·AH·AE·AF·AU·AM)
- AV-1 Android 17: https://developer.android.com/about/versions/17
- AV-2 Android 17 동작 변경(target 37): https://developer.android.com/about/versions/17/behavior-changes-17
- AV-3 Android 17 동작 변경(전체): https://developer.android.com/about/versions/17/behavior-changes-all
- AV-4 ★ 로컬 네트워크 권한(2026-10-02 갱신): https://developer.android.com/privacy-and-security/local-network-permission
- AV-5 로컬 네트워크 정의: https://developer.android.com/privacy-and-security/local-network-definition
- AV-6 (보조) Android 17 배포: https://techcabal.com/2026/05/23/phones-getting-the-android-17-update/ , https://www.gsmarena.com/android_17_stable_update_is_rolling_out_to_pixel_phones-news-73308.php , https://www.latestly.com/technology/android-17-official-rollout-check-complete-list-of-eligible-devices-for-samsung-oneplus-motorola-nothing-and-others-7480429.html/amp
- AV-7 (보조) 버전 점유율: https://9to5google.com/2026/01/30/android-16-is-on-7-5-of-devices-in-latest-distribution-numbers-update/
- AV-8 Play 대상 API 요구: https://support.google.com/googleplay/android-developer/answer/11926878
- AN-1 ★ Wi-Fi 피어 연결(WifiNetworkSpecifier): https://developer.android.com/develop/connectivity/wifi/wifi-bootstrap
- AN-2 WifiNetworkSpecifier 소스: https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/java/android/net/wifi/WifiNetworkSpecifier.java
- AN-3 WifiNetworkFactory 소스: https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/service/java/com/android/server/wifi/WifiNetworkFactory.java
- AN-4 FrameworkFacade 소스: https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/service/java/com/android/server/wifi/FrameworkFacade.java
- AN-5 ConnectivityService 소스: https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/service/src/com/android/server/ConnectivityService.java
- AN-6 STA+STA 동시 연결: https://source.android.com/docs/core/connect/wifi-sta-sta-concurrency
- AN-7 네트워크 상태 읽기(기본 네트워크): https://developer.android.com/develop/connectivity/network-ops/reading-network-state
- AN-8 Network 소스: https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/framework/src/android/net/Network.java
- AN-9 OkHttpClient 소스: https://github.com/square/okhttp/blob/master/okhttp/src/commonJvmAndroid/kotlin/okhttp3/OkHttpClient.kt
- AN-10 Firebase Storage Android 네트워크 계층: https://github.com/firebase/firebase-android-sdk/blob/main/firebase-storage/src/main/java/com/google/firebase/storage/network/NetworkRequest.java
- AN-11 Android 10 개인정보 변경(구형 Wi-Fi API): https://developer.android.com/about/versions/10/privacy/changes
- AN-12 Companion device pairing: https://developer.android.com/develop/connectivity/bluetooth/companion-device-pairing
- AP-1 Wi-Fi Direct: https://developer.android.com/develop/connectivity/wifi/wifip2p
- AP-2 WifiP2pConfig 소스(Android 10 공개 여부): https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/java/android/net/wifi/p2p/WifiP2pConfig.java , https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-10.0.0_r1/api/current.txt
- AP-3 WifiP2pGroup 소스: https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/java/android/net/wifi/p2p/WifiP2pGroup.java
- AP-4 WifiP2pServiceImpl 소스: https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/service/java/com/android/server/wifi/p2p/WifiP2pServiceImpl.java
- AP-5 Wi-Fi Aware: https://developer.android.com/develop/connectivity/wifi/wifi-aware
- AH-1 LocalOnlyHotspot: https://developer.android.com/develop/connectivity/wifi/localonlyhotspot
- AH-2 WifiManager 소스: https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/java/android/net/wifi/WifiManager.java
- AH-3 WifiServiceImpl 소스: https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/service/java/com/android/server/wifi/WifiServiceImpl.java
- AH-4 WifiApConfigStore 소스: https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/service/java/com/android/server/wifi/WifiApConfigStore.java
- AH-5 SoftApConfiguration 소스·공개 API: https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/java/android/net/wifi/SoftApConfiguration.java , https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/framework/api/current.txt
- AH-6 TetheringManager 공개 API·권한: https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/Tethering/common/TetheringLib/api/current.txt , https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/Tethering/src/com/android/networkstack/tethering/TetheringService.java
- AH-7 핫스팟 IP 할당: https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/main/staticlibs/device/com/android/net/module/util/PrivateAddressCoordinator.java
- AH-8 삼성 핫스팟 자동 꺼짐: https://www.samsung.com/us/support/answer/ANS00079036 , (보조) https://r2.community.samsung.com/t5/Tech-Talk/Auto-turning-off-Hotspot-feature-not-available/m-p/20370917
- AH-9 AOSP 핫스팟 종료 기본값: https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/main/service/ServiceWifiResources/res/values/config.xml
- AH-10 (보조, 과거 기사) 국내 테더링 한도: https://www.newsis.com/view/NISX20220801_0001963445 , https://www.dailian.co.kr/news/view/784495/ , https://byline.network/?p=32363
- AE-1 Wi-Fi 권한: https://developer.android.com/develop/connectivity/wifi/wifi-permissions
- AF-1 FGS 타입: https://developer.android.com/develop/background-work/services/fgs/service-types
- AF-2 ★ FGS 시간 제한: https://developer.android.com/develop/background-work/services/fgs/timeout
- AF-3 Play FGS 신고: https://support.google.com/googleplay/android-developer/answer/13392821
- AF-4 ★ Doze·App Standby와 예외 정책: https://developer.android.com/training/monitoring-device-state/doze-standby
- AF-5 전원 관리 제한 표: https://developer.android.com/topic/performance/power/power-details
- AF-6 UIDT: https://developer.android.com/develop/background-work/background-tasks/uidt
- AF-7 Android 16 동작 변경: https://developer.android.com/about/versions/16/behavior-changes-all
- AF-8 백그라운드 FGS 시작 제한: https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- AF-9 삼성 FGS 보장(Android Developers Blog 2023-05): https://android-developers.googleblog.com/2023/05/improving-consistency-of-background-work-on-android.html
- AF-10 (보조) dontkillmyapp 삼성: https://dontkillmyapp.com/samsung
- AF-11 알림 권한: https://developer.android.com/develop/ui/views/notifications/notification-permission
- AU-1 USB 호스트: https://developer.android.com/develop/connectivity/usb/host
- AU-2 MtpDevice·MtpEvent 소스: https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/media/java/android/mtp/MtpDevice.java
- AU-3 UsbDeviceConnection 소스: https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/hardware/usb/UsbDeviceConnection.java
- AU-4 시스템 MTP 제공자 소스: https://android.googlesource.com/platform/packages/services/Mtp/+/refs/heads/main/src/com/android/mtp/
- AU-5 Sony FX3 USB 테더링: https://helpguide.sony.net/di/ftp_2035/v1/en/contents/TP0003032502.html
- AU-6 (보조) Lightroom Android OTG: https://petapixel.com/2016/11/09/lightroom-android-can-now-grab-raw-photos-directly-cameras
- AM-1 Play 사진·동영상 권한: https://support.google.com/googleplay/android-developer/answer/14115180
- AM-2 Android 14 부분 접근: https://developer.android.com/about/versions/14/changes/partial-photo-video-access
- AM-3 공유 미디어: https://developer.android.com/training/data-storage/shared/media
- AM-4 JobInfo 소스: https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/apex/jobscheduler/framework/java/android/app/job/JobInfo.java

### 클라우드 직행 (CL)
- Sony
  - CL-S1 https://helpguide.sony.net/di/ftp_2360/v1/en/index.html
  - CL-S2 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/FTP_server_registration.html
  - CL-S3 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/root_certificate.html
  - CL-S4 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/troubleshooting.html
  - CL-S5 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/auto_transfer.html
  - CL-S6 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/transfer_result.html
  - CL-S7 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/FTP_function.html
  - CL-S8 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/WiFi_connection.html
  - CL-S9 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/power_save.html
  - CL-S10 https://helpguide.sony.net/di/ftp_2360/v1/en/contents/save_load.html
  - CL-S11 https://helpguide.sony.net/di/ftp_2410/v1/en/contents/FTP_server_registration.html
  - CL-S12 https://helpguide.sony.net/di/ftp_2420/v1/en/contents/FTP_server_registration.html
  - CL-S13 https://helpguide.sony.net/di/ftp_2440/v1/en/contents/FTP_server_registration.html
  - CL-S14 https://helpguide.sony.net/di/ftp_2620/v1/en/contents/FTP_server_registration.html
  - CL-S15 https://helpguide.sony.net/di/sftp/v1/en/contents/01_SFTP_function.html , https://helpguide.sony.net/di/sftp/v1/en/contents/02_FTPS_function.html
  - CL-S16 https://helpguide.sony.net/ilc/2630/v1/es/contents/transfer_ftp.html
  - CL-S17 (보조) https://www.sony.ca/en/electronics/support/e-mount-body-ilce-1-series/ilce-1/software/00260268
  - CL-S18 https://helpguide.sony.net/ilc/1720/v1/en/contents/TP0001661970.html
- Canon
  - CL-C1 https://cam.start.canon/en/C017/manual/html/UG-06_Network_0060.html
  - CL-C2 https://cam.start.canon/en/C022/manual/html/UG-07_Network_0070.html
  - CL-C3 https://cam.start.canon/en/C023/manual/html/UG-07_Network_0070.html
  - CL-C4 https://cam.start.canon/en/C012/manual/html/UG-07_Network_0070.html
  - CL-C5 https://cam.start.canon/en/C018/manual/html/UG-06_Network_0060.html
  - CL-C6 https://cam.start.canon/en/C017/manual/html/UG-06_Network_0160.html
- Nikon
  - CL-N1 https://onlinemanual.nikonimglib.com/z9/en/nwm_connect_to_ftp_server_325.html
  - CL-N2 https://onlinemanual.nikonimglib.com/z9/en/ftp_servers_connecting_via_ethernet_or_wlan_67.html
  - CL-N3 https://onlinemanual.nikonimglib.com/z9/en/11_connecting_to_computers_or_ftp_servers_04.html
  - CL-N4 https://onlinemanual.nikonimglib.com/z6III/en/nwm_connect_to_ftp_server_365.html
  - CL-N5 https://onlinemanual.nikonimglib.com/z6III/en/ftp_servers_connecting_via_wireless_lan_95.html
  - CL-N6 https://onlinemanual.nikonimglib.com/z50II/en/09-09-07.html
  - CL-N7 (보조) https://nikonrumors.com/2022/10/25/nikon-z9-firmware-update-version-3-0-released.aspx/amp/
- Fujifilm
  - CL-F1 https://fujifilm-dsc.com/en/manual/gfx100ii/connections/ftp_upload/
  - CL-F2 https://fujifilm-dsc.com/en/manual/gfx100ii/connections/network_usb_menu/
  - CL-F3 https://fujifilm-dsc.com/en/manual/x-h2_connection/overview_usage/ftp_upload/
- AWS
  - CL-A1 https://docs.aws.amazon.com/transfer/latest/userguide/tf-server-endpoint.html
  - CL-A2 https://docs.aws.amazon.com/transfer/latest/userguide/create-server-ftp.html
  - CL-A3 https://docs.aws.amazon.com/transfer/latest/userguide/create-server-ftps.html
  - CL-A4 https://docs.aws.amazon.com/transfer/latest/userguide/create-server-in-vpc.html
  - CL-A5 https://docs.aws.amazon.com/transfer/latest/userguide/sftp-for-transfer-family.html
  - CL-A6 ★ https://docs.aws.amazon.com/transfer/latest/APIReference/API_ProtocolDetails.html
  - CL-A7 https://docs.aws.amazon.com/transfer/latest/userguide/custom-lambda-idp.html
  - CL-A8 https://docs.aws.amazon.com/transfer/latest/userguide/events-detail-reference.html
  - CL-A9 https://docs.aws.amazon.com/transfer/latest/userguide/security-policies.html
  - CL-A10 https://docs.aws.amazon.com/transfer/latest/userguide/configuring-servers-change-host-key.html
  - CL-A11 https://aws.amazon.com/aws-transfer-family/faqs/
  - CL-A12 https://aws.amazon.com/aws-transfer-family/pricing/
  - CL-A13 ★ 서울 공개 요금 파일(publicationDate 2026-09-11): https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSTransfer/current/ap-northeast-2/index.json
  - CL-A14 https://docs.aws.amazon.com/transfer/latest/APIReference/API_StopServer.html
  - CL-A15 https://aws.amazon.com/vpc/pricing/
  - CL-A16 https://aws.amazon.com/lightsail/pricing/
  - CL-A17 https://docs.aws.amazon.com/config/latest/developerguide/transfer-family-server-no-ftp.html
  - CL-A18 https://www.amazontrust.com/repository/
  - CL-A19 (보조, 403으로 검색 요약만) https://repost.aws/questions/QURR9WVIbjQ-uYYFu_gMCdhw/ftp-transfer-family-ftps-tls-resume-failed
- 대안 구현
  - CL-O1 SFTPGo: https://github.com/drakkan/sftpgo
  - CL-O2 https://docs.sftpgo.com/latest/eventmanager/
  - CL-O3 https://docs.sftpgo.com/latest/external-auth/
  - CL-O4 https://docs.sftpgo.com/latest/config-file/
  - CL-G1 Google Cloud FTP: https://docs.cloud.google.com/cloud-ftp/overview
  - CL-G2 https://docs.cloud.google.com/cloud-ftp/add-sftp-users
  - CL-G3 https://docs.cloud.google.com/cloud-ftp/create-external-sftp-server
  - CL-G4 https://docs.cloud.google.com/storage/docs/cloud-storage-fuse/overview
  - CL-L1 Let's Encrypt: https://letsencrypt.org/certificates/
  - CL-O5 (2026-10-19) Oracle Cloud Always Free Resources: https://docs.oracle.com/en-us/iaas/Content/FreeTier/resourceref.htm
  - CL-O6 (2026-10-19, 제3자 집계) Vultr vc2-1c-1gb: https://sparecores.com/server/vultr/vc2-1c-1gb , https://pcr.cloud-mercato.com/providers/vultr/flavors/vc2-1c-1gb
  - CL-O7 (2026-10-19) Google Cloud 무료 등급 Compute: https://cloud.google.com/free/docs/compute-getting-started
  - CL-K1 (2026-10-19) KT 인터넷 이용약관 2025.5 제15조 ①항 5호: https://corp.kt.com/attach/board/BS00000005/70/%28이용약관+전문%29+인터넷서비스+이용약관_202505.pdf
- 핫스팟·요금제
  - CL-H1 https://support.apple.com/en-us/111785
  - CL-H2 https://support.apple.com/en-us/guide/iphone/iph45447ca6/ios
  - CL-H3 https://support.apple.com/en-us/101604
  - CL-H4 (보조) https://discussions.apple.com/thread/251959460
  - CL-H5 https://support.google.com/android/answer/9059108
  - CL-H6 https://www.samsung.com/ae/support/mobile-devices/how-to-use-and-configure-a-mobile-hotspot-on-a-galaxy-phone
  - CL-H7 (보조) https://r1.community.samsung.com/t5/suggestions/hotspot-timer/m-p/2532403
  - CL-H8 SKT 5GX 프라임: https://m.tworld.co.kr/product/callplan?prod_id=NA00007790
  - CL-H9 (보조) https://www.newsis.com/view/NISX20220801_0001963445
- 사례(보조)
  - CL-P1 https://rilavek.com/resources/canon-ftp-to-s3
  - CL-P2 https://rilavek.com/resources/nikon-ftp-to-s3
  - CL-P3 https://rilavek.com/resources/sony-ftp-to-s3
  - CL-P4 https://rilavek.com/docs/sources/ftp
  - CL-P5 https://www.couchdrop.io/guides/how-to-upload-media-from-a-camera-to-cloud-storage-via-sftp-ftp
  - CL-P6 https://www.fotoware.com/customer-success-story-lat-images , https://blog.photoshelter.com/2008/10/photoshelter-super-ftp-embedda/
