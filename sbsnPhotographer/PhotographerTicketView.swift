import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 매칭된 촬영 하나. 만나기 전에는 지도·채팅·시작, 촬영 중에는 카메라 수신 화면, 끝나면 전달 상태를 보여 준다.
struct PhotographerTicketView: View {
    @Environment(PhotographerSession.self) private var session
    @State private var locations: [LocationSample] = []
    @State private var showsChat = false
    @State private var confirmsCancel = false
    @State private var confirmsEnd = false
    @State private var isWorking = false

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
        .sheet(isPresented: $showsChat) {
            if let ticket = session.ticket, let uid = session.uid {
                NavigationStack {
                    TicketChatView(ticketId: ticket.id, myUid: uid, otherLabel: "고객")
                        .navigationTitle("고객과 채팅")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            Button("닫기") { showsChat = false }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func content(for ticket: TicketRecord) -> some View {
        switch ticket.phase {
        case .matched, .waitingForCustomer, .waitingForPhotographer:
            meeting(ticket)
        case .shooting, .ended:
            if let delivery = session.delivery {
                CameraTransferTestView(model: delivery)
                    .safeAreaInset(edge: .bottom) {
                        shootingBar(ticket)
                    }
                    .toolbar {
                        Button("채팅", systemImage: "bubble.left.and.bubble.right") { showsChat = true }
                    }
            } else {
                ContentUnavailableView("전달이 끝났습니다", systemImage: "checkmark.circle")
            }
        case .cancelled:
            ContentUnavailableView("취소된 촬영입니다", systemImage: "xmark.circle",
                                   description: Text(ticket.cancelledBy == ticket.customerUid ? "고객이 취소했습니다." : "취소했습니다."))
        }
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
        .confirmationDialog("이 촬영을 취소할까요?", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("촬영 취소", role: .destructive) {
                perform { await session.cancelMatch() }
            }
        }
    }

    private func shootingBar(_ ticket: TicketRecord) -> some View {
        VStack(spacing: 6) {
            if ticket.phase == .ended {
                Text("촬영이 끝났습니다. 고객이 산 사진과 미리 올리는 사진을 마저 올립니다.")
                    .font(.footnote)
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
            Text("카메라 수신을 멈춥니다. 이미 받은 사진은 계속 고객에게 넘깁니다.")
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
