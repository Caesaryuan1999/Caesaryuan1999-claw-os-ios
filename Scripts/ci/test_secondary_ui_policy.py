from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
controller = (ROOT / "Tinodios/SettingsNotificationsViewController.swift").read_text(encoding="utf-8")
model = (ROOT / "Tinodios/ClawSecondaryUIState.swift").read_text(encoding="utf-8")
project = (ROOT / "Tinodios.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
ci = (ROOT / "Scripts/ci/verify_publish_outcomes_macos.sh").read_text(encoding="utf-8")
assert "ClawNotificationAuthorization(status: settings.authorizationStatus" in controller
assert "authorization?.status == .notDetermined" in controller
assert "switch state.action(forStatusButton:" in controller
assert "UIApplication.didBecomeActiveNotification" in controller
assert "authorizationReadGeneration == generation" in controller
assert "greaterThanOrEqualToConstant: 52" in controller
assert "notificationsAuthorized ? openSystemSettings()" not in controller
assert "if status == .denied" in model and "部分提醒方式未开启" in model
assert project.count("ClawSecondaryUIState.swift in Sources */ =") == 2
assert "-only-testing:TinodiosUITests/SecondaryUIStateTests" in ci
print("NOTIFY controller/helper/target/CI source wiring PASS; no system permission execution")
