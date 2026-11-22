#if os(iOS) && canImport(GoogleSignIn)
import GoogleSignIn
import SBSNBackend
import UIKit

/// Google 로그인 화면(GoogleSignIn, D051·L04). 두 앱이 같이 쓴다.
///
/// 앱 Info.plist에 `REVERSED_CLIENT_ID` URL scheme이 있어야 한다(값은 git 제외 `Config/*.local.xcconfig`).
/// 없으면 GoogleSignIn이 예외로 앱을 멈추므로, 먼저 확인하고 없으면 오류 문구를 보인다.
public enum GoogleSignInSupport {
    enum Failure: LocalizedError {
        case notConfigured
        case missingToken

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Google 로그인을 아직 쓸 수 없습니다(앱에 Google 로그인 설정이 없습니다)."
            case .missingToken: "Google 로그인 정보를 읽지 못했습니다."
            }
        }
    }

    /// 앱 `.onOpenURL`에서 부른다(Google 로그인에서 돌아오는 주소).
    @MainActor
    @discardableResult
    public static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`
    static func reversedClientID(_ clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static func hasURLScheme(for clientID: String) -> Bool {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.contains(reversedClientID(clientID))
    }

    /// 계정 고르기 → ID 토큰·액세스 토큰. 사용자가 취소하면 nil.
    @MainActor
    static func signIn() async throws -> (idToken: String, accessToken: String)? {
        guard let clientID = AccountService.googleClientID, hasURLScheme(for: clientID), let presenter = topViewController() else {
            throw Failure.notConfigured
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else { throw Failure.missingToken }
            return (idToken, result.user.accessToken.tokenString)
        } catch let error as GIDSignInError where error.code == .canceled {
            return nil
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif
