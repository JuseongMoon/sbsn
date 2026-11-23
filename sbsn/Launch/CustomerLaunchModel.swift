import CoreLocation
import Observation
import UIKit
import SBSNBackend
import SBSNCore

/// 고객 앱의 출시 2단계 상태(D064~D066): 내 대화방·안 읽은 수, 답을 기다리는 내 신청(한 번에 하나, L15), 진행 중인 티켓.
///
/// 연결된 계정(Apple·Google)일 때만 듣는다(규칙이 익명 읽기를 막는다). 계정이 바뀌면 `start(uid:)`를 다시 부른다.
/// 쓰기는 모두 서버 함수이고 화면은 이 리스너가 바뀐 뒤 바뀐다.
@Observable
@MainActor
final class CustomerLaunchModel {
    private(set) var uid: String?
    private(set) var rooms: [LaunchMatch.Room] = []
    private(set) var unread: [String: Int] = [:]
    private(set) var pendingRequest: LaunchMatch.Request?
    private(set) var activeTicket: LaunchMatch.Ticket?
    /// 최근 티켓 5개(상호 취소 동의 카드를 그 방에 띄우는 데 쓴다)
    private(set) var recentTickets: [LaunchMatch.Ticket] = []
    private(set) var listenError: String?
    /// 채팅 탭의 화면 경로(방 ID). 알림·삭제 막힘에서 방을 열 때 쓴다.
    var chatPath: [String] = []
    /// 다른 화면에서 탭을 바꿔 달라는 요청(뿌리 화면이 받아 지운다)
    var requestedTab: CustomerTab?
    /// 몇 초 보이는 알림 줄(늦은 응답 결과 등)
    var toast: String?

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    var totalUnread: Int { unread.values.reduce(0, +) }

    /// 연결된 계정의 uid(익명이면 nil). 같은 uid면 그대로 둔다.
    func start(uid: String?) {
        guard uid != self.uid else { return }
        tasks.forEach { $0.cancel() }
        tasks = []
        self.uid = uid
        rooms = []
        unread = [:]
        pendingRequest = nil
        activeTicket = nil
        recentTickets = []
        listenError = nil
        chatPath = []
        guard let uid else { return }
        tasks = [
            Task { [weak self] in
                await self?.listen(LaunchMatchService.rooms(uid: uid, role: .customer)) { $0.rooms = $1 }
            },
            Task { [weak self] in
                await self?.listen(LaunchMatchService.unreadCounts(uid: uid)) { $0.unread = $1 }
            },
            Task { [weak self] in
                await self?.listen(LaunchMatchService.pendingRequests(customerUid: uid)) { model, requests in
                    model.pendingRequest = requests.first { $0.isWaiting(now: Date()) }
                }
            },
            Task { [weak self] in
                await self?.listen(LaunchMatchService.recentTickets(uid: uid, role: .customer)) { model, tickets in
                    model.recentTickets = tickets
                    model.activeTicket = tickets.first(where: \.isActive)
                }
            },
        ]
    }

    /// 이 방에서 상대가 "서로 취소"를 요청해 내가 답할 티켓
    func mutualCancelAwaitingAnswer(roomId: String) -> LaunchMatch.Ticket? {
        guard let uid else { return nil }
        return recentTickets.first { $0.roomId == roomId && $0.awaitsMutualAnswer(from: uid, now: Date()) }
    }

    /// 앱이 아는 진행 중인 건(계정 삭제를 서버에 묻기 전에 막는다, 설계 2.6)
    var localDeletionBlocker: AccountService.DeletionBlocked? {
        if let activeTicket { return .init(kind: .ticket, blockerId: activeTicket.id, unlockAt: nil) }
        if let pendingRequest, pendingRequest.isWaiting(now: Date()) {
            return .init(kind: .request, blockerId: pendingRequest.id, unlockAt: nil)
        }
        return nil
    }

    /// [진행 중인 촬영 보기]: 티켓이면 촬영 탭, 신청이면 그 대화방
    func show(_ blocker: AccountService.DeletionBlocked) {
        switch blocker.kind {
        case .ticket, .delivery:
            requestedTab = .shoot
        case .request:
            Task {
                let roomId = pendingRequest?.id == blocker.blockerId ? pendingRequest?.roomId
                    : (try? await LaunchMatchService.request(id: blocker.blockerId))?.roomId
                guard let roomId else { return }
                chatPath = [roomId]
                requestedTab = .chat
            }
        }
    }

    func room(_ id: String) -> LaunchMatch.Room? {
        rooms.first { $0.id == id }
    }

    private func listen<T: Sendable>(_ stream: AsyncThrowingStream<T, Error>, apply: (CustomerLaunchModel, T) -> Void) async {
        do {
            for try await value in stream {
                apply(self, value)
            }
        } catch {
            guard !Task.isCancelled else { return }
            listenError = "대화 정보를 불러오지 못했어요: \(error.localizedDescription)"
        }
    }
}

/// 고객 현재 위치(활동 반경 판정용, D065). 위치는 기기에서만 쓰고 서버로 보내지 않는다.
/// 화면이 보이고 앱이 앞에 있는 동안만 `track()`을 돌린다(L13). 화면은 `scenePhase`가 바뀌면 작업을 끝내고 다시 시작한다.
@Observable
@MainActor
final class CustomerLocationReader {
    static let shared = CustomerLocationReader()

    private(set) var latest: CLLocation?
    /// 앱이 앞에 있지 않을 때 받은 위치 수(0이어야 한다, 개발 메뉴·시험 확인용). 만나는 위치 공유 몫까지 더한다.
    static var backgroundUpdates = 0

    /// EPSG:5179 mm
    var projected: PublicLocationGrid.ProjectedPoint? {
        latest.map { PublicLocationGrid.project(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
    }

    func track() async {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let location = update.location else { continue }
                if UIApplication.shared.applicationState != .active { Self.backgroundUpdates += 1 }
                latest = location
            }
        } catch {}
    }
}
