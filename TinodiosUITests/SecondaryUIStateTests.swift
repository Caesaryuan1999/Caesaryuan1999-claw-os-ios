import XCTest
import UserNotifications

final class SecondaryUIStateTests: XCTestCase {
    func testNotificationNotDeterminedRequestsPermission() {
        let state = ClawNotificationAuthorization(status: .notDetermined,
            alertsEnabled: false, notificationCenterEnabled: false)
        XCTAssertFalse(state.isUsable)
        XCTAssertEqual(state.action(forStatusButton: true), .request)
        XCTAssertEqual(state.action(forStatusButton: false), .request)
    }

    func testNotificationDeniedOpensSettingsInsteadOfRequestingAgain() {
        let state = ClawNotificationAuthorization(status: .denied,
            alertsEnabled: false, notificationCenterEnabled: false)
        XCTAssertEqual(state.action(forStatusButton: true), .settings)
        XCTAssertEqual(state.action(forStatusButton: false), .settings)
        XCTAssertFalse(state.isUsable)
    }

    func testNotificationAuthorizedWithDisabledAlertOrCenterNeedsSettings() {
        for flags in [(false, true), (true, false), (false, false)] {
            let state = ClawNotificationAuthorization(status: .authorized,
                alertsEnabled: flags.0, notificationCenterEnabled: flags.1)
            XCTAssertFalse(state.isUsable)
            XCTAssertEqual(state.action(forStatusButton: false), .settings)
            XCTAssertTrue(state.title.contains("已授权"))
            XCTAssertTrue(state.summary.contains("部分提醒"))
        }
    }

    func testNotificationGrantedModesKeepUsablePreferencesWithoutReprompt() {
        for status in [UNAuthorizationStatus.authorized, .provisional, .ephemeral] {
            let state = ClawNotificationAuthorization(status: status,
                alertsEnabled: true, notificationCenterEnabled: true)
            XCTAssertTrue(state.isUsable)
            XCTAssertEqual(state.action(forStatusButton: false), .none)
            XCTAssertEqual(state.action(forStatusButton: true), .settings)
        }
    }

    func testNotificationReturnFromSettingsUsesNewSnapshot() {
        let denied = ClawNotificationAuthorization(status: .denied,
            alertsEnabled: false, notificationCenterEnabled: false)
        let enabled = ClawNotificationAuthorization(status: .authorized,
            alertsEnabled: true, notificationCenterEnabled: true)
        XCTAssertNotEqual(denied.isUsable, enabled.isUsable)
        XCTAssertEqual(denied.buttonTitle, "前往系统设置")
        XCTAssertEqual(enabled.action(forStatusButton: false), .none)
    }
}
