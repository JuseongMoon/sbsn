import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 원본 사진에서 고객에게 넘길 파일을 만든다.
///
/// - 미리보기: 저화질(긴 변 1024px) JPEG에 워터마크를 픽셀로 새긴다. 장당 구매라 사기 전에는 쓸 수 있는 화질이 나가면 안 되고,
///   워터마크 없는 저화질본은 서버에 두지 않는다. 회전 정보는 픽셀에 반영하고 메타데이터는 넣지 않는다.
/// - 고화질본: 고객에게 넘기는 최종본. 원해상도 JPEG(sRGB 8비트)로 맞춘다. 카메라마다 들어오는 파일이 달라서
///   (JPEG·HEIF·RAW, sRGB·Adobe RGB·P3, 8·10비트, HDR, 세로 사진의 회전 정보) 어느 카메라든 같은 모양으로 만든다.
///   a7C II 원본(7008×4672, 약 21MB) 기준 약 8.7MB로 LTE 3~4Mbps에서 17~23초다(2026-10-27 측정).
///   위치와 카메라·렌즈 일련번호, 소유자 이름, 제조사 노트는 빼고 촬영 시각·노출 정보는 남긴다.
public enum PhotoPreviewRenderer {
    public static let defaultMaxPixelSize = 1024
    public static let defaultQuality = 0.75
    public static let defaultWatermark = "십분스냅 SAMPLE"
    /// ImageIO에서 0.85와 0.9는 크기가 같았고 0.8보다 22% 컸다(a7C II 3장). 장당 구매한 "고화질"이라 0.85로 둔다.
    public static let defaultFullResolutionQuality = 0.85

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

    /// 고객에게 넘기는 원해상도 JPEG.
    ///
    /// 이미 sRGB 8비트 JPEG이고 회전 정보가 없으면 그대로 다시 인코딩만 한다(가장 흔한 경우, 빠르고 메모리를 덜 쓴다).
    /// 그 밖에는(세로 사진, Adobe RGB·P3, HEIF, 10비트·HDR, RAW) 픽셀을 sRGB 8비트로 그려 회전을 반영하고,
    /// HDR은 SDR로 톤 매핑한다(iOS 18 이상). 메타데이터는 원본에서 개인정보만 빼고 옮긴다.
    /// - Parameter maxPixelSize: 긴 변 상한. nil이면 원해상도.
    public static func renderFullResolutionJPEG(from source: URL, to destination: URL, quality: Double = defaultFullResolutionQuality,
                                                maxPixelSize: Int? = nil) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(imageSource) > 0,
              let sourceProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        else { throw RenderError.unreadableImage }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RenderError.encodingFailed
        }
        var properties = deliverableMetadata(from: sourceProperties)
        properties[kCGImageDestinationLossyCompressionQuality] = quality
        // AddImageFromSource는 넘긴 값을 원본 메타데이터 위에 덮어쓸 뿐이라 GPS·일련번호가 남는다.
        // 그래서 빠른 경로도 이미지만 꺼내 AddImage로 쓴다(넘긴 메타데이터만 기록, 시간·크기는 같음).
        let image: CGImage
        if maxPixelSize == nil, isPlainSRGBJPEG(imageSource, properties: sourceProperties) {
            guard let decoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { throw RenderError.unreadableImage }
            image = decoded
        } else {
            image = try renderSRGB(from: source, imageSource: imageSource, maxPixelSize: maxPixelSize)
        }
        CGImageDestinationAddImage(output, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            throw RenderError.encodingFailed
        }
    }

    /// 회전 정보 없는 sRGB 8비트 JPEG인지
    static func isPlainSRGBJPEG(_ imageSource: CGImageSource, properties: [CFString: Any]) -> Bool {
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let depth = properties[kCGImagePropertyDepth] as? Int ?? 8
        let profile = properties[kCGImagePropertyProfileName] as? String
        return CGImageSourceGetType(imageSource) as String? == UTType.jpeg.identifier
            && orientation == 1 && depth == 8
            && (profile == nil || profile?.hasPrefix("sRGB") == true)
    }

    /// 회전을 반영하고 sRGB 8비트로 그린 이미지. Core Image가 색 공간을 바꾸고, iOS 18 이상에서는 HDR을 SDR로 톤 매핑한다.
    static func renderSRGB(from source: URL, imageSource: CGImageSource, maxPixelSize: Int?) throws -> CGImage {
        var options: [CIImageOption: Any] = [.applyOrientationProperty: true]
        if #available(iOS 18, macOS 15, *) {
            options[.toneMapHDRtoSDR] = true
        }
        guard var image = CIImage(contentsOf: source, options: options) else { throw RenderError.unreadableImage }
        if let maxPixelSize {
            let longSide = max(image.extent.width, image.extent.height)
            if longSide > CGFloat(maxPixelSize) {
                let scale = CGFloat(maxPixelSize) / longSide
                image = image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
            }
        }
        let extent = image.extent.integral
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let rendered = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])
                .createCGImage(image, from: extent, format: .RGBA8, colorSpace: srgb)
        else { throw RenderError.encodingFailed }
        return rendered
    }

    /// 고객에게 넘길 메타데이터. 회전은 픽셀에 반영하므로 1로, 위치·일련번호·소유자·제조사 노트는 뺀다.
    static func deliverableMetadata(from source: [CFString: Any]) -> [CFString: Any] {
        var result: [CFString: Any] = [:]
        if var exif = source[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            for key in [kCGImagePropertyExifBodySerialNumber, kCGImagePropertyExifLensSerialNumber,
                        kCGImagePropertyExifCameraOwnerName, kCGImagePropertyExifMakerNote] {
                exif[key] = nil
            }
            result[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = source[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            result[kCGImagePropertyTIFFDictionary] = tiff
        }
        if let iptc = source[kCGImagePropertyIPTCDictionary] {
            result[kCGImagePropertyIPTCDictionary] = iptc
        }
        result[kCGImagePropertyOrientation] = 1
        return result
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
