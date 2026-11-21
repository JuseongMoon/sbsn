import SBSNUI

/// 작가 앱에서 기획에는 있지만 아직 만들지 않은 메뉴(빈 페이지). 근거는 총괄 문서 `UI_WIREFRAME_PLAN.md` 2절.
enum PhotographerFeatures {
    // 촬영 탭
    static let activityArea = PlannedFeature(
        id: "activityArea", title: "활동 위치·반경", summary: "촬영할 지역과 이동할 수 있는 거리를 정하는 화면이 들어갈 자리입니다.",
        plannedItems: ["활동 지역", "반경"], systemImage: "mappin.and.ellipse")
    static let breakTime = PlannedFeature(
        id: "breakTime", title: "휴게", summary: "잠깐 쉬는 동안 새 매칭을 받지 않게 하는 화면이 들어갈 자리입니다.",
        plannedItems: ["휴게 시작·끝", "휴게 시간 기록"], systemImage: "cup.and.saucer")
    static let requestPolicy = PlannedFeature(
        id: "requestPolicy", title: "수락·거절 설정", summary: "새 요청을 수락하거나 거절하는 화면이 들어갈 자리입니다. 지금은 고객이 확정하면 바로 매칭됩니다.",
        plannedItems: ["요청 수락", "거절 사유"], systemImage: "hand.raised")
    static let customerBrief = PlannedFeature(
        id: "customerBrief", title: "고객 브리프", summary: "고객이 남긴 요청 사항을 보는 화면이 들어갈 자리입니다.",
        plannedItems: ["인원", "원하는 분위기", "소통 언어"], systemImage: "doc.text")
    static let safety = PlannedFeature(
        id: "safety", title: "안전·긴급 지원", summary: "현장에서 문제가 생겼을 때 도움을 요청하는 화면이 들어갈 자리입니다.",
        plannedItems: ["긴급 연락", "신고"], systemImage: "exclamationmark.shield")
    static let timer = PlannedFeature(
        id: "timer", title: "10분 타이머", summary: "촬영 시간을 재는 타이머가 촬영 화면 위쪽에 들어갈 자리입니다.",
        plannedItems: ["남은 시간", "연장"], systemImage: "timer")
    static let cameraGuide = PlannedFeature(
        id: "cameraGuide", title: "카메라 연결 가이드", summary: "카메라 기종별로 FTP 전송을 설정하는 방법이 들어갈 자리입니다. 연결 주소·포트·암호는 이 화면에 그대로 보입니다.",
        plannedItems: ["소니", "캐논", "니콘", "후지", "핫스팟 설정"], systemImage: "camera.badge.ellipsis")
    static let photoReview = PlannedFeature(
        id: "photoReview", title: "사진 검수·공개", summary: "고객에게 보일 사진을 고르는 화면이 들어갈 자리입니다. 지금은 받은 사진이 바로 고객에게 보입니다.",
        plannedItems: ["AI 후보", "제외·복원", "고객 공개 승인"], systemImage: "checkmark.rectangle.stack")

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
