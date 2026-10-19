//
//  CameraTransferTestModel.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import Foundation
import ImageIO
import Observation
import SBSNBackend
import SBSNCameraTransfer
import UIKit

/// 카메라의 FTP 자동 전송을 실기기에서 검증하는 화면의 모델.
///
/// 받은 파일은 임시 촬영 티켓 폴더(`Application Support/Tickets/<티켓 ID>/originals`)에 모으고,
/// 같은 티켓 폴더에 FTP 로그(`session-log.txt`), 수신 기록(`received.csv`), 업로드 기록(`uploads.csv`)을 남긴다.
///
/// 업로드 순서: 사진을 받으면 미리보기(긴 변 2048px, 수백 KB)를 바로 만들어 올리고, 원본(약 20MB)은
/// 대기열에 넣어 한 장씩 올린다. LTE 업로드에서 원본은 장당 수십 초가 걸리므로, 원본끼리 동시에 올려
/// 미리보기 대역폭을 빼앗지 않게 하려는 것이다.
@Observable
final class CameraTransferTestModel {
    nonisolated struct ReceivedPhoto: Identifiable, Sendable {
        enum UploadState: Sendable {
            case waiting
            case uploading
            case uploaded(duration: TimeInterval)
            case failed(String)

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
        var original: UploadState = .waiting

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

    var previewUploadedCount: Int { photos.filter(\.preview.isUploaded).count }
    var originalUploadedCount: Int { photos.filter(\.original.isUploaded).count }
    var failedUploadCount: Int { photos.filter { $0.preview.isFailed || $0.original.isFailed }.count }

    private var server: FTPServer?
    private var isSuspendedForBackground = false
    private let uploader: TicketPhotoUploader
    private var originalQueue: [UUID] = []
    private var isUploadingOriginal = false
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
    }

    func start() {
        guard server == nil else { return }
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
            appendLog("server started: ticket \(ticketID), port \(Self.port)")
        } catch {
            errorMessage = "FTP 서버를 시작하지 못했습니다: \(error.localizedDescription)"
        }
        refreshAddresses()
    }

    func stop() {
        exitShootingMode()
        server?.stop()
        server = nil
        isRunning = false
        keepsScreenAwake = false
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

    private func appendLog(_ line: String) {
        let stamped = "\(Self.timestampFormatter.string(from: Date())) \(line)"
        logLines.append(LogLine(id: nextLogID, text: stamped))
        nextLogID += 1
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
        appendToFile(named: "session-log.txt", line: stamped)
    }

    private func append(_ photo: ReceivedPhoto) {
        photos.append(photo)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fields = [
            photo.relativePath,
            String(photo.byteCount),
            String(format: "%.3f", photo.transferDuration),
            iso.string(from: photo.receivedAt),
            photo.capturedAt.map(iso.string(from:)) ?? "",
            photo.shotToReceiveLatency.map { String(format: "%.3f", $0) } ?? "",
        ]
        appendToFile(named: "received.csv", line: fields.joined(separator: ","))
        uploadPreview(of: photo)
    }

    /// 미리보기를 만들어 바로 올린다. 성공 여부와 상관없이 끝나면 원본을 대기열에 넣는다.
    private func uploadPreview(of photo: ReceivedPhoto) {
        updatePhoto(photo.id) { $0.preview = .uploading }
        let sourceURL = photo.fileURL
        let fileName = sourceURL.lastPathComponent
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
                let upload = try await uploader.uploadPreview(fileAt: previewURL, originalFileName: fileName, capturedAt: photo.capturedAt)
                updatePhoto(photo.id) { $0.preview = .uploaded(duration: upload.duration) }
                recordUpload(kind: "preview", photo: photo, upload: upload, renderDuration: renderDuration)
            } catch {
                updatePhoto(photo.id) { $0.preview = .failed(error.localizedDescription) }
                appendLog("preview failed: \(fileName): \(error)")
            }
            enqueueOriginalIfNeeded(photo.id)
        }
    }

    private func enqueueOriginalIfNeeded(_ id: UUID) {
        guard let photo = photos.first(where: { $0.id == id }),
              case .waiting = photo.original,
              !originalQueue.contains(id)
        else { return }
        originalQueue.append(id)
        uploadNextOriginal()
    }

    /// 원본은 한 번에 한 장만 올린다.
    private func uploadNextOriginal() {
        guard !isUploadingOriginal, !originalQueue.isEmpty else { return }
        let id = originalQueue.removeFirst()
        guard let photo = photos.first(where: { $0.id == id }) else { return uploadNextOriginal() }
        isUploadingOriginal = true
        updatePhoto(id) { $0.original = .uploading }
        Task {
            do {
                let upload = try await uploader.uploadOriginal(fileAt: photo.fileURL)
                updatePhoto(id) { $0.original = .uploaded(duration: upload.duration) }
                recordUpload(kind: "original", photo: photo, upload: upload, renderDuration: nil)
            } catch {
                updatePhoto(id) { $0.original = .failed(error.localizedDescription) }
                appendLog("original failed: \(photo.relativePath): \(error)")
            }
            isUploadingOriginal = false
            uploadNextOriginal()
        }
    }

    func retryFailedUploads() {
        for photo in photos {
            if photo.preview.isFailed {
                uploadPreview(of: photo)
            }
            if photo.original.isFailed {
                updatePhoto(photo.id) { $0.original = .waiting }
                enqueueOriginalIfNeeded(photo.id)
            }
        }
    }

    private func recordUpload(kind: String, photo: ReceivedPhoto, upload: TicketPhotoUploader.Upload, renderDuration: TimeInterval?) {
        let receivedToStored = Date().timeIntervalSince(photo.receivedAt)
        appendLog("\(kind) stored: \(upload.storagePath) (\(upload.byteCount / 1000)KB, \(String(format: "%.2f", upload.duration))s)")
        // 종류, 파일, 바이트, 업로드 초, 앱 수신부터 서버 저장까지 초, 미리보기 생성 초
        appendToFile(named: "uploads.csv", line: [
            kind,
            photo.relativePath,
            String(upload.byteCount),
            String(format: "%.3f", upload.duration),
            String(format: "%.3f", receivedToStored),
            renderDuration.map { String(format: "%.3f", $0) } ?? "",
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
