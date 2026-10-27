import Foundation
import Testing
@testable import SBSNCore

struct PhotoRecordTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    @Test func cannotPurchaseWithoutPreviewOrTwice() {
        #expect(PhotoRecord(fileName: "A.JPG").canPurchase(in: .shooting) == false)
        let previewed = PhotoRecord(fileName: "A.JPG", previewUploadedAt: now)
        #expect(previewed.canPurchase(in: .shooting))
        #expect(previewed.canPurchase(in: .matched))
        var purchased = previewed
        purchased.purchasedAt = now
        #expect(purchased.canPurchase(in: .shooting) == false)
    }

    @Test func afterEndingOnlyPhotosWithFullResolutionCanBePurchased() {
        // 촬영이 끝난 뒤에는 작가 앱이 더 올리지 않을 수 있으므로 준비된 사진만 산다.
        let previewed = PhotoRecord(fileName: "A.JPG", previewUploadedAt: now)
        #expect(previewed.canPurchase(in: .ended) == false)
        var ready = previewed
        ready.fullresUploadedAt = now
        #expect(ready.canPurchase(in: .ended))
        #expect(ready.canPurchase(in: .cancelled) == false)
    }

    @Test func downloadAndDeliveryFollowPurchaseAndFullResolution() {
        var photo = PhotoRecord(fileName: "A.JPG", previewUploadedAt: now, purchasedAt: now)
        #expect(photo.isReadyToDownload == false)
        #expect(photo.canMarkDelivered == false)
        photo.fullresUploadedAt = now
        #expect(photo.isReadyToDownload)
        #expect(photo.canMarkDelivered)
        photo.deliveredAt = now
        #expect(photo.canMarkDelivered == false)
    }

    @Test func chatTextIsTrimmedAndBounded() {
        #expect(ChatMessage.validText("  안녕  ") == "안녕")
        #expect(ChatMessage.validText("   ") == nil)
        #expect(ChatMessage.validText(String(repeating: "가", count: ChatMessage.textLimit)) != nil)
        #expect(ChatMessage.validText(String(repeating: "가", count: ChatMessage.textLimit + 1)) == nil)
    }
}
