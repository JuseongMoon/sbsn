import FirebaseFunctions
import Foundation

/// 작가가 고른 사진을 고객에게 공개한다(callable `publishGallery`, 서울 리전, D038).
///
/// 티켓당 한 번이다. 서버가 장수(5~8)·ID 형식·두 객체의 존재와 소유·초안 기록을 확인한 뒤 트랜잭션으로
/// `galleryPublishedAt`·`galleryPhotoIds`를 쓰고 고객 알림을 보낸다. 같은 목록·순서로 다시 부르면 처음 결과를 돌려주므로
/// 응답을 못 받았을 때는 그냥 다시 부르면 된다. 다른 목록이면 `GALLERY_ALREADY_PUBLISHED`로 거부된다.
public enum TicketGallery {
    public static let region = "asia-northeast3"

    public struct Published: Sendable, Equatable {
        public let publishedAt: Date?
        public let photoIDs: [String]
    }

    /// 공개 실패. `reason`은 서버가 `details.reason`으로 주는 값이다(웹 설계 문서의 실패 코드 표).
    public struct PublishError: LocalizedError, Equatable {
        public let reason: String?
        /// 문제가 된 사진(객체 없음·불일치·오래됨일 때)
        public let photoID: String?
        public let message: String?

        public var errorDescription: String? {
            switch reason {
            case "AUTH_REQUIRED": "로그인이 풀렸습니다. 앱을 다시 열어 주세요."
            case "TICKET_ACCESS_DENIED": "이 촬영의 작가만 공개할 수 있습니다."
            case "INVALID_PHOTO_COUNT": "5~8장을 골라 공개해 주세요."
            case "INVALID_PHOTO_ID", "DUPLICATE_PHOTO_ID": "사진 정보가 맞지 않습니다. 그 사진을 빼고 다시 골라 주세요."
            case "UNSUPPORTED_DELIVERY_MODE": "이전 방식 촬영은 이 버전에서 공개할 수 없습니다."
            case "GALLERY_ALREADY_PUBLISHED": "이미 다른 사진으로 공개된 촬영입니다."
            case "TICKET_CANCELLED": "취소된 촬영입니다."
            case "SHOOT_NOT_ENDED": "촬영을 끝낸 뒤 공개할 수 있습니다."
            case "OBJECT_MISSING": "서버에 아직 없는 사진이 있습니다. 다시 올린 뒤 공개해 주세요."
            case "OBJECT_MISMATCH": "서버의 사진 정보가 맞지 않습니다. 그 사진을 빼고 다시 골라 주세요."
            case "OBJECT_TOO_OLD": "오래전에 올린 사진이 있습니다. 그 사진을 다시 올려야 합니다."
            default: message.map { "공개하지 못했습니다: \($0)" } ?? "공개하지 못했습니다. 잠시 뒤 다시 시도해 주세요."
            }
        }

        /// 그 사진을 새 ID로 다시 올리면 풀리는 실패
        public var needsReupload: Bool { ["OBJECT_MISSING", "OBJECT_MISMATCH", "OBJECT_TOO_OLD"].contains(reason ?? "") }
    }

    public static func publish(ticketId: String, photoIds: [String]) async throws -> Published {
        let callable = Functions.functions(region: region).httpsCallable("publishGallery")
        let result: HTTPSCallableResult
        do {
            result = try await callable.call(["ticketId": ticketId, "photoIds": photoIds])
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            throw PublishError(reason: details?["reason"] as? String, photoID: details?["photoId"] as? String,
                               message: error.localizedDescription)
        }
        let data = result.data as? [String: Any] ?? [:]
        // 서버는 `toISOString()`이라 소수점 초가 붙는다.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let publishedAt = (data["galleryPublishedAt"] as? String).flatMap { formatter.date(from: $0) }
        return Published(publishedAt: publishedAt, photoIDs: data["galleryPhotoIds"] as? [String] ?? photoIds)
    }
}
