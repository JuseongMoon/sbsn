import FirebaseFirestore
import Foundation
import SBSNCore

/// 고객 앱이 보는 공개 갤러리(`tickets/{ticketId}/photos`)와 찜·구매·전달 기록.
///
/// 고객은 공개 전에는 아무것도 못 본다. 공개 뒤에는 티켓의 `galleryPhotoIds` 문서를 하나씩 읽는다(컬렉션 목록 조회는 규칙이 막는다, D038).
/// 고객이 쓸 수 있는 항목은 `favoritedAt`·`purchasedAt`·`deliveredAt`뿐이고 모두 서버 시각으로 쓴다(보안 규칙).
/// 구매는 한 번 기록하면 되돌릴 수 없으므로 화면에서 확인을 받은 뒤 부른다. 찜은 해제할 수 있다.
public enum TicketPhotoCatalog {
    nonisolated static func collection(_ ticketId: String) -> CollectionReference {
        TicketService.ticketDocument(ticketId).collection("photos")
    }

    /// 공개한 사진들. 작가가 정한 순서(`photoIds`)대로, 모든 문서의 첫 응답이 온 뒤부터 바뀔 때마다 보낸다.
    public nonisolated static func gallery(ticketId: String, photoIds: [String]) -> AsyncThrowingStream<[PhotoRecord], Error> {
        AsyncThrowingStream { continuation in
            let state = GalleryState(photoIds: photoIds)
            let registrations = photoIds.map { photoId in
                collection(ticketId).document(photoId).addSnapshotListener { snapshot, error in
                    guard let snapshot else {
                        continuation.finish(throwing: error ?? FirestoreListeners.ListenerError.snapshotMissing)
                        return
                    }
                    let record = snapshot.data(with: .estimate).map { FirestoreCodec.photo(id: photoId, data: $0) }
                    if let ordered = state.update(photoId, record: record) {
                        continuation.yield(ordered)
                    }
                }
            }
            nonisolated(unsafe) let listeners = registrations
            continuation.onTermination = { _ in listeners.forEach { $0.remove() } }
        }
    }

    public static func setFavorited(ticketId: String, photoId: String, _ favorited: Bool) async throws {
        try await collection(ticketId).document(photoId).updateData([
            "favoritedAt": favorited ? FieldValue.serverTimestamp() : FieldValue.delete(),
        ])
    }

    /// 구매 기록. 보안 규칙이 공개된 사진만, 고화질본이 있는 사진만, 공개 뒤 168시간 안에만 허용한다.
    public static func purchase(ticketId: String, photoId: String) async throws {
        try await collection(ticketId).document(photoId).updateData(["purchasedAt": FieldValue.serverTimestamp()])
    }

    /// 고화질본을 사진 앱에 저장했다는 기록. 작가 화면에 "전달 완료"로 보인다. 이미 기록했으면 규칙이 거부하므로 무시한다.
    public static func markDelivered(ticketId: String, photoId: String) async {
        try? await collection(ticketId).document(photoId).updateData(["deliveredAt": FieldValue.serverTimestamp()])
    }
}

/// 문서별 리스너의 최신 값을 모은다. 리스너는 Firestore가 메인 스레드에서 부르지만 격리 밖 클로저라 잠금으로 지킨다.
private final class GalleryState: @unchecked Sendable {
    private let lock = NSLock()
    private let photoIds: [String]
    private var records: [String: PhotoRecord?] = [:]

    init(photoIds: [String]) {
        self.photoIds = photoIds
    }

    /// 모든 문서가 한 번씩 응답했으면 순서대로 정리한 목록(문서가 없는 사진은 뺀다), 아니면 nil
    func update(_ photoId: String, record: PhotoRecord?) -> [PhotoRecord]? {
        lock.lock()
        defer { lock.unlock() }
        records[photoId] = .some(record)
        guard records.count == photoIds.count else { return nil }
        return photoIds.compactMap { records[$0] ?? nil }
    }
}
