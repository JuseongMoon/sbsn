import CryptoKit
import Foundation

/// 공개 위치 격자 v1(D059·L02). iOS `SBSNCore`와 Android `:core`가 공유하는 계약이다.
///
/// 규격: 웹 저장소 `firebase/docs/public-location-grid-v1.md`, 시험 벡터: 같은 폴더 `public-location-grid-v1.vectors.json`
/// (이 패키지 `Tests/SBSNCoreTests/Resources/`에 복사본).
/// 1. WGS 84 위도·경도를 EPSG:5179(Korea 2000 / Unified CS, GRS 80, 중앙 자오선 127.5°, 원점 위도 38°, 축척 0.9996,
///    가산 E 1,000,000m·N 2,000,000m)로 투영하고 `floor(m × 1000 + 0.5)`로 정수 mm로 만든다. 이 실제 좌표는 서버로 보내지 않는다.
/// 2. 원점을 뺀 mm를 200,000으로 나눠 내림한 값이 칸(`g1:<x>:<y>`)이다. 서비스 범위 밖이면 발행하지 않는다.
/// 3. 촬영 가능을 새로 켤 때 만든 32바이트 세션 키로 `HMAC-SHA256(["sbsn-grid-v1","<uid>",x,y])`를 구해
///    첫 4바이트·다음 4바이트(빅 엔디언)를 200,000으로 나눈 나머지만큼 칸의 시작점에서 옮긴 점이 표시점이다.
/// 4. 서버에는 칸 번호와 표시점 mm만 보낸다. 지도는 표시점을 WGS 84로 되돌려 그린다.
/// 5. 묶음 수준 `level`은 한 변 `2^level`칸이고 ID는 `g1:<level>:floor(x/2^level):floor(y/2^level)`다.
///
/// 투영은 Krüger 급수(6차, Karney 2011)다. 한국 범위에서 오차가 mm보다 훨씬 작다.
public enum PublicLocationGrid {
    public static let version = "g1"
    public static let cellSizeMm: Int64 = 200_000
    public static let originEastMm: Int64 = 1_000_000_000
    public static let originNorthMm: Int64 = 2_000_000_000
    /// 서비스 범위(mm): E [700,000, 1,400,000)m, N [1,300,000, 2,200,000)m
    public static let serviceEastMm: Range<Int64> = 700_000_000..<1_400_000_000
    public static let serviceNorthMm: Range<Int64> = 1_300_000_000..<2_200_000_000
    static let hmacLabel = "sbsn-grid-v1"

    /// EPSG:5179 좌표(정수 mm, 동쪽·북쪽)
    public struct ProjectedPoint: Sendable, Equatable, Hashable {
        public let eastMm: Int64
        public let northMm: Int64

        public init(eastMm: Int64, northMm: Int64) {
            self.eastMm = eastMm
            self.northMm = northMm
        }

        public var isInService: Bool {
            PublicLocationGrid.serviceEastMm.contains(eastMm) && PublicLocationGrid.serviceNorthMm.contains(northMm)
        }
    }

    /// 200m 칸
    public struct Cell: Sendable, Equatable, Hashable {
        public let x: Int64
        public let y: Int64

        public init(x: Int64, y: Int64) {
            self.x = x
            self.y = y
        }

        public init(containing point: ProjectedPoint) {
            x = PublicLocationGrid.floorDiv(point.eastMm - PublicLocationGrid.originEastMm, PublicLocationGrid.cellSizeMm)
            y = PublicLocationGrid.floorDiv(point.northMm - PublicLocationGrid.originNorthMm, PublicLocationGrid.cellSizeMm)
        }

        /// `g1:<x>:<y>`를 읽는다. 표기가 규격과 다르면(양수의 +, 선행 0, -0, 다른 판) nil
        public init?(id: String) {
            let parts = id.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == Substring(PublicLocationGrid.version),
                  let x = Int64(parts[1]), let y = Int64(parts[2])
            else { return nil }
            self.init(x: x, y: y)
            guard self.id == id else { return nil }
        }

        /// `g1:<x>:<y>`(부호 있는 10진수, 양수의 +·선행 0·-0 없음)
        public var id: String { "\(PublicLocationGrid.version):\(x):\(y)" }

