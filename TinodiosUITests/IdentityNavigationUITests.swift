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
        captureKeyboard("login-email-keyboard", field: email)
        dismissKeyboardByTappingMargin()

        let password = app.secureTextFields["密码"]
        let syntheticPassword = "NavigationOnly42"
        enter(syntheticPassword, into: password)
        XCTAssertFalse((password.value as? String ?? "").isEmpty)
        captureKeyboard("login-password-keyboard", field: password,
                        expectedSecureLength: syntheticPassword.count)
        dismissKeyboardByTappingMargin()

        openIdentity("注册账号", title: "创建账号")
        let phone = app.textFields["手机号"]
        enter("00000000000", into: phone)
        XCTAssertEqual(phone.value as? String, "00000000000")
        captureKeyboard("registration-phone-keyboard", field: phone)
        dismissKeyboardByTappingMargin()
        returnToLogin()

        openIdentity("找回密码", title: "找回密码")
        selectEmail()
        let resetEmail = app.textFields["邮箱"]
        enter("navigation@example.invalid", into: resetEmail)
        XCTAssertEqual(resetEmail.value as? String, "navigation@example.invalid")
        captureKeyboard("password-reset-email-keyboard", field: resetEmail)
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

    private func captureKeyboard(_ name: String, field: XCUIElement, expectedSecureLength: Int? = nil) {
        recordKeyboardState(name + "-before", field: field, expectedSecureLength: expectedSecureLength)
        capture(name)
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = name + "-screen"
        screen.lifetime = .keepAlways
        add(screen)
        recordKeyboardState(name + "-after", field: field, expectedSecureLength: expectedSecureLength)
    }

    private func recordKeyboardState(_ name: String, field: XCUIElement, expectedSecureLength: Int?) {
        let keyboard = app.keyboards.firstMatch
        let keyboardExists = keyboard.exists
        let keyboardHittable = keyboardExists && keyboard.isHittable
        let keyboardFrame = keyboard.frame
        let fieldFrame = field.frame
        let appFrame = app.frame
        let fieldVisible = fullyVisible(field)
        let foreground = app.state == .runningForeground
        // Never attach input values, placeholder text or an accessibility tree.
        var state: [String: Any] = [
            "stage": name,
            "uptimeSeconds": ProcessInfo.processInfo.systemUptime,
            "appForeground": foreground,
            "keyboardExists": keyboardExists,
            "keyboardHittable": keyboardHittable,
            "keyboardFrame": geometry(keyboardFrame),
            "fieldFrame": geometry(fieldFrame),
            "appFrame": geometry(appFrame),
            "fieldFullyVisible": fieldVisible,
            "fieldOverlapsKeyboard": fieldFrame.intersects(keyboardFrame)
        ]
        var secureValueIsPopulated = true
        var secureLength = 0
        if let expectedLength = expectedSecureLength {
            let value = field.value as? String ?? ""
            secureLength = value.count
            secureValueIsPopulated = !value.isEmpty && value != field.label
                && value != (field.placeholderValue ?? "")
            state["secureValuePopulatedNotPlaceholder"] = secureValueIsPopulated
            state["secureValueCharacterCount"] = secureLength
            state["expectedSyntheticCharacterCount"] = expectedLength
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = name + "-state"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Could not encode safe keyboard geometry evidence")
        }
        XCTAssertTrue(foreground, "Keyboard evidence requires the foreground app")
        XCTAssertTrue(keyboardExists && keyboardHittable, "A hittable software keyboard must remain present")
        XCTAssertFalse(keyboardFrame.isEmpty, "Keyboard geometry must be nonempty")
        XCTAssertTrue(appFrame.intersects(keyboardFrame), "Keyboard must intersect the actual screen")
        XCTAssertTrue(fieldVisible, "Input must be fully visible while the keyboard is present")
        XCTAssertFalse(fieldFrame.intersects(keyboardFrame), "Keyboard must not cover the input")
        if let expectedLength = expectedSecureLength {
            XCTAssertTrue(secureValueIsPopulated, "Secure value must differ from the empty placeholder")
            XCTAssertEqual(secureLength, expectedLength, "Secure value must retain the synthetic input length")
        }
    }

    private func geometry(_ frame: CGRect) -> [String: Double] {
        ["x": Double(frame.minX), "y": Double(frame.minY),
         "width": Double(frame.width), "height": Double(frame.height)]
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
