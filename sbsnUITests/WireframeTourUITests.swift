import XCTest

/// 두 앱의 탭·메뉴와 예시 화면(D032, 고객 19·작가 18)과 하위 화면을 차례로 열어 캡처한다(시뮬레이터).
///
///   xcodebuild test -scheme sbsn -destination 'platform=iOS Simulator,id=<기기>' \
///     -only-testing:sbsnUITests/WireframeTourUITests
///
/// 작가 앱은 미리 설치해 둔다. 지도·탭 목록에서 닿는 예시 화면은 그 경로로 열고, 티켓이 있어야 닿는 화면
/// (촬영 안내, 안전·긴급, 추천 순서, 선택 바구니, 리뷰, 고객 브리프, 타이머, 연결 가이드, 검수, 채팅 신고·차단)은
/// 마이 > 개발 > "예시 화면 전체"로 연다. 서버에는 쓰지 않는다: 확정·촬영 가능은 누르지 않는다.
/// `TEST_RUNNER_SBSN_SHOT_DIR`을 주면 캡처를 그 폴더에 PNG로도 남긴다.
@MainActor
final class WireframeTourUITests: XCTestCase {
    let customerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsn")
    let photographerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsnPhotographer")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    /// 연 예시 화면 id(뿌리 `sample.<id>`)
    private var opened: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func test_customerTour() throws {
        let app = customerApp
        app.launch()
        dismissAlerts()
        XCTAssertTrue(app.tabBars.buttons["촬영"].waitForExistence(timeout: 30), "탭 바가 없음(로그인 확인)")
        shot("고객-촬영-지도", app)

        // 촬영 탭: C1 작가 목록 → C3 프로필, C2 조건, C9 이벤트
        app.buttons["목록"].tap()
        expectSample("photographerList", app, shot: "고객-C01-작가목록")
        tapText("하린 작가", app)
        expectSample("photographerProfile", app, shot: "고객-C03-프로필")
        back(app)
        app.buttons["지도"].tap()
        openPlanned("conditions", app, shot: "고객-C02-촬영조건")
        back(app)
        openPlanned("events", app, shot: "고객-C09-이벤트-프로모션")
        app.buttons["쿠폰"].tap()
        shot("고객-C09-이벤트-쿠폰", app)
        app.buttons["촬영지 가이드"].tap()
        tapText("경복궁 동문 앞", app)
        expectSample("guidePlace", app, shot: "고객-C09-촬영지")
        back(app)
        back(app)

        // 내 사진 탭: C10~C13
        app.tabBars.buttons["내 사진"].tap()
        shot("고객-내사진", app)
        openPlanned("album", app, shot: "고객-C10-앨범")
        tapText("서촌 · 하린 작가", app)
        expectSample("albumDetail", app, shot: "고객-C10-앨범상세")
        back(app)
        back(app)
        openPlanned("orders", app, shot: "고객-C11-주문")
        tapText("촬영료 15,000원", app)
        expectSample("orderDetail", app, shot: "고객-C11-주문상세")
        tapText("영수증 보기", app)
        expectSample("receipt", app, shot: "고객-C11-영수증")
        back(app)
        back(app)
        back(app)
        openPlanned("retouch", app, shot: "고객-C12-전문보정")
        tapID("sample.retouchRequestLink", app)
        expectSample("retouchRequest", app, shot: "고객-C12-새요청")
        back(app)
        back(app)
        openPlanned("shareAndPrint", app, shot: "고객-C13-공유인화")
        back(app)

        // 마이 탭: C14~C19, C9
        app.tabBars.buttons["마이"].tap()
        shot("고객-마이", app)
        for (id, name) in [("profile", "C14-프로필언어"), ("accountLink", "C15-계정연결"), ("help", "C16-도움말")] {
            openPlanned(id, app, shot: "고객-\(name)")
            back(app)
        }
        openPlanned("inquiry", app, shot: "고객-C17-문의신고")
        tapText("사진 한 장이 저장되지 않아요", app)
        expectSample("inquiryDetail", app, shot: "고객-C17-문의상세")
        back(app)
        tapID("sample.blockedUsersLink", app)
        expectSample("blockedUsers", app, shot: "고객-C17-차단한사용자")
        back(app)
        back(app)
        openPlanned("refund", app, shot: "고객-C18-환불분쟁")
        back(app)
        openPlanned("terms", app, shot: "고객-C19-약관정책")
        for title in ["서비스 이용약관", "위치기반서비스 이용약관", "개인정보 처리방침", "환불 정책"] {
            tapText(title, app)
            expectSample("document", app, shot: "고객-C19-문서-\(title)")
            back(app)
        }
        tapID("sample.locationInfoLink", app)
        expectSample("locationInfo", app, shot: "고객-C19-위치정보")
        tapID("sample.locationInquiryLink", app)
        expectSample("inquiry", app, shot: "고객-C19-위치정보-문의하기")
        back(app)
        back(app)
        tapText("동의 내역", app)
        expectSample("consents", app, shot: "고객-C19-동의내역")
        back(app)
        tapText("사진·계정 삭제", app)
        expectSample("deletion", app, shot: "고객-C19-삭제")
        back(app)
        back(app)
        openPlanned("events", app, shot: "고객-마이-이벤트")
        back(app)

        // 티켓이 있어야 닿는 화면: 개발 > 예시 화면 전체
        openDeveloper(app, shot: "고객-마이-개발")
        openPlanned("briefing", app, shot: "고객-C04-촬영안내")
        back(app)
        openPlanned("safety", app, shot: "고객-C05-안전긴급")
        tapID("sample.reportLink", app)
        expectSample("report", app, shot: "고객-C05-작가신고")
        back(app)
        back(app)
        openPlanned("recommendation", app, shot: "고객-C06-추천순서")
        back(app)
        openPlanned("basket", app, shot: "고객-C07-선택바구니")
        tapID("sample.compareLink", app)
        expectSample("compare", app, shot: "고객-C07-두장비교")
        back(app)
        back(app)
        openPlanned("review", app, shot: "고객-C08-리뷰")
        back(app)
        openSheet("채팅 신고 시트", sample: "chatReport", app, shot: "고객-채팅-신고")
        openSheet("채팅 차단 시트", sample: "chatBlock", app, shot: "고객-채팅-차단")
        print("SBSN 고객 예시 화면 \(Set(opened).count)개 열림: \(Set(opened).sorted())")
    }

