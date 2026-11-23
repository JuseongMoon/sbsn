import Foundation

/// 위치를 쓰는 때(출시 기준, 총괄 2026-11-23 팀원 제보 대응).
/// - 작가: "촬영 가능"을 켠 동안(공개 지도 1분 발행), 또는 출시 티켓이 매칭 뒤 시작 전(만나는 위치, L13·L14)일 때만 쓴다.
///   만나는 위치는 촬영 가능과 별개로 티켓에 묶는다: 시작 대기 중 촬영 가능이 꺼져도 시작·취소·종료까지 유지한다(총괄 공통 기준).
///   옛 MVP 티켓은 위치를 켜지 않는다(D063으로 MVP 매칭이 끝났고, 기기에 남은 진행 티켓이 위치를 붙잡던 것을 막는다).
///   그 밖에는 모든 위치 수신을 즉시 멈추고 마지막 위치도 지운다(낡은 위치를 올리지 않게).
/// - 고객: 앱이 앞에 있을 때만 쓴다(L13). 백그라운드로 가면 멈추고 앞으로 오면 다시 받는다.
public enum LocationUse {
    public static func photographerNeedsLocation(isAvailable: Bool, launchMeetup: Bool) -> Bool {
        isAvailable || launchMeetup
    }

    /// MVP 티켓에서 만나는 단계(시작 전)
    public static func isMeetup(_ phase: TicketPhase) -> Bool {
        switch phase {
        case .matched, .waitingForCustomer, .waitingForPhotographer: true
        case .shooting, .ended, .cancelled: false
        }
    }
}
