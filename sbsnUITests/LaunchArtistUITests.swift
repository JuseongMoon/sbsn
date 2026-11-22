import XCTest

/// 출시 1단계 작가 흐름과 계정 삭제(D059·L07·L08·L10)를 공용 개발 에뮬레이터에서 돈다. 앱은 `-SBSNEmulatorHost`로 띄운다.
///
/// 시험마다 Auth 에뮬레이터에 새 비밀번호 시험 계정을 만들고 `launchTest: true` 클레임을 붙인다(L09, 에뮬레이터 관리자 토큰 `owner`).
/// 시뮬레이터 위치는 서비스 범위 안(서울)으로, 작가 앱 위치 권한은 미리 허용해 둔다(`simctl location`·`simctl privacy`).
@MainActor
final class LaunchArtistUITests: XCTestCase {
    var host: String { ProcessInfo.processInfo.environment["SBSN_EMULATOR_HOST"] ?? "127.0.0.1" }
    lazy var admin = EmulatorAdmin(host: host)
    let photographerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsnPhotographer")
    let customerApp = XCUIApplication(bundleIdentifier: "com.ScienceFiction.sbsn")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 작가: 로그인 → 승인 전 촬영 가능 거부 → 승인 → 발행 → 앱 재시작은 같은 기기 세션 → 다른 기기 넘겨받음 → 다시 켜기 → 끄기 → 로그아웃
    func test_L2_artistApprovalPublishAndTakeover() async throws {
        let account = try await admin.createTestAccount(prefix: "artist")
        let app = photographerApp
        app.launchArguments = ["-SBSNEmulatorHost", host]
        app.launch()
        try signInAtGate(app, account: account)
        print("SBSN 작가 로그인 \(account.uid.prefix(6))…")

        // 1. 승인 전: 서버가 거부하고 스위치가 꺼진다.
        let toggle = try openAvailabilityToggle(app)
        tapSwitch(toggle)
        allowNotificationsIfAsked()
        let error = app.staticTexts["photographer.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 30), "승인 전 거부 문구가 없음")
        print("SBSN 승인 전 거부: \(error.label)")
        XCTAssertTrue(error.label.contains("작가 계정이 아닙니다"))
        XCTAssertTrue(waitUntil(timeout: 10) { toggle.value as? String == "0" }, "거부 뒤 스위치가 꺼지지 않음")

        // 2. 운영 승인 뒤 켜면 공개 지도 문서가 생긴다.
        try await admin.setDocument("launchArtistRoles/\(account.uid)", fields: ["approved": ["booleanValue": true]])
        tapSwitch(toggle)
        allowNotificationsIfAsked()
        let first = try await waitForDocument("publicPhotographers/\(account.uid)", timeout: 40)
        let firstExpires = try XCTUnwrap(first.timestamp("expiresAt"))
        let deviceDoc = try await admin.document("launchDevices/\(account.uid)")
        let device = try XCTUnwrap(deviceDoc)
        let sessionHash = try XCTUnwrap(device.string("activeDeviceSessionHash"))
        print("SBSN 발행 확인: 지도 문서 있음, 만료까지 \(Int(firstExpires.timeIntervalSinceNow))초")

        // 3. 앱을 다시 켜면 저장한 세션으로 발행만 한다(켜기를 다시 보내지 않으므로 활성 기기 세션이 그대로다).
        app.terminate()
        app.launch()
        let resumed = try openAvailabilityToggle(app)
        XCTAssertEqual(resumed.value as? String, "1", "재시작 뒤 촬영 가능이 이어지지 않음")
        let next = try await waitForDocument("publicPhotographers/\(account.uid)", timeout: 80) { doc in
            (doc.timestamp("expiresAt") ?? .distantPast) > firstExpires
        }
        let afterDoc = try await admin.document("launchDevices/\(account.uid)")
        let after = try XCTUnwrap(afterDoc)
        XCTAssertEqual(after.string("activeDeviceSessionHash"), sessionHash, "재시작 뒤 기기 세션이 바뀜")
        print("SBSN 재시작 뒤 같은 세션으로 갱신: 만료 \(Int(((next.timestamp("expiresAt") ?? firstExpires).timeIntervalSince(firstExpires))))초 늘어남")

        // 4. 다른 기기가 켜면(같은 계정, 새 deviceSessionId) 다음 발행 주기에 이 기기는 멈추고 끈다.
        let token = try await admin.idToken(email: account.email, password: account.password)
        let otherDevice = UUID().uuidString.lowercased()
        let (status, _) = try await admin.call("setLaunchAvailabilityV1", idToken: token,
                                               data: ["available": true, "deviceSessionId": otherDevice])
        XCTAssertEqual(status, 200)
        let takenAt = Date()
        XCTAssertTrue(waitUntil(timeout: 80) { resumed.value as? String == "0" }, "다른 기기가 켠 뒤 이 기기가 꺼지지 않음")
        let replaced = app.staticTexts["photographer.error"]
        XCTAssertTrue(replaced.waitForExistence(timeout: 5))
        XCTAssertEqual(replaced.label, "다른 기기에서 촬영 가능을 켜서 이 기기는 껐습니다.")
        print("SBSN 넘겨받음: \(Int(Date().timeIntervalSince(takenAt)))초 뒤 이 기기 꺼짐")
        attachScreenshot("넘겨받음", app: app)
        // 다른 기기 것을 끈다(시험 정리). 이 기기는 서버에 끄기를 보내지 않았으므로 성공해야 한다.
        let (offStatus, _) = try await admin.call("setLaunchAvailabilityV1", idToken: token,
                                                  data: ["available": false, "deviceSessionId": otherDevice])
        XCTAssertEqual(offStatus, 200, "다른 기기 세션 끄기 실패(이 기기가 소유권을 다시 가져갔나?)")

        // 5. 이 기기에서 다시 켜면 새 세션으로 소유권을 가져온다. 끄면 지도 문서가 바로 지워진다.
        tapSwitch(resumed)
        _ = try await waitForDocument("publicPhotographers/\(account.uid)", timeout: 80)
        let retakenDoc = try await admin.document("launchDevices/\(account.uid)")
        let retaken = try XCTUnwrap(retakenDoc)
        XCTAssertNotEqual(retaken.string("activeDeviceSessionHash"), sessionHash, "다시 켰는데 새 세션이 아님")
        tapSwitch(resumed)
        let removed = try await waitForMissing("publicPhotographers/\(account.uid)", timeout: 20)
        XCTAssertTrue(removed, "끈 뒤 지도 문서가 남음")
        print("SBSN 다시 켜기·끄기 확인")

        // 6. 로그아웃하면 로그인 화면으로 돌아간다.
        app.tabBars.buttons["마이"].tap()
        let signOut = app.buttons["my.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        signOut.tap()
        XCTAssertTrue(app.switches["signIn.age14"].waitForExistence(timeout: 20), "로그아웃 뒤 로그인 화면이 아님")
    }

    /// 작가: 로그인 → 계정 삭제 → 로그인 화면. 서버 작업이 끝나 Auth 계정이 지워진다(Apple 없음 경로).
    func test_L3_artistAccountDeletion() async throws {
        let account = try await admin.createTestAccount(prefix: "artist")
        let app = photographerApp
        app.launchArguments = ["-SBSNEmulatorHost", host]
        app.launch()
        try signInAtGate(app, account: account)
        try await admin.setDocument("launchArtistRoles/\(account.uid)", fields: ["approved": ["booleanValue": true]])
        app.tabBars.buttons["마이"].tap()
        try deleteAccount(app)
        XCTAssertTrue(app.switches["signIn.age14"].waitForExistence(timeout: 30), "삭제 뒤 로그인 화면이 아님")
        try await expectDeletionCompleted(uid: account.uid)
    }

    /// 고객: 마이 → 로그인 → 계정 삭제 → 익명 둘러보기. 서버 작업이 끝나 Auth 계정이 지워진다(Apple 없음 경로).
    func test_L4_customerAccountDeletion() async throws {
        let account = try await admin.createTestAccount(prefix: "customer")
        let app = customerApp
        app.launchArguments = ["-SBSNEmulatorHost", host]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 30))
        app.tabBars.buttons["마이"].tap()
        if app.buttons["my.signOut"].waitForExistence(timeout: 5) {
            app.buttons["my.signOut"].tap()
        }
        let signIn = app.buttons["my.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        signIn.tap()
        try fillSignIn(app, account: account)
        XCTAssertTrue(app.descendants(matching: .any)["my.nickname"].waitForExistence(timeout: 30), "로그인 뒤 닉네임이 없음")
        try deleteAccount(app)
        XCTAssertTrue(app.buttons["my.signIn"].waitForExistence(timeout: 30), "삭제 뒤 둘러보기로 돌아가지 않음")
        try await expectDeletionCompleted(uid: account.uid)
    }

    // MARK: - 화면 도우미

    /// 작가 앱의 로그인 화면에서 시험 계정으로 로그인한다. 이미 로그인한 채면 먼저 로그아웃한다.
    private func signInAtGate(_ app: XCUIApplication, account: EmulatorAdmin.TestAccount) throws {
        let age = app.switches["signIn.age14"]
        if !age.waitForExistence(timeout: 15) {
            XCTAssertTrue(app.tabBars.buttons["마이"].waitForExistence(timeout: 15), "로그인 화면도 탭도 없음")
            app.tabBars.buttons["마이"].tap()
            let signOut = app.buttons["my.signOut"]
            XCTAssertTrue(signOut.waitForExistence(timeout: 10))
            signOut.tap()
            XCTAssertTrue(age.waitForExistence(timeout: 20), "로그아웃 뒤 로그인 화면이 아님")
        }
        try fillSignIn(app, account: account)
        XCTAssertTrue(app.tabBars.buttons["촬영"].waitForExistence(timeout: 30), "로그인 뒤 탭이 보이지 않음: \(app.staticTexts["signIn.error"].exists ? app.staticTexts["signIn.error"].label : "-")")
    }

    private func fillSignIn(_ app: XCUIApplication, account: EmulatorAdmin.TestAccount) throws {
        let age = app.switches["signIn.age14"]
        XCTAssertTrue(age.waitForExistence(timeout: 10))
        if age.value as? String != "1" { tapSwitch(age) }
        let email = app.textFields["signIn.test.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "시험 로그인 칸이 없음(에뮬레이터 아님?)")
        email.tap()
        email.typeText(account.email)
        let password = app.textFields["signIn.test.password"]
        password.tap()
        password.typeText(account.password)
        app.buttons["signIn.test.submit"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<6 {
            if app.buttons["지금 안 함"].exists { app.buttons["지금 안 함"].tap(); break }
            if springboard.buttons["지금 안 함"].exists { springboard.buttons["지금 안 함"].tap(); break }
            usleep(500_000)
        }
    }

    private func openAvailabilityToggle(_ app: XCUIApplication) throws -> XCUIElement {
        let tab = app.tabBars.buttons["촬영"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        let toggle = app.switches["photographer.available"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "촬영 가능 스위치가 없음")
        XCTAssertTrue(waitUntil(timeout: 20) { toggle.isEnabled }, "촬영 가능 스위치를 누를 수 없음(이름·로그인?)")
        return toggle
    }

    private func deleteAccount(_ app: XCUIApplication) throws {
        let delete = app.buttons["my.deleteAccount"]
        for _ in 0..<6 where !(delete.exists && delete.isHittable) { app.swipeUp() }
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "계정 삭제 단추가 없음")
        delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "삭제 확인 창이 없음")
        print("SBSN 삭제 확인 창: \(alert.label) / \(alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))")
        let confirm = app.alerts.buttons["계정 삭제"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "삭제 확인 창이 없음")
        confirm.tap()
        // 요청 뒤 최대 10초 동안 완료를 보고 알림을 띄운다(에뮬레이터는 곧 끝나므로 "계정을 삭제했습니다.").
        let notice = app.alerts["계정을 삭제했습니다."]
        XCTAssertTrue(notice.waitForExistence(timeout: 30), "삭제 완료 알림이 없음: \(app.alerts.firstMatch.exists ? app.alerts.firstMatch.label : "-")")
        print("SBSN 삭제 뒤 알림: \(notice.label)")
        notice.buttons["확인"].tap()
    }

    private func expectDeletionCompleted(uid: String) async throws {
        var status: String?
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            status = try await admin.document("accountDeletionJobs/\(uid)")?.string("status")
            if status == "completed" { break }
            try await Task.sleep(for: .seconds(2))
        }
        XCTAssertEqual(status, "completed", "삭제 작업이 끝나지 않음")
        let exists = try await admin.userExists(uid: uid)
        XCTAssertFalse(exists, "Auth 계정이 남음")
        let profile = try await admin.document("users/\(uid)")
        XCTAssertNil(profile, "프로필이 남음")
        print("SBSN 계정 삭제 완료: 작업 completed, Auth·프로필 없음")
    }

    private func allowNotificationsIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["허용"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
    }

    private func tapSwitch(_ toggle: XCUIElement) {
        // SwiftUI Toggle은 행 전체가 아니라 오른쪽 스위치를 눌러야 바뀐다.
        let knob = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        knob.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return condition()
    }

    private func waitForDocument(_ path: String, timeout: TimeInterval,
                                 where accept: ([String: Any]) -> Bool = { _ in true }) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let doc = try await admin.document(path), accept(doc) { return doc }
            try await Task.sleep(for: .seconds(2))
        }
        XCTFail("문서가 생기지 않음: \(path.split(separator: "/").first ?? "")")
        throw EmulatorAdmin.Failure.timeout
    }

    private func waitForMissing(_ path: String, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try await admin.document(path) == nil { return true }
            try await Task.sleep(for: .seconds(1))
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

/// 공용 개발 에뮬레이터 관리자 호출(REST, 관리자 토큰 `owner`). 데모 프로젝트에서만 쓴다.
struct EmulatorAdmin {
    struct TestAccount {
        let email: String
        let password: String
        let uid: String
    }

    enum Failure: Error {
        case badResponse(Int, String)
        case timeout
    }

    let host: String
    let project = "demo-sbsn-functions"
    var auth: String { "http://\(host):19099" }
    var firestore: String { "http://\(host):18080/v1/projects/\(project)/databases/(default)/documents" }
    var functions: String { "http://\(host):15001/\(project)/asia-northeast3" }

    /// 새 비밀번호 시험 계정 + `launchTest` 클레임(L09)
    func createTestAccount(prefix: String) async throws -> TestAccount {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let email = "\(prefix)-\(suffix)@example.test"
        let password = UUID().uuidString
        let (status, body) = try await request("\(auth)/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key",
                                               body: ["email": email, "password": password, "returnSecureToken": true])
        guard status == 200, let uid = body["localId"] as? String else { throw Failure.badResponse(status, "signUp") }
        let (claimStatus, _) = try await request("\(auth)/identitytoolkit.googleapis.com/v1/projects/\(project)/accounts:update",
                                                 bearer: "owner", body: ["localId": uid, "customAttributes": #"{"launchTest":true}"#])
        guard claimStatus == 200 else { throw Failure.badResponse(claimStatus, "claims") }
        return TestAccount(email: email, password: password, uid: uid)
    }

    func idToken(email: String, password: String) async throws -> String {
        let (status, body) = try await request("\(auth)/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key",
                                               body: ["email": email, "password": password, "returnSecureToken": true])
        guard status == 200, let token = body["idToken"] as? String else { throw Failure.badResponse(status, "signIn") }
        return token
    }

    func userExists(uid: String) async throws -> Bool {
        let (status, body) = try await request("\(auth)/identitytoolkit.googleapis.com/v1/projects/\(project)/accounts:lookup",
                                               bearer: "owner", body: ["localId": [uid]])
        guard status == 200 else { throw Failure.badResponse(status, "lookup") }
        return !((body["users"] as? [Any]) ?? []).isEmpty
    }

    /// 문서의 필드(Firestore REST 형식). 없으면 nil.
    func document(_ path: String) async throws -> [String: Any]? {
        let (status, body) = try await request("\(firestore)/\(path)", method: "GET", bearer: "owner")
        if status == 404 { return nil }
        guard status == 200 else { throw Failure.badResponse(status, "get") }
        return body["fields"] as? [String: Any] ?? [:]
    }

    func setDocument(_ path: String, fields: [String: Any]) async throws {
        let (status, _) = try await request("\(firestore)/\(path)", method: "PATCH", bearer: "owner", body: ["fields": fields])
        guard status == 200 else { throw Failure.badResponse(status, "patch") }
    }

    /// 호출 함수를 사용자 토큰으로 부른다(다른 기기 흉내).
    func call(_ name: String, idToken: String, data: [String: Any]) async throws -> (Int, [String: Any]) {
        try await request("\(functions)/\(name)", bearer: idToken, body: ["data": data])
    }

    private func request(_ url: String, method: String = "POST", bearer: String? = nil, body: Any? = nil) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, json)
    }
}

extension Dictionary where Key == String, Value == Any {
    func string(_ field: String) -> String? {
        (self[field] as? [String: Any])?["stringValue"] as? String
    }

    func timestamp(_ field: String) -> Date? {
        guard let text = (self[field] as? [String: Any])?["timestampValue"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
