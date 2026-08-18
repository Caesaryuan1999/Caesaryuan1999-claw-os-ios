#!/usr/bin/env python3
"""Static regression checks for iOS attachments and immersive media previews."""

from pathlib import Path


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
for scene, label in ((image_scene, "image"), (video_scene, "video")):
    for marker in ("Details", "contentTypeLabel", "fileNameLabel", "sizeLabel"):
        if marker in scene:
            raise AssertionError(f"{label} preview must not expose file metadata: {marker}")

print("iOS media attachment and preview policy checks passed")
