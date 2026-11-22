#if os(iOS)
import SBSNBackend
import SBSNCore
import SwiftUI

/// 시작 대기 중 촬영 취소 사유 시트(설계 2.5, L17). 두 앱이 같이 쓴다. 취소는 바로 효력이 생기고 상대에게는 분류만 보인다.
/// "서로 이야기해서 취소해요"를 고르면 상대에게 24시간 동의 카드가 뜬다. 메모는 서버 전용이다.
public struct LaunchCancelSheet: View {
    let ticketId: String
    let onDone: () -> Void
    @State private var reason: LaunchMatch.CancelReason?
    @State private var note = ""
    @State private var isWorking = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    public init(ticketId: String, onDone: @escaping () -> Void = {}) {
        self.ticketId = ticketId
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(LaunchMatch.CancelReason.allCases) { option in
                        Button {
                            reason = option
                        } label: {
                            HStack {
                                Text(option.label).foregroundStyle(.primary)
                                Spacer()
                                if reason == option { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }
                        }
                        .accessibilityIdentifier("cancel.reason.\(option.rawValue)")
                    }
                } footer: {
                    Text("취소는 바로 적용되고 상대에게는 고른 분류만 보여요. \"서로 이야기해서 취소해요\"를 고르면 상대가 24시간 안에 동의할 수 있어요.")
                }
                if reason == .other {
                    Section("메모(상대에게 보이지 않아요)") {
                        TextField("메모", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityIdentifier("cancel.note")
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("촬영을 취소할까요?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("돌아가기") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("촬영 취소", role: .destructive) {
                        Task { await cancel() }
                    }
                    .disabled(reason == nil || isWorking)
                    .accessibilityIdentifier("cancel.confirm")
                }
            }
        }
    }

    private func cancel() async {
        guard let reason else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await LaunchMatchService.updateShooting(ticketId: ticketId, .cancel(reason, note: reason == .other ? note : nil))
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 상대가 "서로 이야기해서 취소"를 골랐을 때 대화방 위에 뜨는 동의 카드(24시간, L17)
public struct LaunchMutualCancelCard: View {
    let ticket: LaunchMatch.Ticket
    @State private var isWorking = false
    @State private var error: String?

    public init(ticket: LaunchMatch.Ticket) {
        self.ticket = ticket
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("서로 취소에 동의하나요?")
                .font(.subheadline.bold())
            Text("동의하면 서로 이야기해서 취소한 것으로 남아요. 답하지 않으면 일방 취소로 남아요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("동의하지 않음") { Task { await answer(false) } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("cancel.mutual.disagree")
                Button("동의") { Task { await answer(true) } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("cancel.mutual.agree")
            }
            .disabled(isWorking)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }

    private func answer(_ agree: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await LaunchMatchService.updateShooting(ticketId: ticket.id, agree ? .agreeCancel : .disagreeCancel)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 촬영 중 남은 시간(분 단위, 15초마다 다시 그림, D051)
public struct LaunchRemainingTime: View {
    let ticket: LaunchMatch.Ticket

    public init(ticket: LaunchMatch.Ticket) {
        self.ticket = ticket
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(spacing: 4) {
                Text(ticket.remainingText(now: context.date) ?? "")
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    .accessibilityIdentifier("ticket.remaining")
                if let end = ticket.scheduledEndAt {
                    Text(ticket.extensionMinutes > 0
                         ? "\(ticket.minutes)분 촬영 · \(ticket.extensionMinutes)분 연장됨 · \(LaunchTime.clock(end))까지"
                         : "\(ticket.minutes)분 촬영 · \(LaunchTime.clock(end))까지")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
#endif
