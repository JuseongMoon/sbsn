import Foundation
import Testing
@testable import SBSNCore

struct PhotoCurationTests {
    @Test func newPhotoIDsMatchServerPattern() {
        for _ in 0..<200 {
            #expect(PhotoCuration.isValidPhotoID(PhotoCuration.newPhotoID()))
        }
        #expect(PhotoCuration.isValidPhotoID("p7k2m9q4x1abc"))
        #expect(!PhotoCuration.isValidPhotoID("p7k2m9q4x1ab"), "p 뒤가 12자보다 짧다")
        #expect(!PhotoCuration.isValidPhotoID("P7k2m9q4x1abc"), "대문자 접두")
        #expect(!PhotoCuration.isValidPhotoID("p7K2m9q4x1abc"), "대문자")
        #expect(!PhotoCuration.isValidPhotoID("p7k2m9q4x1ab."), "점")
        #expect(!PhotoCuration.isValidPhotoID("DSC00001.JPG"))
    }

    @Test func onlyJPEGAndHEIFAtLeast4000pxAreAccepted() {
        #expect(PhotoCuration.rejection(format: .jpeg, longSide: 4_000) == nil)
        #expect(PhotoCuration.rejection(format: .heif, longSide: 8_064) == nil)
        #expect(PhotoCuration.rejection(format: .jpeg, longSide: 3_999) == .tooSmall(longSide: 3_999))
        #expect(PhotoCuration.rejection(format: .raw, longSide: 7_008) == .raw)
        #expect(PhotoCuration.rejection(format: .other, longSide: 7_008) == .unsupportedFormat)
        #expect(PhotoCuration.rejection(format: nil, longSide: 0) == .unreadable)
        #expect(PhotoCuration.Rejection.unreadable.errorDescription == "이 사진은 이 폰에서 열 수 없는 형식입니다. 편집 앱에서 JPEG로 내보내 다시 골라 주세요.")
        #expect(PhotoCuration.Rejection.tooSmall(longSide: 3_024).errorDescription?.contains("3,024px") == true)
    }

    @Test func captureOutsideShootWindowOnlyWarns() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let now = start.addingTimeInterval(20 * 60)
        #expect(!PhotoCuration.isOutsideShootWindow(capturedAt: start.addingTimeInterval(-10 * 60), shootStartedAt: start, now: now))
        #expect(PhotoCuration.isOutsideShootWindow(capturedAt: start.addingTimeInterval(-10 * 60 - 1), shootStartedAt: start, now: now))
        #expect(PhotoCuration.isOutsideShootWindow(capturedAt: now.addingTimeInterval(1), shootStartedAt: start, now: now))
        #expect(!PhotoCuration.isOutsideShootWindow(capturedAt: nil, shootStartedAt: start, now: now), "시각이 없으면 경고하지 않는다")
    }

    @Test func publishNeedsFiveToEightPhotos() {
        #expect(PhotoCuration.countProblem(4) == "5장 이상 골라 주세요(지금 4장).")
        #expect(PhotoCuration.countProblem(5) == nil)
        #expect(PhotoCuration.countProblem(8) == nil)
        #expect(PhotoCuration.countProblem(9) == "8장까지 공개할 수 있습니다(지금 9장).")
    }

    @Test func legacyTicketsAreNotCurated() {
        let created = Date(timeIntervalSince1970: 0)
        #expect(TicketRecord(id: "T", customerUid: "C", photographerUid: "P", photographerDisplayName: "", createdAt: created).isCurated)
        #expect(!TicketRecord(id: "T", customerUid: "C", photographerUid: "P", photographerDisplayName: "", createdAt: created,
                              deliveryMode: nil).isCurated)
    }
}