        /// 이 칸(시작점부터 200,000mm 끝점까지 닫힌 사각형)에서 `point`까지 최단 거리의 제곱(mm², 64비트 정수). 칸 안이면 0
        public func distanceSquaredMm(to point: ProjectedPoint) -> Int64 {
            let start = origin
            func gap(_ value: Int64, _ low: Int64) -> Int64 {
                let high = low + PublicLocationGrid.cellSizeMm
                return value < low ? low - value : (value > high ? value - high : 0)
            }
            let dx = gap(point.eastMm, start.eastMm)
            let dy = gap(point.northMm, start.northMm)
            return dx * dx + dy * dy
        }

        /// 고객 좌표가 이 칸에서 `radiusMeters` 안인지(D065 활동 반경). 정확히 반경과 같은 거리도 안이다.
        /// 고객 좌표는 기기에서만 쓴다(서버에 보내지 않는다).
        public func isWithin(radiusMeters: Int64, of point: ProjectedPoint) -> Bool {
            let radiusMm = radiusMeters * 1000
            return distanceSquaredMm(to: point) <= radiusMm * radiusMm
        }

        /// 칸의 남서쪽 시작점(포함)
        public var origin: ProjectedPoint {
            ProjectedPoint(eastMm: PublicLocationGrid.originEastMm + x * PublicLocationGrid.cellSizeMm,
                           northMm: PublicLocationGrid.originNorthMm + y * PublicLocationGrid.cellSizeMm)
        }

        /// 지도를 줄였을 때의 묶음 ID. 한 변이 `2^level`칸이다.
        public func clusterID(level: Int) -> String {
            precondition(level >= 0 && level < 62)
            let size = Int64(1) << level
            return "\(PublicLocationGrid.version):\(level):\(PublicLocationGrid.floorDiv(x, size)):\(PublicLocationGrid.floorDiv(y, size))"
        }
    }

    /// 촬영 가능 한 번(공개 세션)의 비밀 키. 기기 밖(서버·로그·분석)으로 보내지 않는다.
    public struct SessionKey: Sendable, Equatable {
        public let bytes: Data

        /// CSPRNG로 32바이트를 만든다(촬영 가능을 새로 켤 때).
        public static func generate() -> SessionKey {
            SessionKey(bytes: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
        }

        public init(bytes: Data) {
            precondition(bytes.count == 32, "세션 키는 32바이트다")
            self.bytes = bytes
        }
    }

    /// 서버에 보내는 값: 칸 번호와 표시점
    public struct Publication: Sendable, Equatable {
        public let cell: Cell
        public let display: ProjectedPoint
        public var cellId: String { cell.id }
    }

    // MARK: - 계산

    /// 실제 위치로 칸과 표시점을 정한다. 서비스 범위 밖이면 nil(발행하지 않는다).
    public static func publication(latitude: Double, longitude: Double, uid: String, key: SessionKey) -> Publication? {
        let projected = project(latitude: latitude, longitude: longitude)
        guard projected.isInService else { return nil }
        let cell = Cell(containing: projected)
        return Publication(cell: cell, display: displayPoint(cell: cell, uid: uid, key: key))
    }

