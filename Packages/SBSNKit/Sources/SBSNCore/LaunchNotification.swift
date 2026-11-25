import Foundation

/// 출시 2단계 알림(웹 계약 FCM 표 10종 + 3단계 갤러리 알림). data 값은 모두 문자열이고 공통 키는 `event`·`eventId`·`roomId`다.
/// 알림 글은 서버가 넣는다(본문·좌표는 데이터에 없다). 앱은 누르면 어디로 갈지만 정하고, 들어간 화면은 서버 상태를 다시 읽는다.
public struct LaunchNotification: Sendable, Equatable {
    public let event: String
    public let eventId: String
    public let roomId: String
    public let requestId: String?
    public let ticketId: String?
    /// 보정본 알림(`retouch_delivered`)의 사진
    public let photoId: String?

    /// 누르면 갈 곳
    public enum Destination: Sendable, Equatable {
        /// 그 대화방(채팅, 신청 결과·신청 카드)
        case room(String)
        /// 그 티켓(진행 중이면 촬영 탭, 끝났으면 대화방으로)
        case ticket(ticketId: String, roomId: String)
        /// 그 촬영의 갤러리(3단계 `gallery_published`·`gallery_photos_added`·`gallery_favorite_removed`, 고객은 내 사진 탭)
        case gallery(ticketId: String)
        /// 그 갤러리의 그 사진(보정본 전달 `retouch_delivered`)
        case galleryPhoto(ticketId: String, photoId: String)
    }

    public init?(userInfo: [AnyHashable: Any]) {
        guard let event = userInfo["event"] as? String else { return nil }
        // 갤러리 알림은 대화방 ID가 없을 수 있다(티켓 ID로 간다).
        guard let roomId = userInfo["roomId"] as? String ?? (event.hasPrefix("gallery_") ? "" : nil) else { return nil }
        self.event = event
        self.eventId = userInfo["eventId"] as? String ?? ""
        self.roomId = roomId
        self.requestId = userInfo["requestId"] as? String
        self.ticketId = userInfo["ticketId"] as? String
        self.photoId = userInfo["photoId"] as? String
    }

    /// 채팅은 대화방, 신청 이벤트는 신청 카드가 있는 대화방, 촬영·연장은 티켓(계약 "채팅은 대화방, 신청 이벤트는 신청 카드, 촬영·연장은 티켓").
    /// 수락은 티켓이 생겼으므로 티켓으로 간다.
    public var destination: Destination {
        if event == "retouch_delivered", let ticketId {
            if let photoId { return .galleryPhoto(ticketId: ticketId, photoId: photoId) }
            return .gallery(ticketId: ticketId)
        }
        if event.hasPrefix("gallery_"), let ticketId {
            return .gallery(ticketId: ticketId)
        }
        switch event {
        case "match_accepted", "shoot_start_requested", "shoot_ended", "shoot_cancelled", "extension_requested":
            if let ticketId { return .ticket(ticketId: ticketId, roomId: roomId) }
            return .room(roomId)
        default:
            return .room(roomId)
        }
    }

    /// 같은 알림을 두 번 보이지 않게 기억해 두는 열쇠(서버가 수신자·전이마다 안정적으로 만든다)
    public var dedupeKey: String { eventId.isEmpty ? "\(event):\(roomId):\(requestId ?? ""):\(ticketId ?? "")" : eventId }

    /// 시간 민감(5분·60초 안에 답해야 하는) 알림
    public var isTimeSensitive: Bool {
        event == "match_requested" || event == "extension_requested"
    }
}
