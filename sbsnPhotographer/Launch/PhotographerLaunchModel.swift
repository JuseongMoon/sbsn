import Foundation
import Observation
import SBSNBackend
import SBSNCore

/// 작가 앱의 출시 2단계 상태(D064~D066): 내 대화방·안 읽은 수, 답을 기다리는 신청(만료 순 20개), 진행 중인 티켓.
/// 시작 대기 동안 정밀 위치를 10초마다 티켓에 올린다(L13·L14, 작가는 촬영 가능 동안 백그라운드 위치 세션이 돈다).
@Observable
@MainActor
final class PhotographerLaunchModel {
    private(set) var uid: String?
    private(set) var rooms: [LaunchMatch.Room] = []
    private(set) var unread: [String: Int] = [:]
    private(set) var pendingRequests: [LaunchMatch.Request] = []
    private(set) var recentTickets: [LaunchMatch.Ticket] = []
    private(set) var activeTicket: LaunchMatch.Ticket?
    private(set) var listenError: String?
    /// 채팅 탭 화면 경로(방 ID)
    var chatPath: [String] = []
    /// 다른 화면에서 탭을 바꿔 달라는 요청
    var requestedTab: PhotographerTab?

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored var latestLocation: () -> GeoPoint? = { nil }

    var totalUnread: Int { unread.values.reduce(0, +) }

    func start(uid: String?) {
        guard uid != self.uid else { return }
        tasks.forEach { $0.cancel() }
        tasks = []
        locationTask?.cancel()
        locationTask = nil
        self.uid = uid
        rooms = []
        unread = [:]
        pendingRequests = []
        recentTickets = []
        activeTicket = nil
        listenError = nil
        chatPath = []
        guard let uid else { return }
        tasks = [
            Task { [weak self] in await self?.listen(LaunchMatchService.rooms(uid: uid, role: .photographer)) { $0.rooms = $1 } },
            Task { [weak self] in await self?.listen(LaunchMatchService.unreadCounts(uid: uid)) { $0.unread = $1 } },
            Task { [weak self] in
                await self?.listen(LaunchMatchService.pendingRequests(photographerUid: uid)) { model, requests in
                    model.pendingRequests = requests
                }
            },
            Task { [weak self] in
                await self?.listen(LaunchMatchService.recentTickets(uid: uid, role: .photographer)) { model, tickets in
                    model.recentTickets = tickets
                    model.activeTicket = tickets.first(where: \.isActive)
                    model.followMeetupLocation()
                }
            },
        ]
    }

    /// 지금 답할 수 있는 신청(만료 시각이 지난 것은 서버 정리 전이어도 뺀다)
    func waitingRequests(now: Date = Date()) -> [LaunchMatch.Request] {
        pendingRequests.filter { $0.isWaiting(now: now) }
    }

    func room(_ id: String) -> LaunchMatch.Room? { rooms.first { $0.id == id } }

    func mutualCancelAwaitingAnswer(roomId: String) -> LaunchMatch.Ticket? {
        guard let uid else { return nil }
        return recentTickets.first { $0.roomId == roomId && $0.awaitsMutualAnswer(from: uid, now: Date()) }
    }

    /// 계정 삭제를 서버에 묻기 전에 막을 진행 건(설계 2.6)
    var localDeletionBlocker: AccountService.DeletionBlocked? {
        if let activeTicket { return .init(kind: .ticket, blockerId: activeTicket.id, unlockAt: nil) }
        if let request = waitingRequests().first { return .init(kind: .request, blockerId: request.id, unlockAt: nil) }
        return nil
    }

    func show(_ blocker: AccountService.DeletionBlocked) {
        switch blocker.kind {
        case .ticket, .delivery:
            requestedTab = .shoot
        case .request:
            Task {
                var roomId = pendingRequests.first { $0.id == blocker.blockerId }?.roomId
                if roomId == nil {
                    roomId = (try? await LaunchMatchService.request(id: blocker.blockerId))?.roomId
                }
                guard let roomId else { return }
                chatPath = [roomId]
                requestedTab = .chat
            }
        }
    }

    /// 시작 대기 동안 10초마다 내 위치를 티켓에 올린다. 시작·취소되면 멈춘다(규칙도 그때 닫는다).
    private func followMeetupLocation() {
        guard let uid, let ticket = activeTicket, ticket.status == .matched else {
            locationTask?.cancel()
            locationTask = nil
            return
        }
        guard locationTask == nil else { return }
        let ticketId = ticket.id
        locationTask = Task { [weak self] in
            while !Task.isCancelled {
                if let point = self?.latestLocation() {
                    try? await TicketLocationService.publish(ticketId: ticketId, uid: uid, point: point, launch: true)
                }
                try? await Task.sleep(for: .seconds(LocationSample.meetupPublishInterval))
            }
        }
    }

    private func listen<T: Sendable>(_ stream: AsyncThrowingStream<T, Error>, apply: (PhotographerLaunchModel, T) -> Void) async {
        do {
            for try await value in stream { apply(self, value) }
        } catch {
            guard !Task.isCancelled else { return }
            listenError = "대화 정보를 불러오지 못했어요: \(error.localizedDescription)"
        }
    }
}
