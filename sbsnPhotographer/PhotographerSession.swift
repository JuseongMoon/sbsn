import Foundation
import os
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

    private static let activeTicketKey = "SBSNActiveTicketID"
    private static let availableKey = "SBSNIsAvailable"
    private static let pendingGalleriesKey = "SBSNPendingGalleryTicketIDs"
    private static let publishedGalleriesKey = "SBSNPublishedGalleries"

    private(set) var uid: String?
    /// "촬영 가능". UserDefaults에 남기고 출시 발행기(`launchPublisher`)와 함께 켜고 끈다(D063, MVP presence는 지웠다).
    private(set) var isAvailable = false
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
    /// 출시 1단계 공개 위치 발행(D059·D063)
    let launchPublisher = LaunchPresencePublisher()
    /// 지금 로그인한 계정. 익명이면 로그인 화면을 보인다(작가는 처음부터 로그인, D051·D063).
    private(set) var account: AccountService.Account?
    /// 계정 삭제 뒤 한 번 보이는 알림(로그인 관문 위에 띄운다. 다음 실행 때 다시 알리지 않는다)
    var accountNotice: String?

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
        launchPublisher.latestLocation = { [weak self] in self?.location.latest }
        // 작가 기기 한 대(L08): 다른 기기가 촬영 가능을 켜면 이 기기는 끄고 알린다(Android와 같은 문구).
        launchPublisher.onReplacedByOtherDevice = { [weak self] in
            self?.setAvailable(false)
            self?.errorMessage = LaunchArtistService.Failure.replacedByOtherDevice.errorDescription
        }
        // 운영 승인 전 작가(L07)·삭제 요청 중: 서버가 거부하면 끄고 서버 문구를 보인다.
        launchPublisher.onRejected = { [weak self] message in
            self?.setAvailable(false)
            self?.errorMessage = message
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
            account = AccountService.current
            // 맥에서 자동 시험을 돌릴 때 관리자 스크립트가 만든 시험 티켓을 실행 인자(-SBSNTicketID)로 넘긴다.
            if let testTicketID = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["SBSNTicketID"] as? String {
                await attach(ticketID: testTicketID, restoring: testTicketID == activeTicketID)
            } else if let ticketID = activeTicketID {
                await attach(ticketID: ticketID, restoring: true)
            }
            await restoreGalleries()
            await refreshPublishedAt(of: publishedGalleries.map(\.ticketID))
            await launchPublisher.flushPendingTurnOff(uid: uid)
            if UserDefaults.standard.bool(forKey: Self.availableKey) {
                // 지난번에 켜 둔 "촬영 가능"을 이어 간다. 위치가 오면 출시 발행기가 다시 발행한다.
                isAvailable = true
                location.start()
                // 출시 공개 위치는 저장한 세션으로 발행만 해서 소유권을 확인한다(켜기를 다시 보내지 않는다, 격자 규격).
                if !launchPublisher.resume(uid: uid) {
                    setAvailable(false)
                }
            }
        } catch {
            errorMessage = "로그인하지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 티켓을 지켜보기 시작한다. 복원이면 로컬 폴더로 전달 엔진도 되살린다.
    /// 매칭은 알림으로만 안다(D063, presence 리스너는 지웠다). 알림과 탭이 같은 티켓을 거의 동시에 넘겨도 한 번만 붙는다.
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
            detachTicket()
        case .cancelled:
            detachTicket()
            if record.cancelledBy == record.customerUid {
                announceCancellation(record)
            }
        }
        if previous?.phase != record.phase {
            // 단계가 바뀌면 티켓 안 위치를 다음 위치부터 바로 보내도록 발행 기록을 지운다.
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
        // 공개 시각은 서버 값을 쓴다. 아직 모르면 기기 시각을 임시로 두고 바로 서버에서 다시 읽어 바꾼다
        // (기기 시계가 어긋나면 내역 목록과 상세의 공개 시각이 달라 보였다).
        let serverPublishedAt = model.serverPublishedAt
        let record = PublishedGallery(ticketID: model.ticketID, publishedAt: serverPublishedAt ?? Date(),
                                      endedAt: model.ticket.endedAt, photoCount: model.photos.count)
        publishedGalleries.removeAll { $0.ticketID == record.ticketID }
        publishedGalleries.append(record)
        savePublishedGalleries()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderID(model.ticketID)])
        galleries[model.ticketID] = nil
        savePendingGalleries()
        model.deleteLocalFiles()
        if serverPublishedAt == nil {
            Task { await refreshPublishedAt(of: [model.ticketID]) }
        }
    }

    /// 서버의 공개 시각으로 내역 기록을 맞춘다. 화면은 서버 값을 우선한다(상세 화면이 읽은 값도 여기로 넘긴다).
    func applyServerPublishedAt(_ date: Date, for ticketID: String) {
        guard let index = publishedGalleries.firstIndex(where: { $0.ticketID == ticketID }),
              publishedGalleries[index].publishedAt != date
        else { return }
        publishedGalleries[index].publishedAt = date
        savePublishedGalleries()
    }

    /// 내역 기록의 공개 시각을 서버에서 다시 읽는다. 읽지 못하면(오프라인 등) 다음 기회에 맞춘다.
    private func refreshPublishedAt(of ticketIDs: [String]) async {
        for ticketID in ticketIDs {
            if let publishedAt = try? await TicketService.fetchTicket(ticketID)?.galleryPublishedAt {
                applyServerPublishedAt(publishedAt, for: ticketID)
            }
        }
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
        ticket == nil && uid != nil
    }

    /// "촬영 가능"을 켜고 끈다. 켜면 위치·알림 권한을 묻고, 출시 발행기가 위치가 오는 대로 공개 위치를 발행한다.
    func setAvailable(_ available: Bool) {
        guard let uid else { return }
        if available {
            guard ticket == nil else {
                errorMessage = "진행 중인 촬영이 있습니다. 촬영을 끝내면 다시 켤 수 있습니다."
                return
            }
            isAvailable = true
            UserDefaults.standard.set(true, forKey: Self.availableKey)
            errorMessage = nil
            location.start()
            requestNotificationAuthorizationIfNeeded()
            // 출시 1단계 공개 위치(D059): 켜는 순간 새 세션으로 소유권을 가져오고 60초마다 표시점을 발행한다.
            launchPublisher.turnOn(uid: uid)
        } else {
            isAvailable = false
            UserDefaults.standard.set(false, forKey: Self.availableKey)
            if ticket == nil {
                location.stop()
            }
            Task { await launchPublisher.turnOff(uid: uid) }
        }
    }

    /// 위치는 10m 움직여야 새로 오므로, 한자리에 서 있어도 살아 있음을 알리게 15초마다 마지막 위치로 발행 여부를 다시 본다.
    /// 백그라운드 위치 수신이 켜져 있는 동안은 앱이 멈추지 않아 이 반복도 계속 돈다.
    private func startHeartbeat() {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(LocationSample.meetupPublishInterval))
                guard let self else { return }
                if location.isTracking, let point = location.latest {
                    handleLocation(point)
                }
            }
        }
    }

    /// 티켓 안 만나기 위치 공유. 대기 중 공개 위치는 출시 발행기가 60초마다 `location.latest`로 따로 보낸다.
    private func handleLocation(_ point: GeoPoint) {
        // 매칭 뒤 만나기 전까지만: 만나야 하므로 자주, 정확하게. 촬영이 시작되면 보내지 않는다.
        guard let ticket, ticket.phase.isActive, ticket.phase != .shooting,
              shouldPublish(point, minimumDistance: 10, minimumInterval: LocationSample.meetupPublishInterval) else { return }
        markPublished(point)
        Task {
            try? await TicketLocationService.publish(ticketId: ticket.id, uid: ticket.photographerUid, point: point)
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
    /// 저장된 로그인이 그사이 서버에서 무효가 됐는지도 본다(다른 기기·웹에서 계정 삭제 등).
    private func didBecomeActive() {
        for model in galleries.values {
            model.retryFailedUploads()
        }
        uploadQueue.signal()
        Task { await revalidateAccount() }
    }

    /// 저장된 로그인이 서버에서 무효면(지워짐·막힘·갱신 토큰 폐기) 새 익명 계정으로 바꾼다. 로그인 관문이 다시 뜬다(총괄 공통 기준).
    /// 앱 시작 때의 확인은 `Backend.signedInUserID()`가 한다.
    private func revalidateAccount() async {
        guard uid != nil, !isRestoring else { return }
        guard !(await Backend.validateSession()) else { return }
        Logger(subsystem: "com.ScienceFiction.sbsnPhotographer", category: "account")
            .notice("저장된 로그인이 무효라 새 익명 계정으로 바꿈")
        UserDefaults.standard.removeObject(forKey: "SBSNLaunchNickname")
        await resetAnonymousAccount()
    }

    // MARK: - 계정 정리·디버그

    /// 출시 계정의 로그아웃·계정 삭제 뒤 새 익명 계정으로 바꾼다(로그인 화면이 다시 뜬다).
    /// 출시 로그인 시험(`LaunchAuthProbeSection`)의 로그아웃도 쓴다.
    func resetAnonymousAccount() async {
        // 공개 위치를 먼저 끈다(로그아웃 뒤에는 이 계정으로 끄기를 보낼 수 없다, 격자 규격).
        await launchPublisher.turnOff(uid: uid)
        ticketTask?.cancel()
        ticket = nil
        isAvailable = false
        location.stop()
        UserDefaults.standard.removeObject(forKey: Self.activeTicketKey)
        UserDefaults.standard.set(false, forKey: Self.availableKey)
        do {
            try await Backend.signOut()
            let uid = try await Backend.signedInUserID()
            self.uid = uid
            account = AccountService.current
            errorMessage = nil
        } catch {
            errorMessage = "계정을 다시 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    func clearLocalTicket() {
        detachTicket()
    }

    // MARK: - 출시 계정(D059)

    /// 로그인 화면에서 로그인한 뒤. 익명 계정에 연결했으면 uid가 같고, 이미 있던 계정으로 로그인했으면 바뀐다.
    /// 닉네임은 로그인 화면이 `SBSNLaunchNickname`에 저장하고, 지도에 보이는 이름은 서버 닉네임이다(L06). 여기서는 쓰지 않는다.
    func accountDidChange(nickname: String) async {
        account = AccountService.current
        guard let current = account?.uid, current != uid else { return }
        await launchPublisher.turnOff(uid: uid)
        ticketTask?.cancel()
        ticket = nil
        isAvailable = false
        location.stop()
        UserDefaults.standard.removeObject(forKey: Self.activeTicketKey)
        UserDefaults.standard.set(false, forKey: Self.availableKey)
        uid = current
    }

    #if DEBUG
    /// 시험 정리: 맥에서 넣은 목록(`Documents/DeleteTickets.txt`, 한 줄에 티켓 폴더 이름 하나)의 폴더만 지운다.
    /// 기기 파일은 devicectl로 지울 수 없어 앱이 지운다. 진행 중 티켓과 공개 대기 티켓은 건너뛰고, 끝나면 목록 파일도 지운다.
    func deleteListedTicketFolders() -> String {
        let list = URL.documentsDirectory.appending(path: "DeleteTickets.txt")
        guard let text = try? String(contentsOf: list, encoding: .utf8) else { return "목록 파일 없음" }
        let names = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let protected = Set(galleries.keys).union([activeTicketID, ticket?.id].compactMap { $0 })
        var deleted = 0, missing = 0, skipped = 0
        for name in names {
            guard !name.contains("/"), !name.hasPrefix("."), !protected.contains(name) else {
                skipped += 1
                continue
            }
            let folder = CuratedDeliveryModel.directory(for: name)
            guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else {
                missing += 1
                continue
            }
            do {
                try FileManager.default.removeItem(at: folder)
                deleted += 1
            } catch {
                skipped += 1
            }
        }
        try? FileManager.default.removeItem(at: list)
        let root = URL.applicationSupportDirectory.appending(path: "Tickets", directoryHint: .isDirectory)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)))?.count ?? 0
        return "목록 \(names.count)개: 지움 \(deleted), 없음 \(missing), 건너뜀 \(skipped), 남은 폴더 \(left)"
    }

    /// 서버 없이 고르기 화면을 시험한다(가져오기·검사·렌더·화면 상태). 가짜 끝난 티켓이라 업로드는 실패로 끝나고, 공개 대기 목록에 저장하지 않는다.
    func openDebugGallery() {
        let now = Date()
        let nickname = UserDefaults.standard.string(forKey: "SBSNLaunchNickname") ?? ""
        let record = TicketRecord(id: "debug-\(UUID().uuidString.prefix(8).lowercased())", customerUid: "debug-customer",
                                  photographerUid: uid ?? "debug-photographer", photographerDisplayName: nickname.isEmpty ? "작가" : nickname,
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
    /// 서버의 공개 시각. 공개 직후 서버 값을 아직 모를 때만 잠깐 기기 시각이다.
    var publishedAt: Date
    let endedAt: Date?
    let photoCount: Int

    var id: String { ticketID }
    var purchaseClosesAt: Date { publishedAt.addingTimeInterval(PhotoCuration.purchaseWindow) }
}
