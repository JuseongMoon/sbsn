import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import Foundation

/// 출시 1단계 계정(D051·L04~L09, 웹 계약 `firebase/docs/launch-phase-1.md`).
///
/// - 고객은 익명으로 둘러보다가 채팅·신청 전에 Google·Apple로 로그인한다. 익명 계정에 자격 증명을 **연결**해 uid를 유지한다.
/// - 그 자격 증명이 이미 다른 계정에 연결돼 있으면 그 계정으로 로그인하고 익명 계정은 버린다(익명은 둘러보기만, L05, 자동 병합 없음).
/// - 상대에게 보이는 이름은 앱 닉네임이다(L06). 로그인 뒤 `saveLaunchProfileV1`로 만 14세 확인과 함께 저장한다(처음 null이면 서버가 만든다).
/// - 비밀번호 시험 로그인은 디버그 빌드의 개발용 에뮬레이터에서만 쓴다(L09, 서버도 `launchTest` 클레임과 demo 프로젝트에서만 받는다).
public enum AccountService {
    /// 지금 로그인한 계정의 요약
    public struct Account: Sendable, Equatable {
        public let uid: String
        public let isAnonymous: Bool
        /// 연결된 제공자(`apple.com`, `google.com`, `password`)
        public let providers: [String]

        public var isLinked: Bool { !isAnonymous }
    }

    public enum AccountError: LocalizedError {
        case notSignedIn
        case malformedResponse
        case testLoginUnavailable

        public var errorDescription: String? {
            switch self {
            case .notSignedIn: "로그인 상태를 확인하지 못했습니다."
            case .malformedResponse: "서버 응답을 읽지 못했습니다."
            case .testLoginUnavailable: "시험 로그인은 개발용 에뮬레이터에서만 쓸 수 있습니다."
            }
        }
    }

    static let region = "asia-northeast3"

    public static var current: Account? {
        guard let user = Auth.auth().currentUser else { return nil }
        return Account(uid: user.uid, isAnonymous: user.isAnonymous, providers: user.providerData.map(\.providerID))
    }

    // MARK: - Apple

    /// Apple 로그인 요청마다 새 nonce를 만든다. Apple에는 `sha256(raw)`를, Firebase에는 원래 값을 넘긴다.
    public static func makeNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters[Int.random(in: 0..<characters.count, using: &generator)] })
    }

    public static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Apple 로그인 결과로 연결 또는 로그인한다. 이름은 첫 로그인 때만 오지만 화면에 쓰지 않는다(L06, 닉네임을 쓴다).
    public static func signIn(appleIDToken: String, rawNonce: String) async throws -> Account {
        let credential = OAuthProvider.appleCredential(withIDToken: appleIDToken, rawNonce: rawNonce, fullName: nil)
        return try await linkOrSignIn(credential)
    }

    // MARK: - Google

    /// 이 앱의 Google OAuth 클라이언트 ID(GoogleService-Info.plist `CLIENT_ID`). Google 로그인 화면 설정에 쓴다.
    public static var googleClientID: String? {
        FirebaseApp.app()?.options.clientID
    }

    /// Google 로그인 결과(ID 토큰·액세스 토큰)로 연결 또는 로그인한다(익명이면 연결, 이미 있는 계정이면 그 계정으로, Apple과 같다).
    public static func signIn(googleIDToken: String, accessToken: String) async throws -> Account {
        try await linkOrSignIn(GoogleAuthProvider.credential(withIDToken: googleIDToken, accessToken: accessToken))
    }

    // MARK: - 시험 로그인(디버그·에뮬레이터 전용, L09)

    /// 이메일·비밀번호 시험 계정으로 로그인한다. 출시 함수는 이 계정에 `launchTest: true` 클레임이 있을 때만 받는다.
    public static func signInForTesting(email: String, password: String) async throws -> Account {
        #if DEBUG
        guard Backend.emulator != nil else { throw AccountError.testLoginUnavailable }
        try await Auth.auth().signIn(withEmail: email, password: password)
        return try await refreshedAccount()
        #else
        throw AccountError.testLoginUnavailable
        #endif
    }

    // MARK: - 공통

    /// 익명이면 연결하고, 자격 증명이 이미 다른 계정에 연결돼 있으면 그 계정으로 로그인한다(익명 계정은 버린다).
    static func linkOrSignIn(_ credential: AuthCredential) async throws -> Account {
        if let user = Auth.auth().currentUser, user.isAnonymous {
            do {
                try await user.link(with: credential)
            } catch let error as NSError where error.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                let updated = error.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential ?? credential
                try await Auth.auth().signIn(with: updated)
            }
        } else {
            try await Auth.auth().signIn(with: credential)
        }
        return try await refreshedAccount()
    }

    /// 연결 뒤에는 ID 토큰을 새로 받아야 서버가 제공자를 안다(웹 계약).
    static func refreshedAccount() async throws -> Account {
        guard let user = Auth.auth().currentUser else { throw AccountError.notSignedIn }
        _ = try await user.getIDTokenResult(forcingRefresh: true)
        guard let account = current else { throw AccountError.notSignedIn }
        return account
    }

    /// 로그아웃한다. 다음 `Backend.signedInUserID()`에서 새 익명 계정으로 둘러보기를 이어 간다.
    public static func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - 계정 삭제(L10)

    /// Apple로 다시 인증한다. 서버는 5분 안에 로그인한 계정의 삭제 요청만 받는다(웹 계약 `requestAccountDeletionV1`).
    public static func reauthenticate(appleIDToken: String, rawNonce: String) async throws {
        guard let user = Auth.auth().currentUser else { throw AccountError.notSignedIn }
        let credential = OAuthProvider.appleCredential(withIDToken: appleIDToken, rawNonce: rawNonce, fullName: nil)
        try await user.reauthenticate(with: credential)
    }

    /// 계정 삭제를 요청하고 삭제 작업 상태(`queued`, `awaiting-apple-revocation` 등)를 돌려준다.
    /// 서버가 공개 지도에서 바로 내리고 출시 쓰기를 막은 뒤 프로필·기기·위치·역할·채팅 본문·Auth를 정리한다.
    /// Apple 연결 계정은 방금 받은 인가 코드와 이 앱의 App ID를 함께 보낸다(서버가 Apple 토큰을 취소한다). 그 밖에는 nil.
    public static func requestDeletion(appleCode: String?, appleClientId: String?) async throws -> String {
        var data: [String: Any] = ["confirmed": true]
        if let appleCode, let appleClientId {
            data["appleCode"] = appleCode
            data["appleClientId"] = appleClientId
        }
        let response = try await Backend.functions(region: region).httpsCallable("requestAccountDeletionV1").call(data)
        return (response.data as? [String: Any])?["status"] as? String ?? "queued"
    }

    /// 만 14세 확인과 닉네임을 저장하고 서버가 정한 닉네임을 돌려준다(`saveLaunchProfileV1`).
    /// `nickname`이 nil이면 처음에는 서버가 만들고, 그 뒤에는 있던 이름을 그대로 둔다(1~30자, 제어문자·@ 불가).
    public static func saveProfile(age14Confirmed: Bool, nickname: String?) async throws -> String {
        let callable = Backend.functions(region: region).httpsCallable("saveLaunchProfileV1")
        let response = try await callable.call(["age14Confirmed": age14Confirmed, "nickname": nickname as Any? ?? NSNull()])
        guard let data = response.data as? [String: Any], let saved = data["nickname"] as? String else {
            throw AccountError.malformedResponse
        }
        return saved
    }
}
