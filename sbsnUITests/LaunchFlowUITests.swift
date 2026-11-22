import XCTest

/// 출시 1단계 흐름(D059)을 개발용 에뮬레이터에서 돈다. 앱은 `-SBSNEmulatorHost`로 띄운다(시뮬레이터 127.0.0.1).
///
/// 시험 계정은 Auth 에뮬레이터에 만들고 `launchTest: true` 클레임을 붙여 둔다(L09). 이메일·비밀번호는
/// `TEST_RUNNER_SBSN_TEST_EMAIL`·`TEST_RUNNER_SBSN_TEST_PASSWORD`로 넘기고 저장소에 적지 않는다.
@MainActor
final class LaunchFlowUITests: XCTestCase {
    var environment: [String: String] { ProcessInfo.processInfo.environment }
    var emulatorHost: String { environment["SBSN_EMULATOR_HOST"] ?? "127.0.0.1" }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 고객: 마이 → 로그인 → 만 14세 확인 → 시험 로그인 → 닉네임이 보인다 → 로그아웃하면 다시 둘러보기
    func test_L1_customerTestLoginAndSignOut() throws {
        let email = try XCTUnwrap(environment["SBSN_TEST_EMAIL"])
        let password = try XCTUnwrap(environment["SBSN_TEST_PASSWORD"])
        let app = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsn")
        app.launchArguments = ["-SBSNEmulatorHost", emulatorHost]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 30))
        app.tabBars.buttons["마이"].tap()
        let signIn = app.buttons["my.signIn"]
        // 지난 실행에서 로그인한 채로 남았으면 먼저 로그아웃한다.
        if app.buttons["my.signOut"].waitForExistence(timeout: 5) {
            signOutOrDiagnose(app)
        }
        XCTAssertTrue(signIn.waitForExistence(timeout: 10), "로그인 단추가 없음(익명 상태가 아님?)")
        signIn.tap()
        let age = app.switches["signIn.age14"]
        XCTAssertTrue(age.waitForExistence(timeout: 10))
        if age.value as? String != "1" { age.switches.firstMatch.tap() }
        let emailField = app.textFields["signIn.test.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "시험 로그인 칸이 없음(에뮬레이터 아님?)")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.textFields["signIn.test.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signIn.test.submit"].tap()
        XCTAssertTrue(waitForDisappearance(app.switches["signIn.age14"], timeout: 30), "로그인 시트가 닫히지 않음")
        // 시험 계정 비밀번호를 넣으면 iOS가 "암호를 저장하겠습니까?"를 띄워 다음 탭을 막는다. 저장하지 않는다.
        // 이 창은 앱 창 안(원격 뷰)이나 스프링보드에 뜬다. 둘 다 본다.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<20 {
            if app.buttons["지금 안 함"].exists { app.buttons["지금 안 함"].tap(); break }
            if springboard.buttons["지금 안 함"].exists { springboard.buttons["지금 안 함"].tap(); break }
            usleep(500_000)
        }
        let nickname = app.descendants(matching: .any)["my.nickname"]
        if !nickname.waitForExistence(timeout: 30) {
            let error = app.staticTexts["signIn.error"]
            XCTFail("로그인 뒤 닉네임이 보이지 않음: \(error.exists ? error.label : "-")")
        }
        print("SBSN 로그인 닉네임 \(nickname.label)")
        XCTAssertTrue(app.buttons["my.signOut"].waitForExistence(timeout: 5))
        signOutOrDiagnose(app)
        print("SBSN 로그아웃 뒤 익명 둘러보기")
    }

    /// 고객: 로그인 시트의 "Google로 계속하기"가 Google 계정 화면을 연다(URL scheme 설정 확인). 실제 로그인은 하지 않고 취소한다.
    func test_L5_googleSignInOpens() throws {
        let app = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsn")
        app.launchArguments = ["-SBSNEmulatorHost", emulatorHost]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 30))
        app.tabBars.buttons["마이"].tap()
        if app.buttons["my.signOut"].waitForExistence(timeout: 5) {
            signOutOrDiagnose(app)
        }
        XCTAssertTrue(app.buttons["my.signIn"].waitForExistence(timeout: 10))
        app.buttons["my.signIn"].tap()
        let age = app.switches["signIn.age14"]
        XCTAssertTrue(age.waitForExistence(timeout: 10))
        if age.value as? String != "1" { age.switches.firstMatch.tap() }
        let google = app.buttons["signIn.google"]
        XCTAssertTrue(waitUntilTrue(timeout: 5) { google.isEnabled }, "Google 단추가 눌리지 않음")
        google.tap()
        // 웹 인증 세션은 먼저 시스템 확인 창("로그인하기 위해 'google.com'을 사용하려고 합니다")을 띄운다.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let proceed = springboard.alerts.buttons["계속"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 15), "Google 로그인 확인 창이 뜨지 않음: \(app.staticTexts["signIn.error"].exists ? app.staticTexts["signIn.error"].label : "-")")
        print("SBSN Google 확인 창: \(springboard.alerts.firstMatch.label)")
        proceed.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 30), "Google 계정 화면이 열리지 않음")
        sleep(3)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Google 계정 화면"
        shot.lifetime = .keepAlways
        add(shot)
        print("SBSN Google 계정 화면 열림")
        let cancel = app.buttons["취소"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(age.waitForExistence(timeout: 10), "취소 뒤 로그인 시트로 돌아오지 않음")
        sleep(1)
        XCTAssertFalse(app.staticTexts["signIn.error"].exists, "취소했는데 오류 문구가 보임")
        print("SBSN Google 취소 뒤 로그인 시트, 오류 없음")
    }

    private func waitUntilTrue(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return condition()
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists, Date() < deadline { usleep(200_000) }
        return !element.exists
    }

    /// 로그아웃하고 둘러보기(로그인 단추)로 돌아오는지 본다. 안 되면 세션이 개발 화면에 남긴 메시지를 출력한다.
    private func signOutOrDiagnose(_ app: XCUIApplication) {
        app.buttons["my.signOut"].tap()
        if !app.buttons["my.signIn"].waitForExistence(timeout: 20) {
            let tree = app.debugDescription.split(separator: "\n")
                .filter { $0.contains("my.") || $0.contains("로그인") || $0.contains("NavigationBar") || $0.contains("Selected") }
                .map { $0.trimmingCharacters(in: .whitespaces).prefix(140) }
            print("SBSN 로그아웃 뒤 화면", tree.joined(separator: " || "))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "로그아웃 뒤"
            shot.lifetime = .keepAlways
            add(shot)
            let developer = app.buttons["my.developer"]
            for _ in 0..<6 where !developer.isHittable { app.swipeUp() }
            developer.tap()
            sleep(2)
            let messages = app.debugDescription.split(separator: "\n").filter { $0.contains("계정") || $0.contains("uid") || $0.contains("Error") || $0.contains("오류") }
                .map { $0.trimmingCharacters(in: .whitespaces).prefix(220) }
            print("SBSN 개발 화면 메시지", messages.joined(separator: " || "))
            XCTFail("로그아웃 뒤 둘러보기로 돌아가지 않음")
        }
    }
}
