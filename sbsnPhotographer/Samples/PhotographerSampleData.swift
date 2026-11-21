import Foundation
import SBSNUI

/// 작가 앱 예시 화면의 더미 데이터(D032). 실제 데이터로 바꾸기 쉽게 화면 코드와 나눠 둔다.
/// 금액은 PROV-04 가안(촬영료 15,000원, 장당 8,000원, 정식 M2 작가 70%, 월말 확정 익월 15일 지급, M1 시급 15,000원 + 정상 촬영 3,000원).
enum PhotographerSampleData {
    // MARK: 촬영 탭

    static let areas = ["경복궁역·서촌", "북촌", "광화문"]
    static let weekdays = ["월", "화", "수", "목", "금", "토", "일"]

    struct BreakRecord: Identifiable {
        var id: String { range }
        let range: String
        let minutes: Int
    }

    static let breakRecords = [
        BreakRecord(range: "13:00~13:30", minutes: 30),
        BreakRecord(range: "15:10~15:25", minutes: 15),
    ]

    static let rejectReasons = ["이동 중", "휴게 예정", "장비 문제"]

    static let brief = [
        ("고객", "고객 · 2명"),
        ("소통 언어", "한국어"),
        ("원하는 분위기", "자연스러운 미소 · 인물·배경 균형"),
        ("요청 사항", "돌담길에서 걸어가는 장면을 찍고 싶어요"),
        ("만날 곳", "경복궁역 3번 출구 앞(예시)"),
    ]

    static let safetyTips = [
        "사람이 많은 공개된 장소에서 만나세요.",
        "촬영은 정해진 거점 안에서만 진행합니다.",
        "위험하다고 느끼면 촬영을 멈추고 운영팀에 알리세요.",
    ]

    struct CameraGuide: Identifiable {
        var id: String { brand }
        let brand: String
        let note: String?
        let steps: [String]
    }

    static let cameraGuides = [
        CameraGuide(brand: "소니 Creators' App", note: "원본 크기로 가져옵니다(2MP 축소 설정은 끕니다)", steps: [
            "카메라와 폰을 Creators' App으로 연결합니다.",
            "이번 촬영 사진을 골라 \"원본\" 크기로 폰에 가져옵니다.",
            "가져온 사진은 사진 앱에 저장됩니다.",
            "십분스냅 작가 앱의 사진 고르기에서 \"사진 앱에서 추가\"로 고릅니다.",
        ]),
        CameraGuide(brand: "카드 리더", note: "사진 앱을 거치지 않고 고를 수 있습니다", steps: [
            "SD 카드를 카드 리더로 폰에 연결합니다.",
            "사진 고르기에서 \"파일에서 추가\"를 누르고 카드의 DCIM 폴더에서 고릅니다.",
        ]),
        CameraGuide(brand: "라이트룸 내보내기", note: "긴 변 4,000px 이상, JPEG로 내보냅니다", steps: [
            "보정한 사진을 \"JPG, 원본 크기\"로 사진 앱에 내보냅니다.",
            "메타데이터는 구매한 고객에게 그대로 전달됩니다. 뺄 항목은 내보낼 때 고릅니다.",
        ]),
        CameraGuide(brand: "캐논·니콘·후지", note: "JPEG로 찍거나 JPEG로 내보냅니다(RAW는 받지 않습니다)", steps: [
            "제조사 앱(Camera Connect·SnapBridge·XApp)으로 원본 크기 JPEG를 폰에 옮깁니다.",
            "사진 앱에서 고릅니다.",
        ]),
    ]

    // MARK: 내역 탭

    struct Shoot: Identifiable {
        var id: String { title }
        let section: String
        let title: String
        let timeline: [(String, String)]
        let received: Int
        let sold: Int
        let delivered: Int
        let deliveryState: String
    }

