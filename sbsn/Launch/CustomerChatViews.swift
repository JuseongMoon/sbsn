import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// "채팅" 탭(D066 S1): 작가마다 방 하나, 최근 활동 순 20개. 익명이면 로그인을 먼저 권한다(L04).
struct CustomerChatTab: View {
    @Environment(CustomerSession.self) private var session
    @Environment(CustomerLaunchModel.self) private var launch
    @State private var showsSignIn = false
    @AppStorage("SBSNLaunchNickname") private var nickname = ""

    var body: some View {
        @Bindable var launch = launch
        NavigationStack(path: $launch.chatPath) {
            Group {
                if launch.uid == nil {
                    ContentUnavailableView {
                        Label("로그인하면 작가와 대화할 수 있습니다", systemImage: "bubble.left.and.bubble.right")
                    } actions: {
                        Button("로그인") { showsSignIn = true }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("chat.signIn")
                    }
                } else if launch.rooms.isEmpty {
                    ContentUnavailableView("아직 대화가 없습니다", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("지도에서 작가를 골라 [채팅하기]를 눌러 보세요."))
                } else {
                    List(launch.rooms) { room in
                        NavigationLink(value: room.id) {
                            CustomerChatRow(room: room, unread: launch.unread[room.id] ?? 0,
                                            pendingRequest: launch.pendingRequest?.roomId == room.id ? launch.pendingRequest : nil,
                                            ticket: launch.activeTicket?.roomId == room.id ? launch.activeTicket : nil)
                        }
                        .accessibilityIdentifier("chat.row")
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("채팅")
            .navigationDestination(for: String.self) { roomId in
                CustomerChatRoomScreen(roomId: roomId)
            }
        }
        .sheet(isPresented: $showsSignIn) {
            SignInSheet(allowsLater: true) { name in
                nickname = name
                Task { await session.accountDidChange() }
            }
        }
    }
}

struct CustomerChatRow: View {
    let room: LaunchMatch.Room
    let unread: Int
    let pendingRequest: LaunchMatch.Request?
    let ticket: LaunchMatch.Ticket?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(room.counterpartName(of: room.customerUid))
                    .font(.headline)
                if let tag {
                    Text(tag)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let at = room.lastMessageAt ?? room.activityAt {
                    Text(LaunchTime.clock(at))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    private var tag: String? {
        if let ticket {
            return ticket.status == .shooting ? "촬영 중" : "시작 대기"
        }
        if let pendingRequest {
            return "신청 대기 · \(LaunchTime.clock(pendingRequest.expiresAt))까지"
        }
        return nil
    }
}

/// 고객 대화방: 방 위에 내 신청·진행 중 촬영 막대, 입력창 위에 신청 막대(설계 2.2)
struct CustomerChatRoomScreen: View {
    let roomId: String
    @Environment(CustomerSession.self) private var session
    @Environment(CustomerLaunchModel.self) private var launch
    @State private var roomInfo: LaunchMatch.Room?

    private var room: LaunchMatch.Room? { roomInfo ?? launch.room(roomId) }

    var body: some View {
        let title = room?.counterpartName(of: launch.uid ?? "") ?? "작가"
        LaunchChatRoomView(roomId: roomId, myUid: launch.uid ?? "", counterpartName: title) {
            CustomerRoomBanner(roomId: roomId)
        } bottom: {
            if let room, launch.activeTicket == nil {
                CustomerRequestBar(room: room)
            }
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

/// 방 위 막대: 이 방의 대기 중 신청(신청 취소), 진행 중 촬영(촬영 탭으로)
struct CustomerRoomBanner: View {
    let roomId: String
    @Environment(CustomerLaunchModel.self) private var launch
    @State private var isWorking = false
    @State private var confirmsCancel = false
    @State private var error: String?

    var body: some View {
        if let ticket = launch.mutualCancelAwaitingAnswer(roomId: roomId) {
            LaunchMutualCancelCard(ticket: ticket)
        }
        if let request = launch.pendingRequest, request.roomId == roomId {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(request.minutes)분 촬영 신청 · \(LaunchTime.clock(request.expiresAt))까지 수락 대기")
                        .font(.subheadline)
                        .accessibilityIdentifier("request.waiting")
                    Spacer()
                    Button("신청 취소") { confirmsCancel = true }
                        .disabled(isWorking)
                        .accessibilityIdentifier("request.cancel")
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(.thinMaterial)
            .confirmationDialog("신청을 취소할까요?", isPresented: $confirmsCancel, titleVisibility: .visible) {
                Button("신청 취소", role: .destructive) {
                    Task { await cancel(request) }
                }
                .accessibilityIdentifier("request.cancel.confirm")
                Button("돌아가기", role: .cancel) {}
            }
        } else if let ticket = launch.activeTicket, ticket.roomId == roomId {
            Text(ticket.status == .shooting ? "촬영 중이에요 · 촬영 탭에서 보세요" : "매칭됐어요 · 촬영 탭에서 만날 곳과 시작을 정하세요")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial)
                .accessibilityIdentifier("request.matched")
        }
    }

    private func cancel(_ request: LaunchMatch.Request) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await LaunchMatchService.respond(requestId: request.id, .cancel)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 신청 막대(설계 2.2): 촬영 시간만 고른다(2단계는 가격·결제 없음, D066 S4). 막히면 이유 한 줄.
struct CustomerRequestBar: View {
    let room: LaunchMatch.Room
    @Environment(CustomerLaunchModel.self) private var launch
    @State private var expanded = false
    @State private var minutes = 20
    @State private var clientRequestId = LaunchChatRequestID.make()
    @State private var eligibility: CustomerRequestEligibility.Outcome?
    @State private var isSending = false
    @State private var error: String?
    @State private var location = CustomerLocationReader.shared
    @State private var authorization = CustomerLocationAuthorization()
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let pending = launch.pendingRequest {
            if pending.roomId != room.id {
                blocked("진행 중인 신청이 있어요")
            }
        } else if !expanded {
            Button {
                expanded = true
            } label: {
                Label("촬영 신청", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .accessibilityIdentifier("request.open")
        } else {
            panel
                .task { await location.track() }
                .task(id: location.projected.map { "\($0.eastMm / 50_000):\($0.northMm / 50_000)" } ?? "none") {
                    eligibility = await CustomerRequestEligibility.check(artistUid: room.photographerUid, customer: location.projected)
                    if case .allowed(let row) = eligibility, let recommended = row.recommendedShootMinutes, minutes == 20 {
                        minutes = LaunchMatch.steppedMinutes(recommended, by: 0)
                    }
                }
        }
    }

    private var panel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("촬영 시간")
                Spacer()
                Button { minutes = LaunchMatch.steppedMinutes(minutes, by: -1) } label: { Image(systemName: "minus.circle") }
                    .disabled(minutes <= LaunchMatch.minutesRange.lowerBound)
                    .accessibilityIdentifier("request.minus")
                Text("\(minutes)분")
                    .monospacedDigit()
                    .frame(minWidth: 52)
                    .accessibilityIdentifier("request.duration")
                Button { minutes = LaunchMatch.steppedMinutes(minutes, by: 1) } label: { Image(systemName: "plus.circle") }
                    .disabled(minutes >= LaunchMatch.minutesRange.upperBound)
                    .accessibilityIdentifier("request.plus")
            }
            .font(.title3)
            Text("10~60분, 5분 단위 · 작가가 5분 안에 수락하면 매칭돼요")
                .font(.caption)
                .foregroundStyle(.secondary)
            switch eligibility {
            case nil:
                ProgressView()
            case .allowed:
                Button {
                    Task { await submit() }
                } label: {
                    Text("촬영 신청").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending)
                .accessibilityIdentifier("request.submit")
            case .blocked(let reason):
                VStack(spacing: 6) {
                    Text(reason)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("request.blocked")
                    if eligibility == .needsLocation {
                        Button("위치 켜기") {
                            if authorization.status == .notDetermined {
                                authorization.requestWhenInUseIfNeeded()
                            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .accessibilityIdentifier("request.enableLocation")
                    }
                }
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("request.error")
            }
            Button("접기") { expanded = false }
                .font(.caption)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func blocked(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .accessibilityIdentifier("request.blocked")
    }

    private func submit() async {
        isSending = true
        defer { isSending = false }
        do {
            _ = try await LaunchMatchService.requestMatch(roomId: room.id, minutes: minutes, clientRequestId: clientRequestId)
            clientRequestId = LaunchChatRequestID.make()
            error = nil
            expanded = false
        } catch {
            self.error = error.localizedDescription
        }
    }
}

enum LaunchChatRequestID {
    static func make() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
}

/// 신청할 수 있는지(설계 2.2, D065·D066 S2). 고객 위치 둘레 2.4km(반경 최대 2km + 칸)를 조회해 이 작가를 찾는다.
/// 지도에 없으면 촬영 가능이 아니거나 어느 반경으로도 닿지 않는 거리다. 판정은 기기에서만 하고 고객 위치는 보내지 않는다.
enum CustomerRequestEligibility {
    enum Outcome: Equatable {
        case allowed(PublicLocationGrid.MapPhotographer)
        case blocked(String)

        static let needsLocation = Outcome.blocked("내 위치를 켜면 신청할 수 있어요")
    }

    static let searchMm: Int64 = 2_400_000

    static func check(artistUid: String, customer: PublicLocationGrid.ProjectedPoint?) async -> Outcome {
        guard let customer else { return .needsLocation }
        do {
            let result = try await LaunchMapService.findPhotographers(west: customer.eastMm - searchMm, south: customer.northMm - searchMm,
                                                                      east: customer.eastMm + searchMm, north: customer.northMm + searchMm)
            return outcome(for: result.photographers.first { $0.uid == artistUid }, customer: customer)
        } catch {
            return .blocked("작가 상태를 확인하지 못했어요. 잠시 뒤 다시 열어 주세요.")
        }
    }

    static func outcome(for row: PublicLocationGrid.MapPhotographer?, customer: PublicLocationGrid.ProjectedPoint) -> Outcome {
        guard let row else { return .blocked("지금은 촬영을 받지 않아요") }
        if row.breakReason != nil {
            return .blocked("작가가 쉬는 중이라 지금은 신청할 수 없어요. 채팅은 할 수 있어요.")
        }
        if row.isWithinRadius(of: customer) == false {
            return .blocked(outOfRangeText(row.radiusMeters))
        }
        return .allowed(row)
    }

    /// D066 S2 문구
    static func outOfRangeText(_ radiusMeters: Int64) -> String {
        "활동 범위 밖 · 이 작가는 지금 \(LaunchMatch.radiusLabel(radiusMeters)) 안에서 촬영해요"
    }
}
