"""Bounded Git/source and target-membership checks. Does not execute Swift/UIKit."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[4]
base = "4c1fecbfc320e85d11e5eb81b8481ed4d1f7e1b2"
inherited = "2e758cfc76e01f99a9a5fef7effd7f7c5f13eeff"
paths = [
    "Tinodios/ClawAssistantViewController.swift",
    "Tinodios/ClawAssistantHistoryViewController.swift",
    "Tinodios/ClawAssistantConversationViewController.swift",
    "TinodiosUITests/AssistantKnownRunLayoutTests.swift",
    "Tinodios.xcodeproj/project.pbxproj",
    "Scripts/ci/verify_publish_outcomes_macos.sh",
]


def git(*args):
    return subprocess.check_output(["git", "-C", str(root), *args])


tracked_delta = git("diff", "--name-only", base, "--", "Tinodios", "TinodiosUITests", "Tinodios.xcodeproj",
                    "Scripts/ci", "TinodeSDK", "TinodiosDB", "Podfile", "Podfile.lock", ".github").decode().splitlines()
assert set(tracked_delta).issubset(paths), tracked_delta
all_tests = git("ls-tree", "-r", "--name-only", base, "TinodiosUITests", "TinodeSDKTests").decode().splitlines()
old_tests = [p for p in all_tests if p.endswith(".swift")]
for path in old_tests:
    assert git("rev-parse", base + ":" + path) == git("hash-object", "--path=" + path, path), path
state = ["Tinodios/ClawAssistant" + name + ".swift" for name in ["Models", "Service", "Run", "Session", "History"]]
for path in state:
    assert git("rev-parse", base + ":" + path) == git("hash-object", "--path=" + path, path), path
selector = paths[-1]
before = git("show", base + ":" + selector).decode().replace("\r\n", "\n")
after = (root / selector).read_text(encoding="utf-8")
added = "  -only-testing:TinodiosVoiceLayoutTests/AssistantKnownRunLayoutTests \\\n"
assert after.count(added) == 1 and after.replace(added, "") == before
pbx = (root / paths[-2]).read_text(encoding="utf-8")
assert pbx.count("C1A090000000000000000003") == 3
assert pbx.count("C1A090000000000000000004") == 2
source_phase = re.search(r"C1A048000000000000000005 = \{isa = PBXSourcesBuildPhase;.*?\};", pbx).group()
assert source_phase.count("C1A090000000000000000004") == 1
tests = (root / paths[3]).read_text(encoding="utf-8")
methods = re.findall(r"func (test\w+)\(", tests)
assert len(methods) == 5 and len(set(methods)) == 5
state_methods = re.findall(r"func (test\w+)\(", (root / "TinodiosUITests/AssistantKnownRunTests.swift").read_text(encoding="utf-8"))
assert len(state_methods) == 13
entries = []
for path in paths:
    raw = (root / path).read_bytes()
    clean = raw.replace(b"\r\n", b"\n")
    entries.append({"path": path, "bytes": len(raw), "raw_sha256": hashlib.sha256(raw).hexdigest(),
                    "lf_sha256": hashlib.sha256(clean).hexdigest(),
                    "git_clean_blob": git("hash-object", "--path=" + path, path).decode().strip()})
checks = {
    "base": base, "inherited_ci_candidate": inherited,
    "evidence_level": "Windows source/membership only; Swift/UIKit/native NOT_RUN",
    "old_swift_files_unchanged": len(old_tests), "five_state_sources_unchanged": True,
    "only_one_selector_added": True, "target": "TinodiosVoiceLayoutTests",
    "ui_methods": methods, "known_state_methods": state_methods,
    "inherited_native_expected": 295, "candidate_native_expected": 313, "navigation_expected": 3,
    "paths": entries,
}
Path(__file__).with_name("ui-source-checks.json").write_text(
    json.dumps(checks, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
print(f"PASS: 6 UI code paths; {len(old_tests)} inherited Swift files and five state sources unchanged; 5 new UI methods pending Mac")
