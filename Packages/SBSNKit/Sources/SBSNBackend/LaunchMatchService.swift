import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation
import SBSNCore

/// 출시 2단계 대화·신청·촬영·연장(D064~D066, 웹 계약 `firebase/docs/launch-phase-2.md` "에뮬레이터 호출 계약", asia-northeast3).
///
/// - 쓰기는 모두 서버 함수다(클라이언트 직접 쓰기는 규칙이 닫는다). 화면은 서버 응답이나 리스너가 바뀐 뒤 바꾼다.
/// - 재시도해도 같은 결과가 오도록 작업마다 `clientRequestId`를 만들어 다시 보낼 때도 같은 값을 쓴다.
/// - 읽기는 참여자 조건과 `limit`가 있는 Firestore 쿼리다(규칙·색인이 정한 모양 그대로).
/// - 시스템 메시지(수락·거절·만료·시작·종료·취소·연장)는 서버가 방에 넣는다. 앱은 그것만 그린다(W12).
public enum LaunchMatchService {
    public enum Failure: LocalizedError, Equatable {
        /// 서버가 받아들이지 않았다(서버 문구 그대로: 이미 진행 중, 작가가 받을 수 없음, 참여자 아님 등)
        case rejected(String)
        /// 네트워크 등 그 밖의 오류
        case other(String)

        public var errorDescription: String? {
            switch self {
            case .rejected(let message), .other(let message): message
            }
        }
    }

    static let region = "asia-northeast3"
    static let pageSize = 20

    // MARK: - 대화

    /// 작가와의 방을 연다(없으면 서버가 만든다). 고객만 부른다.
    public static func openConversation(artistUid: String) async throws -> String {
        let data = try await call("openLaunchConversationV1", ["artistUid": artistUid])
        guard let roomId = data["roomId"] as? String else { throw Failure.other("대화방을 열지 못했습니다.") }
        return roomId
    }

    /// 글을 보낸다(1~1,000자). 연락처 검사(`ContactFilter`)는 화면이 보내기 전에 한다.
    @discardableResult
    public static func send(roomId: String, clientRequestId: String, text: String) async throws -> String {
        let data = try await call("sendLaunchMessageV1", ["roomId": roomId, "clientRequestId": clientRequestId, "text": text])
        return data["messageId"] as? String ?? ""
    }

    /// 사진 한 장을 보낸다: 서버가 정한 임시 경로에 JPEG(5 MiB 이하)를 올리고 게시한다. 서버가 다시 줄이고 메타데이터를 지운다.
    /// `jpeg`는 화면이 긴 변 1,280px·메타데이터 없이 만든 것이다(L19).
    @discardableResult
    public static func sendPhoto(roomId: String, clientRequestId: String, jpeg: Data) async throws -> String {
        let prepared = try await call("prepareLaunchAttachmentV1", ["roomId": roomId, "clientRequestId": clientRequestId])
        guard let attachmentId = prepared["attachmentId"] as? String else { throw Failure.other("사진을 올릴 자리를 받지 못했습니다.") }
        if prepared["published"] as? Bool != true {
            guard let uploadPath = prepared["uploadPath"] as? String else { throw Failure.other("사진을 올릴 자리를 받지 못했습니다.") }
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            do {
                _ = try await Storage.storage().reference(withPath: uploadPath).putDataAsync(jpeg, metadata: metadata)
            } catch {
                // 같은 요청을 다시 보낸 경우 이미 올라가 있으면 규칙이 거부한다(resource == null). 게시로 넘어간다.
                let code = StorageErrorCode(rawValue: (error as NSError).code)
                guard code == .unauthorized else { throw Failure.other(error.localizedDescription) }
            }
        }
        let published = try await call("publishLaunchAttachmentV1", ["roomId": roomId, "attachmentId": attachmentId])
        return published["messageId"] as? String ?? attachmentId
    }

