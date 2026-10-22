import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 원본 사진에서 고객에게 넘길 파일을 만든다.
///
/// - 미리보기: 저화질(긴 변 1024px) JPEG에 워터마크를 픽셀로 새긴다. 장당 구매라 사기 전에는 쓸 수 있는 화질이 나가면 안 되고,
///   워터마크 없는 저화질본은 서버에 두지 않는다. 회전 정보는 픽셀에 반영하고 메타데이터는 넣지 않는다.
/// - 고화질본: 원해상도 HEIC. 원본 JPEG(약 20MB)의 3분의 1 이하라 LTE로도 구매 직후 넘길 수 있다.
///   위치와 카메라·렌즈 일련번호, 소유자 이름은 빼고 촬영 시각·노출 정보는 남긴다.
public enum PhotoPreviewRenderer {
    public static let defaultMaxPixelSize = 1024
    public static let defaultQuality = 0.75
    public static let defaultWatermark = "십분스냅 SAMPLE"
    public static let defaultFullResolutionQuality = 0.8

    public enum RenderError: Error {
        case unreadableImage
        case encodingFailed
    }

    /// 미리보기 JPEG. `watermark`가 nil이면 워터마크 없이 만든다(시험용).
    public static func renderJPEG(
        from source: URL,
        to destination: URL,
        maxPixelSize: Int = defaultMaxPixelSize,
        quality: Double = defaultQuality,
        watermark: String? = defaultWatermark
    ) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw RenderError.unreadableImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw RenderError.unreadableImage
        }
        if let watermark {
            image = try drawWatermark(watermark, over: image)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RenderError.encodingFailed
        }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            throw RenderError.encodingFailed
        }
    }

    /// 원해상도 고화질본 HEIC.
    public static func renderFullResolutionHEIC(from source: URL, to destination: URL, quality: Double = defaultFullResolutionQuality) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(imageSource) > 0 else {
            throw RenderError.unreadableImage
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw RenderError.encodingFailed
        }
        // 값을 kCFNull로 주면 원본에서 그 항목을 지운다.
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyGPSDictionary: kCFNull as Any,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifBodySerialNumber: kCFNull as Any,
                kCGImagePropertyExifLensSerialNumber: kCFNull as Any,
                kCGImagePropertyExifCameraOwnerName: kCFNull as Any,
                kCGImagePropertyExifMakerNote: kCFNull as Any,
            ],
            kCGImagePropertyExifAuxDictionary: kCFNull as Any,
        ]
        CGImageDestinationAddImageFromSource(output, imageSource, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            throw RenderError.encodingFailed
        }
    }

    /// 사진 전체에 비스듬히 반복되는 반투명 글자. 모서리 로고보다 잘라 내거나 지우기 어렵다.
    static func drawWatermark(_ text: String, over image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw RenderError.encodingFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let longSide = CGFloat(max(width, height))
        let fontSize = longSide / 22
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("AppleSDGothicNeo-Bold" as CFString, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 1, green: 1, blue: 1, alpha: 0.42),
            NSAttributedString.Key(kCTStrokeColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 0.25),
            NSAttributedString.Key(kCTStrokeWidthAttributeName as String): -2.0,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let lineWidth = max(CTLineGetTypographicBounds(line, nil, nil, nil), 1)
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -.pi / 6)
        let span = longSide * 1.2
        var y = -span
        var row = 0
        while y < span {
            var x = -span + (row.isMultiple(of: 2) ? 0 : lineWidth * 0.6)
            while x < span {
                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, context)
                x += lineWidth * 1.2
            }
            y += fontSize * 3.2
            row += 1
        }
        guard let result = context.makeImage() else { throw RenderError.encodingFailed }
        return result
    }
}
