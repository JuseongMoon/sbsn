import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 고객에게 먼저 보여 줄 미리보기 JPEG를 만든다.
///
/// 원본의 회전 정보는 픽셀에 반영하고, 위치·기기 정보 같은 메타데이터는 넣지 않는다.
/// LTE 업로드로 원본(약 20MB)은 장당 수십 초가 걸리므로, 미리보기(수백 KB)를 먼저 올려 고객이 바로 보게 한다.
public enum PhotoPreviewRenderer {
    public static let defaultMaxPixelSize = 2048
    public static let defaultQuality = 0.8

    public enum RenderError: Error {
        case unreadableImage
        case encodingFailed
    }

    public static func renderJPEG(
        from source: URL,
        to destination: URL,
        maxPixelSize: Int = defaultMaxPixelSize,
        quality: Double = defaultQuality
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
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw RenderError.unreadableImage
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
}