    func test_photographerTour() throws {
        let app = photographerApp
        app.launch()
        dismissAlerts()
        XCTAssertTrue(app.tabBars.buttons["촬영"].waitForExistence(timeout: 30), "탭 바가 없음(로그인 확인)")
        XCTAssertTrue(app.switches["photographer.available"].waitForExistence(timeout: 20), "촬영 가능 토글이 없음")
        shot("작가-촬영-대기", app)

        // 촬영 탭: P1~P3
        openPlanned("activityArea", app, shot: "작가-P01-활동위치")
        back(app)
        openPlanned("breakTime", app, shot: "작가-P02-휴게")
        tapID("sample.breakToggle", app)
        shot("작가-P02-휴게중", app)
        back(app)
        openPlanned("requestPolicy", app, shot: "작가-P03-수락거절")
        back(app)

        // 내역 탭: P9~P13
        app.tabBars.buttons["내역"].tap()
        shot("작가-내역", app)
        openPlanned("history", app, shot: "작가-P09-촬영이력")
        tapText("14:10 · 서촌", app)
        expectSample("historyDetail", app, shot: "작가-P09-촬영상세")
        back(app)
        back(app)
        openPlanned("sales", app, shot: "작가-P10-판매전달")
        back(app)
        openPlanned("settlement", app, shot: "작가-P11-수익정산")
        tapText("10월분", app)
        expectSample("payoutDetail", app, shot: "작가-P11-지급명세")
        back(app)
        back(app)
        openPlanned("feedback", app, shot: "작가-P12-품질피드백")
        back(app)
        openPlanned("disputes", app, shot: "작가-P13-분쟁")
        tapText("환불 요청", app)
        expectSample("disputeDetail", app, shot: "작가-P13-분쟁상세")
        back(app)
        back(app)

        // 마이 탭: P14~P18
        app.tabBars.buttons["마이"].tap()
        shot("작가-마이", app)
        openPlanned("portfolio", app, shot: "작가-P14-프로필포트폴리오")
        tapID("sample.profilePreviewLink", app)
        expectSample("profilePreview", app, shot: "작가-P14-고객에게보이는모습")
        back(app)
        back(app)
        openPlanned("registration", app, shot: "작가-P15-등록계약")
        tapText("계약서 보기", app)
        expectSample("document", app, shot: "작가-P15-계약서")
        back(app)
        back(app)
        openPlanned("originals", app, shot: "작가-P16-원본보관")
        back(app)
        openPlanned("support", app, shot: "작가-P17-고객지원")
        tapID("sample.blockedUsersLink", app)
        expectSample("blockedUsers", app, shot: "작가-P17-차단한사용자")
        back(app)
        back(app)
        openPlanned("terms", app, shot: "작가-P18-약관정책")
        for title in ["작가 이용약관", "위치기반서비스 이용약관", "개인정보 처리방침"] {
            tapText(title, app)
            expectSample("document", app, shot: "작가-P18-문서-\(title)")
            back(app)
        }
        tapID("sample.locationInfoLink", app)
        expectSample("locationInfo", app, shot: "작가-P18-위치정보")
        tapID("sample.locationInquiryLink", app)
        expectSample("support", app, shot: "작가-P18-위치정보-문의하기")
        back(app)
        back(app)
        tapText("동의 내역", app)
        expectSample("consents", app, shot: "작가-P18-동의내역")
        back(app)
        tapText("계정 삭제", app)
        expectSample("deletion", app, shot: "작가-P18-삭제")
        back(app)
        back(app)

        // 티켓이 있어야 닿는 화면: 개발 > 예시 화면 전체
        openDeveloper(app, shot: "작가-마이-개발")
        openPlanned("customerBrief", app, shot: "작가-P04-고객브리프")
        back(app)
        openPlanned("safety", app, shot: "작가-P05-안전긴급")
        tapID("sample.reportLink", app)
        expectSample("report", app, shot: "작가-P05-고객신고")
        back(app)
        tapText("촬영 중단 요청", app)
        expectSample("stopRequest", app, shot: "작가-P05-촬영중단요청")
        back(app)
        back(app)
        openPlanned("timer", app, shot: "작가-P06-타이머")
        app.buttons["시작"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        shot("작가-P06-타이머진행", app)
        back(app)
        openPlanned("cameraGuide", app, shot: "작가-P07-연결가이드")
        tapText("소니", app)
        expectSample("cameraGuideDetail", app, shot: "작가-P07-소니")
        back(app)
        back(app)
        openPlanned("photoReview", app, shot: "작가-P08-검수공개")
        back(app)
        openSheet("채팅 신고 시트", sample: "chatReport", app, shot: "작가-채팅-신고")
        openSheet("채팅 차단 시트", sample: "chatBlock", app, shot: "작가-채팅-차단")
        print("SBSN 작가 예시 화면 \(Set(opened).count)개 열림: \(Set(opened).sorted())")
    }

    // MARK: - 도구

    /// 예시 화면 링크(`planned.<id>`)를 눌러 예시 화면(`sample.<id>`)이 뜨는지 보고 캡처한다.
    private func openPlanned(_ id: String, _ app: XCUIApplication, shot name: String) {
        tapID("planned.\(id)", app)
        expectSample(id, app, shot: name)
    }

    private func expectSample(_ id: String, _ app: XCUIApplication, shot name: String) {
        let root = app.descendants(matching: .any)["sample.\(id)"].firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 6), "\(name): 예시 화면 sample.\(id)이 뜨지 않음")
        XCTAssertFalse(app.staticTexts["준비 중"].exists, "\(name): 빈 \"준비 중\" 화면이 남아 있음")
        opened.append(id)
        shot(name, app)
    }

    /// 식별자로 찾아 누른다. 화면 밖이면 위아래로 밀어 찾는다.
    private func tapID(_ id: String, _ app: XCUIApplication) {
        let element = app.descendants(matching: .any)[id].firstMatch
        guard reveal(element, app) else {
            XCTFail("\(id)를 찾지 못함")
            return
        }
        element.tap()
    }

    private func tapText(_ text: String, _ app: XCUIApplication) {
        let element = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        guard reveal(element, app) else {
            XCTFail("\"\(text)\"를 찾지 못함")
            return
        }
        element.tap()
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 3), element.isHittable { return true }
        for _ in 0..<5 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        for _ in 0..<10 where !(element.exists && element.isHittable) {
            app.swipeDown()
        }
        return element.exists && element.isHittable
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func openDeveloper(_ app: XCUIApplication, shot name: String) {
        tapID("my.developer", app)
        XCTAssertTrue(app.navigationBars["개발"].waitForExistence(timeout: 5))
        shot(name, app)
    }

    /// 개발 메뉴의 시트 버튼(채팅 신고·차단)을 눌러 시트를 캡처하고 닫는다.
    private func openSheet(_ title: String, sample id: String, _ app: XCUIApplication, shot name: String) {
        let button = app.buttons[title].firstMatch
        guard reveal(button, app) else {
            XCTFail("\(title) 버튼을 찾지 못함")
            return
        }
        button.tap()
        expectSample(id, app, shot: name)
        app.buttons["닫기"].firstMatch.tap()
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
