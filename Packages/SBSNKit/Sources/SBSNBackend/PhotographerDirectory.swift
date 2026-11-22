import FirebaseFirestore
import Foundation

/// MVP 작가 공개 상태(`photographerPresence/{uid}`) 컬렉션.
///
/// 앱은 이제 이 문서를 쓰거나 구독하지 않는다(D063: 공개 위치는 출시 격자 발행 `LaunchPresencePublisher`, 지도는 `LaunchMapService`).
/// `TicketService`의 확정·취소·종료 트랜잭션이 작가 잠금(`activeTicketId`)을 다루므로 2단계 매칭 때까지 컬렉션 참조만 남긴다.
public enum PhotographerDirectory {
    nonisolated static var collection: CollectionReference {
        Firestore.firestore().collection("photographerPresence")
    }
}
