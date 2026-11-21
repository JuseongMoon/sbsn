import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 작가가 고른 파일을 디코드하지 않고 속성만 읽은 결과(D040 ③ 입력 검사의 재료).
///
/// 형식·해상도·촬영 시각만 본다. 받아도 되는지는 `SBSNCore.PhotoCuration`이 정한다.
public struct PhotoInspection: Sendable, Equatable {
    public enum Format: Sendable, Equatable {
        case jpeg
        case heif
        case raw
        /// ImageIO가 읽기는 하지만 받지 않는 형식(PNG 등). 값은 형식 식별자
        case other(String)
    }

    public let format: Format
    /// 회전 정보를 반영한 크기(세로 사진이면 가로·세로가 바뀐다)
    public let width: Int
    public let height: Int
    /// EXIF 촬영 시각. 없으면 nil(라이트룸에서 메타데이터를 빼고 내보낸 경우 등)
    public let capturedAt: Date?

    public var longSide: Int { max(width, height) }

    public init(format: Format, width: Int, height: Int, capturedAt: Date?) {
        self.format = format
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
    }

    /// ImageIO가 열 수 없으면 nil(앱 안내: "이 폰에서 열 수 없는 형식").
    public static func of(_ url: URL) -> PhotoInspection? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let identifier = CGImageSourceGetType(source) as String?
        else { return nil }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotates = (5...8).contains(orientation)
        return PhotoInspection(format: format(of: identifier), width: rotates ? height : width, height: rotates ? width : height,
                               capturedAt: captureDate(from: properties))
    }

    static func format(of identifier: String) -> Format {
        guard let type = UTType(identifier) else { return .other(identifier) }
        if type.conforms(to: .jpeg) { return .jpeg }
        if type.conforms(to: .heif) || type.conforms(to: .heic) { return .heif }
        if type.conforms(to: .rawImage) { return .raw }
        return .other(identifier)
    }

    /// EXIF `DateTimeOriginal`(+ `OffsetTimeOriginal`·`SubsecTimeOriginal`). 시간대가 없으면 기기 시간대로 읽는다.
    public static func captureDate(from properties: [CFString: Any]) -> Date? {
        guard let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var text = original
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            text += offset
        } else {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            formatter.timeZone = .current
        }
        guard let date = formatter.date(from: text) else { return nil }
        if let subsec = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, let fraction = Double("0." + subsec) {
            return date.addingTimeInterval(fraction)
        }
        return date
    }
}
