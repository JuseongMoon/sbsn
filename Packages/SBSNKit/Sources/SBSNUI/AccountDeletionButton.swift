#if os(iOS)
import AuthenticationServices
import SBSNBackend
import SwiftUI
import UIKit

/// 계정 칸의 "계정 삭제"(L10). 두 앱이 같이 쓴다. Android `AccountDeletionButton`과 문구·식별자를 맞춘다.
///
/// - 서버 삭제 함수(`requestAccountDeletionV1`)가 공개 지도에서 바로 내리고 데이터·Apple 토큰·Auth를 정리한다.
/// - 서버는 5분 안에 로그인한 계정만 받는다. 오래됐으면 "다시 로그인한 뒤 요청해 주세요."가 오고 그 문구를 그대로 보인다.
/// - Apple 연결 계정은 Apple로 다시 인증해 받은 인가 코드와 이 앱의 App ID를 함께 보낸다(iOS 경로).
/// - 확인 창 문구는 정책 담당이 정할 때까지 가안이다.
public struct AccountDeletionButton: View {
    let onRequested: (_ status: String) async -> Void
    @State private var confirming = false
    @State private var isWorking = false
    @State private var message: String?

    /// `onRequested`: 삭제를 접수한 뒤(로그아웃해 둘러보기·로그인 화면으로 돌아간다)
    public init(onRequested: @escaping (_ status: String) async -> Void) {
        self.onRequested = onRequested
    }

    public var body: some View {
        Button("계정 삭제", role: .destructive) { confirming = true }
            .disabled(isWorking)
            .accessibilityIdentifier("my.deleteAccount")
            .alert("계정을 삭제할까요?", isPresented: $confirming) {
                Button("삭제", role: .destructive) {
                    Task { await delete() }
                }
                .accessibilityIdentifier("my.deleteAccount.confirm")
                Button("취소", role: .cancel) {}
            } message: {
                Text("삭제를 요청하면 지도와 프로필에서 바로 내려가고 되돌릴 수 없습니다. 산 사진은 먼저 휴대폰에 저장해 두세요.")
            }
        if isWorking {
            ProgressView()
        }
        if let message {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityIdentifier("my.deleteAccount.error")
        }
    }

    private func delete() async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            var appleCode: String?
            if AccountService.current?.providers.contains("apple.com") == true {
                appleCode = try await reauthenticateWithApple()
            }
            let status = try await AccountService.requestDeletion(appleCode: appleCode,
                                                                 appleClientId: appleCode == nil ? nil : Bundle.main.bundleIdentifier)
            await onRequested(status)
        } catch let error as ASAuthorizationError where error.code == .canceled {
            message = "Apple 재인증을 취소했습니다."
        } catch {
            message = error.localizedDescription
        }
    }

    /// Apple로 다시 인증하고(Firebase 재인증까지) 삭제 요청에 넣을 인가 코드를 돌려준다.
    private func reauthenticateWithApple() async throws -> String {
        let nonce = AccountService.makeNonce()
        let credential = try await AppleAuthorization().perform(hashedNonce: AccountService.sha256(nonce))
        guard let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
              let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8)
        else { throw ReauthError.missingCredential }
        try await AccountService.reauthenticate(appleIDToken: token, rawNonce: nonce)
        return code
    }

    private enum ReauthError: LocalizedError {
        case missingCredential
        var errorDescription: String? { "Apple 재인증 정보를 읽지 못했습니다." }
    }
}

/// 단추 없이 Apple 인증 창을 띄운다(재인증용). 끝날 때까지 자신을 잡아 둔다.
@MainActor
final class AppleAuthorization: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    func perform(hashedNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = hashedNonce
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        MainActor.assumeIsolated {
            if let credential {
                continuation?.resume(returning: credential)
            } else {
                continuation?.resume(throwing: ASAuthorizationError(.failed))
            }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
#endif
