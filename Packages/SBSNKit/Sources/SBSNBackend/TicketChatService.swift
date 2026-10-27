import FirebaseFirestore
import Foundation
import SBSNCore

/// 티켓 안의 1:1 채팅(`tickets/{ticketId}/messages/{autoId}`). 글만 보내고 고치거나 지울 수 없다.
public enum TicketChatService {
    nonisolated static func collection(_ ticketId: String) -> CollectionReference {
        TicketService.ticketDocument(ticketId).collection("messages")
    }

    /// 보낸 순서대로. 아직 서버에 닿지 않은 내 글은 추정 시각으로 자리를 잡는다.
    public nonisolated static func messages(ticketId: String) -> AsyncThrowingStream<[ChatMessage], Error> {
        FirestoreListeners.documents(of: collection(ticketId).order(by: "sentAt")) { snapshot in
            snapshot.documents.compactMap { document in
                var message = FirestoreCodec.message(id: document.documentID, data: document.data(with: .estimate))
                if document.metadata.hasPendingWrites {
                    message = message.map { ChatMessage(id: $0.id, senderUid: $0.senderUid, text: $0.text, sentAt: nil) }
                }
                return message
            }
        }
    }

    public static func send(ticketId: String, senderUid: String, text: String) async throws {
        guard let text = ChatMessage.validText(text) else { return }
        try await collection(ticketId).addDocument(data: [
            "senderUid": senderUid,
            "text": text,
            "sentAt": FieldValue.serverTimestamp(),
        ])
    }
}
