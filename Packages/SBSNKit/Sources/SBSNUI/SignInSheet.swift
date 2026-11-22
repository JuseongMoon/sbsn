#if os(iOS)
import AuthenticationServices
import SBSNBackend
import SwiftUI

/// 출시 로그인 시트(설계 문서 1.1, D051·L04·L06·L09·L28). 두 앱이 같이 쓴다.
///
/// - Apple을 위에, Google을 아래에 같은 크기로 둔다. 만 14세 확인을 켜야 단추가 눌린다.
/// - Google은 GoogleSignIn 계정 고르기 화면을 쓴다(앱 `.onOpenURL`에서 `GoogleSignInSupport.handle`).
/// - 로그인하면 `saveLaunchProfileV1`으로 만 14세 확인을 저장하고 서버가 정한 닉네임을 받는다.
/// - 디버그 빌드에서 개발용 에뮬레이터를 쓸 때만 비밀번호 시험 로그인을 보인다(L09).
public struct SignInSheet: View {
    /// 고객은 "나중에"로 둘러보기로 돌아갈 수 있다. 작가 앱은 처음부터 로그인해야 하므로 false.
    let allowsLater: Bool
    let onSignedIn: (_ nickname: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var age14Confirmed = false
    @State private var nonce = AccountService.makeNonce()
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var testEmail = ""
    @State private var testPassword = ""

    public init(allowsLater: Bool, onSignedIn: @escaping (_ nickname: String) -> Void) {
        self.allowsLater = allowsLater
        self.onSignedIn = onSignedIn
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(allowsLater ? "채팅과 촬영 신청은 로그인 뒤 할 수 있습니다." : "작가 앱은 로그인한 뒤 쓸 수 있습니다.")
                        .foregroundStyle(.secondary)
                    Toggle("만 14세 이상입니다", isOn: $age14Confirmed)
                        .accessibilityIdentifier("signIn.age14")
                    Text("계속하면 이용약관과 개인정보 처리방침에 동의하게 됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    SignInWithAppleButton(.continue) { request in
                        nonce = AccountService.makeNonce()
                        request.requestedScopes = []
                        request.nonce = AccountService.sha256(nonce)
                    } onCompletion: { result in
                        Task { await finishApple(result) }
                    }
                    .frame(height: 48)
                    .disabled(!age14Confirmed || isWorking)
                    .accessibilityIdentifier("signIn.apple")
                    Button {
                        Task { await finishGoogle() }
                    } label: {
                        Label("Google로 계속하기", systemImage: "g.circle")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .disabled(!age14Confirmed || isWorking)
                    .accessibilityIdentifier("signIn.google")
                }
                if Backend.emulator != nil {
                    testLoginSection
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("signIn.error")
                    }
                }
            }
            .navigationTitle("십분스냅에 로그인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsLater {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("나중에") { dismiss() }
                            .accessibilityIdentifier("signIn.later")
                    }
                }
            }
            .overlay {
                if isWorking { ProgressView() }
            }
            .interactiveDismissDisabled(!allowsLater)
        }
    }

    /// 디버그·에뮬레이터 전용(L09). 계정에는 운영자가 `launchTest: true` 클레임을 붙여 둔다.
    private var testLoginSection: some View {
        Section("개발: 시험 로그인(에뮬레이터)") {
            TextField("이메일", text: $testEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("signIn.test.email")
            // 에뮬레이터 시험 계정 전용(실제 암호가 아니다). SecureField를 쓰면 iOS가 "암호를 저장하겠습니까?"를 띄워
            // 다음 조작을 막으므로 일반 칸으로 받는다.
            TextField("비밀번호", text: $testPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("signIn.test.password")
            Button("시험 계정으로 로그인") {
                Task { await run { _ = try await AccountService.signInForTesting(email: testEmail, password: testPassword) } }
            }
            .disabled(!age14Confirmed || testEmail.isEmpty || testPassword.isEmpty || isWorking)
            .accessibilityIdentifier("signIn.test.submit")
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            return
        case .failure(let error):
            errorMessage = "Apple 로그인에 실패했습니다: \(error.localizedDescription)"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple 로그인 정보를 읽지 못했습니다."
                return
            }
            let rawNonce = nonce
            await run { _ = try await AccountService.signIn(appleIDToken: token, rawNonce: rawNonce) }
        }
    }

    /// Google 계정 고르기 → 익명이면 연결, 이미 있는 계정이면 그 계정으로 로그인(Apple과 같다).
    private func finishGoogle() async {
        #if canImport(GoogleSignIn)
        errorMessage = nil
        do {
            guard let tokens = try await GoogleSignInSupport.signIn() else { return }
            await run { _ = try await AccountService.signIn(googleIDToken: tokens.idToken, accessToken: tokens.accessToken) }
        } catch {
            errorMessage = "Google 로그인에 실패했습니다: \(error.localizedDescription)"
        }
        #endif
    }

    /// 로그인한 뒤 만 14세 확인을 저장하고 닉네임을 받아 끝낸다.
    private func run(_ signIn: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await signIn()
            let nickname = try await AccountService.saveProfile(age14Confirmed: true, nickname: nil)
            onSignedIn(nickname)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
