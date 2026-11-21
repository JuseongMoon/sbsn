import Foundation
import Observation
import Photos
import SBSNBackend
import SBSNCore

/// 구매한 사진의 고화질본을 받아 사진 앱에 자동 저장하고, 서버에 전달 기록을 남긴다.
///
/// 저장한 사진 ID는 `UserDefaults`(`SBSNDeliveredPhotos.<티켓 ID>`)에 적어 같은 사진을 두 번 저장하지 않는다.
/// 한 번에 한 장씩 처리한다. 사진 앱 권한이 없으면 파일만 받아 두고 상세 화면에서 내보낼 수 있게 한다.
/// 공개된 사진은 언제나 고화질본이 있어(D038) 구매하면 바로 내려받는다. 실패한 사진은 30초마다 다시 시도한다.
@Observable
@MainActor
final class PhotoDeliveryManager {
    enum Status: Equatable {
        case queued
        case downloading
        case saving
        case saved
        /// 사진 앱 권한이 없어 저장하지 못했다. 파일은 남아 있어 내보낼 수 있다.
        case downloadedOnly(URL)
        case failed(String)
    }

    struct Badge {
        let symbol: String
        let text: String
    }

    static let retryInterval: Duration = .seconds(30)

    let ticketId: String
    private let downloader: TicketPhotoDownloader
    private let storageKey: String
    private(set) var statuses: [String: Status] = [:]
    /// 이 기기의 사진 앱에 저장을 마친 사진 ID
    private(set) var savedPhotoIDs: Set<String>
    /// 사진 목록 리스너의 최신 값. 상세 화면도 이것을 읽어 구매·전달 상태 변화를 바로 반영한다.
    private(set) var photos: [PhotoRecord] = []
    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    /// 이번 실행에서 서버에 전달 기록을 보낸 사진 ID. 규칙이 두 번째 기록을 거부하므로 한 번만 보낸다.
    private var markedDelivered: Set<String> = []
    private(set) var listenError: String?
    private var listener: Task<Void, Never>?

    init(ticketId: String, downloader: TicketPhotoDownloader) {
        self.ticketId = ticketId
        self.downloader = downloader
        storageKey = "SBSNDeliveredPhotos.\(ticketId)"
        savedPhotoIDs = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }

