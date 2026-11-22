import SBSNCore
import SwiftUI

/// 매칭 뒤 서로의 위치를 보는 별도 화면(D051: 채팅과 위치 지도를 분리). 작가 앱과 고객 앱이 같이 쓴다.
///
/// 대화방 위 "위치" 단추로 연다. 위치를 올리고 받는 일은 이 화면이 아니라 각 앱의 위치 공유 루프가 하므로
/// 화면을 닫아도 공유는 이어진다.
public struct MeetupMapSheet: View {
    let participants: [ParticipantsMapView.Participant]
    /// 상대를 부르는 이름(예: "김작가", "고객")
    let otherLabel: String
    @Environment(\.dismiss) private var dismiss

    public init(participants: [ParticipantsMapView.Participant], otherLabel: String) {
        self.participants = participants
        self.otherLabel = otherLabel
    }

    private var me: ParticipantsMapView.Participant? { participants.first(where: \.isMe) }
    private var other: ParticipantsMapView.Participant? { participants.first { !$0.isMe } }

    public var body: some View {
        NavigationStack {
            ParticipantsMapView(participants: participants)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom) { footer }
                .navigationTitle("위치")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { dismiss() }
                            .accessibilityIdentifier("meetup.map.close")
                    }
                }
        }
        .accessibilityIdentifier("meetup.map")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let other {
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    Text(otherLine(other, now: context.date))
                        .font(.subheadline)
                }
            } else {
                Text("\(otherLabel) 위치를 기다리는 중입니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if me == nil {
                Text("내 위치가 아직 없습니다. 위치 권한을 확인해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }

    /// "김작가 위치 1분 전 · 180m"처럼 갱신 시각(분 단위)과 거리를 보인다. 초 단위 카운트는 쓰지 않는다(D051).
    private func otherLine(_ other: ParticipantsMapView.Participant, now: Date) -> String {
        var parts = ["\(otherLabel) 위치"]
        if let updatedAt = other.updatedAt {
            let minutes = Int(now.timeIntervalSince(updatedAt) / 60)
            parts[0] += minutes < 1 ? " 방금" : " \(minutes)분 전"
        }
        if let me {
            let meters = Int(me.point.distance(to: other.point).rounded())
            parts.append(meters < 1_000 ? "\(meters)m" : String(format: "%.1fkm", Double(meters) / 1_000))
        }
        return parts.joined(separator: " · ")
    }
}
