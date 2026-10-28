import SBSNCore
import SBSNUI
import SwiftUI
import UIKit

/// 매칭 뒤 촬영이 시작되기 전까지의 화면: 서로의 위치 지도, 작가 확인 상태, 채팅.
struct TicketMeetupView: View {
    let ticket: TicketRecord
    let myUid: String
    let sharing: TicketLocationSharing
    /// 작가 응답 없음 판단에 쓰는 시각. 부모 화면이 주기적으로 갱신한다.
    let now: Date

    @Environment(\.openURL) private var openURL

    private var participants: [ParticipantsMapView.Participant] {
        var result: [ParticipantsMapView.Participant] = []
        if let myPoint = sharing.myPoint {
            result.append(ParticipantsMapView.Participant(id: myUid, label: "나", point: myPoint, updatedAt: nil, isMe: true))
        }
        if let sample = sharing.others.first(where: { $0.uid == ticket.photographerUid }) {
            result.append(ParticipantsMapView.Participant(
                id: sample.uid, label: ticket.photographerDisplayName, point: sample.point, updatedAt: sample.updatedAt, isMe: false
            ))
        }
        return result
    }

    /// 작가 앱이 알림을 받아 티켓을 봤거나, 위치를 올리기 시작했으면 확인된 것으로 본다.
    private var isPhotographerConfirmed: Bool {
        ticket.photographerAckAt != nil || sharing.others.contains { $0.uid == ticket.photographerUid }
    }

    private var silence: PhotographerSilence? {
        let photographerSample = sharing.others.first { $0.uid == ticket.photographerUid }
        return PhotographerSilence.of(ticket, photographerLocationUpdatedAt: photographerSample?.updatedAt, at: now)
    }

    var body: some View {
        VStack(spacing: 0) {
            ParticipantsMapView(participants: participants)
                .frame(height: 260)
            statusLines
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            TicketChatView(ticketId: ticket.id, myUid: myUid, otherLabel: ticket.photographerDisplayName)
        }
        .task(id: ticket.id) { await sharing.listenToOthers() }
        .task(id: ticket.id) { await sharing.shareMyLocation() }
    }

    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let silence {
                silenceNotice(silence)
            } else {
                Label(isPhotographerConfirmed ? "작가 확인됨" : "작가 앱이 알림을 받는 중…",
                      systemImage: isPhotographerConfirmed ? "checkmark.circle.fill" : "bell.badge")
                    .font(.subheadline)
                    .foregroundStyle(isPhotographerConfirmed ? Color.green : Color.secondary)
            }
            if sharing.authorization.isDenied {
                HStack {
                    Text("위치 권한이 없어 내 위치를 작가에게 보낼 수 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.caption)
                }
            }
            if let error = sharing.publishError ?? sharing.listenError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 작가 폰이 꺼졌거나 앱이 종료됐을 수 있을 때. 기다릴지 취소할지는 고객이 정한다(아래 취소 버튼).
    private func silenceNotice(_ silence: PhotographerSilence) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            switch silence {
            case .notAcknowledged(let since):
                Label("작가 앱이 \(since, style: .relative)째 응답하지 않습니다", systemImage: "exclamationmark.triangle.fill")
            case .locationStale(let since):
                Label("작가 위치가 \(since, style: .relative)째 갱신되지 않았습니다", systemImage: "exclamationmark.triangle.fill")
            }
            Text("작가 폰이 꺼져 있거나 앱이 종료됐을 수 있습니다. 채팅을 보내 보고, 계속 응답이 없으면 취소할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .foregroundStyle(.orange)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ticket.photographerSilence")
    }
}
