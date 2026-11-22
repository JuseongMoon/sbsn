import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

/// 서버(Firebase) 연결 진입점. 앱은 Firebase 타입 대신 이 모듈의 타입만 쓴다.
public enum Backend {
    /// 앱 개발용 로컬 에뮬레이터(웹 저장소 `firebase/scripts/start_dev_emulators.sh`). 디버그 빌드에서 실행 인자
    /// `-SBSNEmulatorHost <주소>`를 줄 때만 쓴다(시뮬레이터 127.0.0.1, 실기기는 맥 LAN 주소 — 주소는 커밋하지 않는다).
    /// sbsn-dev의 MVP 흐름과 섞이지 않게 프로젝트 ID를 에뮬레이터 전용 demo 프로젝트로 바꾼다.
    public struct Emulator: Sendable, Equatable {
        public static let projectID = "demo-sbsn-functions"
        public static let storageBucket = "demo-sbsn-functions.appspot.com"
        public static let authPort = 19099
        public static let firestorePort = 18080
        public static let functionsPort = 15001
        public static let storagePort = 19199

        public let host: String
    }

    /// 지금 쓰는 에뮬레이터. nil이면 GoogleService-Info.plist의 실제 프로젝트(sbsn-dev)에 붙는다.
    nonisolated(unsafe) public private(set) static var emulator: Emulator?

    /// 앱 시작 시 한 번 호출한다. 앱 번들에 GoogleService-Info.plist가 있어야 한다.
    @MainActor
    public static func configure() {
        guard FirebaseApp.app() == nil else { return }
        #if DEBUG
        if let host = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["SBSNEmulatorHost"] as? String,
           !host.isEmpty, let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            options.projectID = Emulator.projectID
            options.storageBucket = Emulator.storageBucket
            FirebaseApp.configure(options: options)
            let emulator = Emulator(host: host)
            Auth.auth().useEmulator(withHost: host, port: Emulator.authPort)
            let settings = Firestore.firestore().settings
            settings.host = "\(host):\(Emulator.firestorePort)"
            settings.isSSLEnabled = false
            settings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = settings
            Storage.storage().useEmulator(withHost: host, port: Emulator.storagePort)
            self.emulator = emulator
            resetAuthIfBackendChanged(to: "emulator:\(host)")
            return
        }
        #endif
        FirebaseApp.configure()
        resetAuthIfBackendChanged(to: "default")
    }

    /// 키체인에 남은 로그인은 그 로그인을 만든 서버(sbsn-dev / 에뮬레이터)에서만 쓸 수 있다. 접속 대상이 바뀌었으면 지운다.
    /// 표시가 없는 기존 설치(지금 사용자)는 기본 서버로 보고 지우지 않는다. 에뮬레이터를 처음 쓸 때만 지운다.
    private static func resetAuthIfBackendChanged(to target: String) {
        let key = "SBSNAuthBackend"
        let previous = UserDefaults.standard.string(forKey: key)
        if previous != target, previous != nil || target != "default" {
            try? Auth.auth().signOut()
        }
        UserDefaults.standard.set(target, forKey: key)
    }

    /// 호출형 함수 인스턴스. 에뮬레이터를 쓰면 로컬 함수로 보낸다.
    static func functions(region: String) -> Functions {
        let functions = Functions.functions(region: region)
        if let emulator {
            functions.useEmulator(withHost: emulator.host, port: Emulator.functionsPort)
        }
        return functions
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
