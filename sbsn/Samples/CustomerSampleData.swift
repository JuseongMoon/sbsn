import SBSNUI

/// 고객 앱 예시 화면의 더미 데이터(D032). 실제 데이터로 바꾸기 쉽게 화면 코드와 나눠 둔다.
/// 사람 이름은 가상(하린·도윤·서아·지우 작가), 금액·기간은 PROV-04 가안(촬영료 15,000원, 장당 8,000원, 7일 구매, 30일 다운로드).
enum CustomerSampleData {
    // MARK: 촬영 탭

    struct Photographer: Identifiable {
        var id: String { name }
        let name: String
        let meters: Int
        let walk: String
        let languages: String
        let rating: Double
        let reviewCount: Int
        let status: String
        let isAvailable: Bool
    }

    static let photographers = [
        Photographer(name: "하린 작가", meters: 120, walk: "도보 2분", languages: "한국어 · English", rating: 4.9, reviewCount: 32,
                     status: "지금 가능", isAvailable: true),
        Photographer(name: "도윤 작가", meters: 260, walk: "도보 4분", languages: "한국어", rating: 4.8, reviewCount: 21,
                     status: "지금 가능", isAvailable: true),
        Photographer(name: "지우 작가", meters: 300, walk: "도보 5분", languages: "한국어 · English", rating: 4.9, reviewCount: 40,
                     status: "촬영 중 · 약 8분 뒤 가능", isAvailable: false),
        Photographer(name: "서아 작가", meters: 410, walk: "도보 6분", languages: "한국어 · 日本語", rating: 4.7, reviewCount: 15,
                     status: "지금 가능", isAvailable: true),
    ]
    static let priceLine = "촬영료 15,000원 + 장당 8,000원"

    static let moods = ["자연스러운 미소", "인물·배경 균형", "궁궐 중심", "감성적인 색감"]
    static let languages = ["한국어", "English", "日本語"]

    static let reviews = [
        SampleReview(stars: 5, tags: "포즈 안내 · 결과물", text: "어색했는데 자세를 하나하나 알려 줘서 편했어요.", date: "11월 18일"),
        SampleReview(stars: 5, tags: "시간 약속", text: "약속한 장소에 먼저 와 계셨어요.", date: "11월 12일"),
        SampleReview(stars: 4, tags: "친절함", text: "골목 사진이 특히 좋았습니다.", date: "11월 3일"),
    ]

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

    static let briefingSteps = ["만나기", "촬영 안내 2~3분", "촬영 10분", "사진 고르기", "사진 받기"]
    static let briefingPromises = [
        "촬영료에는 사진이 포함되지 않습니다",
        "사진은 장당 8,000원입니다",
        "사진은 공개 후 7일 안에 고를 수 있습니다",
        "만남 장소에서 5분 기다린 뒤 종료됩니다",
        "촬영 시작 전 취소는 무료입니다",
    ]
    static let safetyTips = [
        "사람이 많은 공개된 장소에서 만나세요.",
        "촬영은 정해진 거점 안에서만 진행합니다.",
        "불편하면 언제든 촬영을 멈추고 운영팀에 알리세요.",
    ]

    struct SamplePhotoItem: Identifiable {
        var id: String { fileName }
        let fileName: String
        let rank: Int?
        let reason: String?
    }

    static let recommended = [
        SamplePhotoItem(fileName: "DSC0104.JPG", rank: 1, reason: "표정 안정 · 배경 균형"),
        SamplePhotoItem(fileName: "DSC0101.JPG", rank: 2, reason: "선명도 우수"),
        SamplePhotoItem(fileName: "DSC0107.JPG", rank: 3, reason: "두 사람 시선 일치"),
        SamplePhotoItem(fileName: "DSC0102.JPG", rank: nil, reason: nil),
        SamplePhotoItem(fileName: "DSC0103.JPG", rank: nil, reason: nil),
        SamplePhotoItem(fileName: "DSC0105.JPG", rank: nil, reason: nil),
        SamplePhotoItem(fileName: "DSC0106.JPG", rank: nil, reason: nil),
        SamplePhotoItem(fileName: "DSC0108.JPG", rank: nil, reason: nil),
    ]
    static let basket = ["DSC0101.JPG", "DSC0104.JPG", "DSC0107.JPG"]

    struct Promotion: Identifiable {
        var id: String { title }
        let title: String
        let period: String
    }

    static let promotions = [
        Promotion(title: "서촌 한복 대여점 제휴 · 촬영료 2,000원 할인(예시)", period: "11월 1일 ~ 12월 31일"),
        Promotion(title: "평일 오전 촬영 · 사진 1장 더(예시)", period: "11월 15일 ~ 12월 15일"),
    ]

