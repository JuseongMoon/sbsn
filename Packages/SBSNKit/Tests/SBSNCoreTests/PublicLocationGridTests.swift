import Foundation
import Testing
@testable import SBSNCore

/// 공개 위치 격자 v1 공통 시험 벡터(D059·L02). 벡터는 웹 저장소 `firebase/docs/public-location-grid-v1.vectors.json`의 복사본이고
/// Android `:core`도 같은 파일을 쓴다. 칸 번호·표시점·묶음 ID는 정확히 같아야 하고, 투영만 2mm까지 허용한다.
struct PublicLocationGridTests {
    struct Vectors: Decodable {
        let version: Int
        let epsg: Int
        let vectors: [Vector]
        /// 화면 너비(조회 범위를 자르기 전 여덟 점의 동서 폭, mm) → 묶음 수준(웹 0460041)
        let clusterLevelVectors: [ClusterLevelVector]
    }

    struct ClusterLevelVector: Decodable {
        let visibleWidthMm: Int64
        let level: Int
    }

    struct Vector: Decodable {
        struct MM: Decodable { let eastMm: Int64; let northMm: Int64 }
        struct WGS84: Decodable { let latitude: Double; let longitude: Double }
        let name: String
        let artistUid: String
        let sessionKeyHex: String
        let projected: MM
        let cellId: String
        let display: MM
        let clusters: [String: String]
        let wgs84: WGS84?
    }

    static let vectors: Vectors = {
        let url = Bundle.module.url(forResource: "public-location-grid-v1.vectors", withExtension: "json")!
        return try! JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }()

    static func key(_ hex: String) -> PublicLocationGrid.SessionKey {
        var bytes = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return PublicLocationGrid.SessionKey(bytes: bytes)
    }

    @Test func vectorFileIsV1() {
        #expect(Self.vectors.version == 1 && Self.vectors.epsg == 5179)
        #expect(Self.vectors.vectors.count == 9)
        #expect(Self.vectors.clusterLevelVectors.count == 13)
    }

    /// 묶음 수준 공통 벡터 13개(정확히 일치)
    @Test(arguments: vectors.clusterLevelVectors.map(\.visibleWidthMm))
    func clusterLevelMatchesVector(_ width: Int64) throws {
        let vector = try #require(Self.vectors.clusterLevelVectors.first { $0.visibleWidthMm == width })
        #expect(PublicLocationGrid.clusterLevel(screenWidthMm: width) == vector.level, "폭 \(width)mm")
    }

    /// mm 입력에서 칸 번호·표시점·묶음 ID가 벡터와 정확히 같다.
    @Test(arguments: vectors.vectors.map(\.name))
    func cellDisplayAndClustersMatch(_ name: String) throws {
        let vector = try #require(Self.vectors.vectors.first { $0.name == name })
        let point = PublicLocationGrid.ProjectedPoint(eastMm: vector.projected.eastMm, northMm: vector.projected.northMm)
        let cell = PublicLocationGrid.Cell(containing: point)
        #expect(cell.id == vector.cellId)
        let display = PublicLocationGrid.displayPoint(cell: cell, uid: vector.artistUid, key: Self.key(vector.sessionKeyHex))
        #expect(display == PublicLocationGrid.ProjectedPoint(eastMm: vector.display.eastMm, northMm: vector.display.northMm))
        #expect(PublicLocationGrid.Cell(containing: display) == cell, "표시점은 같은 칸 안에 있다")
        for (level, id) in vector.clusters {
            #expect(cell.clusterID(level: try #require(Int(level))) == id, "\(name) 묶음 수준 \(level)")
        }
    }

