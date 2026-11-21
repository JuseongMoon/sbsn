import Foundation

/// 티켓 사진 문서(`tickets/{ticketId}/photos/{사진 ID}`)의 내용.
///
/// 작가 앱이 미리보기·고화질본 경로와 업로드 시각을 쓰고(공개 전 초안), 고객 앱이 찜·구매·전달 시각을 쓴다(공개 뒤).
/// Storage 객체 이름은 `<사진 ID>.jpg`다(`previews/`·`fullres/`).
public struct PhotoRecord: Sendable, Equatable, Identifiable {
    /// 문서 ID = 사진 ID(`^p[a-z0-9]{12}$`, `PhotoCuration.isValidPhotoID`)
    public let id: String
    /// 원래 파일 이름(표시용). 안드로이드 선택기는 이름을 주지 않아 없을 수 있다(`displayName(index:)`).
    public var fileName: String?
    public var previewPath: String?
    public var previewUploadedAt: Date?
    public var fullresPath: String?
    public var fullresUploadedAt: Date?
    public var capturedAt: Date?
    public var favoritedAt: Date?
    public var purchasedAt: Date?
    /// 고객 앱이 고화질본을 사진 앱에 저장한 시각. 사이클이 끝까지 돌았다는 서버 쪽 기록이다.
    public var deliveredAt: Date?

    public init(id: String, fileName: String? = nil, previewPath: String? = nil, previewUploadedAt: Date? = nil,
                fullresPath: String? = nil, fullresUploadedAt: Date? = nil, capturedAt: Date? = nil,
                favoritedAt: Date? = nil, purchasedAt: Date? = nil, deliveredAt: Date? = nil) {
        self.id = id
        self.fileName = fileName
        self.previewPath = previewPath
        self.previewUploadedAt = previewUploadedAt
        self.fullresPath = fullresPath
        self.fullresUploadedAt = fullresUploadedAt
        self.capturedAt = capturedAt
        self.favoritedAt = favoritedAt
        self.purchasedAt = purchasedAt
        self.deliveredAt = deliveredAt
    }

    public var hasPreview: Bool { previewUploadedAt != nil }
    public var isFullResolutionReady: Bool { fullresUploadedAt != nil }
    public var isFavorited: Bool { favoritedAt != nil }
    public var isPurchased: Bool { purchasedAt != nil }
    public var isDelivered: Bool { deliveredAt != nil }

    /// 화면에 보일 이름. 파일 이름 → 촬영 시각 → "사진 n" 순이다(공통 명세).
    /// - Parameter index: 갤러리 안 순서(0부터)
    public func displayName(index: Int, timeFormat: Date.FormatStyle = .dateTime.hour().minute().second()) -> String {
        if let fileName, !fileName.isEmpty { return fileName }
        if let capturedAt { return capturedAt.formatted(timeFormat) }
        return "사진 \(index + 1)"
    }

    /// 구매할 수 있는지. 보안 규칙과 같은 조건이다: 공개된 갤러리의 사진이고, 미리보기·고화질본이 있고, 기한 전이다.
    public func canPurchase(on ticket: TicketRecord, at now: Date = Date()) -> Bool {
        !isPurchased && hasPreview && isFullResolutionReady && ticket.galleryPhotoIds.contains(id) && ticket.acceptsGalleryPurchase(at: now)
    }

    /// 고객 앱이 고화질본을 내려받을 수 있는 상태
    public var isReadyToDownload: Bool { isPurchased && isFullResolutionReady }

    /// 사진 앱에 저장한 기록을 남길 수 있는지. 보안 규칙과 같은 조건이다.
    public var canMarkDelivered: Bool { isReadyToDownload && !isDelivered }
}
