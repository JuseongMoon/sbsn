import Foundation

/// 위도·경도 한 점. 지도와 위치 공유에 쓴다.
public struct GeoPoint: Sendable, Equatable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// 위도 1도의 길이(m). 경도 1도는 위도에 따라 `cos(위도)`배로 줄어든다.
    static let metersPerDegreeLatitude = 111_320.0

    /// 두 점 사이 거리(m). 위치 발행 간격을 정하는 짧은 거리용이라 구면 보정 없이 계산한다.
    public func distance(to other: GeoPoint) -> Double {
        let latitudeMeters = (latitude - other.latitude) * Self.metersPerDegreeLatitude
        let longitudeMeters = (longitude - other.longitude) * Self.metersPerDegreeLatitude * cos(latitude * .pi / 180)
        return (latitudeMeters * latitudeMeters + longitudeMeters * longitudeMeters).squareRoot()
    }
}

/// 티켓 안에서 공유하는 한 사람의 위치(`tickets/{ticketId}/locations/{uid}`)
public struct LocationSample: Sendable, Equatable, Identifiable {
    /// 매칭부터 촬영 시작까지 정밀 위치를 보내는 간격(D051·L14). 멈춰 있어도 이 간격으로 다시 보낸다.
    public static let meetupPublishInterval: TimeInterval = 10

    public let uid: String
    public var point: GeoPoint
    public var updatedAt: Date?

    public var id: String { uid }

    public init(uid: String, point: GeoPoint, updatedAt: Date?) {
        self.uid = uid
        self.point = point
        self.updatedAt = updatedAt
    }
}

/// MVP 작가 공개 상태 문서(`photographerPresence/{uid}`). 앱은 더 쓰거나 구독하지 않고(D063),
/// `TicketService`의 확정·취소·종료 트랜잭션이 작가 잠금을 읽을 때만 쓴다(2단계 매칭 때까지).
public struct PhotographerPresence: Sendable, Equatable, Identifiable {
    /// 이보다 오래 갱신이 없으면 확정할 수 없고, 보안 규칙도 그 작가와의 매칭을 거부한다.
    public static let staleAfter: TimeInterval = 10 * 60

    public let uid: String
    public var displayName: String
    public var isAvailable: Bool
    public var location: GeoPoint?
    public var updatedAt: Date?
    public var activeTicketId: String?

    public var id: String { uid }

    public init(uid: String, displayName: String, isAvailable: Bool, location: GeoPoint?, updatedAt: Date?, activeTicketId: String?) {
        self.uid = uid
        self.displayName = displayName
        self.isAvailable = isAvailable
        self.location = location
        self.updatedAt = updatedAt
        self.activeTicketId = activeTicketId
    }

    /// 고객이 지금 확정할 수 있는 작가인지: 촬영 가능이고, 다른 고객과 매칭돼 있지 않고, 최근에 살아 있음을 알렸다.
    public func isSelectable(at now: Date = Date()) -> Bool {
        guard isAvailable, activeTicketId == nil, location != nil, let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) < Self.staleAfter
    }

    /// 촬영 종료·취소 때 같은 쓰기에서 작가 잠금을 풀지(공통 명세). 공개 상태 문서가 있고 잠금이 바로 이 티켓일 때만 푼다.
    /// 문서가 없거나(24시간 보존으로 지워짐), 다른 티켓으로 잠겼거나, 이미 풀렸으면 그 문서는 건드리지 않고 티켓·고객 잠금만 처리한다.
    public static func releasesLock(presenceExists: Bool, activeTicketId: String?, for ticketId: String) -> Bool {
        presenceExists && activeTicketId == ticketId
    }
}
