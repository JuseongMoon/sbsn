import FirebaseFunctions
import Foundation
import SBSNCore

/// 출시 1단계 지도 조회(D059, 웹 `findLaunchPhotographersV1`, asia-northeast3). 익명 세션도 조회할 수 있다.
///
/// sbsn-dev에는 아직 배포 전이라 앱은 개발용 에뮬레이터를 쓸 때만 부른다(`Backend.usesLaunchFeatures`).
public enum LaunchMapService {
    public struct Result: Sendable, Equatable {
        public let photographers: [PublicLocationGrid.MapPhotographer]
        /// 조회 영역 안 결과가 100명을 넘었다(반환된 점만 센다 → 인원은 "n+"로 보인다)
        public let truncated: Bool
    }

    public enum ServiceError: LocalizedError {
        case malformedResponse

        public var errorDescription: String? { "지도 조회 결과를 읽지 못했습니다." }
    }

    static let region = "asia-northeast3"

    /// EPSG:5179 정수 mm의 닫힌 사각형(축마다 100칸 이하, `PublicLocationGrid.queryRect`로 만든다)
    public static func findPhotographers(west: Int64, south: Int64, east: Int64, north: Int64) async throws -> Result {
        let callable = Backend.functions(region: region).httpsCallable("findLaunchPhotographersV1")
        let response = try await callable.call(["westMm": west, "southMm": south, "eastMm": east, "northMm": north])
        guard let data = response.data as? [String: Any], let rows = data["photographers"] as? [[String: Any]] else {
            throw ServiceError.malformedResponse
        }
        let photographers = rows.compactMap { row -> PublicLocationGrid.MapPhotographer? in
            guard let uid = row["artistUid"] as? String,
                  let east = (row["eastMm"] as? NSNumber)?.int64Value, let north = (row["northMm"] as? NSNumber)?.int64Value
            else { return nil }
            return PublicLocationGrid.MapPhotographer(uid: uid, nickname: row["nickname"] as? String ?? "작가",
                                                      display: .init(eastMm: east, northMm: north))
        }
        return Result(photographers: photographers, truncated: data["truncated"] as? Bool ?? false)
    }
}
