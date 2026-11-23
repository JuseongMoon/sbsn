import Foundation
import SBSNCore

/// 출시 알림을 앞에서 보일지 정한다(설계 2.7, 총괄 구현 결정·두 앱 공통).
/// - 같은 `eventId`는 한 번만 보인다(서버는 같은 사건을 다시 보낼 수 있다). 최근 200개를 기억한다.
/// - 그 대화방을 열고 있으면 `chat_message` 배너를 숨긴다(화면이 이미 그 글을 보인다).
@MainActor
public enum LaunchNotificationGate {
    static let seenKey = "SBSNLaunchSeenNotificationIDs"
    static let memory = 200

    /// 지금 화면에 열린 대화방(대화방 화면이 나타날 때 넣고 사라질 때 뺀다)
    public static var openRoomId: String?

    /// 앞에서 배너로 보일지. 처음 보는 알림이면 기억한다.
    public static func shouldPresent(_ notification: LaunchNotification) -> Bool {
        if notification.event == "chat_message", !notification.roomId.isEmpty, notification.roomId == openRoomId {
            remember(notification)
            return false
        }
        return remember(notification)
    }

    /// 처음이면 기억하고 true, 이미 본 알림이면 false
    @discardableResult
    public static func remember(_ notification: LaunchNotification) -> Bool {
        var seen = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        let key = notification.dedupeKey
        guard !seen.contains(key) else { return false }
        seen.append(key)
        if seen.count > memory { seen.removeFirst(seen.count - memory) }
        UserDefaults.standard.set(seen, forKey: seenKey)
        return true
    }
}
