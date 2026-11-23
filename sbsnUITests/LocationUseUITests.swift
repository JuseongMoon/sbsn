import CoreLocation
import XCTest

/// 위치를 쓰는 때(팀원 제보 2026-11-23, TestFlight 0.2(3) 밤새 배터리·위치 표시):
/// 작가는 촬영 가능을 끄면 모든 위치 수신이 멈추고, 고객은 앱이 뒤에 있는 동안 위치를 받지 않는다(L13).
/// 공용 개발 에뮬레이터에서 돈다. 시뮬레이터 위치는 `XCUIDevice.location`으로 움직인다.
@MainActor
final class LocationUseUITests: XCTestCase {
    var host: String { ProcessInfo.processInfo.environment["SBSN_EMULATOR_HOST"] ?? "127.0.0.1" }
    lazy var admin = EmulatorAdmin(host: host)
    let photographerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsnPhotographer")
    let customerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsn")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 작가: 켜면 위치 사용 켜짐 → 끄면 꺼짐, 그 뒤 위치를 움직이고 홈으로 나갔다 와도 꺼진 채(멈춘 뒤 받은 위치 0회)
    func test_L11_photographerStopsLocationWhenOff() async throws {
        let artist = try await admin.createTestAccount(prefix: "artist")
        let app = photographerApp
        app.launchArguments = ["-SBSNEmulatorHost", host]
        app.launch()
        try signInAtGate(app, account: artist)
        try await admin.setDocument("launchArtistRoles/\(artist.uid)", fields: ["approved": ["booleanValue": true]])
        app.tabBars.buttons["촬영"].tap()
        let toggle = app.switches["photographer.available"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["availability.on"].waitForExistence(timeout: 5))
        app.buttons["availability.on"].tap()
        dismissPrompts()
        XCTAssertTrue(app.staticTexts["home.status"].waitForExistence(timeout: 20))
        XCTAssertTrue(locationUsage(app).contains("켜짐"), "켰는데 위치 사용이 꺼짐: \(locationUsage(app))")

        app.tabBars.buttons["촬영"].tap()
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitUntil(timeout: 10) { toggle.value as? String == "0" })
        let off = locationUsage(app)
        print("SBSN 끈 뒤: \(off)")
        XCTAssertTrue(off.contains("꺼짐"), "끈 뒤에도 위치 사용: \(off)")

