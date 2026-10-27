import Foundation

/// 티켓 안의 1:1 채팅 한 줄(`tickets/{ticketId}/messages/{autoId}`). 글만 보내고 고치거나 지울 수 없다.
public struct ChatMessage: Sendable, Equatable, Identifiable {
    public static let textLimit = 1000

    public let id: String
    public let senderUid: String
    public let text: String
    /// 서버 시각. 아직 서버에 닿지 않은 내 메시지는 nil이다.
    public let sentAt: Date?

    public init(id: String, senderUid: String, text: String, sentAt: Date?) {
        self.id = id
        self.senderUid = senderUid
        self.text = text
        self.sentAt = sentAt
    }

    /// 보낼 수 있게 다듬는다. 비어 있거나 너무 길면 nil.
    public static func validText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= textLimit else { return nil }
        return trimmed
    }
}