    /// WGS 84 입력: 투영은 2mm 안, 칸 번호는 정확히 같다. 역투영 뒤 다시 투영하면 1mm 안으로 돌아온다.
    @Test(arguments: vectors.vectors.filter { $0.wgs84 != nil }.map(\.name))
    func projectionWithinTwoMillimeters(_ name: String) throws {
        let vector = try #require(Self.vectors.vectors.first { $0.name == name })
        let wgs84 = try #require(vector.wgs84)
        let projected = PublicLocationGrid.project(latitude: wgs84.latitude, longitude: wgs84.longitude)
        #expect(abs(projected.eastMm - vector.projected.eastMm) <= 2, "\(name) E 차이 \(projected.eastMm - vector.projected.eastMm)mm")
        #expect(abs(projected.northMm - vector.projected.northMm) <= 2, "\(name) N 차이 \(projected.northMm - vector.projected.northMm)mm")
        #expect(PublicLocationGrid.Cell(containing: projected).id == vector.cellId)

        let back = PublicLocationGrid.unproject(PublicLocationGrid.ProjectedPoint(eastMm: vector.display.eastMm, northMm: vector.display.northMm))
        let again = PublicLocationGrid.project(latitude: back.latitude, longitude: back.longitude)
        #expect(abs(again.eastMm - vector.display.eastMm) <= 1 && abs(again.northMm - vector.display.northMm) <= 1)
    }

    @Test func publicationStopsOutsideServiceArea() {
        let key = PublicLocationGrid.SessionKey.generate()
        #expect(key.bytes.count == 32)
        #expect(PublicLocationGrid.publication(latitude: 37.5665, longitude: 126.978, uid: "artist-01", key: key) != nil)
        // 도쿄는 서비스 범위 밖이라 발행하지 않는다.
        #expect(PublicLocationGrid.publication(latitude: 35.6812, longitude: 139.7671, uid: "artist-01", key: key) == nil)
    }

    /// 묶음 수준(총괄 결정, 웹 벡터가 나오면 대조): 가로 12개 이하가 되는 가장 작은 level
    @Test func clusterLevelFromScreenWidth() {
        #expect(PublicLocationGrid.clusterLevel(screenWidthMm: 2_000_000) == 0)
        #expect(PublicLocationGrid.clusterLevel(screenWidthMm: 2_400_000) == 0)
        #expect(PublicLocationGrid.clusterLevel(screenWidthMm: 2_400_001) == 1)
        #expect(PublicLocationGrid.clusterLevel(screenWidthMm: 5_300_000) == 2)
        #expect(PublicLocationGrid.clusterLevel(screenWidthMm: 20_000_000) == 4)
        #expect(PublicLocationGrid.clusterLevel(screenWidthMm: 9_000_000_000) == 10)
    }

    /// 조회 범위: 축마다 100칸(20km)을 넘으면 가운데 100칸으로 줄인다.
    @Test func queryRectNarrowsToCenterHundredCells() {
        let small = PublicLocationGrid.queryRect(west: 950_000_000, south: 1_950_000_000, east: 960_000_000, north: 1_960_000_000)
        #expect(!small.narrowed && small.west == 950_000_000 && small.east == 960_000_000)
        let wide = PublicLocationGrid.queryRect(west: 900_000_000, south: 1_950_000_000, east: 960_000_000, north: 1_960_000_000)
        #expect(wide.narrowed)
        #expect(wide.east - wide.west == 20_000_000 && wide.west == 920_000_000)
        #expect(wide.south == 1_950_000_000 && wide.north == 1_960_000_000)
        // 화면 네 모서리·변 가운데 투영: 서울 시청 둘레 약 2km 화면
        let box = PublicLocationGrid.projectedViewport([(37.575, 126.966), (37.575, 126.990), (37.557, 126.966), (37.557, 126.990),
                                                       (37.575, 126.978), (37.557, 126.978), (37.566, 126.966), (37.566, 126.990)])
        let width = box.map { $0.east - $0.west } ?? 0
        #expect(width > 2_000_000 && width < 2_200_000)
        #expect(PublicLocationGrid.clusterLevel(screenWidthMm: width) == 0)
    }

    @Test func hmacMessageEscapesLikeJSON() {
        let cell = PublicLocationGrid.Cell(x: -1, y: 0)
        #expect(PublicLocationGrid.hmacMessage(uid: "a\"b\\c/d한\n", cell: cell) == "[\"sbsn-grid-v1\",\"a\\\"b\\\\c/d한\\n\",-1,0]")
        #expect(PublicLocationGrid.floorDiv(-1, 200_000) == -1 && PublicLocationGrid.floorDiv(-200_000, 200_000) == -1
                && PublicLocationGrid.floorDiv(199_999, 200_000) == 0)
    }
}
