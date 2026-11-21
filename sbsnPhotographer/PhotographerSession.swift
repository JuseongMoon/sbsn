import Foundation
import Observation
import SBSNBackend
import SBSNCore
import UIKit
import UserNotifications

/// 작가 앱의 상태를 한곳에서 든다: 로그인, "촬영 가능" 상태와 위치 발행, 진행 중인 티켓, 공개 대기 티켓들의 선별 업로드, 원격 알림, 복원.
///
/// 화면이 아니라 앱 수준 싱글턴이다. 화면을 오가도 업로드가 끊기지 않고,
/// 알림으로 백그라운드에서 실행돼 화면(scene)이 없을 때도 `AppDelegate`가 이 객체로 일을 시킬 수 있다.
///
/// 티켓은 두 종류로 든다(D040, 설계 문서 2.7절).
/// - 진행 중 티켓(`ticket`, 최대 1개): 매칭부터 촬영 종료까지. 작가 잠금과 짝이다.
/// - 공개 대기 티켓(`galleries`, 여럿): 촬영이 끝나 사진을 고르고 올리는 티켓. 공개 전에도 다음 매칭을 받을 수 있다.
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
    private static let pendingGalleriesKey = "SBSNPendingGalleryTicketIDs"
    private static let publishedGalleriesKey = "SBSNPublishedGalleries"

    private(set) var uid: String?
    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Self.displayNameKey) }
    }
    private(set) var isAvailable = false
    private(set) var presence: PhotographerPresence?
    /// 진행 중인 티켓(매칭~촬영). 끝나면 공개 대기로 옮기고 비운다.
    private(set) var ticket: TicketRecord?
    /// 공개 대기 티켓의 선별 업로드 엔진. 키는 티켓 ID.
    private(set) var galleries: [String: CuratedDeliveryModel] = [:]
    /// 최근에 공개한 촬영(구매 기한 동안 내역 탭에 남긴다)
    private(set) var publishedGalleries: [PublishedGallery] = []
    /// 지금 화면에 열린 공개 대기 티켓. 업로드 큐가 이 티켓을 먼저 처리한다.
    var focusedGalleryID: String?
    private(set) var registration = Registration.pending
    /// 배너·소리 권한. 꺼져 있어도 앱을 깨우는 알림은 받는다.
    private(set) var isAlertAuthorized: Bool?
    private(set) var errorMessage: String?
    /// 알림을 탭해 열어야 할 화면. 화면이 준비되면 가져간다.
    var pendingRoute: PhotographerRoute?
    /// 고객이 취소한 촬영. 취소되면 티켓을 놓고 홈으로 돌아가므로 작가가 알 수 있게 홈에 남겨 둔다(새 매칭이 오거나 확인하면 지운다).
    private(set) var cancelledByCustomer: TicketRecord?
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
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var deviceLog: DeviceConditionLog?
    @ObservationIgnored private lazy var uploadQueue = GalleryUploadQueue(
        models: { [unowned self] in Array(galleries.values) },
        focusedTicketID: { [unowned self] in focusedGalleryID }
    )

    private init() {
        displayName = UserDefaults.standard.string(forKey: Self.displayNameKey) ?? ""
        publishedGalleries = Self.loadPublishedGalleries()
        Backend.configure()
    }

    /// 공개 대기 티켓(먼저 끝난 촬영부터)
    var pendingGalleries: [CuratedDeliveryModel] {
        galleries.values.sorted { ($0.ticket.endedAt ?? .distantPast) < ($1.ticket.endedAt ?? .distantPast) }
    }

    /// 구매 기한이 지나지 않은 공개 기록(최근 것부터)
    var recentPublishedGalleries: [PublishedGallery] {
        publishedGalleries.filter { $0.publishedAt.addingTimeInterval(PhotoCuration.purchaseWindow) > Date() }
            .sorted { $0.publishedAt > $1.publishedAt }
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
        let deviceLog = DeviceConditionLog { [unowned self] in
            DeviceConditionLog.Context(isAvailable: isAvailable, phase: ticket.map { "\($0.phase)" } ?? "none")
        }
        deviceLog.start()
        self.deviceLog = deviceLog
        uploadQueue.start()
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
            await restoreGalleries()
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
        cancelledByCustomer = nil
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
            // 선별 흐름은 촬영 중에 위치가 필요 없다(만나기 위치 공유는 시작에서 멈춘다). 배터리를 아끼려고 끈다.
            if record.isCurated, !isAvailable {
                location.stop()
            }
        case .ended:
            if record.isCurated {
                beginGallery(for: record)
            }
            // 고객이 끝낸 경우(작가가 사라졌을 때) 고객이 같은 쓰기로 잠금을 풀었다. "촬영 가능"만 끈다.
            if presence?.isAvailable == true, let uid {
                Task { try? await PhotographerDirectory.setAvailable(uid: uid, false) }
            }
            detachTicket()
        case .cancelled:
            detachTicket()
            if record.cancelledBy == record.customerUid {
                announceCancellation(record)
            }
        }
        if previous?.phase != record.phase {
            // 매칭·촬영 중에는 공개 위치 대신 티켓 안 위치를 쓴다. 다음 위치부터 바로 보내도록 발행 기록을 지운다.
            lastPublishedAt = nil
            lastPublishedPoint = nil
        }
    }

    // MARK: - 공개 대기

    /// 끝난 선별 티켓을 공개 대기로 옮긴다. 화면은 그 티켓의 고르기 화면으로 간다.
    private func beginGallery(for record: TicketRecord) {
        if let model = galleries[record.id] {
            model.updateTicket(record)
        } else {
            let model = makeGallery(for: record)
            galleries[record.id] = model
            savePendingGalleries()
            if CuratedDeliveryModel.hasLocalFiles(ticketID: record.id) {
                // 앱을 다시 켰을 때 진행 중이던 티켓이 이미 끝나 있었다. 고르던 사진을 되살린다.
                Task { await model.restore() }
            }
            model.appendEvent("ended", "-", "-", bytes: 0, seconds: 0, note: record.endedAt.map { "\($0)" } ?? "")
            scheduleReminder(for: record)
        }
        pendingRoute = .gallery(record.id)
    }

    private func makeGallery(for record: TicketRecord) -> CuratedDeliveryModel {
        let model = CuratedDeliveryModel(ticket: record)
        model.onNeedsWork = { [weak self] in self?.uploadQueue.signal() }
        model.onPublished = { [weak self] model in self?.finishGallery(model) }
        return model
    }

    /// 앱을 켤 때 공개 대기 티켓을 되살린다. 취소됐거나 이전 방식이면 버리고, 이미 공개됐으면 공개 기록으로 옮긴다.
    private func restoreGalleries() async {
        for ticketID in UserDefaults.standard.stringArray(forKey: Self.pendingGalleriesKey) ?? [] where galleries[ticketID] == nil {
            guard let record = try? await TicketService.fetchTicket(ticketID) else {
                // 읽지 못하면(오프라인 등) 다음에 다시 본다. 로컬 기록만 있으면 일단 되살린다.
                continue
            }
            guard record.isCurated, record.phase == .ended else {
                try? FileManager.default.removeItem(at: CuratedDeliveryModel.directory(for: ticketID))
                continue
            }
            let model = makeGallery(for: record)
            galleries[ticketID] = model
            await model.restore()
        }
        savePendingGalleries()
        uploadQueue.signal()
    }

    /// 공개가 끝난 티켓: 공개 기록으로 옮기고 지연 알림을 지우고 로컬 사본을 지운다.
    private func finishGallery(_ model: CuratedDeliveryModel) {
        let record = PublishedGallery(ticketID: model.ticketID, publishedAt: model.ticket.galleryPublishedAt ?? Date(),
                                      endedAt: model.ticket.endedAt, photoCount: model.photos.count)
        publishedGalleries.removeAll { $0.ticketID == record.ticketID }
        publishedGalleries.append(record)
        savePublishedGalleries()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderID(model.ticketID)])
        galleries[model.ticketID] = nil
        savePendingGalleries()
        model.deleteLocalFiles()
    }

    private func savePendingGalleries() {
        UserDefaults.standard.set(pendingGalleries.map(\.ticketID), forKey: Self.pendingGalleriesKey)
    }

    private func savePublishedGalleries() {
        // 구매 기한이 지난 지 하루가 넘은 기록은 버린다.
        let keep = publishedGalleries.filter { $0.publishedAt.addingTimeInterval(PhotoCuration.purchaseWindow + 86_400) > Date() }
        publishedGalleries = keep
        UserDefaults.standard.set(try? JSONEncoder().encode(keep), forKey: Self.publishedGalleriesKey)
    }

    private static func loadPublishedGalleries() -> [PublishedGallery] {
        guard let data = UserDefaults.standard.data(forKey: publishedGalleriesKey) else { return [] }
        return (try? JSONDecoder().decode([PublishedGallery].self, from: data)) ?? []
    }

    /// 종료 30분 뒤에도 공개하지 않았으면 다시 알린다(티켓마다 한 번). 공개하면 지운다.
    private func scheduleReminder(for record: TicketRecord) {
        guard let endedAt = record.endedAt else { return }
        let fireAt = endedAt.addingTimeInterval(PhotoCuration.publishReminderDelay)
        let delay = fireAt.timeIntervalSinceNow
        guard delay > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "사진을 아직 공개하지 않았습니다"
        content.body = "고객이 사진을 기다리고 있습니다. 5~8장을 골라 공개해 주세요."
        content.sound = .default
        content.userInfo = ["type": "galleryReminder", "ticketId": record.id]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: Self.reminderID(record.id), content: content, trigger: trigger)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    private static func reminderID(_ ticketID: String) -> String { "gallery-reminder-\(ticketID)" }

    /// 고객이 취소하면 작가 앱은 티켓을 놓고 홈으로 돌아간다. 폰이 잠겨 있으면 작가가 모르고 고객을 찾아갈 수 있어
    /// 홈에 안내를 남기고, 앱이 화면에 없으면 로컬 알림을 띄운다. 매칭 중에는 백그라운드 위치로 앱이 살아 있어
    /// 티켓 리스너가 취소를 바로 받으므로 서버 알림 없이 된다(앱을 쓸어 올려 끈 경우는 다음에 열 때 홈 안내로 안다).
    private func announceCancellation(_ record: TicketRecord) {
        cancelledByCustomer = record
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = "촬영이 취소됐습니다"
        content.body = "고객이 촬영을 취소했습니다."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: "ticket-cancelled-\(record.id)", content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    func dismissCancellationNotice() {
        cancelledByCustomer = nil
    }

    private func detachTicket() {
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
                errorMessage = "진행 중인 촬영이 있습니다. 촬영을 끝내면 다시 켤 수 있습니다."
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
        } catch {
            errorMessage = "종료를 기록하지 못했습니다: \(error.localizedDescription)"
        }
    }

    func cancelMatch() async {
        guard let ticket, ticket.canCancel, let uid else { return }
        do {
            try await TicketService.cancel(ticket: ticket, by: uid)
            // 서버가 취소를 받았으면 리스너를 기다리지 않고 뗀다. 잠금이 읽을 수 없는 티켓을 가리켜
            // 이 티켓의 리스너가 끊긴 뒤에도 홈에 취소한 매칭이 남아 "촬영 가능"을 못 켜는 일을 막는다.
            if self.ticket?.id == ticket.id {
                detachTicket()
            }
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

    /// 원격 알림. 매칭은 티켓을 붙여 "받음"을 남긴다. 처리할 일이 있었으면 true.
    /// 구매 알림(`curatedPhotoPurchased`)은 판매 소식이라 할 일이 없다. 고화질본은 공개 전에 이미 올라가 있다(D038).
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        guard let notification = PhotographerPush.notification(from: userInfo) else { return false }
        await restoration?.value
        switch notification {
        case .match(let ticketID):
            await attach(ticketID: ticketID, restoring: false)
            return true
        case .message, .purchase:
            return false
        }
    }

    /// 알림을 탭했을 때. 진행 중 티켓이면 그 화면, 공개 대기·공개한 티켓이면 갤러리 화면으로 간다.
    func openTicket(_ ticketID: String, photoID: String? = nil) {
        if ticket?.id == ticketID {
            pendingRoute = .live(ticketID)
        } else if galleries[ticketID] != nil || publishedGalleries.contains(where: { $0.ticketID == ticketID }) {
            pendingRoute = .gallery(ticketID)
        } else {
            // 매칭 알림을 앱이 꺼져 있을 때 탭했다. 티켓을 붙이면 화면이 열린다.
            Task { await attach(ticketID: ticketID, restoring: activeTicketID == ticketID) }
        }
    }

    // MARK: - 생명주기

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.didBecomeActive()
                }
            },
        ]
    }

    /// 앱이 앞으로 오면 실패한 업로드를 다시 하고 큐를 깨운다(뒤에 있는 동안 멈춘 렌더·전송을 이어 간다).
    private func didBecomeActive() {
        for model in galleries.values {
            model.retryFailedUploads()
        }
        uploadQueue.signal()
    }

    // MARK: - 디버그

    /// 새 작가로 시험하려고 익명 계정을 버린다. 익명 계정은 키체인에 남아 앱을 지워도 돌아오기 때문이다.
    func resetAnonymousAccount() async {
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
        detachTicket()
    }

    #if DEBUG
    /// 서버 없이 고르기 화면을 시험한다(가져오기·검사·렌더·화면 상태). 가짜 끝난 티켓이라 업로드는 실패로 끝나고, 공개 대기 목록에 저장하지 않는다.
    func openDebugGallery() {
        let now = Date()
        let record = TicketRecord(id: "debug-\(UUID().uuidString.prefix(8).lowercased())", customerUid: "debug-customer",
                                  photographerUid: uid ?? "debug-photographer", photographerDisplayName: displayName,
                                  createdAt: now.addingTimeInterval(-20 * 60), customerStartedAt: now.addingTimeInterval(-15 * 60),
                                  photographerStartedAt: now.addingTimeInterval(-15 * 60), endedAt: now.addingTimeInterval(-60))
        let model = makeGallery(for: record)
        galleries[record.id] = model
        pendingRoute = .gallery(record.id)
    }
    #endif
}

/// 작가 앱 촬영 탭에서 여는 화면
enum PhotographerRoute: Hashable {
    /// 진행 중 티켓(만나기·촬영)
    case live(String)
    /// 공개 대기·공개한 티켓의 갤러리
    case gallery(String)
}

/// 공개한 촬영 기록(내역 탭). 구매 기한 동안 남긴다.
struct PublishedGallery: Codable, Identifiable, Hashable {
    let ticketID: String
    let publishedAt: Date
    let endedAt: Date?
    let photoCount: Int

    var id: String { ticketID }
    var purchaseClosesAt: Date { publishedAt.addingTimeInterval(PhotoCuration.purchaseWindow) }
}
