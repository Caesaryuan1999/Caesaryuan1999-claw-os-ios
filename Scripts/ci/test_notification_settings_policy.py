#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SHARED = (ROOT / "TinodiosDB" / "SharedUtils.swift").read_text(encoding="utf-8")
SETTINGS = (ROOT / "Tinodios" / "SettingsNotificationsViewController.swift").read_text(encoding="utf-8")
APP_DELEGATE = (ROOT / "Tinodios" / "AppDelegate.swift").read_text(encoding="utf-8")


PREFERENCES = {
    "kClawPrefPrivateMessageNotifications": "true",
    "kClawPrefGroupMessageNotifications": "true",
    "kClawPrefCallNotifications": "true",
    "kClawPrefMessagePreview": "false",
    "kClawPrefInAppVibration": "true",
}


def main() -> None:
    for key, default in PREFERENCES.items():
        assert f"static public let {key}" in SHARED, f"missing preference key: {key}"
        assert f"{key}: {default}" in SHARED, f"unexpected default for {key}"
        assert key in SETTINGS, f"settings screen does not expose {key}"

    for localization_key in (
        "private_messages",
        "group_messages",
        "call_reminders",
        "message_preview",
        "notification_sound",
        "in_app_vibration",
    ):
        assert f'text("{localization_key}")' in SETTINGS, f"missing notification UI row: {localization_key}"

    assert "UNUserNotificationCenter.current().getNotificationSettings" in SETTINGS
    assert "ClawNotificationAuthorization(status: settings.authorizationStatus" in SETTINGS
    assert "authorization?.status == .notDetermined" in SETTINGS
    assert "settings.alertSetting == .enabled" in SETTINGS
    assert "settings.notificationCenterSetting == .enabled" in SETTINGS
    assert "requestAuthorization(options: [.alert, .badge, .sound])" in SETTINGS
    assert "UIApplication.openSettingsURLString" in SETTINGS
    assert "control.accessibilityLabel = row.title" in SETTINGS

    assert "enum ClawNotificationPolicy" in APP_DELEGATE
    assert "ClawNotificationPolicy.allowsMessage" in APP_DELEGATE
    assert "ClawNotificationPolicy.allowsCalls" in APP_DELEGATE
    assert "ClawNotificationPolicy.previewBody" in APP_DELEGATE
    assert "ClawNotificationPolicy.vibratesInApp" in APP_DELEGATE
    utils = (ROOT / "Tinodios" / "Utils.swift").read_text(encoding="utf-8")
    assert "struct ClawMessageNotice" in utils
    assert "static let maxBodyLength = 120" in utils
    assert "var deliveryKey" in utils
    assert "var canOpenTopic" in utils
    assert "ClawMessageNotice(topic:" in APP_DELEGATE
    assert "UINotificationFeedbackGenerator().notificationOccurred(.success)" in APP_DELEGATE
    assert "messageVC.topicName == topicName" in APP_DELEGATE


if __name__ == "__main__":
    main()
