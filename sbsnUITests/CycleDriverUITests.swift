import XCTest

/// 실기기 두 대로 MVP 사이클을 한 단계씩 돌리는 드라이버. 맥에서 단계마다 테스트 하나를 골라 실행한다.
///
///   xcodebuild test-without-building -xctestrun <파일> -destination id=<기기> \
///     -only-testing:sbsnUITests/CycleDriverUITests/test_P1_photographerGoesAvailable
///
/// 작가 단계(P)는 작가 폰, 고객 단계(C)는 고객 폰에서 실행한다. 다른 앱도 번들 ID로 띄워 조작한다.
/// 값은 실행할 때 `TEST_RUNNER_SBSN_*` 환경 변수로 넘긴다(앞의 TEST_RUNNER_는 떼고 읽는다).
@MainActor
final class CycleDriverUITests: XCTestCase {
    let photographerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsnPhotographer")
    let customerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsn")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    var photographerName: String { ProcessInfo.processInfo.environment["SBSN_NAME"] ?? "시험작가" }
    var message: String { ProcessInfo.processInfo.environment["SBSN_MESSAGE"] ?? "경복궁 정문 앞이에요" }
    var photoIndex: Int { Int(ProcessInfo.processInfo.environment["SBSN_PHOTO_INDEX"] ?? "0") ?? 0 }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 작가

