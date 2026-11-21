import Foundation
import Testing
@testable import SBSNCore

struct PhotoRecordTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    private func publishedTicket(at time: Date, ids: [String] = ["pa"]) -> TicketRecord {
        TicketRecord(id: "T1", customerUid: "C", photographerUid: "P", photographerDisplayName: "작가", createdAt: time,
                     endedAt: time, galleryPublishedAt: time, galleryPhotoIds: ids)
    }

    @Test func purchaseNeedsPublishedSelectionWithBothFiles() {
        let ticket = publishedTicket(at: now)
        let ready = PhotoRecord(id: "pa", previewUploadedAt: now, fullresUploadedAt: now)
        #expect(ready.canPurchase(on: ticket, at: now))
        #expect(PhotoRecord(id: "pa", previewUploadedAt: now).canPurchase(on: ticket, at: now) == false)
        #expect(PhotoRecord(id: "pb", previewUploadedAt: now, fullresUploadedAt: now).canPurchase(on: ticket, at: now) == false,
                "공개 목록에 없는 사진은 살 수 없다")
        var unpublished = ticket
        unpublished.galleryPublishedAt = nil
        #expect(ready.canPurchase(on: unpublished, at: now) == false)
        var purchased = ready
        purchased.purchasedAt = now
        #expect(purchased.canPurchase(on: ticket, at: now) == false)
    }

    @Test func purchaseClosesExactly168HoursAfterPublishing() {
        let ticket = publishedTicket(at: now)
        let ready = PhotoRecord(id: "pa", previewUploadedAt: now, fullresUploadedAt: now)
        #expect(ready.canPurchase(on: ticket, at: now.addingTimeInterval(168 * 3600 - 1)))
        #expect(ready.canPurchase(on: ticket, at: now.addingTimeInterval(168 * 3600)) == false)
        #expect(ticket.galleryPurchaseClosesAt == now.addingTimeInterval(168 * 3600))
    }

    @Test func downloadAndDeliveryFollowPurchaseAndFullResolution() {
        var photo = PhotoRecord(id: "pa", previewUploadedAt: now, purchasedAt: now)
        #expect(photo.isReadyToDownload == false)
        #expect(photo.canMarkDelivered == false)
        photo.fullresUploadedAt = now
        #expect(photo.isReadyToDownload)
        #expect(photo.canMarkDelivered)
        photo.deliveredAt = now
        #expect(photo.canMarkDelivered == false)
    }

    /// 이름이 없으면 촬영 시각, 그것도 없으면 "사진 n"(안드로이드 선택기는 이름을 주지 않는다).
    @Test func displayNameFallsBackToCaptureTimeThenIndex() {
        #expect(PhotoRecord(id: "pa", fileName: "DSC00012.JPG").displayName(index: 0) == "DSC00012.JPG")
        let timed = PhotoRecord(id: "pa", capturedAt: now)
        #expect(timed.displayName(index: 0) == now.formatted(.dateTime.hour().minute().second()))
        #expect(PhotoRecord(id: "pa", fileName: "").displayName(index: 2) == "사진 3")
    }

    @Test func chatTextIsTrimmedAndBounded() {
        #expect(ChatMessage.validText("  안녕  ") == "안녕")
        #expect(ChatMessage.validText("   ") == nil)
        #expect(ChatMessage.validText(String(repeating: "가", count: ChatMessage.textLimit)) != nil)
        #expect(ChatMessage.validText(String(repeating: "가", count: ChatMessage.textLimit + 1)) == nil)
    }
}
