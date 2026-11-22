import os
import Foundation
import Network
import Observation
import SBSNBackend
import UIKit

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
    /// 계정 삭제 뒤 한 번 보이는 알림(로그아웃 뒤 마이 탭 위에 띄운다. 다음 실행 때 다시 알리지 않는다)
    var accountNotice: String?
    /// 로그인·연결·로그아웃마다 오른다. 익명 → 연결은 uid가 같아 이것으로 출시 리스너를 다시 붙인다.
    private(set) var accountRevision = 0

    /// 사용자가 "지도로 돌아가기"로 떠난 티켓. 서버 잠금 해제가 아직 반영되지 않았어도 지도로 갈 수 있게 한다.
    private var dismissedTicketId: String?
    private var lockTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var activeObserver: (any NSObjectProtocol)?

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
        // 앱이 앞으로 올 때 저장된 로그인이 서버에서 무효가 됐는지 본다(다른 기기·웹에서 계정 삭제 등).
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.revalidateAccount() }
            }
        }
    }

    /// 저장된 로그인이 서버에서 무효면(지워짐·막힘·갱신 토큰 폐기) 새 익명 계정으로 둘러보기를 이어 간다(총괄 공통 기준).
    /// 앱 시작 때의 확인은 `Backend.signedInUserID()`가 한다.
    private func revalidateAccount() async {
        guard phase == .ready, uid != nil else { return }
        guard !(await Backend.validateSession()) else { return }
        Self.log.notice("저장된 로그인이 무효라 새 익명 계정으로 바꿈")
        UserDefaults.standard.removeObject(forKey: "SBSNLaunchNickname")
        await reissueAccount(reportsInDebug: false)
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
    static let log = Logger(subsystem: "com.ScienceFiction.sbsn", category: "account")

    func reissueAccount(reportsInDebug: Bool = true) async {
        Self.log.info("계정 다시 만들기 시작(현재 \(AccountService.current?.isAnonymous == true ? "익명" : "연결", privacy: .public))")
        lockTask?.cancel()
        lockTask = nil
        forgetLocalTicket()
        dismissedTicketId = nil
        serverTicketId = nil
        uid = nil
        do {
            try await Backend.signOut()
            Self.log.info("로그아웃함")
        } catch {
            Self.log.error("로그아웃 실패: \(String(describing: error), privacy: .public)")
            debugMessage = "계정을 지우지 못했습니다: \(error.localizedDescription)"
            await signIn()
            return
        }
        await signIn()
        if reportsInDebug, let uid {
            debugMessage = "새 익명 계정: \(uid)"
        }
    }

    /// 로그인으로 계정이 바뀌었을 때 리스너를 새 uid로 다시 붙인다(연결은 uid가 같고, 이미 있던 계정으로 로그인하면 바뀐다).
    /// 탭 화면을 "로그인 중"으로 내리지 않고 uid와 리스너만 바꾼다(내렸다 올리면 화면이 깜빡이고 그 사이 누른 단추가 사라진다).
    func accountDidChange() async {
        accountRevision += 1
        guard let current = AccountService.current?.uid, current != uid else { return }
        lockTask?.cancel()
        lockTask = nil
        forgetLocalTicket()
        dismissedTicketId = nil
        serverTicketId = nil
        uid = current
        listenToServerLock(uid: current)
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
        accountRevision += 1
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
