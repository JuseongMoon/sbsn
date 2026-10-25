//
//  CameraTransferTestModel.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import Foundation
import ImageIO
import Network
import Observation
import SBSNBackend
import SBSNCameraTransfer
import SBSNCore
import UIKit

/// 카메라의 FTP 자동 전송과 고객 전달 흐름을 실기기에서 검증하는 화면의 모델.
///
/// 받은 파일은 임시 촬영 티켓 폴더(`Application Support/Tickets/<티켓 ID>/originals`)에 모으고,
/// 같은 티켓 폴더에 FTP 로그(`session-log.txt`), 수신 기록(`received.csv`), 업로드 기록(`uploads.csv`)을 남긴다.
///
/// 전달 흐름(장당 구매):
/// 1. 사진을 받으면 저화질·워터마크 미리보기(긴 변 1024px, 백수십 KB)를 바로 만들어 올린다.
/// 2. 남는 대역으로 큰 파일을 `DeliveryPlanner` 순서대로 올린다: 구매한 사진의 고화질본 → 찜한 사진의 고화질본
///    → 구매한 사진의 원본(와이파이일 때만) → 나머지 고화질본(마지막 사진을 받은 뒤 정한 시간까지만 미리 올림).
/// 3. 찜·구매는 Firestore 사진 문서를 지켜보다가 바뀌는 즉시 순서에 반영한다.
///    앱이 백그라운드에 있을 때 들어온 구매는 서버 함수가 보내는 원격 알림으로 앱을 깨워 반영한다.
///    백그라운드 업로드가 끝나 iOS가 앱을 잠깐 깨울 때도 서버에서 찜·구매를 다시 읽는다.
/// LTE 실측 업로드가 3~4Mbps라 원본(약 20MB)을 전부 올리면 45장에 35~40분이 걸려서, 원본은 구매한 사진만 올린다.
@Observable
final class CameraTransferTestModel {
    nonisolated enum UploadMethod: String, CaseIterable, Identifiable, Sendable {
        case file
        case data
        /// 앱이 화면 앞에 있으면 putData, 백그라운드에서 시작하는 업로드는 putFile
        case automatic

        var id: Self { self }

        var title: String {
            switch self {
            case .file: "putFile"
            case .data: "putData"
            case .automatic: "자동"
            }
        }
    }

    nonisolated struct ReceivedPhoto: Identifiable, Sendable {
        enum UploadState: Sendable {
            case waiting
            case uploading
            case uploaded(duration: TimeInterval)
            case failed(String)

            var isWaiting: Bool {
                if case .waiting = self { true } else { false }
            }

            var isUploading: Bool {
                if case .uploading = self { true } else { false }
            }

            var isUploaded: Bool {
                if case .uploaded = self { true } else { false }
            }

            var isFailed: Bool {
                if case .failed = self { true } else { false }
            }
        }

        let id = UUID()
        let fileURL: URL
        let relativePath: String
        let byteCount: Int
        let transferDuration: TimeInterval
        let receivedAt: Date
        let capturedAt: Date?
        let thumbnail: UIImage?
        var preview: UploadState = .waiting
        var fullResolution: UploadState = .waiting
        /// 구매한 사진만 올린다. 구매 전에는 계속 대기다.
        var original: UploadState = .waiting
        /// 미리보기가 올라가 고객이 볼 수 있게 된 뒤에만 큰 파일을 올린다.
        var isReadyForLargeUploads = false
        var isFavorited = false
        var isPurchased = false

        var fileName: String { fileURL.lastPathComponent }

        /// 카메라 시계 기준 촬영 시각부터 앱 수신 완료까지 걸린 시간. 카메라 시계가 틀린 만큼 어긋난다.
        var shotToReceiveLatency: TimeInterval? { capturedAt.map { receivedAt.timeIntervalSince($0) } }
    }

    nonisolated struct InterfaceAddress: Identifiable, Hashable, Sendable {
        let name: String
        let address: String
        var id: String { name + address }
        /// iOS 개인용 핫스팟은 bridge 인터페이스로 잡힌다.
        var isLikelyHotspot: Bool { name.hasPrefix("bridge") }
    }

