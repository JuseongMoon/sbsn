import FirebaseFirestore
import Foundation
import SBSNCore

/// 매칭 뒤 서로의 위치(`tickets/{ticketId}/locations/{uid}`). 각자 자기 문서만 쓰고 참여자만 읽는다.
/// 티켓 문서와 분리해 위치 갱신이 티켓 리스너를 깨우지 않게 한다. 여기 위치는 뭉개지 않는다(만나야 하므로).
public enum TicketLocationService {
    nonisolated static func collection(_ ticketId: String) -> CollectionReference {
        TicketService.ticketDocument(ticketId).collection("locations")
    }

    public nonisolated static func locations(ticketId: String) -> AsyncThrowingStream<[LocationSample], Error> {
        FirestoreListeners.documents(of: collection(ticketId)) { snapshot in
            snapshot.documents.compactMap { FirestoreCodec.location(id: $0.documentID, data: $0.data(with: .estimate)) }
        }
    }

    public static func publish(ticketId: String, uid: String, point: SBSNCore.GeoPoint) async throws {
        try await collection(ticketId).document(uid).setData([
            "location": FirestoreCodec.geoPoint(point),
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }
}
