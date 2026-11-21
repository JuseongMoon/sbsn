import CryptoKit
import Foundation
import ImageIO
import Network
import Observation
import SBSNBackend
import SBSNCameraTransfer
import SBSNCore
import SwiftUI
import UIKit

/// 공개 대기 티켓 하나의 선별 업로드 엔진(D036·D038, 설계 문서 2.3~2.5절). `PhotographerSession`이 티켓마다 하나씩 들고,
/// 업로드는 앱 전체 큐(`GalleryUploadQueue`)가 차례를 정한다.
///
/// 흐름: 작가가 고른 파일을 티켓 폴더(`Application Support/Tickets/<티켓>/originals/<사진 ID>.<확장자>`)로 복사하고 검사한다
/// → 미리보기(워터마크, 메타데이터 없음)와 고화질본(메타데이터 전부, D037)을 만든다 → 두 파일을 병렬로 올린다
/// → 고른 사진이 모두 올라가면 `publishGallery`로 한 번 공개한다(올리는 중이면 공개 예약).
/// 고른 순서·공개 예약은 `selection.json`에 두어 앱을 다시 켜도 이어 간다. 공개 뒤에는 찜·구매·전달만 보여 준다.
@Observable
@MainActor
final class CuratedDeliveryModel: Identifiable {
    enum Step: Equatable {
        case waiting
        case working
        case done
        case failed(String)

        var isDone: Bool { self == .done }
        var isFailed: Bool { if case .failed = self { true } else { false } }
    }

    struct Photo: Identifiable {
        /// 사진 ID(`^p[a-z0-9]{12}$`). 서버가 다른 파일로 보면(불일치·오래됨) 새 ID로 바꿔 다시 올린다.
        var id: String
        let fileExtension: String
        /// 원래 파일 이름(표시용, 없을 수 있다)
        let fileName: String?
        let capturedAt: Date?
        let width: Int
        let height: Int
        let assetIdentifier: String?
        let contentKey: String
        var thumbnail: UIImage?
        var isOutsideShootWindow = false
        /// 촬영 위치가 지워진 채 들어왔다(GPS 태그는 있는데 값이 0/0이거나 형식이 잘못됨, I008). 고화질본은 받은 그대로 옮긴다.
        var locationRemoved = false
        /// 미리보기·고화질본 파일을 이 기기에서 만들었는지
        var isRendered = false
        var preview = Step.waiting
        var fullres = Step.waiting
        /// 만들기 실패(파일 문제)는 다시 해도 같으므로 자동으로 다시 하지 않는다. 작가가 빼고 다른 사진을 고른다.
        var renderError: String?
        /// 공개 뒤 서버 기록(찜·구매·전달)
        var record: PhotoRecord?

        var isUploaded: Bool { preview.isDone && fullres.isDone }
        var isFailed: Bool { preview.isFailed || fullres.isFailed || renderError != nil }

        func displayName(index: Int) -> String {
            PhotoRecord(id: id, fileName: fileName, capturedAt: capturedAt).displayName(index: index)
        }
    }

    enum PublishState: Equatable {
        case draft
        /// 다 올라가면 바로 공개한다.
        case reserved
        case publishing
        case published(Date?)
        case failed(String)

        var isPublished: Bool { if case .published = self { true } else { false } }
    }

    let ticketID: String
    let customerUID: String
    let ticketDirectory: URL
    private(set) var ticket: TicketRecord
    private(set) var photos: [Photo] = []
    private(set) var publishState = PublishState.draft
    /// 고르기에서 받지 않은 파일과 그 이유(작가에게 보인다)
    private(set) var notices: [String] = []
    private(set) var isNetworkAvailable = true
    /// 업로드 처리량(바이트/초) 추정. 남은 시간 표시에 쓴다.
    private(set) var throughput: Double?

    /// 할 일이 생겼을 때 큐를 깨운다.
    @ObservationIgnored var onNeedsWork: (() -> Void)?
    /// 공개가 끝났을 때(세션이 공개 목록으로 옮기고 로컬 파일을 지운다)
    @ObservationIgnored var onPublished: ((CuratedDeliveryModel) -> Void)?

