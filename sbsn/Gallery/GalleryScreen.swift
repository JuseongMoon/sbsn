import SBSNCore
import SwiftUI

/// 끝난 선별 촬영의 사진 화면: 공개 전이면 "작가가 사진을 고르는 중", 공개 뒤면 갤러리(설계 문서 3절).
/// 촬영 탭(방금 끝난 촬영)과 내 사진 탭(지난 촬영)이 같이 쓴다.
struct GalleryScreen: View {
    let ticketID: String
    @Environment(GalleryStore.self) private var galleries

    var body: some View {
        let workspace = galleries.workspace(for: ticketID)
        Group {
            if let ticket = galleries.ticket(ticketID) ?? workspace.ticket {
                if ticket.isGalleryPublished {
                    TicketPhotoGridView(ticket: ticket, workspace: workspace)
                } else if ticket.cancelledAt != nil {
                    ContentUnavailableView("취소된 촬영입니다", systemImage: "xmark.circle")
                } else {
                    AwaitingPhotosView(ticket: ticket)
                }
            } else {
                ProgressView("촬영 정보를 불러오는 중…")
            }
        }
        .onAppear { galleries.remember(ticketID) }
    }
}

/// 공개 전: 작가가 사진을 옮겨 고르는 중이다. 30분이 넘으면 늦어지고 있다고 안내한다.
struct AwaitingPhotosView: View {
    let ticket: TicketRecord

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let waited = ticket.endedAt.map { context.date.timeIntervalSince($0) } ?? 0
            ContentUnavailableView {
                Label("작가가 사진을 고르는 중입니다", systemImage: "photo.badge.checkmark")
            } description: {
                VStack(spacing: 8) {
                    Text("보통 5~15분 걸립니다. 공개되면 알림으로 알려 드립니다.")
                    if let endedAt = ticket.endedAt {
                        Text("종료 \(endedAt, style: .relative) 지남")
                            .font(.caption)
                    }
                    if waited >= PhotoCuration.publishReminderDelay {
                        Text("늦어지고 있습니다. 채팅으로 작가에게 물어보세요.")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .accessibilityIdentifier("gallery.awaiting")
        }
    }
}

/// 촬영 중(고객): 둘 다 시작한 시각부터 10분을 서버 시각 기준으로 보여 준다. 사진은 촬영이 끝난 뒤 작가가 골라서 보낸다(D036).
struct CustomerShootingView: View {
    static let shootLength: TimeInterval = 10 * 60
    let ticket: TicketRecord

    private var startedAt: Date? {
        guard let customer = ticket.customerStartedAt, let photographer = ticket.photographerStartedAt else { return nil }
        return max(customer, photographer)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            let remaining = max(0, Self.shootLength - elapsed)
            VStack(spacing: 16) {
                Text("\(ticket.photographerDisplayName.isEmpty ? "작가" : ticket.photographerDisplayName) 작가가 촬영 중입니다")
                    .font(.headline)
                Text(String(format: "%02d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                    .font(.system(size: 64, weight: .semibold, design: .monospaced))
                    .accessibilityIdentifier("customer.shooting.timer")
                ProgressView(value: min(elapsed, Self.shootLength), total: Self.shootLength)
                    .padding(.horizontal, 32)
                Text("사진은 촬영이 끝나면 작가가 골라서 보내 드립니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
