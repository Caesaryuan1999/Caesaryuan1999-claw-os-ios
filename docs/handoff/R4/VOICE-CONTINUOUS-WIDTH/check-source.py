"""Fixed-source scope/consumer evidence; this does not run Swift/UIKit."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BASE = "cb296b0f6c0f0571fc0d70f590ef916365c0dd0d"
SOURCE = "1fa8c6b4abd993fc10ced1acc7e153e9fba162d0"
PRODUCTION = ["Tinodios/MessageViewController.swift", "Tinodios/format/FormatNode.swift",
              "Tinodios/format/MultiImageTextAttachment.swift"]
TEST = "TinodiosUITests/VoiceLayoutTests.swift"
POLICY = "Scripts/ci/test_message_delete_policy.py"

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)

def old(path):
    return git("show", BASE + ":" + path).decode("utf-8").replace("\r\n", "\n")

def now(path):
    return (ROOT / path).read_text(encoding="utf-8")

def methods(text):
    found = {}
    for match in re.finditer(r"func (test\w+)\([^)]*\)[^{]*\{", text):
        depth, end = 1, match.end()
        while depth:
            assert end < len(text)
            depth += (text[end] == "{") - (text[end] == "}")
            end += 1
        found[match.group(1)] = text[match.start():end]
    return found

changed = git("diff", "--name-only", BASE, "--").decode().splitlines()
source_changed = sorted(p for p in changed if not p.startswith("docs/"))
assert source_changed == sorted(PRODUCTION + [TEST, POLICY]), source_changed
for path in PRODUCTION:
    assert now(path) == git("show", SOURCE + ":" + path).decode().replace("\r\n", "\n"), path
before, after = methods(old(TEST)), methods(now(TEST))
assert len(before) == 8
assert all(after.get(name) == body for name, body in before.items())
added = sorted(set(after) - set(before))
assert len(added) == 3

vc, formatter, attachment = [now(p) for p in PRODUCTION]
red_vc, red_formatter = [old(p) for p in PRODUCTION[:2]]
assert "audioBodyWidth(in:" not in red_vc
assert "guard voiceMaxWidth >= Constants.kPlayIconSize" in red_formatter
assert 'audio.type == "audio/toggle-play"' in vc
assert "durationMs: audio.audioDurationMilliseconds" in vc
assert "bodyWidth - padding" in vc
assert "play.audioDurationMilliseconds = attachment.duration" in formatter
assert "var audioDurationMilliseconds: Int?" in attachment
assert "CGFloat(min(max(durationMs ?? 0, 1_000), 60_000)) / 1000" in vc
assert "(maxVoiceWidth - baseVoiceWidth) * (seconds - 1) / 59" in vc
assert "size.width >= Constants.kPlayIconSize" in formatter
assert "maxContentWidth(availableWidth:" not in formatter
assert "size: CGSize(width: Constants.kPlayIconSize, height: Constants.kPlayIconSize)" in formatter
assert "$0 > 0 ? AbstractFormatter.millisToTime" in formatter

# The only policy change follows the relocated width consumer. All deletion
# assertions and every other policy file remain byte-equivalent in the diff.
old_policy = old(POLICY)
new_policy = now(POLICY)
old_assertion = '    assert "MessageBubbleLayoutPolicy.voiceWidth" in format_node\n'
assert old_assertion in old_policy
start = new_policy.index("    # AU width now belongs")
end = new_policy.index('\n\n\nif __name__', start)
assert new_policy[:start] + old_assertion.rstrip("\n") + new_policy[end:] == old_policy

script = now("Scripts/ci/verify_publish_outcomes_macos.sh")
assert "-only-testing:TinodiosVoiceLayoutTests/VoiceLayoutTests" in script
assert "VoiceLayoutTests.swift in Sources" in now("Tinodios.xcodeproj/project.pbxproj")
for path in ["Scripts/ci/verify_publish_outcomes_macos.sh", "Tinodios.xcodeproj/project.pbxproj",
             "Tinodios/widgets/RichTextView.swift", "Tinodios/MessageCell+VLCMediaPlayerDelegate.swift",
             "Tinodios/widgets/SendMessageBar.swift", "Tinodios/widgets/SendMessageBar.xib",
             "Tinodios/MediaRecorder.swift", "Tinodios/MessageInteractor.swift", "Podfile", "Podfile.lock"]:
    assert old(path) == now(path), path

paths = []
for path in PRODUCTION + [TEST, POLICY]:
    raw = (ROOT / path).read_bytes()
    clean = git("hash-object", "--path=" + path, path).decode().strip()
    paths.append({"path": path, "base_blob": git("rev-parse", BASE + ":" + path).decode().strip(),
                  "working_clean_blob": clean, "raw_sha256": hashlib.sha256(raw).hexdigest(),
                  "lf_sha256": hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest()})
report = {"base": BASE, "production_commit": SOURCE,
          "level": "Windows fixed source predicates; Swift/UIKit NOT_RUN",
          "red": "old voiceWidth was only a formatter guard; no container consumer",
          "old_voice_methods_preserved": len(before), "new_voice_methods": added,
          "native_before": 318, "native_candidate_expected": 321, "navigation_expected": 3,
          "native_execution": "NOT_RUN", "paths": paths}
Path(__file__).with_name("source-checks.json").write_text(
    json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
print("PASS: 3 fixed production, 1 existing Swift test file, 1 policy assertion; 8 old methods unchanged, 3 new methods NOT_RUN")
