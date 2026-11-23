import Foundation
import Testing
@testable import SBSNCore

/// 갤러리 v2 시계·장수·문구(D068, 웹 launch-phase-3.md 경계: 9·10·30·31장, 24·72·168시간)
struct GalleryV2Tests {
    // 2026-11-23 14:05 KST
    let ended = Date(timeIntervalSince1970: 1_795_410_300)

    func gallery(publishedAfterHours hours: Double) -> GalleryV2.Gallery {
        let published = ended.addingTimeInterval(hours * 3600)
        return .init(ticketId: "t", customerUid: "c", photographerUid: "p", publishedAt: published,
                     editableFrom: published.addingTimeInterval(24 * 3600), closesAt: published.addingTimeInterval(168 * 3600),
                     revision: 1, orderedPhotoIds: ["a", "b"])
    }

    @Test func firstPublishClocks() {
        let hour = 3600.0
        if case .awaitingFirstPublish(_, _, let late) = GalleryV2.stage(endedAt: ended, gallery: nil, now: ended.addingTimeInterval(23 * hour)) {
            #expect(!late)
        } else { Issue.record("23시간이면 대기") }
        if case .awaitingFirstPublish(_, _, let late) = GalleryV2.stage(endedAt: ended, gallery: nil, now: ended.addingTimeInterval(24 * hour)) {
            #expect(late, "24시간 정각부터 지연")
        } else { Issue.record("24시간이면 지연 대기") }
        #expect(GalleryV2.stage(endedAt: ended, gallery: nil, now: ended.addingTimeInterval(72 * hour))
                == .firstPublishClosed(deadline: ended.addingTimeInterval(72 * hour)), "72시간 정각부터 닫힘")
        let server = ended.addingTimeInterval(70 * hour)
        #expect(GalleryV2.stage(endedAt: ended, firstPublishUntil: server, gallery: nil, now: server) == .firstPublishClosed(deadline: server),
                "서버 값이 있으면 그것을 쓴다")
    }

    @Test func publishedClocks() {
        let g = gallery(publishedAfterHours: 3)
        #expect(GalleryV2.stage(endedAt: ended, gallery: g, now: g.publishedAt) == .locked(until: g.editableFrom, closesAt: g.closesAt))
        #expect(GalleryV2.stage(endedAt: ended, gallery: g, now: g.editableFrom) == .editable(closesAt: g.closesAt), "24시간 정각부터 편집")
        #expect(GalleryV2.stage(endedAt: ended, gallery: g, now: g.closesAt) == .closed(at: g.closesAt), "168시간 정각부터 마감")
    }

    @Test func countsAndRemoval() {
        #expect(!GalleryV2.canPublish(count: 9) && GalleryV2.canPublish(count: 10) && GalleryV2.canPublish(count: 30) && !GalleryV2.canPublish(count: 31))
        let plain = GalleryV2.Item(id: "a", isPublished: true, previewPath: nil, fullresPath: nil, fileExpiresAt: nil, favorited: false, purchasedAt: nil)
        let bought = GalleryV2.Item(id: "b", isPublished: true, previewPath: nil, fullresPath: nil, fileExpiresAt: nil, favorited: true, purchasedAt: Date())
        #expect(GalleryV2.canRemove(plain, currentCount: 11) && !GalleryV2.canRemove(plain, currentCount: 10), "10장 아래로 못 줄임")
        #expect(!GalleryV2.canRemove(bought, currentCount: 20), "구매된 사진은 못 지움")
        #expect(GalleryV2.remainingSlots(currentCount: 28) == 2 && GalleryV2.remainingSlots(currentCount: 31) == 0)
    }

    @Test func orderFollowsGallery() {
        let g = gallery(publishedAfterHours: 1)
        func item(_ id: String, published: Bool = true) -> GalleryV2.Item {
            .init(id: id, isPublished: published, previewPath: nil, fullresPath: nil, fileExpiresAt: nil, favorited: false, purchasedAt: nil)
        }
        #expect(GalleryV2.ordered([item("b"), item("x"), item("a")], by: g).map(\.id) == ["a", "b"])
        #expect(GalleryV2.ordered([item("a", published: false), item("b")], by: g).map(\.id) == ["b"], "지운 사진은 뺀다")
    }

    @Test func copy() {
        let hour = 3600.0
        let waiting = GalleryV2.stage(endedAt: ended, gallery: nil, now: ended.addingTimeInterval(hour))
        #expect(GalleryV2.Copy.photographer(waiting) == "11월 24일 14:05까지 공개해 주세요")
        #expect(GalleryV2.Copy.customer(waiting, photoCount: 0) == "작가가 사진을 고르고 있어요 · 11월 24일 14:05까지 공개 약속")
        let late = GalleryV2.stage(endedAt: ended, gallery: nil, now: ended.addingTimeInterval(30 * hour))
        #expect(GalleryV2.Copy.photographer(late) == "약속한 24시간이 지났어요 · 11월 26일 14:05까지 공개할 수 있어요")
        #expect(GalleryV2.Copy.customer(late, photoCount: 0) == "약속한 시간이 지났어요. 작가가 아직 준비 중이에요")
        let closed = GalleryV2.stage(endedAt: ended, gallery: nil, now: ended.addingTimeInterval(80 * hour))
        #expect(GalleryV2.Copy.customer(closed, photoCount: 0) == "작가가 기한 안에 사진을 공개하지 못했어요.", "D068 G2")
        #expect(GalleryV2.Copy.testPurchaseButton == "구매하기(시험)" && GalleryV2.Copy.testPurchaseBanner == "시험판: 결제 없이 구매로 기록돼요", "D068 G1")
    }
}
