import FirebaseMessaging
import Foundation
import SBSNCore

/// 출시 알림 설치 등록(W1, 웹 `registerLaunchPushTokenV1`·`unregisterLaunchPushTokenV1`).
///
/// - 설치마다 ID 하나(이 앱을 지웠다 깔면 새 ID)를 로그인한 계정에 묶는다. 같은 설치로 다른 계정이 등록하면 서버가 바꿔 낀다.
/// - 연결된 계정(Apple·Google)이고 프로필이 있어야 받는다. 작가는 운영 승인도 있어야 한다. 익명이면 부르지 않는다.
/// - 로그아웃 전에 해제한다(계정 삭제는 서버가 정리한다). 실패해도 앱 흐름은 막지 않는다.
public enum LaunchPush {
    static let installationKey = "SBSNLaunchInstallationId"

    /// 이 설치의 ID(`[A-Za-z0-9_-]`, 처음 부를 때 만든다)
    public static var installationId: String {
        if let stored = UserDefaults.standard.string(forKey: installationKey) { return stored }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: installationKey)
        return created
    }

    /// APNs 기기 토큰을 FCM에 넘긴다(앱 델리게이트가 받을 때마다).
    @MainActor
    public static func setAPNsToken(_ token: Data) {
        Messaging.messaging().apnsToken = token
    }

    /// 지금 계정으로 이 설치를 등록한다. 익명이면 하지 않는다.
    @MainActor
    public static func registerIfLinked(role: LaunchMatch.Role) async {
        guard AccountService.current?.isLinked == true else { return }
        do {
            let token = try await Messaging.messaging().token()
            try await register(role: role, fcmToken: token)
        } catch {
            print("SBSN 출시 알림 등록 실패: \(error.localizedDescription)")
        }
    }

    /// 토큰을 직접 주고 등록한다(시험도 쓴다).
    public static func register(role: LaunchMatch.Role, fcmToken: String) async throws {
        _ = try await LaunchMatchService.call("registerLaunchPushTokenV1", [
            "appRole": role.rawValue, "installationId": installationId, "fcmToken": fcmToken,
        ])
    }

    /// 로그아웃 전에 이 설치를 지금 계정에서 뗀다.
    public static func unregister(role: LaunchMatch.Role) async {
        guard AccountService.current?.isLinked == true else { return }
        _ = try? await LaunchMatchService.call("unregisterLaunchPushTokenV1", [
            "appRole": role.rawValue, "installationId": installationId,
        ])
    }
}
