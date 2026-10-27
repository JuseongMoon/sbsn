import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 활성 티켓 화면. 티켓 리스너를 붙이고 단계(`phase`)에 따라 만남 화면·사진 화면·취소 안내를 보여 준다.
///
/// 시작·취소·종료 같은 쓰기는 서버 커밋이 끝난 뒤에만 화면을 바꾼다: 쓰는 동안 들어온 스냅샷은 `latestTicket`에만 두고
/// 끝난 뒤 한 번에 반영한다(리스너는 로컬 쓰기를 추정값으로 먼저 주기 때문).
struct CustomerTicketView: View {
    let ticketId: String
    let myUid: String

    @Environment(CustomerSession.self) private var session
    @State private var workspace: TicketWorkspace
    @State private var ticket: TicketRecord?
    @State private var latestTicket: TicketRecord?
    @State private var hasReceivedSnapshot = false
    @State private var loadError: String?
    @State private var listenerGeneration = 0
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var hasReleasedLock = false
    @State private var showsCancelConfirm = false
    @State private var showsEndConfirm = false
    @State private var showsChat = false
    /// `canEnd`는 시각에 따라 달라지므로 주기적으로 갱신한다.
    @State private var now = Date()

    init(ticketId: String, myUid: String) {
        self.ticketId = ticketId
        self.myUid = myUid
        _workspace = State(initialValue: TicketWorkspace(ticketId: ticketId, myUid: myUid))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(ticket?.photographerDisplayName ?? "촬영")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .task(id: listenerGeneration) { await listen() }
                .task { await tickClock() }
                .onChange(of: ticket?.phase, initial: true) { _, phase in handlePhaseChange(phase) }
                .sheet(isPresented: $showsChat) { chatSheet }
                .confirmationDialog("촬영을 취소할까요?", isPresented: $showsCancelConfirm, titleVisibility: .visible) {
                    Button("촬영 취소", role: .destructive, action: cancelTicket)
                    Button("돌아가기", role: .cancel) {}
                }
                .confirmationDialog("촬영을 종료할까요?", isPresented: $showsEndConfirm, titleVisibility: .visible) {
                    Button("촬영 종료", role: .destructive, action: endTicket)
                    Button("돌아가기", role: .cancel) {}
                } message: {
                    Text("종료하면 더 이상 사진이 올라오지 않습니다. 이미 올라온 사진은 계속 구매할 수 있습니다.")
                }
        }
    }

    // MARK: - 단계별 본문

    @ViewBuilder
    private var content: some View {
        if let loadError {
            ContentUnavailableView {
                Label("촬영 정보를 불러오지 못했습니다", systemImage: "wifi.exclamationmark")
            } description: {
                Text(loadError)
            } actions: {
                Button("다시 시도") { listenerGeneration += 1 }
                    .buttonStyle(.borderedProminent)
                Button("지도로 돌아가기") { session.forgetLocalTicket() }
            }
        } else if let ticket {
            switch ticket.phase {
            case .matched, .waitingForPhotographer, .waitingForCustomer:
                TicketMeetupView(ticket: ticket, myUid: myUid, sharing: workspace.locationSharing)
                    .safeAreaInset(edge: .bottom) { meetupBar(ticket) }
            case .shooting, .ended:
                TicketPhotoGridView(ticket: ticket, workspace: workspace)
                    .safeAreaInset(edge: .bottom) { photoBar(ticket) }
            case .cancelled:
                cancelledView(ticket)
            }
        } else if hasReceivedSnapshot {
            ContentUnavailableView {
                Label(session.isOnline ? "촬영 정보를 찾을 수 없습니다" : "오프라인입니다", systemImage: "questionmark.folder")
            } description: {
                Text(session.isOnline ? "취소됐거나 지워진 촬영입니다." : "연결되면 촬영 정보를 불러옵니다.")
            } actions: {
                Button("지도로 돌아가기") { session.forgetLocalTicket() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView("촬영 정보를 불러오는 중…")
        }
    }

    private func meetupBar(_ ticket: TicketRecord) -> some View {
        VStack(spacing: 8) {
            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if ticket.phase == .waitingForPhotographer {
                Text("작가도 시작을 누르면 촬영이 시작됩니다")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if ticket.phase == .waitingForCustomer {
                Text("작가가 시작을 눌렀습니다. 촬영 시작을 누르면 바로 시작됩니다")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if ticket.canCancel {
                    Button("취소", role: .destructive) { showsCancelConfirm = true }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)
                }
                if ticket.canStart(.customer) {
                    Button(action: startTicket) {
                        Group {
                            if isWorking {
                                ProgressView()
                            } else {
                                Text("촬영 시작")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                    .accessibilityIdentifier("customer.start")
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func photoBar(_ ticket: TicketRecord) -> some View {
        let canEnd = ticket.canEnd(.customer, at: now)
        if ticket.phase == .ended || canEnd || actionError != nil {
            VStack(spacing: 8) {
                if let actionError {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if ticket.phase == .ended {
                    Button("새 촬영 찾기") { session.forgetLocalTicket() }
                        .buttonStyle(.borderedProminent)
                } else if canEnd {
                    Text("작가가 응답하지 않으면 촬영을 종료할 수 있습니다")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("촬영 종료", role: .destructive) { showsEndConfirm = true }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)
                }
            }
            .padding()
            .background(.regularMaterial)
        }
    }

    private func cancelledView(_ ticket: TicketRecord) -> some View {
        ContentUnavailableView {
            Label("취소됐습니다", systemImage: "xmark.circle")
        } description: {
            Text(ticket.cancelledBy == myUid ? "촬영을 취소했습니다." : "작가가 촬영을 취소했습니다.")
        } actions: {
            Button("지도로 돌아가기") { session.forgetLocalTicket() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let ticket, ticket.phase == .shooting || ticket.phase == .ended {
            ToolbarItem(placement: .topBarTrailing) {
                Button("채팅", systemImage: "bubble.left.and.bubble.right") { showsChat = true }
            }
        }
    }

    private var chatSheet: some View {
        NavigationStack {
            TicketChatView(ticketId: ticketId, myUid: myUid, otherLabel: ticket?.photographerDisplayName ?? "작가")
                .navigationTitle("채팅")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { showsChat = false }
                    }
                }
        }
    }

    // MARK: - 리스너

    private func listen() async {
        loadError = nil
        do {
            for try await update in TicketService.ticket(ticketId) {
                latestTicket = update
                hasReceivedSnapshot = true
                if !isWorking {
                    ticket = update
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
        }
    }

    private func tickClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            now = Date()
        }
    }

    /// 끝나거나 취소되면 고객 잠금을 한 번만 푼다(실패는 무시). 취소는 다음 실행 때 다시 열리지 않게 저장값도 지운다.
    private func handlePhaseChange(_ phase: TicketPhase?) {
        switch phase {
        case .ended:
            releaseLockOnce()
        case .cancelled:
            releaseLockOnce()
            session.clearStoredTicket(ticketId)
        default:
            break
        }
    }

    private func releaseLockOnce() {
        guard !hasReleasedLock else { return }
        hasReleasedLock = true
        Task { try? await TicketService.releaseCustomerLock(uid: myUid) }
    }

    // MARK: - 쓰기

    private func startTicket() {
        perform("시작") { try await TicketService.markStarted(ticketId: ticketId, role: .customer) }
    }

    private func cancelTicket() {
        guard let ticket else { return }
        perform("취소") { try await TicketService.cancel(ticket: ticket, by: myUid) }
    }

    private func endTicket() {
        perform("종료") { try await TicketService.endAsCustomer(ticketId: ticketId) }
    }

    /// 오프라인이면 보내지 않고 안내한다. 성공이든 실패든 끝난 뒤에 가장 최근 스냅샷을 화면에 반영한다.
    private func perform(_ label: String, _ work: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        guard session.isOnline else {
            actionError = "인터넷 연결을 확인해 주세요."
            return
        }
        isWorking = true
        actionError = nil
        Task {
            do {
                try await work()
            } catch {
                actionError = "\(label)하지 못했습니다: \(error.localizedDescription)"
            }
            isWorking = false
            ticket = latestTicket
        }
    }
}
