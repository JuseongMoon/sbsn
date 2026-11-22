import Foundation
import SBSNCore
import Security

/// 출시 공개 세션(격자 규격 "세션 키"·"기기 세션"): 작가 uid에 묶은 세션 키와 `deviceSessionId`(UUID v4 소문자).
///
/// - 촬영 가능을 직접 켤 때 새로 만들고, 같은 계정으로 앱이 다시 켜지면 불러와 같은 표시점·같은 기기 세션으로 잇는다.
/// - 끄기·로그아웃·계정 전환·다른 기기의 넘겨받음이면 지운다. 끄기 요청이 실패하면 `deviceSessionId`만 남겨 다음에 다시 보낸다.
/// - 키체인에 "이 기기에서만, 처음 잠금 해제 뒤"로 둔다(백업·다른 기기로 넘어가지 않고, 잠긴 채 백그라운드 위치로 깨어나도 읽힌다).
public struct LaunchPublicSession: Sendable, Equatable {
    public let uid: String
    public let deviceSessionId: String
    public let key: PublicLocationGrid.SessionKey

    /// 새 공개 세션(무작위 UUID v4 + CSPRNG 32바이트 키)
    public static func start(uid: String) -> LaunchPublicSession {
        LaunchPublicSession(uid: uid, deviceSessionId: UUID().uuidString.lowercased(), key: .generate())
    }

    /// 끄기 요청을 다시 보내야 하는 세션(원문 키는 남기지 않는다)
    public struct PendingOff: Sendable, Equatable, Codable {
        public let uid: String
        public let deviceSessionId: String

        public init(uid: String, deviceSessionId: String) {
            self.uid = uid
            self.deviceSessionId = deviceSessionId
        }
    }

    public enum Store {
        static let service = "com.ScienceFiction.sbsn.launchPublicSession"
        static let currentAccount = "current"
        static let pendingOffAccount = "pendingOff"

        private struct Stored: Codable {
            let uid: String
            let deviceSessionId: String
            let key: Data
        }

        /// 이 계정의 세션. 다른 계정 것이면 nil(그 세션은 이미 끝난 것으로 본다).
        public static func load(uid: String) -> LaunchPublicSession? {
            guard let data = read(currentAccount), let stored = try? JSONDecoder().decode(Stored.self, from: data),
                  stored.uid == uid, stored.key.count == 32
            else { return nil }
            return LaunchPublicSession(uid: stored.uid, deviceSessionId: stored.deviceSessionId, key: .init(bytes: stored.key))
        }

        public static func save(_ session: LaunchPublicSession) {
            let stored = Stored(uid: session.uid, deviceSessionId: session.deviceSessionId, key: session.key.bytes)
            if let data = try? JSONEncoder().encode(stored) {
                write(data, account: currentAccount)
            }
        }

        public static func clear() {
            delete(currentAccount)
        }

        public static var pendingOff: PendingOff? {
            read(pendingOffAccount).flatMap { try? JSONDecoder().decode(PendingOff.self, from: $0) }
        }

        public static func setPendingOff(_ value: PendingOff?) {
            if let value, let data = try? JSONEncoder().encode(value) {
                write(data, account: pendingOffAccount)
            } else {
                delete(pendingOffAccount)
            }
        }

        // MARK: - 키체인

        private static func query(_ account: String) -> [String: Any] {
            [kSecClass as String: kSecClassGenericPassword,
             kSecAttrService as String: service,
             kSecAttrAccount as String: account]
        }

        private static func read(_ account: String) -> Data? {
            var query = query(account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
            return result as? Data
        }

        private static func write(_ data: Data, account: String) {
            delete(account)
            var item = query(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }

        private static func delete(_ account: String) {
            SecItemDelete(query(account) as CFDictionary)
        }
    }
}
