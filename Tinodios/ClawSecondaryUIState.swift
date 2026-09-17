import Foundation
import UserNotifications

/// The same decision is used by the settings screen and native tests.
struct ClawNotificationAuthorization {
    enum Action: Equatable { case request, settings, none }
    let status: UNAuthorizationStatus
    let alertsEnabled: Bool
    let notificationCenterEnabled: Bool

    var isUsable: Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return alertsEnabled && notificationCenterEnabled
        default:
            return false
        }
    }

    func action(forStatusButton: Bool) -> Action {
        if status == .notDetermined { return .request }
        return forStatusButton || !isUsable ? .settings : .none
    }

    var title: String {
        if status == .notDetermined { return "开启新消息通知" }
        if status == .denied { return "系统通知已关闭" }
        return "已授权，可在系统设置调整提醒方式"
    }

    var summary: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return isUsable ? "系统允许显示提醒。具体投递仍受网络和系统设置影响。"
                : "部分提醒方式未开启，可在系统设置中调整。你仍可打开 CLAW OS 查看并同步消息。"
        default:
            return "可能无法及时收到新消息提醒。你仍可打开 CLAW OS 查看并同步消息。"
        }
    }

    var buttonTitle: String {
        status == .notDetermined ? "开启系统通知" : "前往系统设置"
    }
}
