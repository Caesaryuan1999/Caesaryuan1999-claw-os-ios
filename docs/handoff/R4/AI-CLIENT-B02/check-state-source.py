"""Bounded source/membership evidence only. Does not execute Swift or native tests."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[4]
base = "2e758cfc76e01f99a9a5fef7effd7f7c5f13eeff"
paths = [
    "Tinodios/ClawAssistantModels.swift", "Tinodios/ClawAssistantService.swift",
    "Tinodios/ClawAssistantRun.swift", "Tinodios/ClawAssistantSession.swift",
    "Tinodios/ClawAssistantHistory.swift", "TinodiosUITests/AssistantKnownRunTests.swift",
    "Tinodios.xcodeproj/project.pbxproj", "Scripts/ci/verify_publish_outcomes_macos.sh",
]

def git(*args):
    return subprocess.check_output(["git", "-C", str(root), *args])

changed = git("diff", "--name-only", base, "--", "Tinodios", "TinodiosUITests", "Tinodios.xcodeproj",
              "Scripts/ci", "TinodeSDK", "TinodiosDB", "Podfile", "Podfile.lock", ".github").decode().splitlines()
assert set(changed).issubset(paths), changed
old_tests = git("ls-tree", "-r", "--name-only", base, "TinodiosUITests", "TinodeSDKTests").decode().splitlines()
old_swift = [p for p in old_tests if p.endswith(".swift")]
for p in old_swift:
    assert git("show", base + ":" + p).replace(b"\r\n", b"\n") == (root / p).read_bytes().replace(b"\r\n", b"\n"), p
selector = paths[-1]
before = git("show", base + ":" + selector).decode().replace("\r\n", "\n")
after = (root / selector).read_text(encoding="utf-8")
added = "  -only-testing:TinodiosVoiceLayoutTests/AssistantKnownRunTests \\\n"
assert after.count(added) == 1 and after.replace(added, "") == before
pbx = (root / paths[-2]).read_text(encoding="utf-8")
assert pbx.count("C1A090000000000000000001") == 3
assert pbx.count("C1A090000000000000000002") == 2
tests = (root / paths[-3]).read_text(encoding="utf-8")
methods = re.findall(r"func (test\w+)\(", tests)
assert len(methods) == 12 and len(set(methods)) == 12
checks = {
    "base": base, "evidence_level": "Windows source comparison; Swift/native NOT_RUN",
    "old_swift_files_unchanged": len(old_swift), "only_one_selector_added": True,
    "test_target": "TinodiosVoiceLayoutTests", "new_methods": methods,
    "inherited_native_expected": 295, "candidate_native_expected": 307, "navigation_expected": 3,
    "paths": [{"path": p, "bytes": (root / p).stat().st_size,
               "raw_sha256": hashlib.sha256((root / p).read_bytes()).hexdigest()} for p in paths],
}
destination = Path(__file__).with_name("state-source-checks.json")
destination.write_text(json.dumps(checks, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
print(f"PASS: {len(paths)} allowed code paths, {len(old_swift)} old Swift files unchanged, {len(methods)} new methods pending Mac")
