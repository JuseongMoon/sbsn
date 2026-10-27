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

    /// 좌표를 `gridMeters` 간격의 격자 가운데로 옮긴다. 작가가 "촬영 가능" 상태로 공개하는 위치는 100m 격자로 뭉개서
    /// 익명 사용자가 작가의 정확한 위치를 따라가지 못하게 한다. 티켓 안의 위치 공유는 뭉개지 않는다.
    public func quantized(gridMeters: Double) -> GeoPoint {
        precondition(gridMeters > 0)
        let latitudeStep = gridMeters / Self.metersPerDegreeLatitude
        let snappedLatitude = Self.snap(latitude, step: latitudeStep)
        // 경도 간격은 원래 위도가 아니라 위도 셀 기준으로 정한다. 같은 셀 안의 점은 같은 결과가 나오고,
        // 이미 뭉갠 점을 다시 뭉개도 변하지 않는다.
        let longitudeMeters = Self.metersPerDegreeLatitude * cos(snappedLatitude * .pi / 180)
        let longitudeStep = longitudeMeters > 1 ? gridMeters / longitudeMeters : latitudeStep
        return GeoPoint(latitude: snappedLatitude, longitude: Self.snap(longitude, step: longitudeStep))
    }

    private static func snap(_ value: Double, step: Double) -> Double {
        ((value / step).rounded(.down) + 0.5) * step
    }

    /// 두 점 사이 거리(m). 위치 발행 간격을 정하는 짧은 거리용이라 구면 보정 없이 계산한다.
    public func distance(to other: GeoPoint) -> Double {
        let latitudeMeters = (latitude - other.latitude) * Self.metersPerDegreeLatitude
        let longitudeMeters = (longitude - other.longitude) * Self.metersPerDegreeLatitude * cos(latitude * .pi / 180)
        return (latitudeMeters * latitudeMeters + longitudeMeters * longitudeMeters).squareRoot()
    }
}

/// 티켓 안에서 공유하는 한 사람의 위치(`tickets/{ticketId}/locations/{uid}`)
public struct LocationSample: Sendable, Equatable, Identifiable {
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

/// 작가의 공개 상태 문서(`photographerPresence/{uid}`). 고객 지도는 이것만 읽는다.
public struct PhotographerPresence: Sendable, Equatable, Identifiable {
    public static let displayNameLimit = 40
    /// 이보다 오래 갱신이 없으면 고객 지도에서 숨기고, 보안 규칙도 그 작가와의 매칭을 거부한다.
    public static let staleAfter: TimeInterval = 10 * 60
    /// 작가 앱이 대기 중에 위치를 다시 쓰는 간격. 움직이지 않아도 이 간격으로 살아 있음을 알린다.
    public static let heartbeatInterval: TimeInterval = 3 * 60
    /// 이만큼 움직이면 간격과 관계없이 바로 쓴다.
    public static let movementThresholdMeters: Double = 25
    /// 공개 위치의 격자 크기
    public static let publicGridMeters: Double = 100

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

    /// 표시 이름으로 쓸 수 있게 다듬는다. 비어 있거나 너무 길면 nil.
    public static func validDisplayName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < displayNameLimit else { return nil }
        return trimmed
    }
}
