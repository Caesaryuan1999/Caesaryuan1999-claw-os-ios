import XCTest

/// Real application navigation only: no credentials, OTP submission or live service.
final class IdentityNavigationUITests: XCTestCase {
    private var app: XCUIApplication!
    private var verifiedLoginScreen = false

    override class var runsForEachTargetApplicationUIConfiguration: Bool { false }

    override func setUpWithError() throws {
        continueAfterFailure = false
        verifiedLoginScreen = false
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-host_name_preference", "127.0.0.1:9", "-use_tls_preference", "false"
        ]
        app.launch()
        // Unknown or previously authenticated state fails. Never clear data to force a pass.
        assertLogin()
        verifiedLoginScreen = true
        XCTAssertTrue(app.textFields["手机号"].exists)
        XCTAssertFalse(app.textFields["原账号名"].exists)
    }

    override func tearDownWithError() throws {
        if verifiedLoginScreen && app?.state == .runningForeground { capture("navigation-final-state") }
        app?.terminate()
        app = nil
    }

    func testRegistrationAndResetReturnToLogin() {
        openIdentity("注册账号", title: "创建账号")
        XCTAssertTrue(app.textFields["手机号"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["邮箱"].exists)
        XCTAssertFalse(app.buttons["claw.identity.challenge"].isEnabled)
        capture("registration-entry")
        returnToLogin()

        openIdentity("找回密码", title: "找回密码")
        XCTAssertTrue(app.textFields["手机号"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["邮箱"].exists)
        XCTAssertFalse(app.buttons["claw.identity.challenge"].isEnabled)
        capture("password-reset-entry")
        returnToLogin()
    }

    func testKeyboardInputAndDismissalAcrossIdentityForms() {
        selectEmail()
        let email = app.textFields["邮箱"]
        enter("navigation@example.invalid", into: email)
        XCTAssertEqual(email.value as? String, "navigation@example.invalid")
        capture("login-email-keyboard")
        dismissKeyboardByTappingMargin()

        let password = app.secureTextFields["密码"]
        enter("NavigationOnly42", into: password)
        XCTAssertFalse((password.value as? String ?? "").isEmpty)
        capture("login-password-keyboard")
        dismissKeyboardByTappingMargin()

        openIdentity("注册账号", title: "创建账号")
        let phone = app.textFields["手机号"]
        enter("00000000000", into: phone)
        XCTAssertEqual(phone.value as? String, "00000000000")
        capture("registration-phone-keyboard")
        dismissKeyboardByTappingMargin()
        returnToLogin()

        openIdentity("找回密码", title: "找回密码")
        selectEmail()
        let resetEmail = app.textFields["邮箱"]
        enter("navigation@example.invalid", into: resetEmail)
        XCTAssertEqual(resetEmail.value as? String, "navigation@example.invalid")
        capture("password-reset-email-keyboard")
        dismissKeyboardByTappingMargin()
        returnToLogin()
    }

    func testLegacyEntryCanBeFullyRevealedAndSwitchedBack() {
        let legacy = app.buttons["使用原账号登录"]
        awaitState("Offline capabilities check must finish before legacy entry is enabled", timeout: 35) {
            legacy.exists && legacy.isEnabled
        }
        reveal(legacy)
        XCTAssertGreaterThanOrEqual(legacy.frame.height, 52)
        capture("legacy-entry-fully-visible")
        legacy.tap()

        let username = app.textFields["原账号名"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        reveal(username)
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)
        XCTAssertFalse(app.textFields["手机号"].exists)
        capture("legacy-account-mode")

        let standard = app.buttons["使用手机号或邮箱登录"]
        reveal(standard)
        XCTAssertTrue(standard.isEnabled)
        standard.tap()
        XCTAssertTrue(app.textFields["手机号"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["邮箱"].exists)
        XCTAssertFalse(app.textFields["原账号名"].exists)
        reveal(app.buttons["使用原账号登录"])
        capture("standard-account-mode-restored")
    }

    private var scroll: XCUIElement {
        app.tables.firstMatch.exists ? app.tables.firstMatch : app.scrollViews.firstMatch
    }

    private func awaitState(_ message: String, timeout: TimeInterval = 8,
                            file: StaticString = #filePath, line: UInt = #line,
                            _ condition: @escaping () -> Bool) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       message, file: file, line: line)
    }

    private func fullyVisible(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable, !element.frame.isEmpty, scroll.exists else { return false }
        let viewport = scroll.frame.intersection(app.frame)
        let frame = element.frame.insetBy(dx: 0.5, dy: 0.5)
        guard viewport.contains(frame) else { return false }
        let keyboard = app.keyboards.firstMatch
        return !keyboard.exists || !keyboard.frame.intersects(frame)
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Expected navigation control", file: file, line: line)
        for _ in 0..<6 {
            if fullyVisible(element) { break }
            if element.frame.midY < scroll.frame.midY { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        awaitState("Control must be fully visible and hittable after bounded scrolling",
                   file: file, line: line) { self.fullyVisible(element) }
    }

    private func assertLogin() {
        XCTAssertTrue(app.buttons["claw.login.primary"].waitForExistence(timeout: 10),
                      "Expected logged-out login screen; existing data was not reset")
        XCTAssertTrue(app.staticTexts["登录 CLAW OS"].exists)
    }

    private func openIdentity(_ entry: String, title: String) {
        let button = app.buttons[entry]
        reveal(button)
        XCTAssertTrue(button.isEnabled)
        button.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["claw.identity.challenge"].exists)
    }

    private func returnToLogin() {
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.exists)
        // Both real storyboard routes have only the standard navigation back button.
        XCTAssertEqual(bar.buttons.count, 1)
        let back = bar.buttons.firstMatch
        XCTAssertTrue(back.isEnabled && back.isHittable)
        back.tap()
        assertLogin()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    private func selectEmail() {
        let email = app.segmentedControls.buttons["邮箱"]
        reveal(email)
        awaitState("Email selector must become enabled") { email.isEnabled }
        email.tap()
        XCTAssertTrue(app.textFields["邮箱"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["手机号"].exists)
    }

    private func enter(_ text: String, into field: XCUIElement) {
        reveal(field)
        awaitState("Identity field must become enabled") { field.isEnabled }
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "A real software keyboard is required; hardware-only typing is not coverage")
        field.typeText(text)
        awaitState("Focused field must remain fully visible above the actual keyboard") {
            self.fullyVisible(field)
        }
    }

    private func dismissKeyboardByTappingMargin() {
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        // Exercise the real background-tap recognizer installed on all three controllers.
        // This point is within the form's empty leading margin, outside its text fields.
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.25)).tap()
        awaitState("Tapping the form background must dismiss the keyboard") {
            !self.app.keyboards.firstMatch.exists
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
