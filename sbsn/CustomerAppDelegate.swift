//
//  CustomerAppDelegate.swift
//  sbsn
//

import SBSNBackend
import UIKit
import UserNotifications

/// 고객 앱의 원격 알림. 작가 메시지, 작가의 시작·취소, 촬영 종료, 나중에 올라온 구매 사진이 배너로 온다(`CustomerPush`).
///
/// 앱이 백그라운드에 있으면 티켓 리스너가 멈추므로, 만나러 걸어가며 폰을 넣어 둔 고객도 작가의 연락을 알 수 있게 한다.
/// 알림을 탭하면 앱이 열리고 진행 중인 티켓 화면이 그대로 보인다.
final class CustomerAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // 권한과 관계없이 등록한다. 권한은 매칭된 뒤 처음 티켓 화면을 열 때 묻는다.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
            do {
                try await CustomerPush.register(apnsToken: deviceToken)
            } catch {
                print("SBSN 고객 알림 토큰 등록 실패: \(error)")
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        print("SBSN 원격 알림 등록 실패: \(error)")
    }

    /// 앱이 화면에 떠 있을 때: 작가 메시지는 채팅 화면이 아닐 수 있어 배너로 띄우고,
    /// 시작·취소·종료·사진 준비는 화면이 이미 바뀌므로 알림 목록에만 남긴다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        switch CustomerPush.notification(from: notification.request.content.userInfo) {
        case .message: [.banner, .list, .sound]
        case .ticket, .photoReady, nil: [.list]
        }
    }

    /// 매칭된 뒤 처음 티켓 화면을 열 때 알림 권한을 묻는다. 작가가 메시지를 보내거나 먼저 시작하면 알 수 있게 한다.
    @MainActor
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
}