    /// 사진 메시지의 이미지(인증 SDK로 읽는다, 참여자만·30일)
    public static func attachmentData(path: String, maxSize: Int64 = 6 * 1024 * 1024) async throws -> Data {
        try await Storage.storage().reference(withPath: path).data(maxSize: maxSize)
    }

    /// 화면에 보인 상대 메시지까지 읽음으로 둔다.
    public static func markRead(roomId: String, throughMessageId: String) async throws {
        _ = try await call("markLaunchConversationReadV1", ["roomId": roomId, "throughMessageId": throughMessageId])
    }

    /// 내 방 목록(최근 활동 순 20개). 역할에 맞는 필드로 묻는다(색인 `customerUid|photographerUid + activityAt desc`).
    public nonisolated static func rooms(uid: String, role: LaunchMatch.Role) -> AsyncThrowingStream<[LaunchMatch.Room], Error> {
        let query = Firestore.firestore().collection("launchConversations")
            .whereField(role == .customer ? "customerUid" : "photographerUid", isEqualTo: uid)
            .order(by: "activityAt", descending: true)
            .limit(to: pageSize)
        return FirestoreListeners.documents(of: query) { snapshot in
            snapshot.documents.compactMap { room(id: $0.documentID, data: $0.data(with: .estimate)) }
        }
    }

    public nonisolated static func room(roomId: String) -> AsyncThrowingStream<LaunchMatch.Room?, Error> {
        FirestoreListeners.document(Firestore.firestore().collection("launchConversations").document(roomId)) { snapshot in
            snapshot.data(with: .estimate).flatMap { room(id: snapshot.documentID, data: $0) }
        }
    }

    /// 방 하나의 메시지(오래된 것부터, 최근 200개). 30일이 지난 방은 규칙이 읽기를 막는다.
    public nonisolated static func messages(roomId: String) -> AsyncThrowingStream<[LaunchMatch.Message], Error> {
        let query = Firestore.firestore().collection("launchConversations").document(roomId).collection("launchMessages")
            .order(by: "sentAt", descending: true)
            .limit(to: 200)
        return FirestoreListeners.documents(of: query) { snapshot in
            Array(snapshot.documents.compactMap { message(id: $0.documentID, data: $0.data(with: .estimate)) }.reversed())
        }
    }

    /// 방마다 안 읽은 수(`users/{uid}/launchConversationReads`, 최대 50개)
    public nonisolated static func unreadCounts(uid: String) -> AsyncThrowingStream<[String: Int], Error> {
        let query = Firestore.firestore().collection("users").document(uid).collection("launchConversationReads").limit(to: 50)
        return FirestoreListeners.documents(of: query) { snapshot in
            Dictionary(uniqueKeysWithValues: snapshot.documents.map { ($0.documentID, ($0.data()["unreadCount"] as? NSNumber)?.intValue ?? 0) })
        }
    }

    // MARK: - 신청

    public struct RequestReceipt: Sendable, Equatable {
        public let requestId: String
        public let status: String
        public let expiresAt: Date?
    }

    /// 고객: 그 방의 작가에게 신청한다(10~60분, 5분 단위). 같은 `clientRequestId`로 다시 보내면 같은 신청이 돌아온다.
    public static func requestMatch(roomId: String, minutes: Int, clientRequestId: String) async throws -> RequestReceipt {
        let data = try await call("requestLaunchMatchV1", ["roomId": roomId, "minutes": minutes, "clientRequestId": clientRequestId])
        guard let requestId = data["requestId"] as? String else { throw Failure.other("신청 결과를 읽지 못했습니다.") }
        return RequestReceipt(requestId: requestId, status: data["status"] as? String ?? "pending",
                              expiresAt: (data["expiresAt"] as? String).flatMap(date(rfc3339:)))
    }

    public enum RequestAnswer: Sendable {
        case accept
        case decline(LaunchMatch.DeclineReason)
        /// 고객의 수락 전 취소
        case cancel
    }

