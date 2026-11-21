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