    /// 칸 안의 표시점. 같은 키·같은 작가·같은 칸이면 언제나 같은 점이다.
    public static func displayPoint(cell: Cell, uid: String, key: SessionKey) -> ProjectedPoint {
        let message = Data(hmacMessage(uid: uid, cell: cell).utf8)
        let mac = Array(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key.bytes)))
        func uint32(_ offset: Int) -> Int64 {
            Int64(mac[offset]) << 24 | Int64(mac[offset + 1]) << 16 | Int64(mac[offset + 2]) << 8 | Int64(mac[offset + 3])
        }
        let origin = cell.origin
        return ProjectedPoint(eastMm: origin.eastMm + uint32(0) % cellSizeMm, northMm: origin.northMm + uint32(4) % cellSizeMm)
    }

    /// 공백 없는 UTF-8 JSON 배열 `["sbsn-grid-v1","<uid>",x,y]`. 문자열은 JSON 표준대로 이스케이프하고 슬래시·비ASCII는 그대로 둔다.
    static func hmacMessage(uid: String, cell: Cell) -> String {
        "[\(jsonString(hmacLabel)),\(jsonString(uid)),\(cell.x),\(cell.y)]"
    }

    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    // MARK: - 지도 화면(묶음 수준·조회 범위)

    /// 묶음 수준 상한(한 변 2^10칸 = 약 205km)
    public static let maxClusterLevel = 10
    /// 화면 가로에 놓일 묶음 수 상한
    public static let maxClustersAcross: Int64 = 12
    /// 조회 범위의 축당 칸 수 상한(findLaunchPhotographersV1 계약)
    public static let maxQueryCellsPerAxis: Int64 = 100

    /// 화면 네 모서리와 네 변 가운데(위경도)를 투영한 점들. 총괄 결정: 이 사각형으로 화면 너비와 조회 범위를 정한다.
    public static func projectedViewport(_ points: [(latitude: Double, longitude: Double)]) -> (west: Int64, south: Int64, east: Int64, north: Int64)? {
        let projected = points.map { project(latitude: $0.latitude, longitude: $0.longitude) }
        guard let first = projected.first else { return nil }
        return projected.dropFirst().reduce((first.eastMm, first.northMm, first.eastMm, first.northMm)) {
            (min($0.0, $1.eastMm), min($0.1, $1.northMm), max($0.2, $1.eastMm), max($0.3, $1.northMm))
        }
    }

    /// 화면 너비(동서 mm)에 한 변 `200m × 2^level` 묶음이 가로 12개 이하가 되는 가장 작은 level(0~10).
    /// 예: 2km → 0, 5.3km → 2, 20km → 4.
    public static func clusterLevel(screenWidthMm: Int64) -> Int {
        for level in 0...maxClusterLevel where screenWidthMm <= maxClustersAcross * cellSizeMm * (Int64(1) << level) {
            return level
        }
        return maxClusterLevel
    }

    /// 조회할 사각형(EPSG:5179 정수 mm, 닫힌 범위, 규격 "화면이 100칸보다 넓을 때").
    /// 화면이 100칸을 넘는 축만 화면 중심 칸 c 기준 c-50~c+49칸으로 줄이고(끝 경계에서 1mm를 뺀다) `narrowed`가 참이다
    /// (앱은 "확대하면 더 보입니다"를 보인다). 서비스 범위 밖은 잘라 낸다.
    public static func queryRect(west: Int64, south: Int64, east: Int64, north: Int64, center: ProjectedPoint)
        -> (west: Int64, south: Int64, east: Int64, north: Int64, narrowed: Bool) {
        func axis(_ low: Int64, _ high: Int64, centerMm: Int64, origin: Int64, service: Range<Int64>) -> (Int64, Int64, Bool) {
            let lowCell = floorDiv(low - origin, cellSizeMm)
            let highCell = floorDiv(high - origin, cellSizeMm)
            var range = (low, high)
            var narrowed = false
            if highCell - lowCell + 1 > maxQueryCellsPerAxis {
                let c = floorDiv(centerMm - origin, cellSizeMm)
                range = (origin + (c - maxQueryCellsPerAxis / 2) * cellSizeMm,
                         origin + (c + maxQueryCellsPerAxis / 2) * cellSizeMm - 1)
                narrowed = true
            }
            return (max(range.0, service.lowerBound), min(range.1, service.upperBound - 1), narrowed)
        }
        let (w, e, narrowedX) = axis(west, east, centerMm: center.eastMm, origin: originEastMm, service: serviceEastMm)
        let (s, n, narrowedY) = axis(south, north, centerMm: center.northMm, origin: originNorthMm, service: serviceNorthMm)
        return (w, s, e, n, narrowedX || narrowedY)
    }

    /// 지도에 보일 작가 한 명(findLaunchPhotographersV1 결과). 2단계(W5)부터 칸·반경·끝 시각·휴게 사유가 같이 온다.
    public struct MapPhotographer: Sendable, Equatable {
        public let uid: String
        public let nickname: String
        public let display: ProjectedPoint
        /// 작가의 200m 칸. 반경 판정(D065)에 쓴다. 응답에 없으면 표시점의 칸.
        public let cell: Cell
        public let radiusMeters: Int64
        public let availabilityEndsAt: Date?
        /// 휴게 중이면 사유 코드(`meal`·`in_transit`·`equipment`·`rest`)
        public let breakReason: String?
        public let recommendedShootMinutes: Int?

        public init(uid: String, nickname: String, display: ProjectedPoint, cell: Cell? = nil, radiusMeters: Int64 = 300,
                    availabilityEndsAt: Date? = nil, breakReason: String? = nil, recommendedShootMinutes: Int? = nil) {
            self.uid = uid
            self.nickname = nickname
            self.display = display
            self.cell = cell ?? Cell(containing: display)
            self.radiusMeters = radiusMeters
            self.availabilityEndsAt = availabilityEndsAt
            self.breakReason = breakReason
            self.recommendedShootMinutes = recommendedShootMinutes
        }

        /// 고객 위치(EPSG:5179 mm)가 이 작가의 활동 반경 안인지(D065). 위치를 모르면 nil.
        public func isWithinRadius(of customer: ProjectedPoint?) -> Bool? {
            customer.map { cell.isWithin(radiusMeters: radiusMeters, of: $0) }
        }
    }

    /// 같은 묶음 ID의 작가들. 한 명이면 그 작가의 표시점, 둘 이상이면 합쳐진 격자 사각형의 중심에 그린다.
    public struct MapCluster: Sendable, Equatable, Identifiable {
        public let id: String
        public let members: [MapPhotographer]
        public let center: ProjectedPoint

        public var count: Int { members.count }
        public var single: MapPhotographer? { members.count == 1 ? members[0] : nil }
    }

    /// 묶음(규격 5항): UID별로 한 번만 센다. 결과는 묶음 ID 순서.
    public static func clusters(_ photographers: [MapPhotographer], level: Int) -> [MapCluster] {
        var groups: [String: [MapPhotographer]] = [:]
        var cells: [String: Cell] = [:]
        var seen: Set<String> = []
        for photographer in photographers where seen.insert(photographer.uid).inserted {
            let cell = Cell(containing: photographer.display)
            let id = cell.clusterID(level: level)
            groups[id, default: []].append(photographer)
            cells[id] = cell
        }
        let size = Int64(1) << level
        return groups.keys.sorted().map { id in
            let members = groups[id]!
            if members.count == 1 { return MapCluster(id: id, members: members, center: members[0].display) }
            let cell = cells[id]!
            let west = originEastMm + floorDiv(cell.x, size) * size * cellSizeMm
            let south = originNorthMm + floorDiv(cell.y, size) * size * cellSizeMm
            return MapCluster(id: id, members: members,
                              center: ProjectedPoint(eastMm: west + size * cellSizeMm / 2, northMm: south + size * cellSizeMm / 2))
        }
    }

    // MARK: - 투영(EPSG:5179, Krüger 급수)

    /// WGS 84 → EPSG:5179 정수 mm(`floor(m × 1000 + 0.5)`)
    public static func project(latitude: Double, longitude: Double) -> ProjectedPoint {
        let (east, north) = TransverseMercator.epsg5179.forward(latitude: latitude, longitude: longitude)
        return ProjectedPoint(eastMm: Int64((east * 1000 + 0.5).rounded(.down)), northMm: Int64((north * 1000 + 0.5).rounded(.down)))
    }

    /// EPSG:5179 mm → WGS 84(지도에 표시점을 그릴 때)
    public static func unproject(_ point: ProjectedPoint) -> (latitude: Double, longitude: Double) {
        TransverseMercator.epsg5179.inverse(east: Double(point.eastMm) / 1000, north: Double(point.northMm) / 1000)
    }
}

