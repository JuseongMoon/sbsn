import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

// MARK: - 촬영 가능 켜기·바꾸기(설계 2.3)

/// 촬영 가능 켜기 시트: 이동할 수 있는 거리(300m·500m·1km·2km, L11)와 끝나는 시각. 켠 채로 [변경]할 때도 같은 시트를 쓴다.
struct AvailabilitySheet: View {
    enum Mode {
        case turnOn
        case change
    }

    let mode: Mode
    let initial: LaunchPresencePublisher.Settings
    let onConfirm: (LaunchPresencePublisher.Settings) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var radius: Int64 = 1000
    @State private var hours: Double = 2
    @State private var customEnd = Date().addingTimeInterval(7200)
    @State private var usesCustomEnd = false

    static let hourOptions: [Double] = [1, 2, 4]

    var body: some View {
        NavigationStack {
            Form {
                Section("이동할 수 있는 거리") {
                    Picker("거리", selection: $radius) {
                        ForEach(LaunchMatch.radiusOptions, id: \.self) { Text(LaunchMatch.radiusLabel($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("availability.radius")
                }
                Section {
                    Picker("언제까지", selection: Binding(get: { usesCustomEnd ? -1 : hours },
                                                       set: { value in
                                                           if value < 0 { usesCustomEnd = true } else { usesCustomEnd = false; hours = value }
                                                       })) {
                        ForEach(Self.hourOptions, id: \.self) { Text("\(Int($0))시간 뒤").tag($0) }
                        Text("직접 고르기").tag(-1.0)
                    }
                    .accessibilityIdentifier("availability.until")
                    if usesCustomEnd {
                        DatePicker("끝나는 시각", selection: $customEnd, in: Date().addingTimeInterval(600)...,
                                   displayedComponents: [.date, .hourAndMinute])
                    }
                    LabeledContent("끝나는 시각", value: LaunchTime.dayClock(endsAt))
                } header: {
                    Text("언제까지")
                } footer: {
                    Text("끝나는 시각이 지나면 촬영 가능이 저절로 꺼져요. 고객 지도에는 내 위치가 200m 칸 안 임의 지점으로 보여요.")
                }
            }
            .navigationTitle(mode == .turnOn ? "촬영 가능 켜기" : "촬영 가능 바꾸기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .turnOn ? "켜기" : "바꾸기") {
                        if !usesCustomEnd { UserDefaults.standard.set(hours, forKey: PhotographerSession.lastHoursKey) }
                        onConfirm(.init(radiusMeters: radius, endsAt: endsAt, breakReason: initial.breakReason))
                        dismiss()
                    }
                    .accessibilityIdentifier(mode == .turnOn ? "availability.on" : "availability.update")
                }
            }
        }
        .onAppear {
            radius = initial.radiusMeters
            customEnd = initial.endsAt
            let remaining = initial.endsAt.timeIntervalSinceNow / 3600
            if let match = Self.hourOptions.first(where: { abs($0 - remaining) < 0.05 }) {
                hours = match
            } else if mode == .change {
                usesCustomEnd = true
            }
        }
    }

    private var endsAt: Date {
        usesCustomEnd ? customEnd : Date().addingTimeInterval(hours * 3600)
    }
}

/// 휴게 사유 고르기(계약 `breakReason` 넷). 휴게 중에는 새 신청이 닫히고 채팅은 받는다(L12).
struct BreakReasonDialog: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (LaunchMatch.BreakReason) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("휴게 사유", isPresented: $isPresented, titleVisibility: .visible) {
            ForEach(LaunchMatch.BreakReason.allCases) { reason in
                Button(reason.label) { onPick(reason) }
                    .accessibilityIdentifier("break.reason.\(reason.rawValue)")
            }
            Button("돌아가기", role: .cancel) {}
        } message: {
            Text("휴게 중에는 새 신청을 받지 않아요. 채팅은 받을 수 있어요.")
        }
    }
}

// MARK: - 새 신청(설계 2.3)

