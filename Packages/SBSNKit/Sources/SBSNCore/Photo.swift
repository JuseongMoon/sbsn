import Foundation

/// 티켓 사진 문서(`tickets/{ticketId}/photos/{원본 파일명}`)의 내용.
///
/// 작가 앱이 미리보기·고화질본·원본 경로와 업로드 시각을 쓰고, 고객 앱이 찜·구매·전달 시각을 쓴다.
public struct PhotoRecord: Sendable, Equatable, Identifiable {
    /// 문서 ID = 카메라 원본 파일명
    public let fileName: String
    public var previewPath: String?
    public var previewUploadedAt: Date?
    public var fullresPath: String?
    public var fullresUploadedAt: Date?
    public var originalPath: String?
    public var originalUploadedAt: Date?
    public var capturedAt: Date?
    public var favoritedAt: Date?
    public var purchasedAt: Date?
    /// 고객 앱이 고화질본을 사진 앱에 저장한 시각. 사이클이 끝까지 돌았다는 서버 쪽 기록이다.
    public var deliveredAt: Date?

    public var id: String { fileName }

    public init(fileName: String, previewPath: String? = nil, previewUploadedAt: Date? = nil,
                fullresPath: String? = nil, fullresUploadedAt: Date? = nil,
                originalPath: String? = nil, originalUploadedAt: Date? = nil, capturedAt: Date? = nil,
                favoritedAt: Date? = nil, purchasedAt: Date? = nil, deliveredAt: Date? = nil) {
        self.fileName = fileName
        self.previewPath = previewPath
        self.previewUploadedAt = previewUploadedAt
        self.fullresPath = fullresPath
        self.fullresUploadedAt = fullresUploadedAt
        self.originalPath = originalPath
        self.originalUploadedAt = originalUploadedAt
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

    /// 구매할 수 있는지. 보안 규칙과 같은 조건이다.
    /// 촬영이 끝난 뒤에는 작가 앱이 더 올리지 않을 수 있으므로 고화질본이 이미 올라간 사진만 살 수 있다.
    public func canPurchase(in phase: TicketPhase) -> Bool {
        guard !isPurchased, hasPreview else { return false }
        switch phase {
        case .cancelled: return false
        case .ended: return isFullResolutionReady
        default: return true
        }
    }

    /// 고객 앱이 고화질본을 내려받을 수 있는 상태
    public var isReadyToDownload: Bool { isPurchased && isFullResolutionReady }

    /// 사진 앱에 저장한 기록을 남길 수 있는지. 보안 규칙과 같은 조건이다.
    public var canMarkDelivered: Bool { isReadyToDownload && !isDelivered }
}
