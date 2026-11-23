import SBSNBackend
import SBSNCore
import SwiftUI

/// 활성 티켓의 오래 도는 작업: 티켓 리스너, 만나는 동안의 위치 공유, 끝난 티켓의 잠금 해제와 갤러리 등록.
///
/// 뿌리 화면이 탭 뷰의 배경으로 붙인다. 탭 화면의 `.task`는 다른 탭으로 가면 취소되지만 이 뷰는 계속 떠 있어서,
/// 고객이 어느 탭에 있어도 위치 공유·상태 갱신·사진 자동 저장이 이어진다. 티켓이 바뀌면 `.id`로 새로 붙는다.
struct TicketBackgroundWork: View {
    let workspace: TicketWorkspace

    @Environment(CustomerSession.self) private var session
    @Environment(GalleryStore.self) private var galleries

    @Environment(\.scenePhase) private var scenePhase
    static let sharesMVPMeetupLocation = false

    var body: some View {
        Color.clear
            .task(id: workspace.listenerGeneration) { await workspace.listenToTicket() }
            // 옛 MVP 티켓은 만나는 위치를 주고받지 않는다(D063으로 MVP 매칭이 끝났다. 기기에 남은 진행 티켓이 위치를 붙잡지 않게).
            // 출시 티켓의 만나는 위치는 `CustomerLaunchTicketView`가 앱이 앞에 있을 때만 주고받는다(L13·L14).
            .task(id: workspace.isMeeting && scenePhase == .active) {
                guard Self.sharesMVPMeetupLocation, workspace.isMeeting, scenePhase == .active else { return }
                let sharing = workspace.locationSharing
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await sharing.listenToOthers() }
                    group.addTask { await sharing.shareMyLocation() }
                }
            }
            .onChange(of: workspace.latestTicket?.phase, initial: true) { _, phase in handlePhaseChange(phase) }
            .accessibilityHidden(true)
    }

    /// 끝나거나 취소되면 고객 잠금을 한 번만 푼다(실패는 무시). 취소는 다음 실행 때 다시 열리지 않게 저장값도 지운다.
    private func handlePhaseChange(_ phase: TicketPhase?) {
        switch phase {
        case .ended:
            releaseLockOnce()
            // 끝난 촬영은 내 사진 탭이 따로 기억한다. 새 촬영을 시작해도 공개되면 여기서 사진을 본다.
            if workspace.latestTicket?.isCurated == true {
                galleries.remember(workspace.ticketId)
            }
        case .cancelled:
            releaseLockOnce()
            session.clearStoredTicket(workspace.ticketId)
        default:
            break
        }
    }

    private func releaseLockOnce() {
        guard !workspace.hasReleasedLock else { return }
        workspace.hasReleasedLock = true
        let uid = workspace.myUid
        Task { try? await TicketService.releaseCustomerLock(uid: uid) }
    }
}

/// 활성 티켓의 작업 묶음을 하나만 들고 있는다. 티켓이 바뀌거나 없어지면 이전 묶음을 놓는다(리스너가 약한 참조로 끝난다).
@MainActor
final class TicketWorkspaceStore {
    private var current: TicketWorkspace?

    func workspace(ticketId: String?, uid: String) -> TicketWorkspace? {
        guard let ticketId else {
            current = nil
            return nil
        }
        if let current, current.ticketId == ticketId, current.myUid == uid {
            return current
        }
        let workspace = TicketWorkspace(ticketId: ticketId, myUid: uid)
        current = workspace
        return workspace
    }
}
