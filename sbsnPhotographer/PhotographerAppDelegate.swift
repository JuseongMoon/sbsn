//
//  PhotographerAppDelegate.swift
//  sbsnPhotographer
//

import SBSNBackend
import UIKit
import UserNotifications

/// 앱 실행과 원격 알림. 일은 모두 `PhotographerSession`에 넘긴다.
///
/// 알림으로 앱이 백그라운드에서 실행되면 화면(scene)이 만들어지지 않으므로, 세션 시작과 복원은 화면이 아니라 여기서 한다.
final class PhotographerAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 알림 델리게이트는 실행이 끝나기 전에 정해야 종료 상태에서 탭한 알림도 받는다.
        UNUserNotificationCenter.current().delegate = self
        // 알림 권한과 관계없이 등록한다. 권한이 없어도 앱을 깨우는 알림은 조용히 온다. 권한은 "촬영 가능"을 켤 때 묻는다.
        application.registerForRemoteNotifications()
        PhotographerSession.shared.start()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
            do {
                try await PhotographerPush.register(apnsToken: deviceToken)
                PhotographerSession.shared.setRegistration(.registered)
            } catch {
                PhotographerSession.shared.setRegistration(.failed(error.localizedDescription))
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PhotographerSession.shared.setRegistration(.failed(error.localizedDescription))
    }

    /// 앱이 화면에 있든 백그라운드에 있든 불린다. 시스템이 메모리 때문에 앱을 내렸으면 백그라운드로 실행한 뒤 부른다.
    /// (작가가 앱을 쓸어 올려 종료했으면 iOS가 실행하지 않는다. 그때는 배너를 탭해야 한다.)
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await PhotographerSession.shared.handleRemoteNotification(userInfo) ? .newData : .noData
    }

    /// 앱이 화면에 떠 있을 때도 배너를 띄워 작가가 매칭·채팅·구매를 알 수 있게 한다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// 배너를 탭하면 그 티켓 화면으로 간다.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let notification = PhotographerPush.notification(from: response.notification.request.content.userInfo) else { return }
        PhotographerSession.shared.openTicket(notification.ticketID)
    }
}
