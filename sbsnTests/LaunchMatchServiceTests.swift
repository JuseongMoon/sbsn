import SBSNBackend
import SBSNCore
import UIKit
import XCTest

/// 출시 2단계 호출부(`LaunchMatchService`)를 공용 개발 에뮬레이터(웹 저장소 `firebase/scripts/start_dev_emulators.sh`)에서 돈다.
/// 한쪽 역할은 앱 코드(SBSNBackend)로, 상대 역할은 REST(시험 계정 ID 토큰으로 callable 직접 호출)로 움직인다.
///
/// 시험 호스트(고객 앱)를 `-SBSNEmulatorHost 127.0.0.1`로 띄워야 한다. 인자가 없으면 건너뛴다(sbsn-dev에 붙지 않게).
///   xcodebuild build-for-testing … → xctestrun의 sbsnTests `CommandLineArguments`에 두 인자를 넣고 test-without-building
@MainActor
final class LaunchMatchServiceTests: XCTestCase {
    lazy var rest = LaunchREST(host: Backend.emulator?.host ?? "127.0.0.1")

    override func setUp() async throws {
        try XCTSkipUnless(Backend.emulator != nil, "에뮬레이터 인자(-SBSNEmulatorHost) 없이 실행됨")
    }

    /// 고객(앱 코드) ↔ 작가(REST): 방 → 글 → 신청 → 거절(사유 필수) → 고객 취소 → 수락 → 삭제 막힘(ticket) → 양쪽 시작 → 연장 동의 → 고객 종료 → 사진
    func test_customerSide() async throws {
        let artist = try await rest.approvedAvailableArtist(nickname: "작가1")
        let customer = try await rest.createAccount(prefix: "customer")
        _ = try await AccountService.signInForTesting(email: customer.email, password: customer.password)
        _ = try await AccountService.saveProfile(age14Confirmed: true, nickname: "고객1")

        let roomId = try await LaunchMatchService.openConversation(artistUid: artist.uid)
        try await LaunchMatchService.send(roomId: roomId, clientRequestId: Self.newId(), text: "경복궁 정문 앞이에요")
        _ = try await first(LaunchMatchService.messages(roomId: roomId)) { $0.contains { $0.text == "경복궁 정문 앞이에요" } }
        let rooms = try await first(LaunchMatchService.rooms(uid: customer.uid, role: .customer)) { $0.contains { $0.id == roomId } }
        XCTAssertEqual(rooms.first { $0.id == roomId }?.photographerUid, artist.uid)

        // 거절: 사유가 없으면 서버가 받지 않고, 사유를 붙이면 고객 방에 분류가 붙은 시스템 메시지가 남는다(D066).
        let first = try await LaunchMatchService.requestMatch(roomId: roomId, minutes: 20, clientRequestId: Self.newId())
        XCTAssertEqual(first.status, "pending")
        let mine = try await self.first(LaunchMatchService.pendingRequests(customerUid: customer.uid)) { $0.contains { $0.id == first.requestId } }
        XCTAssertEqual(mine.first?.minutes, 20)
        let (noReason, _) = try await rest.call("respondLaunchMatchV1", token: artist.token, ["requestId": first.requestId, "action": "decline"])
        XCTAssertEqual(noReason, 400, "사유 없는 거절은 거부")
        let (declined, declineBody) = try await rest.call("respondLaunchMatchV1", token: artist.token,
                                                          ["requestId": first.requestId, "action": "decline", "declineReason": "too_far"])
        XCTAssertEqual(declined, 200, "\(declineBody)")
        _ = try await self.first(LaunchMatchService.messages(roomId: roomId)) {
            $0.contains { $0.kind == .system && $0.text == "작가가 이번 신청을 받지 않았어요 · 너무 멀어요" }
        }

        // 고객의 수락 전 취소
        let second = try await LaunchMatchService.requestMatch(roomId: roomId, minutes: 15, clientRequestId: Self.newId())
        let cancelled = try await LaunchMatchService.respond(requestId: second.requestId, .cancel)
        XCTAssertEqual(cancelled.status, "cancelled")

        // 수락 → 티켓(시작 대기). 이때 계정 삭제는 막힌다(ticket).
        let third = try await LaunchMatchService.requestMatch(roomId: roomId, minutes: 20, clientRequestId: Self.newId())
        let (accepted, acceptBody) = try await rest.call("respondLaunchMatchV1", token: artist.token, ["requestId": third.requestId, "action": "accept"])
        XCTAssertEqual(accepted, 200, "\(acceptBody)")
        let ticketId = try XCTUnwrap(acceptBody["ticketId"] as? String)
        let matched = try await self.first(LaunchMatchService.ticket(id: ticketId)) { $0?.status == .matched }
        XCTAssertEqual(matched?.minutes, 20)
        do {
            _ = try await AccountService.requestDeletion(appleCode: nil, appleClientId: nil)
            XCTFail("진행 중인 촬영이 있는데 삭제가 접수됨")
        } catch let blocked as AccountService.DeletionBlocked {
            XCTAssertEqual(blocked.kind, .ticket)
            XCTAssertEqual(blocked.blockerId, ticketId)
            XCTAssertEqual(blocked.errorDescription, "진행 중인 촬영을 끝내거나 취소한 뒤 삭제할 수 있습니다")
        }

        // 양쪽 시작 → 촬영 중
        try await LaunchMatchService.updateShooting(ticketId: ticketId, .start)
        let waiting = try await self.first(LaunchMatchService.ticket(id: ticketId)) { $0?.customerConfirmedAt != nil }
        XCTAssertEqual(waiting?.status, .matched, "한쪽만 시작하면 대기")
        let (started, _) = try await rest.call("updateLaunchShootingV1", token: artist.token, ["ticketId": ticketId, "action": "start"])
        XCTAssertEqual(started, 200)
        let shooting = try await self.first(LaunchMatchService.ticket(id: ticketId)) { $0?.status == .shooting }
        XCTAssertNotNil(shooting?.scheduledEndAt)
        XCTAssertEqual(shooting?.remainingText(now: Date()), "19분 남음")

        // 연장: 고객 요청 → 작가 동의 → 5분 늘어난다.
        let extensionRequest = try await LaunchMatchService.requestExtension(ticketId: ticketId, clientRequestId: Self.newId())
        XCTAssertEqual(extensionRequest.status, .pending)
        let (agreed, _) = try await rest.call("respondLaunchExtensionV1", token: artist.token,
                                              ["ticketId": ticketId, "extensionId": extensionRequest.id, "accept": true])
        XCTAssertEqual(agreed, 200)
        let extended = try await self.first(LaunchMatchService.ticket(id: ticketId)) { $0?.extensionMinutes == 5 }
        XCTAssertEqual(extended?.remainingExtensionMinutes, 25)

        // 고객이 혼자 끝낸다(서버가 endedByRole을 남긴다).
        let ended = try await LaunchMatchService.updateShooting(ticketId: ticketId, .end)
        XCTAssertEqual(ended.status, "ended")
        XCTAssertEqual(ended.endedByRole, .customer)
        let recent = try await self.first(LaunchMatchService.recentTickets(uid: customer.uid, role: .customer)) {
            $0.contains { $0.id == ticketId && $0.status == .ended }
        }
        XCTAssertFalse(recent.contains { $0.isActive })

        // 사진 메시지: 임시 경로에 올리고 게시 → 참여자가 읽을 수 있다.
        let jpeg = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }.jpegData(compressionQuality: 0.8))
        let photoId = try await LaunchMatchService.sendPhoto(roomId: roomId, clientRequestId: Self.newId(), jpeg: jpeg)
        let withPhoto = try await self.first(LaunchMatchService.messages(roomId: roomId)) { $0.contains { $0.id == photoId && $0.kind == .photo } }
        let path = try XCTUnwrap(withPhoto.first { $0.id == photoId }?.attachmentPath)
        let downloaded = try await LaunchMatchService.attachmentData(path: path)
        XCTAssertFalse(downloaded.isEmpty)
        print("SBSN 고객 쪽 통과: 방 \(roomId.prefix(6)) 티켓 \(ticketId.prefix(6)) 사진 \(downloaded.count)B")
    }

    /// 작가(앱 코드) ↔ 고객(REST): 반경·끝 시각으로 켜기 → 대기 신청 목록 → 거절(사유) → 수락 → 시작 → 연장 거절 → 작가 종료 →
    /// 상호 취소 동의 → 휴게 중 신청 거부 → 안 읽은 수와 읽음 처리
    func test_photographerSide() async throws {
        let artist = try await rest.createAccount(prefix: "artist")
        _ = try await AccountService.signInForTesting(email: artist.email, password: artist.password)
        _ = try await AccountService.saveProfile(age14Confirmed: true, nickname: "작가1")
        try await rest.approve(artistUid: artist.uid)
        let deviceSessionId = UUID().uuidString.lowercased()
        try await LaunchArtistService.setAvailability(deviceSessionId: deviceSessionId, radiusMeters: 1000,
                                                      endsAt: Date().addingTimeInterval(7200), breakReason: nil)

        let customer = try await rest.createAccount(prefix: "customer")
        let customerToken = try await rest.idToken(customer)
        _ = try await rest.call("saveLaunchProfileV1", token: customerToken, ["age14Confirmed": true, "nickname": "고객1"])
        let (_, room) = try await rest.call("openLaunchConversationV1", token: customerToken, ["artistUid": artist.uid])
        let roomId = try XCTUnwrap(room["roomId"] as? String)

        func customerRequest(_ minutes: Int) async throws -> String {
            let (status, body) = try await rest.call("requestLaunchMatchV1", token: customerToken,
                                                     ["roomId": roomId, "minutes": minutes, "clientRequestId": Self.newId()])
            XCTAssertEqual(status, 200, "\(body)")
            return try XCTUnwrap(body["requestId"] as? String)
        }

        // 거절(사유)
        let first = try await customerRequest(30)
        let incoming = try await self.first(LaunchMatchService.pendingRequests(photographerUid: artist.uid)) { $0.contains { $0.id == first } }
        XCTAssertEqual(incoming.first { $0.id == first }?.minutes, 30)
        let declined = try await LaunchMatchService.respond(requestId: first, .decline(.busy))
        XCTAssertEqual(declined.status, "declined")

        // 수락 → 시작 → 연장 거절 → 작가 종료
        let second = try await customerRequest(10)
        let accepted = try await LaunchMatchService.respond(requestId: second, .accept)
        let ticketId = try XCTUnwrap(accepted.ticketId)
        _ = try await rest.call("updateLaunchShootingV1", token: customerToken, ["ticketId": ticketId, "action": "start"])
        try await LaunchMatchService.updateShooting(ticketId: ticketId, .start)
        _ = try await self.first(LaunchMatchService.ticket(id: ticketId)) { $0?.status == .shooting }
        let (_, extensionBody) = try await rest.call("requestLaunchExtensionV1", token: customerToken,
                                                     ["ticketId": ticketId, "clientRequestId": Self.newId()])
        let extensionId = try XCTUnwrap(extensionBody["extensionId"] as? String)
        _ = try await self.first(LaunchMatchService.extensionRequest(ticketId: ticketId, extensionId: extensionId)) { $0?.status == .pending }
        let refused = try await LaunchMatchService.respondExtension(ticketId: ticketId, extensionId: extensionId, accept: false)
        XCTAssertEqual(refused, "declined")
        let ended = try await LaunchMatchService.updateShooting(ticketId: ticketId, .end)
        XCTAssertEqual(ended.endedByRole, .photographer)

        // 시작 대기에서 "서로 이야기해서 취소" → 고객이 동의하면 상호
        let third = try await customerRequest(20)
        let thirdAnswer = try await LaunchMatchService.respond(requestId: third, .accept)
        let mutualTicket = try XCTUnwrap(thirdAnswer.ticketId)
        let cancelled = try await LaunchMatchService.updateShooting(ticketId: mutualTicket, .cancel(.mutual, note: "비가 와서 다음에"))
        XCTAssertEqual(cancelled.status, "cancelled")
        let (agreeStatus, _) = try await rest.call("updateLaunchShootingV1", token: customerToken, ["ticketId": mutualTicket, "action": "agree_cancel"])
        XCTAssertEqual(agreeStatus, 200)
        let mutual = try await self.first(LaunchMatchService.ticket(id: mutualTicket)) { $0?.cancellationResponse == "agreed" }
        XCTAssertEqual(mutual?.cancellationReason, .mutual)

        // 휴게 전에 들어온 신청은 휴게 중에도 수락할 수 있고, 수락하면 서버가 휴게를 푼다(웹 0d28d4f).
        let beforeBreak = try await customerRequest(15)
        try await LaunchArtistService.setAvailability(deviceSessionId: deviceSessionId, radiusMeters: 1000,
                                                      endsAt: Date().addingTimeInterval(7200), breakReason: .rest)
        let breakAccepted = try await LaunchMatchService.respond(requestId: beforeBreak, .accept)
        XCTAssertEqual(breakAccepted.status, "accepted", "휴게 전 신청을 휴게 중에 수락하지 못함")
        let device = try await rest.document("launchDevices/\(artist.uid)")
        XCTAssertNil(device?["breakReason"].flatMap { ($0 as? [String: Any])?["stringValue"] }, "수락 뒤에도 휴게가 남음")
        let breakTicket = try XCTUnwrap(breakAccepted.ticketId)
        _ = try await rest.call("updateLaunchShootingV1", token: customerToken, ["ticketId": breakTicket, "action": "cancel", "cancelReason": "other"])

        // 휴게 중에는 새 신청을 받지 않는다(W5).
        try await LaunchArtistService.setAvailability(deviceSessionId: deviceSessionId, radiusMeters: 1000,
                                                      endsAt: Date().addingTimeInterval(7200), breakReason: .meal)
        let (onBreak, _) = try await rest.call("requestLaunchMatchV1", token: customerToken,
                                               ["roomId": roomId, "minutes": 20, "clientRequestId": Self.newId()])
        XCTAssertNotEqual(onBreak, 200, "휴게 중 신청이 접수됨")

        // 안 읽은 수 → 읽음 처리
        let (_, sent) = try await rest.call("sendLaunchMessageV1", token: customerToken,
                                            ["roomId": roomId, "clientRequestId": Self.newId(), "text": "다음에 또 부탁드려요"])
        let messageId = try XCTUnwrap(sent["messageId"] as? String)
        _ = try await self.first(LaunchMatchService.unreadCounts(uid: artist.uid)) { ($0[roomId] ?? 0) >= 1 }
        try await LaunchMatchService.markRead(roomId: roomId, throughMessageId: messageId)
        _ = try await self.first(LaunchMatchService.unreadCounts(uid: artist.uid)) { $0[roomId] == 0 }
        try await LaunchArtistService.setAvailability(false, deviceSessionId: deviceSessionId)
        print("SBSN 작가 쪽 통과: 방 \(roomId.prefix(6)) 티켓 \(ticketId.prefix(6))·\(mutualTicket.prefix(6))")
    }

    /// 출시 알림 설치 등록(W1): 연결 계정·프로필이면 등록, 해제하면 지워진다. 승인 전 작가는 받지 않는다.
    func test_pushInstallation() async throws {
        let customer = try await rest.createAccount(prefix: "customer")
        _ = try await AccountService.signInForTesting(email: customer.email, password: customer.password)
        _ = try await AccountService.saveProfile(age14Confirmed: true, nickname: "고객1")
        try await LaunchPush.register(role: .customer, fcmToken: "test-fcm-token-\(Self.newId())")
        let rows = try await rest.query(collection: "launchPushInstallations", field: "uid", equals: customer.uid)
        XCTAssertEqual(rows.count, 1, "설치 등록 문서가 없음")
        XCTAssertEqual(rows.first?["appRole"], "customer")
        await LaunchPush.unregister(role: .customer)
        let after = try await rest.query(collection: "launchPushInstallations", field: "uid", equals: customer.uid)
        XCTAssertTrue(after.isEmpty, "해제 뒤에도 남음")

        // 승인 전 작가 역할로는 등록되지 않는다.
        do {
            try await LaunchPush.register(role: .photographer, fcmToken: "test-fcm-token-x")
            XCTFail("승인 전 작가 등록이 받아들여짐")
        } catch {}
        print("SBSN 알림 설치 등록·해제 통과")
    }

    /// 작가 프로필(W9) 저장·사진·공개 읽기와 제재 상태(W6) 읽기
    func test_profileAndSanction() async throws {
        let artist = try await rest.createAccount(prefix: "artist")
        _ = try await AccountService.signInForTesting(email: artist.email, password: artist.password)
        _ = try await AccountService.saveProfile(age14Confirmed: true, nickname: "작가1")
        try await rest.approve(artistUid: artist.uid)
        let jpeg = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }.jpegData(compressionQuality: 0.8))
        try await LaunchArtistProfileService.save(recommendedShootMinutes: 25, bio: "궁 촬영 전문", photoJPEG: jpeg)
        let profile = try await LaunchArtistProfileService.profile(artistUid: artist.uid)
        XCTAssertEqual(profile.nickname, "작가1")
        XCTAssertEqual(profile.recommendedShootMinutes, 25)
        XCTAssertEqual(profile.bio, "궁 촬영 전문")
        let photoPath = try XCTUnwrap(profile.photoPath)
        let photo = try await LaunchArtistProfileService.photoData(path: photoPath)
        XCTAssertFalse(photo.isEmpty)
        // 사진 없이 다시 저장하면 사진은 그대로
        try await LaunchArtistProfileService.save(recommendedShootMinutes: 30, bio: "궁 촬영 전문", photoJPEG: nil)
        let again = try await LaunchArtistProfileService.profile(artistUid: artist.uid)
        XCTAssertEqual(again.recommendedShootMinutes, 30)
        XCTAssertEqual(again.photoPath, photoPath)

        let sanction = try await LaunchArtistProfileService.sanctionStatus()
        XCTAssertEqual(sanction.missedCount7d, 0)
        XCTAssertFalse(sanction.isRestricted())
        let latest = try await LaunchArtistProfileService.latestSanctionEventId(uid: artist.uid)
        XCTAssertNil(latest)
        print("SBSN 프로필·제재 통과: 사진 \(photo.count)B")
    }

    /// 3단계 갤러리 v2(웹 launch-phase-3.md): 촬영 종료 → 사진 10장 준비·업로드·확정 → 9장 공개 거부 → 10장 공개 →
    /// 잠금 중 편집 거부·버전 경합 → 작가 목록 10장 → 고객 찜·구매 기록 → 산 사진 고화질 받기, 사지 않은 사진은 거부
    func test_galleryPublishAndPurchase() async throws {
        // 작가(앱 코드)로 끝난 촬영을 만든다.
        let artist = try await rest.createAccount(prefix: "artist")
        _ = try await AccountService.signInForTesting(email: artist.email, password: artist.password)
        _ = try await AccountService.saveProfile(age14Confirmed: true, nickname: "작가1")
        try await rest.approve(artistUid: artist.uid)
        let deviceSessionId = UUID().uuidString.lowercased()
        try await LaunchArtistService.setAvailability(deviceSessionId: deviceSessionId, radiusMeters: 1000,
                                                      endsAt: Date().addingTimeInterval(7200), breakReason: nil)
        let customer = try await rest.createAccount(prefix: "customer")
        let customerToken = try await rest.idToken(customer)
        _ = try await rest.call("saveLaunchProfileV1", token: customerToken, ["age14Confirmed": true, "nickname": "고객1"])
        let (_, room) = try await rest.call("openLaunchConversationV1", token: customerToken, ["artistUid": artist.uid])
        let roomId = try XCTUnwrap(room["roomId"] as? String)
        let (_, requested) = try await rest.call("requestLaunchMatchV1", token: customerToken,
                                                 ["roomId": roomId, "minutes": 10, "clientRequestId": Self.newId()])
        let requestId = try XCTUnwrap(requested["requestId"] as? String)
        let accepted = try await LaunchMatchService.respond(requestId: requestId, .accept)
        let ticketId = try XCTUnwrap(accepted.ticketId)
        _ = try await rest.call("updateLaunchShootingV1", token: customerToken, ["ticketId": ticketId, "action": "start"])
        try await LaunchMatchService.updateShooting(ticketId: ticketId, .start)
        try await LaunchMatchService.updateShooting(ticketId: ticketId, .end)
        let ended = try await first(LaunchGalleryService.endedTickets(photographerUid: artist.uid)) { $0.contains { $0.id == ticketId } }
        let deadline = try XCTUnwrap(ended.first { $0.id == ticketId }?.firstPublishUntil, "firstPublishUntil이 없음(V2)")
        XCTAssertGreaterThan(deadline.timeIntervalSinceNow, 71 * 3600)

        // 사진 10장: 준비 → 고화질·미리보기 업로드 → 확정
        var photoIds: [String] = []
        for index in 0..<10 {
            let prepared = try await LaunchGalleryService.prepare(ticketId: ticketId, clientRequestId: Self.newId())
            let fullres = try Self.jpegFile(width: 1600, height: 1067, hue: CGFloat(index) / 10)
            let preview = try Self.jpegFile(width: 640, height: 427, hue: CGFloat(index) / 10)
            try await LaunchGalleryService.upload(fileURL: fullres, to: prepared.fullresPath)
            try await LaunchGalleryService.upload(fileURL: preview, to: prepared.previewPath)
            let result = try await LaunchGalleryService.finalize(ticketId: ticketId, photoId: prepared.photoId)
            XCTAssertEqual(result, .ready, "사진 \(index) 확정 실패")
            photoIds.append(prepared.photoId)
        }

        let ids = photoIds
        // 9장은 공개할 수 없다.
        do {
            _ = try await LaunchGalleryService.publish(ticketId: ticketId, orderedPhotoIds: Array(photoIds.prefix(9)), clientRequestId: Self.newId())
            XCTFail("9장 공개가 받아들여짐")
        } catch let failure as LaunchMatchService.Failure {
            print("SBSN 9장 거부: \(failure.reason ?? "-") \(failure.localizedDescription)")
        }
        let published = try await LaunchGalleryService.publish(ticketId: ticketId, orderedPhotoIds: photoIds, clientRequestId: Self.newId())
        XCTAssertEqual(published.revision, 1)
        let galleryValue = try await first(LaunchGalleryService.gallery(ticketId: ticketId)) { $0 != nil }
        let gallery = try XCTUnwrap(galleryValue)
        XCTAssertEqual(gallery.orderedPhotoIds, photoIds)
        XCTAssertEqual(gallery.editableFrom.timeIntervalSince(gallery.publishedAt), 24 * 3600, accuracy: 1)
        XCTAssertEqual(gallery.closesAt.timeIntervalSince(gallery.publishedAt), 168 * 3600, accuracy: 1)

        // 잠금 중 편집은 거부, 버전이 다르면 버전 경합
        do {
            try await LaunchGalleryService.edit(ticketId: ticketId, expectedRevision: 99, orderedPhotoIds: photoIds, clientRequestId: Self.newId())
            XCTFail("다른 버전 편집이 받아들여짐")
        } catch let failure as LaunchMatchService.Failure {
            XCTAssertEqual(failure.reason, "GALLERY_REVISION_CONFLICT")
        }
        do {
            try await LaunchGalleryService.edit(ticketId: ticketId, expectedRevision: 1, orderedPhotoIds: Array(photoIds.reversed()),
                                                clientRequestId: Self.newId())
            XCTFail("잠금 중 편집이 받아들여짐")
        } catch let failure as LaunchMatchService.Failure {
            print("SBSN 잠금 중 편집 거부: \(failure.reason ?? "-")")
            XCTAssertNotNil(failure.reason)
        }
        let artistItems = try await first(LaunchGalleryService.items(ticketId: ticketId, role: .photographer)) { $0.count == 10 }
        XCTAssertEqual(GalleryV2.ordered(artistItems, by: gallery).map(\.id), photoIds)

        try await LaunchArtistService.setAvailability(false, deviceSessionId: deviceSessionId)
        XCTAssertEqual(gallery.purchasedCount, 0, "작가용 구매 개수(V5)")
        XCTAssertTrue(artistItems.allSatisfy { !$0.isPurchased && !$0.favorited })

        // 고객(앱 코드): 공개 목록 → 찜 → 구매 기록(시험판) → 고화질 받기
        _ = try await AccountService.signInForTesting(email: customer.email, password: customer.password)
        let items = try await first(LaunchGalleryService.items(ticketId: ticketId, role: .customer)) { $0.count == 10 }
        let ordered = GalleryV2.ordered(items, by: gallery)
        XCTAssertEqual(ordered.map(\.id), photoIds)
        let previewPath = try XCTUnwrap(ordered[0].previewPath)
        let previewBytes = try await LaunchGalleryService.previewData(path: previewPath)
        XCTAssertFalse(previewBytes.isEmpty)
        let favorited = try await LaunchGalleryService.setFavorite(ticketId: ticketId, photoId: photoIds[1], favorited: true)
        XCTAssertTrue(favorited)
        _ = try await first(LaunchGalleryService.items(ticketId: ticketId, role: .customer)) { $0.first { $0.id == ids[1] }?.favorited == true }
        let purchase = try await LaunchGalleryService.recordPurchase(ticketId: ticketId, photoIds: [photoIds[0], photoIds[1]], clientRequestId: Self.newId())
        XCTAssertEqual(purchase[photoIds[0]], .granted)
        XCTAssertEqual(purchase[photoIds[1]], .granted)
        let bought = try await first(LaunchGalleryService.items(ticketId: ticketId, role: .customer)) { $0.first { $0.id == ids[0] }?.isPurchased == true }
        let fullresPath = try XCTUnwrap(bought.first { $0.id == photoIds[0] }?.fullresPath)
        let saved = FileManager.default.temporaryDirectory.appendingPathComponent("\(photoIds[0]).jpg")
        try? FileManager.default.removeItem(at: saved)
        try await LaunchGalleryService.downloadFullres(path: fullresPath, to: saved)
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: saved.path)[.size] as? Int)
        XCTAssertGreaterThan(size, 0)
        // 사지 않은 사진의 고화질본은 읽을 수 없다.
        let notBought = try XCTUnwrap(bought.first { $0.id == photoIds[2] }?.fullresPath)
        do {
            try await LaunchGalleryService.downloadFullres(path: notBought, to: FileManager.default.temporaryDirectory.appendingPathComponent("x.jpg"))
            XCTFail("사지 않은 고화질본을 받음")
        } catch {}
        // 작가에게는 사진별 구매됨·찜됨과 개수만 보인다(V5)
        _ = try await AccountService.signInForTesting(email: artist.email, password: artist.password)
        let marked = try await first(LaunchGalleryService.items(ticketId: ticketId, role: .photographer)) {
            $0.first { $0.id == ids[0] }?.isPurchased == true && $0.first { $0.id == ids[1] }?.favorited == true
        }
        XCTAssertNil(marked.first { $0.id == ids[0] }?.purchasedAt, "구매 시각은 고객 전용")
        let counted = try await first(LaunchGalleryService.gallery(ticketId: ticketId)) { $0?.purchasedCount == 2 }
        XCTAssertEqual(counted?.favoritedCount, 1)
        XCTAssertFalse(GalleryV2.canRemove(try XCTUnwrap(marked.first { $0.id == ids[0] }), currentCount: 10 + 5), "구매된 사진은 삭제 단추를 끈다")
        print("SBSN 갤러리 통과: 티켓 \(ticketId.prefix(6)) 10장 공개·구매 2장·고화질 \(size)B·작가 표시 구매 2·찜 1")
    }

    /// 시험용 sRGB JPEG(방향 1) 파일
    static func jpegFile(width: Int, height: Int, hue: CGFloat) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(hue: hue, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.white.setFill()
            context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try XCTUnwrap(image.jpegData(compressionQuality: 0.85)).write(to: url)
        return url
    }

    // MARK: - 도우미

    static func newId() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }

    /// 스트림에서 조건을 만족하는 첫 값(20초 안)
    func first<T: Sendable>(_ stream: AsyncThrowingStream<T, Error>, timeout: Duration = .seconds(20),
                            where condition: @escaping @Sendable (T) -> Bool) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                for try await value in stream where condition(value) { return value }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() ?? nil else {
                throw LaunchREST.Failure.timeout
            }
            return value
        }
    }
}

