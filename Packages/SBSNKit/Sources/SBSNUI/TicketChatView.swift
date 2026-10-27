import SBSNBackend
import SBSNCore
import SwiftUI

/// 티켓 안의 1:1 채팅. 작가 앱과 고객 앱이 같이 쓴다. 글만 보내고 고치거나 지울 수 없다.
public struct TicketChatView: View {
    let ticketId: String
    let myUid: String
    let otherLabel: String

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    public init(ticketId: String, myUid: String, otherLabel: String) {
        self.ticketId = ticketId
        self.myUid = myUid
        self.otherLabel = otherLabel
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if messages.isEmpty {
                            Text("\(otherLabel)에게 만날 곳을 알려 주세요.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 24)
                        }
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.last?.id) { _, id in
                    if let id {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }
            HStack(spacing: 8) {
                TextField("메시지", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                    .accessibilityIdentifier("chat.field")
                Button("보내기", systemImage: "paperplane.fill", action: send)
                    .labelStyle(.iconOnly)
                    .disabled(isSending || ChatMessage.validText(draft) == nil)
                    .accessibilityIdentifier("chat.send")
            }
            .padding(12)
        }
        .task(id: ticketId) {
            do {
                for try await update in TicketChatService.messages(ticketId: ticketId) {
                    messages = update
                }
            } catch {
                errorMessage = "채팅을 불러오지 못했습니다: \(error.localizedDescription)"
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isMine = message.senderUid == myUid
        return HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMine ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(isMine ? .white : .primary)
                Text(message.sentAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "보내는 중")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    private func send() {
        guard let text = ChatMessage.validText(draft), !isSending else { return }
        isSending = true
        draft = ""
        Task {
            defer { isSending = false }
            do {
                try await TicketChatService.send(ticketId: ticketId, senderUid: myUid, text: text)
                errorMessage = nil
            } catch {
                draft = text
                errorMessage = "보내지 못했습니다: \(error.localizedDescription)"
            }
        }
    }
}
