import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 진행 중인 촬영 하나. 만나기 전에는 지도·채팅·시작, 촬영 중에는 10분 타이머·채팅·종료를 보여 준다.
/// 끝나면 세션이 공개 대기로 옮기고 화면은 사진 고르기로 간다(`GalleryRouteView`).
struct PhotographerTicketView: View {
    @Environment(PhotographerSession.self) private var session
    @State private var locations: [LocationSample] = []
    @State private var showsChat = false
    @State private var confirmsCancel = false
    @State private var confirmsEnd = false
    @State private var isWorking = false
    /// "…" 메뉴에서 연 예시 화면
    @State private var openedFeature: PlannedFeature?
    /// 채팅 "…" 메뉴의 신고·차단(예시 시트, D032). 화면과 채팅 시트에서 따로 띄운다.
    @State private var showsReport = false
    @State private var showsBlock = false
    @State private var showsChatReport = false
    @State private var showsChatBlock = false

    var body: some View {
        Group {
            if let ticket = session.ticket {
                content(for: ticket)
                    .task(id: ticket.id) {
                        do {
                            for try await update in TicketLocationService.locations(ticketId: ticket.id) {
                                locations = update
                            }
                        } catch {}
                    }
            } else {
                ContentUnavailableView("진행 중인 촬영이 없습니다", systemImage: "camera")
            }
        }
        .navigationDestination(item: $openedFeature) { PhotographerSampleScreen($0) }
        .sampleChatSafetySheets(target: "고객", cancelsShoot: session.ticket?.canCancel ?? false,
                                showsReport: $showsReport, showsBlock: $showsBlock)
        .sheet(isPresented: $showsChat) {
            if let ticket = session.ticket, let uid = session.uid {
                NavigationStack {
                    TicketChatView(ticketId: ticket.id, myUid: uid, otherLabel: "고객")
                        .navigationTitle("고객과 채팅")
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
                        .sampleChatSafetySheets(target: "고객", cancelsShoot: false,
                                                showsReport: $showsChatReport, showsBlock: $showsChatBlock)
                }
            }
        }
    }

    @ViewBuilder
    private func content(for ticket: TicketRecord) -> some View {
        if !ticket.isCurated {
            // 전환 전에 만든 실시간 FTP 티켓(D039). 이 버전은 이어 가지 못하고 끝내거나 취소만 한다.
            legacyTicket(ticket)
        } else {
            switch ticket.phase {
            case .matched, .waitingForCustomer, .waitingForPhotographer:
                meeting(ticket)
            case .shooting, .ended:
                ShootingTimerView(ticket: ticket)
                    .safeAreaInset(edge: .bottom) {
                        shootingBar(ticket)
                    }
                    .navigationTitle("촬영 중")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        Button("채팅", systemImage: "bubble.left.and.bubble.right") { showsChat = true }
                            .accessibilityIdentifier("photographer.chat")
                        Menu("더 보기", systemImage: "ellipsis.circle") { plannedMenuItems }
                            .accessibilityIdentifier("photographer.more")
                    }
            case .cancelled:
                cancelled(ticket)
            }
        }
    }

    private func legacyTicket(_ ticket: TicketRecord) -> some View {
        ContentUnavailableView {
            Label("이전 방식 촬영입니다", systemImage: "exclamationmark.triangle")
        } description: {
            Text("실시간 FTP로 시작한 촬영은 이 버전에서 이어 갈 수 없습니다. 끝내거나 취소해 주세요.")
        } actions: {
            if ticket.canCancel {
                Button("촬영 취소", role: .destructive) { perform { await session.cancelMatch() } }
            } else if ticket.canEnd(.photographer) {
                Button("촬영 종료", role: .destructive) { perform { await session.endShooting() } }
            }
        }
    }

    private func cancelled(_ ticket: TicketRecord) -> some View {
        ContentUnavailableView("취소된 촬영입니다", systemImage: "xmark.circle",
                               description: Text(ticket.cancelledBy == ticket.customerUid ? "고객이 취소했습니다." : "취소했습니다."))
    }

    private func meeting(_ ticket: TicketRecord) -> some View {
        VStack(spacing: 0) {
            ParticipantsMapView(participants: participants(ticket))
                .frame(height: 240)
            TicketChatView(ticketId: ticket.id, myUid: ticket.photographerUid, otherLabel: "고객")
            VStack(spacing: 8) {
                Text(meetingStatus(ticket))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("취소", role: .destructive) { confirmsCancel = true }
                        .buttonStyle(.bordered)
                        .disabled(!ticket.canCancel || isWorking)
                    Button {
                        perform { await session.markStarted() }
                    } label: {
                        Text(ticket.photographerStartedAt == nil ? "촬영 시작" : "고객을 기다리는 중")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ticket.canStart(.photographer) || isWorking)
                    .accessibilityIdentifier("photographer.start")
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("고객 만나기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu("더 보기", systemImage: "ellipsis.circle") { plannedMenuItems }
                .accessibilityIdentifier("photographer.more")
        }
        .confirmationDialog("이 촬영을 취소할까요?", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("촬영 취소", role: .destructive) {
                perform { await session.cancelMatch() }
            }
        }
    }

    /// "…" 메뉴의 예시 화면 항목과 채팅 신고·차단(만나기·촬영 화면 공통)
    @ViewBuilder
    private var plannedMenuItems: some View {
        Button(PhotographerFeatures.customerBrief.title, systemImage: PhotographerFeatures.customerBrief.systemImage) {
            openedFeature = PhotographerFeatures.customerBrief
        }
        Button(PhotographerFeatures.safety.title, systemImage: PhotographerFeatures.safety.systemImage) {
            openedFeature = PhotographerFeatures.safety
        }
        Divider()
        SampleChatSafetyMenuItems(showsReport: $showsReport, showsBlock: $showsBlock)
    }

    private func shootingBar(_ ticket: TicketRecord) -> some View {
        VStack(spacing: 6) {
            if ticket.phase == .ended {
                ProgressView("사진 고르기로 넘어가는 중…")
            } else {
                Button("촬영 종료", role: .destructive) { confirmsEnd = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                    .accessibilityIdentifier("photographer.end")
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .confirmationDialog("촬영을 끝낼까요?", isPresented: $confirmsEnd, titleVisibility: .visible) {
            Button("촬영 종료", role: .destructive) {
                perform { await session.endShooting() }
            }
        } message: {
            Text("끝나면 카메라 사진을 폰으로 옮겨 5~8장을 골라 공개합니다. 고르는 동안에도 다음 촬영을 받을 수 있습니다.")
        }
    }

    private func participants(_ ticket: TicketRecord) -> [ParticipantsMapView.Participant] {
        locations.map { sample in
            ParticipantsMapView.Participant(id: sample.uid, label: sample.uid == ticket.photographerUid ? "나" : "고객",
                                            point: sample.point, updatedAt: sample.updatedAt, isMe: sample.uid == ticket.photographerUid)
        }
    }

    private func meetingStatus(_ ticket: TicketRecord) -> String {
        switch ticket.phase {
        case .matched: "채팅으로 만날 곳을 정하고, 만나서 촬영 안내를 한 뒤 둘 다 시작을 누르세요."
        case .waitingForPhotographer: "고객이 시작을 눌렀습니다. 준비되면 시작을 누르세요."
        case .waitingForCustomer: "고객이 시작을 누르면 촬영이 시작됩니다."
        default: ""
        }
    }

    private func perform(_ action: @escaping () async -> Void) {
        isWorking = true
        Task {
            await action()
            isWorking = false
        }
    }
}
