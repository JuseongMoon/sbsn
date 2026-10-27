import FirebaseFirestore
import FirebaseMessaging
import Foundation

/// 작가 기기의 원격 알림.
///
/// 서버 함수(`firebase/functions`)가 `photographers/{uid}`의 FCM 토큰으로 매칭·채팅·구매 알림을 보낸다.
/// 매칭과 구매 알림에는 content-available이 함께 들어 있어, 백그라운드에 있던 작가 앱이 잠깐 깨어나 일을 할 수 있다.
public enum PhotographerPush {
    /// 원격 알림에 담긴 구매
    public struct Purchase: Sendable, Equatable {
        public let ticketID: String
        public let fileName: String
    }

    /// 원격 알림의 종류. 키는 서버 함수의 `data.type`과 맞춘다.
    public enum Notification: Sendable, Equatable {
        /// 고객이 작가를 확정했다. 깨어난 앱은 티켓에 "받음"을 남기고 매칭 화면을 준비한다.
        case match(ticketID: String)
        /// 고객이 채팅을 보냈다. 배너만 온다.
        case message(ticketID: String)
        /// 고객이 사진을 샀다. 깨어난 앱은 고화질본을 올린다.
        case purchase(Purchase)

        public var ticketID: String {
            switch self {
            case .match(let ticketID), .message(let ticketID): ticketID
            case .purchase(let purchase): purchase.ticketID
            }
        }
    }

    /// 원격 알림 내용을 분류한다. 모르는 종류면 nil.
    public static func notification(from userInfo: [AnyHashable: Any]) -> Notification? {
        guard let ticketID = userInfo["ticketId"] as? String else { return nil }
        switch userInfo["type"] as? String {
        case "match": return .match(ticketID: ticketID)
        case "message": return .message(ticketID: ticketID)
        case "purchase": return purchase(from: userInfo).map(Notification.purchase)
        default: return nil
        }
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
