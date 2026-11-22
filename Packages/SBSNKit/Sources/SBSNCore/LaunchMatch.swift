import Foundation

/// 출시 2단계 매칭·촬영 규칙(D064~D066, 웹 계약 `firebase/docs/launch-phase-2.md`). 순수 값과 계산만 둔다.
/// 상태 전이와 시한 판정은 서버가 한다. 앱은 서버 문서를 읽어 화면 단계를 정하고 시각만 보인다(초 카운트 없음, D051).
/// 사유 코드와 문구는 웹 함수(`launchDeclineLabels`·`launchCancellationLabels`)·Android `:core`와 같다.
public enum LaunchMatch {
    // MARK: - 촬영 시간·연장(L20·L21·L45)

    /// 신청 촬영 시간: 10~60분, 5분 단위
    public static let minutesRange = 10...60
    public static let minutesStep = 5
    /// 연장: 5분씩, 촬영 중 합계 30분까지. 작가는 60초 안에 답한다.
    public static let extensionStep = 5
    public static let extensionLimit = 30
    public static let extensionAnswerSeconds = 60
    /// 신청은 서버 접수 뒤 5분에 만료된다.
    public static let requestLifetimeMinutes = 5

    /// 신청할 수 있는 분인지
    public static func isValidMinutes(_ minutes: Int) -> Bool {
        minutesRange.contains(minutes) && minutes % minutesStep == 0
    }

    /// [－]·[＋]로 5분씩 옮기고 범위 안에 둔다. 범위 밖·단위가 안 맞는 값은 가까운 허용값으로 맞춘다.
    public static func steppedMinutes(_ minutes: Int, by steps: Int) -> Int {
        let snapped = (minutes + minutesStep / 2) / minutesStep * minutesStep
        let moved = snapped + steps * minutesStep
        return min(max(moved, minutesRange.lowerBound), minutesRange.upperBound)
    }

    // MARK: - 사유

