import SBSNUI

/// 작가 앱에서 기획에는 있지만 아직 실제 데이터와 연결하지 않은 메뉴(예시 화면, D032). 근거는 총괄 문서 `UI_WIREFRAME_PLAN.md` 2절.
enum PhotographerFeatures {
    /// 명세 순서(P1~P18). 개발 메뉴의 "예시 화면 전체"가 쓴다. P6 10분 타이머와 P8 사진 검수·공개는 실제 화면이 됐다(D036).
    /// P1 활동 위치·반경, P2 휴게, P3 수락·거절은 2단계 실제 화면(켜기 시트·휴게·새 신청 카드)이 돼 뺐다.
    static let all = [customerBrief, safety, cameraGuide,
                      history, sales, settlement, feedback, disputes, portfolio, registration, originals, support, terms]

    // 촬영 탭
    static let customerBrief = PlannedFeature(
        id: "customerBrief", title: "고객 브리프", summary: "고객이 남긴 요청 사항을 보는 화면이 들어갈 자리입니다.",
        plannedItems: ["인원", "원하는 분위기", "소통 언어"], systemImage: "doc.text")
    static let safety = PlannedFeature(
        id: "safety", title: "안전·긴급 지원", summary: "현장에서 문제가 생겼을 때 도움을 요청하는 화면이 들어갈 자리입니다.",
        plannedItems: ["긴급 연락", "신고"], systemImage: "exclamationmark.shield")
    static let cameraGuide = PlannedFeature(
        id: "cameraGuide", title: "사진 옮기기 가이드", summary: "촬영한 사진을 카메라에서 폰으로 옮기는 방법이 들어갈 자리입니다.",
        plannedItems: ["소니 Creators' App", "카드 리더", "라이트룸 내보내기", "캐논·니콘·후지"], systemImage: "camera.badge.ellipsis")

    // 내역 탭
    static let history = PlannedFeature(
        id: "history", title: "촬영 이력", summary: "지난 촬영을 모아 보는 화면이 들어갈 자리입니다.", systemImage: "clock.arrow.circlepath")
    static let sales = PlannedFeature(
        id: "sales", title: "판매·전달 현황", summary: "촬영별로 팔린 사진과 전달 상태를 보는 화면이 들어갈 자리입니다.", systemImage: "chart.bar")
    static let settlement = PlannedFeature(
        id: "settlement", title: "수익·정산", summary: "월 정산 내역과 지급 예정액을 보는 화면이 들어갈 자리입니다.", systemImage: "wonsign.circle")
    static let feedback = PlannedFeature(
        id: "feedback", title: "품질 피드백", summary: "고객 리뷰와 운영팀 피드백을 보는 화면이 들어갈 자리입니다.", systemImage: "star.bubble")
    static let disputes = PlannedFeature(
        id: "disputes", title: "분쟁 대응", summary: "고객 문의·환불 요청에 답하는 화면이 들어갈 자리입니다.", systemImage: "exclamationmark.bubble")

    // 마이 탭
    static let portfolio = PlannedFeature(
        id: "portfolio", title: "프로필·포트폴리오", summary: "고객에게 보일 프로필과 샘플 사진을 관리하는 화면이 들어갈 자리입니다. 고객에게 보일 이름은 촬영 탭에서 입력합니다.",
        plannedItems: ["경력", "장비", "소통 언어", "샘플 사진"], systemImage: "person.crop.rectangle")
    static let registration = PlannedFeature(
        id: "registration", title: "등록·계약·장비", summary: "작가 등록 정보와 계약, 장비를 관리하는 화면이 들어갈 자리입니다.",
        plannedItems: ["신원 확인", "계약", "장비"], systemImage: "person.text.rectangle")
    static let originals = PlannedFeature(
        id: "originals", title: "원본 보관·삭제", summary: "이 폰에 남은 카메라 원본을 확인하고 지우는 화면이 들어갈 자리입니다.", systemImage: "externaldrive")
    static let support = PlannedFeature(
        id: "support", title: "고객지원", summary: "운영팀에 문의하는 화면이 들어갈 자리입니다.", systemImage: "questionmark.circle")
    static let terms = PlannedFeature(
        id: "terms", title: "약관·정책", summary: "작가 약관과 위치정보·개인정보 동의 내역이 들어갈 자리입니다.",
        plannedItems: ["작가 이용약관", "위치정보 동의", "개인정보 처리방침"], systemImage: "doc.plaintext")
}
