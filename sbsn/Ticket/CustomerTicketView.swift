import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 활성 티켓 화면. 단계(`phase`)에 따라 만남 화면·촬영 중 화면·사진 화면(고르는 중 → 갤러리)·취소 안내를 보여 준다.
///
/// 티켓 리스너는 `TicketWorkspace`가 갖고 뿌리 화면의 `TicketBackgroundWork`가 돌린다(다른 탭에 있어도 이어지게).
/// 시작·취소·종료 같은 쓰기는 서버 커밋이 끝난 뒤에만 화면을 바꾼다: 쓰는 동안에는 쓰기 직전 티켓을 보여 주고
/// 끝난 뒤 가장 최근 스냅샷으로 돌아간다(리스너는 로컬 쓰기를 추정값으로 먼저 주기 때문).
struct CustomerTicketView: View {
    let workspace: TicketWorkspace

    @Environment(CustomerSession.self) private var session
    /// 쓰는 동안 화면에 고정해 두는 티켓
    @State private var ticketBeforeWrite: TicketRecord?
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var showsPayment = false
    /// 만나기 화면 "…" 메뉴에서 연 예시 화면
    @State private var openedFeature: PlannedFeature?
    /// 채팅 "…" 메뉴의 신고·차단(예시 시트, D032). 만나기 화면과 채팅 시트에서 따로 띄운다.
    @State private var showsMeetupReport = false
    @State private var showsMeetupBlock = false
    @State private var showsChatReport = false
    @State private var showsChatBlock = false
    @State private var showsCancelConfirm = false
    @State private var showsEndConfirm = false
    @State private var showsChat = false
    /// `canEnd`와 작가 응답 없음 안내는 시각에 따라 달라지므로 주기적으로 갱신한다.
    @State private var now = Date()

