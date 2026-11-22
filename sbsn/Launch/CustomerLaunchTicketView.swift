import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 출시 2단계 티켓 화면(고객, 설계 2.5): 시작 대기 → 촬영 중. 촬영 탭이 진행 중인 티켓이 있으면 이 화면이 된다.
///
/// - 시작 대기: 대화 + 위치(🗺, 매칭~시작 10초 간격, L13·L14) + [촬영 시작](둘 다 눌러야 시작). 취소는 … 메뉴 안(사유 시트).
/// - 촬영 중: 남은 분, [5분 연장 신청](작가가 60초 안에 동의, 합계 30분), [촬영 종료](누구든 혼자 끝냄, 자동 종료 없음 L21).
/// - 종료·취소되면 서버 리스너가 티켓을 내려 촬영 탭이 지도로 돌아간다. 결과는 서버 시스템 메시지로 대화방에 남는다.
struct CustomerLaunchTicketView: View {
    let ticket: LaunchMatch.Ticket
    @Environment(CustomerLaunchModel.self) private var launch
    @State private var sharing: TicketLocationSharing?
    @State private var showsMap = false
    @State private var showsCancel = false
    @State private var confirmsStart = false
    @State private var confirmsEnd = false
    @State private var isWorking = false
    @State private var error: String?
    @State private var extensionRequest: LaunchMatch.Extension?
    @State private var extensionNotice: String?
    @State private var extensionRequestId = LaunchChatRequestID.make()

    private var myUid: String { launch.uid ?? "" }
    private var name: String { launch.room(ticket.roomId)?.counterpartName(of: myUid) ?? "작가" }

    var body: some View {
        NavigationStack {
            LaunchChatRoomView(roomId: ticket.roomId, myUid: myUid, counterpartName: name) {
                EmptyView()
            } bottom: {
                ticketBar
            }
            .navigationTitle("\(name) · \(ticket.status == .shooting ? "촬영 중" : "시작 대기")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showsCancel) {
                LaunchCancelSheet(ticketId: ticket.id)
            }
            .sheet(isPresented: $showsMap) {
                MeetupMapSheet(participants: participants, otherLabel: name)
            }
        }
        .task(id: "\(ticket.id):\(ticket.status.rawValue)") { await shareLocationWhileMatched() }
        .task(id: extensionRequest?.id) { await followExtension() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if ticket.status == .matched {
                Button {
                    showsMap = true
                } label: {
                    Label("위치", systemImage: "map")
                }
                .accessibilityIdentifier("ticket.map")
                Menu {
                    Button("촬영 취소", role: .destructive) { showsCancel = true }
                        .accessibilityIdentifier("ticket.cancel")
                } label: {
                    Label("더 보기", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("ticket.menu")
            }
        }
    }

    // MARK: - 아래 막대

    @ViewBuilder
    private var ticketBar: some View {
        VStack(spacing: 10) {
            switch ticket.status {
            case .matched:
                matchedBar
            case .shooting:
                shootingBar
            case .ended, .cancelled:
                EmptyView()
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("ticket.error")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    @ViewBuilder
    private var matchedBar: some View {
        if ticket.hasConfirmedStart(.customer) {
            Text("작가가 시작을 누르면 촬영이 시작돼요")
                .font(.subheadline)
                .accessibilityIdentifier("ticket.waitingOther")
        } else {
            if ticket.hasConfirmedStart(.photographer) {
                Text("작가가 시작을 눌렀어요")
                    .font(.subheadline)
                    .accessibilityIdentifier("ticket.otherStarted")
            }
            Button {
                confirmsStart = true
            } label: {
                Text("촬영 시작").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .accessibilityIdentifier("ticket.start")
            .confirmationDialog("만나서 촬영 안내를 마쳤나요?", isPresented: $confirmsStart, titleVisibility: .visible) {
                Button("촬영 시작") { Task { await run(.start) } }
                    .accessibilityIdentifier("ticket.start.confirm")
                Button("돌아가기", role: .cancel) {}
            } message: {
                Text("둘 다 시작을 누르면 \(ticket.minutes)분 촬영이 시작돼요.")
            }
        }
    }

    @ViewBuilder
    private var shootingBar: some View {
        LaunchRemainingTime(ticket: ticket)
        if let extensionNotice {
            Text(extensionNotice)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ticket.extensionNotice")
        }
        HStack {
            if extensionRequest?.isWaiting(now: Date()) == true {
                Label("작가 동의를 기다리는 중", systemImage: "hourglass")
                    .font(.footnote)
                    .accessibilityIdentifier("ticket.extensionWaiting")
            } else if ticket.canRequestExtension {
                Button("5분 연장 신청") { Task { await requestExtension() } }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                    .accessibilityIdentifier("ticket.extend")
                Text("남은 연장 \(ticket.remainingExtensionMinutes)분")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("촬영 종료", role: .destructive) { confirmsEnd = true }
                .buttonStyle(.bordered)
                .disabled(isWorking)
                .accessibilityIdentifier("ticket.end")
        }
        .confirmationDialog("촬영을 끝낼까요?", isPresented: $confirmsEnd, titleVisibility: .visible) {
            Button("촬영 종료", role: .destructive) { Task { await run(.end) } }
                .accessibilityIdentifier("ticket.end.confirm")
            Button("돌아가기", role: .cancel) {}
        } message: {
            // 4단계에서 "지금 끝내면 남은 시간은 환불되지 않습니다"를 더한다(L42).
            Text("끝내면 다시 시작할 수 없어요. 사진은 작가가 고른 뒤 갤러리에 올라와요.")
        }
    }

    // MARK: - 동작

    private func run(_ action: LaunchMatchService.ShootingAction) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await LaunchMatchService.updateShooting(ticketId: ticket.id, action)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func requestExtension() async {
        isWorking = true
        defer { isWorking = false }
        do {
            extensionRequest = try await LaunchMatchService.requestExtension(ticketId: ticket.id, clientRequestId: extensionRequestId)
            extensionRequestId = LaunchChatRequestID.make()
            extensionNotice = nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func followExtension() async {
        guard let id = extensionRequest?.id else { return }
        do {
            for try await value in LaunchMatchService.extensionRequest(ticketId: ticket.id, extensionId: id) {
                guard let value else { continue }
                extensionRequest = value
                switch value.status {
                case .pending: continue
                case .accepted: extensionNotice = "5분 연장됐어요"
                case .declined, .expired, .cancelled: extensionNotice = "작가가 연장을 받지 않았어요"
                }
                return
            }
        } catch {}
    }

    // MARK: - 위치(매칭~시작)

    private var participants: [ParticipantsMapView.Participant] {
        guard let sharing else { return [] }
        var result: [ParticipantsMapView.Participant] = []
        if let myPoint = sharing.myPoint {
            result.append(.init(id: myUid, label: "나", point: myPoint, updatedAt: nil, isMe: true))
        }
        if let sample = sharing.others.first(where: { $0.uid == ticket.photographerUid }) {
            result.append(.init(id: sample.uid, label: name, point: sample.point, updatedAt: sample.updatedAt, isMe: false))
        }
        return result
    }

    private func shareLocationWhileMatched() async {
        guard ticket.status == .matched, !myUid.isEmpty else {
            sharing = nil
            return
        }
        let sharing = TicketLocationSharing(ticketId: ticket.id, myUid: myUid, launch: true)
        self.sharing = sharing
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await sharing.listenToOthers() }
            group.addTask { await sharing.shareMyLocation() }
        }
    }
}