/// 새 신청 카드: 고객 닉네임·시간·마감, 마지막 메시지 없이 [대화 보기] [거절] [수락].
/// [거절]은 사유 보기를 띄우고 보기를 누르면 바로 거절된다(D066 S3). [수락]은 확인 없이 보낸다(5분 안).
struct PhotographerRequestCard: View {
    let request: LaunchMatch.Request
    /// 홈에서는 그 대화방을 연다. 대화방 안에서는 nil(단추를 숨긴다).
    var onOpenRoom: (() -> Void)?
    @State private var choosesDecline = false
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                HStack {
                    Text("\(request.customerNickname ?? "고객") · \(request.minutes)분")
                        .font(.headline)
                    Spacer()
                    Text(request.isExpiringSoon(now: context.date) ? "곧 만료" : "\(LaunchTime.clock(request.expiresAt))까지")
                        .font(.subheadline)
                        .foregroundStyle(request.isExpiringSoon(now: context.date) ? Color.orange : Color.secondary)
                        .accessibilityIdentifier("request.deadline")
                }
            }
            HStack {
                if let onOpenRoom {
                    Button("대화 보기", action: onOpenRoom)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("request.openRoom")
                }
                Spacer()
                Button("거절") { choosesDecline = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("request.decline")
                Button("수락") { Task { await answer(.accept) } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("request.accept")
            }
            .disabled(isWorking)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("request.error")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("request.card")
        .confirmationDialog("거절 사유(고객에게는 분류만 보여요)", isPresented: $choosesDecline, titleVisibility: .visible) {
            ForEach(LaunchMatch.DeclineReason.allCases) { reason in
                Button(reason.label) { Task { await answer(.decline(reason)) } }
                    .accessibilityIdentifier("decline.reason.\(reason.rawValue)")
            }
            Button("돌아가기", role: .cancel) {}
        }
        .buttonStyle(.borderless)
    }

    private func answer(_ answer: LaunchMatchService.RequestAnswer) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await LaunchMatchService.respond(requestId: request.id, answer)
            switch result.status {
            case "accepted", "declined": error = nil
            case "expired": error = "이미 만료된 신청이에요"
            case "auto_declined": error = "다른 신청을 이미 수락했어요"
            case "cancelled": error = "고객이 신청을 취소했어요"
            default: error = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 채팅 탭

struct PhotographerChatTab: View {
    @Environment(PhotographerLaunchModel.self) private var launch

    var body: some View {
        @Bindable var launch = launch
        NavigationStack(path: $launch.chatPath) {
            Group {
                if launch.rooms.isEmpty {
                    ContentUnavailableView("아직 대화가 없습니다", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("고객이 지도에서 대화를 걸면 여기에 보여요."))
                } else {
                    List(launch.rooms) { room in
                        NavigationLink(value: room.id) {
                            PhotographerChatRow(room: room, unread: launch.unread[room.id] ?? 0,
                                                waiting: launch.waitingRequests().first { $0.roomId == room.id },
                                                ticket: launch.activeTicket?.roomId == room.id ? launch.activeTicket : nil)
                        }
                        .accessibilityIdentifier("chat.row")
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("채팅")
            .navigationDestination(for: String.self) { roomId in
                PhotographerChatRoomScreen(roomId: roomId)
            }
        }
    }
}

struct PhotographerChatRow: View {
    let room: LaunchMatch.Room
    let unread: Int
    let waiting: LaunchMatch.Request?
    let ticket: LaunchMatch.Ticket?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.counterpartName(of: room.photographerUid)).font(.headline)
                if let ticket {
                    Text(ticket.status == .shooting ? "촬영 중" : "시작 대기").font(.caption).foregroundStyle(Color.accentColor)
                } else if let waiting {
                    Text("신청 대기 · \(LaunchTime.clock(waiting.expiresAt))까지").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let at = room.lastMessageAt ?? room.activityAt {
                    Text(LaunchTime.clock(at)).font(.caption).foregroundStyle(.secondary)
                }
                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("chat.unread")
                }
            }
        }
    }
}

/// 작가 대화방: 방 위에 이 방의 신청 카드(고정)·상호 취소 동의 카드·진행 중 촬영 안내
struct PhotographerChatRoomScreen: View {
    let roomId: String
    @Environment(PhotographerLaunchModel.self) private var launch
    @State private var roomInfo: LaunchMatch.Room?

    var body: some View {
        let room = roomInfo ?? launch.room(roomId)
        let title = room?.counterpartName(of: launch.uid ?? "") ?? "고객"
        LaunchChatRoomView(roomId: roomId, myUid: launch.uid ?? "", counterpartName: title) {
            if let ticket = launch.mutualCancelAwaitingAnswer(roomId: roomId) {
                LaunchMutualCancelCard(ticket: ticket)
            }
            ForEach(launch.waitingRequests().filter { $0.roomId == roomId }) { request in
                PhotographerRequestCard(request: request)
                    .padding(12)
                    .background(.thinMaterial)
            }
            if let ticket = launch.activeTicket, ticket.roomId == roomId {
                Text(ticket.status == .shooting ? "촬영 중이에요 · 촬영 탭에서 보세요" : "매칭됐어요 · 촬영 탭에서 시작을 눌러 주세요")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial)
            }
        } bottom: {
            EmptyView()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: roomId) {
            do {
                for try await value in LaunchMatchService.room(roomId: roomId) { roomInfo = value }
            } catch {}
        }
    }
}

// MARK: - 티켓(설계 2.5)

