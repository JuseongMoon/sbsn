import FirebaseFirestore
import Foundation
import SBSNCore

/// 촬영 티켓(`tickets/{ticketId}`)의 생성·구독·전이.
///
/// 고객이 작가를 확정하는 순간 티켓이 생긴다(1차 매칭). 확정과 취소는 트랜잭션으로 보낸다:
/// 작가 잠금(`photographerPresence.activeTicketId`)과 고객 잠금(`customers/{uid}.activeTicketId`)을 티켓과 함께 원자적으로 쓰고,
/// 보안 규칙이 `getAfter`로 세 쓰기를 묶어 같은 작가를 두 고객이 동시에 확정하면 하나만 통과시킨다.
/// 트랜잭션은 기기가 오프라인이면 바로 실패하므로, 확정했다고 믿고 기다리다 나중에 거부되는 일이 없다.
public enum TicketService {
    public enum ConfirmError: LocalizedError {
        /// 그 사이 다른 고객과 매칭됐거나 작가가 촬영 가능을 껐다.
        case photographerUnavailable
        /// 이 고객에게 이미 진행 중인 티켓이 있다.
        case alreadyMatched(ticketId: String)

        public var errorDescription: String? {
            switch self {
            case .photographerUnavailable: "지금은 이 작가와 매칭할 수 없습니다. 다른 작가를 골라 주세요."
            case .alreadyMatched: "진행 중인 촬영이 있습니다. 먼저 끝내거나 취소해 주세요."
            }
        }
    }

    nonisolated static var db: Firestore { Firestore.firestore() }

    nonisolated static func ticketDocument(_ ticketId: String) -> DocumentReference {
        db.collection("tickets").document(ticketId)
    }

    // MARK: - 구독

    public nonisolated static func ticket(_ ticketId: String) -> AsyncThrowingStream<TicketRecord?, Error> {
        FirestoreListeners.document(ticketDocument(ticketId)) { snapshot in
            guard let data = snapshot.data(with: .estimate) else { return nil }
            return FirestoreCodec.ticket(id: snapshot.documentID, data: data)
        }
    }

    /// 티켓을 한 번 읽는다. 없거나 읽을 권한이 없으면 nil이 아니라 오류다.
    public static func fetchTicket(_ ticketId: String) async throws -> TicketRecord? {
        let snapshot = try await ticketDocument(ticketId).getDocument()
        guard let data = snapshot.data() else { return nil }
        return FirestoreCodec.ticket(id: snapshot.documentID, data: data)
    }

    /// 고객의 활성 티켓 ID. 다른 기기나 재설치 뒤에도 서버에서 찾을 수 있다.
    public nonisolated static func customerActiveTicketId(uid: String) -> AsyncThrowingStream<String?, Error> {
        FirestoreListeners.document(db.collection("customers").document(uid)) { snapshot in
            snapshot.data(with: .estimate)?["activeTicketId"] as? String
        }
    }

    // MARK: - 고객

