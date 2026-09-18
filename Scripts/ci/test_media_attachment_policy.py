#!/usr/bin/env python3
"""Static regression checks for iOS attachments and immersive media previews."""

from pathlib import Path
import re
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
HELPER = (ROOT / "Tinodios" / "LargeFileHelper.swift").read_text(encoding="utf-8")
INTERACTOR = (ROOT / "Tinodios" / "MessageInteractor.swift").read_text(encoding="utf-8")
CONTROLLER = (ROOT / "Tinodios" / "MessageViewController.swift").read_text(encoding="utf-8")
SEND_BAR = (ROOT / "Tinodios" / "MessageViewController+SendMessageBarDelegate.swift").read_text(encoding="utf-8")
IMAGE_PREVIEW = (ROOT / "Tinodios" / "ImagePreviewController.swift").read_text(encoding="utf-8")
VIDEO_PREVIEW = (ROOT / "Tinodios" / "VideoPreviewController.swift").read_text(encoding="utf-8")
STORYBOARD = (ROOT / "Tinodios" / "Base.lproj" / "Main.storyboard").read_text(encoding="utf-8")


def require(source: str, marker: str, message: str) -> None:
    if marker not in source:
        raise AssertionError(message)


def scene_containing(source: str, marker: str) -> str:
    marker_offset = source.index(marker)
    start = source.rfind("<scene", 0, marker_offset)
    end = source.index("</scene>", marker_offset) + len("</scene>")
    return source[start:end]


require(HELPER, "enum AttachmentUploadPolicy", "missing centralized upload retry policy")
require(HELPER, "static let maxAttempts = 3", "uploads must have a bounded retry count")
for status in (408, 425, 429):
    require(HELPER, str(status), f"HTTP {status} must be retryable")
require(HELPER, "statusCode >= 500", "5xx responses must be retryable")
require(HELPER, "NSURLErrorCancelled", "user cancellation must not be retried")
require(HELPER, "AttachmentUploadPolicy.shouldRetry", "upload completion must use retry policy")
require(HELPER, "enum FailureKind", "upload failures must be classified before retrying")
require(HELPER, "enum Outcome", "upload cleanup must use an explicit outcome")
require(HELPER, "static func classify", "upload error classification must be centralized")
require(HELPER, "shouldDeleteTemporarySource", "temporary source cleanup must be outcome-aware")
require(HELPER, "failedRetryable", "retryable upload failures must remain distinguishable from terminal failures")
require(HELPER, "removeItem(at: localURL)", "temporary multipart files must be deleted")
require(HELPER, "private func retry(upload:", "upload helper must restart transient failures")

require(INTERACTOR, "msgFailed(topic: topic, dbMessageId: msg.msgId)",
        "terminal upload failures must retain a failed message instead of silently deleting it")
if "self.interactor?.deleteFailedMessages()" in CONTROLLER:
    raise AssertionError("opening a conversation must not delete failed attachment messages")
require(SEND_BAR, "startAccessingSecurityScopedResource()",
        "files selected from Files/iCloud must use their security-scoped URL")
require(SEND_BAR, ".fileSizeKey", "file size must be checked before loading file data")
require(CONTROLLER, ".fileSizeKey", "video size must be checked before loading video data")

require(IMAGE_PREVIEW, "scrollView.backgroundColor = .black", "image preview canvas must be black")
require(IMAGE_PREVIEW, "imageView.backgroundColor = .black", "image preview must avoid light-mode flashes")
require(IMAGE_PREVIEW, "saveImageButtonClicked", "received images must retain the save action")
require(VIDEO_PREVIEW, "videoView.backgroundColor = .black", "video preview canvas must be black")
require(VIDEO_PREVIEW, "controlsView.backgroundColor = .black", "video loading state must avoid white flashes")
require(VIDEO_PREVIEW, "saveVideoButtonClicked", "received videos must retain the save action")

image_scene = scene_containing(STORYBOARD, 'storyboardIdentifier="ImagePreviewController"')
video_scene = scene_containing(STORYBOARD, 'customClass="VideoPreviewController"')
# The image immersive layout remains unchanged. R3's approved video design now
# displays captured-owner filename/actual size, so check its real wiring instead.
for marker in ("Details", "contentTypeLabel", "fileNameLabel", "sizeLabel"):
    if marker in image_scene:
        raise AssertionError(f"image preview must not expose file metadata: {marker}")

video = ET.fromstring(video_scene)
ids = [node.attrib["id"] for node in video.iter() if "id" in node.attrib]
assert len(ids) == len(set(ids)), "video scene IDs must be unique"
outlets = {node.attrib["property"]: node.attrib["destination"] for node in video.iter("outlet")}
declared = set(re.findall(r"@IBOutlet(?: private)? weak var (\w+):", VIDEO_PREVIEW))
assert set(outlets) == declared, "actual controller outlets and scene must agree exactly"
assert all(target in ids for target in outlets.values())
for node in video.iter("constraint"):
    for field in ("firstItem", "secondItem"):
        assert field not in node.attrib or node.attrib[field] in ids
for action in video.iter("action"):
    assert action.attrib["destination"] == "gfT-SI-43h"
    assert "func " + action.attrib["selector"].rstrip(":") + "(" in VIDEO_PREVIEW
for prop, selector in (("playPauseButton", "playPauseClicked:"), ("muteButton", "muteButtonClicked:"),
                       ("shareButton", "saveVideoButtonClicked:"), ("returnButton", "returnToChat:")):
    button = video.find(".//button[@id='" + outlets[prop] + "']")
    assert button is not None
    height = button.find("./constraints/constraint[@firstAttribute='height']")
    assert height is not None and height.attrib["relation"] == "greaterThanOrEqual"
    assert float(height.attrib["constant"]) >= 52
    assert button.find("./connections/action").attrib["selector"] == selector
assert video.find(".//viewLayoutGuide[@key='contentLayoutGuide']") is not None
assert video.find(".//viewLayoutGuide[@key='frameLayoutGuide']") is not None
for prop in ("fileNameLabel", "sizeLabel"):
    assert video.find(".//label[@id='" + outlets[prop] + "']").attrib["numberOfLines"] == "0"
for marker in ("traitCollection.preferredContentSizeCategory.isAccessibilityCategory",
               "label.sizeThatFits", "ClawTheme.font", "ClawTheme.background",
               "let content = frozenContent", "ownedContext?.isCurrent == true",
               "metadataStack.isHidden = failed", "sourceAvailable", "case .remote = content.videoSrc",
               "button === shareButton", "!isPreparingShare", "presentation.complete(result",
               "self?.acceptsSource(source) == true", "self?.shareSlot.accepts(attempt) == true",
               "player.isSeekable", "audio.isMuted", "updateLocalAccessoryInsets"):
    require(VIDEO_PREVIEW, marker, "video UI must retain production boundary: " + marker)
assert "as? UIBarButtonItem" not in VIDEO_PREVIEW
assert "周末海边" not in VIDEO_PREVIEW and "8.6 MB" not in VIDEO_PREVIEW

print("iOS media attachment and preview policy checks passed")
