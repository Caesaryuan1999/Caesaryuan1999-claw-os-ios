"""Bounded source evidence only. Does not execute Swift, UIKit, AV or a microphone."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BASE = "0ea19847e3b043bc14bfb046d2e1809cf92134e6"
PRODUCTION = [
    "Tinodios/Cache.swift",
    "Tinodios/MediaRecorder.swift",
    "Tinodios/MessageViewController+SendMessageBarDelegate.swift",
    "Tinodios/MessageViewController.swift",
]
TESTS = [
    "TinodiosUITests/MediaRecorderLifecycleTests.swift",
    "TinodiosUITests/VoiceLayoutTests.swift",
]

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)

def original(path):
    return git("show", BASE + ":" + path).decode("utf-8")

def current(path):
    return (ROOT / path).read_text(encoding="utf-8")

def methods(text):
    result = {}
    for match in re.finditer(r"func (test\w+)\([^)]*\)[^{]*\{", text):
        depth, end = 1, match.end()
        while depth and end < len(text):
            depth += (text[end] == "{") - (text[end] == "}")
            end += 1
        assert depth == 0
        result[match.group(1)] = text[match.start():end].replace("\r\n", "\n")
    return result

def predicates(read):
    recorder = read(PRODUCTION[1])
    delegate = read(PRODUCTION[2])
    gate = delegate[delegate.index("case .stopAndSend:"):delegate.index("case .stopRecording, .pauseRecording:")]
    meter = recorder[recorder.index("@objc func recordUpdate()"):recorder.index("func audioRecorderDidFinishRecording")]
    return {
        "actual_factory_uses_unified_limit": "recorder.maxDuration = MediaRecorder.recordingLimitMilliseconds" in read(PRODUCTION[0]),
        "engine_limit_is_sixty_seconds": "static let recordingLimitMilliseconds = 60_000" in recorder,
        "submission_admission_before_handoff": "guard !recorder.deferSubmissionForRecordingCompletion() else { return }" in gate,
        "meter_does_not_invent_success_before_finish_flag": "stopForPreview()" not in meter,
    }

changed = git("diff", "--name-only", BASE, "--").decode().splitlines()
source_changed = [p for p in changed if not p.startswith("docs/")]
assert sorted(source_changed) == sorted(PRODUCTION + TESTS), source_changed
old_counts = {}
new_methods = {}
for path in TESTS:
    old, now = methods(original(path)), methods(current(path))
    assert all(now.get(name) == body for name, body in old.items()), path
    old_counts[path] = len(old)
    new_methods[path] = sorted(set(now) - set(old))
assert [len(new_methods[p]) for p in TESTS] == [3, 2]

for path in [
    "Tinodios/widgets/SendMessageBar.swift", "Tinodios/widgets/SendMessageBar.xib",
    "Tinodios/MessageCell+VLCMediaPlayerDelegate.swift", "Tinodios/MessageInteractor.swift",
    "Scripts/ci/verify_publish_outcomes_macos.sh", "Tinodios.xcodeproj/project.pbxproj",
    "Podfile", "Podfile.lock",
]:
    assert current(path) == original(path).replace("\r\n", "\n"), path

red, green = predicates(original), predicates(current)
assert not any(red.values()), red
assert all(green.values()), green
recorder = current(PRODUCTION[1])
assert "duration: max(0, Int(elapsed * 1000))" in recorder
assert "if flag { _ = self.stopForPreview() } else { self.failRecording() }" in recorder
assert "guard state == .recording else { return false }" in recorder
assert "guard recorder.isRecording else {" in recorder
assert "600_000" not in current(PRODUCTION[0]) + current(PRODUCTION[3])
assert "engine.isRecording = false; engine.currentTime = 0" in current(TESTS[0])
assert "bar.longPressed(sender: gesture)" in current(TESTS[1])
assert "override func sendAudioAttachment(recorder: MediaRecorder)" in current(TESTS[1])

paths = []
for path in PRODUCTION + TESTS:
    raw = (ROOT / path).read_bytes()
    paths.append({
        "path": path,
        "base_blob": git("rev-parse", BASE + ":" + path).decode().strip(),
        "working_git_clean_blob": git("hash-object", "--path=" + path, path).decode().strip(),
        "raw_sha256": hashlib.sha256(raw).hexdigest(),
        "lf_sha256": hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest(),
    })
report = {
    "base": BASE,
    "evidence_level": "Windows fixed-source predicates and unchanged assertions; no Swift or AV execution",
    "red_source_predicates": red,
    "green_source_predicates": green,
    "old_test_method_bodies_preserved": old_counts,
    "new_methods": new_methods,
    "previous_native_expected": 313,
    "candidate_native_expected": 318,
    "navigation_expected": 3,
    "native_execution": "NOT_RUN",
    "paths": paths,
}
Path(__file__).with_name("source-checks.json").write_text(
    json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
print("PASS: four source predicates; four production/two existing test files; old 14 method bodies unchanged; five new methods NOT_RUN")
