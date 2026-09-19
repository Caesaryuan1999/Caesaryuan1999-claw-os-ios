"""Bounded source/asset preservation check, not a Swift or UIKit test."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).with_name("VOICE-UI-CHECKS.json")
SOURCE = "89ccf1b4d34513defecccec448bf74bfed44ee65"
TEST = "TinodiosUITests/VoiceLayoutTests.swift"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def sha(data):
    return hashlib.sha256(data).hexdigest()


original = git("show", SOURCE + ":" + TEST).decode("utf-8").replace("\r\n", "\n")
current = (ROOT / TEST).read_text(encoding="utf-8")
first = current.index("    func testCompactVoiceOriginalRenderer")
last = current.index("    func testOwnedAudioActualAACPlayback", first)
without = current[:first] + current[last:]
first = without.index("private final class CompactVoiceTap:")
last = without.index("private final class VoiceDelegateSpy:", first)
without = without[:first] + without[last:]
assert without == original, "An existing method/helper changed"
methods = lambda text: re.findall(r"(?m)^    func (test\w+)\(", text)
old, new = methods(original), methods(current)
assert len(old) == 17 and len(new) == 20
assert set(old).issubset(new)
assets = []
for name in ("wave", "tail"):
    original_path = Path(__file__).parent / "design-assets" / ("voice-" + name + ".pdf")
    path = "Tinodios/Supporting Files/Assets.xcassets/claw-voice-" + name + ".imageset/voice-" + name + ".pdf"
    data = (ROOT / path).read_bytes()
    assert data == original_path.read_bytes() == git("show", SOURCE + ":" + path)
    assets.append({"path": path, "bytes": len(data), "sha256": sha(data)})
production = git("diff", "--name-only", SOURCE + "^", SOURCE).decode().splitlines()
assert len(production) == 7
assert not git("diff", SOURCE, "--", "Tinodios", "TinodeSDK", "TinodiosDB", "Podfile", "Podfile.lock", "Tinodios.xcodeproj", "Scripts", ".github").strip()
static = json.loads(OUT.with_name("VOICE-UI-STATIC.json").read_text(encoding="utf-8"))
assert static["scripts"] == 44 and static["failed"] == 0
git("diff", "--check")
report = {
    "level": "Windows source preservation and original PDF byte comparison; no Swift build",
    "visual_source": SOURCE,
    "production_paths": production,
    "test_path": TEST,
    "test_git_blob": git("hash-object", "--path=" + TEST, TEST).decode().strip(),
    "test_raw_sha256": sha((ROOT / TEST).read_bytes()),
    "old_methods": old,
    "old_methods_and_helpers_lf_unchanged": True,
    "added_methods": [m for m in new if m not in old],
    "method_count": len(new),
    "expected_native_total": 330,
    "navigation_methods_separate": 3,
    "static_scripts": {"passed": 44, "failed": 0},
    "assets": assets,
    "swift_uikit_av_execution": "NOT_RUN",
    "screenshots": "Prepared as XCTest keepAlways PNG/JSON; not yet generated for this candidate",
}
OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
print("PASS: seven production entities; original 17 test bodies/helpers unchanged; three new methods; two original PDFs; 44 source policies")
