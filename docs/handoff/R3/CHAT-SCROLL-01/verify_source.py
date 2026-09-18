"""Narrow source/wiring checks, not Swift execution or UIKit behavioral tests."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BASE = "0a54fcf1ecb35a6f3511815ed59c7750f692ea2d"
PRODUCTION = ["FilePreviewController.swift", "ImagePreviewController.swift", "MessageInteractor.swift",
    "MessagePresenter.swift", "MessageViewController+MessageCellDelegate.swift",
    "MessageViewController+MessageDisplayLogic.swift", "MessageViewController+SendMessageBarDelegate.swift",
    "MessageViewController.swift", "VideoPreviewController.swift"]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

def old(path):
    return subprocess.check_output(["git", "show", BASE + ":" + path], cwd=ROOT).decode("utf-8")

results = []
def check(name, condition):
    assert condition, name
    results.append(name)

changed = subprocess.check_output(["git", "diff", "--name-only", BASE], cwd=ROOT, text=True).splitlines()
check("nine production files only", sorted(x for x in changed if x.startswith("Tinodios/")) ==
      sorted("Tinodios/" + x for x in PRODUCTION))
check("SDK DB recorder helpers XIB frozen", not any(x.startswith(("TinodeSDK/", "TinodiosDB/")) or
      x.endswith((".xib", ".storyboard", "MediaRecorder.swift", "Cache.swift", "LargeFileHelper.swift")) for x in changed))
vc = read("Tinodios/MessageViewController.swift")
display = read("Tinodios/MessageViewController+MessageDisplayLogic.swift")
interactor = read("Tinodios/MessageInteractor.swift")
check("automatic terminal uses no delayed bottom helper", ".scrollToBottom(" not in vc + display and
      "reloadDataAndKeepOffset" not in vc + display)
check("source fixed before cache queue", interactor.index("let source = originalSource ?? chatSource(for: t)") <
      interactor.index("self.messageInteractorQueue.async", interactor.index("private func loadMessagesFromCache(displayIntent:")))
check("two phases serialized", "completion: { _ in refreshPhase() }" in display and
      "completion: { _ in finish() }" in display and "enqueueChatPresentation" in display)
check("quote pin hook only delta", read("Tinodios/MessageViewController+MessageCellDelegate.swift").replace(
    "        invalidateChatDisplayIntent()\n", "", 1) == old("Tinodios/MessageViewController+MessageCellDelegate.swift"))
check("capture before prepareSubmission", vc.index("let displayIntent = captureChatSubmissionIntent()", vc.index("func sendAudioAttachment")) <
      vc.index("try recorder.prepareSubmission"))
for filename, later in [("FilePreviewController.swift", "sending = true"),
                         ("ImagePreviewController.swift", "originalImage.resize("),
                         ("VideoPreviewController.swift", "thumbnailer.getThumbmail")]:
    text = read("Tinodios/" + filename)
    check(filename + " immutable confirm before work", text.index("let displayIntent = captureDisplayIntent?()") < text.index(later) and
          "userInfo: [ChatDisplayIntent.notificationKey: displayIntent]" in text)
check("video read retains original UI intent", "private func sendVideoAttachment(withContent content: VideoPreviewContent, displayIntent: ChatDisplayIntent)" in vc and
      "previewOutOfBand: previewSize > Constants.kMaxPosterSize), displayIntent: displayIntent)" in vc)
for method in ["draftyAudio", "draftyImage", "draftyVideo", "draftyFile"]:
    pattern = r"(?ms)^    private static func " + method + r"\(.*?^    \}\n"
    check(method + " business body unchanged", re.findall(pattern, interactor) == re.findall(pattern, old("Tinodios/MessageInteractor.swift")))
script = read("Scripts/ci/verify_publish_outcomes_macos.sh")
addition = "  -only-testing:TinodiosVoiceLayoutTests/ChatScrollTests \\\n"
check("CI only one selector addition", script.count(addition) == 1 and script.replace(addition, "") == old("Scripts/ci/verify_publish_outcomes_macos.sh"))
tests = read("TinodiosUITests/ChatScrollTests.swift")
methods = re.findall(r"^    func (test\w+)\(", tests, re.M)
check("ten native methods without skip", len(methods) == 10 and "XCTSkip" not in tests)
check("original native tests byte stable", not any(p.startswith(("TinodeSDKTests/", "TinodiosUITests/")) and
      p != "TinodiosUITests/ChatScrollTests.swift" for p in changed))
check("real consumer and UIKit coverage", all(x in tests for x in ["controller.displayChatMessages(",
    "controller.sendMessageBar(sendText:", "preview.sendFileAttachment(sendButton)",
    "XCTAssertTrue(controller.chatPresentationRunning", "controller.collectionView.numberOfItems(inSection: 0)",
    "controller.chatMaximumOffset, accuracy: 1", "UIGraphicsImageRenderer"]))
project = read("Tinodios.xcodeproj/project.pbxproj")
check("source wired to existing App hosted target", "files = (C1A048000000000000000002, C1A050000000000000000002, );" in project and
      project.count("/* ChatScrollTests.swift in Sources */") == 1 and
      project.count("fileRef = C1A050000000000000000001;") == 1)
paths = ["Tinodios/" + x for x in PRODUCTION] + ["TinodiosUITests/ChatScrollTests.swift",
    "Tinodios.xcodeproj/project.pbxproj", "Scripts/ci/verify_publish_outcomes_macos.sh", "Scripts/ci/test_brand_ui_policy.py"]
report = {"level": "Windows source/wiring only; Swift/UIKit NOT_RUN", "checks": results,
    "nativeExpected": {"existing": 232, "newChatScroll": 10, "total": 242, "navigationSeparate": 3},
    "methods": methods, "sources": [{"path": p, "sha256": hashlib.sha256((ROOT / p).read_bytes()).hexdigest(),
    "gitBlob": subprocess.check_output(["git", "hash-object", "--path=" + p, p], cwd=ROOT, text=True).strip()} for p in paths]}
(Path(__file__).parent / "source-checks.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"passed": len(results), "level": report["level"], "methods": len(methods)}, ensure_ascii=False))
