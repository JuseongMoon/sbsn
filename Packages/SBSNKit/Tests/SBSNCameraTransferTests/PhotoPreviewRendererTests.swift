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
        #expect(size.width == 1536)
        #expect(size.height == 2048)
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
        let source = try makeJPEG(width: 1200, height: 800, properties: [:])
        let preview = directory.appending(path: "preview.jpg")

        try PhotoPreviewRenderer.renderJPEG(from: source, to: preview)

        let size = try pixelSize(of: preview)
        #expect(size.width == 1200)
        #expect(size.height == 800)
    }

    @Test func rejectsFilesThatAreNotImages() throws {
        let source = directory.appending(path: "not-image.jpg")
        try Data("not an image".utf8).write(to: source)

        #expect(throws: PhotoPreviewRenderer.RenderError.self) {
            try PhotoPreviewRenderer.renderJPEG(from: source, to: directory.appending(path: "preview.jpg"))
        }
    }

    private func makeJPEG(width: Int, height: Int, properties: [CFString: Any]) throws -> URL {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        // 압축이 되도록 단색이 아닌 그라데이션을 그린다.
        for x in stride(from: 0, to: width, by: 50) {
            context.setFillColor(red: CGFloat(x) / CGFloat(width), green: 0.5, blue: 1 - CGFloat(x) / CGFloat(width), alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 50, height: height))
        }
        let url = directory.appending(path: "source-\(UUID().uuidString).jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    private func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        #expect(orientation == 1, "미리보기에는 회전 정보가 픽셀에 반영돼 있어야 한다")
        return (try #require(properties[kCGImagePropertyPixelWidth] as? Int), try #require(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    private func fileSize(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int)
    }
}
