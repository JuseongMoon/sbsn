#if os(iOS)
import Foundation
import UIKit

/// 출시 사진 다시 만들기(채팅 사진 L19, 작가 프로필 사진): 긴 변을 줄이고 메타데이터(GPS 포함) 없는 JPEG(품질 0.8, Android와 같은 값).
public enum LaunchImageEncoding {
    public static func jpeg(from data: Data, longSide: CGFloat = 1280, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, longSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // 픽셀만 다시 그려 원본 EXIF·GPS가 따라오지 않는다.
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }.jpegData(compressionQuality: quality)
    }
}
#endif
