import SBSNCore
import SwiftUI

/// 작가 첫 화면: 이름, "촬영 가능" 토글, 진행 중인 촬영, 알림·전원 경고.
struct PhotographerHomeView: View {
    @Environment(PhotographerSession.self) private var session

    var body: some View {
        @Bindable var session = session
        Form {
            if let ticket = session.ticket {
                Section("진행 중인 촬영") {
                    NavigationLink(value: ticket.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(phaseTitle(ticket.phase))
                                .font(.headline)
                            Text("매칭 \(ticket.createdAt, style: .relative) 전")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if ticket.phase == .ended, let delivery = session.delivery, delivery.hasPendingDeliveries {
                        Label("고객에게 넘길 사진을 올리는 중입니다. 끝나면 다시 촬영 가능을 켤 수 있습니다.", systemImage: "arrow.up.circle")
                            .font(.footnote)
                    }
                }
            }

            Section {
                TextField("고객에게 보일 이름", text: $session.displayName)
                    .disabled(session.isAvailable)
                    .accessibilityIdentifier("photographer.name")
                Toggle("촬영 가능", isOn: Binding(
                    get: { session.isAvailable },
                    set: { session.setAvailable($0) }
                ))
                .disabled(!session.isAvailable && !session.canGoAvailable)
                .accessibilityIdentifier("photographer.available")
                if session.isAvailable {
                    LabeledContent("위치", value: locationText)
                        .accessibilityIdentifier("photographer.location")
                    if let presence = session.presence, let updatedAt = presence.updatedAt {
                        LabeledContent("고객 지도에 보이는 시각") {
                            Text(updatedAt, style: .relative)
                        }
                    }
                }
            } header: {
                Text("대기")
            } footer: {
                Text("켜 두면 앱이 뒤에 있거나 화면이 꺼져도 고객 지도에 내 위치(100m 단위)가 보입니다. 고객이 확정하면 알림이 옵니다. 앱을 쓸어 올려 끄면 위치 공유와 알림 처리가 멈춥니다.")
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
                }
            }

            Section("개발") {
                if let delivery = session.delivery {
                    NavigationLink("카메라 전송 측정") {
                        CameraTransferTestView(model: delivery, showsMeasurements: true)
                    }
                }
                LabeledContent("작가 ID", value: session.uid ?? "-")
                    .font(.caption)
                Button("진행 중인 촬영 로컬 정리", role: .destructive) {
                    session.clearLocalTicket()
                }
                .disabled(session.ticket == nil)
                Button("익명 계정 재발급", role: .destructive) {
                    Task { await session.resetAnonymousAccount() }
                }
            }
        }
        .navigationTitle("십분스냅 작가")
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
            result.append("알림이 꺼져 있습니다. 매칭·채팅·구매 배너가 오지 않습니다.")
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
        case .ended: "촬영 종료 · 전달 중"
        case .cancelled: "취소됨"
        }
    }
}
