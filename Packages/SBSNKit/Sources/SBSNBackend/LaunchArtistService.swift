import FirebaseFunctions
import Foundation
import SBSNCore

/// 출시 1단계 작가 공개 위치(D059·L07·L08, 웹 `setLaunchAvailabilityV1`·`publishLaunchLocationV1`, asia-northeast3).
///
/// - 운영이 승인한 작가(`launchArtistRoles/{uid}.approved`)만 켤 수 있다. 승인 전이면 서버가 거부하고 그 문구를 보인다.
/// - 마지막으로 켠 기기가 소유권을 갖는다. 다른 기기가 켜면 이 기기의 발행·끄기는 `replacedByOtherDevice`가 된다.
/// - 서버는 1분에 한 번만 받는다(`rateLimited`). 다음 주기에 보낸다.
/// - 좌표 필드에는 격자 규격의 **표시점**만 넣는다(실제 위치는 칸을 고르는 데만 쓴다).
public enum LaunchArtistService {
    public enum Failure: LocalizedError, Equatable {
        /// 다른 기기가 촬영 가능을 켰다(L08). 되풀이하지 않고 멈춘다.
        case replacedByOtherDevice
        /// 1분 제한. 다음 주기에 보낸다.
        case rateLimited
        /// 승인 전 작가·삭제 요청 중 등 서버가 거부했다(서버 문구).
        case rejected(String)
        /// 네트워크 등 그 밖의 오류
        case other(String)

        public var errorDescription: String? {
            switch self {
            case .replacedByOtherDevice: "다른 기기에서 촬영 가능을 켜서 이 기기는 껐습니다."
            case .rateLimited: "1분 후 다시 갱신해 주세요."
            case .rejected(let message), .other(let message): message
            }
        }
    }

    static let region = "asia-northeast3"

    /// 촬영 가능을 켜거나 끈다. 켜면 이 기기가 소유권을 갖는다(앱 재시작 때는 부르지 않고 발행으로 소유권을 확인한다, 격자 규격).
    public static func setAvailability(_ available: Bool, deviceSessionId: String) async throws {
        try await call("setLaunchAvailabilityV1", ["available": available, "deviceSessionId": deviceSessionId])
    }

    /// 2단계(W5): 촬영 가능을 반경·끝 시각·휴게와 함께 켜거나 바꾼다. 켠 채로 바꿀 때도 같은 `deviceSessionId`를 쓴다(새 세션 아님).
    /// 휴게를 끝내면 `breakReason: nil`. 끌 때는 `setAvailability(false, …)`.
    public static func setAvailability(deviceSessionId: String, radiusMeters: Int64, endsAt: Date,
                                       breakReason: LaunchMatch.BreakReason?) async throws {
        try await call("setLaunchAvailabilityV1", [
            "available": true,
            "deviceSessionId": deviceSessionId,
            "radiusMeters": radiusMeters,
            "availabilityEndsAt": LaunchMatchService.rfc3339(endsAt),
            "breakReason": breakReason?.rawValue ?? NSNull(),
        ])
    }

    /// 표시점을 발행한다. 서버는 칸 안 포함·승인·기기·60초 제한을 확인하고 지도 문서를 120초 유효로 둔다.
    public static func publish(_ publication: PublicLocationGrid.Publication, deviceSessionId: String) async throws {
        try await call("publishLaunchLocationV1", [
            "cellId": publication.cellId,
            "eastMm": publication.display.eastMm,
            "northMm": publication.display.northMm,
            "deviceSessionId": deviceSessionId,
        ])
    }

    private static func call(_ name: String, _ data: sending [String: Any]) async throws {
        do {
            _ = try await Backend.functions(region: region).httpsCallable(name).call(data)
        } catch {
            throw failure(from: error)
        }
    }

    /// 서버 거부의 이유 코드(`details.reason`, 웹 launch-phase-2.md "출시 callable 오류 이유 코드")로 나눈다.
    /// 코드가 없으면(1단계 서버·Firebase 자체 거부·네트워크) callable 상태로 기본 안내를 고른다.
    static func failure(from error: Error) -> Failure {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return .other(error.localizedDescription)
        }
        switch LaunchMatchService.reason(of: nsError) {
        case "DEVICE_SESSION_MISMATCH": return .replacedByOtherDevice
        case "LOCATION_RATE_LIMITED": return .rateLimited
        case .some: return code == .unavailable || code == .deadlineExceeded ? .other(nsError.localizedDescription) : .rejected(nsError.localizedDescription)
        case nil: break
        }
        switch code {
        // 이유 코드가 없는 1단계 서버는 다른 기기가 켰을 때만 이 상태를 돌려준다.
        case .failedPrecondition: return .replacedByOtherDevice
        case .resourceExhausted: return .rateLimited
        case .permissionDenied, .unauthenticated, .invalidArgument: return .rejected(nsError.localizedDescription)
        default: return .other(nsError.localizedDescription)
        }
    }
}