    struct Coupon: Identifiable {
        var id: String { name }
        let name: String
        let benefit: String
        let expiry: String
    }

    static let coupons = [
        Coupon(name: "첫 촬영 쿠폰", benefit: "촬영료 2,000원 할인", expiry: "12월 31일까지"),
        Coupon(name: "친구 추천 쿠폰", benefit: "사진 1장 8,000원 할인", expiry: "12월 15일까지"),
    ]

    struct GuidePlace: Identifiable {
        var id: String { name }
        let name: String
        let bestTime: String
        let allowed: String
        let caution: String
    }

    static let guidePlaces = [
        GuidePlace(name: "경복궁 동문 앞", bestTime: "오전 9~10시, 해 질 무렵", allowed: "궁 밖 돌담길까지(궁 안은 촬영 허가 필요)",
                   caution: "관람객 동선을 막지 않게 짧게 찍습니다"),
        GuidePlace(name: "서촌 골목", bestTime: "오후 3~5시", allowed: "공개된 골목. 주택 대문 앞은 피합니다",
                   caution: "주민 생활 공간이라 소리를 낮춥니다"),
        GuidePlace(name: "통인시장 입구", bestTime: "오전 11시 전", allowed: "입구 바깥쪽",
                   caution: "상점 앞을 오래 막지 않습니다"),
    ]

    static let reviewTags = ["포즈 안내", "시간 약속", "결과물", "친절함"]

    // MARK: 내 사진 탭

    struct Shoot: Identifiable {
        var id: String { title }
        let section: String
        let title: String
        let photos: [String]
        let daysLeft: Int
    }

    static let shoots = [
        Shoot(section: "11월 21일", title: "서촌 · 하린 작가 · 구매 3장", photos: ["DSC0101.JPG", "DSC0104.JPG", "DSC0107.JPG"], daysLeft: 27),
        Shoot(section: "11월 9일", title: "경복궁 · 도윤 작가 · 구매 1장", photos: ["DSC0412.JPG"], daysLeft: 15),
    ]

    struct Order: Identifiable {
        var id: String { number }
        let number: String
        let title: String
        let state: String
        let date: String
        let items: [String]
        let amount: Int
    }

    static let orders = [
        Order(number: "ORD-20261121-001(예시)", title: "촬영료 15,000원", state: "결제 완료", date: "2026-11-21 10:22",
              items: ["10분 촬영 · 하린 작가"], amount: 15_000),
        Order(number: "ORD-20261121-002(예시)", title: "사진 3장 24,000원", state: "결제 완료", date: "2026-11-21 10:40",
              items: ["DSC0101.JPG", "DSC0104.JPG", "DSC0107.JPG"], amount: 24_000),
        Order(number: "ORD-20261109-004(예시)", title: "사진 1장 8,000원", state: "환불 완료", date: "2026-11-09 15:12",
              items: ["DSC0415.JPG"], amount: 8_000),
    ]
    static let maskedCard = "카드 ****1234"

    static let retouchSteps = ["접수", "작업 중", "검수", "완료"]
    static let retouchScopes = ["피부 정리", "배경 정리", "색감"]

    // MARK: 마이 탭

    struct FAQGroup: Identifiable {
        var id: String { title }
        let title: String
        let items: [(question: String, answer: String)]
    }

    static let faq = [
        FAQGroup(title: "가격·결제", items: [
            ("촬영료에 사진이 포함되나요?", "아니요. 촬영료 15,000원에는 사진이 포함되지 않고, 사진은 장당 8,000원입니다."),
            ("사진을 하나도 안 사도 되나요?", "네. 마음에 드는 사진이 없으면 0장도 됩니다."),
        ]),
        FAQGroup(title: "촬영", items: [
            ("몇 분 찍나요?", "만나서 2~3분 안내한 뒤 10분 촬영합니다."),
            ("작가가 늦으면 어떻게 하나요?", "만남 장소에서 5분 기다린 뒤 종료되고, 시작 전 취소는 무료입니다."),
        ]),
        FAQGroup(title: "사진 받기", items: [
            ("언제까지 받을 수 있나요?", "공개 후 30일 동안 다시 받을 수 있습니다(구매는 공개 후 7일 안)."),
            ("어디에 저장되나요?", "구매하면 사진 앱에 바로 저장됩니다."),
        ]),
        FAQGroup(title: "위치·개인정보", items: [
            ("내 위치는 누가 보나요?", "매칭된 작가만 만나는 동안 봅니다. 촬영이 끝나면 지웁니다."),
            ("사진에 위치가 남나요?", "작가 원본의 메타데이터(촬영 위치, 카메라 정보 등)가 그대로 들어 있습니다. 다른 사람에게 보낼 때는 사진 앱 공유 옵션에서 위치를 뺄 수 있습니다."),
        ]),
    ]