/// 횡단 메르카토르(Krüger 6차 급수). 상수는 Karney, "Transverse Mercator with an accuracy of a few nanometers"(2011).
struct TransverseMercator: Sendable {
    let k0: Double
    let falseEasting: Double
    let falseNorthing: Double
    let lon0: Double
    let e: Double
    let rectifyingRadius: Double
    let alpha: [Double]
    let beta: [Double]
    /// 원점 위도의 ξ에 해당하는 거리(m, 축척 적용 전)
    let originArc: Double

    static let epsg5179 = TransverseMercator(a: 6_378_137, inverseFlattening: 298.257222101, k0: 0.9996,
                                             lat0: 38, lon0: 127.5, falseEasting: 1_000_000, falseNorthing: 2_000_000)

    init(a: Double, inverseFlattening: Double, k0: Double, lat0: Double, lon0: Double, falseEasting: Double, falseNorthing: Double) {
        let f = 1 / inverseFlattening
        let n = f / (2 - f)
        let n2 = n * n, n3 = n2 * n, n4 = n3 * n, n5 = n4 * n, n6 = n5 * n
        self.k0 = k0
        self.falseEasting = falseEasting
        self.falseNorthing = falseNorthing
        self.lon0 = lon0 * .pi / 180
        e = (f * (2 - f)).squareRoot()
        rectifyingRadius = a / (1 + n) * (1 + n2 / 4 + n4 / 64 + n6 / 256)
        alpha = [
            n / 2 - 2 * n2 / 3 + 5 * n3 / 16 + 41 * n4 / 180 - 127 * n5 / 288 + 7891 * n6 / 37800,
            13 * n2 / 48 - 3 * n3 / 5 + 557 * n4 / 1440 + 281 * n5 / 630 - 1_983_433 * n6 / 1_935_360,
            61 * n3 / 240 - 103 * n4 / 140 + 15061 * n5 / 26880 + 167_603 * n6 / 181_440,
            49561 * n4 / 161_280 - 179 * n5 / 168 + 6_601_661 * n6 / 7_257_600,
            34729 * n5 / 80640 - 3_418_889 * n6 / 1_995_840,
            212_378_941 * n6 / 319_334_400,
        ]
        beta = [
            n / 2 - 2 * n2 / 3 + 37 * n3 / 96 - n4 / 360 - 81 * n5 / 512 + 96199 * n6 / 604_800,
            n2 / 48 + n3 / 15 - 437 * n4 / 1440 + 46 * n5 / 105 - 1_118_711 * n6 / 3_870_720,
            17 * n3 / 480 - 37 * n4 / 840 - 209 * n5 / 4480 + 5569 * n6 / 90720,
            4397 * n4 / 161_280 - 11 * n5 / 504 - 830_251 * n6 / 7_257_600,
            4583 * n5 / 161_280 - 108_847 * n6 / 3_991_680,
            20_648_693 * n6 / 638_668_800,
        ]
        originArc = Self.xiEta(latitude: lat0 * .pi / 180, deltaLongitude: 0, e: e, alpha: alpha).xi * rectifyingRadius
    }

