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
///   6,000만 화소를 넘는 원본은 긴 변을 8192로 줄인다(D013).
///   메타데이터는 작가가 올린 파일 것을 전부 유지한다(D037): JPEG는 원본 세그먼트를 바이트로 옮기고(`JPEGMetadataTransplant`),
///   HEIF는 ImageIO 메타데이터 트리로 옮긴다(MakerNote는 빠질 수 있다). 회전·색 공간·크기만 출력값으로 고친다.
public enum PhotoPreviewRenderer {
    public static let defaultMaxPixelSize = 1024
    public static let defaultQuality = 0.75
    public static let defaultWatermark = "십분스냅 SAMPLE"
    /// ImageIO에서 0.85와 0.9는 크기가 같았고 0.8보다 22% 컸다(a7C II 3장). 장당 구매한 "고화질"이라 0.85로 둔다.
    public static let defaultFullResolutionQuality = 0.85
    /// 가로×세로가 이 값을 넘는 원본은 고화질본 긴 변을 `largeSourceMaxPixelSize`로 줄인다(D013).
    /// 1억 화소 원본은 디코드만 400MB라 작가 폰 메모리가 모자라고, 원해상도 JPEG가 LTE로 1분 가까이 걸린다.
    public static let largeSourcePixelCount = 60_000_000
    public static let largeSourceMaxPixelSize = 8192

    /// 입력 크기에 따른 고화질본 긴 변 상한. 6,000만 화소 이하면 nil(원해상도).
    public static func automaticMaxPixelSize(width: Int, height: Int) -> Int? {
        width * height > largeSourcePixelCount ? largeSourceMaxPixelSize : nil
    }

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
    /// 이미 sRGB 8비트 JPEG이고 회전 정보가 없고 줄일 필요가 없으면 그대로 다시 인코딩만 한다(가장 흔한 경우, 빠르고 메모리를 덜 쓴다).
    /// 그 밖에는(세로 사진, Adobe RGB·P3, HEIF, 10비트·HDR, 6,000만 화소 초과) 픽셀을 sRGB 8비트로 그려 회전을 반영하고,
    /// HDR은 SDR로 톤 매핑한다(iOS 18 이상). 메타데이터는 전부 옮기고 회전·색 공간·크기만 고친다(D037).
    /// - Parameter maxPixelSize: 긴 변 상한. nil이면 `automaticMaxPixelSize`(6,000만 화소 초과면 8192, 아니면 원해상도).
    public static func renderFullResolutionJPEG(from source: URL, to destination: URL, quality: Double = defaultFullResolutionQuality,
                                                maxPixelSize: Int? = nil) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(imageSource) > 0,
              let sourceProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        else { throw RenderError.unreadableImage }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sourceWidth = sourceProperties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let sourceHeight = sourceProperties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = sourceProperties[kCGImagePropertyOrientation] as? Int ?? 1
        let cap = maxPixelSize ?? automaticMaxPixelSize(width: sourceWidth, height: sourceHeight)
        let image: CGImage
        if cap == nil, isPlainSRGBJPEG(imageSource, properties: sourceProperties) {
            guard let decoded = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
                  let detached = detachedFromSource(decoded)
            else { throw RenderError.unreadableImage }
            image = detached
        } else {
            image = try renderSRGB(from: source, imageSource: imageSource, maxPixelSize: cap)
        }
        let rotates = (5...8).contains(orientation)
        let resized = image.width != (rotates ? sourceHeight : sourceWidth) || image.height != (rotates ? sourceWidth : sourceHeight)

