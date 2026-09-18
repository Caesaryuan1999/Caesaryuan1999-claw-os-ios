#!/usr/bin/env python3
"""Seal inventories/evidence references for the existing forward-apply package format."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
REPORT = Path(__file__).resolve().parent
BASE = "34a8b3e5ad4df210117e2e03b308576796ba55b2"
TARGET = "1b20ec2971061dbc002d1748f0f252d87b69d0f7"


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(name, value):
    (REPORT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def main():
    manifest = json.loads((REPORT / "file-manifest.json").read_text(encoding="utf-8"))
    assert (manifest["baseline"], manifest["target"], manifest["files"]) == (BASE, TARGET, 102)
    assert sha((REPORT / manifest["patch"]).read_bytes()) == manifest["patch_sha256"]
    selectors = re.findall(r"-only-testing:([^\s\\]+)", git("show", TARGET + ":Scripts/ci/verify_publish_outcomes_macos.sh").decode())
    prior = json.loads((ROOT / "docs/handoff/R3/FINAL-E6E07AFF/native-methods.json").read_text())
    sources = {item["class"]: item["methods"][0]["file"] for item in prior["classes"]}
    inventory = []
    for selector in selectors:
        test_target, name = selector.split("/")
        path = sources.get(name, "TinodiosUITests/" + name + ".swift")
        data = git("show", TARGET + ":" + path)
        text = data.decode()
        blocks = list(re.finditer(r"(?ms)^(?:(?:final )?class|extension) " + re.escape(name)
                                  + r"\b[^\n]*\{\n.*?^\}", text))
        assert blocks, name
        methods = [{"name": match[1], "file": path, "line": text[:block.start() + match.start()].count("\n") + 1}
                   for block in blocks for match in re.finditer(r"(?m)^    func (test\w+)\(", block[0])]
        assert methods and len({method["name"] for method in methods}) == len(methods)
        inventory.append({"target": test_target, "class": name, "source_git_sha256": sha(data),
                          "count": len(methods), "methods": methods})
    sdk = sum(item["count"] for item in inventory if item["target"] == "TinodeSDKTests")
    ui = sum(item["count"] for item in inventory if item["target"] == "TinodiosUITests" and item["class"] != "IdentityNavigationUITests")
    vlc = sum(item["count"] for item in inventory if item["target"] == "TinodiosVLCProbeTests")
    voice = sum(item["count"] for item in inventory if item["target"] == "TinodiosVoiceLayoutTests")
    nav = sum(item["count"] for item in inventory if item["class"] == "IdentityNavigationUITests")
    assert (sdk, ui, vlc, voice, nav) == (44, 175, 7, 6, 3)
    write_json("native-methods.json", {"candidate": TARGET, "inventory_only_not_execution": True,
               "native_method_count": sdk + ui + vlc + voice, "sdk": sdk, "ui_runner": ui,
               "vlc_host": vlc, "voice_component_host": voice, "real_app_navigation_separate": nav,
               "classes": inventory})

    dependencies = []
    for path, reason in [
        ("Scripts/ci/fixtures/ios113.sql", "Synthetic nonempty account/attachment SQLite fixture, not user data"),
        ("Scripts/ci/run_static_policies.py", "Preserved source policy entry point"),
        ("Podfile.lock", "Actual target dependency lock; delta IS included in this package"),
    ]:
        original = git("show", BASE + ":" + path)
        target = git("show", TARGET + ":" + path)
        dependencies.append({"path": path, "base_sha256": sha(original), "target_sha256": sha(target),
                             "target_bytes": len(target), "unchanged_from_baseline": original == target,
                             "included_as_patch_delta": path in {item["path"] for item in manifest["manifest"]},
                             "reason": reason})
    write_json("baseline-prerequisites.json", {"baseline": BASE, "target": TARGET, "dependencies": dependencies,
               "not_an_empty_upstream_patch": True, "private_content_read_or_copied": False,
               "configuration": "Retain private baseline configuration locally. CI only uses disabled push placeholder and loopback."})

    workspace = ROOT.parents[1]
    evidence_root = workspace / "artifacts/integration/20260918"
    root_review_path = evidence_root / "R3-ios-ci30-root-review.json"
    review = json.loads(root_review_path.read_text(encoding="utf-8"))
    assert review["sha"] == TARGET and review["run"] == 35361193265
    assert len(review["voice_assets"]) == 38
    assets = []
    for item in review["voice_assets"]:
        path = workspace / item["file"]
        assert path.is_file() and path.stat().st_size == item["bytes"]
        assert sha(path.read_bytes()) == item["sha256"]
        assets.append({key: item[key] for key in ("file", "bytes", "sha256", "test", "name")})
    evidence = evidence_root / "R3-ios-ci30-evidence/ios-01-a-20260918-151503"
    small_files = []
    summaries = {}
    for name, count in [("sdk-summary.json", 44), ("storage-summary.json", 188), ("navigation-summary.json", 3)]:
        path = evidence / name
        data = path.read_bytes()
        value = json.loads(data)
        assert (value["passedTests"], value["failedTests"], value["skippedTests"]) == (count, 0, 0)
        summaries[name] = {key: value[key] for key in ("passedTests", "failedTests", "skippedTests", "startTime", "finishTime", "result")}
        small_files.append({"file": path.relative_to(workspace).as_posix(), "bytes": len(data), "sha256": sha(data)})
    for name in ["simulator-manifest.json", "launch-smoke/manifest.json"]:
        path = evidence / name
        data = path.read_bytes()
        small_files.append({"file": path.relative_to(workspace).as_posix(), "bytes": len(data), "sha256": sha(data)})
    cold = json.loads((evidence / "launch-smoke/manifest.json").read_text())
    assert cold["status"] == "FAIL" and cold["failure"] == "wait_tested_device_boot exceeded 45 seconds"
    assert [item["step"] for item in cold["commands"]] == ["list_existing_devices", "boot_tested_device", "wait_tested_device_boot"]
    archive = evidence_root / "R3-ios-ci30-evidence.zip"
    assert sha(archive.read_bytes()) == review["archive"]["sha256"]
    app = evidence / "CLAW-OS-unsigned-simulator.zip"
    app_sha = sha(app.read_bytes())
    assert app_sha == cold["tested_archive_sha256"]
    write_json("ci30-evidence-index.json", {"target": TARGET, "run": 35361193265, "job": 105652584258,
               "artifact_id": 10554503451, "artifact_bytes": archive.stat().st_size,
               "artifact_sha256": review["archive"]["sha256"], "summaries": summaries,
               "app_zip": {"path": app.relative_to(workspace).as_posix(), "bytes": app.stat().st_size, "sha256": app_sha},
               "cold_launch": {"status": "NOT_RUN: simulator readiness gate failed before install/launch",
                               "bootstatus_timeout_seconds": 45, "bootstatus_elapsed_seconds": 46.685563,
                               "later_state": "Booted only, not readiness evidence", "cause": "Internal bootstatus stage unknown"},
               "small_evidence": small_files,
               "root_review": {"path": root_review_path.relative_to(workspace).as_posix(), "sha256": sha(root_review_path.read_bytes())},
               "voice_assets_verified": assets, "voice_asset_count": len(assets),
               "visual_review": "Parent reviewed original screenshots; packaging only rechecks file hashes, not a new visual/device acceptance",
               "ci31": {"run": 35364243217, "same_target": TARGET, "status_at_packaging": "PENDING parent evidence; one authorized environment rerun"}})

    lineending = sum(item["target_git_sha256"] != item["target_worktree_sha256"] for item in manifest["manifest"])
    write_json("packaging-checks.json", {"baseline": BASE, "target": TARGET,
               "latest_production_commit": "603476bf93b652821af7f83afdba00bb023c3cf4",
               "source_range_diff_check": "PASS", "actual_forward_apply": "PASS",
               "real_baseline_entries": manifest["full_real_baseline_entry_count"], "mode_blob_sha_matches": "102/102",
               "unselected_entries_unchanged": True, "real_current_index_unchanged": True,
               "private_blob_read_or_checkout": False, "production_ci_tests_modified_by_packaging": False,
               "native_inventory": {"sdk": sdk, "ui_runner": ui, "vlc": vlc, "voice": voice, "total": 232, "navigation_separate": nav},
               "native_execution": "CI30 exact target 232 native + 3 navigation PASS; package PASS; cold NOT_RUN due boot readiness timeout; CI31 pending",
               "lineending_worktree_sha_differences": lineending,
               "raw_patch_artifact_note": "Native Git patch context whitespace is preserved; source-range diff --check passed",
               "packaging_first_stage_check": "Windows-generated metadata CRLF forced as raw staged blobs caused whitespace check failure; metadata only normalized to LF and restaged. Patch/source bytes unchanged.",
               "prior_packages_preserved": True, "prior_failure_evidence_preserved": True})
    lines = ["operation\tpath\tmode\ttarget_git_blob\ttarget_git_sha256\tbytes"]
    lines += ["\t".join(str(item[key]) for key in ("operation", "path", "target_mode", "target_blob", "target_git_sha256", "target_bytes"))
              for item in manifest["manifest"]]
    (REPORT / "paths.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    hashes = [{"file": path.name, "bytes": path.stat().st_size, "sha256": sha(path.read_bytes())}
              for path in sorted(REPORT.iterdir()) if path.is_file() and path.name != "bundle-hashes.json"]
    write_json("bundle-hashes.json", {"baseline": BASE, "source_target": TARGET, "files": hashes})
    print(json.dumps({"entities": len(hashes), "patch_sha256": manifest["patch_sha256"],
                      "bundle_sha256": sha((REPORT / "bundle-hashes.json").read_bytes()),
                      "native": [sdk, ui, vlc, voice], "navigation_separate": nav}))


if __name__ == "__main__":
    main()
