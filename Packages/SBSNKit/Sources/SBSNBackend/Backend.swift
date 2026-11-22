import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation
import os

/// 서버(Firebase) 연결 진입점. 앱은 Firebase 타입 대신 이 모듈의 타입만 쓴다.
public enum Backend {
    /// 앱 개발용 로컬 에뮬레이터(웹 저장소 `firebase/scripts/start_dev_emulators.sh`). 디버그 빌드에서 실행 인자
    /// `-SBSNEmulatorHost <주소>`를 줄 때만 쓴다(시뮬레이터 127.0.0.1, 실기기는 맥 LAN 주소 — 주소는 커밋하지 않는다).
    /// sbsn-dev 데이터와 섞이지 않게 프로젝트 ID를 에뮬레이터 전용 demo 프로젝트로 바꾼다.
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
    /// 출시 1단계 화면(계정·지도)은 어느 쪽이든 늘 켜져 있다(D063).
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

    /// 저장된 로그인이 아직 서버에서 살아 있는지 본다(총괄 공통 기준, Android 9100316과 같은 목적).
    /// 앱이 앞으로 올 때 부른다. false면 로그인이 없거나 서버에서 무효(지워짐·막힘·갱신 토큰 폐기)라 로그아웃했다.
    /// 앱은 그때 새 익명 계정으로 다시 시작한다(고객은 둘러보기, 작가는 로그인 관문).
    /// 네트워크 오류·시간 초과는 판단할 수 없어 로그인을 그대로 두고 true를 돌려준다(오프라인에서 로그인이 사라지지 않게).
    /// 서버 확인은 1분에 한 번까지 한다.
    public static func validateSession() async -> Bool {
        await SignIn.shared.validate()
    }

    /// 서버가 이 로그인을 더는 받지 않는다는 오류인지(계정 삭제·정지, 갱신 토큰 무효·폐기).
    /// `INVALID_REFRESH_TOKEN`(다른 서버가 만든 로그인 등)은 SDK가 따로 분류하지 않아 서버 응답 문구로 본다.
    static func isDeadSession(_ error: Error) -> Bool {
        let deadCodes: Set<Int> = [AuthErrorCode.userNotFound.rawValue, AuthErrorCode.userDisabled.rawValue,
                                   AuthErrorCode.invalidUserToken.rawValue, AuthErrorCode.userTokenExpired.rawValue]
        let serverCodes = ["INVALID_REFRESH_TOKEN", "USER_NOT_FOUND", "USER_DISABLED", "TOKEN_EXPIRED"]
        var next: NSError? = error as NSError
        var depth = 0
        while let current = next, depth < 5 {
            if current.domain == AuthErrors.domain {
                if deadCodes.contains(current.code) { return true }
                if current.code != AuthErrorCode.networkError.rawValue,
                   serverCodes.contains(where: String(describing: current.userInfo).contains) {
                    return true
                }
            }
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }
}

// 사진 업로드와 푸시 토큰 등록이 동시에 시작돼도 익명 로그인이 한 번만 일어나도록, 진행 중인 로그인을 함께 기다린다.
// (실기기에서 동시 업로드가 익명 사용자를 둘 만들어 티켓 소유자와 업로더가 달라지는 문제가 있었다.)
private actor SignIn {
    static let shared = SignIn()
    static let log = Logger(subsystem: "com.ScienceFiction.sbsn", category: "auth")
    /// 서버 확인에 쓰는 시간. 넘으면 판단할 수 없어 로그인을 그대로 둔다.
    static let checkTimeout: Duration = .seconds(5)
    static let checkInterval: Duration = .seconds(60)

    private var task: Task<String, Error>?
    /// 이 프로세스에서 저장된 로그인을 서버에 확인했는지(앱 시작 때 한 번)
    private var checkedOnLaunch = false
    private var lastCheck: ContinuousClock.Instant?

    func userID() async throws -> String {
        if !checkedOnLaunch {
            checkedOnLaunch = true
            _ = await discardIfDead()
        }
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

    func validate() async -> Bool {
        guard Auth.auth().currentUser != nil else { return false }
        if let lastCheck, ContinuousClock.now - lastCheck < Self.checkInterval {
            return true
        }
        return !(await discardIfDead())
    }

    /// 저장된 로그인을 서버에서 새로 받아 본다(ID 토큰 강제 갱신). 무효면 로그아웃하고 true.
    /// 캐시된 ID 토큰은 계정이 지워진 뒤에도 1시간까지 남아 있어 강제 갱신으로만 알 수 있다.
    /// SDK도 갱신 오류 일부(계정 없음·정지)에서는 스스로 로그아웃하지만 `INVALID_REFRESH_TOKEN`에서는 하지 않는다.
    func discardIfDead() async -> Bool {
        guard Auth.auth().currentUser != nil else { return false }
        lastCheck = .now
        switch await Self.refreshOutcome() {
        case .alive, .unknown:
            return false
        case .dead:
            Self.log.notice("저장된 로그인이 서버에서 무효라 로그아웃함")
            task = nil
            try? Auth.auth().signOut()
            return true
        }
    }

    enum RefreshOutcome: Sendable {
        case alive
        case dead
        /// 네트워크 오류·시간 초과(판단 못 함)
        case unknown
    }

    /// 강제 갱신 결과. SDK 호출은 취소할 수 없어 시간 초과와 경주시키고 먼저 끝난 쪽을 쓴다.
    static func refreshOutcome() async -> RefreshOutcome {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ outcome: RefreshOutcome) {
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: outcome) }
            }
            Task {
                guard let user = Auth.auth().currentUser else {
                    finish(.dead)
                    return
                }
                do {
                    _ = try await user.getIDTokenResult(forcingRefresh: true)
                    finish(.alive)
                } catch {
                    let dead = Backend.isDeadSession(error)
                    if !dead {
                        log.info("로그인 확인 실패(그대로 둠): \((error as NSError).code, privacy: .public)")
                    }
                    finish(dead ? .dead : .unknown)
                }
            }
            Task {
                try? await Task.sleep(for: checkTimeout)
                finish(.unknown)
            }
        }
    }
}
