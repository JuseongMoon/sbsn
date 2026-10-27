import FirebaseFirestore
import Foundation
import SBSNCore

/// 고객 앱이 보는 티켓 사진 목록(`tickets/{ticketId}/photos`)과 찜·구매·전달 기록.
///
/// 고객이 쓸 수 있는 항목은 `favoritedAt`·`purchasedAt`·`deliveredAt`뿐이고 모두 서버 시각으로 쓴다(보안 규칙).
/// 구매는 한 번 기록하면 되돌릴 수 없으므로 화면에서 확인을 받은 뒤 부른다.
public enum TicketPhotoCatalog {
    nonisolated static func collection(_ ticketId: String) -> CollectionReference {
        TicketService.ticketDocument(ticketId).collection("photos")
    }

    /// 사진 목록. 촬영 시각(없으면 미리보기 시각) 순이다.
    public nonisolated static func photos(ticketId: String) -> AsyncThrowingStream<[PhotoRecord], Error> {
        FirestoreListeners.documents(of: collection(ticketId)) { snapshot in
            snapshot.documents
                .map { FirestoreCodec.photo(id: $0.documentID, data: $0.data(with: .estimate)) }
                .sorted { ($0.capturedAt ?? $0.previewUploadedAt ?? .distantPast, $0.fileName)
                    < ($1.capturedAt ?? $1.previewUploadedAt ?? .distantPast, $1.fileName) }
        }
    }

    public static func setFavorited(ticketId: String, fileName: String, _ favorited: Bool) async throws {
        try await collection(ticketId).document(fileName).updateData([
            "favoritedAt": favorited ? FieldValue.serverTimestamp() : FieldValue.delete(),
        ])
    }

    /// 구매 기록. 보안 규칙이 미리보기가 있는 사진만, 촬영이 끝난 뒤에는 고화질본이 있는 사진만 허용한다.
    public static func purchase(ticketId: String, fileName: String) async throws {
        try await collection(ticketId).document(fileName).updateData(["purchasedAt": FieldValue.serverTimestamp()])
    }

    /// 고화질본을 사진 앱에 저장했다는 기록. 작가 화면에 "전달 완료"로 보인다. 이미 기록했으면 규칙이 거부하므로 무시한다.
    public static func markDelivered(ticketId: String, fileName: String) async {
        try? await collection(ticketId).document(fileName).updateData(["deliveredAt": FieldValue.serverTimestamp()])
    }
}