    /// 신청에 답한다. 수락하면 티켓 ID가 온다(티켓 ID = 신청 ID). 이미 끝난 신청이면 서버의 현재 상태가 온다.
    public static func respond(requestId: String, _ answer: RequestAnswer) async throws -> (status: String, ticketId: String?) {
        var payload: [String: Any] = ["requestId": requestId]
        switch answer {
        case .accept: payload["action"] = "accept"
        case .decline(let reason):
            payload["action"] = "decline"
            payload["declineReason"] = reason.rawValue
        case .cancel: payload["action"] = "cancel"
        }
        let data = try await call("respondLaunchMatchV1", payload)
        return (data["status"] as? String ?? "", data["ticketId"] as? String)
    }

    /// 작가: 답을 기다리는 신청(만료 순 20개)
    public nonisolated static func pendingRequests(photographerUid: String) -> AsyncThrowingStream<[LaunchMatch.Request], Error> {
        requests(field: "photographerUid", uid: photographerUid)
    }

    /// 고객: 답을 기다리는 내 신청(한 번에 하나, L15)
    public nonisolated static func pendingRequests(customerUid: String) -> AsyncThrowingStream<[LaunchMatch.Request], Error> {
        requests(field: "customerUid", uid: customerUid)
    }

    nonisolated static func requests(field: String, uid: String) -> AsyncThrowingStream<[LaunchMatch.Request], Error> {
        let query = Firestore.firestore().collection("launchMatchRequests")
            .whereField(field, isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
            .whereField("expiresAt", isGreaterThan: Timestamp(date: Date()))
            .order(by: "expiresAt")
            .limit(to: pageSize)
        return FirestoreListeners.documents(of: query) { snapshot in
            snapshot.documents.compactMap { request(id: $0.documentID, data: $0.data(with: .estimate)) }
        }
    }

    /// 신청 하나(계정 삭제가 막혔을 때 그 방을 찾는 데 쓴다, W10)
    public static func request(id: String) async throws -> LaunchMatch.Request? {
        let snapshot = try await Firestore.firestore().collection("launchMatchRequests").document(id).getDocument()
        return snapshot.data().flatMap { request(id: id, data: $0) }
    }

    // MARK: - 티켓

    public enum ShootingAction: Sendable {
        case start
        case end
        case cancel(LaunchMatch.CancelReason, note: String?)
        case agreeCancel
        case disagreeCancel
    }

    public struct ShootingResult: Sendable, Equatable {
        public let status: String
        public let endedByRole: LaunchMatch.Role?
        public let endedAt: Date?
    }

    /// 시작 확인·종료·일방 취소·상호 취소 응답. 종료가 겹치면 서버의 첫 기록이 온다.
    @discardableResult
    public static func updateShooting(ticketId: String, _ action: ShootingAction) async throws -> ShootingResult {
        var payload: [String: Any] = ["ticketId": ticketId]
        switch action {
        case .start: payload["action"] = "start"
        case .end: payload["action"] = "end"
        case .cancel(let reason, let note):
            payload["action"] = "cancel"
            payload["cancelReason"] = reason.rawValue
            if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                payload["cancelNote"] = String(note.prefix(LaunchMatch.CancelReason.noteLimit))
            }
        case .agreeCancel: payload["action"] = "agree_cancel"
        case .disagreeCancel: payload["action"] = "disagree_cancel"
        }
        let data = try await call("updateLaunchShootingV1", payload)
        return ShootingResult(status: data["status"] as? String ?? "",
                              endedByRole: (data["endedByRole"] as? String).flatMap(LaunchMatch.Role.init(rawValue:)),
                              endedAt: (data["endedAt"] as? String).flatMap(date(rfc3339:)))
    }

    public nonisolated static func ticket(id: String) -> AsyncThrowingStream<LaunchMatch.Ticket?, Error> {
        FirestoreListeners.document(Firestore.firestore().collection("launchTickets").document(id)) { snapshot in
            snapshot.data(with: .estimate).flatMap { ticket(id: snapshot.documentID, data: $0) }
        }
    }

