import FirebaseFirestore
import Foundation
import SBSNCore

/// 작가의 공개 상태(`photographerPresence/{uid}`). 고객 지도가 읽고, 작가 앱이 발행한다.
///
/// 잠금 필드 `activeTicketId`는 고객이 확정 트랜잭션에서 채우므로 작가 쪽 발행은 항상 병합으로 써서 그 값을 덮지 않는다.
/// 보안 규칙이 `updatedAt == request.time`을 요구하므로 작가 쪽 쓰기는 모두 서버 시각을 함께 보낸다.
public enum PhotographerDirectory {
    static let presenceValidity: TimeInterval = 24 * 60 * 60

    nonisolated static var collection: CollectionReference {
        Firestore.firestore().collection("photographerPresence")
    }

    /// 고객 지도: 촬영 가능 작가. 규칙상 limit이 있어야 읽힌다. 잠겼거나 오래된 작가는 호출하는 쪽이 `isSelectable`로 거른다.
    public nonisolated static func availablePhotographers() -> AsyncThrowingStream<[PhotographerPresence], Error> {
        let query = collection.whereField("isAvailable", isEqualTo: true).limit(to: 100)
        return FirestoreListeners.documents(of: query) { snapshot in
            snapshot.documents.compactMap { FirestoreCodec.presence(id: $0.documentID, data: $0.data(with: .estimate)) }
        }
    }

    /// 작가: 자기 상태 문서. 고객이 잠그면 `activeTicketId`가 채워져 매칭을 알 수 있다.
    public nonisolated static func presence(of uid: String) -> AsyncThrowingStream<PhotographerPresence?, Error> {
        FirestoreListeners.document(collection.document(uid)) { snapshot in
            guard let data = snapshot.data(with: .estimate) else { return nil }
            return FirestoreCodec.presence(id: snapshot.documentID, data: data)
        }
    }

    /// 작가: "촬영 가능" 상태와 위치를 발행한다. 위치는 100m 격자로 뭉개서 올린다.
    public static func publish(uid: String, displayName: String, isAvailable: Bool, location: SBSNCore.GeoPoint) async throws {
        try await collection.document(uid).setData([
            "displayName": displayName,
            "isAvailable": isAvailable,
            "location": FirestoreCodec.geoPoint(location.quantized(gridMeters: PhotographerPresence.publicGridMeters)),
            "updatedAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(presenceValidity)),
        ], merge: true)
    }

    /// 작가: 대기 중 위치만 다시 쓴다(살아 있음을 알리는 heartbeat 포함).
    public static func publishLocation(uid: String, location: SBSNCore.GeoPoint) async throws {
        try await collection.document(uid).updateData([
            "location": FirestoreCodec.geoPoint(location.quantized(gridMeters: PhotographerPresence.publicGridMeters)),
            "updatedAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(presenceValidity)),
        ])
    }

    /// 작가: "촬영 가능"을 끈다. 문서는 남겨 이름과 마지막 위치를 유지한다.
    public static func setAvailable(uid: String, _ isAvailable: Bool) async throws {
        try await collection.document(uid).updateData([
            "isAvailable": isAvailable,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    /// 작가: 매칭 잠금을 푼다(촬영 종료·취소 뒤).
    public static func clearActiveTicket(uid: String) async throws {
        try await collection.document(uid).updateData([
            "activeTicketId": NSNull(),
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }
}
