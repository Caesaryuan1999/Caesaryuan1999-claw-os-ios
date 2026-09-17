#!/usr/bin/env python3
"""Guard iOS APNs/FCM configuration and notification lifecycle coverage."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP_DELEGATE = (ROOT / "Tinodios" / "AppDelegate.swift").read_text(encoding="utf-8")
UI_UTILS = (ROOT / "Tinodios" / "UiUtils.swift").read_text(encoding="utf-8")
ENTITLEMENTS = (ROOT / "Tinodios" / "Tinodios.entitlements").read_text(encoding="utf-8")
DEVEL = (ROOT / "devel.xcconfig").read_text(encoding="utf-8")
PROD = (ROOT / "prod.xcconfig").read_text(encoding="utf-8")
IPA_WORKFLOW = (ROOT / ".github" / "workflows" / "ios-ipa.yml").read_text(encoding="utf-8")
SIGNING_SCRIPT = (ROOT / "Scripts" / "ci" / "install_ios_signing_assets.sh").read_text(encoding="utf-8")


def main() -> None:
    assert "APS_ENVIRONMENT = development" in DEVEL
    assert "APS_ENVIRONMENT = production" in PROD
    assert "<key>aps-environment</key>" in ENTITLEMENTS
    assert "<string>$(APS_ENVIRONMENT)</string>" in ENTITLEMENTS

    assert "UNUserNotificationCenter.current().delegate = appDelegate" in UI_UTILS
    assert "requestAuthorization" in UI_UTILS
    assert "registerForRemoteNotifications" in UI_UTILS
    assert "didRegisterForRemoteNotificationsWithDeviceToken" in APP_DELEGATE
    assert "didFailToRegisterForRemoteNotificationsWithError" in APP_DELEGATE
    assert "Messaging.messaging().apnsToken = deviceToken" in APP_DELEGATE

    assert "Remote notification callback:" in APP_DELEGATE
    assert "Foreground notification callback:" in APP_DELEGATE
    assert "Notification response callback:" in APP_DELEGATE
    assert "FCM registration succeeded:" in APP_DELEGATE
    assert "FCM token fetched:" in UI_UTILS
    assert "ClawNotificationDiagnostics.redactedToken" in APP_DELEGATE
    assert "ClawNotificationDiagnostics.redactedToken" in UI_UTILS

    # Unattributed push bodies cannot be displayed as another account's preview.
    assert "completionHandler([.badge, .banner, .list, .sound])" not in APP_DELEGATE
    assert 'body: "收到新消息，打开应用查看"' in APP_DELEGATE
    nse = (ROOT / "TinodiosNSExtension/NotificationService.swift").read_text(encoding="utf-8")
    assert 'safeContent.body = "收到新消息，打开应用查看"' in nse
    assert "SharedUtils.fetchDesc" not in nse
    assert "SharedUtils.connectAndLoginSync" not in APP_DELEGATE

    # Release IPA creation must fail closed when Firebase configuration is absent.
    assert "IOS_EXPECTED_APS_ENVIRONMENT: production" in IPA_WORKFLOW
    assert "Release IPA builds require a real Firebase configuration" in IPA_WORKFLOW
    assert "Creating a placeholder config for IPA build only" not in IPA_WORKFLOW
    assert "validate_profile_push_entitlement" in SIGNING_SCRIPT
    assert "Entitlements:aps-environment" in SIGNING_SCRIPT


if __name__ == "__main__":
    main()