    static let inquiryTypes = ["촬영", "사진", "결제", "앱 오류"]
    static let reportTargets = ["작가", "채팅"]

    struct Inquiry: Identifiable {
        var id: String { title }
        let title: String
        let state: String
        let question: String
        let answer: String?
    }

    static let inquiries = [
        Inquiry(title: "사진 한 장이 저장되지 않아요", state: "답변 완료", question: "구매한 사진 중 한 장이 사진 앱에 없어요.",
                answer: "확인해 보니 저장이 중간에 멈췄습니다. 사진 화면에서 다시 저장을 눌러 주세요."),
        Inquiry(title: "다음 주 촬영 가능 시간", state: "접수됨", question: "평일 오후에도 촬영할 수 있나요?", answer: nil),
    ]

    static let refundReasons = ["사진 품질", "사진 5장 미만", "사진 공개 늦음", "구매 사진 못 받음", "결제 오류", "기타"]
    static let refundPolicy = [
        "정상 사진이 5장 미만이면 재촬영 또는 촬영료 환불 중 고릅니다.",
        "구매한 사진을 받지 못하면 그 사진을 환불하거나 24시간 안에 복구합니다.",
        "사진 공개가 촬영 종료 후 60분을 넘기면 촬영료 환불을 고를 수 있습니다.",
    ]

    static let documents = [
        SampleDocument(title: "서비스 이용약관", clauses: [
            .init("제1조 목적", "이 약관은 십분스냅 촬영 중개 서비스 이용 조건을 정합니다. 예시 문장입니다."),
            .init("제2조 정의", "\"작가\"는 승인된 촬영 수행자를, \"고객\"은 촬영을 요청하는 이용자를 말합니다."),
            .init("제3조 가격", "촬영료와 사진 가격은 확정 전 화면에 표시합니다. 촬영료에는 사진이 포함되지 않습니다."),
            .init("제4조 취소", "촬영 시작 전 취소는 무료입니다. 만남 장소에서 5분 기다린 뒤 종료될 수 있습니다."),
        ]),
        SampleDocument(title: "위치기반서비스 이용약관", clauses: [
            .init("제1조 목적", "작가 찾기와 만남을 위해 위치정보를 이용하는 조건을 정합니다."),
            .init("제2조 제공 범위", "만나는 동안 매칭된 작가에게만 내 위치를 제공합니다."),
            .init("제3조 보관", "위치 제공 사실은 법이 정한 기간 동안 기록하고, 만남 위치는 촬영 종료 때 지웁니다."),
        ]),
        SampleDocument(title: "개인정보 처리방침", clauses: [
            .init("제1조 수집 항목", "기기 식별용 익명 계정, 만남 중 위치, 구매한 사진 기록을 처리합니다."),
            .init("제2조 이용 목적", "매칭, 사진 전달, 고객 지원에만 씁니다."),
            .init("제3조 보관 기간", "서버의 사진은 올린 뒤 30일이 지나면 구매 여부와 관계없이 지웁니다. 산 사진은 사진 앱에 저장된 사본이 남습니다."),
        ]),
        SampleDocument(title: "환불 정책", clauses: [
            .init("제1조 촬영료", "정상 사진이 5장 미만이면 재촬영 또는 촬영료 환불 중 고릅니다."),
            .init("제2조 사진", "구매한 사진을 받지 못하면 해당 사진을 환불하거나 24시간 안에 복구합니다."),
            .init("제3조 법정 권리", "이 정책은 관련 법이 정한 권리를 제한하지 않습니다."),
        ]),
    ]

    static let locationConsents = [
        SampleLocationConsent(title: "만남 중 내 위치 공유", consentedAt: "2026-11-21",
                              offResult: "다음 만남부터 작가가 내 위치를 볼 수 없습니다"),
    ]
    static let locationHistory = [
        "11월 21일 10:22~10:41 · 하린 작가에게 만남 위치 · 촬영 시작으로 종료",
        "11월 9일 15:01~15:12 · 도윤 작가에게 만남 위치 · 촬영 시작으로 종료",
    ]
    static let blockedUsers = ["지우 작가(11월 2일 차단)"]

    struct Consent: Identifiable {
        var id: String { item }
        let item: String
        let date: String
        let version: String
    }

    static let consents = [
        Consent(item: "서비스 이용약관", date: "2026-11-09 14:50", version: "초안 2026-11-01"),
        Consent(item: "위치기반서비스 이용약관", date: "2026-11-09 14:50", version: "초안 2026-11-01"),
        Consent(item: "개인정보 처리방침", date: "2026-11-09 14:50", version: "초안 2026-11-01"),
        Consent(item: "만남 중 위치 공유", date: "2026-11-21 10:22", version: "초안 2026-11-21"),
    ]
}