    /// 고객이 지도에서 고른 작가를 확정한다. 성공하면 새 티켓 ID를 돌려준다.
    public static func confirm(photographer: PhotographerPresence, customerUid: String) async throws -> String {
        let ticketRef = db.collection("tickets").document()
        let presenceRef = PhotographerDirectory.collection.document(photographer.uid)
        let customerRef = db.collection("customers").document(customerUid)
        let ticketId = ticketRef.documentID
        let photographerUid = photographer.uid
        let refs = (ticket: ticketRef, presence: presenceRef, customer: customerRef)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let presenceSnapshot = try transaction.getDocument(refs.presence)
                guard let presence = FirestoreCodec.presence(id: presenceSnapshot.documentID, data: presenceSnapshot.data() ?? [:]),
                      presence.isSelectable()
                else {
                    errorPointer?.pointee = ConfirmError.photographerUnavailable as NSError
                    return nil
                }
                let customerSnapshot = try transaction.getDocument(refs.customer)
                if let existing = customerSnapshot.data()?["activeTicketId"] as? String {
                    errorPointer?.pointee = ConfirmError.alreadyMatched(ticketId: existing) as NSError
                    return nil
                }
                transaction.setData([
                    "customerUid": customerUid,
                    "photographerUid": photographerUid,
                    "photographerDisplayName": presence.displayName,
                    "createdAt": FieldValue.serverTimestamp(),
                ], forDocument: refs.ticket)
                transaction.updateData(["activeTicketId": ticketId], forDocument: refs.presence)
                transaction.setData(["activeTicketId": ticketId], forDocument: refs.customer)
            } catch {
                errorPointer?.pointee = error as NSError
            }
            return nil
        }
        return ticketId
    }

    /// 고객: 끝나거나 취소된 티켓의 고객 잠금을 푼다. 작가가 끝낸 경우 고객 문서는 고객만 풀 수 있다.
    public static func releaseCustomerLock(uid: String) async throws {
        try await db.collection("customers").document(uid).updateData(["activeTicketId": NSNull()])
    }

    // MARK: - 전이

    /// "시작". 둘 다 누르면 촬영 중이 된다. 보안 규칙이 한 번만 쓰게 한다.
    public static func markStarted(ticketId: String, role: ParticipantRole) async throws {
        let field = switch role {
        case .customer: "customerStartedAt"
        case .photographer: "photographerStartedAt"
        }
        try await ticketDocument(ticketId).updateData([field: FieldValue.serverTimestamp()])
    }

    /// 작가 앱이 매칭을 봤다는 표시. 고객 화면에 "작가 앱이 받음"으로 보인다. 이미 표시했으면 규칙이 거부하므로 무시한다.
    public static func acknowledge(ticketId: String) async {
        try? await ticketDocument(ticketId).updateData(["photographerAckAt": FieldValue.serverTimestamp()])
    }

    /// 작가: 촬영 종료. 같은 배치로 자기 잠금을 풀고 "촬영 가능"도 끈다.
    /// 종료 뒤에도 고객에게 넘길 사진을 올리는 동안은 새 매칭을 받지 않고, 다 끝나면 작가가 다시 켠다.
    public static func end(ticketId: String, photographerUid: String) async throws {
        let batch = db.batch()
        batch.updateData(["endedAt": FieldValue.serverTimestamp()], forDocument: ticketDocument(ticketId))
        batch.updateData([
            "activeTicketId": NSNull(),
            "isAvailable": false,
            "updatedAt": FieldValue.serverTimestamp(),
        ], forDocument: PhotographerDirectory.collection.document(photographerUid))
        try await batch.commit()
    }

    /// 고객: 촬영 중 작가가 사라졌을 때의 종료. 작가 시작 뒤 유예 시간이 지나야 규칙이 허용한다.
    public static func endAsCustomer(ticketId: String) async throws {
        try await ticketDocument(ticketId).updateData(["endedAt": FieldValue.serverTimestamp()])
    }

    /// 둘 다 시작하기 전의 취소. 트랜잭션으로 자기 쪽 잠금을 함께 푼다(고객은 작가 잠금도 푼다).
    public static func cancel(ticket: TicketRecord, by uid: String) async throws {
        guard let role = ticket.role(of: uid) else { return }
        let ticketRef = ticketDocument(ticket.id)
        let presenceRef = PhotographerDirectory.collection.document(ticket.photographerUid)
        let customerRef = db.collection("customers").document(ticket.customerUid)
        let refs = (ticket: ticketRef, presence: presenceRef, customer: customerRef)
        _ = try await db.runTransaction { transaction, _ in
            transaction.updateData([
                "cancelledAt": FieldValue.serverTimestamp(),
                "cancelledBy": uid,
            ], forDocument: refs.ticket)
            switch role {
            case .customer:
                transaction.updateData(["activeTicketId": NSNull()], forDocument: refs.presence)
                transaction.updateData(["activeTicketId": NSNull()], forDocument: refs.customer)
            case .photographer:
                transaction.updateData([
                    "activeTicketId": NSNull(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ], forDocument: refs.presence)
            }
            return nil
        }
    }
}