    static var isPhotoLibraryAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .authorized || status == .limited
    }

    func status(of photo: PhotoRecord) -> Status? {
        statuses[photo.id]
    }

    /// 그리드 배지와 상세 화면 상태 문구. 구매하지 않은 사진은 nil.
    func badge(for photo: PhotoRecord) -> Badge? {
        if savedPhotoIDs.contains(photo.id) || photo.isDelivered {
            return Badge(symbol: "checkmark.circle.fill", text: "사진 앱에 저장됨")
        }
        switch statuses[photo.id] {
        case .queued, .downloading:
            return Badge(symbol: "arrow.down.circle", text: "고화질 받는 중")
        case .saving:
            return Badge(symbol: "arrow.down.circle", text: "사진 앱에 저장하는 중")
        case .saved:
            return Badge(symbol: "checkmark.circle.fill", text: "사진 앱에 저장됨")
        case .downloadedOnly:
            return Badge(symbol: "square.and.arrow.up", text: "다운로드 완료")
        case .failed(let message):
            return Badge(symbol: "exclamationmark.circle", text: message)
        case nil:
            break
        }
        if photo.isPurchased {
            return Badge(symbol: "cart.fill", text: "고화질 받을 준비 중")
        }
        return nil
    }

    /// 공개된 사진 문서들을 갤러리가 살아 있는 동안 계속 듣는다. 그리드에서 상세로 들어가도 끊기지 않아야
    /// 상세 화면에서 구매한 사진이 바로 내려받아진다(그리드의 task는 상세로 들어가면 취소된다, 실기기에서 확인).
    /// 고객은 사진 목록을 조회할 수 없어 공개 목록의 문서를 하나씩 듣는다(D038).
    func startListening(photoIds: [String]) {
        guard listener == nil else { return }
        listenError = nil
        listener = Task { [weak self, ticketId] in
            do {
                for try await update in TicketPhotoCatalog.gallery(ticketId: ticketId, photoIds: photoIds) {
                    guard let self else { return }
                    self.update(photos: update)
                }
            } catch {
                self?.listenError = "사진 목록을 불러오지 못했습니다: \(error.localizedDescription)"
            }
            self?.listener = nil
        }
    }

    /// 사진 목록이 바뀔 때마다 부른다.
    func update(photos: [PhotoRecord]) {
        self.photos = photos
        for photo in photos where photo.isReadyToDownload {
            enqueueIfIdle(photo.id)
        }
        markDeliveredIfNeeded()
    }

    /// 실패했거나 권한이 없어 저장하지 못한 사진을 다시 처리한다.
    func retry(_ photoID: String) {
        enqueueIfIdle(photoID, allowingRetry: true)
    }

    /// 갤러리 화면이 떠 있는 동안 돌린다. 멈춘 사진(실패, 권한을 나중에 켬)을 다시 시도한다.
    func watchForStalled() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.retryInterval)
            guard !Task.isCancelled else { return }
            retryStalled()
        }
    }

    // MARK: - 큐

    private func enqueueIfIdle(_ photoID: String, allowingRetry: Bool = false) {
        guard !savedPhotoIDs.contains(photoID), !queue.contains(photoID) else { return }
        switch statuses[photoID] {
        case .queued, .downloading, .saving, .saved:
            return
        case .downloadedOnly, .failed:
            guard allowingRetry else { return }
        case nil:
            break
        }
        queue.append(photoID)
        statuses[photoID] = .queued
        startWorker()
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task {
            while !queue.isEmpty {
                let photoID = queue.removeFirst()
                await process(photoID)
            }
            worker = nil
        }
    }

    private func process(_ photoID: String) async {
        statuses[photoID] = .downloading
        let fileURL: URL
        do {
            fileURL = try await downloader.downloadFullResolution(photoId: photoID)
        } catch {
            statuses[photoID] = .failed("고화질본을 받지 못했습니다: \(error.localizedDescription)")
            return
        }
        // 구매할 때 권한을 물었지만, 다른 기기에서 구매했거나 앱을 다시 깐 경우는 여기서 묻는다.
        var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if authorization == .notDetermined {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard authorization == .authorized || authorization == .limited else {
            statuses[photoID] = .downloadedOnly(fileURL)
            return
        }
        statuses[photoID] = .saving
        do {
            try await Self.saveToPhotoLibrary(fileURL: fileURL)
        } catch {
            statuses[photoID] = .failed("사진 앱에 저장하지 못했습니다: \(error.localizedDescription)")
            return
        }
        savedPhotoIDs.insert(photoID)
        UserDefaults.standard.set(savedPhotoIDs.sorted(), forKey: storageKey)
        statuses[photoID] = .saved
        markDeliveredIfNeeded()
    }

    /// 변경 블록은 Photos가 자기 큐에서 돌리므로 격리 밖(detached)에서 만들고 파일 URL만 넘긴다.
    /// 파일을 옮기므로(`shouldMoveFile`) 캐시에는 남지 않고, 확장자가 `.jpg`라 형식을 알아본다.
    /// 개발 메뉴의 저장 시험(`SavedPhotoProbeView`)도 같은 경로를 쓴다.
    static func saveToPhotoLibrary(fileURL: URL) async throws {
        try await Task.detached {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                request.addResource(with: .photo, fileURL: fileURL, options: options)
            }
        }.value
    }

    // MARK: - 서버 기록·복구

    private func markDeliveredIfNeeded() {
        for photo in photos where photo.canMarkDelivered && savedPhotoIDs.contains(photo.id) && !markedDelivered.contains(photo.id) {
            markedDelivered.insert(photo.id)
            Task { await TicketPhotoCatalog.markDelivered(ticketId: ticketId, photoId: photo.id) }
        }
    }

    private func retryStalled() {
        for (photoID, status) in statuses {
            switch status {
            case .failed:
                enqueueIfIdle(photoID, allowingRetry: true)
            case .downloadedOnly:
                // 사용자가 설정에서 권한을 켜고 돌아온 경우
                if Self.isPhotoLibraryAuthorized {
                    enqueueIfIdle(photoID, allowingRetry: true)
                }
            default:
                break
            }
        }
    }
}
