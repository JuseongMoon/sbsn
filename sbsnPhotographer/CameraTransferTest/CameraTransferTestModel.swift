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

/// 촬영 티켓 하나의 카메라 FTP 수신과 고객 전달(업로드) 엔진. 화면이 아니라 `PhotographerSession`이 소유한다.
///
/// 받은 파일은 촬영 티켓 폴더(`Application Support/Tickets/<티켓 ID>/originals`)에 모으고,
/// 같은 티켓 폴더에 FTP 로그(`session-log.txt`), 수신 기록(`received.csv`), 업로드 기록(`uploads.csv`)을 남긴다.
/// 앱을 다시 켜면 이 폴더와 서버의 사진 문서로 상태를 복원한다(`restore`).
///
/// 전달 흐름(장당 구매):
/// 1. 사진을 받으면 저화질·워터마크 미리보기(긴 변 1024px, 백수십 KB)를 바로 만들어 올린다.
/// 2. 남는 대역으로 큰 파일을 `DeliveryPlanner` 순서대로 올린다: 구매한 사진의 고화질본 → 찜한 사진의 고화질본
///    → 구매한 사진의 원본(와이파이일 때만) → 나머지 고화질본(마지막 사진을 받은 뒤 정한 시간까지만 미리 올림).
/// 3. 찜·구매는 Firestore 사진 문서를 지켜보다가 바뀌는 즉시 순서에 반영한다.
///    앱이 백그라운드에 있을 때 들어온 구매는 서버 함수가 보내는 원격 알림으로 앱을 깨워 반영한다.
///    백그라운드 업로드가 끝나 iOS가 앱을 잠깐 깨울 때도 서버에서 찜·구매를 다시 읽는다.
/// 4. 실패한 업로드는 앱이 앞으로 오거나 인터넷이 돌아오면 자동으로 다시 올린다.
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
    /// 인터넷이 끊겼다 돌아오면 실패한 업로드를 다시 올린다.
    private(set) var isNetworkAvailable = true
    /// 실패 뒤 다시 올리기까지 기다리는 시간. 실패할수록 늘리고(최대 30초) 성공하면 되돌린다.
    private var retryDelay: TimeInterval = 5
    private var retryTask: Task<Void, Never>?
    /// 앱을 다시 켜 복원한 사진. 고화질본을 올리기 전에 서버에 이미 있는지 확인한다(업로드 뒤 문서를 쓰기 전에 멈춘 경우).
    private var restoredFileNames: Set<String> = []
    /// 전달이 끝나 세션이 놓은 모델. 진행 중이던 작업이 끝나도 새 업로드를 시작하지 않는다.
    private var isStopped = false

    /// 티켓 폴더가 이미 있는지(앱을 다시 켰을 때 복원할 수 있는지)
    static func hasLocalFiles(ticketID: String) -> Bool {
        FileManager.default.fileExists(atPath: directory(for: ticketID).path(percentEncoded: false))
    }

    static func directory(for ticketID: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: "Tickets", directoryHint: .isDirectory)
            .appending(path: ticketID, directoryHint: .isDirectory)
    }

    /// 티켓은 고객이 작가를 확정할 때 서버에 생긴다. 작가 앱은 그 ID와 고객 uid를 받아 쓴다.
    init(ticketID: String, customerUID: String) {
        self.ticketID = ticketID
        ticketDirectory = Self.directory(for: ticketID)
        uploader = TicketPhotoUploader(ticketID: ticketID, customerUID: customerUID)
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
    }

    /// 카메라 수신만 멈춘다(촬영 종료). 찜·구매 반영과 업로드는 계속된다.
    func stopReceiving() {
        exitShootingMode()
        server?.stop()
        server = nil
        isRunning = false
        isSuspendedForBackground = false
        keepsScreenAwake = false
        appendLog("server stopped: shooting ended")
    }

    /// 전부 멈춘다(전달까지 끝났거나 티켓이 취소됐을 때).
    func stop() {
        isStopped = true
        stopReceiving()
        demandTask?.cancel()
        demandTask = nil
        retryTask?.cancel()
        retryTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        appendLog("model stopped")
    }

    /// 아직 고객에게 넘길 것이 남았는지. 세션은 이것이 false가 된 뒤에야 티켓을 놓는다.
    /// 촬영이 끝난 뒤에는 고화질본이 올라간 사진만 살 수 있으므로, 미리 올리기 시간 안이면 남은 고화질본도 마저 올린다.
    var hasPendingDeliveries: Bool {
        activeLargeUploads > 0
            || photos.contains { $0.isPurchased && !$0.fullResolution.isUploaded }
            || (isPrefetchOpen && photos.contains { $0.isReadyForLargeUploads && !$0.fullResolution.isUploaded })
    }

    /// 큰 파일 업로드가 하나 끝날 때마다 부른다. 세션이 전달이 다 끝났는지 확인하는 데 쓴다.
    @ObservationIgnored var onLargeUploadFinished: (() -> Void)?

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
        retryFailedUploads()
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
            let isAvailable = path.status == .satisfied
            Task { @MainActor in self?.updateNetwork(isExpensive: isExpensive, isAvailable: isAvailable) }
        }
        monitor.start(queue: DispatchQueue(label: "sbsn.path-monitor"))
        pathMonitor = monitor
    }

    /// 핫스팟을 켠 작가 폰은 셀룰러가 끊겨도 카메라 수신은 계속되므로, 인터넷이 돌아올 때 실패한 업로드를 다시 올린다.
    private func updateNetwork(isExpensive: Bool, isAvailable: Bool) {
        if isAvailable != isNetworkAvailable {
            isNetworkAvailable = isAvailable
            appendLog("network: \(isAvailable ? "available" : "unavailable")")
            if isAvailable {
                retryFailedUploads()
            }
        }
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
        // 카메라가 같은 파일을 다시 보내면(전송 실패 뒤 재시도) 이미 올린 것을 다시 올리지 않는다.
        // 다른 사진이 같은 이름으로 오는 경우는 FTP 서버가 이름을 바꿔 받는다.
        if let existing = photos.first(where: { $0.relativePath == photo.relativePath }), existing.byteCount == photo.byteCount {
            appendLog("received again, ignored: \(photo.relativePath)")
            return
        }
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
                scheduleRetryAfterFailure()
            }
        }
    }

    // MARK: - 찜·구매

    /// 첫 미리보기가 올라간 뒤(고객이 볼 사진이 생긴 뒤) 찜·구매를 듣기 시작한다. 복원 때는 바로 시작한다.
    private func startListeningToDemandsIfNeeded() {
        guard demandTask == nil else { return }
        demandTask = Task {
            do {
                for try await demands in await uploader.photoDemands() {
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
    /// 서버에서 찜·구매를 다시 읽어 구매한 사진부터 올리고, 남은 시간 안에서 알림에 담긴 그 한 장의 고화질본이 끝나기를 기다린다.
    /// 고화질본은 putData로 깨어 있는 시간 안에 보낸다. 그 시간 안에 못 끝내면 앱이 멈추면서 같이 멈추고, 앱을 다시 열면 이어진다.
    /// 여러 장을 한꺼번에 사면 알림마다 한 장씩 처리되고, 나머지는 앱이 앞으로 올 때 이어진다.
    func handleWake(for purchase: PhotographerPush.Purchase) async -> Bool {
        appendLog("push: purchase \(purchase.fileName) in \(purchase.ticketID) (\(Self.applicationStateText))")
        guard purchase.ticketID == ticketID else { return false }
        if !(await refreshDemands(trigger: "push")),
           let index = photos.firstIndex(where: { $0.fileName == purchase.fileName }), !photos[index].isPurchased {
            // 서버를 못 읽으면 알림에 담긴 구매만이라도 반영한다.
            photos[index].isPurchased = true
            appendLog("demand (push payload): \(purchase.fileName) purchased true")
            scheduleLargeUploads()
        }
        // 알림 처리에 주어진 시간은 약 30초다. 3초 여유를 두고 그 안에서만 기다린다.
        let remaining = UIApplication.shared.applicationState == .background
            ? min(max(UIApplication.shared.backgroundTimeRemaining - 3, 5), 25)
            : 25
        let deadline = Date().addingTimeInterval(remaining)
        while Date() < deadline,
              let photo = photos.first(where: { $0.fileName == purchase.fileName }),
              photo.isPurchased, photo.fullResolution.isWaiting || photo.fullResolution.isUploading {
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
        guard !isStopped else { return }
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
            .appending(path: fileName + ".jpg")
        appendLog("fullres started: \(fileName) (\(reason), \(start.transport.rawValue), \(activeLargeUploads)/\(start.concurrency), \(start.appState))")
        let wasRestored = restoredFileNames.contains(fileName)
        Task {
            do {
                // 복원한 사진은 지난번에 업로드는 끝났는데 문서를 쓰기 전에 앱이 멈췄을 수 있다. 서버에 있으면 문서만 채운다.
                if wasRestored, await uploader.fullResolutionExists(originalFileName: fileName) {
                    let byteCount = (try? FileManager.default.attributesOfItem(atPath: fullResolutionURL.path(percentEncoded: false))[.size] as? Int) ?? 0
                    try await uploader.recordFullResolution(originalFileName: fileName, byteCount: byteCount)
                    updatePhoto(photo.id) { $0.fullResolution = .uploaded(duration: 0) }
                    finishLargeUpload(start: start, uploadedBytes: nil)
                    appendLog("fullres already on server, document recorded: \(fileName)")
                } else {
                    let renderStartedAt = Date()
                    try await Task.detached(priority: .userInitiated) {
                        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: sourceURL, to: fullResolutionURL)
                    }.value
                    let renderDuration = Date().timeIntervalSince(renderStartedAt)
                    let upload = try await withBackgroundTime(for: start.transport, name: "fullres \(fileName)") {
                        try await uploader.uploadFullResolution(fileAt: fullResolutionURL, originalFileName: fileName, transport: start.transport)
                    }
                    updatePhoto(photo.id) { $0.fullResolution = .uploaded(duration: upload.duration) }
                    finishLargeUpload(start: start, uploadedBytes: upload.byteCount)
                    recordUpload(kind: "fullres", photo: photo, upload: upload, start: start, renderDuration: renderDuration)
                }
                retryDelay = 5
            } catch {
                updatePhoto(photo.id) { $0.fullResolution = .failed(error.localizedDescription) }
                finishLargeUpload(start: start, uploadedBytes: nil)
                appendLog("fullres failed: \(fileName): \(error)")
                scheduleRetryAfterFailure()
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
                retryDelay = 5
            } catch {
                updatePhoto(photo.id) { $0.original = .failed(error.localizedDescription) }
                finishLargeUpload(start: start, uploadedBytes: nil)
                appendLog("original failed: \(photo.relativePath): \(error)")
                scheduleRetryAfterFailure()
            }
            await refreshDemandsIfInBackground()
            scheduleLargeUploads()
        }
    }

    /// 실패한 업로드를 잠시 뒤 다시 올린다. 인터넷이 없으면 돌아올 때(`updateNetwork`)까지 기다린다.
    private func scheduleRetryAfterFailure() {
        guard isNetworkAvailable, retryTask == nil else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        retryTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            retryTask = nil
            guard !Task.isCancelled else { return }
            appendLog("retrying failed uploads after \(Int(delay))s")
            retryFailedUploads()
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
        onLargeUploadFinished?()
    }

    func retryFailedUploads() {
        guard isNetworkAvailable, photos.contains(where: { $0.preview.isFailed || $0.fullResolution.isFailed || $0.original.isFailed }) else { return }
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

    // MARK: - 복원

    /// 앱을 다시 켰을 때 티켓 폴더의 원본과 서버의 사진 문서로 상태를 되살린다.
    /// `headless`(알림으로 백그라운드 실행)면 깨어 있는 시간이 짧으므로 썸네일·EXIF·미리보기 재업로드는 생략한다.
    /// 끝나면 찜·구매 리스너를 바로 붙이고 미완료 업로드를 이어 간다. 카메라 수신은 세션이 따로 시작한다.
    func restore(headless: Bool) async {
        let originals = ticketDirectory.appending(path: "originals", directoryHint: .isDirectory)
        let received = Self.readReceivedCSV(at: ticketDirectory.appending(path: "received.csv"))
        var restored: [ReceivedPhoto] = []
        for (url, values) in Self.scanOriginals(originals) {
            let byteCount = values.fileSize ?? 0
            let relative = url.standardizedFileURL.pathComponents.dropFirst(originals.standardizedFileURL.pathComponents.count).joined(separator: "/")
            let record = received[relative]
            let receivedAt = record?.receivedAt ?? values.contentModificationDate ?? Date()
            if headless {
                restored.append(ReceivedPhoto(fileURL: url, relativePath: relative, byteCount: byteCount,
                                              transferDuration: record?.transferDuration ?? 0, receivedAt: receivedAt,
                                              capturedAt: record?.capturedAt, thumbnail: nil))
            } else {
                var photo = Self.makeReceivedPhoto(from: FTPServer.ReceivedFile(url: url, byteCount: byteCount, duration: record?.transferDuration ?? 0),
                                                   root: originals)
                photo = ReceivedPhoto(fileURL: photo.fileURL, relativePath: photo.relativePath, byteCount: photo.byteCount,
                                      transferDuration: photo.transferDuration, receivedAt: receivedAt,
                                      capturedAt: record?.capturedAt ?? photo.capturedAt, thumbnail: photo.thumbnail)
                restored.append(photo)
            }
        }
        restored.sort { $0.receivedAt < $1.receivedAt }

        var records: [String: PhotoRecord] = [:]
        do {
            records = try await uploader.fetchPhotoRecords()
        } catch {
            appendLog("restore: photo records unavailable: \(error)")
        }
        for index in restored.indices {
            let fileName = restored[index].fileName
            guard let record = records[fileName] else { continue }
            if record.hasPreview {
                restored[index].preview = .uploaded(duration: 0)
                restored[index].isReadyForLargeUploads = true
            }
            if record.isFullResolutionReady { restored[index].fullResolution = .uploaded(duration: 0) }
            if record.originalUploadedAt != nil { restored[index].original = .uploaded(duration: 0) }
            restored[index].isFavorited = record.isFavorited
            restored[index].isPurchased = record.isPurchased
        }
        // 복원하는 사이 카메라에서 새로 받은 사진이 있으면 뒤에 붙여 둔다.
        let restoredPaths = Set(restored.map(\.relativePath))
        photos = restored + photos.filter { !restoredPaths.contains($0.relativePath) }
        restoredFileNames = Set(restored.map(\.fileName))
        // 마지막 수신 시각을 되살리지 않으면 미리 올리기 창이 다시 열려, 끝난 티켓의 고화질본을 전부 올리기 시작한다.
        lastReceivedAt = photos.map(\.receivedAt).max()
        appendLog("restored \(restored.count) photos (\(headless ? "headless" : "foreground")), records \(records.count), "
            + "purchased \(restored.filter(\.isPurchased).count), fullres pending \(restored.filter { $0.isPurchased && !$0.fullResolution.isUploaded }.count)")
        startMonitoringNetwork()
        startListeningToDemandsIfNeeded()
        if !headless {
            for photo in restored where !photo.preview.isUploaded {
                uploadPreview(of: photo)
            }
        }
        scheduleLargeUploads()
    }

    /// 받은 원본 파일과 크기·수정 시각. FTP가 받는 중인 임시 파일(`.<이름>.part`)은 사진이 아니므로 지운다.
    private nonisolated static func scanOriginals(_ originals: URL) -> [(URL, URLResourceValues)] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: originals, includingPropertiesForKeys: Array(keys)) else { return [] }
        var files: [(URL, URLResourceValues)] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent.hasPrefix(".") {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
                files.append((url, values))
            }
        }
        return files
    }

    private static func readReceivedCSV(at url: URL) -> [String: (receivedAt: Date, capturedAt: Date?, transferDuration: TimeInterval)] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: (receivedAt: Date, capturedAt: Date?, transferDuration: TimeInterval)] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4, let receivedAt = isoFormatter.date(from: fields[3]) else { continue }
            // 같은 파일이 다시 전송돼 두 줄이면 마지막 줄을 쓴다.
            result[fields[0]] = (receivedAt, fields.count > 4 ? isoFormatter.date(from: fields[4]) : nil, Double(fields[2]) ?? 0)
        }
        return result
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