        // JPEG 입력: 메타데이터 없이 인코딩하고 원본 세그먼트를 옮긴다. 원본 구조를 읽지 못하면 아래 메타데이터 트리 방식으로 간다.
        if CGImageSourceGetType(imageSource) as String? == UTType.jpeg.identifier,
           let original = try? Data(contentsOf: source, options: .mappedIfSafe) {
            let encoded = try encodeJPEG(image, quality: quality)
            let output = JPEGMetadataTransplant.Output(width: image.width, height: image.height,
                                                       dropsThumbnail: orientation != 1 || resized)
            if let transplanted = try? JPEGMetadataTransplant.transplant(from: original, into: encoded, output: output) {
                try transplanted.write(to: destination, options: .atomic)
                return
            }
        }
        guard let destinationImage = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw RenderError.encodingFailed }
        let metadata = fixedMetadata(of: imageSource, width: image.width, height: image.height)
        CGImageDestinationAddImageAndMetadata(destinationImage, image, metadata,
                                              [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destinationImage) else {
            throw RenderError.encodingFailed
        }
    }

    /// 메타데이터 없이 JPEG로 인코딩한다(인코더가 넣는 Exif·IPTC는 이식 때 원본 것으로 바뀐다).
    static func encodeJPEG(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw RenderError.encodingFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.encodingFailed }
        return data as Data
    }

    /// JPEG가 아닌 입력(HEIF)의 메타데이터 트리. EXIF·GPS·일련번호·XMP는 남고 MakerNote는 빠질 수 있다(공통 명세상 허용).
    /// 회전·크기·색 공간은 원본에 그 항목이 있을 때만 출력값으로 고친다. 출력에 없는 데이터를 가리키는 XMP 항목은 지운다.
    static func fixedMetadata(of imageSource: CGImageSource, width: Int, height: Int) -> CGImageMetadata? {
        guard let original = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil),
              let metadata = CGImageMetadataCreateMutableCopy(original)
        else { return nil }
        let fixes: [(CFString, CFString, CFTypeRef)] = [
            (kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber),
            (kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension, width as CFNumber),
            (kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelYDimension, height as CFNumber),
            (kCGImagePropertyExifDictionary, kCGImagePropertyExifColorSpace, 1 as CFNumber),
        ]
        for (dictionary, key, value) in fixes where CGImageMetadataCopyTagMatchingImageProperty(metadata, dictionary, key) != nil {
            CGImageMetadataSetValueMatchingImageProperty(metadata, dictionary, key, value)
        }
        if CGImageMetadataCopyTagWithPath(metadata, nil, "photoshop:ICCProfile" as CFString) != nil {
            CGImageMetadataSetValueWithPath(metadata, nil, "photoshop:ICCProfile" as CFString, "sRGB IEC61966-2.1" as CFString)
        }
        for tag in (CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]) ?? [] {
            guard let prefix = CGImageMetadataTagCopyPrefix(tag) as String?, let name = CGImageMetadataTagCopyName(tag) as String?
            else { continue }
            if prefix == "hdrgm" || (prefix == "GCamera" && name.hasPrefix("MotionPhoto")) || (prefix == "Container" && name == "Directory") {
                CGImageMetadataRemoveTagWithPath(metadata, nil, "\(prefix):\(name)" as CFString)
            }
        }
        return metadata
    }

    /// 원본에서 꺼낸 이미지는 ImageIO가 원본 메타데이터와 이어 두어, 원본에 IPTC가 있으면 넘긴 값만 써도
    /// 촬영 시각(DateTimeOriginal)에서 IPTC 날짜 칸(DateCreated·TimeCreated)을 다시 만든다(2026-11-21 확인).
    /// 같은 픽셀 버퍼로 CGImage를 새로 만들어 그 연결을 끊는다. `copy()`로는 끊기지 않는다. 픽셀은 복사하지 않는다.
    static func detachedFromSource(_ image: CGImage) -> CGImage? {
        guard let colorSpace = image.colorSpace, let provider = image.dataProvider else { return nil }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: image.bitsPerComponent, bitsPerPixel: image.bitsPerPixel,
                       bytesPerRow: image.bytesPerRow, space: colorSpace, bitmapInfo: image.bitmapInfo, provider: provider,
                       decode: nil, shouldInterpolate: image.shouldInterpolate, intent: image.renderingIntent)
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
        var extent = image.extent.integral
        if let maxPixelSize {
            // 회전을 반영한 크기 기준. 짧은 변은 반올림한다(안드로이드 `roundToInt`와 같게: 10240×6826 → 8192×5461).
            let width = extent.width
            let height = extent.height
            let longSide = max(width, height)
            if longSide > CGFloat(maxPixelSize) {
                let scale = CGFloat(maxPixelSize) / longSide
                let target = CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
                image = image.applyingFilter("CILanczosScaleTransform", parameters: [
                    kCIInputScaleKey: target.height / height,
                    kCIInputAspectRatioKey: (target.width / width) / (target.height / height),
                ])
                extent = CGRect(origin: image.extent.origin, size: target)
            }
        }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let rendered = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])
                .createCGImage(image, from: extent, format: .RGBA8, colorSpace: srgb)
        else { throw RenderError.encodingFailed }
        return rendered
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