    private var ticketId: String { workspace.ticketId }
    private var myUid: String { workspace.myUid }
    private var ticket: TicketRecord? { isWorking ? ticketBeforeWrite : workspace.latestTicket }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(ticket?.photographerDisplayName ?? "촬영")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .navigationDestination(item: $openedFeature) { CustomerSampleScreen($0) }
                .task { await tickClock() }
                .task { await CustomerAppDelegate.requestAuthorizationIfNeeded() }
                .sheet(isPresented: $showsChat) { chatSheet }
                .sampleChatSafetySheets(target: chatPartner, cancelsShoot: ticket?.canCancel ?? false,
                                        showsReport: $showsMeetupReport, showsBlock: $showsMeetupBlock)
                .sheet(isPresented: $showsPayment) {
                    PaymentPlaceholderSheet(onContinue: {
                        showsPayment = false
                        startTicket()
                    }, onClose: { showsPayment = false })
                }
                .confirmationDialog("촬영을 취소할까요?", isPresented: $showsCancelConfirm, titleVisibility: .visible) {
                    Button("촬영 취소", role: .destructive, action: cancelTicket)
                    Button("돌아가기", role: .cancel) {}
                }
                .confirmationDialog("촬영을 종료할까요?", isPresented: $showsEndConfirm, titleVisibility: .visible) {
                    Button("촬영 종료", role: .destructive, action: endTicket)
                    Button("돌아가기", role: .cancel) {}
                } message: {
                    Text("종료하면 작가가 사진을 골라 공개할 수 있습니다. 공개되면 알림으로 알려 드립니다.")
                }
        }
    }

    // MARK: - 단계별 본문

    @ViewBuilder
    private var content: some View {
        if let loadError = workspace.loadError {
            ContentUnavailableView {
                Label("촬영 정보를 불러오지 못했습니다", systemImage: "wifi.exclamationmark")
            } description: {
                Text(loadError)
            } actions: {
                Button("다시 시도") { workspace.listenerGeneration += 1 }
                    .buttonStyle(.borderedProminent)
                Button("지도로 돌아가기") { session.forgetLocalTicket() }
            }
        } else if let ticket, !ticket.isCurated {
            // 전환 전에 만든 실시간 FTP 티켓(D039). 이 버전은 사진을 보여 주지 못한다.
            ContentUnavailableView {
                Label("이전 방식 촬영입니다", systemImage: "exclamationmark.triangle")
            } description: {
                Text("이 촬영은 이 버전에서 이어 갈 수 없습니다.")
            } actions: {
                Button("지도로 돌아가기") { session.forgetLocalTicket() }
                    .buttonStyle(.borderedProminent)
            }
        } else if let ticket {
            switch ticket.phase {
            case .matched, .waitingForPhotographer, .waitingForCustomer:
                TicketMeetupView(ticket: ticket, myUid: myUid, sharing: workspace.locationSharing, now: now)
                    .safeAreaInset(edge: .bottom) { meetupBar(ticket) }
            case .shooting:
                CustomerShootingView(ticket: ticket)
                    .safeAreaInset(edge: .bottom) { photoBar(ticket) }
            case .ended:
                GalleryScreen(ticketID: ticket.id)
                    .safeAreaInset(edge: .bottom) { photoBar(ticket) }
            case .cancelled:
                cancelledView(ticket)
            }
        } else if workspace.hasReceivedSnapshot {
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
                    // 촬영료 결제 자리 화면을 먼저 띄운다. 그 화면의 "결제 없이 계속"이 시작을 기록한다(결제 없음, D003).
                    Button { showsPayment = true } label: {
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
                    // 사진은 내 사진 탭에 남는다(공개 전이어도 공개되면 알림이 온다).
                    HStack(spacing: 12) {
                        Button("새 촬영 찾기") { session.forgetLocalTicket() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("customer.newShoot")
                        NavigationLink {
                            CustomerSampleScreen(CustomerFeatures.review)
                        } label: {
                            Text("리뷰 남기기")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("planned.review")
                    }
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
            .frame(maxWidth: .infinity)
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
        if let ticket, ticket.canCancel {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("더 보기", systemImage: "ellipsis.circle") {
                    Button(CustomerFeatures.briefing.title, systemImage: CustomerFeatures.briefing.systemImage) {
                        openedFeature = CustomerFeatures.briefing
                    }
                    Button(CustomerFeatures.safety.title, systemImage: CustomerFeatures.safety.systemImage) {
                        openedFeature = CustomerFeatures.safety
                    }
                    Divider()
                    SampleChatSafetyMenuItems(showsReport: $showsMeetupReport, showsBlock: $showsMeetupBlock)
                }
                .accessibilityIdentifier("customer.meetup.more")
            }
        }
    }

    private var chatSheet: some View {
        NavigationStack {
            TicketChatView(ticketId: ticketId, myUid: myUid, otherLabel: ticket?.photographerDisplayName ?? "작가")
                .navigationTitle("채팅")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu("더 보기", systemImage: "ellipsis.circle") {
                            SampleChatSafetyMenuItems(showsReport: $showsChatReport, showsBlock: $showsChatBlock)
                        }
                        .accessibilityIdentifier("chat.more")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { showsChat = false }
                    }
                }
                .sampleChatSafetySheets(target: chatPartner, cancelsShoot: false,
                                        showsReport: $showsChatReport, showsBlock: $showsChatBlock)
        }
    }

    private var chatPartner: String { ticket?.photographerDisplayName ?? "작가" }

    private func tickClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            now = Date()
        }
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
        guard let ticket else { return }
        perform("종료") { try await TicketService.endAsCustomer(ticket: ticket) }
    }

    /// 오프라인이면 보내지 않고 안내한다. 성공이든 실패든 끝난 뒤에 가장 최근 스냅샷을 화면에 반영한다.
    private func perform(_ label: String, _ work: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        guard session.isOnline else {
            actionError = "인터넷 연결을 확인해 주세요."
            return
        }
        ticketBeforeWrite = workspace.latestTicket
        isWorking = true
        actionError = nil
        Task {
            do {
                try await work()
            } catch {
                actionError = "\(label)하지 못했습니다: \(error.localizedDescription)"
            }
            isWorking = false
            ticketBeforeWrite = nil
        }
    }
}
