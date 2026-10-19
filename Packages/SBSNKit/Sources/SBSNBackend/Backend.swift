import FirebaseCore

/// 서버(Firebase) 연결 진입점. 앱은 Firebase 타입 대신 이 모듈의 타입만 쓴다.
public enum Backend {
    /// 앱 시작 시 한 번 호출한다. 앱 번들에 GoogleService-Info.plist가 있어야 한다.
    @MainActor
    public static func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }
}
