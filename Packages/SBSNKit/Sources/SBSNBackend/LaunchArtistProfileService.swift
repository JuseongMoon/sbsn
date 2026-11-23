import FirebaseFirestore
import FirebaseStorage
import Foundation
import SBSNCore

/// 작가 공개 프로필(W9)과 제재 상태·검토 요청(W6, L16·L17).
///
/// - 프로필: 추천 촬영 시간(10~60분, 5분 단위), 소개(500자), 사진(서버가 정한 임시 경로에 JPEG를 올린 뒤 저장 때 붙인다).
///   고객은 익명이어도 공개 프로필을 읽는다(운영 승인된 작가만).
/// - 제재: 최근 7일 응답 없이 만료된 신청 수, 경고 수, 제한 끝 시각. 제한 중이면 고객 지도에서 숨겨지고 새 신청을 받지 않는다.
public enum LaunchArtistProfileService {
    public struct Profile: Sendable, Equatable {
        public let artistUid: String
        public let nickname: String
        public let recommendedShootMinutes: Int?
        public let bio: String
        public let photoPath: String?
        /// 촬영 종료 → 첫 공개 평균(3단계 집계, 없으면 nil)
        public let averageDeliveryMinutes: Int?
    }

    public struct SanctionStatus: Sendable, Equatable {
        public let missedCount7d: Int
        public let warningCount7d: Int
        public let restrictedUntil: Date?

        public init(missedCount7d: Int, warningCount7d: Int, restrictedUntil: Date?) {
            self.missedCount7d = missedCount7d
            self.warningCount7d = warningCount7d
            self.restrictedUntil = restrictedUntil
        }

        /// 제한 중(지금 시각 기준)
        public func isRestricted(now: Date = Date()) -> Bool { (restrictedUntil ?? .distantPast) > now }
    }

    // MARK: - 프로필

    public static func profile(artistUid: String) async throws -> Profile {
        let data = try await LaunchMatchService.call("getLaunchPhotographerProfileV1", ["artistUid": artistUid])
        return Profile(artistUid: artistUid, nickname: data["nickname"] as? String ?? "작가",
                       recommendedShootMinutes: (data["recommendedShootMinutes"] as? NSNumber)?.intValue,
                       bio: data["bio"] as? String ?? "", photoPath: data["photoPath"] as? String,
                       averageDeliveryMinutes: (data["averageDeliveryMinutes"] as? NSNumber)?.intValue)
    }

    /// 작가 본인 프로필을 저장한다. 닉네임은 그대로 둔다(로그인 때 정한 값). `photoJPEG`가 nil이면 사진은 그대로.
    public static func save(recommendedShootMinutes: Int?, bio: String, photoJPEG: Data?) async throws {
        var payload: [String: Any] = ["age14Confirmed": true, "nickname": NSNull(), "bio": bio]
        if let recommendedShootMinutes {
            payload["recommendedShootMinutes"] = recommendedShootMinutes
        }
        if let photoJPEG {
            let prepared = try await LaunchMatchService.call("prepareLaunchProfilePhotoV1",
                                                             ["clientRequestId": UUID().uuidString.lowercased()])
            guard let uploadId = prepared["photoUploadId"] as? String, let uploadPath = prepared["uploadPath"] as? String else {
                throw LaunchMatchService.Failure.other("사진을 올릴 자리를 받지 못했습니다.")
            }
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await Storage.storage().reference(withPath: uploadPath).putDataAsync(photoJPEG, metadata: metadata)
            payload["photoUploadId"] = uploadId
        }
        _ = try await LaunchMatchService.call("saveLaunchProfileV1", payload)
    }

    /// 프로필 사진(공개 승인된 작가의 현재 사진만 읽힌다)
    public static func photoData(path: String) async throws -> Data {
        try await Storage.storage().reference(withPath: path).data(maxSize: 6 * 1024 * 1024)
    }

    // MARK: - 제재

    public static func sanctionStatus() async throws -> SanctionStatus {
        let data = try await LaunchMatchService.call("getLaunchSanctionStatusV1", [:])
        return SanctionStatus(missedCount7d: (data["missedCount7d"] as? NSNumber)?.intValue ?? 0,
                              warningCount7d: (data["warningCount7d"] as? NSNumber)?.intValue ?? 0,
                              restrictedUntil: (data["restrictedUntil"] as? String).flatMap(LaunchMatchService.date(rfc3339:)))
    }

    /// 가장 최근 제재 사건(검토 요청에 붙인다)
    public static func latestSanctionEventId(uid: String) async throws -> String? {
        let snapshot = try await Firestore.firestore().collection("launchSanctionEvents")
            .whereField("photographerUid", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        return snapshot.documents.first?.documentID
    }

    /// 검토 요청(L17, 영업일 3일 안에 답한다). 같은 `clientRequestId`로 다시 보내면 같은 접수가 돌아온다.
    @discardableResult
    public static func requestReview(eventId: String, note: String, clientRequestId: String) async throws -> String {
        let data = try await LaunchMatchService.call("requestLaunchSanctionReviewV1",
                                                     ["eventId": eventId, "clientRequestId": clientRequestId, "note": note])
        return data["status"] as? String ?? "received"
    }
}
