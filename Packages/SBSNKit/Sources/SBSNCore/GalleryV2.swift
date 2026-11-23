import Foundation

/// 출시 3단계 갤러리 v2(D052·D053·D068, 웹 계약 `firebase/docs/launch-phase-3.md`). 순수 값·시계·판정·문구만 둔다.
/// 시간 판정은 서버가 한다(공개 트랜잭션·편집·구매가 각각 다시 검사). 앱은 시각만 보이고 단추를 미리 끈다.
public enum GalleryV2 {
    /// 첫 공개 약속(종료 뒤 24시간, 3시간은 목표)
    public static let promiseHours = 24.0
    /// 첫 공개 기한(종료 뒤 72시간, 서버 `firstPublishUntil`)
    public static let firstPublishDeadlineHours = 72.0
    /// 공개 뒤 잠금(24시간), 편집·구매 마감(168시간)
    public static let lockHours = 24.0
    public static let closeHours = 168.0
    /// 공개 목록은 늘 10~30장
    public static let photoCountRange = 10...30

    // MARK: - 문서

    /// `galleries/{ticketId}`
    public struct Gallery: Sendable, Equatable {
        public let ticketId: String
        public let customerUid: String
        public let photographerUid: String
        public let publishedAt: Date
        public let editableFrom: Date
        public let closesAt: Date
        public let revision: Int
        public let orderedPhotoIds: [String]
        /// 작가에게 보이는 개수(V5, 웹 6e677ea). 고객 쪽에서는 쓰지 않는다.
        public var purchasedCount: Int?
        public var favoritedCount: Int?

        public init(ticketId: String, customerUid: String, photographerUid: String, publishedAt: Date, editableFrom: Date,
                    closesAt: Date, revision: Int, orderedPhotoIds: [String]) {
            self.ticketId = ticketId
            self.customerUid = customerUid
            self.photographerUid = photographerUid
            self.publishedAt = publishedAt
            self.editableFrom = editableFrom
            self.closesAt = closesAt
            self.revision = revision
            self.orderedPhotoIds = orderedPhotoIds
        }
    }

    /// `galleries/{ticketId}/items/{photoId}`(고객) 또는 `artistItems/{photoId}`(작가)
    public struct Item: Sendable, Equatable, Identifiable {
        public let id: String
        public let isPublished: Bool
        public let previewPath: String?
        public let fullresPath: String?
        /// 객체 보관 끝(생성 뒤 30일). 지나면 구매 기록은 남고 파일만 없다.
        public let fileExpiresAt: Date?
        public let favorited: Bool
        /// 고객 문서의 구매 시각(고객 전용)
        public let purchasedAt: Date?
        /// 작가 문서의 구매됨 표시(V5, 시각·구매자는 고객 전용이라 불리언만 온다)
        public var purchasedFlag = false

        public init(id: String, isPublished: Bool, previewPath: String?, fullresPath: String?, fileExpiresAt: Date?,
                    favorited: Bool, purchasedAt: Date?) {
            self.id = id
            self.isPublished = isPublished
            self.previewPath = previewPath
            self.fullresPath = fullresPath
            self.fileExpiresAt = fileExpiresAt
            self.favorited = favorited
            self.purchasedAt = purchasedAt
        }

        public var isPurchased: Bool { purchasedAt != nil || purchasedFlag }

        public func isFileExpired(now: Date) -> Bool { (fileExpiresAt ?? .distantFuture) <= now }
    }

