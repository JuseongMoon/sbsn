import Foundation
import Testing
@testable import SBSNCore

/// 출시 2단계 규칙(D064~D066): 촬영 시간, 사유 코드(웹·Android와 같은 문자열), 남은 시간 표시, 연락처 감지.
struct LaunchMatchTests {
    @Test func minutesAreTenToSixtyInFiveMinuteSteps() {
        #expect(LaunchMatch.isValidMinutes(10) && LaunchMatch.isValidMinutes(60) && LaunchMatch.isValidMinutes(25))
        #expect(!LaunchMatch.isValidMinutes(5) && !LaunchMatch.isValidMinutes(65) && !LaunchMatch.isValidMinutes(12))
        #expect(LaunchMatch.steppedMinutes(20, by: 1) == 25)
        #expect(LaunchMatch.steppedMinutes(10, by: -1) == 10)
        #expect(LaunchMatch.steppedMinutes(60, by: 1) == 60)
        #expect(LaunchMatch.steppedMinutes(12, by: 0) == 10, "단위가 안 맞으면 가까운 값")
        #expect(LaunchMatch.steppedMinutes(13, by: 0) == 15)
    }

    /// 서버(`launchDeclineLabels`·`launchCancellationLabels`·`breakReason`)와 같은 코드
    @Test func reasonCodesMatchServer() {
        #expect(LaunchMatch.DeclineReason.allCases.map(\.rawValue) == ["too_far", "duration_mismatch", "busy", "other"])
        #expect(LaunchMatch.CancelReason.allCases.map(\.rawValue)
                == ["schedule_changed", "no_contact", "no_show", "cannot_meet", "mutual", "other"])
        #expect(LaunchMatch.BreakReason.allCases.map(\.rawValue) == ["meal", "in_transit", "equipment", "rest"])
        #expect(LaunchMatch.DeclineReason.other.customerLabel == nil)
        #expect(LaunchMatch.CancelReason.other.counterpartLabel == nil)
        #expect(LaunchMatch.radiusOptions.map(LaunchMatch.radiusLabel) == ["300m", "500m", "1km", "2km"])
    }

    @Test func customerOutcomeCarriesDeclineCategory() {
        let now = Date()
        func request(_ status: LaunchMatch.RequestStatus, _ reason: LaunchMatch.DeclineReason? = nil) -> LaunchMatch.Request {
            .init(id: "r", roomId: "room", customerUid: "c", photographerUid: "p", minutes: 20, status: status,
                  createdAt: now, expiresAt: now.addingTimeInterval(300), ticketId: nil, declineReason: reason)
        }
        #expect(request(.declined, .tooFar).customerOutcome == "작가가 이번 신청을 받지 않았어요 · 너무 멀어요")
        #expect(request(.declined, .other).customerOutcome == "작가가 이번 신청을 받지 않았어요")
        #expect(request(.autoDeclined).customerOutcome == "작가가 다른 촬영을 수락했어요")
        #expect(request(.pending).customerOutcome == nil)
        #expect(request(.pending).isWaiting(now: now))
        #expect(!request(.pending).isWaiting(now: now.addingTimeInterval(301)), "정리가 늦어도 만료 시각이 지나면 대기가 아님")
        #expect(request(.pending).isExpiringSoon(now: now.addingTimeInterval(250)))
    }

    static func ticket(status: LaunchMatch.TicketStatus, end: Date? = nil, extensionMinutes: Int = 0,
                       cancelReason: LaunchMatch.CancelReason? = nil, cancelledBy: LaunchMatch.Role? = nil,
                       response: String? = nil, responseExpires: Date? = nil) -> LaunchMatch.Ticket {
        .init(id: "t", roomId: "room", customerUid: "c", photographerUid: "p", minutes: 20, status: status,
              matchedAt: Date(), customerConfirmedAt: nil, photographerConfirmedAt: nil, startedAt: end == nil ? nil : Date(),
              scheduledEndAt: end, extensionMinutes: extensionMinutes, pendingExtensionId: nil, endedAt: nil, endedByRole: nil,
              cancelledAt: cancelledBy == nil ? nil : Date(), cancelledByRole: cancelledBy, cancellationReason: cancelReason,
              cancellationResponse: response, cancellationResponseExpiresAt: responseExpires)
    }

    /// 분 단위(초 없음, D051), 1분 미만 "곧 끝나요", 지나도 자동 종료 없음(L21)
    @Test func remainingTextIsInMinutes() {
        let now = Date()
        #expect(Self.ticket(status: .shooting, end: now.addingTimeInterval(12 * 60 + 30)).remainingText(now: now) == "12분 남음")
        #expect(Self.ticket(status: .shooting, end: now.addingTimeInterval(59)).remainingText(now: now) == "곧 끝나요")
        #expect(Self.ticket(status: .shooting, end: now.addingTimeInterval(-5)).remainingText(now: now) == "예정 시간이 지났어요")
        #expect(Self.ticket(status: .matched).remainingText(now: now) == nil)
    }

    @Test func extensionStopsAtThirtyMinutes() {
        #expect(Self.ticket(status: .shooting, end: Date(), extensionMinutes: 25).canRequestExtension)
        #expect(!Self.ticket(status: .shooting, end: Date(), extensionMinutes: 30).canRequestExtension)
        #expect(!Self.ticket(status: .matched).canRequestExtension)
        #expect(Self.ticket(status: .shooting, end: Date(), extensionMinutes: 10).remainingExtensionMinutes == 20)
    }

    @Test func mutualAnswerOnlyForCounterpartWithin24Hours() {
        let now = Date()
        let ticket = Self.ticket(status: .cancelled, cancelReason: .mutual, cancelledBy: .customer,
                                 response: "pending", responseExpires: now.addingTimeInterval(3600))
        #expect(ticket.awaitsMutualAnswer(from: "p", now: now))
        #expect(!ticket.awaitsMutualAnswer(from: "c", now: now), "취소한 쪽은 답하지 않는다")
        #expect(!ticket.awaitsMutualAnswer(from: "p", now: now.addingTimeInterval(3601)))
        let unilateral = Self.ticket(status: .cancelled, cancelReason: .scheduleChanged, cancelledBy: .customer)
        #expect(!unilateral.awaitsMutualAnswer(from: "p", now: now))
    }

    @Test func roomFallsBackToRoleNames() {
        let room = LaunchMatch.Room(id: "r", customerUid: "c", photographerUid: "p", activityAt: nil, lastMessageAt: nil,
                                    customerNickname: nil, photographerNickname: "김작가")
        #expect(room.counterpartName(of: "c") == "김작가")
        #expect(room.counterpartName(of: "p") == "고객")
        #expect(room.counterpartUid(of: "c") == "p")
    }

    // MARK: - 연락처·링크(L03)

    /// 잡아야 하는 문장(서버 표시 정규식이 잡는 것 포함)
    @Test(arguments: [
        ("010-1234-5678로 연락 주세요", ContactFilter.Kind.phone),
        ("01012345678", .phone),
        ("010 1234 5678", .phone),
        ("+82 10-1234-5678", .phone),
        ("02-123-4567 사무실", .phone),
        ("메일 snap@example.com 으로", .email),
        ("https://open.kakao.com/o/abc 여기로", .url),
        ("www.example.com 보세요", .url),
        ("instagram.com/snapper 팔로우", .url),
        ("카톡 아이디 snap_01", .messenger),
        ("카톡 snap01 추가해요", .messenger),
        ("오픈채팅으로 와요", .messenger),
        ("인스타 @snap.photo", .messenger),
        ("텔레그램 snapper", .messenger),
    ])
    func detectsContacts(_ text: String, _ kind: ContactFilter.Kind) throws {
        let result = try #require(ContactFilter.scan(text), "\(text)")
        #expect(result.matches.contains { $0.kind == kind }, "\(text): \(result.matches.map(\.kind))")
    }

    /// 잡지 않아야 하는 보통 문장
    @Test(arguments: [
        "지금 경복궁 정문 앞이에요",
        "20분 촬영 가능할까요?",
        "2시 10분쯤 도착해요",
        "사진 30장 정도 찍어 주세요",
        "인스타 감성으로 부탁드려요",
        "온라인으로 보고 연락드렸어요",
        "3번 출구 앞 1층",
        "10.5km 걸어왔어요",
    ])
    func ignoresOrdinaryText(_ text: String) {
        #expect(ContactFilter.scan(text) == nil, "\(text): \(ContactFilter.scan(text)?.masked ?? "")")
    }

    @Test func maskKeepsSeparators() throws {
        let result = try #require(ContactFilter.scan("010-1234-5678 로 연락 주세요"))
        #expect(result.masked == "***-****-**** 로 연락 주세요")
        let email = try #require(ContactFilter.scan("a@b.co"))
        #expect(email.masked == "*@*.**")
    }
}

