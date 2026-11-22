#if os(iOS) && DEBUG
import AuthenticationServices
import SBSNBackend
import SwiftUI

/// 개발 메뉴: 출시 로그인 제공자 시험(총괄 순서 2번, sbsn-dev는 Auth만).
///
/// Google·Apple 로그인과 익명 연결만 한다. 출시 함수(`saveLaunchProfileV1` 등)는 부르지 않는다(sbsn-dev에는 아직 배포 전).
/// 익명이면 연결해 uid를 유지하고, 그 자격 증명이 이미 다른 계정에 있으면 그 계정으로 로그인한다(로그인 시트와 같은 `AccountService`).
/// 보고에 쓰도록 uid는 앞 6자만 보인다. 디버그 빌드에만 있다.
public struct LaunchAuthProbeSection: View {
    let onAccountChanged: () async -> Void
    let onSignOut: () async -> Void
    @State private var account = AccountService.current
    @State private var nonce = AccountService.makeNonce()
    @State private var result: String?
    @State private var isWorking = false

    /// `onAccountChanged`: 연결·로그인 뒤(uid가 바뀌었으면 앱이 리스너를 다시 붙인다). `onSignOut`: 로그아웃해 새 익명 계정으로.
    public init(onAccountChanged: @escaping () async -> Void, onSignOut: @escaping () async -> Void) {
        self.onAccountChanged = onAccountChanged
        self.onSignOut = onSignOut
    }

    public var body: some View {
        Section {
            LabeledContent("계정", value: Self.summary(account))
                .accessibilityIdentifier("dev.auth.account")
            SignInWithAppleButton(.continue) { request in
                nonce = AccountService.makeNonce()
                request.requestedScopes = []
                request.nonce = AccountService.sha256(nonce)
            } onCompletion: { completion in
                Task { await finishApple(completion) }
            }
            .frame(height: 44)
            .disabled(isWorking)
            .accessibilityIdentifier("dev.auth.apple")
            Button("Google로 계속하기") {
                Task { await finishGoogle() }
            }
            .disabled(isWorking)
            .accessibilityIdentifier("dev.auth.google")
            Button("로그아웃(새 익명 계정)", role: .destructive) {
                Task {
                    isWorking = true
                    await onSignOut()
                    account = AccountService.current
                    result = "로그아웃 → \(Self.summary(account))"
                    isWorking = false
                }
            }
            .disabled(isWorking)
            .accessibilityIdentifier("dev.auth.signOut")
            if let result {
                Text(result)
                    .font(.footnote)
                    .accessibilityIdentifier("dev.auth.result")
            }
        } header: {
            Text("출시 로그인 시험(Auth만)")
        } footer: {
            Text("Google·Apple 로그인과 익명 연결만 합니다. 출시 함수(프로필 저장 등)는 부르지 않습니다. uid는 앞 6자만 보입니다.")
        }
        .onAppear { account = AccountService.current }
    }

    static func summary(_ account: AccountService.Account?) -> String {
        guard let account else { return "-" }
        let kind = account.isAnonymous ? "익명" : "연결"
        let providers = account.providers.isEmpty ? "" : " · " + account.providers.joined(separator: ", ")
        return "\(kind)\(providers) · \(account.uid.prefix(6))…"
    }

    private func finishApple(_ completion: Result<ASAuthorization, Error>) async {
        switch completion {
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            result = "Apple 취소"
        case .failure(let error):
            result = "Apple 실패: \(error.localizedDescription)"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8)
            else {
                result = "Apple 로그인 정보를 읽지 못했습니다."
                return
            }
            let rawNonce = nonce
            await link("Apple") { try await AccountService.signIn(appleIDToken: token, rawNonce: rawNonce) }
        }
    }

    private func finishGoogle() async {
        #if canImport(GoogleSignIn)
        do {
            guard let tokens = try await GoogleSignInSupport.signIn() else {
                result = "Google 취소"
                return
            }
            await link("Google") { try await AccountService.signIn(googleIDToken: tokens.idToken, accessToken: tokens.accessToken) }
        } catch {
            result = "Google 실패: \(error.localizedDescription)"
        }
        #endif
    }

    private func link(_ provider: String, _ signIn: () async throws -> AccountService.Account) async {
        isWorking = true
        defer { isWorking = false }
        let before = AccountService.current
        do {
            let after = try await signIn()
            account = after
            let how = before?.uid == after.uid ? "익명 계정에 연결(uid 유지)" : "이미 있는 계정으로 로그인(uid 바뀜)"
            result = "\(provider) 성공: \(how) → \(Self.summary(after))"
            await onAccountChanged()
        } catch {
            account = AccountService.current
            result = "\(provider) 실패: \(error.localizedDescription)"
        }
    }
}
#endif