    /// 최근 티켓(매칭 순 5개). 진행 중인 것(시작 대기·촬영 중)은 이 안에 있다(한 사람은 한 번에 하나, 서버 잠금).
    public nonisolated static func recentTickets(uid: String, role: LaunchMatch.Role) -> AsyncThrowingStream<[LaunchMatch.Ticket], Error> {
        let query = Firestore.firestore().collection("launchTickets")
            .whereField(role == .customer ? "customerUid" : "photographerUid", isEqualTo: uid)
            .order(by: "matchedAt", descending: true)
            .limit(to: 5)
        return FirestoreListeners.documents(of: query) { snapshot in
            snapshot.documents.compactMap { ticket(id: $0.documentID, data: $0.data(with: .estimate)) }
        }
    }

    // MARK: - 연장

    /// 고객: 5분 연장을 요청한다(작가가 60초 안에 동의해야 늘어난다).
    public static func requestExtension(ticketId: String, clientRequestId: String) async throws -> LaunchMatch.Extension {
        let data = try await call("requestLaunchExtensionV1", ["ticketId": ticketId, "clientRequestId": clientRequestId])
        guard let id = data["extensionId"] as? String else { throw Failure.other("연장 요청 결과를 읽지 못했습니다.") }
        return LaunchMatch.Extension(id: id, status: LaunchMatch.Extension.Status(rawValue: data["status"] as? String ?? "") ?? .pending,
                                     minutes: LaunchMatch.extensionStep,
                                     expiresAt: (data["expiresAt"] as? String).flatMap(date(rfc3339:)) ?? Date())
    }

    /// 작가: 연장에 답한다.
    @discardableResult
    public static func respondExtension(ticketId: String, extensionId: String, accept: Bool) async throws -> String {
        let data = try await call("respondLaunchExtensionV1", ["ticketId": ticketId, "extensionId": extensionId, "accept": accept])
        return data["status"] as? String ?? ""
    }

    public nonisolated static func extensionRequest(ticketId: String, extensionId: String) -> AsyncThrowingStream<LaunchMatch.Extension?, Error> {
        let reference = Firestore.firestore().collection("launchTickets").document(ticketId).collection("extensions").document(extensionId)
        return FirestoreListeners.document(reference) { snapshot in
            snapshot.data(with: .estimate).flatMap { data -> LaunchMatch.Extension? in
                guard let status = LaunchMatch.Extension.Status(rawValue: data["status"] as? String ?? ""),
                      let expiresAt = FirestoreCodec.date(data["expiresAt"]) else { return nil }
                return LaunchMatch.Extension(id: snapshot.documentID, status: status,
                                             minutes: (data["minutes"] as? NSNumber)?.intValue ?? LaunchMatch.extensionStep,
                                             expiresAt: expiresAt)
            }
        }
    }

    // MARK: - 변환

    static func room(id: String, data: [String: Any]) -> LaunchMatch.Room? {
        guard let customerUid = data["customerUid"] as? String, let photographerUid = data["photographerUid"] as? String else { return nil }
        return LaunchMatch.Room(id: id, customerUid: customerUid, photographerUid: photographerUid,
                                activityAt: FirestoreCodec.date(data["activityAt"]), lastMessageAt: FirestoreCodec.date(data["lastMessageAt"]),
                                customerNickname: data["customerNickname"] as? String,
                                photographerNickname: data["photographerNickname"] as? String)
    }

    static func message(id: String, data: [String: Any]) -> LaunchMatch.Message? {
        guard let kind = LaunchMatch.Message.Kind(rawValue: data["type"] as? String ?? "text") else { return nil }
        return LaunchMatch.Message(id: id, kind: kind, senderUid: data["senderUid"] as? String, text: data["text"] as? String,
                                   attachmentPath: data["attachmentPath"] as? String, event: data["event"] as? String,
                                   sentAt: FirestoreCodec.date(data["sentAt"]))
    }