    static let shoots = [
        Shoot(section: "11월 21일", title: "14:10 · 서촌 · 고객 2명 · 받은 사진 42 · 판매 3 · 전달 완료",
              timeline: [("확정", "14:02"), ("만남", "14:08"), ("시작", "14:10"), ("종료", "14:21"), ("전달 완료", "14:35")],
              received: 42, sold: 3, delivered: 3, deliveryState: "전달 완료"),
        Shoot(section: "11월 21일", title: "11:30 · 경복궁 · 고객 1명 · 받은 사진 38 · 판매 2 · 전달 대기 1장",
              timeline: [("확정", "11:22"), ("만남", "11:27"), ("시작", "11:30"), ("종료", "11:41"), ("전달 완료", "-")],
              received: 38, sold: 2, delivered: 1, deliveryState: "전달 대기 1장"),
        Shoot(section: "11월 20일", title: "16:05 · 서촌 · 고객 2명 · 받은 사진 45 · 판매 4 · 전달 완료",
              timeline: [("확정", "15:58"), ("만남", "16:03"), ("시작", "16:05"), ("종료", "16:16"), ("전달 완료", "16:30")],
              received: 45, sold: 4, delivered: 4, deliveryState: "전달 완료"),
    ]

    struct Payout: Identifiable {
        var id: String { month }
        let month: String
        let paidOn: String
        let lines: [(String, Int)]
        var total: Int { lines.reduce(0) { $0 + $1.1 } }
    }

    static let payouts = [
        Payout(month: "10월분", paidOn: "11월 15일 지급", lines: [("촬영료 매출 작가 몫", 94_500), ("사진 매출 작가 몫", 134_400), ("환불 조정", -5_600)]),
        Payout(month: "9월분", paidOn: "10월 15일 지급", lines: [("촬영료 매출 작가 몫", 63_000), ("사진 매출 작가 몫", 89_600)]),
    ]

    static let reviews = [
        SampleReview(stars: 5, tags: "포즈 안내 · 결과물", text: "어색했는데 자세를 하나하나 알려 줘서 편했어요.", date: "11월 18일"),
        SampleReview(stars: 5, tags: "시간 약속", text: "약속한 장소에 먼저 와 계셨어요.", date: "11월 12일"),
        SampleReview(stars: 4, tags: "친절함", text: "골목 사진이 특히 좋았습니다.", date: "11월 3일"),
    ]

    static let opsFeedback = [
        ("역광 장면 노출 확인 부탁(예시)", "11월 19일"),
        ("미리보기 6장 이상 유지 좋습니다(예시)", "11월 10일"),
    ]

    static let disputeActions = ["재보정 제안", "환불 동의", "의견 제출"]

    // MARK: 마이 탭

    static let profile = SampleProfile(
        name: "하린 작가",
        stats: "★ 4.9 · 촬영 128회 · 경력 7년",
        intro: "서촌 골목과 경복궁 돌담을 배경으로 자연스러운 커플·친구 사진을 찍습니다. 처음 촬영하는 분도 편하게 포즈를 알려 드려요.",
        equipment: "Sony a7C II · 35mm F1.8",
        languages: "한국어 · English",
        area: "경복궁역·서촌",
        portfolioCaptions: ["경복궁 · 커플", "서촌 골목 · 친구", "돌담길 · 커플", "통인시장 · 가족", "한옥 카페 · 친구", "광화문 · 커플"],
        priceLines: [("촬영료", "15,000원 (사진 미포함)"), ("사진", "장당 8,000원")],
        priceExample: "예) 3장 39,000원",
        reviews: reviews
    )

    static let equipment = ["Sony a7C II", "FE 35mm F1.8", "보조 배터리 2개"]
    static let languages = ["한국어", "English", "日本語"]

    static let contract = SampleDocument(title: "작가 계약서(예시)", clauses: [
        .init("제1조 목적", "십분스냅 첫 검증 기간(M1)의 촬영 업무 조건을 정합니다. 예시 문장입니다."),
        .init("제2조 근무와 보상", "지정 시간 동안 시간당 15,000원, 정상 촬영 1건당 3,000원을 지급합니다."),
        .init("제3조 사진", "촬영 원본은 정해진 기간 뒤 폰에서 지웁니다."),
    ])
    static let maskedAccount = "○○은행 ****5678"

    struct OriginalsShoot: Identifiable {
        var id: String { title }
        let title: String
        let size: String
        let sold: String
    }

