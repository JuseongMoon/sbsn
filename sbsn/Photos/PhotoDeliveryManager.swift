import Foundation
import Observation
import Photos
import SBSNBackend
import SBSNCore

/// 구매한 사진의 고화질본을 받아 사진 앱에 자동 저장하고, 서버에 전달 기록을 남긴다.
///
/// 저장한 파일명은 `UserDefaults`(`SBSNDeliveredPhotos.<티켓 ID>`)에 적어 같은 사진을 두 번 저장하지 않는다.
/// 한 번에 한 장씩 처리한다. 사진 앱 권한이 없으면 파일만 받아 두고 상세 화면에서 내보낼 수 있게 한다.
/// 작가 앱이 업로드는 끝냈는데 문서를 쓰기 전에 멈춘 사진은 30초마다 서버에 파일이 있는지 확인해 바로 받는다.
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

    static let missingDocumentCheckInterval: Duration = .seconds(30)

    let ticketId: String
    private let downloader: TicketPhotoDownloader
    private let storageKey: String
    private(set) var statuses: [String: Status] = [:]
    /// 이 기기의 사진 앱에 저장을 마친 파일명
    private(set) var savedFileNames: Set<String>
    /// 사진 목록 리스너의 최신 값. 상세 화면도 이것을 읽어 구매·전달 상태 변화를 바로 반영한다.
    private(set) var photos: [PhotoRecord] = []
    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    /// 이번 실행에서 서버에 전달 기록을 보낸 파일명. 규칙이 두 번째 기록을 거부하므로 한 번만 보낸다.
    private var markedDelivered: Set<String> = []
    private(set) var listenError: String?
    private var listener: Task<Void, Never>?

    init(ticketId: String, downloader: TicketPhotoDownloader) {
        self.ticketId = ticketId
        self.downloader = downloader
        storageKey = "SBSNDeliveredPhotos.\(ticketId)"
        savedFileNames = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }

    static var isPhotoLibraryAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        return status == .authorized || status == .limited
    }

    func status(of photo: PhotoRecord) -> Status? {
        statuses[photo.fileName]
    }

    /// 그리드 배지와 상세 화면 상태 문구. 구매하지 않은 사진은 nil.
    func badge(for photo: PhotoRecord) -> Badge? {
        if savedFileNames.contains(photo.fileName) || photo.isDelivered {
            return Badge(symbol: "checkmark.circle.fill", text: "사진 앱에 저장됨")
        }
        switch statuses[photo.fileName] {
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
            return Badge(symbol: "cart.fill", text: photo.isFullResolutionReady ? "고화질 받을 준비 중" : "작가 앱이 고화질본을 올리는 중")
        }
        return nil
    }

    /// 사진 목록을 티켓이 열려 있는 동안 계속 듣는다. 그리드에서 상세로 들어가도 끊기지 않아야
    /// 상세 화면에서 구매한 사진이 바로 내려받아진다(그리드의 task는 상세로 들어가면 취소된다, 실기기에서 확인).
    /// 티켓이 바뀌어 이 객체가 사라지면 다음 갱신 때 멈춘다.
    func startListening() {
        guard listener == nil else { return }
        listenError = nil
        listener = Task { [weak self, ticketId] in
            do {
                for try await update in TicketPhotoCatalog.photos(ticketId: ticketId) {
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
            enqueueIfIdle(photo.fileName)
        }
        markDeliveredIfNeeded()
    }

    /// 실패했거나 권한이 없어 저장하지 못한 사진을 다시 처리한다.
    func retry(_ fileName: String) {
        enqueueIfIdle(fileName, allowingRetry: true)
    }

    /// 사진 화면이 떠 있는 동안 돌린다. 문서 없이 올라온 고화질본을 찾고, 멈춘 사진을 다시 시도한다.
    func watchForMissingDocuments() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.missingDocumentCheckInterval)
            guard !Task.isCancelled else { return }
            await checkMissingDocuments()
            retryStalled()
        }
    }

    // MARK: - 큐

    private func enqueueIfIdle(_ fileName: String, allowingRetry: Bool = false) {
        guard !savedFileNames.contains(fileName), !queue.contains(fileName) else { return }
        switch statuses[fileName] {
        case .queued, .downloading, .saving, .saved:
            return
        case .downloadedOnly, .failed:
            guard allowingRetry else { return }
        case nil:
            break
        }
        queue.append(fileName)
        statuses[fileName] = .queued
        startWorker()
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task {
            while !queue.isEmpty {
                let fileName = queue.removeFirst()
                await process(fileName)
            }
            worker = nil
        }
    }

    private func process(_ fileName: String) async {
        statuses[fileName] = .downloading
        let fileURL: URL
        do {
            fileURL = try await downloader.downloadFullResolution(fileName: fileName)
        } catch {
            statuses[fileName] = .failed("고화질본을 받지 못했습니다: \(error.localizedDescription)")
            return
        }
        // 구매할 때 권한을 물었지만, 다른 기기에서 구매했거나 앱을 다시 깐 경우는 여기서 묻는다.
        var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if authorization == .notDetermined {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard authorization == .authorized || authorization == .limited else {
            statuses[fileName] = .downloadedOnly(fileURL)
            return
        }
        statuses[fileName] = .saving
        do {
            try await Self.saveToPhotoLibrary(fileURL: fileURL)
        } catch {
            statuses[fileName] = .failed("사진 앱에 저장하지 못했습니다: \(error.localizedDescription)")
            return
        }
        savedFileNames.insert(fileName)
        UserDefaults.standard.set(savedFileNames.sorted(), forKey: storageKey)
        statuses[fileName] = .saved
        markDeliveredIfNeeded()
    }

    /// 변경 블록은 Photos가 자기 큐에서 돌리므로 격리 밖(detached)에서 만들고 파일 URL만 넘긴다.
    /// 파일을 옮기므로(`shouldMoveFile`) 캐시에는 남지 않고, 확장자가 `.jpg`라 형식을 알아본다.
    private static func saveToPhotoLibrary(fileURL: URL) async throws {
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
        for photo in photos where photo.canMarkDelivered && savedFileNames.contains(photo.fileName) && !markedDelivered.contains(photo.fileName) {
            markedDelivered.insert(photo.fileName)
            Task { await TicketPhotoCatalog.markDelivered(ticketId: ticketId, fileName: photo.fileName) }
        }
    }

    private func checkMissingDocuments() async {
        let candidates = photos.filter {
            $0.isPurchased && !$0.isFullResolutionReady && !savedFileNames.contains($0.fileName) && statuses[$0.fileName] == nil
        }
        for photo in candidates {
            if await downloader.fullResolutionExists(fileName: photo.fileName) {
                enqueueIfIdle(photo.fileName)
            }
        }
    }

    private func retryStalled() {
        for (fileName, status) in statuses {
            switch status {
            case .failed:
                enqueueIfIdle(fileName, allowingRetry: true)
            case .downloadedOnly:
                // 사용자가 설정에서 권한을 켜고 돌아온 경우
                if Self.isPhotoLibraryAuthorized {
                    enqueueIfIdle(fileName, allowingRetry: true)
                }
            default:
                break
            }
        }
    }
}
