import Foundation
import Observation
import SBSNBackend
import SBSNCore

/// 찜 하트 토글. 연타하면 300ms 디바운스로 마지막 값만 서버에 보낸다.
///
/// 보내기 전과 보내는 동안에는 누른 값을 화면에 보여 주고, 서버가 거부하면 원래 값으로 돌아간다.
@Observable
@MainActor
final class FavoriteToggler {
    static let debounce: Duration = .milliseconds(300)

    let ticketId: String
    /// 아직 서버에 확정되지 않은 사진별 원하는 값
    private(set) var pending: [String: Bool] = [:]
    private(set) var errorMessage: String?
    private var tasks: [String: Task<Void, Never>] = [:]

    init(ticketId: String) {
        self.ticketId = ticketId
    }

    /// 화면에 보일 찜 상태. 보내는 중이면 누른 값, 아니면 서버 값.
    func isFavorited(_ photo: PhotoRecord) -> Bool {
        pending[photo.id] ?? photo.isFavorited
    }

    func isPending(_ photo: PhotoRecord) -> Bool {
        pending[photo.id] != nil
    }

    func toggle(_ photo: PhotoRecord) {
        let photoID = photo.id
        let desired = !isFavorited(photo)
        pending[photoID] = desired
        tasks[photoID]?.cancel()
        tasks[photoID] = Task {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await send(photoID: photoID, favorited: desired)
        }
    }

    private func send(photoID: String, favorited: Bool) async {
        do {
            try await TicketPhotoCatalog.setFavorited(ticketId: ticketId, photoId: photoID, favorited)
            errorMessage = nil
        } catch {
            errorMessage = "찜을 저장하지 못했습니다: \(error.localizedDescription)"
        }
        // 보내는 사이 다시 눌렀으면 새 값이 따로 예약돼 있으므로 건드리지 않는다.
        if pending[photoID] == favorited {
            pending[photoID] = nil
            tasks[photoID] = nil
        }
    }
}