    /// 이름을 넣고 "촬영 가능"을 켠 뒤 위치가 공유되면 홈으로 나간다(앱은 백그라운드 위치로 살아 있어야 한다).
    func test_P1_photographerGoesAvailable() throws {
        let app = photographerApp
        app.activate()
        let toggle = app.switches["photographer.available"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "촬영 가능 토글이 없음")
        if (toggle.value as? String) != "1" {
            let name = app.textFields["photographer.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            clearText(in: name)
            name.typeText(photographerName + "\n")
            tapSwitch(toggle)
        }
        allowSystemAlerts(seconds: 8)
        let location = app.descendants(matching: .any)["photographer.location"]
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 40) { location.label.contains("공유 중") || location.value as? String == "공유 중" },
                      "위치 공유 상태: \(location.label) \(String(describing: location.value))")
        attachScreenshot("P1 촬영 가능", app: app)
        XCUIDevice.shared.press(.home)
    }

    /// 매칭된 티켓 화면을 열고(알림 대신 앱을 직접 앞으로) 고객 메시지를 확인한 뒤 시작을 누른다.
    func test_P2_photographerStarts() throws {
        let app = photographerApp
        app.activate()
        let start = app.buttons["photographer.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "티켓 화면의 시작 버튼이 없음")
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 20), "고객 메시지가 보이지 않음")
        attachScreenshot("P2 만나기", app: app)
        XCTAssertTrue(waitUntil(timeout: 10) { start.isEnabled })
        start.tap()
        let end = app.buttons["photographer.end"]
        XCTAssertTrue(end.waitForExistence(timeout: 40), "촬영 화면으로 넘어가지 않음(고객이 시작했는지 확인)")
        printAddresses(app)
        attachScreenshot("P2 촬영 중", app: app)
    }

    /// 촬영 화면에서 받은 장수를 확인한다.
    func test_P3_photographerShowsReceived() throws {
        let app = photographerApp
        app.activate()
        XCTAssertTrue(app.buttons["photographer.end"].waitForExistence(timeout: 20))
        printAddresses(app)
        attachScreenshot("P3 수신", app: app)
    }

    /// 작가 앱을 백그라운드로 보낸다(구매 알림으로 깨어나는지 보는 단계 앞).
    func test_P4_photographerGoesBackground() throws {
        photographerApp.activate()
        XCTAssertTrue(photographerApp.wait(for: .runningForeground, timeout: 10))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(photographerApp.wait(for: .runningBackground, timeout: 10))
    }

    func test_P5_photographerEnds() throws {
        let app = photographerApp
        app.activate()
        let end = app.buttons["photographer.end"]
        XCTAssertTrue(end.waitForExistence(timeout: 20))
        end.tap()
        let confirm = app.sheets.buttons["촬영 종료"].firstMatch.exists ? app.sheets.buttons["촬영 종료"].firstMatch : app.buttons.matching(identifier: "촬영 종료").element(boundBy: 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["촬영이 끝났습니다. 고객이 산 사진과 미리 올리는 사진을 마저 올립니다."].waitForExistence(timeout: 20)
                      || app.navigationBars["십분스냅 작가"].waitForExistence(timeout: 10))
        attachScreenshot("P5 종료", app: app)
    }

    // MARK: - 고객

    /// 지도에서 작가를 골라 확정하고, 작가 앱이 받았다는 표시를 기다린다.
    func test_C1_customerConfirms() throws {
        let app = customerApp
        app.activate()
        allowSystemAlerts(seconds: 6)
        let marker = app.descendants(matching: .any)["marker.\(photographerName)"]
        // 지도 마커는 접근성 요소로 "이름, 이름" 같은 레이블만 남고 식별자는 지도 것으로 바뀐다.
        let labeled = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", photographerName)).firstMatch
        XCTAssertTrue(waitUntil(timeout: 60) { marker.exists || labeled.exists }, "지도에 작가가 보이지 않음")
        attachScreenshot("C1 지도", app: app)
        (marker.exists ? marker : labeled).tap()
        let confirm = app.buttons["customer.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "확정 버튼이 없음")
        confirm.tap()
        let started = Date()
        XCTAssertTrue(app.buttons["customer.start"].waitForExistence(timeout: 30), "티켓 화면으로 넘어가지 않음")
        XCTAssertTrue(app.staticTexts["작가 확인됨"].waitForExistence(timeout: 60), "작가 앱이 받았다는 표시가 없음")
        print("SBSN 작가 확인까지 \(String(format: "%.1f", Date().timeIntervalSince(started)))초")
        attachScreenshot("C1 매칭", app: app)
    }

    func test_C2_customerSendsMessage() throws {
        let app = customerApp
        app.activate()
        let field = app.descendants(matching: .any)["chat.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText(message)
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 15), "보낸 메시지가 보이지 않음")
        attachScreenshot("C2 채팅", app: app)
    }

    func test_C3_customerStarts() throws {
        let app = customerApp
        app.activate()
        let start = app.buttons["customer.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        attachScreenshot("C3 시작", app: app)
    }

    /// 사진 목록이 촬영 중 화면으로 바뀌고 미리보기가 몇 장 왔는지 기록한다.
    func test_C4_customerSeesPreviews() throws {
        let app = customerApp
        app.activate()
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo.cell.'"))
        XCTAssertTrue(waitUntil(timeout: 120) { cells.count > photoIndex }, "미리보기가 \(photoIndex + 1)장 이상 오지 않음")
        print("SBSN 고객 그리드 사진 \(cells.count)장")
        attachScreenshot("C4 미리보기", app: app)
    }

    /// `SBSN_PHOTO_INDEX`번째 사진을 열어 구매하고, 사진 앱에 저장될 때까지 기다린다.
    func test_C5_customerPurchases() throws {
        let app = customerApp
        app.activate()
        if app.navigationBars.buttons.element(boundBy: 0).exists, !app.descendants(matching: .any)["photo.cell.\(firstCellName(app) ?? "")"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo.cell.'"))
        XCTAssertTrue(waitUntil(timeout: 60) { cells.count > photoIndex })
        let cell = cells.element(boundBy: photoIndex)
        let fileName = cell.identifier.replacingOccurrences(of: "photo.cell.", with: "")
        cell.tap()
        let purchase = app.buttons["photo.purchase"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 15), "\(fileName) 구매 버튼이 없음")
        purchase.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == '구매'")).allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(confirm, "구매 확인 버튼이 없음")
        let purchasedAt = Date()
        confirm?.tap()
        print("SBSN 구매 \(fileName) \(ISO8601DateFormatter().string(from: purchasedAt))")
        waitForDelivery(app: app, fileName: fileName, since: purchasedAt)
    }

    /// 이미 산 사진의 상세를 열어 사진 앱 저장까지 기다린다(권한 창이 뜨면 허용).
    func test_C6_customerChecksDelivery() throws {
        let app = customerApp
        app.activate()
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo.cell.'"))
        XCTAssertTrue(waitUntil(timeout: 60) { cells.count > photoIndex })
        let cell = cells.element(boundBy: photoIndex)
        let fileName = cell.identifier.replacingOccurrences(of: "photo.cell.", with: "")
        cell.tap()
        waitForDelivery(app: app, fileName: fileName, since: Date())
    }

    private func waitForDelivery(app: XCUIApplication, fileName: String, since: Date) {
        let delivery = app.descendants(matching: .any)["photo.delivery"]
        // 사진 앱 권한 창은 구매가 기록된 뒤 뜬다. 기다리는 동안 창이 보이면 허용한다.
        XCTAssertTrue(waitUntil(timeout: 180) {
            if springboard.alerts.firstMatch.exists { allowSystemAlerts(seconds: 2) }
            return delivery.exists && delivery.label.contains("사진 앱에 저장됨")
        }, "사진 앱 저장까지 가지 않음: \(delivery.exists ? delivery.label : "상태 없음")")
        print("SBSN 사진 앱 저장 확인 \(fileName) \(String(format: "%.1f", Date().timeIntervalSince(since)))초")
        attachScreenshot("저장 \(fileName)", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// 촬영이 끝난 뒤: 안내가 보이고, 고화질본이 없는 사진(`SBSN_PHOTO_INDEX`)은 구매 버튼이 없어야 한다.
    func test_C7_customerAfterEnd() throws {
        let app = customerApp
        app.activate()
        XCTAssertTrue(app.staticTexts["촬영이 끝났습니다. 준비된 사진만 구매할 수 있습니다"].waitForExistence(timeout: 20), "종료 안내가 없음")
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo.cell.'"))
        XCTAssertTrue(waitUntil(timeout: 20) { cells.count > photoIndex })
        let cell = cells.element(boundBy: photoIndex)
        let fileName = cell.identifier.replacingOccurrences(of: "photo.cell.", with: "")
        cell.tap()
        XCTAssertTrue(app.navigationBars[fileName].waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        print("SBSN 종료 뒤 \(fileName) 구매 버튼 \(app.buttons["photo.purchase"].exists ? "있음" : "없음")")
        attachScreenshot("C7 종료 뒤 \(fileName)", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// 진단: 고객 앱 화면 구조를 출력한다.
    func test_C0_customerDumpsHierarchy() throws {
        let app = customerApp
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(12))
        print("SBSN 화면 구조\n" + app.debugDescription)
        attachScreenshot("C0", app: app)
    }

    // MARK: - 도구

    private func firstCellName(_ app: XCUIApplication) -> String? {
        let cell = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo.cell.'")).firstMatch
        return cell.exists ? cell.identifier.replacingOccurrences(of: "photo.cell.", with: "") : nil
    }

    /// 위치·알림·사진 권한 창이 뜨면 허용한다. 한국어·영어 문구를 모두 본다.
    private func allowSystemAlerts(seconds: TimeInterval) {
        let labels = ["앱을 사용하는 동안 허용", "Allow While Using App", "허용", "Allow", "전체 접근 허용", "Allow Full Access", "추가 허용"]
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 1) {
                // 정확한 문구가 없으면 "허용"이 들어가되 거부가 아닌 버튼(예: "사진 추가 허용")을 누른다.
                let fallback = alert.buttons.matching(NSPredicate(format: "(label CONTAINS '허용' AND NOT label CONTAINS '안 함') OR label BEGINSWITH 'Allow'")).firstMatch
                if let button = labels.lazy.map({ alert.buttons[$0] }).first(where: { $0.exists }) ?? (fallback.exists ? fallback : nil) {
                    print("SBSN 권한 허용: \(alert.label) → \(button.label)")
                    button.tap()
                    continue
                }
                print("SBSN 모르는 권한 창: \(alert.label) \(alert.buttons.allElementsBoundByIndex.map(\.label))")
                return
            }
        }
    }

    private func tapSwitch(_ toggle: XCUIElement) {
        // SwiftUI Toggle은 행 전체가 아니라 오른쪽 스위치를 눌러야 바뀐다.
        let knob = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        knob.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func clearText(in field: XCUIElement) {
        guard let current = field.value as? String, !current.isEmpty, current != field.placeholderValue else { return }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    }

    private func printAddresses(_ app: XCUIApplication) {
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '호스트'"))
        for row in rows.allElementsBoundByIndex {
            print("SBSN FTP \(row.label) \(String(describing: row.value))")
        }
        let received = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '받은 '")).firstMatch
        if received.exists { print("SBSN \(received.label)") }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return condition()
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
