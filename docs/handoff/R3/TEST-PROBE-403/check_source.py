"""Exact source preservation checks, not Swift/VLC execution."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
BASE = "7e12f3b4997bf80bb37629bfca809638f98b41c1"
NAME = "TinodiosUITests/VLCPlaybackProbeTests.swift"
old = subprocess.check_output(["git", "show", BASE + ":" + NAME], cwd=ROOT).decode()
new = (ROOT / NAME).read_text(encoding="utf-8")
checks = {}

def verify(name, value):
    checks[name] = bool(value)
    assert value, name

def method(source, name):
    blocks = re.findall(r"(?ms)^    (?:@discardableResult )?(?:private )?func " + name + r"\([^\n]*\)[^\n]* \{\n.*?^    \}\n", source)
    assert len(blocks) == 1, name
    return blocks[0]

names = re.findall(r"(?m)^    func (test\w+)\(", old)
verify("same_exact_four_methods", names == re.findall(r"(?m)^    func (test\w+)\(", new) and len(names) == 4)
for name in names[:3] + ["decoded", "snapshot", "clip", "readFixture", "cleanup", "validateBaseline", "until"]:
    verify("unchanged_" + name, method(old, name) == method(new, name))
verify("global_terminal_unchanged", re.findall(r"(?m)^    func terminal\(\).*", old) == re.findall(r"(?m)^    func terminal\(\).*", new))
verify("five_second_full_window_and_separate_result_guard", "XCTWaiter.wait(for: [polling], timeout: 5)" in new
       and "NSPredicate { _, _ in sample(); return false }" in new and "guard waited == .timedOut, elapsed >= 5," in new)
verify("request_and_fixture_revision_both_required", '(\u00240["requestSequence"] as? Int ?? 0) > secondCount' in new
       and '\u00240["fixtureRevision"] as? Int == revision' in new)
verify("both_real_write_completions_required", '\u00240["headerWrite"] as? String == "completed" && \u00240["bodyWrite"] as? String == "completed"' in new)
verify("zero_request_zero_frame_not_a_pass", "decodedDespite403 || (completed403 && stoppedOrTerminal)" in new)
verify("both_cache_modes_unchanged", "for cacheable in [false, true]" in new)
verify("failure_keeps_current_case_requests_and_prior_evidence", all(s in new for s in
       ['currentCase["requestsAtFailure"] = server.observations()', '"priorStageEvidence": priorProgress', '"completedCases": results']))
verify("default_player_options_unchanged", method(old, "libraryEvidence") == method(new, "libraryEvidence")
       and new[new.index("    init(url: URL)"):new.index("    static func hostEvidence")]
       == old[old.index("    init(url: URL)"):old.index("    static func hostEvidence")])
changed = subprocess.check_output(["git", "diff", BASE, "--name-only"], cwd=ROOT, text=True).splitlines()
verify("only_one_non_docs_file_changed", [p for p in changed if not p.startswith("docs/")] == [NAME])
result = {"base": BASE, "file": NAME, "rawSHA256": hashlib.sha256((ROOT / NAME).read_bytes()).hexdigest(),
          "normalizedSHA256": hashlib.sha256(new.encode()).hexdigest(), "methods": names,
          "checks": checks, "scope": "Windows source inspection only; Swift/VLC NOT_RUN; no new native methods"}
(HERE / "source-checks.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(f"PASS {len(checks)} source checks; not Swift/VLC execution")