    static let originals = [
        OriginalsShoot(title: "11월 21일 14:10 · 서촌", size: "0.9GB", sold: "판매 3장"),
        OriginalsShoot(title: "11월 21일 11:30 · 경복궁", size: "0.8GB", sold: "판매 2장"),
        OriginalsShoot(title: "11월 20일 16:05 · 서촌", size: "0.9GB", sold: "판매 4장"),
        OriginalsShoot(title: "11월 19일 13:40 · 광화문", size: "0.6GB", sold: "판매 없음"),
    ]

    static let supportTypes = ["사진 옮기기", "정산", "앱 오류", "기타"]
    static let supportFAQ = [
        ("사진이 고르기에서 막힐 때", "JPEG·HEIC만 받고, 긴 변 4,000px 미만과 RAW는 받지 않습니다. 원본 크기 JPEG로 다시 내보내 주세요."),
        ("배터리 아끼기", "촬영 사이에는 화면을 끄고, 저전력 모드는 끕니다(업로드가 늦어집니다)."),
        ("정산일", "월말에 확정한 금액을 다음 달 15일에 지급합니다. 휴일이면 다음 영업일입니다."),
    ]

    static let documents = [
        SampleDocument(title: "위치기반서비스 이용약관", clauses: [
            .init("제1조 목적", "촬영 가능 중 지도 공개와 매칭 뒤 위치 공유의 조건을 정합니다."),
            .init("제2조 공개 범위", "지도에는 100m 단위로만 공개하고, 정밀 위치는 매칭된 고객에게만 만나는 동안 제공합니다."),
            .init("제3조 보관", "위치 제공 사실은 법이 정한 기간 동안 기록하고, 만남 위치는 촬영 종료 때 지웁니다."),
        ]),
        SampleDocument(title: "작가 이용약관", clauses: [
            .init("제1조 목적", "십분스냅에서 촬영 서비스를 제공하는 작가의 이용 조건을 정합니다."),
            .init("제2조 매칭", "촬영 가능을 켠 동안 고객이 확정하면 바로 매칭됩니다."),
            .init("제3조 사진 전달", "구매한 사진의 고화질본은 촬영이 끝난 뒤에도 전달을 마칩니다."),
        ]),
        SampleDocument(title: "개인정보 처리방침", clauses: [
            .init("제1조 수집 항목", "작가 계정, 촬영 가능 중 위치(100m 단위), 촬영·정산 기록을 처리합니다."),
            .init("제2조 이용 목적", "매칭, 사진 전달, 정산, 분쟁 대응에만 씁니다."),
            .init("제3조 보관 기간", "정산 기록은 세법이 정한 기간 동안 보관합니다."),
        ]),
    ]

    static let locationConsents = [
        SampleLocationConsent(title: "촬영 가능일 때 지도에 위치 공개(100m 단위)", consentedAt: "2026-11-01",
                              offResult: "촬영 가능을 켜도 고객 지도에 보이지 않습니다"),
        SampleLocationConsent(title: "매칭 뒤 고객과 위치 공유", consentedAt: "2026-11-01",
                              offResult: "만나는 동안 고객이 내 위치를 볼 수 없습니다"),
    ]
    static let locationStopHints = [
        "촬영 가능을 끄면 공개가 멈춥니다.",
        "만나는 중에는 만나기 화면 위치 줄의 스위치로 멈춥니다.",
    ]
    static let locationHistory = [
        "11월 21일 14:02~14:10 · 고객에게 만남 위치 · 촬영 시작으로 종료",
        "11월 21일 11:22~11:30 · 고객에게 만남 위치 · 촬영 시작으로 종료",
    ]
    static let blockedUsers = ["고객(11월 9일 촬영, 차단)"]
    static let consents = [
        ("작가 이용약관", "2026-11-01 09:30", "초안 2026-11-01"),
        ("위치 공개·공유", "2026-11-01 09:30", "초안 2026-11-01"),
        ("개인정보 처리방침", "2026-11-01 09:30", "초안 2026-11-01"),
    ]
}
