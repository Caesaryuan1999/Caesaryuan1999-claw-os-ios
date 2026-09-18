from pathlib import Path
import hashlib
import json
import re
import subprocess

root = Path(__file__).resolve().parents[4]
path = "TinodiosUITests/VLCPlaybackProbeTests.swift"
base = "49194cc56f5c1dfd894efd9a9be6877560e219d3"
before = subprocess.check_output(["git", "show", base + ":" + path], cwd=root).decode().replace("\r\n", "\n")
after = (root / path).read_text(encoding="utf-8")
checks = []


def check(name, value):
    checks.append({"name": name, "pass": bool(value)})
    assert value, name


def method(text, name):
    match = re.search(r"^    (?:@discardableResult )?(?:private )?func " + re.escape(name) + r"\b", text, re.M)
    assert match, name
    start = match.start()
    brace = text.index("{", match.end())
    depth, end = 1, brace + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


selected = re.search(r"(?ms)^final class VLCPlaybackProbeTests: XCTestCase \{\n.*?^\}", after)[0]
check("all seven methods remain in the selected XCTestCase", len(re.findall(r"^    func test", selected, re.M)) == 7)
changed_tests = {"testRealVLCReopenChangedContentAnd403RecordsCacheAndCookieBehavior",
                 "testLocalPlaylistExternalReferenceRecordsRealVLCNetworkBehavior"}
for name in re.findall(r"^    func (test\w+)\(", before, re.M):
    if name not in changed_tests:
        check(name + " byte-identical body", method(before, name) == method(after, name))
for name in ["until", "cleanup", "clip", "readFixture", "decoded", "snapshot", "ownedFixture", "ownedLease", "closeOwned"]:
    check(name + " unchanged", method(before, name) == method(after, name))
check("HTTP source and actual player unchanged", before[:before.index("final class VLCPlaybackProbeTests")] == after[:after.index("final class VLCPlaybackProbeTests")])
check("monotonic five-second absolute deadline", "let absoluteDeadline = started + 5" in after and "let remaining = absoluteDeadline - current" in after)
check("strict minimum and whole-method budget", "elapsed >= 5 && remainingBudget() >= 0" in after and "guard remainingBudget() >= remaining" in after)
check("maximum eight segments", "for _ in 0..<8" in after)
check("only legal timeout may be supplemented", 'guard result == .timedOut else { reason = "wait_rejected"' in after)
check("four same-helper controlled cases", all(token in after for token in ["let supplemented = observeFullWindow", "let normal = observeFullWindow", "let noProgress = observeFullWindow", "let interrupted = observeFullWindow"]))
check("controlled cases actually invoked", "verifyObservationDeadlineBoundaries()" in method(after, "testRealVLCReopenChangedContentAnd403RecordsCacheAndCookieBehavior"))
check("both actual observation windows use same helper", all("observeFullWindow(started:" in method(after, name) for name in changed_tests))
check("response and frame condition retained", "decodedDespite403 || (completed403 && stoppedOrTerminal)" in after)
check("original response evidence binding retained", '($0["requestSequence"] as? Int ?? 0) > secondCount' in after and '$0["fixtureRevision"] as? Int == revision' in after)
check("new safe timing evidence", all(token in after for token in ['"elapsedMicroseconds"', '"waitCategories"', '"deadlineReached"', '"supplementalWaits"']))
check("production files untouched", subprocess.run(["git", "diff", "--quiet", base, "--", "Tinodios/VideoPreviewController.swift", "Tinodios/ClawSecondaryUIState.swift"], cwd=root).returncode == 0)
data = {"level": "Windows source checks only; four controlled Swift cases and live VLC NOT_RUN",
        "base": base, "sourceSHA256": hashlib.sha256((root/path).read_bytes()).hexdigest(),
        "checks": checks, "nativeMethodsUnchanged": {"sdk": 44, "uiRunner": 175, "vlcHost": 7, "total": 226, "navigationSeparate": 3}}
(Path(__file__).parent / "source-checks.json").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(f"Deadline source checks {len(checks)}/{len(checks)}; native226+navigation3 still NOT_RUN")
