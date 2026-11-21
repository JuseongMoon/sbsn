import Foundation
import SBSNCore

/// 앱 전체의 업로드 차례(설계 문서 2.7절). 공개 대기 티켓이 여럿이어도 한 번에 한 사진씩 만들고 올려 서로 대역을 다투지 않는다.
///
/// 순서: 공개를 예약한 티켓 → 지금 화면에 열린 티켓 → 나머지(먼저 끝난 촬영부터). 같은 티켓 안에서는 고른 순서다.
/// 새 촬영을 하는 동안에도 이전 티켓의 업로드는 이어 간다.
@MainActor
final class GalleryUploadQueue {
    private let models: () -> [CuratedDeliveryModel]
    private let focusedTicketID: () -> String?
    private var wake: AsyncStream<Void>.Continuation?
    private var loop: Task<Void, Never>?

    init(models: @escaping () -> [CuratedDeliveryModel], focusedTicketID: @escaping () -> String?) {
        self.models = models
        self.focusedTicketID = focusedTicketID
    }

    func start() {
        guard loop == nil else { return }
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        loop = Task { [weak self] in
            for await _ in stream {
                while let model = self?.next() {
                    await model.processNext()
                }
            }
        }
        continuation.yield()
    }

    /// 할 일이 생겼을 때 부른다(사진 추가, 다시 시도, 공개 예약, 복원).
    func signal() {
        wake?.yield()
    }

    private func next() -> CuratedDeliveryModel? {
        let focused = focusedTicketID()
        return models()
            .filter(\.hasPendingWork)
            .min { rank($0, focused: focused) < rank($1, focused: focused) }
    }

    private func rank(_ model: CuratedDeliveryModel, focused: String?) -> (Int, Date) {
        let priority = model.publishState == .reserved ? 0 : model.ticketID == focused ? 1 : 2
        return (priority, model.ticket.endedAt ?? .distantFuture)
    }
}