    @ObservationIgnored private let uploader: TicketPhotoUploader
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryDelay: TimeInterval = 5
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var recordsTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTasks: [UUID: UIBackgroundTaskIdentifier] = [:]
    @ObservationIgnored private var uploadedBytes = 0
    @ObservationIgnored private var uploadSeconds: TimeInterval = 0

    var id: String { ticketID }

    init(ticket: TicketRecord) {
        self.ticket = ticket
        ticketID = ticket.id
        customerUID = ticket.customerUid
        ticketDirectory = Self.directory(for: ticket.id)
        uploader = TicketPhotoUploader(ticketID: ticket.id, customerUID: ticket.customerUid)
        startMonitoringNetwork()
    }

    static func directory(for ticketID: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: "Tickets", directoryHint: .isDirectory)
            .appending(path: ticketID, directoryHint: .isDirectory)
    }

    static func hasLocalFiles(ticketID: String) -> Bool {
        FileManager.default.fileExists(atPath: directory(for: ticketID).appending(path: "selection.json").path(percentEncoded: false))
    }

    // MARK: - 상태

    var uploadedCount: Int { photos.filter(\.isUploaded).count }
    var allUploaded: Bool { !photos.isEmpty && photos.allSatisfy(\.isUploaded) }
    /// 위치가 지워진 채 들어온 사진 수(I008 안내)
    var locationRemovedCount: Int { photos.filter(\.locationRemoved).count }
    var isPublished: Bool { publishState.isPublished }
    var canEditSelection: Bool { !isPublished && publishState != .publishing }
    /// 공개 버튼을 막는 이유(장수). nil이면 장수는 맞다.
    var countProblem: String? { PhotoCuration.countProblem(photos.count) }
    var remainingSlots: Int { max(0, PhotoCuration.publishableCount.upperBound - photos.count) }
    /// 큐가 이 티켓에서 할 일이 있는지(실패해 다시 시도를 기다리는 사진은 빼고)
    var hasPendingWork: Bool { nextPhotoToProcess != nil }
    var hasUnfinishedUploads: Bool { photos.contains { !$0.isUploaded } }

    /// 남은 업로드 바이트를 처리량으로 나눈 추정(초). 처리량을 아직 모르면 nil.
    var estimatedSecondsLeft: TimeInterval? {
        guard let throughput, throughput > 0 else { return nil }
        let left = photos.filter { !$0.fullres.isDone }.reduce(0) { total, photo in
            total + ((try? FileManager.default.attributesOfItem(atPath: fullresURL(photo.id).path(percentEncoded: false))[.size] as? Int) ?? 9_000_000)
        }
        return Double(left) / throughput
    }

    func updateTicket(_ ticket: TicketRecord) {
        self.ticket = ticket
        if let publishedAt = ticket.galleryPublishedAt, !isPublished {
            markPublished(at: publishedAt, ids: ticket.galleryPhotoIds)
        }
    }

    // MARK: - 고르기

    /// 고른 파일 하나를 받는다. 받지 않으면 이유를 `notices`에 남긴다. 파일은 옮긴다(호출한 쪽 임시 파일).
    func add(fileAt url: URL, fileName: String?, assetIdentifier: String?) {
        guard canEditSelection else { return }
        let label = fileName ?? url.lastPathComponent
        guard photos.count < PhotoCuration.publishableCount.upperBound else {
            notices.append("\(label): \(PhotoCuration.publishableCount.upperBound)장까지 고를 수 있습니다.")
            try? FileManager.default.removeItem(at: url)
            return
        }
        let inspection = PhotoInspection.of(url)
        if let rejection = PhotoCuration.rejection(format: inspection.map { Self.inputFormat($0.format) }, longSide: inspection?.longSide ?? 0) {
            notices.append("\(label): \(rejection.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let inspection else { return }
        let contentKey = Self.contentKey(of: url)
        if photos.contains(where: { ($0.assetIdentifier != nil && $0.assetIdentifier == assetIdentifier) || $0.contentKey == contentKey }) {
            notices.append("\(label): 이미 고른 사진입니다.")
            try? FileManager.default.removeItem(at: url)
            return
        }
        let photoID = PhotoCuration.newPhotoID()
        let fileExtension = inspection.format == .heif ? "heic" : "jpg"
        let destination = originalURL(photoID, fileExtension: fileExtension)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            notices.append("\(label): 앱 폴더로 옮기지 못했습니다(\(error.localizedDescription)).")
            return
        }
        var photo = Photo(id: photoID, fileExtension: fileExtension, fileName: fileName, capturedAt: inspection.capturedAt,
                          width: inspection.width, height: inspection.height, assetIdentifier: assetIdentifier, contentKey: contentKey)
        photo.thumbnail = Self.thumbnail(of: destination)
        photo.isOutsideShootWindow = PhotoCuration.isOutsideShootWindow(capturedAt: inspection.capturedAt, shootStartedAt: shootStartedAt)
        photo.locationRemoved = inspection.location == .removed
        photos.append(photo)
        // 기본 순서는 촬영 시각순이다(작가가 끌어서 바꿀 수 있다). 시각이 없는 사진은 고른 순서대로 뒤에 둔다.
        sortByCaptureTimeIfUntouched()
        appendLog("added \(photoID) \(fileName ?? "-") \(inspection.width)x\(inspection.height) location=\(inspection.location.rawValue)")
        if photo.locationRemoved {
            let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            appendEvent("locationRemoved", photoID, "original", bytes: bytes, seconds: 0, note: "")
        }
        save()
        onNeedsWork?()
    }

    func dismissNotices() {
        notices = []
    }

    /// 공개 전에만 뺄 수 있다. 서버에 이미 올라간 초안은 고객에게 보이지 않고(공개 목록에만 들어간 사진이 보인다) 30일 뒤 지워진다.
    func remove(_ photoID: String) {
        guard canEditSelection, let index = photos.firstIndex(where: { $0.id == photoID }) else { return }
        let photo = photos.remove(at: index)
        for url in [originalURL(photo.id, fileExtension: photo.fileExtension), previewURL(photo.id), fullresURL(photo.id)] {
            try? FileManager.default.removeItem(at: url)
        }
        hasCustomOrder = true
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard canEditSelection else { return }
        photos.move(fromOffsets: source, toOffset: destination)
        hasCustomOrder = true
        save()
    }

    /// 작가가 순서를 직접 바꾼 뒤로는 새 사진을 맨 뒤에 붙인다.
    @ObservationIgnored private var hasCustomOrder = false

    private func sortByCaptureTimeIfUntouched() {
        guard !hasCustomOrder else { return }
        let indexed = photos.enumerated().map { ($0.offset, $0.element) }
        photos = indexed.sorted { lhs, rhs in
            switch (lhs.1.capturedAt, rhs.1.capturedAt) {
            case let (a?, b?): a == b ? lhs.0 < rhs.0 : a < b
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.0 < rhs.0
            }
        }.map(\.1)
    }

    /// 촬영 시작 시각(둘 다 시작한 시각). 시간대 경고와 타이머의 기준이다.
    var shootStartedAt: Date? {
        guard let customer = ticket.customerStartedAt, let photographer = ticket.photographerStartedAt else { return nil }
        return max(customer, photographer)
    }

    // MARK: - 처리(큐가 부른다)

    private var nextPhotoToProcess: Photo? {
        photos.first { !$0.isUploaded && !$0.isFailed && $0.preview != .working && $0.fullres != .working }
    }

    /// 다음 사진 하나를 만들고 올린다. 큐가 한 번에 한 사진씩 부른다.
    func processNext() async {
        guard let photo = nextPhotoToProcess else { return }
        let photoID = photo.id
        if !photo.isRendered {
            update(photoID) { $0.preview = .working; $0.fullres = .working }
            do {
                try await render(photo)
                update(photoID) { $0.isRendered = true }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "사진을 만들지 못했습니다: \(error.localizedDescription)"
                update(photoID) { $0.renderError = message; $0.preview = .waiting; $0.fullres = .waiting }
                appendLog("render failed \(photoID): \(error)")
                return
            }
        }
        guard let current = photos.first(where: { $0.id == photoID }) else { return }
        async let previewResult: Void = deliver(.preview, of: current)
        async let fullresResult: Void = deliver(.fullres, of: current)
        _ = await (previewResult, fullresResult)
        if photos.contains(where: \.isFailed) {
            scheduleRetry()
        } else {
            retryDelay = 5
        }
        save()
        publishIfReserved()
    }

    private func render(_ photo: Photo) async throws {
        let source = originalURL(photo.id, fileExtension: photo.fileExtension)
        let preview = previewURL(photo.id)
        let fullres = fullresURL(photo.id)
        let started = Date()
        try await withExtraBackgroundTime(name: "render \(photo.id)") {
            try await Task.detached(priority: .userInitiated) {
                try PhotoPreviewRenderer.renderJPEG(from: source, to: preview)
                try Self.renderFullResolution(from: source, to: fullres)
            }.value
        }
        appendLog("rendered \(photo.id) in \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
    }

    /// 고화질본(메타데이터 포함)이 50MiB 이상이면 품질을 두 단계 낮춰 다시 만들고, 그래도 넘으면 받지 않는다(공통 명세).
    nonisolated private static func renderFullResolution(from source: URL, to destination: URL) throws {
        for quality in [PhotoPreviewRenderer.defaultFullResolutionQuality] + PhotoCuration.fallbackQualities {
            try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: destination, quality: quality)
            let size = (try FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int) ?? 0
            if size < PhotoCuration.fullResolutionByteLimit { return }
        }
        try? FileManager.default.removeItem(at: destination)
        throw TooLargeError()
    }

    private struct TooLargeError: LocalizedError {
        var errorDescription: String? { "이 사진은 50MB를 넘어 올릴 수 없습니다. 해상도를 낮춰 다시 내보내 주세요." }
    }

    private func deliver(_ variant: TicketPhotoUploader.Variant, of photo: Photo) async {
        let isPreview = variant == .preview
        if isPreview ? photo.preview.isDone : photo.fullres.isDone { return }
        update(photo.id) { if isPreview { $0.preview = .working } else { $0.fullres = .working } }
        let url = isPreview ? previewURL(photo.id) : fullresURL(photo.id)
        let isForeground = UIApplication.shared.applicationState != .background
        // 고화질본은 앞에서 시작하면 iOS 백그라운드 전송(putFile)으로 보내 작가가 다른 앱을 써도 이어지게 한다.
        // 백그라운드에서 새로 시작한 putFile은 iOS가 한참 미룰 수 있어(2026-10-25 실측) 그때는 깨어 있는 시간 안에 putData로 보낸다.
        let transport: TicketPhotoUploader.Transport = isPreview || !isForeground ? .data : .file
        do {
            let upload = try await withExtraBackgroundTime(name: "\(variant.rawValue) \(photo.id)") {
                try await uploader.deliver(variant, photoID: photo.id, fileAt: url, fileName: photo.fileName,
                                           capturedAt: photo.capturedAt, transport: transport)
            }
            update(photo.id) { if isPreview { $0.preview = .done } else { $0.fullres = .done } }
            if !isPreview, !upload.reusedExisting, upload.transferDuration > 0 {
                uploadedBytes += upload.byteCount
                uploadSeconds += upload.transferDuration
                throughput = Double(uploadedBytes) / uploadSeconds
            }
            appendEvent("uploaded", photo.id, variant.rawValue, bytes: upload.byteCount, seconds: upload.duration,
                        note: "\(transport.rawValue)\(upload.reusedExisting ? " reused" : "")")
        } catch {
            update(photo.id) { if isPreview { $0.preview = .failed(error.localizedDescription) } else { $0.fullres = .failed(error.localizedDescription) } }
            appendLog("\(variant.rawValue) failed \(photo.id): \(error)")
        }
    }

    /// 실패한 업로드를 잠시 뒤 다시 한다(5초에서 30초까지 늘린다). 인터넷이 없으면 돌아올 때까지 기다린다.
    private func scheduleRetry() {
        guard isNetworkAvailable, retryTask == nil else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.retryTask = nil
            self?.retryFailedUploads()
        }
    }

    /// 실패한 업로드를 대기로 되돌리고 큐를 깨운다(앱이 앞으로 올 때, 인터넷이 돌아올 때, 작가가 칸을 누를 때).
    func retryFailedUploads() {
        var changed = false
        for index in photos.indices where photos[index].preview.isFailed || photos[index].fullres.isFailed {
            if photos[index].preview.isFailed { photos[index].preview = .waiting }
            if photos[index].fullres.isFailed { photos[index].fullres = .waiting }
            changed = true
        }
        if case .failed = publishState, allUploaded {
            publishState = .reserved
            changed = true
        }
        if changed {
            onNeedsWork?()
            publishIfReserved()
        }
    }

    // MARK: - 공개

    /// "고객에게 공개". 다 올라갔으면 바로, 아니면 다 올라가는 대로 공개한다(공개 예약).
    func requestPublish() {
        guard countProblem == nil, canEditSelection else { return }
        publishState = allUploaded ? .publishing : .reserved
        save()
        if allUploaded {
            Task { await publish() }
        } else {
            onNeedsWork?()
        }
    }

    func cancelReservation() {
        guard publishState == .reserved else { return }
        publishState = .draft
        save()
    }

    private func publishIfReserved() {
        guard publishState == .reserved, allUploaded, countProblem == nil else { return }
        publishState = .publishing
        Task { await publish() }
    }

    private func publish() async {
        let ids = photos.map(\.id)
        appendLog("publishing \(ids.count) photos")
        do {
            let result = try await withExtraBackgroundTime(name: "publish \(ticketID)") {
                try await TicketGallery.publish(ticketId: ticketID, photoIds: ids)
            }
            appendEvent("published", "-", "-", bytes: ids.count, seconds: 0, note: result.photoIDs.joined(separator: " "))
            markPublished(at: result.publishedAt ?? Date(), ids: result.photoIDs)
        } catch let error as TicketGallery.PublishError {
            appendLog("publish failed: \(error.reason ?? "-") \(error.photoID ?? "")")
            if error.reason == "GALLERY_ALREADY_PUBLISHED", let fresh = try? await TicketService.fetchTicket(ticketID),
               let publishedAt = fresh.galleryPublishedAt {
                updateTicket(fresh)
                markPublished(at: publishedAt, ids: fresh.galleryPhotoIds)
                return
            }
            if error.needsReupload, let photoID = error.photoID {
                prepareReupload(photoID, keepsID: error.reason == "OBJECT_MISSING")
                publishState = .reserved
                save()
                onNeedsWork?()
                return
            }
            publishState = .failed(error.localizedDescription)
            save()
        } catch {
            publishState = .failed("공개하지 못했습니다: \(error.localizedDescription)")
            save()
        }
    }

    /// 서버가 그 사진을 쓸 수 없다고 하면 다시 올린다. 객체가 없을 때만 같은 ID로 다시 만들 수 있고(만들기만 되는 규칙),
    /// 불일치·오래됨은 새 ID로 올린다.
    private func prepareReupload(_ photoID: String, keepsID: Bool) {
        guard let index = photos.firstIndex(where: { $0.id == photoID }) else { return }
        var photo = photos[index]
        if !keepsID {
            let newID = PhotoCuration.newPhotoID()
            try? FileManager.default.moveItem(at: originalURL(photoID, fileExtension: photo.fileExtension),
                                              to: originalURL(newID, fileExtension: photo.fileExtension))
            try? FileManager.default.removeItem(at: previewURL(photoID))
            try? FileManager.default.removeItem(at: fullresURL(photoID))
            photo.id = newID
            photo.isRendered = false
            appendLog("reupload \(photoID) as \(newID)")
        }
        photo.preview = .waiting
        photo.fullres = .waiting
        photos[index] = photo
    }

    private func markPublished(at date: Date?, ids: [String]) {
        // 서버가 확정한 순서를 따른다.
        let byID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let ordered = ids.compactMap { byID[$0] }
        if ordered.count == photos.count { photos = ordered }
        publishState = .published(date)
        save()
        listenToRecords()
        onPublished?(self)
    }

    /// 공개 뒤 찜·구매·전달을 보여 준다.
    private func listenToRecords() {
        guard recordsTask == nil else { return }
        let stream = uploader.photoRecords()
        recordsTask = Task { [weak self] in
            do {
                for try await records in stream {
                    guard let self else { return }
                    for index in photos.indices {
                        photos[index].record = records[photos[index].id]
                    }
                }
            } catch {}
        }
    }

    func stop() {
        recordsTask?.cancel()
        recordsTask = nil
        retryTask?.cancel()
        retryTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: - 복원

    /// 앱을 다시 켰을 때 `selection.json`과 서버 사진 문서로 상태를 되살린다.
    func restore() async {
        guard let data = try? Data(contentsOf: selectionURL),
              let saved = try? JSONDecoder().decode(SavedSelection.self, from: data)
        else { return }
        hasCustomOrder = saved.hasCustomOrder
        var restored: [Photo] = []
        for item in saved.photos {
            let original = originalURL(item.id, fileExtension: item.fileExtension)
            guard FileManager.default.fileExists(atPath: original.path(percentEncoded: false)) else { continue }
            var photo = Photo(id: item.id, fileExtension: item.fileExtension, fileName: item.fileName, capturedAt: item.capturedAt,
                              width: item.width, height: item.height, assetIdentifier: item.assetIdentifier, contentKey: item.contentKey)
            photo.thumbnail = Self.thumbnail(of: original)
            photo.isRendered = FileManager.default.fileExists(atPath: previewURL(item.id).path(percentEncoded: false))
                && FileManager.default.fileExists(atPath: fullresURL(item.id).path(percentEncoded: false))
            photo.isOutsideShootWindow = PhotoCuration.isOutsideShootWindow(capturedAt: item.capturedAt, shootStartedAt: shootStartedAt)
            photo.locationRemoved = item.locationRemoved ?? false
            restored.append(photo)
        }
        photos = restored
        if let records = try? await uploader.fetchPhotoRecords() {
            for index in photos.indices {
                guard let record = records[photos[index].id] else { continue }
                if record.previewUploadedAt != nil { photos[index].preview = .done }
                if record.fullresUploadedAt != nil { photos[index].fullres = .done }
            }
        }
        if let publishedAt = ticket.galleryPublishedAt {
            markPublished(at: publishedAt, ids: ticket.galleryPhotoIds)
        } else if saved.publishReserved {
            publishState = .reserved
            publishIfReserved()
        }
        appendLog("restored \(photos.count) photos, uploaded \(uploadedCount)")
        onNeedsWork?()
    }

    private struct SavedSelection: Codable {
        struct Item: Codable {
            let id: String
            let fileExtension: String
            let fileName: String?
            let capturedAt: Date?
            let width: Int
            let height: Int
            let assetIdentifier: String?
            let contentKey: String
            /// I008 전에 저장한 기록에는 없다.
            let locationRemoved: Bool?
        }

        let photos: [Item]
        let publishReserved: Bool
        let hasCustomOrder: Bool
    }

    private func save() {
        let saved = SavedSelection(
            photos: photos.map {
                SavedSelection.Item(id: $0.id, fileExtension: $0.fileExtension, fileName: $0.fileName, capturedAt: $0.capturedAt,
                                    width: $0.width, height: $0.height, assetIdentifier: $0.assetIdentifier, contentKey: $0.contentKey,
                                    locationRemoved: $0.locationRemoved)
            },
            publishReserved: publishState == .reserved || publishState == .publishing,
            hasCustomOrder: hasCustomOrder
        )
        do {
            try FileManager.default.createDirectory(at: ticketDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: selectionURL, options: .atomic)
        } catch {
            appendLog("save failed: \(error)")
        }
    }

    /// 공개가 끝나 로컬 사본(원본 복사·미리보기·고화질본)을 지운다. 사진은 작가 보관함이나 SD 카드에 남아 있다.
    func deleteLocalFiles() {
        stop()
        try? FileManager.default.removeItem(at: ticketDirectory)
    }

    // MARK: - 경로·도구

    private var selectionURL: URL { ticketDirectory.appending(path: "selection.json") }

    func originalURL(_ photoID: String, fileExtension: String) -> URL {
        ticketDirectory.appending(path: "originals", directoryHint: .isDirectory).appending(path: "\(photoID).\(fileExtension)")
    }

    func previewURL(_ photoID: String) -> URL {
        ticketDirectory.appending(path: "previews", directoryHint: .isDirectory).appending(path: "\(photoID).jpg")
    }

    func fullresURL(_ photoID: String) -> URL {
        ticketDirectory.appending(path: "fullres", directoryHint: .isDirectory).appending(path: "\(photoID).jpg")
    }

    private func update(_ photoID: String, _ change: (inout Photo) -> Void) {
        guard let index = photos.firstIndex(where: { $0.id == photoID }) else { return }
        change(&photos[index])
    }

    private static func inputFormat(_ format: PhotoInspection.Format) -> PhotoCuration.InputFormat {
        switch format {
        case .jpeg: .jpeg
        case .heif: .heif
        case .raw: .raw
        case .other: .other
        }
    }

    /// 같은 파일을 두 번 고르지 않게: 크기 + 앞 1MB 해시
    private static func contentKey(of url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int) ?? 0
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "\(size)" }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 1_048_576)) ?? Data()
        let digest = SHA256.hash(data: head).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(size)-\(digest)"
    }

    private static func thumbnail(of url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }

    private func startMonitoringNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor in self?.updateNetwork(isAvailable: isAvailable) }
        }
        monitor.start(queue: DispatchQueue(label: "sbsn.gallery-path-monitor"))
        pathMonitor = monitor
    }

    private func updateNetwork(isAvailable: Bool) {
        guard isAvailable != isNetworkAvailable else { return }
        isNetworkAvailable = isAvailable
        appendLog("network: \(isAvailable ? "available" : "unavailable")")
        if isAvailable { retryFailedUploads() }
    }

    /// 작업 중에 앱이 뒤로 가도 끝낼 시간을 시스템에 조금 더 받는다(보통 30초 안팎).
    private func withExtraBackgroundTime<T>(name: String, _ operation: () async throws -> T) async rethrows -> T {
        let id = UUID()
        backgroundTasks[id] = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.endBackgroundTime(id)
        }
        defer { endBackgroundTime(id) }
        return try await operation()
    }

    private func endBackgroundTime(_ id: UUID) {
        guard let task = backgroundTasks.removeValue(forKey: id) else { return }
        UIApplication.shared.endBackgroundTask(task)
    }

    // MARK: - 기록

    /// 문제가 생긴 단계를 맥으로 꺼내 볼 수 있게 티켓 폴더에 남긴다(`session-log.txt`).
    func appendLog(_ line: String) {
        append(named: "session-log.txt", line: "\(Self.isoFormatter.string(from: Date())) \(line)")
    }

    /// 시간 예산(종료 → 마지막 업로드 → 공개) 측정용 기록(`events.csv`): 시각, 사건, 사진, 갈래, 바이트, 초, 메모
    func appendEvent(_ event: String, _ photoID: String, _ variant: String, bytes: Int, seconds: TimeInterval, note: String) {
        append(named: "events.csv", line: [Self.isoFormatter.string(from: Date()), event, photoID, variant, String(bytes),
                                           String(format: "%.3f", seconds), note].joined(separator: ","))
    }

    private func append(named name: String, line: String) {
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
        } catch {}
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
