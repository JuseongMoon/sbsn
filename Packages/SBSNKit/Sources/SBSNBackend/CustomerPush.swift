import FirebaseFirestore
import FirebaseMessaging
import Foundation

/// 고객 기기의 원격 알림.
///
/// 서버 함수(`firebase/functions`)가 `customerDevices/{uid}`의 FCM 토큰으로 작가 메시지, 작가의 시작·취소, 촬영 종료,
/// 나중에 올라온 구매 사진을 알린다. 고객 자신이 한 일은 알리지 않는다. 앱을 깨우지는 않고 배너만 온다.
public enum CustomerPush {
    /// 원격 알림의 종류. 키는 서버 함수의 `data.type`과 맞춘다.
    public enum Notification: Sendable, Equatable {
        /// 작가가 채팅을 보냈다.
        case message(ticketID: String)
        /// 작가가 시작·취소했거나 촬영이 끝났다. 화면은 티켓 리스너가 이미 바꾸므로 앱이 앞에 있으면 배너를 띄우지 않는다.
        case ticket(ticketID: String)
        /// 산 사진의 고화질본이 올라왔다. 앱을 열면 사진 앱에 저장된다.
        case photoReady(ticketID: String, fileName: String)
    }

    /// 원격 알림 내용을 분류한다. 모르는 종류면 nil.
    public static func notification(from userInfo: [AnyHashable: Any]) -> Notification? {
        guard let ticketID = userInfo["ticketId"] as? String else { return nil }
        switch userInfo["type"] as? String {
        case "message": return .message(ticketID: ticketID)
        case "ticket": return .ticket(ticketID: ticketID)
        case "photo": return (userInfo["fileName"] as? String).map { .photoReady(ticketID: ticketID, fileName: $0) }
        default: return nil
        }
    }

    /// APNs 기기 토큰을 FCM에 넘기고, 받은 FCM 토큰을 고객 기기 문서에 저장한다. 앱을 켤 때마다 불러 토큰이 바뀌어도 따라간다.
    @MainActor
    public static func register(apnsToken: Data) async throws {
        try await PushToken.register(apnsToken: apnsToken, in: "customerDevices")
    }
}

/// 작가·고객 기기 문서(`photographers/{uid}`, `customerDevices/{uid}`)에 FCM 토큰을 저장한다.
/// 규칙은 두 키와 서버 시각만 허용하므로 문서를 통째로 덮어쓴다.
enum PushToken {
    @MainActor
    static func register(apnsToken: Data, in collection: String) async throws {
        let messaging = Messaging.messaging()
        messaging.apnsToken = apnsToken
        let token = try await messaging.token()
        let uid = try await Backend.signedInUserID()
        try await Firestore.firestore().collection(collection).document(uid).setData([
            "fcmToken": token,
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp(),
        ])
    }
}
