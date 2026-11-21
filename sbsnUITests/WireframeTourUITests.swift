import XCTest

/// 두 앱의 탭과 메뉴를 차례로 열어 화면을 캡처한다(와이어프레임 확인용, 시뮬레이터).
///
///   xcodebuild test -scheme sbsn -destination 'platform=iOS Simulator,id=<기기>' \
///     -only-testing:sbsnUITests/WireframeTourUITests
///
/// 작가 앱은 미리 설치해 둔다. 티켓이 있어야 보이는 화면(가격·조건 확인, 만나기, 결제 자리, 사진 고르기, 촬영 화면)은
/// 실기기 사이클(`CycleDriverUITests`)에서 캡처한다. 서버에는 쓰지 않는다: 확정·촬영 가능은 누르지 않는다.
/// `TEST_RUNNER_SBSN_SHOT_DIR`을 주면 캡처를 그 폴더에 PNG로도 남긴다.
@MainActor
final class WireframeTourUITests: XCTestCase {
    let customerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsn")
    let photographerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsnPhotographer")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func test_customerTour() throws {
        let app = customerApp
        app.launch()
        dismissAlerts()
        XCTAssertTrue(app.tabBars.buttons["촬영"].waitForExistence(timeout: 30), "탭 바가 없음(로그인 확인)")
        shot("고객-촬영-지도", app)

        app.buttons["목록"].tap()
        XCTAssertTrue(app.staticTexts["준비 중"].waitForExistence(timeout: 5), "작가 목록 빈 페이지가 없음")
        shot("고객-촬영-목록", app)
        app.buttons["지도"].tap()
        for id in ["conditions", "events"] {
            openPlanned(id, in: app, name: "고객-촬영")
        }

        app.tabBars.buttons["내 사진"].tap()
        XCTAssertTrue(app.navigationBars["내 사진"].waitForExistence(timeout: 5))
        shot("고객-내사진", app)
        for id in ["album", "orders", "retouch", "shareAndPrint"] {
            openPlanned(id, in: app, name: "고객-내사진")
        }

        app.tabBars.buttons["마이"].tap()
        XCTAssertTrue(app.navigationBars["마이"].waitForExistence(timeout: 5))
        shot("고객-마이", app)
        for id in ["profile", "accountLink", "help", "inquiry", "refund", "terms", "events"] {
            openPlanned(id, in: app, name: "고객-마이")
        }
        openDeveloper(in: app, name: "고객-마이-개발")
        app.tabBars.buttons["촬영"].tap()
    }

    func test_photographerTour() throws {
        let app = photographerApp
        app.launch()
        dismissAlerts()
        XCTAssertTrue(app.tabBars.buttons["촬영"].waitForExistence(timeout: 30), "탭 바가 없음(로그인 확인)")
        XCTAssertTrue(app.switches["photographer.available"].waitForExistence(timeout: 20), "촬영 가능 토글이 없음")
        shot("작가-촬영-대기", app)
        for id in ["activityArea", "breakTime", "requestPolicy"] {
            openPlanned(id, in: app, name: "작가-촬영")
        }

        app.tabBars.buttons["내역"].tap()
        XCTAssertTrue(app.navigationBars["내역"].waitForExistence(timeout: 5))
        shot("작가-내역", app)
        for id in ["history", "sales", "settlement", "feedback", "disputes"] {
            openPlanned(id, in: app, name: "작가-내역")
        }

        app.tabBars.buttons["마이"].tap()
        XCTAssertTrue(app.navigationBars["마이"].waitForExistence(timeout: 5))
        shot("작가-마이", app)
        for id in ["portfolio", "registration", "originals", "support", "terms"] {
            openPlanned(id, in: app, name: "작가-마이")
        }
        openDeveloper(in: app, name: "작가-마이-개발")
        app.tabBars.buttons["촬영"].tap()
    }

    // MARK: - 도구

    /// 빈 페이지 행(`planned.<id>`)을 눌러 "준비 중" 화면을 캡처하고 돌아온다. 화면 밖이면 내려 가며 찾는다.
    private func openPlanned(_ id: String, in app: XCUIApplication, name: String) {
        let link = app.descendants(matching: .any)["planned.\(id)"].firstMatch
        for _ in 0..<4 where !(link.exists && link.isHittable) {
            app.swipeUp()
        }
        guard link.waitForExistence(timeout: 5) else {
            XCTFail("\(id) 메뉴가 없음")
            return
        }
        link.tap()
        XCTAssertTrue(app.staticTexts["준비 중"].waitForExistence(timeout: 5), "\(id) 빈 페이지가 뜨지 않음")
        shot("\(name)-\(id)", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func openDeveloper(in app: XCUIApplication, name: String) {
        let link = app.descendants(matching: .any)["my.developer"].firstMatch
        for _ in 0..<4 where !(link.exists && link.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 5), "개발 메뉴가 없음")
        link.tap()
        XCTAssertTrue(app.navigationBars["개발"].waitForExistence(timeout: 5))
        shot(name, app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// 위치·알림 권한 창이 뜨면 허용한다.
    private func dismissAlerts() {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 1) else { continue }
            let allow = alert.buttons.matching(NSPredicate(format: "(label CONTAINS '허용' AND NOT label CONTAINS '안 함') OR label BEGINSWITH 'Allow'")).firstMatch
            if allow.exists { allow.tap() } else { return }
        }
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SBSN_SHOT_DIR"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
