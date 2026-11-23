import XCTest

/// 출시 2단계 고객 화면(설계 2.2·2.4·2.5)을 공용 개발 에뮬레이터에서 돈다. 작가는 작가 앱으로 촬영 가능을 켜고(1단계 발행),
/// 신청 응답·시작·연장 동의는 REST(시험 계정 ID 토큰)로 한다. 시뮬레이터 위치는 서울, 두 앱 위치 권한은 미리 허용해 둔다.
@MainActor
final class LaunchMatchUITests: XCTestCase {
    var host: String { ProcessInfo.processInfo.environment["SBSN_EMULATOR_HOST"] ?? "127.0.0.1" }
    lazy var admin = EmulatorAdmin(host: host)
    let photographerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsnPhotographer")
    let customerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsn")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 지도 카드 → 채팅하기 → 글·연락처 가리기 → 신청 → (작가 수락) → 시작 → (작가 시작) → 연장 → (작가 동의) → 고객 종료 → 채팅 탭
    func test_L8_customerMatchToEnd() async throws {
        // 작가: 작가 앱에서 로그인·승인·촬영 가능(공개 지도 발행)
        let artist = try await admin.createTestAccount(prefix: "artist")
        photographerApp.launchArguments = ["-SBSNEmulatorHost", host]
        photographerApp.launch()
        try signIn(at: photographerApp, gate: true, account: artist)
        try await admin.setDocument("launchArtistRoles/\(artist.uid)", fields: ["approved": ["booleanValue": true]])
        photographerApp.tabBars.buttons["촬영"].tap()
        let toggle = photographerApp.switches["photographer.available"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(photographerApp.buttons["availability.on"].waitForExistence(timeout: 5), "켜기 시트가 없음")
        attachScreenshot("L8 켜기 시트", app: photographerApp)
        photographerApp.buttons["availability.on"].tap()
        dismissNotificationPrompt()
        let onStatus = photographerApp.staticTexts["home.status"]
        if !onStatus.waitForExistence(timeout: 15) {
            attachScreenshot("L8 켜기 뒤", app: photographerApp)
            XCTFail("켜기 뒤 상태 줄이 없음: \(photographerApp.staticTexts["photographer.error"].exists ? photographerApp.staticTexts["photographer.error"].label : "-")")
        }
        let published = try await waitFor("publicPhotographers/\(artist.uid)", timeout: 90)
        XCTAssertTrue(published, "작가 발행이 지도에 없음")
        let profile = try await admin.document("users/\(artist.uid)")
        let nickname = try XCTUnwrap(profile?.string("nickname"))
        let artistToken = try await admin.idToken(email: artist.email, password: artist.password)
        print("SBSN 작가 발행: \(nickname)")

        // 고객: 로그인 → 지도 핀 → 카드 → 채팅하기
        let customer = try await admin.createTestAccount(prefix: "customer")
        let app = customerApp
        app.launchArguments = ["-SBSNEmulatorHost", host]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 30))
        app.tabBars.buttons["마이"].tap()
        if app.buttons["my.signOut"].waitForExistence(timeout: 5) { app.buttons["my.signOut"].tap() }
        XCTAssertTrue(app.buttons["my.signIn"].waitForExistence(timeout: 20))
        app.buttons["my.signIn"].tap()
        try signIn(at: app, gate: false, account: customer)
        XCTAssertTrue(app.descendants(matching: .any)["my.nickname"].waitForExistence(timeout: 30))
        app.tabBars.buttons["촬영"].tap()
        // 같은 칸에 다른 시험 작가(공용 에뮬레이터의 Android 시험 등)가 있으면 묶음으로 보인다. 묶음을 차례로 눌러 목록에서 고른다.
        XCTAssertTrue(openCard(of: nickname, in: app, timeout: 120), "지도에서 작가를 찾지 못함")
        let status = app.staticTexts["map.card.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "작가 카드가 없음")
        print("SBSN 카드 상태: \(status.label)")
        XCTAssertTrue(status.label.hasPrefix("촬영 가능"), "같은 위치인데 \(status.label)")
        // 프로필(W9): 작가가 저장한 소개가 보이고 [채팅하기]로 이어진다.
        _ = try await admin.call("saveLaunchProfileV1", idToken: artistToken,
                                 data: ["age14Confirmed": true, "nickname": NSNull(), "bio": "궁 촬영 전문", "recommendedShootMinutes": 25])
        app.buttons["map.card.profile"].tap()
        XCTAssertTrue(app.staticTexts["궁 촬영 전문"].waitForExistence(timeout: 15), "프로필 소개가 없음")
        app.buttons["profile.chat"].tap()

        // 글 → 연락처는 가리고 보내기
        let input = app.textViews["chat.input"].exists ? app.textViews["chat.input"] : app.textFields["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 20), "대화방이 열리지 않음")
        input.tap()
        input.typeText("경복궁 정문 앞이에요")
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts["경복궁 정문 앞이에요"].waitForExistence(timeout: 15), "보낸 글이 보이지 않음")
        input.tap()
        input.typeText("010-1234-5678 로 연락 주세요")
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts["chat.contactPreview"].waitForExistence(timeout: 5), "연락처 경고가 없음")
        app.buttons["chat.contactMask"].tap()
        XCTAssertTrue(app.staticTexts["***-****-**** 로 연락 주세요"].waitForExistence(timeout: 15), "가린 글이 보이지 않음")