    struct LogLine: Identifiable {
        let id: Int
        let text: String
    }

    static let port: UInt16 = 2121
    static let user = "camera"
    static let password = "sbsn"

    let ticketID: String
    let ticketDirectory: URL
    private(set) var isRunning = false
    private(set) var addresses: [InterfaceAddress] = []
    private(set) var photos: [ReceivedPhoto] = []
    private(set) var logLines: [LogLine] = []
    private(set) var errorMessage: String?
    var keepsScreenAwake = false {
        didSet { updateIdleTimer() }
    }
    /// 촬영 모드: 화면 자동 잠금을 막고 근접 센서를 켠다. 주머니에 넣으면 화면만 꺼지고 앱은 화면 앞 상태로 남아 전송이 계속된다.
    private(set) var isShootingMode = false
    var uploadMethod = UploadMethod.file {
        didSet { appendLog("upload method: \(uploadMethod.rawValue)") }
    }
    /// 큰 파일(고화질본·원본)을 동시에 몇 개까지 올릴지. LTE 실측에서 동시 업로드는 합계 속도를 늘리지 못했다.
    var largeUploadConcurrency = 1 {
        didSet {
            appendLog("large upload concurrency: \(largeUploadConcurrency)")
            scheduleLargeUploads()
        }
    }
    /// 마지막 사진을 받은 뒤 찜·구매하지 않은 사진의 고화질본을 얼마 동안 미리 올릴지(분)
    var prefetchMinutes = 30 {
        didSet {
            appendLog("prefetch minutes: \(prefetchMinutes)")
            scheduleLargeUploads()
        }
    }
    /// 구매한 사진의 원본을 셀룰러(핫스팟)에서도 올릴지. 기본은 와이파이에서만 올린다.
    var uploadsOriginalsOnCellular = false {
        didSet {
            appendLog("originals on cellular: \(uploadsOriginalsOnCellular)")
            scheduleLargeUploads()
        }
    }
    /// 지금 앱의 인터넷 경로가 셀룰러처럼 비싼 망인지. 핫스팟을 켜면 아이폰 자신의 인터넷은 셀룰러다.
    private(set) var isOnExpensiveNetwork = true
    private(set) var lastReceivedAt: Date?
    /// 큰 파일을 하나라도 올리고 있던 시간과 그동안 올린 바이트. 사진이 띄엄띄엄 와서 쉬는 시간은 빼고 계산한다.
    private(set) var largeUploadedBytes = 0
    private(set) var largeBusyDurationAtLastUpload: TimeInterval = 0

    var previewUploadedCount: Int { photos.filter(\.preview.isUploaded).count }
    var fullResolutionUploadedCount: Int { photos.filter(\.fullResolution.isUploaded).count }
    var originalUploadedCount: Int { photos.filter(\.original.isUploaded).count }
    var failedUploadCount: Int {
        photos.filter { $0.preview.isFailed || $0.fullResolution.isFailed || $0.original.isFailed }.count
    }
    /// 큰 파일 처리량(바이트/초)
    var largeUploadThroughput: Double? {
        largeBusyDurationAtLastUpload > 0 ? Double(largeUploadedBytes) / largeBusyDurationAtLastUpload : nil
    }
    /// 이 시각이 지나면 찜·구매하지 않은 사진은 미리 올리지 않는다. 아직 받은 사진이 없으면 nil.
    var prefetchDeadline: Date? { lastReceivedAt?.addingTimeInterval(TimeInterval(prefetchMinutes * 60)) }
    var isPrefetchOpen: Bool { prefetchDeadline.map { Date() < $0 } ?? true }

    private var server: FTPServer?
    private var isSuspendedForBackground = false
    private let uploader: TicketPhotoUploader
    private var demandTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var activeLargeUploads = 0
    private var largeBusySince: Date?
    private var largeBusyAccumulated: TimeInterval = 0
    private var backgroundTasks: [UUID: UIBackgroundTaskIdentifier] = [:]
    private var nextLogID = 0
    private var brightnessBeforeShooting: CGFloat?

