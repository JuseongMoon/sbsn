import Foundation

/// 촬영 티켓에서 한 사람이 맡는 역할.
public enum ParticipantRole: String, Sendable, Equatable {
    case customer
    case photographer
}

/// 촬영 티켓 문서(`tickets/{ticketId}`)의 내용. 상태는 저장하지 않고 시각 필드에서 `phase`로 파생한다.
///
/// 고객이 지도에서 작가를 확정하는 순간 만들어지고(= 1차 매칭), 둘 다 "시작"을 누르면 촬영 중이 된다.
/// 각 시각은 한 번만 쓸 수 있고, 둘이 동시에 "시작"을 눌러도 각자 자기 필드만 쓰므로 충돌이 없다.
public struct TicketRecord: Sendable, Equatable, Identifiable {
    public let id: String
    public let customerUid: String
    public let photographerUid: String
    public let photographerDisplayName: String
    public let createdAt: Date
    public var customerStartedAt: Date?
    public var photographerStartedAt: Date?
    /// 작가 앱이 매칭 알림을 받아 티켓을 봤다는 표시
    public var photographerAckAt: Date?
    /// 작가가 "촬영 종료"를 누른 시각. 종료 뒤에도 미리 올라간 사진은 구매·전달된다.
    public var endedAt: Date?
    public var cancelledAt: Date?
    public var cancelledBy: String?

    /// 촬영 중에 작가가 사라졌을 때 고객이 스스로 종료할 수 있을 때까지의 시간
    public static let customerEndGracePeriod: TimeInterval = 60 * 60

    public init(id: String, customerUid: String, photographerUid: String, photographerDisplayName: String, createdAt: Date,
                customerStartedAt: Date? = nil, photographerStartedAt: Date? = nil, photographerAckAt: Date? = nil,
                endedAt: Date? = nil, cancelledAt: Date? = nil, cancelledBy: String? = nil) {
        self.id = id
        self.customerUid = customerUid
        self.photographerUid = photographerUid
        self.photographerDisplayName = photographerDisplayName
        self.createdAt = createdAt
        self.customerStartedAt = customerStartedAt
        self.photographerStartedAt = photographerStartedAt
        self.photographerAckAt = photographerAckAt
        self.endedAt = endedAt
        self.cancelledAt = cancelledAt
        self.cancelledBy = cancelledBy
    }

    public var phase: TicketPhase { TicketPhase.of(self) }

    public func role(of uid: String) -> ParticipantRole? {
        if uid == customerUid { return .customer }
        if uid == photographerUid { return .photographer }
        return nil
    }

    public func uid(of role: ParticipantRole) -> String {
        switch role {
        case .customer: customerUid
        case .photographer: photographerUid
        }
    }

    public func startedAt(_ role: ParticipantRole) -> Date? {
        switch role {
        case .customer: customerStartedAt
        case .photographer: photographerStartedAt
        }
    }

    /// 보안 규칙과 같은 조건이다. 앱은 거부될 쓰기를 보내지 않도록 먼저 이것으로 확인한다.
    public func canStart(_ role: ParticipantRole) -> Bool {
        phase.isActive && startedAt(role) == nil
    }

    /// 촬영 중(둘 다 시작)이 되기 전에는 참여자 누구나 취소할 수 있다. 한쪽만 시작한 뒤 상대가 사라져도 빠져나갈 수 있어야 한다.
    public var canCancel: Bool {
        phase.isActive && phase != .shooting
    }

    /// 종료는 촬영 중일 때 작가가 한다. 작가가 사라지면 고객도 유예 시간이 지난 뒤 종료할 수 있다.
    public func canEnd(_ role: ParticipantRole, at now: Date = Date()) -> Bool {
        guard phase == .shooting, let photographerStartedAt else { return false }
        switch role {
        case .photographer: return true
        case .customer: return now > photographerStartedAt.addingTimeInterval(Self.customerEndGracePeriod)
        }
    }
}

/// 티켓의 진행 단계. 시각 필드에서 파생한다.
public enum TicketPhase: Sendable, Equatable {
    /// 매칭됐고 아직 아무도 시작하지 않았다.
    case matched
    /// 고객은 시작을 눌렀고 작가를 기다린다.
    case waitingForPhotographer
    /// 작가는 시작을 눌렀고 고객을 기다린다.
    case waitingForCustomer
    case shooting
    case ended
    case cancelled

    public static func of(_ ticket: TicketRecord) -> TicketPhase {
        if ticket.cancelledAt != nil { return .cancelled }
        if ticket.endedAt != nil { return .ended }
        switch (ticket.customerStartedAt != nil, ticket.photographerStartedAt != nil) {
        case (true, true): return .shooting
        case (true, false): return .waitingForPhotographer
        case (false, true): return .waitingForCustomer
        case (false, false): return .matched
        }
    }

    /// 끝나거나 취소되지 않은 티켓
    public var isActive: Bool {
        switch self {
        case .ended, .cancelled: false
        default: true
        }
    }
}
