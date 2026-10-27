import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SBSNCameraTransfer

struct PhotoPreviewRendererTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "PhotoPreviewRendererTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func shrinksToMaxPixelSizeAndAppliesOrientation() throws {
        // 가로 4000x3000 원본에 "시계 방향 90도 회전"(EXIF 6)이 붙은 사진은 세로 사진으로 보여야 한다.
        let source = try makeJPEG(width: 4000, height: 3000, properties: [kCGImagePropertyOrientation: 6])
        let preview = directory.appending(path: "preview.jpg")

        try PhotoPreviewRenderer.renderJPEG(from: source, to: preview)

        let size = try pixelSize(of: preview)
        #expect(size.width == 768)
        #expect(size.height == 1024)
        #expect(try fileSize(preview) < fileSize(source))
    }

    @Test func dropsLocationAndCameraMetadata() throws {
        let source = try makeJPEG(width: 3000, height: 2000, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5796, kCGImagePropertyGPSLongitude: 126.977],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "ILCE-7CM2"],
        ])
        let preview = directory.appending(path: "preview.jpg")

        try PhotoPreviewRenderer.renderJPEG(from: source, to: preview)

        let imageSource = try #require(CGImageSourceCreateWithURL(preview as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
    }

    @Test func keepsSmallImagesAtOriginalSize() throws {
        let source = try makeJPEG(width: 800, height: 600, properties: [:])
        let preview = directory.appending(path: "preview.jpg")

        try PhotoPreviewRenderer.renderJPEG(from: source, to: preview)

        let size = try pixelSize(of: preview)
        #expect(size.width == 800)
        #expect(size.height == 600)
    }

    @Test func burnsWatermarkIntoPreviewPixels() throws {
        let source = try makeJPEG(width: 2000, height: 1500, properties: [:])
        let plain = directory.appending(path: "plain.jpg")
        let marked = directory.appending(path: "marked.jpg")

        try PhotoPreviewRenderer.renderJPEG(from: source, to: plain, quality: 1, watermark: nil)
        try PhotoPreviewRenderer.renderJPEG(from: source, to: marked, quality: 1)

        // 워터마크 글자가 사진 전체에 반복되므로, 바뀐 픽셀이 한쪽에 몰리지 않고 넓게 퍼져 있어야 한다.
        let difference = try changedPixelShare(between: plain, and: marked)
        #expect(difference.total > 0.05)
        #expect(difference.leftHalf > 0.02)
        #expect(difference.rightHalf > 0.02)
    }

    @Test func fullResolutionJPEGBakesRotationKeepsShotDetailsAndDropsPrivateData() throws {
        // 세로로 찍은 사진(EXIF 6)은 회전을 픽셀에 반영해 어느 뷰어에서나 세로로 보이게 한다.
        let source = try makeJPEG(width: 3000, height: 2000, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5796, kCGImagePropertyGPSLongitude: 126.977],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:22 14:00:00",
                kCGImagePropertyExifBodySerialNumber: "5012345",
                kCGImagePropertyExifCameraOwnerName: "Photographer",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "ILCE-7CM2"],
        ])
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output)

        let info = try deliverable(output)
        #expect(info.width == 2000 && info.height == 3000)
        #expect(info.exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:10:22 14:00:00")
        #expect(info.tiff[kCGImagePropertyTIFFModel] as? String == "ILCE-7CM2")
        #expect(info.properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(info.exif[kCGImagePropertyExifBodySerialNumber] == nil)
        #expect(info.exif[kCGImagePropertyExifCameraOwnerName] == nil)
    }

    /// 가장 흔한 입력(가로 sRGB JPEG)은 그리지 않고 다시 인코딩만 하는 경로를 탄다. 이 경로에서도 개인정보는 빠져야 한다.
    @Test func plainSRGBJPEGKeepsOriginalResolutionAndDropsPrivateData() throws {
        let source = try makeJPEG(width: 3000, height: 2000, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5796, kCGImagePropertyGPSLongitude: 126.977],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:22 14:00:00",
                kCGImagePropertyExifBodySerialNumber: "5012345",
                kCGImagePropertyExifLensSerialNumber: "0001234",
            ],
        ])
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output)

        let info = try deliverable(output)
        #expect(info.width == 3000 && info.height == 2000)
        #expect(info.exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:10:22 14:00:00")
        #expect(info.properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(info.exif[kCGImagePropertyExifBodySerialNumber] == nil)
        #expect(info.exif[kCGImagePropertyExifLensSerialNumber] == nil)
    }

    /// 카메라를 Adobe RGB로 두면 색 관리 안 하는 뷰어(메신저 등)에서 색이 바래 보이므로 sRGB 픽셀로 바꾼다.
    @Test func adobeRGBIsConvertedToSRGB() throws {
        let source = try makeJPEG(width: 1200, height: 800, properties: [:], colorSpace: CGColorSpace(name: CGColorSpace.adobeRGB1998)!)
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output)

        #expect(try deliverable(output).width == 1200)
    }

    /// 10비트 HEIF(Display P3)로 찍는 카메라도 8비트 sRGB JPEG로 넘긴다.
    @Test func tenBitHEIFIsConvertedToEightBitJPEG() throws {
        let source = try makeImage(width: 1600, height: 1200, type: .heic, bitsPerComponent: 16,
                                   colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output)

        let info = try deliverable(output)
        #expect(info.width == 1600 && info.height == 1200)
    }

    @Test func capsLongSideWhenAsked() throws {
        let source = try makeJPEG(width: 4000, height: 3000, properties: [:])
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output, maxPixelSize: 2000)

        let info = try deliverable(output)
        #expect(info.width == 2000 && info.height == 1500)
    }

    @Test func rejectsFilesThatAreNotImages() throws {
        let source = directory.appending(path: "not-image.jpg")
        try Data("not an image".utf8).write(to: source)

        #expect(throws: PhotoPreviewRenderer.RenderError.self) {
            try PhotoPreviewRenderer.renderJPEG(from: source, to: directory.appending(path: "preview.jpg"))
        }
    }

    private func makeJPEG(width: Int, height: Int, properties: [CFString: Any],
                          colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) throws -> URL {
        try makeImage(width: width, height: height, type: .jpeg, bitsPerComponent: 8, colorSpace: colorSpace, properties: properties)
    }

    private func makeImage(width: Int, height: Int, type: UTType, bitsPerComponent: Int, colorSpace: CGColorSpace,
                           properties: [CFString: Any] = [:]) throws -> URL {
        let bitmapInfo = bitsPerComponent == 16
            ? CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo
        ))
        // 압축이 되도록 단색이 아닌 그라데이션을 그린다.
        for x in stride(from: 0, to: width, by: 50) {
            context.setFillColor(red: CGFloat(x) / CGFloat(width), green: 0.5, blue: 1 - CGFloat(x) / CGFloat(width), alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 50, height: height))
        }
        let url = directory.appending(path: "source-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "img")")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// 고객 최종본이 지켜야 할 모양(JPEG, 회전 정보 1, 8비트, sRGB)을 확인하고 크기와 메타데이터를 돌려준다.
    private func deliverable(_ url: URL) throws -> (width: Int, height: Int, properties: [CFString: Any],
                                                    exif: [CFString: Any], tiff: [CFString: Any]) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
        #expect(properties[kCGImagePropertyDepth] as? Int == 8)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.colorSpace?.name == CGColorSpace.sRGB, "색 공간: \(String(describing: image.colorSpace?.name))")
        return (try #require(properties[kCGImagePropertyPixelWidth] as? Int), try #require(properties[kCGImagePropertyPixelHeight] as? Int),
                properties, properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:],
                properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:])
    }

    private func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        #expect(orientation == 1, "미리보기에는 회전 정보가 픽셀에 반영돼 있어야 한다")
        return (try #require(properties[kCGImagePropertyPixelWidth] as? Int), try #require(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    /// 두 사진에서 눈에 띄게(채널 차이 24 이상) 바뀐 픽셀의 비율. 전체, 왼쪽 절반, 오른쪽 절반.
    private func changedPixelShare(between a: URL, and b: URL) throws -> (total: Double, leftHalf: Double, rightHalf: Double) {
        let first = try rgba(a)
        let second = try rgba(b)
        #expect(first.width == second.width && first.height == second.height)
        var changed = (total: 0, left: 0, right: 0)
        for y in 0..<first.height {
            for x in 0..<first.width {
                let i = (y * first.width + x) * 4
                let isChanged = (0..<3).contains { abs(Int(first.pixels[i + $0]) - Int(second.pixels[i + $0])) >= 24 }
                guard isChanged else { continue }
                changed.total += 1
                if x < first.width / 2 { changed.left += 1 } else { changed.right += 1 }
            }
        }
        let count = Double(first.width * first.height)
        return (Double(changed.total) / count, Double(changed.left) / (count / 2), Double(changed.right) / (count / 2))
    }

    private func rgba(_ url: URL) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (pixels, image.width, image.height)
    }

    private func fileSize(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int)
    }
}
