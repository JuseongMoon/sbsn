import SBSNCore
import SBSNUI
import SwiftUI

/// 작가 "촬영" 탭의 첫 화면: 진행 중인 촬영, 공개 대기 촬영, "촬영 가능" 토글, 새 요청 설정 자리, 알림·전원 경고.
/// 개발 메뉴는 마이 탭으로 옮겼다(`PhotographerDeveloperPage`).
struct PhotographerHomeView: View {
    @Environment(PhotographerSession.self) private var session
    @Environment(PhotographerLaunchModel.self) private var launch
    @State private var showsTurnOn = false
    @State private var showsChange = false
    @State private var choosesBreak = false

    var body: some View {
        Form {
            if session.ticket == nil, let cancelled = session.cancelledByCustomer {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("고객이 촬영을 취소했습니다", systemImage: "xmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        if let cancelledAt = cancelled.cancelledAt {
                            Text("\(LaunchTime.clock(cancelledAt)) 취소 · 매칭 \(LaunchTime.clock(cancelled.createdAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("확인") { session.dismissCancellationNotice() }
                        .accessibilityIdentifier("photographer.cancelledNotice.dismiss")
                }
            }

            if let ticket = session.ticket {
                Section("진행 중인 촬영") {
                    NavigationLink(value: PhotographerRoute.live(ticket.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(phaseTitle(ticket.phase))
                                .font(.headline)
                            Text("매칭 \(ticket.createdAt, style: .relative) 전")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !session.pendingGalleries.isEmpty {
                Section {
                    ForEach(session.pendingGalleries) { model in
                        NavigationLink(value: PhotographerRoute.gallery(model.ticketID)) {
                            PendingGalleryRow(model: model)
                        }
                        .accessibilityIdentifier("home.pendingGallery")
                    }
                } header: {
                    Text("공개 대기 \(session.pendingGalleries.count)건")
                } footer: {
                    Text("고르는 동안에도 다음 촬영을 받을 수 있습니다. 업로드는 앱 안에서 이어 갑니다.")
                }
            }

            Section {
                // 켜면 거리·끝 시각 시트를 거친다(설계 2.3). 끄면 바로 끈다.
                Toggle("촬영 가능", isOn: Binding(
                    get: { session.isAvailable },
                    set: { on in
                        if on { showsTurnOn = true } else { session.setAvailable(false) }
                    }
                ))
                .disabled(!session.isAvailable && !session.canGoAvailable)
                .accessibilityIdentifier("photographer.available")
                if session.isAvailable {
                    if let settings = session.launchPublisher.settings {
                        Text(statusText(settings))
                            .accessibilityIdentifier("home.status")
                        HStack {
                            Button("변경") { showsChange = true }
                                .accessibilityIdentifier("availability.change")
                            Spacer()
                            if settings.breakReason == nil {
                                Button("휴게") { choosesBreak = true }
                                    .accessibilityIdentifier("break.start")
                            } else {
                                Button("휴게 끝내기") {
                                    var next = settings
                                    next.breakReason = nil
                                    Task { await session.updateAvailability(next) }
                                }
                                .accessibilityIdentifier("break.end")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    LabeledContent("위치", value: locationText)
                        .accessibilityIdentifier("photographer.location")
                }
            } header: {
                Text("대기")
            } footer: {
                Text("켜 두면 앱이 뒤에 있거나 화면이 꺼져도 고객 지도에 내 위치가 200m 칸 안의 임의 지점으로 보입니다(1분마다 갱신). 앱을 쓸어 올려 끄면 위치 공유가 멈춥니다.")
            }

            let waiting = launch.waitingRequests()
            if !waiting.isEmpty {
                Section("새 신청(\(waiting.count))") {
                    ForEach(waiting) { request in
                        PhotographerRequestCard(request: request) {
                            launch.chatPath = [request.roomId]
                            launch.requestedTab = .chat
                        }
                    }
                }
            }

            if !warnings.isEmpty {
                Section("확인 필요") {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let message = session.errorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("photographer.error")
                }
            }
        }
        .navigationTitle("십분스냅 작가")
        .sheet(isPresented: $showsTurnOn) {
            AvailabilitySheet(mode: .turnOn, initial: session.lastAvailabilitySettings) { settings in
                session.setAvailable(true, settings: settings)
            }
        }
        .sheet(isPresented: $showsChange) {
            AvailabilitySheet(mode: .change, initial: session.launchPublisher.settings ?? session.lastAvailabilitySettings) { settings in
                Task { await session.updateAvailability(settings) }
            }
        }
        .modifier(BreakReasonDialog(isPresented: $choosesBreak) { reason in
            guard var settings = session.launchPublisher.settings else { return }
            settings.breakReason = reason.rawValue
            Task { await session.updateAvailability(settings) }
        })
    }

    /// "촬영 가능 · 1km · 18:00까지" 또는 "휴게 중 · 식사 · 1km · 18:00까지"
    private func statusText(_ settings: LaunchPresencePublisher.Settings) -> String {
        let head = settings.breakReasonValue.map { "휴게 중 · \($0.label)" } ?? "촬영 가능"
        return "\(head) · \(LaunchMatch.radiusLabel(settings.radiusMeters)) · \(LaunchTime.clock(settings.endsAt))까지"
    }

    private var locationText: String {
        switch session.location.status {
        case .idle: "꺼짐"
        case .waitingForAuthorization: "권한 확인 중"
        case .denied: "위치 권한이 꺼져 있습니다(설정 > 십분스냅 작가 > 위치)"
        case .tracking: "공유 중"
        case .failed(let message): "오류: \(message)"
        }
    }

    private var warnings: [String] {
        var result: [String] = []
        if case .failed(let message) = session.registration {
            result.append("알림 등록 실패: \(message). 매칭을 알 수 없습니다.")
        }
        if session.isAlertAuthorized == false {
            result.append("알림이 꺼져 있습니다. 매칭·채팅·구매·공개 알림이 오지 않습니다.")
        }
        if session.isLowPowerModeEnabled {
            result.append("저전력 모드에서는 앱이 뒤에 있을 때 업로드가 늦어질 수 있습니다.")
        }
        if !session.isBackgroundRefreshAvailable {
            result.append("백그라운드 앱 새로 고침이 꺼져 있습니다(설정 > 일반).")
        }
        return result
    }

    private func phaseTitle(_ phase: TicketPhase) -> String {
        switch phase {
        case .matched: "새 촬영 요청: 고객을 만나세요"
        case .waitingForCustomer: "고객의 시작을 기다리는 중"
        case .waitingForPhotographer: "고객이 시작을 눌렀습니다"
        case .shooting: "촬영 중"
        case .ended: "촬영 종료"
        case .cancelled: "취소됨"
        }
    }
}

/// 공개 대기 촬영 한 줄: 종료 시각, 고른 장수, 업로드·공개 상태
private struct PendingGalleryRow: View {
    let model: CuratedDeliveryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let endedAt = model.ticket.endedAt {
                Text("\(LaunchTime.clock(endedAt)) 종료 촬영")
                    .font(.headline)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(model.photos.contains(where: \.isFailed) ? .red : .secondary)
        }
    }

    private var statusText: String {
        let count = model.photos.count
        switch model.publishState {
        case .reserved: return "공개 예약 · 올리는 중 \(model.uploadedCount)/\(count)"
        case .publishing: return "공개하는 중"
        case .failed(let message): return message
        default:
            if count == 0 { return "사진을 골라 주세요" }
            return "고른 사진 \(count)장 · 올라감 \(model.uploadedCount)장"
        }
    }
}
