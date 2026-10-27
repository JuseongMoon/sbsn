import FirebaseFirestore
import Foundation
import SBSNCore

/// Firestore 문서와 SBSNCore 값 사이의 변환. 앱은 Firebase 타입을 직접 쓰지 않는다.
///
/// 서버 시각(`FieldValue.serverTimestamp()`)으로 쓴 항목은 서버에 닿기 전 스냅샷에서 비어 있으므로,
/// 리스너는 `data(with: .estimate)`로 읽어 추정값을 받는다.
enum FirestoreCodec {
    static func date(_ value: Any?) -> Date? {
        (value as? Timestamp)?.dateValue()
    }

    static func point(_ value: Any?) -> SBSNCore.GeoPoint? {
        guard let geo = value as? FirebaseFirestore.GeoPoint else { return nil }
        return SBSNCore.GeoPoint(latitude: geo.latitude, longitude: geo.longitude)
    }

    static func geoPoint(_ point: SBSNCore.GeoPoint) -> FirebaseFirestore.GeoPoint {
        FirebaseFirestore.GeoPoint(latitude: point.latitude, longitude: point.longitude)
    }

    static func ticket(id: String, data: [String: Any]) -> TicketRecord? {
        guard let customerUid = data["customerUid"] as? String,
              let photographerUid = data["photographerUid"] as? String,
              let createdAt = date(data["createdAt"])
        else { return nil }
        return TicketRecord(
            id: id,
            customerUid: customerUid,
            photographerUid: photographerUid,
            photographerDisplayName: data["photographerDisplayName"] as? String ?? "",
            createdAt: createdAt,
            customerStartedAt: date(data["customerStartedAt"]),
            photographerStartedAt: date(data["photographerStartedAt"]),
            photographerAckAt: date(data["photographerAckAt"]),
            endedAt: date(data["endedAt"]),
            cancelledAt: date(data["cancelledAt"]),
            cancelledBy: data["cancelledBy"] as? String
        )
    }

    static func photo(id: String, data: [String: Any]) -> PhotoRecord {
        PhotoRecord(
            fileName: id,
            previewPath: data["previewPath"] as? String,
            previewUploadedAt: date(data["previewUploadedAt"]),
            fullresPath: data["fullresPath"] as? String,
            fullresUploadedAt: date(data["fullresUploadedAt"]),
            originalPath: data["originalPath"] as? String,
            originalUploadedAt: date(data["originalUploadedAt"]),
            capturedAt: date(data["capturedAt"]),
            favoritedAt: date(data["favoritedAt"]),
            purchasedAt: date(data["purchasedAt"]),
            deliveredAt: date(data["deliveredAt"])
        )
    }

    static func presence(id: String, data: [String: Any]) -> PhotographerPresence? {
        guard let displayName = data["displayName"] as? String, let isAvailable = data["isAvailable"] as? Bool else { return nil }
        return PhotographerPresence(
            uid: id,
            displayName: displayName,
            isAvailable: isAvailable,
            location: point(data["location"]),
            updatedAt: date(data["updatedAt"]),
            activeTicketId: data["activeTicketId"] as? String
        )
    }

    static func message(id: String, data: [String: Any]) -> ChatMessage? {
        guard let senderUid = data["senderUid"] as? String, let text = data["text"] as? String else { return nil }
        return ChatMessage(id: id, senderUid: senderUid, text: text, sentAt: date(data["sentAt"]))
    }

    static func location(id: String, data: [String: Any]) -> LocationSample? {
        guard let point = point(data["location"]) else { return nil }
        return LocationSample(uid: id, point: point, updatedAt: date(data["updatedAt"]))
    }
}

/// Firestore 리스너를 AsyncThrowingStream으로 감싼다.
/// Firestore는 리스너를 메인 스레드에서 부른다. 액터에 묶인 클로저로 만들면 Swift 6 격리 검사에 걸리므로 격리 밖에서 만든다.
enum FirestoreListeners {
    enum ListenerError: Error {
        case snapshotMissing
    }

    nonisolated static func documents<T: Sendable>(of query: Query,
                                                   transform: @escaping @Sendable (QuerySnapshot) -> T) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let registration = query.addSnapshotListener { snapshot, error in
                guard let snapshot else {
                    continuation.finish(throwing: error ?? ListenerError.snapshotMissing)
                    return
                }
                continuation.yield(transform(snapshot))
            }
            nonisolated(unsafe) let listener = registration
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    nonisolated static func document<T: Sendable>(_ reference: DocumentReference,
                                                  transform: @escaping @Sendable (DocumentSnapshot) -> T) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let registration = reference.addSnapshotListener { snapshot, error in
                guard let snapshot else {
                    continuation.finish(throwing: error ?? ListenerError.snapshotMissing)
                    return
                }
                continuation.yield(transform(snapshot))
            }
            nonisolated(unsafe) let listener = registration
            continuation.onTermination = { _ in listener.remove() }
        }
    }
}