    /// 작가 거절 사유(D066 S3). 누르면 바로 거절된다. 고객에게는 분류만 보인다(`other`는 분류 없이).
    public enum DeclineReason: String, CaseIterable, Sendable, Identifiable {
        case tooFar = "too_far"
        case durationMismatch = "duration_mismatch"
        case busy
        case other

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .tooFar: "너무 멀어요"
            case .durationMismatch: "요청한 시간이 맞지 않아요"
            case .busy: "지금 다른 일정이 있어요"
            case .other: "기타"
            }
        }

        /// 고객에게 붙는 분류(없으면 nil)
        public var customerLabel: String? { self == .other ? nil : label }
    }

    /// 시작 대기 중 일방 취소 사유(L17). 상대에게는 분류만 보이고 메모는 서버 전용이다.
    public enum CancelReason: String, CaseIterable, Sendable, Identifiable {
        case scheduleChanged = "schedule_changed"
        case noContact = "no_contact"
        case noShow = "no_show"
        case cannotMeet = "cannot_meet"
        case mutual
        case other

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .scheduleChanged: "일정이 바뀌었어요"
            case .noContact: "상대와 연락이 안 돼요"
            case .noShow: "상대가 약속 장소에 오지 않았어요"
            case .cannotMeet: "만나기로 한 곳에 갈 수 없어요"
            case .mutual: "서로 이야기해서 취소해요"
            case .other: "기타"
            }
        }

        /// 상대에게 보이는 분류(`other`는 분류 없이)
        public var counterpartLabel: String? { self == .other ? nil : label }

        /// 서버 메모 상한
        public static let noteLimit = 500
    }

    /// 휴게 사유(계약 `breakReason`). 끝 시각은 없고 작가가 직접 끝낸다.
    public enum BreakReason: String, CaseIterable, Sendable, Identifiable {
        case meal
        case inTransit = "in_transit"
        case equipment
        case rest

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .meal: "식사"
            case .inTransit: "이동 중"
            case .equipment: "장비 정비"
            case .rest: "잠시 휴식"
            }
        }
    }

    /// 활동 반경(L11)
    public static let radiusOptions: [Int64] = [300, 500, 1000, 2000]

    /// "300m"·"1km"
    public static func radiusLabel(_ meters: Int64) -> String {
        meters >= 1000 && meters % 1000 == 0 ? "\(meters / 1000)km" : "\(meters)m"
    }

    // MARK: - 신청

    public enum RequestStatus: String, Sendable {
        case pending
        case accepted
        case declined
        case autoDeclined = "auto_declined"
        case cancelled
        case expired
    }

    /// `launchMatchRequests/{requestId}`. 양측만 읽고 상태는 서버만 쓴다.
    public struct Request: Sendable, Equatable, Identifiable {
        public let id: String
        public let roomId: String
        public let customerUid: String
        public let photographerUid: String
        public let minutes: Int
        public let status: RequestStatus
        public let createdAt: Date?
        public let expiresAt: Date
        public let ticketId: String?
        public let declineReason: DeclineReason?

        public init(id: String, roomId: String, customerUid: String, photographerUid: String, minutes: Int,
                    status: RequestStatus, createdAt: Date?, expiresAt: Date, ticketId: String?, declineReason: DeclineReason?) {
            self.id = id
            self.roomId = roomId
            self.customerUid = customerUid
            self.photographerUid = photographerUid
            self.minutes = minutes
            self.status = status
            self.createdAt = createdAt
            self.expiresAt = expiresAt
            self.ticketId = ticketId
            self.declineReason = declineReason
        }

        /// 아직 답을 기다린다(서버 정리가 늦어도 만료 시각이 지났으면 대기로 보지 않는다).
        public func isWaiting(now: Date) -> Bool {
            status == .pending && expiresAt > now
        }

        /// 만료까지 1분 안이면 "곧 만료"
        public func isExpiringSoon(now: Date) -> Bool {
            isWaiting(now: now) && expiresAt.timeIntervalSince(now) <= 60
        }

        /// 고객에게 보이는 결과 한 줄(대기 중이면 nil). 서버 시스템 메시지·알림과 같은 문구.
        public var customerOutcome: String? {
            switch status {
            case .pending, .accepted: nil
            case .declined:
                ["작가가 이번 신청을 받지 않았어요", declineReason?.customerLabel].compactMap(\.self).joined(separator: " · ")
            case .autoDeclined: "작가가 다른 촬영을 수락했어요"
            case .cancelled: "신청을 취소했어요"
            case .expired: "작가가 5분 안에 답하지 않아 신청이 취소됐어요"
            }
        }
    }

    // MARK: - 티켓

    public enum TicketStatus: String, Sendable {
        case matched
        case shooting
        case ended
        case cancelled
    }

    public enum Role: String, Sendable {
        case customer
        case photographer
    }

    /// `launchTickets/{ticketId}`. 신청 하나에 티켓 하나(티켓 ID = 신청 ID).
    public struct Ticket: Sendable, Equatable, Identifiable {
        public let id: String
        public let roomId: String
        public let customerUid: String
        public let photographerUid: String
        public let minutes: Int
        public let status: TicketStatus
        public let matchedAt: Date?
        public let customerConfirmedAt: Date?
        public let photographerConfirmedAt: Date?
        public let startedAt: Date?
        public let scheduledEndAt: Date?
        public let extensionMinutes: Int
        public let pendingExtensionId: String?
        public let endedAt: Date?
        public let endedByRole: Role?
        public let cancelledAt: Date?
        public let cancelledByRole: Role?
        public let cancellationReason: CancelReason?
        /// 상호 취소 요청에 대한 상대 응답(`pending`·`agreed`·`declined`)
        public let cancellationResponse: String?
        public let cancellationResponseExpiresAt: Date?

        public init(id: String, roomId: String, customerUid: String, photographerUid: String, minutes: Int, status: TicketStatus,
                    matchedAt: Date?, customerConfirmedAt: Date?, photographerConfirmedAt: Date?, startedAt: Date?,
                    scheduledEndAt: Date?, extensionMinutes: Int, pendingExtensionId: String?, endedAt: Date?, endedByRole: Role?,
                    cancelledAt: Date?, cancelledByRole: Role?, cancellationReason: CancelReason?,
                    cancellationResponse: String?, cancellationResponseExpiresAt: Date?) {
            self.id = id
            self.roomId = roomId
            self.customerUid = customerUid
            self.photographerUid = photographerUid
            self.minutes = minutes
            self.status = status
            self.matchedAt = matchedAt
            self.customerConfirmedAt = customerConfirmedAt
            self.photographerConfirmedAt = photographerConfirmedAt
            self.startedAt = startedAt
            self.scheduledEndAt = scheduledEndAt
            self.extensionMinutes = extensionMinutes
            self.pendingExtensionId = pendingExtensionId
            self.endedAt = endedAt
            self.endedByRole = endedByRole
            self.cancelledAt = cancelledAt
            self.cancelledByRole = cancelledByRole
            self.cancellationReason = cancellationReason
            self.cancellationResponse = cancellationResponse
            self.cancellationResponseExpiresAt = cancellationResponseExpiresAt
        }

        public func role(of uid: String) -> Role? {
            uid == customerUid ? .customer : (uid == photographerUid ? .photographer : nil)
        }

        /// 진행 중(시작 대기·촬영 중). 계정 삭제가 막히고 지도 대신 티켓 화면이 보인다.
        public var isActive: Bool { status == .matched || status == .shooting }

        /// 시작 대기에서 이 역할이 이미 시작을 눌렀는지
        public func hasConfirmedStart(_ role: Role) -> Bool {
            (role == .customer ? customerConfirmedAt : photographerConfirmedAt) != nil
        }

        /// 연장을 더 신청할 수 있는지(촬영 중, 합계 30분 미만, 대기 중인 연장 없음)
        public var canRequestExtension: Bool {
            status == .shooting && extensionMinutes < LaunchMatch.extensionLimit && pendingExtensionId == nil
        }

        /// 남은 연장 분
        public var remainingExtensionMinutes: Int { max(0, LaunchMatch.extensionLimit - extensionMinutes) }

        /// 촬영 중 남은 시간 표시(분 단위, D051). 1분 미만은 "곧 끝나요", 지나면 "예정 시간이 지났어요"(자동 종료 없음, L21).
        public func remainingText(now: Date) -> String? {
            guard status == .shooting, let scheduledEndAt else { return nil }
            let seconds = scheduledEndAt.timeIntervalSince(now)
            if seconds <= 0 { return "예정 시간이 지났어요" }
            if seconds < 60 { return "곧 끝나요" }
            return "\(Int(seconds / 60))분 남음"
        }

        /// 상대가 "서로 취소"를 요청해 내가 답할 수 있는지(24시간 안)
        public func awaitsMutualAnswer(from uid: String, now: Date) -> Bool {
            guard status == .cancelled, cancellationReason == .mutual, cancellationResponse == "pending",
                  let role = role(of: uid), role != cancelledByRole else { return false }
            return (cancellationResponseExpiresAt ?? .distantPast) > now
        }
    }

    /// 연장 요청(`launchTickets/{id}/extensions/{extensionId}`)
    public struct Extension: Sendable, Equatable, Identifiable {
        public enum Status: String, Sendable {
            case pending, accepted, declined, expired, cancelled
        }

        public let id: String
        public let status: Status
        public let minutes: Int
        public let expiresAt: Date

        public init(id: String, status: Status, minutes: Int, expiresAt: Date) {
            self.id = id
            self.status = status
            self.minutes = minutes
            self.expiresAt = expiresAt
        }

        public func isWaiting(now: Date) -> Bool { status == .pending && expiresAt > now }
    }

    // MARK: - 대화

    /// `launchConversations/{roomId}`. 고객·작가 쌍마다 하나(같은 작가와 다시 촬영해도 같은 방).
    public struct Room: Sendable, Equatable, Identifiable {
        public let id: String
        public let customerUid: String
        public let photographerUid: String
        public let activityAt: Date?
        public let lastMessageAt: Date?
        /// 서버가 넣어 주면 쓴다(웹에 요청 중인 W11). 없으면 nil.
        public let customerNickname: String?
        public let photographerNickname: String?

        public init(id: String, customerUid: String, photographerUid: String, activityAt: Date?, lastMessageAt: Date?,
                    customerNickname: String?, photographerNickname: String?) {
            self.id = id
            self.customerUid = customerUid
            self.photographerUid = photographerUid
            self.activityAt = activityAt
            self.lastMessageAt = lastMessageAt
            self.customerNickname = customerNickname
            self.photographerNickname = photographerNickname
        }

        public func counterpartUid(of uid: String) -> String {
            uid == customerUid ? photographerUid : customerUid
        }

        /// 상대 이름. 서버가 닉네임을 주지 않으면 역할 이름으로 보인다.
        public func counterpartName(of uid: String) -> String {
            if uid == customerUid {
                return photographerNickname ?? "작가"
            }
            return customerNickname ?? "고객"
        }
    }

    /// `launchMessages/{messageId}`
    public struct Message: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable {
            case text, photo, system
        }

        public let id: String
        public let kind: Kind
        public let senderUid: String?
        public let text: String?
        public let attachmentPath: String?
        /// 시스템 메시지의 사건(`match_declined` 등)
        public let event: String?
        public let sentAt: Date?

        public init(id: String, kind: Kind, senderUid: String?, text: String?, attachmentPath: String?, event: String?, sentAt: Date?) {
            self.id = id
            self.kind = kind
            self.senderUid = senderUid
            self.text = text
            self.attachmentPath = attachmentPath
            self.event = event
            self.sentAt = sentAt
        }

        /// 목록 한 줄
        public var preview: String {
            switch kind {
            case .photo: "사진"
            case .text, .system: text ?? ""
            }
        }
    }
}