    /// 공개 순서대로 정렬(갤러리의 `orderedPhotoIds`, 목록에 없는 항목은 뺀다)
    public static func ordered(_ items: [Item], by gallery: Gallery) -> [Item] {
        let byId = Dictionary(items.filter(\.isPublished).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return gallery.orderedPhotoIds.compactMap { byId[$0] }
    }

    /// 업로드 한 장(`galleries/{ticketId}/uploads/{photoId}`)의 상태
    public enum UploadStatus: String, Sendable {
        case pending
        case ready
        case failed
    }

    // MARK: - 시계

    public enum Stage: Sendable, Equatable {
        /// 첫 공개 전. `late`면 약속한 24시간이 지났다.
        case awaitingFirstPublish(promise: Date, deadline: Date, late: Bool)
        /// 72시간 기한이 지나 첫 공개를 닫았다(4단계 미이행 처리 L39)
        case firstPublishClosed(deadline: Date)
        /// 공개 뒤 24시간 잠금
        case locked(until: Date, closesAt: Date)
        /// 추가·삭제·순서 변경·새 구매 가능
        case editable(closesAt: Date)
        /// 편집·구매 마감 뒤(미리보기와 산 사진 보기는 계속)
        case closed(at: Date)
    }

    /// 첫 공개 기한(서버가 `firstPublishUntil`을 주면 그 값, 없으면 종료 + 72시간)
    public static func firstPublishDeadline(endedAt: Date, serverValue: Date? = nil) -> Date {
        serverValue ?? endedAt.addingTimeInterval(firstPublishDeadlineHours * 3600)
    }

    public static func stage(endedAt: Date, firstPublishUntil: Date? = nil, gallery: Gallery?, now: Date) -> Stage {
        guard let gallery else {
            let promise = endedAt.addingTimeInterval(promiseHours * 3600)
            let deadline = firstPublishDeadline(endedAt: endedAt, serverValue: firstPublishUntil)
            if now >= deadline { return .firstPublishClosed(deadline: deadline) }
            return .awaitingFirstPublish(promise: promise, deadline: deadline, late: now >= promise)
        }
        if now >= gallery.closesAt { return .closed(at: gallery.closesAt) }
        if now < gallery.editableFrom { return .locked(until: gallery.editableFrom, closesAt: gallery.closesAt) }
        return .editable(closesAt: gallery.closesAt)
    }

    // MARK: - 장수·삭제

    /// 첫 공개·변경 공개를 보낼 수 있는 장수인지(10~30)
    public static func canPublish(count: Int) -> Bool { photoCountRange.contains(count) }

    /// 이 사진을 목록에서 뺄 수 있는지: 구매된 사진은 안 되고, 10장 아래로 줄일 수 없다(서버도 다시 검사)
    public static func canRemove(_ item: Item, currentCount: Int) -> Bool {
        !item.isPurchased && currentCount > photoCountRange.lowerBound
    }

    /// 사진을 더 고를 수 있는 남은 자리(최대 30장)
    public static func remainingSlots(currentCount: Int) -> Int { max(0, photoCountRange.upperBound - currentCount) }

    // MARK: - 문구(D068 G3, 설계 3.1·3.2)

    public enum Copy {
        public static let testPurchaseBanner = "시험판: 결제 없이 구매로 기록돼요"
        public static let testPurchaseButton = "구매하기(시험)"

        /// 작가 화면 위 한 줄
        public static func photographer(_ stage: Stage) -> String {
            switch stage {
            case .awaitingFirstPublish(let promise, let deadline, let late):
                late ? "약속한 24시간이 지났어요 · \(LaunchTime.dayClock(deadline))까지 공개할 수 있어요"
                    : "\(LaunchTime.dayClock(promise))까지 공개해 주세요"
            case .firstPublishClosed:
                "공개 기한이 지났어요. 이 촬영은 공개할 수 없어요"
            case .locked(let until, _):
                "\(LaunchTime.dayClock(until))까지 잠금"
            case .editable(let closesAt):
                "\(LaunchTime.dayClock(closesAt))까지 추가·삭제할 수 있어요"
            case .closed(let at):
                "\(LaunchTime.dayClock(at))에 편집 기간이 끝났어요"
            }
        }

        /// 공개 단추 아래 안내(첫 공개 전)
        public static func publishNote(now: Date) -> String {
            let closes = now.addingTimeInterval(closeHours * 3600)
            return "공개하면 24시간 동안 바꿀 수 없고, 그 뒤 \(LaunchTime.dayClock(closes))까지 추가·삭제할 수 있어요"
        }

        /// 고객 화면 위 한 줄
        public static func customer(_ stage: Stage, photoCount: Int) -> String {
            switch stage {
            case .awaitingFirstPublish(let promise, _, let late):
                late ? "약속한 시간이 지났어요. 작가가 아직 준비 중이에요"
                    : "작가가 사진을 고르고 있어요 · \(LaunchTime.dayClock(promise))까지 공개 약속"
            case .firstPublishClosed:
                "작가가 기한 안에 사진을 공개하지 못했어요."
            case .locked(_, let closesAt), .editable(let closesAt):
                "사진 \(photoCount)장 · 구매 기한 \(LaunchTime.dayClock(closesAt))"
            case .closed(let at):
                "구매 기한이 지났어요(\(LaunchTime.dayClock(at)))"
            }
        }

        public static let removeFloor = "10장 아래로 줄일 수 없어요"
        public static let removeFavoritedConfirm = "고객이 찜한 사진이에요. 지우면 고객에게 알려요"
        public static let revisionConflict = "다른 곳에서 먼저 바꿨어요. 최신 목록을 불러왔어요"
        public static let fileExpired = "파일 보관 기간이 지났어요"
    }
}
