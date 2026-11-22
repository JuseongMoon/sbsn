import Foundation

/// 두 앱 공통 시각 표기(총괄 구현 결정): 한국 시각, 24시간제, 초 없음. 기기 설정(12시간제·다른 시간대)과 상관없이 같다.
/// 예: "14:10"(신청 마감 "14:10까지"), "11월 26일 14:10"(삭제 가능 시각).
public enum LaunchTime {
    static let seoul = TimeZone(identifier: "Asia/Seoul")!

    static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = seoul
        formatter.dateFormat = format
        return formatter
    }

    nonisolated(unsafe) static let clockFormatter = formatter("HH:mm")
    nonisolated(unsafe) static let dayClockFormatter = formatter("M월 d일 HH:mm")

    /// "14:10"
    public static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// "11월 26일 14:10"
    public static func dayClock(_ date: Date) -> String {
        dayClockFormatter.string(from: date)
    }
}
