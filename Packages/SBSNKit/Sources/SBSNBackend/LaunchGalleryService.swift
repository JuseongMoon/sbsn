import FirebaseFirestore
import FirebaseStorage
import Foundation
import SBSNCore

/// 출시 3단계 갤러리 v2 호출부(웹 계약 `firebase/docs/launch-phase-3.md` e964411, 백엔드 f1d9b52).
///
/// - 작가: 사진 한 장마다 준비(`prepared_pair`) → 임시 경로 두 개에 JPEG 업로드(고화질 50 MiB 미만, 미리보기 1 MiB 미만)
///   → 확정(`ready`/`failed`) → 10~30장 첫 공개 → 잠금 뒤 편집(목록 버전 `expectedRevision`).
/// - 고객: 갤러리·공개 아이템 구독, 찜, 구매 기록(개발 환경 시험판, 사진별 결과), 산 사진 고화질본 읽기.
/// - 시각 판정은 서버가 하고, 거부는 이유 코드(`FIRST_PUBLISH_DEADLINE_PASSED`·`GALLERY_REVISION_CONFLICT`·`PURCHASED_PHOTO` 등)로 온다.
public enum LaunchGalleryService {
    // MARK: - 작가: 올리기·공개·편집

    public struct PreparedPhoto: Sendable, Equatable {
        public let photoId: String
        public let fullresPath: String
        public let previewPath: String
        public let expiresAt: Date?
    }

    /// 사진 한 장 자리를 받는다. 같은 `clientRequestId`로 다시 부르면 같은 사진 ID가 온다(재시도).
    public static func prepare(ticketId: String, clientRequestId: String) async throws -> PreparedPhoto {
        let data = try await LaunchMatchService.call("prepareLaunchGalleryPhotoV2",
                                                     ["ticketId": ticketId, "inputKind": "prepared_pair", "clientRequestId": clientRequestId])
        guard let photoId = data["photoId"] as? String, let paths = data["uploadPaths"] as? [String: Any],
              let fullres = paths["fullres"] as? String, let preview = paths["preview"] as? String else {
            throw LaunchMatchService.Failure.other("사진 올릴 자리를 받지 못했습니다.")
        }
        return PreparedPhoto(photoId: photoId, fullresPath: fullres, previewPath: preview,
                             expiresAt: (data["expiresAt"] as? String).flatMap(LaunchMatchService.date(rfc3339:)))
    }