/// 작가 티켓 화면: 시작 대기(위치·시작·취소) → 촬영 중(남은 분, 연장 동의 60초, [촬영 종료]). 자동 종료 없음(L21).
struct PhotographerLaunchTicketView: View {
    let ticket: LaunchMatch.Ticket
    @Environment(PhotographerLaunchModel.self) private var launch
    @Environment(PhotographerSession.self) private var session
    @State private var showsCancel = false
    @State private var showsMap = false
    @State private var confirmsStart = false
    @State private var confirmsEnd = false
    @State private var isWorking = false
    @State private var error: String?
    @State private var others: [LocationSample] = []
    @State private var pendingExtension: LaunchMatch.Extension?

    private var myUid: String { launch.uid ?? "" }
    private var name: String { launch.room(ticket.roomId)?.counterpartName(of: myUid) ?? "고객" }

    var body: some View {
        LaunchChatRoomView(roomId: ticket.roomId, myUid: myUid, counterpartName: name) {
            if let pendingExtension, pendingExtension.isWaiting(now: Date()) {
                extensionCard(pendingExtension)
            }
        } bottom: {
            bar
        }
        .navigationTitle("\(name) · \(ticket.status == .shooting ? "촬영 중" : "시작 대기")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if ticket.status == .matched {
                    Button { showsMap = true } label: { Label("위치", systemImage: "map") }
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
        .sheet(isPresented: $showsCancel) { LaunchCancelSheet(ticketId: ticket.id) }
        .sheet(isPresented: $showsMap) { MeetupMapSheet(participants: participants, otherLabel: name) }
        .task(id: "\(ticket.id):\(ticket.status.rawValue)") { await listenToCustomerLocation() }
        .task(id: ticket.pendingExtensionId) { await followExtension() }
    }

    @ViewBuilder
    private var bar: some View {
        VStack(spacing: 10) {
            switch ticket.status {
            case .matched:
                if ticket.hasConfirmedStart(.photographer) {
                    Text("고객이 시작을 누르면 촬영이 시작돼요").font(.subheadline).accessibilityIdentifier("ticket.waitingOther")
                } else {
                    if ticket.hasConfirmedStart(.customer) {
                        Text("고객이 시작을 눌렀어요").font(.subheadline).accessibilityIdentifier("ticket.otherStarted")
                    }
                    Button { confirmsStart = true } label: { Text("촬영 시작").frame(maxWidth: .infinity) }
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
            case .shooting:
                LaunchRemainingTime(ticket: ticket)
                HStack {
                    Text("남은 연장 \(ticket.remainingExtensionMinutes)분").font(.caption).foregroundStyle(.secondary)
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
                    // 4단계에서 "지금 끝내면 남은 시간만큼 고객에게 환불됩니다"를 더한다(L42).
                    Text("끝내면 다시 시작할 수 없어요. 끝난 뒤 사진을 골라 올려 주세요.")
                }
            case .ended, .cancelled:
                EmptyView()
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("ticket.error")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    private func extensionCard(_ request: LaunchMatch.Extension) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("고객이 \(request.minutes)분 연장을 원해요").font(.subheadline.bold())
            Text("\(LaunchTime.clock(request.expiresAt))까지 답해 주세요").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("거절") { Task { await answerExtension(request, accept: false) } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("extension.decline")
                Button("동의") { Task { await answerExtension(request, accept: true) } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("extension.accept")
            }
            .disabled(isWorking)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("extension.card")
    }

    private var participants: [ParticipantsMapView.Participant] {
        var result: [ParticipantsMapView.Participant] = []
        if let me = session.location.latest {
            result.append(.init(id: myUid, label: "나", point: me, updatedAt: nil, isMe: true))
        }
        if let sample = others.first(where: { $0.uid == ticket.customerUid }) {
            result.append(.init(id: sample.uid, label: name, point: sample.point, updatedAt: sample.updatedAt, isMe: false))
        }
        return result
    }

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

    private func answerExtension(_ request: LaunchMatch.Extension, accept: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let status = try await LaunchMatchService.respondExtension(ticketId: ticket.id, extensionId: request.id, accept: accept)
            if status == "expired" { error = "1분이 지나 연장 요청이 만료됐어요" }
            pendingExtension = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func followExtension() async {
        guard let id = ticket.pendingExtensionId else {
            pendingExtension = nil
            return
        }
        do {
            for try await value in LaunchMatchService.extensionRequest(ticketId: ticket.id, extensionId: id) {
                pendingExtension = value
            }
        } catch {}
    }

    private func listenToCustomerLocation() async {
        guard ticket.status == .matched else { return }
        do {
            for try await samples in TicketLocationService.locations(ticketId: ticket.id, launch: true) {
                others = samples.filter { $0.uid != myUid }
            }
        } catch {}
    }
}
