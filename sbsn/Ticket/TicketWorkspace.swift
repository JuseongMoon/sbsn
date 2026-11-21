import Foundation
import Observation
import SBSNBackend
import SBSNCore

/// 티켓 하나를 보는 동안 화면들이 같이 쓰는 객체 묶음. 활성 티켓이 바뀌면 통째로 새로 만든다.
///
/// 티켓 리스너·위치 공유는 화면이 아니라 `TicketBackgroundWork`(뿌리 화면에 붙음)가 돌린다.
/// 탭을 옮기면 그 탭 화면의 `.task`가 취소되므로, 고객이 "내 사진"·"마이"에 있는 동안에도 계속 돌게 하려는 것이다.
/// 끝난 촬영의 사진(갤러리)은 진행 중 티켓과 따로 `GalleryStore`가 든다(D040 ①).
@Observable
@MainActor
final class TicketWorkspace {
    let ticketId: String
    let myUid: String
    let locationSharing: TicketLocationSharing

    /// 리스너가 마지막으로 받은 티켓. 화면은 쓰는 동안에는 이 값을 바로 반영하지 않는다(`CustomerTicketView`).
    private(set) var latestTicket: TicketRecord?
    private(set) var hasReceivedSnapshot = false
    private(set) var loadError: String?
    /// "다시 시도"로 올리면 리스너를 새로 붙인다.
    var listenerGeneration = 0
    /// 끝나거나 취소된 티켓의 고객 잠금은 한 번만 푼다.
    @ObservationIgnored var hasReleasedLock = false

    init(ticketId: String, myUid: String) {
        self.ticketId = ticketId
        self.myUid = myUid
        locationSharing = TicketLocationSharing(ticketId: ticketId, myUid: myUid)
    }

    /// 만나는 단계(둘 다 시작하기 전)에만 위치를 주고받는다.
    var isMeeting: Bool {
        switch latestTicket?.phase {
        case .matched, .waitingForPhotographer, .waitingForCustomer: true
        default: false
        }
    }

    func listenToTicket() async {
        loadError = nil
        do {
            for try await update in TicketService.ticket(ticketId) {
                latestTicket = update
                hasReceivedSnapshot = true
            }
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }
}