    /// 임시 경로에 JPEG 파일을 올린다. 이미 올라가 있으면(재시도) 규칙이 새로 쓰기를 막으므로 성공으로 본다.
    public static func upload(fileURL: URL, to path: String) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        do {
            _ = try await Storage.storage().reference(withPath: path).putFileAsync(from: fileURL, metadata: metadata)
        } catch {
            guard StorageErrorCode(rawValue: (error as NSError).code) == .unauthorized else { throw error }
        }
    }

    public enum FinalizeResult: Sendable, Equatable {
        case ready
        /// `INVALID_JPEG` 등. 같은 사진 ID로는 고칠 수 없어 새로 준비해야 한다.
        case failed(reason: String?)
    }

    /// 서버가 두 파일을 검사·변환하고 정식 경로에 쓴다. 일시 오류는 같은 사진 ID로 다시 부른다.
    public static func finalize(ticketId: String, photoId: String) async throws -> FinalizeResult {
        let data = try await LaunchMatchService.call("finalizeLaunchGalleryPhotoV2", ["ticketId": ticketId, "photoId": photoId])
        return data["status"] as? String == "ready" ? .ready : .failed(reason: data["reason"] as? String)
    }

    public struct PublishResult: Sendable, Equatable {
        public let revision: Int
        public let publishedAt: Date?
        public let editableFrom: Date?
        public let closesAt: Date?
    }

    /// 첫 공개(10~30장, 72시간 기한은 서버가 트랜잭션에서 본다). 같은 요청 재시도는 원래 결과가 온다.
    public static func publish(ticketId: String, orderedPhotoIds: [String], clientRequestId: String) async throws -> PublishResult {
        let data = try await LaunchMatchService.call("publishLaunchGalleryV2",
                                                     ["ticketId": ticketId, "orderedPhotoIds": orderedPhotoIds, "clientRequestId": clientRequestId])
        return PublishResult(revision: (data["revision"] as? NSNumber)?.intValue ?? 1,
                             publishedAt: (data["publishedAt"] as? String).flatMap(LaunchMatchService.date(rfc3339:)),
                             editableFrom: (data["editableFrom"] as? String).flatMap(LaunchMatchService.date(rfc3339:)),
                             closesAt: (data["closesAt"] as? String).flatMap(LaunchMatchService.date(rfc3339:)))
    }

    /// 변경 공개(추가·삭제·순서를 한 번에). 다른 곳에서 먼저 바꿨으면 `GALLERY_REVISION_CONFLICT`로 거부된다.
    @discardableResult
    public static func edit(ticketId: String, expectedRevision: Int, orderedPhotoIds: [String], clientRequestId: String) async throws -> Int {
        let data = try await LaunchMatchService.call("editLaunchGalleryV2", [
            "ticketId": ticketId, "expectedRevision": expectedRevision,
            "orderedPhotoIds": orderedPhotoIds, "clientRequestId": clientRequestId,
        ])
        return (data["revision"] as? NSNumber)?.intValue ?? expectedRevision + 1
    }

    /// 작가: 끝난 촬영 최근 20개(V1: photographerUid·status·endedAt desc)
    public nonisolated static func endedTickets(photographerUid: String) -> AsyncThrowingStream<[LaunchMatch.Ticket], Error> {
        let query = Firestore.firestore().collection("launchTickets")
            .whereField("photographerUid", isEqualTo: photographerUid)
            .whereField("status", isEqualTo: "ended")
            .order(by: "endedAt", descending: true)
            .limit(to: 20)
        return FirestoreListeners.documents(of: query) { snapshot in
            snapshot.documents.compactMap { LaunchMatchService.ticket(id: $0.documentID, data: $0.data(with: .estimate)) }
        }
    }

    /// 고객: 최근 티켓 20개 중 끝난 것(내 사진 탭, 색인 customerUid·matchedAt desc)
    public nonisolated static func customerEndedTickets(customerUid: String) -> AsyncThrowingStream<[LaunchMatch.Ticket], Error> {
        let query = Firestore.firestore().collection("launchTickets")
            .whereField("customerUid", isEqualTo: customerUid)
            .order(by: "matchedAt", descending: true)
            .limit(to: 20)
        return FirestoreListeners.documents(of: query) { snapshot in
            snapshot.documents.compactMap { LaunchMatchService.ticket(id: $0.documentID, data: $0.data(with: .estimate)) }
                .filter { $0.status == .ended }
        }
    }

    // MARK: - 갤러리 읽기(두 앱)

    public nonisolated static func gallery(ticketId: String) -> AsyncThrowingStream<GalleryV2.Gallery?, Error> {
        FirestoreListeners.document(Firestore.firestore().collection("galleries").document(ticketId)) { snapshot in
            snapshot.data(with: .estimate).flatMap { gallery(id: snapshot.documentID, data: $0) }
        }
    }

    /// 공개 아이템(고객은 `items`, 작가는 `artistItems`). 규칙대로 `status == published`, 30개까지.
    public nonisolated static func items(ticketId: String, role: LaunchMatch.Role) -> AsyncThrowingStream<[GalleryV2.Item], Error> {
        let query = Firestore.firestore().collection("galleries").document(ticketId)
            .collection(role == .customer ? "items" : "artistItems")
            .whereField("status", isEqualTo: "published")
            .limit(to: 30)
        return FirestoreListeners.documents(of: query) { snapshot in
            snapshot.documents.map { item(id: $0.documentID, data: $0.data(with: .estimate)) }
        }
    }

    // MARK: - 고객: 찜·구매 기록·저장

    @discardableResult
    public static func setFavorite(ticketId: String, photoId: String, favorited: Bool) async throws -> Bool {
        let data = try await LaunchMatchService.call("setLaunchGalleryFavoriteV2",
                                                     ["ticketId": ticketId, "photoId": photoId, "favorited": favorited])
        return data["favorited"] as? Bool ?? favorited
    }

    public enum PurchaseStatus: String, Sendable {
        case granted
        case alreadyGranted = "already_granted"
        case unavailable
    }

    /// 구매 기록(3단계 시험판, D068 G1). 1~30장, 사진별 결과. 같은 요청 ID와 같은 입력은 원래 결과가 온다.
    public static func recordPurchase(ticketId: String, photoIds: [String], clientRequestId: String) async throws -> [String: PurchaseStatus] {
        let data = try await LaunchMatchService.call("recordLaunchGalleryPurchaseV2",
                                                     ["ticketId": ticketId, "photoIds": photoIds, "clientRequestId": clientRequestId])
        let rows = data["results"] as? [[String: Any]] ?? []
        return Dictionary(rows.compactMap { row -> (String, PurchaseStatus)? in
            guard let id = row["photoId"] as? String, let status = PurchaseStatus(rawValue: row["status"] as? String ?? "") else { return nil }
            return (id, status)
        }, uniquingKeysWith: { first, _ in first })
    }

    /// 미리보기(워터마크, 1 MiB 미만)
    public static func previewData(path: String) async throws -> Data {
        try await Storage.storage().reference(withPath: path).data(maxSize: 2 * 1024 * 1024)
    }

    /// 산 사진 고화질본을 파일로 받는다(50 MiB 미만, 메타데이터 그대로 D037)
    public static func downloadFullres(path: String, to fileURL: URL) async throws {
        _ = try await Storage.storage().reference(withPath: path).writeAsync(toFile: fileURL)
    }

    // MARK: - 변환

    static func gallery(id: String, data: [String: Any]) -> GalleryV2.Gallery? {
        guard let customerUid = data["customerUid"] as? String, let photographerUid = data["photographerUid"] as? String,
              let publishedAt = FirestoreCodec.date(data["publishedAt"]), let editableFrom = FirestoreCodec.date(data["editableFrom"]),
              let closesAt = FirestoreCodec.date(data["closesAt"]) else { return nil }
        var gallery = GalleryV2.Gallery(ticketId: id, customerUid: customerUid, photographerUid: photographerUid, publishedAt: publishedAt,
                                        editableFrom: editableFrom, closesAt: closesAt,
                                        revision: (data["revision"] as? NSNumber)?.intValue ?? 1,
                                        orderedPhotoIds: data["orderedPhotoIds"] as? [String] ?? [])
        gallery.purchasedCount = (data["purchasedCount"] as? NSNumber)?.intValue
        gallery.favoritedCount = (data["favoritedCount"] as? NSNumber)?.intValue
        return gallery
    }

    static func item(id: String, data: [String: Any]) -> GalleryV2.Item {
        var item = GalleryV2.Item(id: id, isPublished: data["status"] as? String == "published",
                                  previewPath: data["previewPath"] as? String, fullresPath: data["fullresPath"] as? String,
                                  fileExpiresAt: FirestoreCodec.date(data["fileExpiresAt"]),
                                  favorited: data["favorited"] as? Bool ?? false, purchasedAt: FirestoreCodec.date(data["purchasedAt"]))
        // 작가 문서(artistItems)는 구매됨을 불리언으로만 준다(V5)
        item.purchasedFlag = data["purchased"] as? Bool ?? false
        return item
    }
}