    init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        ticketID = "POC-" + formatter.string(from: Date())
        ticketDirectory = URL.applicationSupportDirectory
            .appending(path: "Tickets", directoryHint: .isDirectory)
            .appending(path: ticketID, directoryHint: .isDirectory)
        uploader = TicketPhotoUploader(ticketID: ticketID)
        // 맥에서 조건을 바꿔 가며 실증을 돌릴 때 실행 인자로 넘긴다(예: -SBSNPrefetchMinutes 2 -SBSNOriginalsOnCellular YES).
        let defaults = UserDefaults.standard
        if let method = defaults.string(forKey: "SBSNUploadMethod").flatMap(UploadMethod.init(rawValue:)) {
            uploadMethod = method
        }
        if (1...4).contains(defaults.integer(forKey: "SBSNLargeUploadConcurrency")) {
            largeUploadConcurrency = defaults.integer(forKey: "SBSNLargeUploadConcurrency")
        }
        // 0이면 미리 올리기를 끄고 찜·구매한 사진만 올린다. 화면에서는 1분부터 고를 수 있다.
        if let minutes = defaults.string(forKey: "SBSNPrefetchMinutes").flatMap(Int.init), (0...240).contains(minutes) {
            prefetchMinutes = minutes
        }
        uploadsOriginalsOnCellular = defaults.bool(forKey: "SBSNOriginalsOnCellular")
    }

    func start() {
        guard server == nil else { return }
        if UserDefaults.standard.bool(forKey: "SBSNKeepScreenAwake") {
            keepsScreenAwake = true
        }
        startMonitoringNetwork()
        let originals = ticketDirectory.appending(path: "originals", directoryHint: .isDirectory)
        let server = FTPServer(port: Self.port, rootDirectory: originals, credentials: (Self.user, Self.password))
        server.onLog = { [weak self] line in
            Task { @MainActor in self?.appendLog(line) }
        }
        server.onFileReceived = { [weak self] file in
            let photo = Self.makeReceivedPhoto(from: file, root: originals)
            Task { @MainActor in self?.append(photo) }
        }
        do {
            try server.start()
            self.server = server
            isRunning = true
            errorMessage = nil
            appendLog("server started: ticket \(ticketID), port \(Self.port), upload \(uploadMethod.rawValue) x\(largeUploadConcurrency), "
                + "prefetch \(prefetchMinutes)m, originals on cellular \(uploadsOriginalsOnCellular)")
        } catch {
            errorMessage = "FTP 서버를 시작하지 못했습니다: \(error.localizedDescription)"
        }
        refreshAddresses()
        PurchaseWakeRouter.shared.handler = { [weak self] purchase in
            await self?.handleWake(for: purchase) ?? false
        }
    }

    func stop() {
        PurchaseWakeRouter.shared.handler = nil
        exitShootingMode()
        server?.stop()
        server = nil
        isRunning = false
        keepsScreenAwake = false
        demandTask?.cancel()
        demandTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        appendLog("server stopped")
    }

    /// iOS는 백그라운드에 있는 앱의 수신 대기 소켓을 회수할 수 있다. 실기기에서 12분 백그라운드 뒤 서버가
    /// "수신 대기 중"으로 보이면서도 카메라 접속을 받지 못했다. 그래서 백그라운드로 갈 때 서버를 닫고,
    /// 다시 앞으로 오면 같은 촬영 티켓으로 새로 연다. 카메라는 다시 붙으면 못 보낸 사진을 자동으로 보낸다.
    func suspendForBackground() {
        guard server != nil else { return }
        server?.stop()
        server = nil
        isRunning = false
        isSuspendedForBackground = true
        appendLog("server suspended: app in background")
    }

    func resumeFromBackground() {
        guard isSuspendedForBackground else { return }
        isSuspendedForBackground = false
        appendLog("server resuming: app active")
        start()
    }

    func enterShootingMode() {
        guard !isShootingMode else { return }
        isShootingMode = true
        updateIdleTimer()
        UIDevice.current.isProximityMonitoringEnabled = true
        if let screen = currentScreen {
            brightnessBeforeShooting = screen.brightness
            screen.brightness = 0.1
        }
        appendLog("shooting mode on (proximity monitoring: \(UIDevice.current.isProximityMonitoringEnabled))")
    }

    func exitShootingMode() {
        guard isShootingMode else { return }
        isShootingMode = false
        updateIdleTimer()
        UIDevice.current.isProximityMonitoringEnabled = false
        if let brightness = brightnessBeforeShooting {
            currentScreen?.brightness = brightness
            brightnessBeforeShooting = nil
        }
        appendLog("shooting mode off")
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepsScreenAwake || isShootingMode
    }

    private var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    func refreshAddresses() {
        addresses = Self.currentIPv4Addresses()
    }

    func note(_ message: String) {
        appendLog(message)
    }

    private func startMonitoringNetwork() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isExpensive = path.isExpensive
            Task { @MainActor in self?.updateNetwork(isExpensive: isExpensive) }
        }
        monitor.start(queue: DispatchQueue(label: "sbsn.path-monitor"))
        pathMonitor = monitor
    }

    private func updateNetwork(isExpensive: Bool) {
        guard isExpensive != isOnExpensiveNetwork else { return }
        isOnExpensiveNetwork = isExpensive
        appendLog("network: \(isExpensive ? "expensive (cellular)" : "not expensive (wi-fi)")")
        scheduleLargeUploads()
    }

    private func appendLog(_ line: String) {
        let stamped = "\(Self.timestampFormatter.string(from: Date())) \(line)"
        logLines.append(LogLine(id: nextLogID, text: stamped))
        nextLogID += 1
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
        appendToFile(named: "session-log.txt", line: stamped)
    }

    private func append(_ photo: ReceivedPhoto) {
        photos.append(photo)
        lastReceivedAt = photo.receivedAt
        let fields = [
            photo.relativePath,
            String(photo.byteCount),
            String(format: "%.3f", photo.transferDuration),
            Self.isoFormatter.string(from: photo.receivedAt),
            photo.capturedAt.map(Self.isoFormatter.string(from:)) ?? "",
            photo.shotToReceiveLatency.map { String(format: "%.3f", $0) } ?? "",
        ]
        appendToFile(named: "received.csv", line: fields.joined(separator: ","))
        uploadPreview(of: photo)
    }

    // MARK: - 미리보기

    /// 저화질·워터마크 미리보기를 만들어 바로 올린다. 올라가면 그 사진의 큰 파일도 대기열에 들어간다.
    private func uploadPreview(of photo: ReceivedPhoto) {
        updatePhoto(photo.id) { $0.preview = .uploading }
        let sourceURL = photo.fileURL
        let fileName = photo.fileName
        let previewURL = ticketDirectory
            .appending(path: "previews", directoryHint: .isDirectory)
            .appending(path: fileName + ".jpg")
        Task {
            let renderStartedAt = Date()
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PhotoPreviewRenderer.renderJPEG(from: sourceURL, to: previewURL)
                }.value
                let renderDuration = Date().timeIntervalSince(renderStartedAt)
                let start = UploadStart(transport: transportForNewUpload(), concurrency: largeUploadConcurrency, reason: "preview")
                let upload = try await withBackgroundTime(for: start.transport, name: "preview \(fileName)") {
                    try await uploader.uploadPreview(fileAt: previewURL, originalFileName: fileName, capturedAt: photo.capturedAt,
                                                     transport: start.transport)
                }
                updatePhoto(photo.id) {
                    $0.preview = .uploaded(duration: upload.duration)
                    $0.isReadyForLargeUploads = true
                }
                recordUpload(kind: "preview", photo: photo, upload: upload, start: start, renderDuration: renderDuration)
                startListeningToDemandsIfNeeded()
                scheduleLargeUploads()
            } catch {
                updatePhoto(photo.id) { $0.preview = .failed(error.localizedDescription) }
                appendLog("preview failed: \(fileName): \(error)")
            }
        }
    }

    // MARK: - 찜·구매

    /// 티켓 문서는 첫 업로드 때 만들어지므로, 첫 미리보기가 올라간 뒤 찜·구매를 듣기 시작한다.
    private func startListeningToDemandsIfNeeded() {
        guard demandTask == nil else { return }
        demandTask = Task {
            do {
                for try await demands in try await uploader.photoDemands() {
                    apply(demands, source: "listener")
                }
            } catch {
                appendLog("demand listener failed: \(error)")
            }
            demandTask = nil
        }
    }

    /// `source`는 기록용이다: listener(실시간 리스너), push(구매 알림을 받고 다시 읽음), background wake(백그라운드 업로드가 끝나 깨어나 다시 읽음).
    private func apply(_ demands: [String: TicketPhotoUploader.PhotoDemand], source: String) {
        var changed = false
        for index in photos.indices {
            guard let demand = demands[photos[index].fileName] else { continue }
            let isFavorited = demand.favoritedAt != nil
            let isPurchased = demand.purchasedAt != nil
            guard isFavorited != photos[index].isFavorited || isPurchased != photos[index].isPurchased else { continue }
            photos[index].isFavorited = isFavorited
            photos[index].isPurchased = isPurchased
            appendLog("demand (\(source)): \(photos[index].fileName) favorited \(isFavorited), purchased \(isPurchased)")
            changed = true
        }
        if changed {
            scheduleLargeUploads()
        }
    }

    /// 서버에서 찜·구매를 한 번 읽어 반영한다. 읽지 못했으면 false.
    @discardableResult
    private func refreshDemands(trigger: String) async -> Bool {
        do {
            apply(try await uploader.fetchPhotoDemands(), source: trigger)
            return true
        } catch {
            appendLog("demand refresh failed (\(trigger)): \(error)")
            return false
        }
    }

    /// 구매 알림을 받았을 때. 앱이 백그라운드에 있었으면 iOS가 잠깐(약 30초) 깨운 상태다.
    /// 서버에서 찜·구매를 다시 읽어 구매한 사진부터 올리고, 그 시간 안에서 구매한 사진의 고화질본이 끝나기를 기다린다.
    /// 고화질본은 putData로 깨어 있는 시간 안에 보낸다. 그 시간 안에 못 끝내면 앱이 멈추면서 같이 멈추고, 앱을 다시 열면 이어진다.
    private func handleWake(for purchase: PhotographerPush.Purchase) async -> Bool {
        appendLog("push: purchase \(purchase.fileName) in \(purchase.ticketID) (\(Self.applicationStateText))")
        guard purchase.ticketID == ticketID else { return false }
        if !(await refreshDemands(trigger: "push")),
           let index = photos.firstIndex(where: { $0.fileName == purchase.fileName }), !photos[index].isPurchased {
            // 서버를 못 읽으면 알림에 담긴 구매만이라도 반영한다.
            photos[index].isPurchased = true
            appendLog("demand (push payload): \(purchase.fileName) purchased true")
            scheduleLargeUploads()
        }
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline,
              photos.contains(where: { $0.isPurchased && ($0.fullResolution.isWaiting || $0.fullResolution.isUploading) }) {
            try? await Task.sleep(for: .milliseconds(500))
        }
        return true
    }

    /// 백그라운드 업로드가 끝나 iOS가 앱을 잠깐 깨웠을 때, 실시간 리스너가 그사이 들어온 구매를 놓쳤을 수 있어 서버에서 다시 읽는다.
    /// 읽는 도중 앱이 멈추면 다음 업로드 시작이 늦어지므로 시간을 조금 더 받는다.
    private func refreshDemandsIfInBackground() async {
        guard UIApplication.shared.applicationState == .background else { return }
        await withExtraBackgroundTime(name: "demand refresh") {
            await refreshDemands(trigger: "background wake")
        }
    }

    // MARK: - 큰 파일(고화질본·원본)

    /// 빈자리가 있는 만큼 `DeliveryPlanner`가 고른 순서대로 큰 파일 업로드를 시작한다.
    private func scheduleLargeUploads() {
        let conditions = DeliveryPlanner.Conditions(
            isPrefetchOpen: isPrefetchOpen,
            allowsOriginals: !isOnExpensiveNetwork || uploadsOriginalsOnCellular
        )
        while activeLargeUploads < largeUploadConcurrency {
            let candidates = photos.filter(\.isReadyForLargeUploads).flatMap { photo in
                var pending: [DeliveryPlanner.Candidate] = []
                if photo.fullResolution.isWaiting {
                    pending.append(.init(fileName: photo.fileName, kind: .fullResolution, receivedAt: photo.receivedAt,
                                         isFavorited: photo.isFavorited, isPurchased: photo.isPurchased))
                }
                if photo.original.isWaiting {
                    pending.append(.init(fileName: photo.fileName, kind: .original, receivedAt: photo.receivedAt,
                                         isFavorited: photo.isFavorited, isPurchased: photo.isPurchased))
                }
                return pending
            }
            guard let next = DeliveryPlanner.next(from: candidates, under: conditions),
                  let photo = photos.first(where: { $0.fileName == next.fileName })
            else { return }
            switch next.kind {
            case .fullResolution: uploadFullResolution(of: photo)
            case .original: uploadOriginal(of: photo)
            }
        }
    }

    private func uploadFullResolution(of photo: ReceivedPhoto) {
        let reason = photo.isPurchased ? "purchased" : photo.isFavorited ? "favorited" : "prefetch"
        let start = beginLargeUpload(reason: reason, sendsNow: photo.isPurchased)
        updatePhoto(photo.id) { $0.fullResolution = .uploading }
        let sourceURL = photo.fileURL
        let fileName = photo.fileName
        let fullResolutionURL = ticketDirectory
            .appending(path: "fullres", directoryHint: .isDirectory)
            .appending(path: fileName + ".heic")
        appendLog("fullres started: \(fileName) (\(reason), \(start.transport.rawValue), \(activeLargeUploads)/\(start.concurrency), \(start.appState))")
        Task {
            do {
                let renderStartedAt = Date()
                try await Task.detached(priority: .userInitiated) {
                    try PhotoPreviewRenderer.renderFullResolutionHEIC(from: sourceURL, to: fullResolutionURL)
                }.value
                let renderDuration = Date().timeIntervalSince(renderStartedAt)
                let upload = try await withBackgroundTime(for: start.transport, name: "fullres \(fileName)") {
                    try await uploader.uploadFullResolution(fileAt: fullResolutionURL, originalFileName: fileName, transport: start.transport)
                }
                updatePhoto(photo.id) { $0.fullResolution = .uploaded(duration: upload.duration) }
                finishLargeUpload(start: start, uploadedBytes: upload.byteCount)
                recordUpload(kind: "fullres", photo: photo, upload: upload, start: start, renderDuration: renderDuration)
            } catch {
                updatePhoto(photo.id) { $0.fullResolution = .failed(error.localizedDescription) }
                finishLargeUpload(start: start, uploadedBytes: nil)
                appendLog("fullres failed: \(fileName): \(error)")
            }
            await refreshDemandsIfInBackground()
            scheduleLargeUploads()
        }
    }

    private func uploadOriginal(of photo: ReceivedPhoto) {
        let start = beginLargeUpload(reason: "purchased")
        updatePhoto(photo.id) { $0.original = .uploading }
        appendLog("original started: \(photo.relativePath) (\(start.transport.rawValue), \(activeLargeUploads)/\(start.concurrency), \(start.appState))")
        Task {
            do {
                let upload = try await withBackgroundTime(for: start.transport, name: "original \(photo.relativePath)") {
                    try await uploader.uploadOriginal(fileAt: photo.fileURL, transport: start.transport)
                }
                updatePhoto(photo.id) { $0.original = .uploaded(duration: upload.duration) }
                finishLargeUpload(start: start, uploadedBytes: upload.byteCount)
                recordUpload(kind: "original", photo: photo, upload: upload, start: start, renderDuration: nil)
            } catch {
                updatePhoto(photo.id) { $0.original = .failed(error.localizedDescription) }
                finishLargeUpload(start: start, uploadedBytes: nil)
                appendLog("original failed: \(photo.relativePath): \(error)")
            }
            await refreshDemandsIfInBackground()
            scheduleLargeUploads()
        }
    }

    private func beginLargeUpload(reason: String, sendsNow: Bool = false) -> UploadStart {
        let start = UploadStart(transport: transportForNewUpload(sendsNow: sendsNow), concurrency: largeUploadConcurrency, reason: reason)
        if activeLargeUploads == 0 {
            largeBusySince = start.startedAt
        }
        activeLargeUploads += 1
        return start
    }

    private func finishLargeUpload(start: UploadStart, uploadedBytes: Int?) {
        let now = Date()
        if let uploadedBytes {
            largeUploadedBytes += uploadedBytes
            largeBusyDurationAtLastUpload = largeBusyAccumulated + now.timeIntervalSince(largeBusySince ?? start.startedAt)
        }
        activeLargeUploads -= 1
        if activeLargeUploads == 0, let since = largeBusySince {
            largeBusyAccumulated += now.timeIntervalSince(since)
            largeBusySince = nil
        }
    }

    func retryFailedUploads() {
        for photo in photos {
            if photo.preview.isFailed {
                uploadPreview(of: photo)
            }
            updatePhoto(photo.id) {
                if $0.fullResolution.isFailed { $0.fullResolution = .waiting }
                if $0.original.isFailed { $0.original = .waiting }
            }
        }
        scheduleLargeUploads()
    }

    /// 업로드를 시작할 때의 조건. 측정 기록에 남긴다.
    private struct UploadStart {
        let transport: TicketPhotoUploader.Transport
        let concurrency: Int
        let appState: String
        /// preview, purchased, favorited, prefetch
        let reason: String
        let startedAt: Date

        init(transport: TicketPhotoUploader.Transport, concurrency: Int, reason: String) {
            self.transport = transport
            self.concurrency = concurrency
            self.reason = reason
            appState = CameraTransferTestModel.applicationStateText
            startedAt = Date()
        }
    }

    private static var applicationStateText: String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    /// sendsNow: 전송 방식 설정과 관계없이, 백그라운드면 지금 깨어 있는 시간 안에 putData로 보낸다.
    /// 백그라운드에서 새로 시작한 putFile 전송은 iOS가 재량으로 미뤄, 구매 알림으로 깨어나 시작한 고화질본(6.5MB)이
    /// 10분이 지나도 올라가지 않았다(2026-10-25 iP9, 셀룰러 핫스팟).
    private func transportForNewUpload(sendsNow: Bool = false) -> TicketPhotoUploader.Transport {
        if sendsNow && UIApplication.shared.applicationState == .background {
            return .data
        }
        return switch uploadMethod {
        case .file: .file
        case .data: .data
        case .automatic: UIApplication.shared.applicationState == .background ? .file : .data
        }
    }

    /// putData 전송은 앱이 멈추면 같이 멈춘다. 전송 중에 백그라운드로 가도 끝낼 수 있게 시스템에 시간을 조금 더 받는다.
    /// putFile은 iOS 백그라운드 전송이 따로 이어 가므로 받지 않는다(지난 실험과 같은 조건 유지).
    private func withBackgroundTime<T>(for transport: TicketPhotoUploader.Transport, name: String,
                                       _ operation: () async throws -> T) async throws -> T {
        guard transport == .data else { return try await operation() }
        return try await withExtraBackgroundTime(name: name, operation)
    }

    /// 앱이 백그라운드로 가거나 백그라운드에서 잠깐 깨어 있는 동안 작업을 끝낼 시간을 시스템에 조금 더 받는다(보통 30초 안팎).
    private func withExtraBackgroundTime<T>(name: String, _ operation: () async throws -> T) async rethrows -> T {
        let id = UUID()
        backgroundTasks[id] = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.appendLog("background time expired: \(name)")
            self?.endBackgroundTime(id)
        }
        defer { endBackgroundTime(id) }
        return try await operation()
    }

    private func endBackgroundTime(_ id: UUID) {
        guard let task = backgroundTasks.removeValue(forKey: id) else { return }
        UIApplication.shared.endBackgroundTask(task)
    }

    private func recordUpload(kind: String, photo: ReceivedPhoto, upload: TicketPhotoUploader.Upload, start: UploadStart,
                              renderDuration: TimeInterval?) {
        let finishedAt = Date()
        let receivedToStored = finishedAt.timeIntervalSince(photo.receivedAt)
        appendLog("\(kind) stored: \(upload.storagePath) (\(upload.byteCount / 1000)KB, \(String(format: "%.2f", upload.duration))s, \(start.transport.rawValue))")
        // 종류, 파일, 바이트, 업로드 초, 앱 수신부터 서버 저장까지 초, 파일 생성 초,
        // 전송 방식, 시작할 때 큰 파일 동시 업로드 설정, 시작할 때 앱 상태, 시작 시각, 끝 시각, Storage 전송 초, 올린 이유
        appendToFile(named: "uploads.csv", line: [
            kind,
            photo.relativePath,
            String(upload.byteCount),
            String(format: "%.3f", upload.duration),
            String(format: "%.3f", receivedToStored),
            renderDuration.map { String(format: "%.3f", $0) } ?? "",
            start.transport.rawValue,
            String(start.concurrency),
            start.appState,
            Self.isoFormatter.string(from: start.startedAt),
            Self.isoFormatter.string(from: finishedAt),
            String(format: "%.3f", upload.transferDuration),
            start.reason,
        ].joined(separator: ","))
    }

    private func updatePhoto(_ id: UUID, _ change: (inout ReceivedPhoto) -> Void) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        change(&photos[index])
    }

    private func appendToFile(named name: String, line: String) {
        let url = ticketDirectory.appending(path: name)
        do {
            try FileManager.default.createDirectory(at: ticketDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            errorMessage = "기록 파일을 쓰지 못했습니다: \(error.localizedDescription)"
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - 파일 분석 (FTP 서버 큐에서 호출)

    private nonisolated static func makeReceivedPhoto(from file: FTPServer.ReceivedFile, root: URL) -> ReceivedPhoto {
        let receivedAt = Date()
        var thumbnail: UIImage?
        var capturedAt: Date?
        if let source = CGImageSourceCreateWithURL(file.url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                thumbnail = UIImage(cgImage: image)
            }
            capturedAt = captureDate(from: source)
        }
        let rootComponents = root.standardizedFileURL.pathComponents
        let relative = file.url.standardizedFileURL.pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
        return ReceivedPhoto(
            fileURL: file.url,
            relativePath: relative.isEmpty ? file.url.lastPathComponent : relative,
            byteCount: file.byteCount,
            transferDuration: file.duration,
            receivedAt: receivedAt,
            capturedAt: capturedAt,
            thumbnail: thumbnail
        )
    }

    /// EXIF의 촬영 시각(DateTimeOriginal + SubsecTimeOriginal + OffsetTimeOriginal).
    private nonisolated static func captureDate(from source: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var text = original
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            text += offset
        } else {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.timeZone = .current
        }
        guard let date = formatter.date(from: text) else { return nil }
        if let subsec = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, let fraction = Double("0." + subsec) {
            return date.addingTimeInterval(fraction)
        }
        return date
    }

    private nonisolated static func currentIPv4Addresses() -> [InterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [InterfaceAddress] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard name != "lo0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            result.append(InterfaceAddress(name: name, address: String(decoding: host.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)))
        }
        return result.sorted { ($0.isLikelyHotspot ? 0 : 1, $0.name) < ($1.isLikelyHotspot ? 0 : 1, $1.name) }
    }
}
