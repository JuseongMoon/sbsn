import SBSNUI

/// 고객 앱에서 기획에는 있지만 아직 실제 데이터와 연결하지 않은 메뉴(예시 화면, D032). 근거는 총괄 문서 `UI_WIREFRAME_PLAN.md` 1절.
enum CustomerFeatures {
    /// 명세 순서(C1~C19, C15 계정 연결은 실제 로그인으로 바뀌어 뺐다). 개발 메뉴의 "예시 화면 전체"가 쓴다.
    /// C03 작가 프로필은 2단계 실제 화면(지도 카드 [프로필])이 돼 뺐다(예시 작가 목록 안에서만 열린다).
    static let all = [photographerList, conditions, briefing, safety, recommendation, basket, review, events,
                      album, orders, retouch, shareAndPrint, profile, help, inquiry, refund, terms]

    // 촬영 탭
    static let photographerList = PlannedFeature(
        id: "photographerList", title: "작가 목록", summary: "주변 작가를 목록으로 비교하는 화면이 들어갈 자리입니다.",
        plannedItems: ["거리", "가격", "소통 언어", "샘플 사진"], systemImage: "list.bullet")
    static let conditions = PlannedFeature(
        id: "conditions", title: "촬영 조건", summary: "원하는 촬영 조건을 고르는 화면이 들어갈 자리입니다.",
        plannedItems: ["인원", "원하는 분위기", "소통 언어"], systemImage: "slider.horizontal.3")
    static let photographerProfile = PlannedFeature(
        id: "photographerProfile", title: "프로필·포트폴리오", summary: "작가를 고르기 전에 경력과 작업을 보는 화면이 들어갈 자리입니다.",
        plannedItems: ["경력", "장비", "소통 언어", "샘플 사진"], systemImage: "person.crop.rectangle")
    static let briefing = PlannedFeature(
        id: "briefing", title: "촬영 안내", summary: "만나기 전에 촬영 흐름과 약속을 확인하는 화면이 들어갈 자리입니다.",
        plannedItems: ["촬영 브리프", "취소·노쇼 안내"], systemImage: "doc.text")
    static let safety = PlannedFeature(
        id: "safety", title: "안전·긴급 지원", summary: "현장에서 문제가 생겼을 때 도움을 요청하는 화면이 들어갈 자리입니다.",
        plannedItems: ["긴급 연락", "신고"], systemImage: "exclamationmark.shield")
    static let recommendation = PlannedFeature(
        id: "recommendation", title: "추천 순서", summary: "잘 나온 사진부터 보여 주는 정렬이 들어갈 자리입니다.",
        plannedItems: ["AI 추천 순서"], systemImage: "sparkles")
    static let basket = PlannedFeature(
        id: "basket", title: "선택 바구니", summary: "여러 장을 골라 한 번에 구매하는 화면이 들어갈 자리입니다. 지금은 한 장씩 바로 구매합니다.",
        plannedItems: ["여러 장 한 번에 결제", "두 장 비교"], systemImage: "basket")
    static let review = PlannedFeature(
        id: "review", title: "리뷰 남기기", summary: "촬영이 끝난 뒤 작가에게 리뷰를 남기는 화면이 들어갈 자리입니다.",
        plannedItems: ["별점", "한 줄 평"], systemImage: "star.bubble")
    static let events = PlannedFeature(
        id: "events", title: "제휴·이벤트", summary: "제휴처 혜택과 이벤트를 보는 화면이 들어갈 자리입니다.",
        plannedItems: ["프로모션", "쿠폰", "촬영지 가이드"], systemImage: "gift")

    // 내 사진 탭
    static let album = PlannedFeature(
        id: "album", title: "지난 촬영(앨범)", summary: "지난 촬영별로 구매한 사진을 모아 보는 화면이 들어갈 자리입니다.",
        plannedItems: ["촬영별 구매 사진"], systemImage: "photo.stack")
    static let orders = PlannedFeature(
        id: "orders", title: "주문 내역", summary: "촬영료와 사진 주문을 확인하는 화면이 들어갈 자리입니다.",
        plannedItems: ["촬영료·사진 주문", "영수증"], systemImage: "receipt")
    static let retouch = PlannedFeature(
        id: "retouch", title: "전문 보정", summary: "구매한 사진에 전문 보정을 추가로 주문하는 화면이 들어갈 자리입니다.",
        plannedItems: ["요청서", "진행 상태", "수정 요청"], systemImage: "wand.and.stars")
    static let shareAndPrint = PlannedFeature(
        id: "shareAndPrint", title: "공유·인화", summary: "사진을 공유하거나 인화를 주문하는 화면이 들어갈 자리입니다.",
        plannedItems: ["공유 링크", "SNS 규격 저장", "인화"], systemImage: "printer")

    // 마이 탭
    static let profile = PlannedFeature(
        id: "profile", title: "프로필·언어", summary: "이름과 사용 언어를 정하는 화면이 들어갈 자리입니다.",
        plannedItems: ["이름", "사용 언어"], systemImage: "person.text.rectangle")
    static let help = PlannedFeature(
        id: "help", title: "도움말", summary: "자주 묻는 질문과 이용 방법이 들어갈 자리입니다.", systemImage: "questionmark.circle")
    static let inquiry = PlannedFeature(
        id: "inquiry", title: "문의·신고", summary: "운영팀에 문의하거나 작가·채팅을 신고하는 화면이 들어갈 자리입니다.",
        plannedItems: ["문의", "신고"], systemImage: "envelope")
    static let refund = PlannedFeature(
        id: "refund", title: "환불·분쟁 요청", summary: "환불이나 분쟁을 요청하는 화면이 들어갈 자리입니다.", systemImage: "arrow.uturn.backward.circle")
    static let terms = PlannedFeature(
        id: "terms", title: "약관·정책", summary: "약관과 동의 내역, 삭제 요청이 들어갈 자리입니다.",
        plannedItems: ["이용약관", "위치정보 동의", "개인정보 처리방침", "환불 정책", "사진 삭제"], systemImage: "doc.plaintext")
}
