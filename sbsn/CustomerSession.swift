import Foundation
import Network
import Observation
import SBSNBackend

/// 고객 앱의 로그인 상태와 활성 티켓. 앱에 하나만 두고 화면은 환경으로 받는다.
///
/// 활성 티켓은 서버의 고객 잠금(`customers/{uid}.activeTicketId`)을 우선하고, 서버 값이 없으면 로컬에 기억한 ID를 쓴다.
/// 끝난 티켓은 서버 잠금이 풀린 뒤에도 사진 화면을 계속 써야 하므로 로컬 ID는 "새 촬영 찾기"를 누를 때 지운다.
@Observable
@MainActor
final class CustomerSession {
    enum Phase: Equatable {
        case signingIn
        case failed(String)
        case ready
    }

    static let storedTicketKey = "SBSNActiveTicketID"

    private(set) var phase = Phase.signingIn
    private(set) var uid: String?
    /// 서버 잠금이 가리키는 티켓. 아직 첫 스냅샷을 받지 못했거나 잠금이 없으면 nil.
    private(set) var serverTicketId: String?
    private(set) var localTicketId: String? = UserDefaults.standard.string(forKey: CustomerSession.storedTicketKey)
    /// 서버 잠금 리스너가 끊겼을 때의 안내. 로컬 ID로 계속 동작한다.
    private(set) var lockWarning: String?
    private(set) var isOnline = true
    /// 디버그 메뉴 동작의 결과 안내
    private(set) var debugMessage: String?

    /// 사용자가 "지도로 돌아가기"로 떠난 티켓. 서버 잠금 해제가 아직 반영되지 않았어도 지도로 갈 수 있게 한다.
    private var dismissedTicketId: String?
    private var lockTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()

    var activeTicketId: String? {
        if let serverTicketId, serverTicketId != dismissedTicketId {
            return serverTicketId
        }
        return localTicketId
    }

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in self?.isOnline = isOnline }
        }
        pathMonitor.start(queue: DispatchQueue(label: "sbsn.customer.network-path"))
    }

    /// 앱이 뜰 때 한 번. 로그인 실패 화면의 "다시 시도"도 이걸 부른다.
    func start() async {
        guard phase != .ready else { return }
        await signIn()
    }

    // MARK: - 활성 티켓

    /// 작가를 확정한 직후 부른다. 서버 리스너보다 먼저 티켓 화면으로 넘어가게 로컬에도 적는다.
    func rememberTicket(_ ticketId: String) {
        dismissedTicketId = nil
        localTicketId = ticketId
        UserDefaults.standard.set(ticketId, forKey: Self.storedTicketKey)
    }

    /// 취소된 티켓: 다음 실행 때 다시 열리지 않게 저장값만 지운다. 화면은 사용자가 "지도로 돌아가기"를 누를 때 바뀐다.
    func clearStoredTicket(_ ticketId: String) {
        guard UserDefaults.standard.string(forKey: Self.storedTicketKey) == ticketId else { return }
        UserDefaults.standard.removeObject(forKey: Self.storedTicketKey)
    }

    /// 티켓 화면을 떠나 지도로 돌아간다.
    func forgetLocalTicket() {
        dismissedTicketId = activeTicketId
        localTicketId = nil
        UserDefaults.standard.removeObject(forKey: Self.storedTicketKey)
    }

    // MARK: - 디버그

    /// 익명 계정을 버리고 새로 만든다. 시험에서 "새 고객"이 필요할 때만 쓴다.
    func reissueAccount() async {
        lockTask?.cancel()
        lockTask = nil
        forgetLocalTicket()
        dismissedTicketId = nil
        serverTicketId = nil
        uid = nil
        do {
            try await Backend.signOut()
        } catch {
            debugMessage = "계정을 지우지 못했습니다: \(error.localizedDescription)"
            await signIn()
            return
        }
        await signIn()
        if let uid {
            debugMessage = "새 익명 계정: \(uid)"
        }
    }

    func clearLocalTicketForDebug() {
        forgetLocalTicket()
        debugMessage = serverTicketId == nil ? "로컬 티켓을 지웠습니다." : "로컬 티켓을 지웠습니다. 서버 잠금은 남아 있습니다."
    }

    func dismissDebugMessage() {
        debugMessage = nil
    }

    // MARK: - 내부

    private func signIn() async {
        phase = .signingIn
        do {
            let uid = try await Backend.signedInUserID()
            self.uid = uid
            phase = .ready
            listenToServerLock(uid: uid)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func listenToServerLock(uid: String) {
        lockTask?.cancel()
        lockTask = Task {
            do {
                for try await ticketId in TicketService.customerActiveTicketId(uid: uid) {
                    serverTicketId = ticketId
                    if let ticketId, ticketId != dismissedTicketId {
                        rememberTicket(ticketId)
                    }
                    lockWarning = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                lockWarning = "서버에서 진행 중인 촬영을 확인하지 못했습니다: \(error.localizedDescription)"
            }
        }
    }
}
