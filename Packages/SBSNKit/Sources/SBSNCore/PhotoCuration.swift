import Foundation

/// 작가 선별 업로드의 규칙(D036·D038·D040, 공통 명세 "선별 전달 공통 명세").
///
/// 서버(규칙·`publishGallery`)가 강제하는 값과 같다. 앱은 거부될 요청을 보내지 않도록 먼저 이것으로 확인하고 작가에게 안내한다.
public enum PhotoCuration {
    /// 공개할 수 있는 장수(서버가 강제)
    public static let publishableCount = 5...8
    /// 안내만 하는 목표 장수
    public static let targetCount = 6
    /// 고화질본 긴 변 최소(PROV-04). 이보다 작은 사진은 받지 않는다.
    public static let minimumLongSide = 4_000
    /// 고화질본 파일(메타데이터 포함) 상한. 서버 규칙은 "미만"이다.
    public static let fullResolutionByteLimit = 50 * 1_024 * 1_024
    /// 미리보기 파일 상한(서버 규칙은 "미만")
    public static let previewByteLimit = 1_024 * 1_024
    /// 고화질본이 상한을 넘으면 차례로 낮춰 다시 만드는 품질(공통 명세, iOS)
    public static let fallbackQualities = [0.80, 0.75]
    /// 공개 뒤 새 구매를 받는 기간(168시간, 서버가 강제)
    public static let purchaseWindow: TimeInterval = 168 * 60 * 60
    /// 이보다 오래된 객체는 공개에 쓸 수 없다(버킷 수명 30일 - 구매 7일 - 하루 여유). 넘으면 새 ID로 다시 올린다.
    public static let objectAgeLimit: TimeInterval = 22 * 24 * 60 * 60
    /// 촬영 시각이 이 구간 밖이면 경고한다: [촬영 시작 - 10분, 지금]
    public static let captureLeadTime: TimeInterval = 10 * 60
    /// 종료 뒤 이 시간이 지나도록 공개하지 않으면 작가 앱이 다시 알리고 고객 화면은 지연 안내를 띄운다.
    public static let publishReminderDelay: TimeInterval = 30 * 60

    // MARK: - 사진 ID

    private static let idAlphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// 새 사진 ID(`p` + 소문자·숫자 12자). 파일 내용마다 새로 발급한다.
    public static func newPhotoID<G: RandomNumberGenerator>(using generator: inout G) -> String {
        "p" + String((0..<12).map { _ in idAlphabet.randomElement(using: &generator)! })
    }

    public static func newPhotoID() -> String {
        var generator = SystemRandomNumberGenerator()
        return newPhotoID(using: &generator)
    }

    /// 서버와 같은 형식(`^p[a-z0-9]{12}$`)인지
    public static func isValidPhotoID(_ id: String) -> Bool {
        let scalars = Array(id.unicodeScalars)
        guard scalars.count == 13, scalars[0] == "p" else { return false }
        return scalars.dropFirst().allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }

    // MARK: - 입력 검사

    /// 고른 파일을 받을 수 없는 이유. 문구는 작가에게 그대로 보인다(공통 명세).
    public enum Rejection: Sendable, Equatable, LocalizedError {
        /// ImageIO가 열지 못했다.
        case unreadable
        case raw
        /// JPEG·HEIC/HEIF 밖의 형식(PNG 등)
        case unsupportedFormat
        case tooSmall(longSide: Int)

        public var errorDescription: String? {
            switch self {
            case .unreadable, .unsupportedFormat: "이 사진은 이 폰에서 열 수 없는 형식입니다. 편집 앱에서 JPEG로 내보내 다시 골라 주세요."
            case .raw: "RAW 사진은 올릴 수 없습니다. JPEG로 내보내 주세요."
            case .tooSmall(let longSide):
                "긴 변 \(minimumLongSide.formatted())px 이상만 올릴 수 있습니다(이 사진 \(longSide.formatted())px). 잘라 내지 않은 원본 크기로 다시 내보내 주세요."
            }
        }
    }

    /// 형식과 크기(회전 반영 긴 변)로 받을지 정한다. 형식이 nil이면 열지 못한 파일이다. nil을 돌려주면 받는다.
    public static func rejection(format: InputFormat?, longSide: Int) -> Rejection? {
        switch format {
        case nil: return .unreadable
        case .raw: return .raw
        case .other: return .unsupportedFormat
        case .jpeg, .heif: return longSide < minimumLongSide ? .tooSmall(longSide: longSide) : nil
        }
    }

    public enum InputFormat: Sendable, Equatable {
        case jpeg
        case heif
        case raw
        case other
    }

    /// 촬영 시각이 이 촬영 시간대 밖이면 true(경고만 한다, 카메라 시계가 틀릴 수 있다). 시각이 없으면 경고하지 않는다.
    public static func isOutsideShootWindow(capturedAt: Date?, shootStartedAt: Date?, now: Date = Date()) -> Bool {
        guard let capturedAt, let shootStartedAt else { return false }
        return capturedAt < shootStartedAt.addingTimeInterval(-captureLeadTime) || capturedAt > now
    }

    // MARK: - 공개

    /// 공개 버튼을 막는 이유. nil이면 장수는 맞다.
    public static func countProblem(_ count: Int) -> String? {
        if count < publishableCount.lowerBound { return "\(publishableCount.lowerBound)장 이상 골라 주세요(지금 \(count)장)." }
        if count > publishableCount.upperBound { return "\(publishableCount.upperBound)장까지 공개할 수 있습니다(지금 \(count)장)." }
        return nil
    }
}