/// 에뮬레이터 REST(관리자 토큰 `owner`, 시험 계정 `launchTest` 클레임)
struct LaunchREST {
    struct Account {
        let email: String
        let password: String
        let uid: String
    }

    struct Artist {
        let uid: String
        let token: String
    }

    enum Failure: Error {
        case badResponse(Int, String)
        case timeout
    }

    let host: String
    let project = "demo-sbsn-functions"
    var auth: String { "http://\(host):19099" }

    func createAccount(prefix: String) async throws -> Account {
        let email = "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())@example.test"
        let password = UUID().uuidString
        let (status, body) = try await request("\(auth)/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key",
                                               body: ["email": email, "password": password, "returnSecureToken": true])
        guard status == 200, let uid = body["localId"] as? String else { throw Failure.badResponse(status, "signUp") }
        let (claims, _) = try await request("\(auth)/identitytoolkit.googleapis.com/v1/projects/\(project)/accounts:update",
                                            bearer: "owner", body: ["localId": uid, "customAttributes": #"{"launchTest":true}"#])
        guard claims == 200 else { throw Failure.badResponse(claims, "claims") }
        return Account(email: email, password: password, uid: uid)
    }

    func idToken(_ account: Account) async throws -> String {
        let (status, body) = try await request("\(auth)/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key",
                                               body: ["email": account.email, "password": account.password, "returnSecureToken": true])
        guard status == 200, let token = body["idToken"] as? String else { throw Failure.badResponse(status, "signIn") }
        return token
    }

    func approve(artistUid: String) async throws {
        let url = "http://\(host):18080/v1/projects/\(project)/databases/(default)/documents/launchArtistRoles/\(artistUid)"
        let (status, _) = try await request(url, method: "PATCH", bearer: "owner", body: ["fields": ["approved": ["booleanValue": true]]])
        guard status == 200 else { throw Failure.badResponse(status, "approve") }
    }

    /// 프로필·운영 승인·촬영 가능(1km, 2시간)까지 마친 작가
    func approvedAvailableArtist(nickname: String) async throws -> Artist {
        let account = try await createAccount(prefix: "artist")
        let token = try await idToken(account)
        _ = try await call("saveLaunchProfileV1", token: token, ["age14Confirmed": true, "nickname": nickname])
        try await approve(artistUid: account.uid)
        let ends = ISO8601DateFormatter().string(from: Date().addingTimeInterval(7200))
        let (status, body) = try await call("setLaunchAvailabilityV1", token: token, [
            "available": true, "deviceSessionId": UUID().uuidString.lowercased(),
            "radiusMeters": 1000, "availabilityEndsAt": ends, "breakReason": NSNull(),
        ])
        guard status == 200 else { throw Failure.badResponse(status, "availability \(body)") }
        return Artist(uid: account.uid, token: token)
    }

    /// 한 필드 같음 조건으로 문서를 찾는다(관리자). 문자열 필드만 돌려준다.
    func query(collection: String, field: String, equals value: String) async throws -> [[String: String]] {
        let (status, body) = try await requestArray("http://\(host):18080/v1/projects/\(project)/databases/(default)/documents:runQuery",
                                                    bearer: "owner", body: ["structuredQuery": [
                                                        "from": [["collectionId": collection]],
                                                        "where": ["fieldFilter": ["field": ["fieldPath": field], "op": "EQUAL",
                                                                                  "value": ["stringValue": value]]],
                                                    ]])
        guard status == 200 else { throw Failure.badResponse(status, "runQuery") }
        return body.compactMap { row in
            guard let fields = (row["document"] as? [String: Any])?["fields"] as? [String: [String: Any]] else { return nil }
            return fields.compactMapValues { $0["stringValue"] as? String }
        }
    }

    private func requestArray(_ url: String, bearer: String, body: Any) async throws -> (Int, [[String: Any]]) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? [])
    }

    /// 문서 필드(관리자 REST). 없으면 nil
    func document(_ path: String) async throws -> [String: Any]? {
        var request = URLRequest(url: URL(string: "http://\(host):18080/v1/projects/\(project)/databases/(default)/documents/\(path)")!)
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["fields"] as? [String: Any]
    }

    /// callable을 HTTP로 부른다. 결과의 `result`(실패면 `error`)를 돌려준다.
    func call(_ name: String, token: String, _ data: [String: Any]) async throws -> (Int, [String: Any]) {
        let (status, body) = try await request("http://\(host):15001/\(project)/asia-northeast3/\(name)", bearer: token, body: ["data": data])
        return (status, (body["result"] as? [String: Any]) ?? (body["error"] as? [String: Any]) ?? body)
    }

    private func request(_ url: String, method: String = "POST", bearer: String? = nil, body: Any) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
    }
}