/// 공통 시각 표기: 한국 시각 24시간제(기기 설정과 상관없이)
struct LaunchTimeTests {
    @Test func koreanTwentyFourHourClock() {
        // 2026-11-26 05:10 UTC = 14:10 KST
        let date = Date(timeIntervalSince1970: 1_795_669_800)
        #expect(LaunchTime.clock(date) == "14:10")
        #expect(LaunchTime.dayClock(date) == "11월 26일 14:10")
        #expect(LaunchTime.clock(Date(timeIntervalSince1970: 1_795_669_800 - 14 * 3600)) == "00:10")
    }
}

/// 출시 알림 → 누르면 갈 곳(계약: 채팅·신청은 대화방, 촬영·연장은 티켓)
struct LaunchNotificationTests {
    @Test func destinations() throws {
        func make(_ event: String, ticket: String? = nil) -> LaunchNotification? {
            var info: [AnyHashable: Any] = ["event": event, "eventId": "e1", "roomId": "room1", "requestId": "r1"]
            if let ticket { info["ticketId"] = ticket }
            return LaunchNotification(userInfo: info)
        }
        #expect(make("chat_message")?.destination == .room("room1"))
        #expect(make("match_requested")?.destination == .room("room1"))
        #expect(make("match_requested")?.isTimeSensitive == true)
        #expect(make("match_declined")?.destination == .room("room1"))
        #expect(make("match_accepted", ticket: "t1")?.destination == .ticket(ticketId: "t1", roomId: "room1"))
        #expect(make("extension_requested", ticket: "t1")?.destination == .ticket(ticketId: "t1", roomId: "room1"))
        #expect(make("shoot_ended")?.destination == .room("room1"), "티켓 ID가 없으면 대화방")
        #expect(LaunchNotification(userInfo: ["type": "message", "ticketId": "x"]) == nil, "MVP 알림은 출시 알림이 아니다")
    }
}

/// 서버와 같은 코드포인트 세기
struct LaunchTextTests {
    @Test func countsCodePointsLikeServer() {
        #expect(LaunchText.length("안녕") == 2)
        // 가족 이모지는 글자 하나지만 코드포인트 7개(서버 [...text].length = 7)
        let family = "👨‍👩‍👧‍👦"
        #expect(family.count == 1 && LaunchText.length(family) == 7)
        #expect(ChatMessage.validText(String(repeating: family, count: 143)) == nil, "143 × 7 = 1001 코드포인트는 서버가 거부")
        #expect(ChatMessage.validText(String(repeating: family, count: 142)) != nil)
        #expect(LaunchText.truncated("ab" + family, limit: 5) == "ab", "글자를 끊지 않는다")
        #expect(LaunchText.truncated("abc", limit: 5) == "abc")
    }
}
