import Foundation
import Observation
import SBSNBackend
import SBSNCore
import UIKit
import UserNotifications

/// 작가 앱의 상태를 한곳에서 든다: 로그인, "촬영 가능" 상태와 위치 발행, 매칭된 티켓, 티켓의 전달 엔진, 원격 알림, 복원.
///
/// 화면이 아니라 앱 수준 싱글턴이다. 화면을 오가도 카메라 수신과 업로드가 끊기지 않고,
/// 알림으로 백그라운드에서 실행돼 화면(scene)이 없을 때도 `AppDelegate`가 이 객체로 일을 시킬 수 있다.
@Observable
@MainActor
final class PhotographerSession {
    enum Registration: Equatable {
        case pending
        case registered
        case failed(String)
    }

    static let shared = PhotographerSession()

    private static let displayNameKey = "SBSNDisplayName"
    private static let activeTicketKey = "SBSNActiveTicketID"
    private static let availableKey = "SBSNIsAvailable"

    private(set) var uid: String?
    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Self.displayNameKey) }
    }
    private(set) var isAvailable = false
    private(set) var presence: PhotographerPresence?
    private(set) var ticket: TicketRecord?
    /// 촬영 중·전달 중인 티켓의 수신·업로드 엔진
    private(set) var delivery: CameraTransferTestModel?
    private(set) var registration = Registration.pending
    /// 배너·소리 권한. 꺼져 있어도 앱을 깨우는 알림은 받는다.
    private(set) var isAlertAuthorized: Bool?
    private(set) var errorMessage: String?
    /// 알림을 탭해 열어야 할 티켓. 화면이 준비되면 가져간다.
    var pendingTicketID: String?
    private(set) var isRestoring = false
    let location = PhotographerLocationTracker()

    @ObservationIgnored private var presenceTask: Task<Void, Never>?
    @ObservationIgnored private var ticketTask: Task<Void, Never>?
    @ObservationIgnored private var restoration: Task<Void, Never>?
    @ObservationIgnored private var lifecycleObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var lastPublishedPoint: GeoPoint?
    @ObservationIgnored private var lastPublishedAt: Date?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var attachingTicketID: String?
    @ObservationIgnored private var deliveryWatch: Task<Void, Never>?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?

    private init() {
        displayName = UserDefaults.standard.string(forKey: Self.displayNameKey) ?? ""
        Backend.configure()
    }

    var activeTicketID: String? {
        UserDefaults.standard.string(forKey: Self.activeTicketKey)
    }

    var isLowPowerModeEnabled: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    var isBackgroundRefreshAvailable: Bool { UIApplication.shared.backgroundRefreshStatus == .available }

    // MARK: - 시작과 복원

    /// 앱이 실행될 때 한 번(`AppDelegate.didFinishLaunching`). 화면이 없는 백그라운드 실행에서도 불린다.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observeLifecycle()
        location.onLocation = { [weak self] point in
            self?.handleLocation(point)
        }
        startHeartbeat()
        restoration = Task { [weak self] in
            await self?.restoreIfNeeded()
        }
    }

    private func restoreIfNeeded() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            let uid = try await Backend.signedInUserID()
            self.uid = uid
            listenToPresence(uid: uid)
            // 맥에서 자동 시험을 돌릴 때 관리자 스크립트가 만든 시험 티켓을 실행 인자(-SBSNTicketID)로 넘긴다.
            if let testTicketID = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["SBSNTicketID"] as? String {
                await attach(ticketID: testTicketID, restoring: testTicketID == activeTicketID)
            } else if let ticketID = activeTicketID {
                await attach(ticketID: ticketID, restoring: true)
            }
            if UserDefaults.standard.bool(forKey: Self.availableKey) {
                // 지난번에 켜 둔 "촬영 가능"을 이어 간다. 위치가 오면 presence가 다시 발행된다.
                isAvailable = true
                location.start()
            }
        } catch {
            errorMessage = "로그인하지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func listenToPresence(uid: String) {
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            do {
                for try await presence in PhotographerDirectory.presence(of: uid) {
                    guard let self else { return }
                    self.presence = presence
                    if let presence {
                        isAvailable = presence.isAvailable
                        UserDefaults.standard.set(presence.isAvailable, forKey: Self.availableKey)
                    }
                    // 고객이 확정하면 잠금에 티켓 ID가 들어온다. 알림보다 먼저 올 수도, 나중에 올 수도 있다(둘 다 멱등).
                    if let ticketID = presence?.activeTicketId, ticketID != ticket?.id {
                        await attach(ticketID: ticketID, restoring: false)
                    }
                }
            } catch {
                self?.errorMessage = "상태를 읽지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    /// 티켓을 지켜보기 시작한다. 복원이면 로컬 폴더로 전달 엔진도 되살린다.
    /// presence 리스너와 알림이 같은 티켓을 거의 동시에 넘겨도 한 번만 붙는다.
    private func attach(ticketID: String, restoring: Bool) async {
        guard ticket?.id != ticketID, attachingTicketID != ticketID else { return }
        attachingTicketID = ticketID
        defer { attachingTicketID = nil }
        UserDefaults.standard.set(ticketID, forKey: Self.activeTicketKey)
        ticketTask?.cancel()
        // 첫 값은 한 번 읽어서 기다린다. 알림으로 깨어난 짧은 시간 안에 티켓 상태를 알아야 한다.
        if let record = try? await TicketService.fetchTicket(ticketID) {
            apply(record, restoring: restoring)
        }
        ticketTask = Task { [weak self] in
            do {
                for try await record in TicketService.ticket(ticketID) {
                    guard let self else { return }
                    if let record {
                        apply(record, restoring: false)
                    }
                }
            } catch {
                self?.errorMessage = "티켓을 읽지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    private func apply(_ record: TicketRecord, restoring: Bool) {
        let previous = ticket
        ticket = record
        switch record.phase {
        case .matched, .waitingForCustomer, .waitingForPhotographer:
            if record.photographerAckAt == nil {
                Task { await TicketService.acknowledge(ticketId: record.id) }
            }
        case .shooting:
            startDelivery(for: record, restoring: restoring)
        case .ended:
            if restoring, CameraTransferTestModel.hasLocalFiles(ticketID: record.id) {
                startDelivery(for: record, restoring: true)
            }
            delivery?.stopReceiving()
            // 고객이 끝낸 경우(작가가 사라졌을 때) 작가 잠금이 남아 있으니 작가 앱이 대신 풀고 "촬영 가능"도 끈다.
            if presence?.activeTicketId == record.id, let uid {
                Task {
                    try? await PhotographerDirectory.clearActiveTicket(uid: uid)
                    try? await PhotographerDirectory.setAvailable(uid: uid, false)
                }
            }
            releaseIfDelivered()
            watchDeliveryUntilDone()
        case .cancelled:
            delivery?.stop()
            delivery = nil
            detachTicket()
            if presence?.activeTicketId == record.id, let uid {
                Task { try? await PhotographerDirectory.clearActiveTicket(uid: uid) }
            }
        }
        if previous?.phase != record.phase {
            // 매칭·촬영 중에는 공개 위치 대신 티켓 안 위치를 쓴다. 다음 위치부터 바로 보내도록 발행 기록을 지운다.
            lastPublishedAt = nil
            lastPublishedPoint = nil
        }
    }

    private func makeDelivery(for record: TicketRecord) -> CameraTransferTestModel {
        let model = CameraTransferTestModel(ticketID: record.id, customerUID: record.customerUid)
        model.onLargeUploadFinished = { [weak self] in
            // 업로드 작업이 마무리된 뒤 확인하도록 한 번 미룬다.
            Task { @MainActor in self?.releaseIfDelivered() }
        }
        delivery = model
        return model
    }

    private func startDelivery(for record: TicketRecord, restoring: Bool) {
        if delivery == nil {
            let model = makeDelivery(for: record)
            if restoring {
                if CameraTransferTestModel.hasLocalFiles(ticketID: record.id) {
                    let headless = UIApplication.shared.applicationState == .background
                    Task {
                        await model.restore(headless: headless)
                        if record.phase == .shooting, UIApplication.shared.applicationState != .background {
                            model.start()
                        }
                    }
                } else {
                    errorMessage = "이 기기에 이전 촬영의 원본이 없습니다. 촬영을 종료해 주세요."
                }
            } else if UIApplication.shared.applicationState != .background {
                model.start()
            }
        } else if record.phase == .shooting, UIApplication.shared.applicationState != .background {
            delivery?.start()
        }
    }

    /// 종료된 티켓의 구매 전달이 다 끝나면 티켓을 놓는다. 그 전까지는 새 "촬영 가능"을 켤 수 없다.
    func releaseIfDelivered() {
        guard let ticket, ticket.phase == .ended else { return }
        if let delivery, delivery.hasPendingDeliveries {
            return
        }
        delivery?.stop()
        delivery = nil
        detachTicket()
    }

    /// 미리 올리기 시간이 끝나는 것처럼 이벤트 없이 바뀌는 조건이 있어, 종료된 티켓은 30초마다 전달이 끝났는지 본다.
    private func watchDeliveryUntilDone() {
        guard deliveryWatch == nil else { return }
        deliveryWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, ticket?.phase == .ended else { break }
                releaseIfDelivered()
            }
            self?.deliveryWatch = nil
        }
    }

    private func detachTicket() {
        deliveryWatch?.cancel()
        deliveryWatch = nil
        ticketTask?.cancel()
        ticketTask = nil
        ticket = nil
        UserDefaults.standard.removeObject(forKey: Self.activeTicketKey)
        if !isAvailable {
            location.stop()
        }
    }

    // MARK: - 촬영 가능

    var canGoAvailable: Bool {
        PhotographerPresence.validDisplayName(displayName) != nil && ticket == nil && uid != nil
    }

    /// "촬영 가능"을 켜고 끈다. 켜면 위치·알림 권한을 묻고, 첫 위치가 오면 공개 상태를 발행한다.
    func setAvailable(_ available: Bool) {
        guard let uid else { return }
        if available {
            guard let name = PhotographerPresence.validDisplayName(displayName) else {
                errorMessage = "이름을 1~39자로 입력해 주세요."
                return
            }
            guard ticket == nil else {
                errorMessage = "진행 중인 촬영이 있습니다. 전달이 끝나면 다시 켤 수 있습니다."
                return
            }
            displayName = name
            isAvailable = true
            UserDefaults.standard.set(true, forKey: Self.availableKey)
            errorMessage = nil
            location.start()
            requestNotificationAuthorizationIfNeeded()
            if let point = location.latest {
                publishPresence(point: point)
            }
        } else {
            isAvailable = false
            UserDefaults.standard.set(false, forKey: Self.availableKey)
            if ticket == nil {
                location.stop()
            }
            Task {
                do {
                    try await PhotographerDirectory.setAvailable(uid: uid, false)
                } catch {
                    errorMessage = "상태를 끄지 못했습니다: \(error.localizedDescription)"
                }
            }
        }
    }

    /// 위치는 10m 움직여야 새로 오므로, 한자리에 서 있어도 살아 있음을 알리게 15초마다 마지막 위치로 발행 여부를 다시 본다.
    /// 백그라운드 위치 수신이 켜져 있는 동안은 앱이 멈추지 않아 이 반복도 계속 돈다.
    private func startHeartbeat() {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                if location.isTracking, let point = location.latest {
                    handleLocation(point)
                }
            }
        }
    }

    private func handleLocation(_ point: GeoPoint) {
        if let ticket {
            // 매칭 뒤 만나기 전까지만: 만나야 하므로 자주, 정확하게. 촬영이 시작되면 보내지 않는다.
            guard ticket.phase.isActive, ticket.phase != .shooting,
                  shouldPublish(point, minimumDistance: 10, minimumInterval: 15) else { return }
            markPublished(point)
            Task {
                try? await TicketLocationService.publish(ticketId: ticket.id, uid: ticket.photographerUid, point: point)
            }
        } else if isAvailable {
            // 대기 중: 고객 지도용. 25m 움직이거나 3분마다. 쓰기마다 모든 고객 지도가 읽기를 하므로 아낀다.
            guard shouldPublish(point, minimumDistance: PhotographerPresence.movementThresholdMeters,
                                minimumInterval: PhotographerPresence.heartbeatInterval) else { return }
            publishPresence(point: point)
        }
    }

    private func shouldPublish(_ point: GeoPoint, minimumDistance: Double, minimumInterval: TimeInterval) -> Bool {
        guard let lastPublishedAt, let lastPublishedPoint else { return true }
        return Date().timeIntervalSince(lastPublishedAt) >= minimumInterval || point.distance(to: lastPublishedPoint) >= minimumDistance
    }

    private func markPublished(_ point: GeoPoint) {
        lastPublishedAt = Date()
        lastPublishedPoint = point
    }

    private func publishPresence(point: GeoPoint) {
        guard let uid, isAvailable else { return }
        markPublished(point)
        let name = PhotographerPresence.validDisplayName(displayName) ?? "작가"
        Task {
            do {
                try await PhotographerDirectory.publish(uid: uid, displayName: name, isAvailable: true, location: point)
            } catch {
                errorMessage = "위치를 올리지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - 전이

    func markStarted() async {
        guard let ticket, ticket.canStart(.photographer) else { return }
        do {
            try await TicketService.markStarted(ticketId: ticket.id, role: .photographer)
        } catch {
            errorMessage = "시작을 기록하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func endShooting() async {
        guard let ticket, ticket.canEnd(.photographer) else { return }
        do {
            try await TicketService.end(ticketId: ticket.id, photographerUid: ticket.photographerUid)
            delivery?.stopReceiving()
        } catch {
            errorMessage = "종료를 기록하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func cancelMatch() async {
        guard let ticket, ticket.canCancel, let uid else { return }
        do {
            try await TicketService.cancel(ticket: ticket, by: uid)
        } catch {
            errorMessage = "취소하지 못했습니다: \(error.localizedDescription)"
        }
    }

    // MARK: - 알림

    func requestNotificationAuthorizationIfNeeded() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                isAlertAuthorized = granted
            } else {
                isAlertAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
        }
    }

    func setRegistration(_ registration: Registration) {
        self.registration = registration
    }

    /// 원격 알림. 매칭은 티켓을 붙여 "받음"을 남기고, 구매는 전달 엔진이 고화질본을 올린다. 처리할 일이 있었으면 true.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard let notification = PhotographerPush.notification(from: userInfo) else { return false }
        await waitForRestoration()
        switch notification {
        case .match(let ticketID):
            await attach(ticketID: ticketID, restoring: false)
            return true
        case .message:
            return false
        case .purchase(let purchase):
            if delivery == nil || delivery?.ticketID != purchase.ticketID {
                // 앱이 메모리에서 내려간 뒤 깨어났다. 로컬 폴더가 있으면 가볍게 복원해서 그 한 장을 올린다.
                guard activeTicketID == purchase.ticketID, CameraTransferTestModel.hasLocalFiles(ticketID: purchase.ticketID),
                      let ticket, ticket.id == purchase.ticketID
                else { return false }
                let model = makeDelivery(for: ticket)
                await model.restore(headless: true)
            }
            guard let delivery else { return false }
            return await delivery.handleWake(for: purchase)
        }
    }

    /// 복원이 끝나기를 잠깐 기다린다. 알림으로 깨어 있는 시간이 짧아 5초만 기다리고 넘어간다.
    /// (기다리기를 그만둬도 복원 자체는 계속된다.)
    private func waitForRestoration() async {
        guard let restoration else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await restoration.value }
            group.addTask { try? await Task.sleep(for: .seconds(5)) }
            await group.next()
            group.cancelAll()
        }
    }

    /// 알림을 탭했을 때. 화면이 준비돼 있으면 티켓 화면으로 간다.
    func openTicket(_ ticketID: String) {
        pendingTicketID = ticketID
        if ticket?.id != ticketID {
            Task { await attach(ticketID: ticketID, restoring: activeTicketID == ticketID) }
        }
    }

    // MARK: - 생명주기

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // 자동 시험 도구가 이 기록으로 백그라운드 전환을 확인한다.
                    self?.delivery?.note("scenePhase: background")
                    self?.delivery?.suspendForBackground()
                }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.didBecomeActive()
                }
            },
        ]
    }

    private func didBecomeActive() {
        delivery?.note("scenePhase: active")
        if ticket?.phase == .shooting {
            delivery?.resumeFromBackground()
            // 앱이 뒤에 있는 동안 촬영이 시작됐으면(상대가 마지막으로 시작을 누름) 수신을 아직 열지 않았다.
            delivery?.start()
        } else {
            delivery?.retryFailedUploads()
        }
        releaseIfDelivered()
    }

    // MARK: - 디버그

    /// 새 작가로 시험하려고 익명 계정을 버린다. 익명 계정은 키체인에 남아 앱을 지워도 돌아오기 때문이다.
    func resetAnonymousAccount() async {
        delivery?.stop()
        delivery = nil
        presenceTask?.cancel()
        ticketTask?.cancel()
        ticket = nil
        presence = nil
        isAvailable = false
        location.stop()
        UserDefaults.standard.removeObject(forKey: Self.activeTicketKey)
        UserDefaults.standard.set(false, forKey: Self.availableKey)
        do {
            try await Backend.signOut()
            let uid = try await Backend.signedInUserID()
            self.uid = uid
            listenToPresence(uid: uid)
            errorMessage = nil
        } catch {
            errorMessage = "계정을 다시 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    func clearLocalTicket() {
        delivery?.stop()
        delivery = nil
        detachTicket()
    }
}
