import XCTest

/// 실기기 두 대로 선별 전달 사이클(D036)을 한 단계씩 돌리는 드라이버. 맥에서 단계마다 테스트 하나를 골라 실행한다.
///
/// 사진은 작가 앱 `Documents/TestPhotos/`에 미리 넣어 두고(`xcrun devicectl device copy to`), 고르기 화면의 개발용
/// "시험 사진 가져오기"로 넣는다. 사진 선택기는 다른 프로세스라 UI 테스트로 누르기 어렵다.
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
        let app = activatePhotographer()
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
        let app = activatePhotographer()
        let start = app.buttons["photographer.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 30), "티켓 화면의 시작 버튼이 없음")
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 20), "고객 메시지가 보이지 않음")
        attachScreenshot("P2 만나기", app: app)
        XCTAssertTrue(waitUntil(timeout: 10) { start.isEnabled })
        start.tap()
        let end = app.buttons["photographer.end"]
        XCTAssertTrue(end.waitForExistence(timeout: 40), "촬영 화면으로 넘어가지 않음(고객이 시작했는지 확인)")
        attachScreenshot("P2 촬영 중", app: app)
    }

    /// 촬영이 끝난 뒤 고르기 화면에서 시험 사진을 넣고, 모두 올라갈 때까지 기다린다(`SBSN_UPLOAD_TIMEOUT`초, 기본 600).
    func test_P3_photographerImportsTestPhotos() throws {
        let app = activatePhotographer()
        openPendingGalleryIfNeeded(app)
        let add = app.buttons["gallery.addTestPhotos"]
        XCTAssertTrue(add.waitForExistence(timeout: 20), "시험 사진 가져오기 버튼이 없음(디버그 빌드인지 확인)")
        add.tap()
        let started = Date()
        print("SBSN 시험 사진 넣음 \(started.ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
        attachScreenshot("P3 고른 사진", app: app)
        let timeout = TimeInterval(ProcessInfo.processInfo.environment["SBSN_UPLOAD_TIMEOUT"] ?? "") ?? 600
        let header = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '고른 사진'")).firstMatch
        XCTAssertTrue(waitUntil(timeout: timeout) {
            guard header.exists, let counts = Self.selectionCounts(header.label) else { return false }
            return counts.selected > 0 && counts.selected == counts.uploaded
        }, "모두 올라가지 않음: \(header.exists ? header.label : "-")")
        print("SBSN 모두 올라감 \(header.label) \(String(format: "%.1f", Date().timeIntervalSince(started)))초")
        attachScreenshot("P3 올라감", app: app)
    }

    /// "고객에게 공개"(또는 공개 예약)를 누르고 공개될 때까지 기다린다.
    func test_P14_photographerPublishes() throws {
        let app = activatePhotographer()
        openPendingGalleryIfNeeded(app)
        let publish = app.buttons["gallery.publish"]
        for _ in 0..<6 where !(publish.exists && publish.isHittable) { app.swipeUp() }
        XCTAssertTrue(publish.waitForExistence(timeout: 20), "공개 버튼이 없음")
        XCTAssertTrue(waitUntil(timeout: 10) { publish.isEnabled }, "공개 버튼이 꺼져 있음(5~8장인지 확인)")
        publish.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label IN %@", ["공개", "다 올라가면 공개"])).allElementsBoundByIndex.last { $0.isHittable }
        try XCTUnwrap(confirm, "공개 확인 버튼이 없음").tap()
        let tappedAt = Date()
        // 공개가 끝나면 세션이 공개 대기에서 빼고 화면이 공개 현황으로 바뀐다.
        XCTAssertTrue(app.navigationBars["공개한 촬영"].waitForExistence(timeout: 300), "공개되지 않음")
        print("SBSN 공개됨 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true))) 누르고 \(String(format: "%.1f", Date().timeIntervalSince(tappedAt)))초")
        attachScreenshot("P14 공개", app: app)
    }

    /// 작가 앱을 백그라운드로 보낸다(구매 알림으로 깨어나는지 보는 단계 앞).
    func test_P4_photographerGoesBackground() throws {
        photographerApp.activate()
        XCTAssertTrue(photographerApp.wait(for: .runningForeground, timeout: 10))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(photographerApp.wait(for: .runningBackground, timeout: 10))
    }

    func test_P5_photographerEnds() throws {
        let app = activatePhotographer()
        let end = app.buttons["photographer.end"]
        XCTAssertTrue(end.waitForExistence(timeout: 20))
        end.tap()
        let confirm = app.sheets.buttons["촬영 종료"].firstMatch.exists ? app.sheets.buttons["촬영 종료"].firstMatch : app.buttons.matching(identifier: "촬영 종료").element(boundBy: 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        print("SBSN 작가 종료 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
        XCTAssertTrue(app.navigationBars["사진 고르기"].waitForExistence(timeout: 30), "사진 고르기 화면으로 넘어가지 않음")
        attachScreenshot("P5 종료", app: app)
    }

    /// 작가 폰에 `SBSN_BANNER_TEXT`가 든 알림 배너가 뜨기를 기다려 배너만 찍는다(홈 화면·다른 앱 알림은 찍지 않는다).
    /// 고객 단계보다 먼저 띄워 두고, 고객 쪽에서 확정·채팅·구매를 한다.
    func test_P6_photographerCapturesBanner() throws {
        let environment = ProcessInfo.processInfo.environment
        let text = try XCTUnwrap(environment["SBSN_BANNER_TEXT"])
        let timeout = TimeInterval(environment["SBSN_BANNER_TIMEOUT"] ?? "") ?? 180
        let banner = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        print("SBSN 배너 기다림 \(text)")
        XCTAssertTrue(banner.waitForExistence(timeout: timeout), "배너가 뜨지 않음: \(text)")
        print("SBSN 배너 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true))) \(banner.label)")
        let attachment = XCTAttachment(screenshot: banner.screenshot())
        attachment.name = "P6 배너"
        attachment.lifetime = .keepAlways
        add(attachment)
        // 배너를 탭해 앱이 열리는지까지 볼 때(작가 앱을 쓸어 올려 종료한 뒤 이어 가기): photographer 또는 customer
        if let target = environment["SBSN_BANNER_TAP"] {
            banner.tap()
            let app = target == "customer" ? customerApp : photographerApp
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "배너를 탭했는데 앱이 열리지 않음")
            print("SBSN 배너 탭 → 앱 열림 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
            attachScreenshot("배너로 연 화면", app: app)
        }
    }

    /// 작가 앱을 앱 전환기에서 쓸어 올려 종료한다(사용자 강제 종료). 이 뒤에는 iOS가 알림으로 앱을 깨우지 않는다.
    func test_P9_photographerForceQuits() throws {
        let app = activatePhotographer()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        // 화면 아래 가장자리에서 천천히 끌어 올려 멈추면 앱 전환기가 열린다.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.998))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)),
                   withVelocity: .slow, thenHoldForDuration: 1.0)
        let card = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR identifier == %@", "십분스냅 작가", "com.ScienceFiction.sbsnPhotographer")).firstMatch
        guard card.waitForExistence(timeout: 5) else {
            print("SBSN 앱 전환기 구조\n" + springboard.debugDescription)
            XCTFail("앱 전환기에서 작가 앱 카드를 찾지 못함")
            return
        }
        card.swipeUp(velocity: .fast)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "작가 앱이 종료되지 않음")
        print("SBSN 작가 앱 쓸어 올려 종료 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
        XCUIDevice.shared.press(.home)
    }

    /// 작가가 채팅을 보낸다(고객 알림 확인용). 촬영 중이면 채팅 시트를 먼저 연다.
    func test_P11_photographerSendsMessage() throws {
        let app = activatePhotographer()
        let field = app.descendants(matching: .any)["chat.field"]
        if !field.waitForExistence(timeout: 5) {
            app.buttons["채팅"].tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText(message)
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 15), "보낸 메시지가 보이지 않음")
        print("SBSN 작가 메시지 보냄 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
    }

    /// 작가가 시작 전에 촬영을 취소한다(고객 알림 확인용).
    func test_P12_photographerCancels() throws {
        let app = activatePhotographer()
        let cancel = app.buttons["취소"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "취소 버튼이 없음")
        cancel.tap()
        let confirm = app.buttons["촬영 취소"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "취소 확인 버튼이 없음")
        confirm.tap()
        print("SBSN 작가 취소 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
    }

    /// 지금 화면(만나기·촬영)의 "…" 메뉴를 열어 캡처하고, 다른 탭에 다녀와 화면이 이어지는지 본다.
    /// 만나기 화면이면 `SBSN_MESSAGE`가 다시 보이는지(채팅 리스너가 다시 붙는지) 확인한다.
    func test_P13_photographerMenusAndTabs() throws {
        let app = activatePhotographer()
        attachScreenshot("P13 지금 화면", app: app)
        let more = app.buttons["photographer.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 20), "\"…\" 메뉴가 없음")
        more.tap()
        attachScreenshot("P13 … 메뉴", app: app)
        dismissMenu(app)
        let isMeeting = app.buttons["photographer.start"].exists
        app.tabBars.buttons["내역"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(5))
        attachScreenshot("P13 내역 탭", app: app)
        app.tabBars.buttons["촬영"].tap()
        if isMeeting {
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 15), "탭 복귀 뒤 채팅이 다시 보이지 않음")
        } else {
            XCTAssertTrue(app.buttons["photographer.end"].waitForExistence(timeout: 15), "탭 복귀 뒤 촬영 화면이 아님")
        }
        attachScreenshot("P13 탭 복귀", app: app)
    }

    // MARK: - 고객

    /// 지금 화면을 캡처하고(만나기면 "…" 메뉴도) 다른 탭(`SBSN_STAY_TAB`, 기본 마이)에 `SBSN_STAY_SECONDS`초(기본 200) 머문 뒤
    /// 촬영 탭으로 돌아온다. 그동안 맥에서 Firestore의 고객 위치 갱신 시각·티켓 상태를 본다(탭을 옮겨도 끊기지 않는지).
    func test_C17_customerStaysOnOtherTab() throws {
        let environment = ProcessInfo.processInfo.environment
        let tab = environment["SBSN_STAY_TAB"] ?? "마이"
        let seconds = TimeInterval(environment["SBSN_STAY_SECONDS"] ?? "") ?? 200
        let app = activateCustomer()
        attachScreenshot("C17 촬영 화면", app: app)
        let more = app.buttons["customer.meetup.more"]
        if more.waitForExistence(timeout: 3) {
            more.tap()
            attachScreenshot("C17 만나기 … 메뉴", app: app)
            dismissMenu(app)
        }
        app.tabBars.buttons[tab].tap()
        print("SBSN 다른 탭(\(tab))으로 감 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
        attachScreenshot("C17 \(tab) 탭", app: app)
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        app.tabBars.buttons["촬영"].tap()
        print("SBSN 촬영 탭으로 돌아옴 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
        attachScreenshot("C17 촬영 탭 복귀", app: app)
    }

    /// 사진을 산 뒤 곧바로 다른 탭(마이)으로 가서 `SBSN_STAY_SECONDS`초(기본 60) 머문다. 그동안 사진 앱 저장(`deliveredAt`)이
    /// 이어지는지 맥에서 보고, 돌아와 상세 화면의 전달 표시를 확인한다.
    func test_C18_customerPurchasesThenVisitsOtherTab() throws {
        let seconds = TimeInterval(ProcessInfo.processInfo.environment["SBSN_STAY_SECONDS"] ?? "") ?? 60
        let app = customerApp
        let (fileName, purchasedAt) = try purchasePhoto(app)
        app.tabBars.buttons["마이"].tap()
        print("SBSN \(fileName) 구매 뒤 마이 탭으로 감 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        app.tabBars.buttons["촬영"].tap()
        waitForDelivery(app: app, fileName: fileName, since: purchasedAt)
    }

    /// 지도에서 작가를 골라 확정하고, 작가 앱이 받았다는 표시를 기다린다.
    func test_C1_customerConfirms() throws {
        let app = activateCustomer()
        allowSystemAlerts(seconds: 6)
        selectPhotographerOnMap(app)
        confirmSelectedPhotographer(app)
        let started = Date()
        XCTAssertTrue(app.buttons["customer.start"].waitForExistence(timeout: 30), "티켓 화면으로 넘어가지 않음")
        XCTAssertTrue(app.staticTexts["작가 확인됨"].waitForExistence(timeout: 60), "작가 앱이 받았다는 표시가 없음")
        print("SBSN 작가 확인까지 \(String(format: "%.1f", Date().timeIntervalSince(started)))초")
        attachScreenshot("C1 매칭", app: app)
    }

    /// 진단: 지도에서 작가를 골라 카드만 띄운다(확정하지 않음). 마커·카드의 시간 표시 언어를 확인할 때 쓴다.
    func test_C9_customerPreviewsPhotographer() throws {
        let app = activateCustomer()
        selectPhotographerOnMap(app)
        XCTAssertTrue(app.buttons["customer.review"].waitForExistence(timeout: 10), "작가 카드가 없음")
        attachScreenshot("C9 작가 카드", app: app)
    }

    func test_C2_customerSendsMessage() throws {
        let app = activateCustomer()
        let field = app.descendants(matching: .any)["chat.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText(message)
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 15), "보낸 메시지가 보이지 않음")
        attachScreenshot("C2 채팅", app: app)
    }

    func test_C3_customerStarts() throws {
        let app = activateCustomer()
        let start = app.buttons["customer.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        let proceed = app.buttons["customer.payment.continue"]
        XCTAssertTrue(proceed.waitForExistence(timeout: 10), "촬영료 결제 자리 화면이 뜨지 않음")
        attachScreenshot("C3 촬영료 결제 자리", app: app)
        proceed.tap()
        attachScreenshot("C3 시작", app: app)
    }

    /// 둘 다 시작하기 전에 고객이 촬영을 취소한다.
    func test_C8_customerCancels() throws {
        let app = activateCustomer()
        let cancel = app.buttons["취소"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 20), "취소 버튼이 없음")
        cancel.tap()
        let confirm = app.buttons["촬영 취소"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "취소 확인 버튼이 없음")
        confirm.tap()
        print("SBSN 고객 취소 \(ISO8601DateFormatter().string(from: Date()))")
        XCTAssertTrue(app.staticTexts["촬영을 취소했습니다."].waitForExistence(timeout: 20), "취소 화면으로 넘어가지 않음")
        attachScreenshot("C8 취소", app: app)
    }

    /// 공개된 갤러리에 사진이 몇 장 보이는지 기록한다(공개 전이면 `SBSN_PUBLISH_TIMEOUT`초, 기본 600 기다린다).
    func test_C4_customerSeesPreviews() throws {
        let app = activateCustomer()
        let timeout = TimeInterval(ProcessInfo.processInfo.environment["SBSN_PUBLISH_TIMEOUT"] ?? "") ?? 600
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo.cell.'"))
        XCTAssertTrue(waitUntil(timeout: timeout) { cells.count > photoIndex }, "갤러리에 사진이 \(photoIndex + 1)장 이상 보이지 않음")
        print("SBSN 고객 갤러리 보임 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true))) 사진 \(cells.count)장")
        attachScreenshot("C4 갤러리", app: app)
    }

    /// `SBSN_PHOTO_INDEX`번째 사진을 열어 구매하고, 사진 앱에 저장될 때까지 기다린다.
    func test_C5_customerPurchases() throws {
        let app = customerApp
        let (fileName, purchasedAt) = try purchasePhoto(app)
        waitForDelivery(app: app, fileName: fileName, since: purchasedAt)
    }

    /// `SBSN_PHOTO_INDEX`번째 사진의 상세를 열어 구매를 확인까지 누른다.
    private func purchasePhoto(_ app: XCUIApplication) throws -> (fileName: String, purchasedAt: Date) {
        app.activate()
        openShootTab(app)
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
        attachScreenshot("사진 상세", app: app)
        purchase.tap()
        let confirm = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "label == '구매'")).allElementsBoundByIndex.last { $0.isHittable },
                                    "구매 확인 버튼이 없음")
        let purchasedAt = Date()
        confirm.tap()
        print("SBSN 구매 \(fileName) \(ISO8601DateFormatter().string(from: purchasedAt))")
        return (fileName, purchasedAt)
    }

    /// 이미 산 사진의 상세를 열어 사진 앱 저장까지 기다린다(권한 창이 뜨면 허용).
    func test_C6_customerChecksDelivery() throws {
        let app = activateCustomer()
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

    /// 촬영이 끝난 뒤 공개 전: "작가가 사진을 고르는 중" 안내가 보이고 사진은 없어야 한다(D038, 공개 전에는 아무것도 못 본다).
    func test_C7_customerAwaitsGallery() throws {
        let app = activateCustomer()
        XCTAssertTrue(app.descendants(matching: .any)["gallery.awaiting"].waitForExistence(timeout: 30), "고르는 중 안내가 없음")
        let cells = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'photo.cell.'"))
        XCTAssertEqual(cells.count, 0, "공개 전인데 사진이 보임")
        print("SBSN 고객 고르는 중 확인 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
        attachScreenshot("C7 고르는 중", app: app)
    }

    /// 10분 넘게 갱신이 없는 작가가 지도에서 빠지는지 본다. 관리자가 갱신 시각만 다른 공개 상태 셋을 미리 넣어 둔다.
    /// FRESH(방금)는 계속 보이고, STALE(곧 10분)은 보이다가 사라지고, GONE(이미 10분 넘음)은 처음부터 없어야 한다.
    func test_C10_customerSeesStalePhotographerHidden() throws {
        let environment = ProcessInfo.processInfo.environment
        let fresh = try XCTUnwrap(environment["SBSN_FRESH_NAME"])
        let stale = try XCTUnwrap(environment["SBSN_STALE_NAME"])
        let gone = try XCTUnwrap(environment["SBSN_GONE_NAME"])
        let app = customerApp
        // 지도는 작가가 처음 보일 때 한 번만 영역을 맞추므로, 새로 띄워 시험 작가들이 화면 안에 오게 한다.
        app.terminate()
        app.activate()
        for title in ["새 촬영 찾기", "지도로 돌아가기"] where app.buttons[title].waitForExistence(timeout: 3) {
            app.buttons[title].tap()
        }
        func marker(_ name: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "marker.\(name)", name)).firstMatch
        }
        XCTAssertTrue(waitUntil(timeout: 60) { marker(fresh).exists && marker(stale).exists }, "시험 작가가 지도에 보이지 않음")
        print("SBSN 둘 다 보임 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
        XCTAssertFalse(marker(gone).exists, "이미 10분 넘은 작가가 보임")
        attachScreenshot("C10 숨기기 전", app: app)

        XCTAssertTrue(waitUntil(timeout: 180) { !marker(stale).exists }, "오래된 작가가 사라지지 않음")
        print("SBSN 오래된 작가 사라짐 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
        XCTAssertTrue(marker(fresh).exists, "방금 갱신한 작가까지 사라짐")
        XCTAssertFalse(marker(gone).exists, "이미 10분 넘은 작가가 보임")
        attachScreenshot("C10 숨긴 뒤", app: app)
    }

    /// 사용자가 지도를 움직인 뒤에는 작가가 새로 보여도 지도를 다시 맞추지 않는지 본다.
    /// 지도를 옮긴 뒤 45초 안에 관리자가 멀리 있는 작가(`SBSN_LATE_NAME`)를 넣는다. 그 작가는 화면 밖에 남아야 한다.
    func test_C11_customerMovedMapStaysPut() throws {
        let late = try XCTUnwrap(ProcessInfo.processInfo.environment["SBSN_LATE_NAME"])
        let app = customerApp
        app.terminate()
        app.activate()
        let marker = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "marker.\(photographerName)", photographerName)).firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 60), "지도에 작가가 보이지 않음")
        let map = app.maps.firstMatch
        // 마커는 가운데에 있으므로 아래쪽을 끌어 마커를 누르지 않게 한다.
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.75))
            .press(forDuration: 0.1, thenDragTo: map.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.75)))
        print("SBSN 지도 옮김 \(Date().ISO8601Format(.iso8601.time(includingFractionalSeconds: true)))")
        attachScreenshot("C11 옮긴 뒤", app: app)
        RunLoop.current.run(until: Date().addingTimeInterval(45))
        attachScreenshot("C11 45초 뒤", app: app)
        let lateMarker = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "marker.\(late)", late)).firstMatch
        XCTAssertFalse(lateMarker.exists, "옮긴 지도를 새 작가에 맞춰 다시 움직임")
        XCTAssertTrue(marker.exists, "원래 작가가 화면에서 사라짐")
    }

    /// 작가 앱이 응답하지 않는 매칭에서 2분 뒤 "작가 응답 없음" 안내가 뜨는지 본다. 관리자가 넣은 앱 없는 시험 작가를 확정한다.
    /// 처음 티켓 화면에서 알림 권한 창이 뜨면 허용한다.
    func test_C12_customerSeesSilentPhotographer() throws {
        let app = activateCustomer()
        allowSystemAlerts(seconds: 3)
        selectPhotographerOnMap(app)
        confirmSelectedPhotographer(app)
        let started = Date()
        XCTAssertTrue(app.buttons["customer.start"].waitForExistence(timeout: 30), "티켓 화면으로 넘어가지 않음")
        allowSystemAlerts(seconds: 5)
        let notice = app.descendants(matching: .any)["ticket.photographerSilence"]
        XCTAssertTrue(notice.waitForExistence(timeout: 210), "작가 응답 없음 안내가 뜨지 않음")
        print("SBSN 응답 없음 안내 확정 \(Int(Date().timeIntervalSince(started)))초 뒤: \(notice.label)")
        attachScreenshot("C12 응답 없음", app: app)
    }

    /// 지도에서 작가를 골라 확정만 하고 티켓 화면이 뜨면 끝낸다(작가 앱 응답을 기다리지 않는다).
    func test_C14_customerConfirmsOnly() throws {
        let app = activateCustomer()
        selectPhotographerOnMap(app)
        confirmSelectedPhotographer(app)
        XCTAssertTrue(app.buttons["customer.start"].waitForExistence(timeout: 30), "티켓 화면으로 넘어가지 않음")
        print("SBSN 확정 \(app.navigationBars.firstMatch.identifier)")
    }

    /// 고객 앱을 백그라운드로 보낸다(고객 알림 배너를 보는 단계 앞).
    func test_C13_customerGoesBackground() throws {
        customerApp.activate()
        XCTAssertTrue(customerApp.wait(for: .runningForeground, timeout: 10))
        XCUIDevice.shared.press(.home)
        // 고객 앱은 백그라운드 실행 모드가 없어 곧바로 일시 정지 상태가 되기도 한다.
        XCTAssertTrue(waitUntil(timeout: 10) { [.runningBackground, .runningBackgroundSuspended].contains(customerApp.state) },
                      "고객 앱 상태: \(customerApp.state.rawValue)")
    }

    /// 진단: 고객 앱 화면 구조를 출력한다.
    func test_C0_customerDumpsHierarchy() throws {
        let app = activateCustomer()
        print("SBSN 기기 선호 언어 \(Locale.preferredLanguages), 실행기 언어 \(Locale.current.identifier)")
        RunLoop.current.run(until: Date().addingTimeInterval(12))
        print("SBSN 화면 구조\n" + app.debugDescription)
        attachScreenshot("C0", app: app)
    }

    // MARK: - 도구

    /// 앱을 앞으로 가져와 "촬영" 탭을 연다. 다른 탭에 두고 나갔어도 단계가 같은 화면에서 시작하게 한다.
    private func activateCustomer() -> XCUIApplication {
        customerApp.activate()
        openShootTab(customerApp)
        return customerApp
    }

    private func activatePhotographer() -> XCUIApplication {
        photographerApp.activate()
        openShootTab(photographerApp)
        return photographerApp
    }

    /// 열린 메뉴를 닫는다(화면 위쪽 빈 곳을 누름).
    private func dismissMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    private func openShootTab(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["촬영"]
        if tab.waitForExistence(timeout: 5), !tab.isSelected {
            tab.tap()
        }
    }

    /// 작가 카드의 "이 작가와 촬영하기"로 가격·조건 확인 자리 화면을 열고, 그 화면의 확정 버튼을 누른다.
    private func confirmSelectedPhotographer(_ app: XCUIApplication) {
        let review = app.buttons["customer.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10), "\"이 작가와 촬영하기\" 버튼이 없음")
        review.tap()
        let confirm = app.buttons["customer.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "가격·조건 확인 화면의 확정 버튼이 없음")
        attachScreenshot("가격·조건 확인", app: app)
        confirm.tap()
    }

    /// 지난 촬영 화면(끝남·취소)에 남아 있으면 지도로 돌아가 작가 마커를 누른다.
    private func selectPhotographerOnMap(_ app: XCUIApplication) {
        // 앱을 막 앞으로 가져왔으면 화면이 그려지기 전이라 버튼을 잠깐 기다린다.
        let back = app.buttons.matching(NSPredicate(format: "label IN %@", ["새 촬영 찾기", "지도로 돌아가기"])).firstMatch
        if back.waitForExistence(timeout: 4) {
            back.tap()
        }
        let marker = app.descendants(matching: .any)["marker.\(photographerName)"]
        // 지도 마커는 접근성 요소로 "이름, 이름" 같은 레이블만 남고 식별자는 지도 것으로 바뀐다.
        let labeled = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", photographerName)).firstMatch
        XCTAssertTrue(waitUntil(timeout: 60) { marker.exists || labeled.exists }, "지도에 작가가 보이지 않음")
        attachScreenshot("지도", app: app)
        (marker.exists ? marker : labeled).tap()
    }

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

    /// 촬영 탭 홈에 있으면 맨 위 공개 대기 촬영을 연다(이미 고르기 화면이면 그대로).
    private func openPendingGalleryIfNeeded(_ app: XCUIApplication) {
        guard !app.navigationBars["사진 고르기"].waitForExistence(timeout: 3) else { return }
        let pending = app.descendants(matching: .any)["home.pendingGallery"].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 15), "공개 대기 촬영이 없음")
        pending.tap()
        XCTAssertTrue(app.navigationBars["사진 고르기"].waitForExistence(timeout: 10))
    }

    /// "고른 사진 6장 · 올라감 4장"에서 두 수를 꺼낸다.
    nonisolated static func selectionCounts(_ label: String) -> (selected: Int, uploaded: Int)? {
        let numbers = label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        return (numbers[0], numbers[1])
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