        // 위치를 움직이고, 홈으로 나가서도 움직인 뒤 돌아온다.
        try await move(steps: 3)
        XCUIDevice.shared.press(.home)
        try await move(steps: 3)
        app.activate()
        let after = locationUsage(app)
        print("SBSN 움직인 뒤: \(after)")
        XCTAssertTrue(after.contains("꺼짐") && after.hasSuffix("멈춘 뒤 받은 위치 0회"), "끈 뒤 위치를 받음: \(after)")
    }

    /// 작가(Android LR7과 같은 범위): 시작 대기 중 다른 기기가 넘겨받아 촬영 가능이 꺼져도 만나는 위치는 유지되고,
    /// 촬영이 시작되면 위치가 꺼진다(정밀 위치는 매칭~시작, L14. 촬영 가능과 별개로 티켓에 묶는다).
    func test_L13_meetupKeepsLocationUntilStart() async throws {
        let artist = try await admin.createTestAccount(prefix: "artist")
        let app = photographerApp
        app.launchArguments = ["-SBSNEmulatorHost", host]
        app.launch()
        try signInAtGate(app, account: artist)
        try await admin.setDocument("launchArtistRoles/\(artist.uid)", fields: ["approved": ["booleanValue": true]])
        let artistToken = try await admin.idToken(email: artist.email, password: artist.password)
        app.tabBars.buttons["촬영"].tap()
        let toggle = app.switches["photographer.available"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["availability.on"].waitForExistence(timeout: 5))
        app.buttons["availability.on"].tap()
        dismissPrompts()
        XCTAssertTrue(app.staticTexts["home.status"].waitForExistence(timeout: 20))

        // 고객(REST) 신청 → 작가 수락 → 시작 대기
        let customer = try await admin.createTestAccount(prefix: "customer")
        let customerToken = try await admin.idToken(email: customer.email, password: customer.password)
        _ = try await admin.call("saveLaunchProfileV1", idToken: customerToken, data: ["age14Confirmed": true, "nickname": "고객1"])
        let (_, opened) = try await admin.call("openLaunchConversationV1", idToken: customerToken, data: ["artistUid": artist.uid])
        let roomId = try XCTUnwrap((opened["result"] as? [String: Any])?["roomId"] as? String)
        let (_, requested) = try await admin.call("requestLaunchMatchV1", idToken: customerToken,
                                                  data: ["roomId": roomId, "minutes": 20, "clientRequestId": UUID().uuidString.lowercased()])
        let ticketId = try XCTUnwrap((requested["result"] as? [String: Any])?["requestId"] as? String)
        XCTAssertTrue(app.buttons["request.accept"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["request.accept"].firstMatch.tap()
        XCTAssertTrue(app.buttons["ticket.start"].waitForExistence(timeout: 20), "시작 대기 화면이 아님")

        // 다른 기기가 넘겨받는다 → 이 기기의 다음 발행에서 촬영 가능이 꺼진다(최대 1분).
        let (taken, _) = try await admin.call("setLaunchAvailabilityV1", idToken: artistToken, data: [
            "available": true, "deviceSessionId": UUID().uuidString.lowercased(), "radiusMeters": 1000,
            "availabilityEndsAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)), "breakReason": NSNull(),
        ])
        XCTAssertEqual(taken, 200)
        try await Task.sleep(for: .seconds(75))
        let meetup = locationUsage(app)
        print("SBSN 넘겨받은 뒤 시작 대기: \(meetup)")
        XCTAssertTrue(meetup.contains("켜짐"), "시작 대기 중인데 만나는 위치가 꺼짐: \(meetup)")

        // 양쪽 시작 → 촬영 중: 촬영 가능도 꺼져 있으니 위치가 꺼진다.
        _ = try await admin.call("updateLaunchShootingV1", idToken: customerToken, data: ["ticketId": ticketId, "action": "start"])
        app.tabBars.buttons["촬영"].tap()
        XCTAssertTrue(app.buttons["ticket.start"].waitForExistence(timeout: 15))
        app.buttons["ticket.start"].tap()
        app.buttons["ticket.start.confirm"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ticket.remaining"].waitForExistence(timeout: 20), "촬영 중 화면이 아님")
        let shooting = locationUsage(app)
        print("SBSN 촬영 시작 뒤: \(shooting)")
        XCTAssertTrue(shooting.contains("꺼짐"), "촬영 시작 뒤에도 위치 사용: \(shooting)")
        _ = try await admin.call("updateLaunchShootingV1", idToken: customerToken, data: ["ticketId": ticketId, "action": "end"])
    }

    /// 고객: 지도를 연 채 홈으로 나가 위치를 움직인 뒤 돌아오면 백그라운드에서 받은 위치가 0회
    func test_L12_customerNoLocationInBackground() async throws {
        let app = customerApp
        app.launchArguments = ["-SBSNEmulatorHost", host]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["촬영"].waitForExistence(timeout: 30))
        app.tabBars.buttons["촬영"].tap()
        try await move(steps: 2)
        XCUIDevice.shared.press(.home)
        try await move(steps: 5)
        app.activate()
        XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 15))
        sleep(2)
        app.tabBars.buttons["마이"].tap()
        XCTAssertTrue(waitUntil(timeout: 10) { app.navigationBars["마이"].exists }, "마이 탭이 열리지 않음")
        openDeveloper(app)
        let counter = app.descendants(matching: .any)["dev.backgroundLocation"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        print("SBSN 고객 \(counter.label)")
        XCTAssertTrue(counter.label.hasSuffix("0회"), "백그라운드에서 위치를 받음: \(counter.label)")
    }

    // MARK: - 도우미

    /// 마이 목록 맨 아래의 개발 메뉴(보일 때까지 내린다)
    private func openDeveloper(_ app: XCUIApplication) {
        let developer = app.buttons["my.developer"]
        for _ in 0..<6 where !(developer.exists && developer.isHittable) {
            app.swipeUp()
        }
        developer.tap()
    }

    private func locationUsage(_ app: XCUIApplication) -> String {
        app.tabBars.buttons["마이"].tap()
        openDeveloper(app)
        let usage = app.descendants(matching: .any)["dev.locationUsage"]
        guard usage.waitForExistence(timeout: 10) else { return "-" }
        let label = usage.label
        app.navigationBars.buttons.firstMatch.tap()
        return label
    }

    /// 서울 시청 둘레를 몇 걸음 움직인다(걸음마다 약 150m, 2초)
    private func move(steps: Int) async throws {
        for step in 1...steps {
            let location = CLLocation(latitude: 37.5665 + Double(step) * 0.0014, longitude: 126.9780)
            XCUIDevice.shared.location = XCUILocation(location: location)
            try await Task.sleep(for: .seconds(2))
        }
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 37.5665, longitude: 126.9780))
    }

    private func signInAtGate(_ app: XCUIApplication, account: EmulatorAdmin.TestAccount) throws {
        let age = app.switches["signIn.age14"]
        if !age.waitForExistence(timeout: 15) {
            app.tabBars.buttons["마이"].tap()
            app.buttons["my.signOut"].tap()
        }
        XCTAssertTrue(age.waitForExistence(timeout: 20))
        if age.value as? String != "1" { age.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        app.textFields["signIn.test.email"].tap()
        app.textFields["signIn.test.email"].typeText(account.email)
        app.textFields["signIn.test.password"].tap()
        app.textFields["signIn.test.password"].typeText(account.password)
        app.buttons["signIn.test.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["촬영"].waitForExistence(timeout: 30))
        dismissPrompts()
    }

    private func dismissPrompts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<6 {
            for label in ["지금 안 함", "허용 안 함", "허용"] where springboard.buttons[label].exists {
                springboard.buttons[label].tap()
                return
            }
            usleep(500_000)
        }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(300_000)
        }
        return condition()
    }
}
