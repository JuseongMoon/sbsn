import XCTest

/// 작가 앱 "메타데이터 경로 시험"을 시뮬레이터에서 돌린다(D037 확인용, 손으로 실행).
///
/// 먼저 시뮬레이터 사진 앱에 시험 사진을 넣는다(`xcrun simctl addmedia`). 경로마다 선택기를 열어 사진을 전부 고르고 추가한다.
/// 받은 파일은 작가 앱 `Documents/MetaProbe/<경로>/`에 남는다. 시험 사진에 위치가 있을 수 있으니 기록·캡처에 좌표를 남기지 않는다.
@MainActor
final class MetadataProbeUITests: XCTestCase {
    let photographerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsnPhotographer")

    func testPickEveryRoute() throws {
        let app = photographerApp
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 30))
        app.tabBars.buttons["마이"].tap()
        tapID("my.developer", app)
        tapID("dev.metadataProbe", app)
        for route in ["probe.current", "probe.compatible", "probe.provider"] {
            tapID(route, app)
            pickEveryPhoto(app, route: route)
        }
        sleep(5)
        let log = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.contains("/") || $0.contains("실패") }
        print("PROBE-LOG", log.joined(separator: " | "))
    }

    /// 선택기 위치 옵션 확인(I008): `.current` 선택기에서 사진 두 장을 고르고 "선택된 항목 → 옵션"의 위치 스위치를 정한 뒤 추가한다.
    /// 받은 파일은 `Documents/MetaProbe/current/`에 남는다. 위치를 끄려면 `TEST_RUNNER_SBSN_PICKER_LOCATION=off`로 실행한다.
    /// 시험 사진은 가짜 좌표가 든 합성 사진을 쓴다(`xcrun simctl addmedia`, 가장 최근 두 장).
    func testPickerLocationOption() throws {
        let includesLocation = ProcessInfo.processInfo.environment["SBSN_PICKER_LOCATION"] != "off"
        print("PROBE-MODE 위치 \(includesLocation ? "켬" : "끔")")
        let app = photographerApp
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 30))
        app.tabBars.buttons["마이"].tap()
        tapID("my.developer", app)
        tapID("dev.metadataProbe", app)
        app.buttons["받은 파일 지우기"].firstMatch.tap()
        tapID("probe.current", app)
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 10), "선택기가 열리지 않음")
        sleep(2)
        // 위 안내 배너의 사진 앱 아이콘도 이미지로 잡히므로 큰 칸만 누른다.
        let cells = app.scrollViews.otherElements.images.allElementsBoundByIndex.filter { $0.frame.width > 80 }
        for cell in cells.prefix(2) {
            cell.tap()
            sleep(1)
        }
        // 아래 가운데 "선택된 항목 표시(n개) · 위치가 포함됨" → 왼쪽 아래 "옵션" → 포함: 위치 스위치
        let selected = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "위치")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5), "선택된 항목 단추 없음")
        print("PROBE-PICKER", selected.label)
        selected.tap()
        let options = app.buttons["옵션"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5), "옵션 단추 없음")
        options.tap()
        let location = app.switches["위치"].firstMatch
        XCTAssertTrue(location.waitForExistence(timeout: 5), "위치 스위치 없음")
        print("PROBE-OPTIONS 위치 기본값", location.value as? String ?? "-")
        if (location.value as? String == "1") != includesLocation {
            // 행 가운데를 누르면 바뀌지 않는다. 오른쪽 스위치를 누른다.
            location.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            sleep(1)
        }
        attach("옵션 \(includesLocation ? "위치 켬" : "위치 끔")", app)
        print("PROBE-OPTIONS 위치", location.value as? String ?? "-")
        // 옵션 완료 → 선택된 항목 완료 → 선택기 완료
        for _ in 0..<4 where !app.buttons["probe.current"].isHittable {
            let done = app.buttons["완료"].firstMatch
            guard done.waitForExistence(timeout: 3) else { break }
            done.tap()
            sleep(1)
        }
        sleep(5)
        attach("받은 뒤", app)
        print("PROBE-LOG", app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.contains("/") }.joined(separator: " | "))
    }

    /// 선택기는 다른 프로세스에서 그려지지만 앱 계층에 사진 칸으로 보인다. 사진 칸을 모두 누르고 "추가"를 누른다.
    private func pickEveryPhoto(_ app: XCUIApplication, route: String) {
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "\(route): 선택기가 열리지 않음")
        sleep(2)
        let cells = app.scrollViews.otherElements.images
        let count = cells.count
        print("PROBE-PICKER", route, "칸", count)
        if count == 0 {
            print("PROBE-TREE", app.debugDescription.prefix(6000))
        }
        for index in 0..<count {
            cells.element(boundBy: index).tap()
        }
        let add = app.buttons.matching(NSPredicate(format: "label IN %@", ["추가", "Add", "완료", "Done"])).firstMatch
        if add.waitForExistence(timeout: 5) {
            add.tap()
        } else {
            print("PROBE-TREE", app.debugDescription.prefix(6000))
            XCTFail("\(route): 추가 버튼 없음")
        }
        sleep(3)
    }

    /// 고객 앱 "사진 앱 저장 시험": `Documents/MetaProbeIn/`의 JPEG를 실제 저장 경로로 넣고 원본 리소스를 다시 꺼낸다.
    /// 먼저 파일을 고객 앱 컨테이너에 넣고, 사진·위치 권한을 미리 허용한다(`xcrun simctl privacy … grant`).
    func testSaveRoundTrip() throws {
        let app = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsn")
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 30))
        app.tabBars.buttons["마이"].tap()
        tapID("my.developer", app)
        let link = app.buttons["사진 앱 저장 시험"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        tapID("probe.saveRoundTrip", app)
        XCTAssertTrue(app.staticTexts["끝"].waitForExistence(timeout: 120), "저장 시험이 끝나지 않음")
    }

    /// 작가 앱 "고르기 화면 시험(서버 없음)": 앱 `Documents/TestPhotos/`의 사진을 넣고 검사·렌더 결과와 화면 상태를 캡처한다.
    /// 가짜 티켓이라 업로드는 실패로 끝난다(규칙이 거부). 렌더한 파일은 앱 `Application Support/Tickets/debug-*/`에 남는다.
    func testDebugGallery() throws {
        let app = photographerApp
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 30))
        app.tabBars.buttons["마이"].tap()
        tapID("my.developer", app)
        tapID("dev.debugGallery", app)
        XCTAssertTrue(app.navigationBars["사진 고르기"].waitForExistence(timeout: 10))
        attach("고르기 빈 화면", app)
        tapID("gallery.addTestPhotos", app)
        sleep(20)
        attach("고른 뒤", app)
        app.swipeUp()
        attach("고른 뒤 아래", app)
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        print("PROBE-GALLERY", labels.joined(separator: " | "))
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 목록 아래쪽에 있으면 보일 때까지 올려서 누른다.
    private func tapID(_ id: String, _ app: XCUIApplication) {
        let element = app.descendants(matching: .any)[id].firstMatch
        var swipes = 0
        while !(element.exists && element.isHittable), swipes < 8 {
            if swipes == 0, element.waitForExistence(timeout: 5), element.isHittable { break }
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists, "\(id)를 찾지 못함")
        element.tap()
    }
}
