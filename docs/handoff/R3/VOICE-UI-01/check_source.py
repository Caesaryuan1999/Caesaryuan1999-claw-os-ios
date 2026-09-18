"""Bounded source/XIB review; does not execute Swift, UIKit or the XIB."""
import ast
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
BASE = "0a7ba4470318e72064fe753ad2434b8a11329e72"
FILES = ["Tinodios/widgets/SendMessageBar.swift", "Tinodios/widgets/SendMessageBar.xib",
         "Tinodios/MessageViewController+SendMessageBarDelegate.swift", "Tinodios/MessageViewController.swift"]
checks = {}


def check(name, condition):
    checks[name] = bool(condition)
    assert condition, name


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def method(source, name):
    matches = re.findall(r"(?ms)^    (?:private )?func " + name + r"\([^\n]*\)[^\n]* \{\n.*?^    \}\n", source)
    assert len(matches) == 1, name
    return matches[0]


bar = (ROOT / FILES[0]).read_text(encoding="utf-8")
old_bar = git("show", BASE + ":" + FILES[0]).decode()
ci = (ROOT / "Scripts/ci/verify_publish_outcomes_macos.sh").read_text(encoding="utf-8")
expected = ast.literal_eval(re.search(r"expected = (\{.*?\})", ci[ci.index("VOICE_RESET_SOURCE"):], re.S)[1])
actual = {name: hashlib.sha256(method(bar, name).encode()).hexdigest() for name in expected}
check("three_production_reset_methods_keep_frozen_hashes", actual == expected)
check("optional_snapshot_all_consumers", not re.search(r"sendButtonConstrains\s*[!.]", bar))
check("gesture_window_identity_and_coordinates", bar.count("sender.location(in: gestureWindow)") == 2
      and "window === gestureWindow" in bar and "dX < -60" in bar and "dY < -60" in bar)
check("attachment_controller_byte_unchanged", bar.split("private final class ClawAttachmentSheetController", 1)[1]
      == old_bar.split("private final class ClawAttachmentSheetController", 1)[1])

xib = ET.parse(ROOT / FILES[1]).getroot()
old_xib = ET.fromstring(git("show", BASE + ":" + FILES[1]))
ids = [item.get("id") for item in xib.iter() if item.get("id")]
check("xib_unique_ids", len(ids) == len(set(ids)))
owner = next(item for item in xib.iter("placeholder") if item.get("placeholderIdentifier") == "IBFilesOwner")
outlets = {item.get("property"): item.get("destination") for item in owner.findall("./connections/outlet")}
declared = set(re.findall(r"@IBOutlet weak var (\w+):", bar))
check("xib_outlets_exactly_match_swift", set(outlets) == declared and all(value in ids for value in outlets.values()))
actions = [item.get("selector") for item in xib.iter("action") if item.get("destination") == "-1"]
# Swift longPressed(sender:) exposes the inherited Objective-C WithSender selector.
check("xib_actions_have_actual_handlers", all(
    "@IBAction func longPressed(sender: UILongPressGestureRecognizer)" in bar if action == "longPressedWithSender:"
    else re.search(r"@IBAction func " + action.split(":")[0] + r"\(", bar) for action in actions))
check("five_voice_actions_minimum_52", sum(item.get("constant") == "52" and item.get("relation") == "greaterThanOrEqual"
      and item.get("priority") == "999" for item in xib.iter("constraint")) == 5)
check("scroll_content_and_frame_guides", {item.get("key") for item in xib.iter("viewLayoutGuide")}
      >= {"contentLayoutGuide", "frameLayoutGuide"})
check("normal_input_recognizer_and_preview_identity_preserved", all(
    ET.tostring(next(item for item in xib.iter() if item.get("id") == ident))
    == ET.tostring(next(item for item in old_xib.iter() if item.get("id") == ident))
    for ident in ["LQB-Eu-unW", "GEe-0f-ZcN", "bxx-m5-ifU", "JUS-tF-V11", "Sxl-U7-4Vy"]))
check("no_sample_duration_or_fake_samples", "00:12" not in bar and "00:12" not in ET.tostring(xib, encoding="unicode")
      and "wavePreviewImageView?.put(amplitude: amplitude, atTime: atTime)" in bar)
check("actual_duration_and_vlc_time", "recordedDuration = max(0, duration)" in bar and "recordedDuration = max(0, atTime)" in bar
      and "player.time?.value" in (ROOT / FILES[2]).read_text(encoding="utf-8"))

delegate = (ROOT / FILES[2]).read_text(encoding="utf-8")
old_delegate = git("show", BASE + ":" + FILES[2]).decode()
# Compare the complete existing record-audio action section, not a simulated guard.
start = "    func sendMessageBar(recordAudio action: AudioBarAction) {"
end = "\nextension MessageViewController: UIDocumentPickerDelegate"
check("recorder_and_player_action_dispatch_byte_unchanged", delegate[delegate.index(start):delegate.index(end)]
      == old_delegate[old_delegate.index(start):old_delegate.index(end)])
vc = (ROOT / FILES[3]).read_text(encoding="utf-8")
old_vc = git("show", BASE + ":" + FILES[3]).decode()
for name in ["voiceScopeIsCurrent", "voiceUI", "stopRecordingPlayback", "discardVoiceRecording", "sendAudioAttachment"]:
    check("owner_lifecycle_method_unchanged_" + name, method(vc, name) == method(old_vc, name))
check("existing_ci_and_native_tests_unchanged", not git("diff", BASE, "--", "Scripts/ci", "TinodeSDKTests", "TinodiosUITests",
      "Tinodios.xcodeproj", "Podfile", "Podfile.lock", "Tinodios/MediaRecorder.swift", "Tinodios/Cache.swift", "Tinodios/MessageInteractor.swift").strip())

manifest = [{"path": name, "rawSHA256": hashlib.sha256((ROOT / name).read_bytes()).hexdigest(),
             "normalizedBlob": git("hash-object", "--", name).decode().strip()} for name in FILES]
result = {"base": BASE, "scope": "Windows source/XML inspection only; Swift/XIB/UI execution NOT_RUN",
          "checks": checks, "resetMethodSHA256": actual, "xibIDs": len(ids), "outlets": len(outlets),
          "actions": actions, "files": manifest, "nativeExpected": {"SDK": 44, "UIrunner": 167, "VLChost": 4, "navigationSeparate": 3}}
(HERE / "source-checks.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"PASS {len(checks)} source/XML checks; not Swift/UI execution")
