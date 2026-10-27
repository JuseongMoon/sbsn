import FirebaseAuth
import FirebaseCore

/// 서버(Firebase) 연결 진입점. 앱은 Firebase 타입 대신 이 모듈의 타입만 쓴다.
public enum Backend {
    /// 앱 시작 시 한 번 호출한다. 앱 번들에 GoogleService-Info.plist가 있어야 한다.
    @MainActor
    public static func configure() {
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }

    /// 로그인한 사용자 ID. 아직 로그인하지 않았으면 익명으로 로그인한다.
    public static func signedInUserID() async throws -> String {
        try await SignIn.shared.userID()
    }

    /// 익명 계정을 버리고 다음 호출에서 새 계정을 만든다. 시험에서 "새 작가·새 고객"을 만들 때만 쓴다(디버그 메뉴).
    /// 익명 계정은 키체인에 남아 앱을 지웠다 깔아도 같은 uid가 돌아올 수 있다.
    public static func signOut() async throws {
        try await SignIn.shared.signOut()
    }
}

// 사진 업로드와 푸시 토큰 등록이 동시에 시작돼도 익명 로그인이 한 번만 일어나도록, 진행 중인 로그인을 함께 기다린다.
// (실기기에서 동시 업로드가 익명 사용자를 둘 만들어 티켓 소유자와 업로더가 달라지는 문제가 있었다.)
private actor SignIn {
    static let shared = SignIn()

    private var task: Task<String, Error>?

    func userID() async throws -> String {
        if let user = Auth.auth().currentUser {
            return user.uid
        }
        if let task {
            return try await task.value
        }
        let task = Task { try await Auth.auth().signInAnonymously().user.uid }
        self.task = task
        do {
            return try await task.value
        } catch {
            self.task = nil
            throw error
        }
    }

    func signOut() throws {
        task = nil
        try Auth.auth().signOut()
    }
}
