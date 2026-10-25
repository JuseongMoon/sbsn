import FirebaseFirestore
import FirebaseMessaging
import Foundation

/// 작가 기기의 원격 알림.
///
/// 고객이 사진을 구매하면 서버 함수(`firebase/functions`)가 `photographers/{uid}`의 FCM 토큰으로 알림을 보낸다.
/// 알림에 content-available이 함께 들어 있어, 백그라운드에 있던 작가 앱이 잠깐 깨어나 구매한 사진을 올릴 수 있다.
public enum PhotographerPush {
    /// 원격 알림에 담긴 구매
    public struct Purchase: Sendable, Equatable {
        public let ticketID: String
        public let fileName: String
    }

    /// APNs 기기 토큰을 FCM에 넘기고, 받은 FCM 토큰을 작가 문서에 저장한다. 앱을 켤 때마다 불러 토큰이 바뀌어도 따라간다.
    @MainActor
    public static func register(apnsToken: Data) async throws {
        let messaging = Messaging.messaging()
        messaging.apnsToken = apnsToken
        let token = try await messaging.token()
        let uid = try await Backend.signedInUserID()
        try await Firestore.firestore().collection("photographers").document(uid).setData([
            "fcmToken": token,
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
        ])
    }

    /// 원격 알림 내용이 구매 알림이면 구매 정보를 꺼낸다. 키는 서버 함수의 `purchaseMessage`와 맞춘다.
    public static func purchase(from userInfo: [AnyHashable: Any]) -> Purchase? {
        guard userInfo["type"] as? String == "purchase",
              let ticketID = userInfo["ticketId"] as? String,
              let fileName = userInfo["fileName"] as? String
        else { return nil }
        return Purchase(ticketID: ticketID, fileName: fileName)
    }
}
