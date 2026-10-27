import Observation
import SBSNBackend
import UIKit

/// 그리드에 보일 미리보기 이미지를 받아 둔다.
///
/// 셀이 화면에 나타날 때 요청하고 사라지면 아직 시작하지 않은 요청을 빼므로, 보이는 사진부터 받고 동시에 너무 많이 받지 않는다.
/// 받은 데이터는 `TicketPhotoDownloader`가 디스크에 캐시하고, 디코딩한 이미지는 여기서 메모리에 둔다.
@Observable
@MainActor
final class PhotoPreviewLoader {
    static let maxConcurrentDownloads = 4

    private let downloader: TicketPhotoDownloader
    private(set) var images: [String: UIImage] = [:]
    private(set) var failures: [String: String] = [:]
    private var queue: [String] = []
    private var running: Set<String> = []

    init(downloader: TicketPhotoDownloader) {
        self.downloader = downloader
    }

    func request(_ fileName: String) {
        guard images[fileName] == nil, !running.contains(fileName), !queue.contains(fileName) else { return }
        failures[fileName] = nil
        queue.append(fileName)
        pump()
    }

    /// 셀이 화면에서 사라졌을 때. 이미 받는 중이면 그대로 두고(캐시에 남으니 낭비가 아니다) 대기 중인 것만 뺀다.
    func cancelRequest(_ fileName: String) {
        queue.removeAll { $0 == fileName }
    }

    private func pump() {
        while running.count < Self.maxConcurrentDownloads, !queue.isEmpty {
            let fileName = queue.removeFirst()
            running.insert(fileName)
            Task { await load(fileName) }
        }
    }

    private func load(_ fileName: String) async {
        defer {
            running.remove(fileName)
            pump()
        }
        do {
            let data = try await downloader.preview(fileName: fileName)
            // 디코딩은 메인 밖에서 끝내 두고 그릴 준비가 된 이미지만 넘긴다.
            let image = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)?.preparingForDisplay()
            }.value
            if let image {
                images[fileName] = image
            } else {
                failures[fileName] = "이미지를 읽을 수 없습니다"
            }
        } catch {
            failures[fileName] = error.localizedDescription
        }
    }
}
