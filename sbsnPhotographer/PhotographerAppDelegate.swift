//
//  PhotographerAppDelegate.swift
//  sbsnPhotographer
//

import SBSNBackend
import UIKit
import UserNotifications

/// 원격 알림을 등록하고 받는다. 구매 알림은 `PurchaseWakeRouter`로 실증 화면 모델에 넘긴다.
final class PhotographerAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            PurchaseWakeRouter.shared.isAlertAuthorized = granted
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
            do {
                try await PhotographerPush.register(apnsToken: deviceToken)
                PurchaseWakeRouter.shared.registration = .registered
            } catch {
                PurchaseWakeRouter.shared.registration = .failed(error.localizedDescription)
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PurchaseWakeRouter.shared.registration = .failed(error.localizedDescription)
    }

    /// 앱이 화면에 있든 백그라운드에 있든 불린다. 앱이 종료돼 있었으면 iOS가 백그라운드로 실행한 뒤 부른다.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let purchase = PhotographerPush.purchase(from: userInfo) else { return .noData }
        return await PurchaseWakeRouter.shared.handle(purchase) ? .newData : .noData
    }

    /// 앱이 화면에 떠 있을 때도 배너를 띄워 작가가 구매를 알 수 있게 한다.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