    static func request(id: String, data: [String: Any]) -> LaunchMatch.Request? {
        guard let roomId = data["roomId"] as? String, let customerUid = data["customerUid"] as? String,
              let photographerUid = data["photographerUid"] as? String,
              let status = LaunchMatch.RequestStatus(rawValue: data["status"] as? String ?? ""),
              let expiresAt = FirestoreCodec.date(data["expiresAt"]) else { return nil }
        return LaunchMatch.Request(id: id, roomId: roomId, customerUid: customerUid, photographerUid: photographerUid,
                                   minutes: (data["minutes"] as? NSNumber)?.intValue ?? 0, status: status,
                                   createdAt: FirestoreCodec.date(data["createdAt"]), expiresAt: expiresAt,
                                   ticketId: data["ticketId"] as? String,
                                   declineReason: (data["declineReason"] as? String).flatMap(LaunchMatch.DeclineReason.init(rawValue:)),
                                   customerNickname: data["customerNickname"] as? String)
    }

    static func ticket(id: String, data: [String: Any]) -> LaunchMatch.Ticket? {
        guard let roomId = data["roomId"] as? String, let customerUid = data["customerUid"] as? String,
              let photographerUid = data["photographerUid"] as? String,
              let status = LaunchMatch.TicketStatus(rawValue: data["status"] as? String ?? "") else { return nil }
        func role(_ key: String) -> LaunchMatch.Role? { (data[key] as? String).flatMap(LaunchMatch.Role.init(rawValue:)) }
        return LaunchMatch.Ticket(
            id: id, roomId: roomId, customerUid: customerUid, photographerUid: photographerUid,
            minutes: (data["minutes"] as? NSNumber)?.intValue ?? 0, status: status,
            matchedAt: FirestoreCodec.date(data["matchedAt"]),
            customerConfirmedAt: FirestoreCodec.date(data["customerConfirmedAt"]),
            photographerConfirmedAt: FirestoreCodec.date(data["photographerConfirmedAt"]),
            startedAt: FirestoreCodec.date(data["startedAt"]), scheduledEndAt: FirestoreCodec.date(data["scheduledEndAt"]),
            extensionMinutes: (data["extensionMinutes"] as? NSNumber)?.intValue ?? 0,
            pendingExtensionId: data["pendingExtensionId"] as? String,
            endedAt: FirestoreCodec.date(data["endedAt"]), endedByRole: role("endedByRole"),
            cancelledAt: FirestoreCodec.date(data["cancelledAt"]), cancelledByRole: role("cancelledByRole"),
            cancellationReason: (data["cancellationReason"] as? String).flatMap(LaunchMatch.CancelReason.init(rawValue:)),
            cancellationResponse: data["cancellationResponse"] as? String,
            cancellationResponseExpiresAt: FirestoreCodec.date(data["cancellationResponseExpiresAt"]))
    }

    nonisolated(unsafe) static let rfc3339Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 서버 시각 응답(UTC RFC 3339, 소수 초가 있을 수도 없을 수도 있다)
    static func date(rfc3339 value: String) -> Date? {
        rfc3339Formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func rfc3339(_ date: Date) -> String {
        rfc3339Formatter.string(from: date)
    }

    // MARK: - 호출

    static func call(_ name: String, _ data: sending [String: Any]) async throws -> [String: Any] {
        do {
            let result = try await Backend.functions(region: region).httpsCallable(name).call(data)
            return result.data as? [String: Any] ?? [:]
        } catch {
            throw failure(from: error)
        }
    }

    static func failure(from error: Error) -> Failure {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return .other(error.localizedDescription)
        }
        switch code {
        case .failedPrecondition, .permissionDenied, .invalidArgument, .alreadyExists, .resourceExhausted, .unauthenticated:
            return .rejected(nsError.localizedDescription)
        default:
            return .other(nsError.localizedDescription)
        }
    }
}
