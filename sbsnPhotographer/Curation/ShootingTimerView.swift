import SBSNCore
import SwiftUI

/// 촬영 중 화면(P6 "10분 타이머"의 실제화). 둘 다 시작한 시각부터 10분을 서버 시각 기준으로 잰다.
///
/// 10분이 지나면 햅틱과 문구로 알리고 자동으로 끝내지는 않는다(연장은 범위 밖). 사진은 촬영이 끝난 뒤 골라서 올린다(D036).
struct ShootingTimerView: View {
    static let shootLength: TimeInterval = 10 * 60

    let ticket: TicketRecord
    @State private var hasAlertedOvertime = false

    private var startedAt: Date? {
        guard let customer = ticket.customerStartedAt, let photographer = ticket.photographerStartedAt else { return nil }
        return max(customer, photographer)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            let remaining = Self.shootLength - elapsed
            VStack(spacing: 16) {
                Text(remaining >= 0 ? "남은 시간" : "10분이 지났습니다")
                    .font(.headline)
                    .foregroundStyle(remaining >= 0 ? Color.secondary : Color.orange)
                Text(Self.clock(abs(remaining)))
                    .font(.system(size: 72, weight: .semibold, design: .monospaced))
                    .foregroundStyle(remaining >= 0 ? Color.primary : Color.orange)
                    .accessibilityIdentifier("shooting.timer")
                ProgressView(value: min(elapsed, Self.shootLength), total: Self.shootLength)
                    .padding(.horizontal, 32)
                Text("사진은 촬영을 끝낸 뒤 폰으로 옮겨 5~8장을 골라 공개합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: remaining < 0) { _, isOver in
                guard isOver, !hasAlertedOvertime else { return }
                hasAlertedOvertime = true
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
