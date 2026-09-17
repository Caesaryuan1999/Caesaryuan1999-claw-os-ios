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

import xml.etree.ElementTree as ET
image = (ROOT / "Tinodios/ImagePreviewController.swift").read_text(encoding="utf-8")
file = (ROOT / "Tinodios/FilePreviewController.swift").read_text(encoding="utf-8")
picker = (ROOT / "Tinodios/MessageViewController+SendMessageBarDelegate.swift").read_text(encoding="utf-8")
assert "ClawMediaFiles.exportPNG(data, suggestedName: content.fileName)" in image
assert "documentDirectory" not in image
assert "mediaState.loadInline(bits)" in image
assert "mediaState.complete(requestID, image: value.image)" in image
assert "Kingfisher.ImageResource(downloadURL: url, cacheKey: key)" in image
assert ".downloader(transport)" in image and "AnyRedirectHandler" in image
assert "LargeFileHelper.addCommonHeaders(to: &modified, using: owner)" in image
assert "using: Cache.tinode" not in image and "isConnectionAuthenticated" not in image
assert "snapshot.accepts(owner:" in image and "mediaState.isCurrent(requestID)" in image
assert "mediaState.shareData" in image and "imageView.image?.pixelData" not in image
assert "image_load_failed" in image and "image_export_failed" in image
assert "error.localizedDescription" not in image and "url.absoluteString" not in image
assert "ClawMediaFiles.read(url)" in picker and "ClawMediaFiles.readRecovery" in picker
assert "attachment_read_failed" in picker
assert 'sendButton.accessibilityLabel = "发送文件"' in file
tree = ET.parse(ROOT / "Tinodios/Base.lproj/Main.storyboard")
button = next(e for e in tree.iter("button") if e.get("id") == "LBd-NU-F3v")
assert button.find("./state").get("title") == "发送文件"
assert button.find("./constraints/constraint").get("constant") == "52"
assert button.find("./connections/action").get("selector") == "sendFileAttachment:"
assert "greaterThanOrEqual" == button.find("./constraints/constraint").get("relation")
print("MEDIA actual helper/controller/storyboard source wiring PASS; no provider/device execution")
assert "UiUtils.presentFileSharingVC(for: destination, for: owner)" in image
assert "if ClawMediaFiles.origin(requestURL) == ClawMediaFiles.origin(service)" in image
