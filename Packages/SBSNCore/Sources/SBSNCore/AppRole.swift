/// 십분스냅 계정이 어떤 앱으로 서비스를 쓰는지 나타낸다.
public enum AppRole: String, Codable, CaseIterable, Sendable {
    case customer
    case photographer
}