        // 신청(20분) → 대기 막대
        app.buttons["request.open"].tap()
        let submit = app.buttons["request.submit"]
        if !submit.waitForExistence(timeout: 30) {
            XCTFail("신청 단추가 없음: \(app.staticTexts["request.blocked"].exists ? app.staticTexts["request.blocked"].label : "-")")
        }
        submit.tap()
        XCTAssertTrue(app.staticTexts["request.waiting"].waitForExistence(timeout: 15), "수락 대기 막대가 없음")
        let requests = try await admin.query(collection: "launchMatchRequests", field: "customerUid", equals: customer.uid)
        let requestId = try XCTUnwrap(requests.first?.id)

        // 작가 수락 → 촬영 탭이 티켓 화면(시작 대기)
        let (accepted, acceptBody) = try await admin.call("respondLaunchMatchV1", idToken: artistToken, data: ["requestId": requestId, "action": "accept"])
        XCTAssertEqual(accepted, 200, "\(acceptBody)")
        let ticketId = requestId
        let start = app.buttons["ticket.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "시작 대기 화면이 아님")
        XCTAssertTrue(app.buttons["ticket.map"].exists, "시작 대기에 위치 단추가 없음")

        // 계정 삭제는 막히고 [진행 중인 촬영 보기]로 티켓에 돌아온다(D065, 설계 2.6).
        app.tabBars.buttons["마이"].tap()
        app.buttons["my.deleteAccount"].tap()
        let blockedText = app.staticTexts["my.deleteAccount.error"]
        XCTAssertTrue(blockedText.waitForExistence(timeout: 10), "삭제 막힘 안내가 없음")
        XCTAssertEqual(blockedText.label, "진행 중인 촬영을 끝내거나 취소한 뒤 삭제할 수 있습니다")
        app.buttons["my.deleteAccount.blocker"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10), "진행 중인 촬영 보기로 티켓에 돌아오지 않음")
        start.tap()
        app.buttons["ticket.start.confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ticket.waitingOther"].waitForExistence(timeout: 15))
        let (started, _) = try await admin.call("updateLaunchShootingV1", idToken: artistToken, data: ["ticketId": ticketId, "action": "start"])
        XCTAssertEqual(started, 200)
        let remaining = app.staticTexts["ticket.remaining"]
        XCTAssertTrue(remaining.waitForExistence(timeout: 20), "촬영 중 화면이 아님")
        print("SBSN 남은 시간: \(remaining.label)")
        XCTAssertTrue(remaining.label.hasSuffix("분 남음"))
        attachScreenshot("L8 촬영 중", app: app)

        // 연장 → 작가 동의 → 늘어남
        app.buttons["ticket.extend"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticket.extensionWaiting"].waitForExistence(timeout: 15))
        let ticketDoc = try await admin.document("launchTickets/\(ticketId)")
        let extensionId = try XCTUnwrap(ticketDoc?.string("pendingExtensionId"))
        let (agreed, _) = try await admin.call("respondLaunchExtensionV1", idToken: artistToken,
                                               data: ["ticketId": ticketId, "extensionId": extensionId, "accept": true])
        XCTAssertEqual(agreed, 200)
        XCTAssertTrue(app.staticTexts["5분 연장됐어요"].waitForExistence(timeout: 15), "연장 결과가 없음")

        // 고객 종료 → 지도로
        app.buttons["ticket.end"].tap()
        app.buttons["ticket.end.confirm"].firstMatch.tap()
        XCTAssertTrue(app.buttons["customer.findMode"].waitForExistence(timeout: 20) || app.segmentedControls["customer.findMode"].waitForExistence(timeout: 5),
                      "종료 뒤 지도로 돌아가지 않음")
        let ended = try await admin.document("launchTickets/\(ticketId)")
        XCTAssertEqual(ended?.string("status"), "ended")
        XCTAssertEqual(ended?.string("endedByRole"), "customer")

        // 채팅 탭: 방이 있고 서버 시스템 메시지가 보인다.
        app.tabBars.buttons["채팅"].tap()
        let row = app.buttons["chat.row"].firstMatch.exists ? app.buttons["chat.row"].firstMatch : app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "채팅 목록에 방이 없음")
        row.tap()
        XCTAssertTrue(app.staticTexts["chat.system"].firstMatch.waitForExistence(timeout: 15), "시스템 메시지가 없음")
        attachScreenshot("L8 대화방", app: app)

        // 정리: 작가 끄기
        photographerApp.activate()
        if toggle.waitForExistence(timeout: 10), toggle.value as? String == "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
    }

    /// 작가 화면(설계 2.3·2.5): 켜기 시트 → 새 신청 카드 → 사유 거절(누르면 바로) → 수락 → 시작 → 연장 동의 → 작가 종료 → 휴게 → 채팅 탭
    func test_L9_photographerRequestsToEnd() async throws {
        let artist = try await admin.createTestAccount(prefix: "artist")
        let app = photographerApp
        app.launchArguments = ["-SBSNEmulatorHost", host]
        app.launch()
        try signIn(at: app, gate: true, account: artist)
        try await admin.setDocument("launchArtistRoles/\(artist.uid)", fields: ["approved": ["booleanValue": true]])
        app.tabBars.buttons["촬영"].tap()
        let toggle = app.switches["photographer.available"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["availability.on"].waitForExistence(timeout: 5), "켜기 시트가 없음")
        app.buttons["availability.on"].tap()
        dismissNotificationPrompt()
        let status = app.staticTexts["home.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), "상태 줄이 없음")
        print("SBSN 작가 상태: \(status.label)")
        XCTAssertTrue(status.label.hasPrefix("촬영 가능 · 1km · "))
        let device = try await admin.document("launchDevices/\(artist.uid)")
        XCTAssertEqual(device?.int("radiusMeters"), 1000, "반경이 서버에 없음")

        // 프로필 편집(W9): 마이 → 프로필 → 소개 → 저장
        app.tabBars.buttons["마이"].tap()
        app.buttons["my.profile"].tap()
        let bio = app.textViews["profile.bio"].exists ? app.textViews["profile.bio"] : app.textFields["profile.bio"]
        XCTAssertTrue(bio.waitForExistence(timeout: 15), "프로필 편집 화면이 아님")
        bio.tap()
        bio.typeText("야경 촬영 좋아해요")
        app.buttons["profile.save"].tap()
        XCTAssertTrue(app.staticTexts["저장했어요"].waitForExistence(timeout: 15), "프로필 저장 안내가 없음")
        let savedProfile = try await admin.document("users/\(artist.uid)")
        XCTAssertEqual(savedProfile?.string("bio"), "야경 촬영 좋아해요")
        XCTAssertEqual(savedProfile?.int("recommendedShootMinutes"), 20, "추천 시간 기본값 20분이 저장되지 않음")
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["촬영"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["sanction.limited"].exists, "제재가 없는데 제한 배너가 보임")

        // 고객(REST): 프로필 → 방 → 신청
        let customer = try await admin.createTestAccount(prefix: "customer")
        let customerToken = try await admin.idToken(email: customer.email, password: customer.password)
        _ = try await admin.call("saveLaunchProfileV1", idToken: customerToken, data: ["age14Confirmed": true, "nickname": "고객1"])
        let (_, opened) = try await admin.call("openLaunchConversationV1", idToken: customerToken, data: ["artistUid": artist.uid])
        let roomId = try XCTUnwrap((opened["result"] as? [String: Any])?["roomId"] as? String)
        func request(_ minutes: Int) async throws -> String {
            let (code, body) = try await admin.call("requestLaunchMatchV1", idToken: customerToken,
                                                    data: ["roomId": roomId, "minutes": minutes, "clientRequestId": UUID().uuidString.lowercased()])
            XCTAssertEqual(code, 200, "\(body)")
            return try XCTUnwrap((body["result"] as? [String: Any])?["requestId"] as? String)
        }

        // 거절: 보기를 누르면 바로 거절된다.
        let first = try await request(30)
        let card = app.descendants(matching: .any)["request.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "새 신청 카드가 없음")
        XCTAssertTrue(app.staticTexts["고객1 · 30분"].exists, "고객 닉네임·분이 카드에 없음")
        app.buttons["request.decline"].firstMatch.tap()
        app.buttons["decline.reason.too_far"].firstMatch.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { !card.exists }, "거절 뒤 카드가 남음")
        let declined = try await admin.document("launchMatchRequests/\(first)")
        XCTAssertEqual(declined?.string("status"), "declined")
        XCTAssertEqual(declined?.string("declineReason"), "too_far")

        // 수락 → 티켓(시작 대기) → 양쪽 시작
        let second = try await request(20)
        XCTAssertTrue(app.buttons["request.accept"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["request.accept"].firstMatch.tap()
        let start = app.buttons["ticket.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "수락 뒤 티켓 화면이 아님")
        _ = try await admin.call("updateLaunchShootingV1", idToken: customerToken, data: ["ticketId": second, "action": "start"])
        XCTAssertTrue(app.staticTexts["ticket.otherStarted"].waitForExistence(timeout: 15), "고객 시작이 보이지 않음")
        start.tap()
        app.buttons["ticket.start.confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ticket.remaining"].waitForExistence(timeout: 20), "촬영 중 화면이 아님")

        // 연장 동의
        _ = try await admin.call("requestLaunchExtensionV1", idToken: customerToken,
                                 data: ["ticketId": second, "clientRequestId": UUID().uuidString.lowercased()])
        XCTAssertTrue(app.buttons["extension.accept"].waitForExistence(timeout: 20), "연장 카드가 없음")
        app.buttons["extension.accept"].tap()
        XCTAssertTrue(waitUntil(timeout: 15) { !app.buttons["extension.accept"].exists })
        let extended = try await admin.document("launchTickets/\(second)")
        XCTAssertEqual(extended?.int("extensionMinutes"), 5)

        // 작가 종료 → 홈
        app.buttons["ticket.end"].tap()
        app.buttons["ticket.end.confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["home.status"].waitForExistence(timeout: 20), "종료 뒤 홈이 아님")
        let ended = try await admin.document("launchTickets/\(second)")
        XCTAssertEqual(ended?.string("endedByRole"), "photographer")

        // 휴게 → 신청 거부 → 휴게 끝
        app.buttons["break.start"].tap()
        app.buttons["break.reason.meal"].firstMatch.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { app.staticTexts["home.status"].label.hasPrefix("휴게 중 · 식사") }, "휴게 상태가 아님")
        let (onBreak, _) = try await admin.call("requestLaunchMatchV1", idToken: customerToken,
                                                data: ["roomId": roomId, "minutes": 20, "clientRequestId": UUID().uuidString.lowercased()])
        XCTAssertNotEqual(onBreak, 200, "휴게 중 신청이 접수됨")
        app.buttons["break.end"].tap()
        XCTAssertTrue(waitUntil(timeout: 15) { app.staticTexts["home.status"].label.hasPrefix("촬영 가능") }, "휴게가 끝나지 않음")
        attachScreenshot("L9 작가 홈", app: app)

        // 채팅 탭: 방과 서버 시스템 메시지
        app.tabBars.buttons["채팅"].tap()
        let row = app.buttons["chat.row"].firstMatch.exists ? app.buttons["chat.row"].firstMatch : app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "채팅 목록에 방이 없음")
        row.tap()
        XCTAssertTrue(app.staticTexts["chat.system"].firstMatch.waitForExistence(timeout: 15), "시스템 메시지가 없음")
        attachScreenshot("L9 대화방", app: app)

        app.tabBars.buttons["촬영"].tap()
        if toggle.waitForExistence(timeout: 10), toggle.value as? String == "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
    }

    /// 출시 알림을 누르면 그 대화방으로 간다(설계 2.7). 알림은 셸이 `xcrun simctl push`로 보낸다:
    /// 이 시험이 "SBSN PUSH READY <roomId>"를 찍으면 그 방의 chat_message를 보낸다(scratchpad 실행 스크립트).
    func test_L10_notificationOpensRoom() async throws {
        let artist = try await admin.createTestAccount(prefix: "artist")
        let artistToken = try await admin.idToken(email: artist.email, password: artist.password)
        _ = try await admin.call("saveLaunchProfileV1", idToken: artistToken, data: ["age14Confirmed": true, "nickname": "작가1"])
        try await admin.setDocument("launchArtistRoles/\(artist.uid)", fields: ["approved": ["booleanValue": true]])
        let customer = try await admin.createTestAccount(prefix: "customer")
        let app = customerApp
        app.launchArguments = ["-SBSNEmulatorHost", host]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 30))
        app.tabBars.buttons["마이"].tap()
        if app.buttons["my.signOut"].waitForExistence(timeout: 5) { app.buttons["my.signOut"].tap() }
        XCTAssertTrue(app.buttons["my.signIn"].waitForExistence(timeout: 20))
        app.buttons["my.signIn"].tap()
        try signIn(at: app, gate: false, account: customer)
        XCTAssertTrue(app.descendants(matching: .any)["my.nickname"].waitForExistence(timeout: 30))
        let customerToken = try await admin.idToken(email: customer.email, password: customer.password)
        let (_, opened) = try await admin.call("openLaunchConversationV1", idToken: customerToken, data: ["artistUid": artist.uid])
        let roomId = try XCTUnwrap((opened["result"] as? [String: Any])?["roomId"] as? String)

        // 대화방을 한 번 열어 알림 권한을 허용한다.
        app.tabBars.buttons["채팅"].tap()
        let row = app.buttons["chat.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "채팅 목록에 방이 없음")
        row.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["허용"].waitForExistence(timeout: 5) { springboard.buttons["허용"].tap() }
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["촬영"].tap()

        print("SBSN PUSH READY \(roomId)")
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "새 메시지가 왔어요")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 90), "알림 배너가 오지 않음")
        banner.tap()
        let input = app.textViews["chat.input"].exists ? app.textViews["chat.input"] : app.textFields["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15), "알림을 눌러도 대화방이 열리지 않음")
        XCTAssertTrue(app.tabBars.buttons["채팅"].isSelected, "채팅 탭이 아님")
        attachScreenshot("L10 알림으로 연 대화방", app: app)
    }

    // MARK: - 도우미

    /// 지도에서 그 작가 카드를 연다: 단독 핀이면 누르고, 묶음이면 하나씩 눌러 목록에 그 작가가 있으면 고른다.
    private func openCard(of nickname: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let marker = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "marker.\(nickname)")).firstMatch
        let row = app.buttons["map.cluster.\(nickname)"]
        while Date() < deadline {
            if marker.exists {
                marker.tap()
                return app.staticTexts["map.card.status"].waitForExistence(timeout: 10)
            }
            let clusters = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "cluster.")).allElementsBoundByIndex
            for cluster in clusters where cluster.exists && cluster.isHittable {
                cluster.tap()
                if row.waitForExistence(timeout: 3) {
                    row.tap()
                    return app.staticTexts["map.card.status"].waitForExistence(timeout: 10)
                }
            }
            sleep(5)
        }
        return false
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(300_000)
        }
        return condition()
    }

    private func signIn(at app: XCUIApplication, gate: Bool, account: EmulatorAdmin.TestAccount) throws {
        let age = app.switches["signIn.age14"]
        if gate, !age.waitForExistence(timeout: 15) {
            app.tabBars.buttons["마이"].tap()
            app.buttons["my.signOut"].tap()
        }
        XCTAssertTrue(age.waitForExistence(timeout: 20))
        if age.value as? String != "1" { age.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let email = app.textFields["signIn.test.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "시험 로그인 칸이 없음(에뮬레이터 아님?)")
        email.tap()
        email.typeText(account.email)
        let password = app.textFields["signIn.test.password"]
        password.tap()
        password.typeText(account.password)
        app.buttons["signIn.test.submit"].tap()
        if gate {
            XCTAssertTrue(app.tabBars.buttons["촬영"].waitForExistence(timeout: 30), "로그인 뒤 탭이 없음")
        }
        dismissNotificationPrompt()
    }

    private func dismissNotificationPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<6 {
            for label in ["지금 안 함", "허용 안 함", "허용"] where springboard.buttons[label].exists {
                springboard.buttons[label].tap()
                return
            }
            usleep(500_000)
        }
    }

    private func waitFor(_ path: String, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await admin.document(path) != nil { return true }
            try await Task.sleep(for: .seconds(2))
        }
        return false
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension EmulatorAdmin {
    /// 한 필드 같음 조건으로 문서를 찾는다(관리자 REST runQuery)
    func query(collection: String, field: String, equals value: String) async throws -> [(id: String, fields: [String: Any])] {
        var request = URLRequest(url: URL(string: "http://\(host):18080/v1/projects/\(project)/databases/(default)/documents:runQuery")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": [
            "from": [["collectionId": collection]],
            "where": ["fieldFilter": ["field": ["fieldPath": field], "op": "EQUAL", "value": ["stringValue": value]]],
        ]])
        let (data, _) = try await URLSession.shared.data(for: request)
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return rows.compactMap { row in
            guard let document = row["document"] as? [String: Any], let name = document["name"] as? String else { return nil }
            return (String(name.split(separator: "/").last ?? ""), document["fields"] as? [String: Any] ?? [:])
        }
    }
}