    /// (ξ, η): 위도·경도 차(라디안)에서 Krüger 급수까지 적용한 값
    private static func xiEta(latitude phi: Double, deltaLongitude lambda: Double, e: Double, alpha: [Double]) -> (xi: Double, eta: Double) {
        let t = sinh(atanh(sin(phi)) - e * atanh(e * sin(phi)))
        let xiPrime = atan2(t, cos(lambda))
        let etaPrime = atanh(sin(lambda) / (1 + t * t).squareRoot())
        var xi = xiPrime, eta = etaPrime
        for (index, a) in alpha.enumerated() {
            let j = Double(2 * (index + 1))
            xi += a * sin(j * xiPrime) * cosh(j * etaPrime)
            eta += a * cos(j * xiPrime) * sinh(j * etaPrime)
        }
        return (xi, eta)
    }

    func forward(latitude: Double, longitude: Double) -> (east: Double, north: Double) {
        let (xi, eta) = Self.xiEta(latitude: latitude * .pi / 180, deltaLongitude: longitude * .pi / 180 - lon0, e: e, alpha: alpha)
        return (falseEasting + k0 * rectifyingRadius * eta, falseNorthing + k0 * (rectifyingRadius * xi - originArc))
    }

    func inverse(east: Double, north: Double) -> (latitude: Double, longitude: Double) {
        let xi = ((north - falseNorthing) / k0 + originArc) / rectifyingRadius
        let eta = (east - falseEasting) / (k0 * rectifyingRadius)
        var xiPrime = xi, etaPrime = eta
        for (index, b) in beta.enumerated() {
            let j = Double(2 * (index + 1))
            xiPrime -= b * sin(j * xi) * cosh(j * eta)
            etaPrime -= b * cos(j * xi) * sinh(j * eta)
        }
        let tauPrime = sin(xiPrime) / (sinh(etaPrime) * sinh(etaPrime) + cos(xiPrime) * cos(xiPrime)).squareRoot()
        let lambda = atan2(sinh(etaPrime), cos(xiPrime))
        // τ' → τ(= tan φ): Newton 반복(Karney 2011 식 19~21)
        var tau = tauPrime
        let e2 = e * e
        for _ in 0..<5 {
            let sigma = sinh(e * atanh(e * tau / (1 + tau * tau).squareRoot()))
            let tauPrimeI = tau * (1 + sigma * sigma).squareRoot() - sigma * (1 + tau * tau).squareRoot()
            let delta = (tauPrime - tauPrimeI) / (1 + tauPrimeI * tauPrimeI).squareRoot()
                * (1 + (1 - e2) * tau * tau) / ((1 - e2) * (1 + tau * tau).squareRoot())
            tau += delta
            if abs(delta) < 1e-14 { break }
        }
        return (atan(tau) * 180 / .pi, (lambda + lon0) * 180 / .pi)
    }
}
