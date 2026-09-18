#!/usr/bin/env python3
"""Verify the sealed patch against a real preserved Git baseline in a temporary index."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
REPORT = Path(__file__).resolve().parent
BASE = "34a8b3e5ad4df210117e2e03b308576796ba55b2"
TARGET = "1b20ec2971061dbc002d1748f0f252d87b69d0f7"
PATCH = REPORT / "CLAW-IOS-R3-source-test-ci.patch"
EXTRA = {
    "docs/handoff/R3/CI-SMOKE/check_smoke_runner.py",
    "docs/handoff/R3/LOCAL-DELETE/check_local_delete_sqlite.py",
    "docs/handoff/R3/LOCAL-DELETE-PLAN/reproduce_partial_delete.py",
    "docs/handoff/R3/CI21-CONFIG-01/verify_real_config.rb",
}

def sha(data):
    return hashlib.sha256(data).hexdigest()

def git(*args, env=None):
    run = subprocess.run(["git", *args], cwd=ROOT, env=env,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if run.returncode:
        raise RuntimeError(run.stderr.decode("utf-8", errors="replace"))
    return run.stdout

def tree(ref):
    records = {}
    for entry in git("ls-tree", "-r", "-z", ref).split(b"\0"):
        if not entry:
            continue
        metadata, path = entry.split(b"\t", 1)
        mode, kind, oid = metadata.decode().split()
        records[path.decode()] = {"mode": mode, "kind": kind, "oid": oid}
    return records

def stage(env):
    records = {}
    for entry in git("ls-files", "--stage", "-z", env=env).split(b"\0"):
        if not entry:
            continue
        metadata, path = entry.split(b"\t", 1)
        mode, oid, level = metadata.decode().split()
        assert level == "0", "Unmerged temporary index"
        records[path.decode()] = {"mode": mode, "kind": "blob", "oid": oid}
    return records

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--generate", action="store_true", help="Generate the exact native Git patch first")
    args = parser.parse_args()
    paths = [item["path"] for item in json.loads((REPORT / "allowlist.json").read_text(encoding="utf-8"))]
    assert len(paths) == len(set(paths)) == 102
    for path in paths:
        assert not Path(path).is_absolute() and ".." not in Path(path).parts
        assert not any(word in path.lower() for word in (
            "sharedutils.swift", "__pycache__", ".runtime", "client-private", "googleservice",
            "google-service", ".p12", ".mobileprovision", "pods/", "build/", ".pem", ".key"))
    changed = [p.decode() for p in git("diff", "--no-renames", "--name-only", "-z", BASE, TARGET).split(b"\0") if p]
    non_docs = {p for p in changed if not p.startswith("docs/")}
    assert set(paths) == non_docs | EXTRA, "Missing or unreviewed non-docs delta"
    assert not (EXTRA - set(changed))
    git("diff", "--quiet", TARGET, "--", *paths)
    prior_tree, final_tree = tree(BASE), tree(TARGET)
    assert all(final_tree[p]["kind"] == "blob" and final_tree[p]["mode"] in ("100644", "100755") for p in paths)

    expected_patch = git("diff", "--binary", "--full-index", "--no-ext-diff", "--no-textconv",
                         "--no-renames", "--src-prefix=a/", "--dst-prefix=b/", BASE, TARGET, "--", *paths)
    if args.generate:
        PATCH.write_bytes(expected_patch)
    assert PATCH.read_bytes() == expected_patch, "Patch is not the exact sealed Git delta"
    git("diff", "--check", BASE, TARGET, "--", *paths)

    current_index_path = Path(git("rev-parse", "--git-path", "index").decode().strip())
    if not current_index_path.is_absolute():
        current_index_path = ROOT / current_index_path
    current_index_before = sha(current_index_path.read_bytes())
    fixtures = REPORT / ".index-fixtures"
    fixtures.mkdir(exist_ok=True)
    manifest = []
    with tempfile.TemporaryDirectory(prefix="forward-", dir=fixtures) as name:
        sandbox = Path(name).resolve()
        assert sandbox.is_relative_to(REPORT.resolve()) and sandbox != REPORT.resolve()
        env = os.environ.copy()
        env["GIT_INDEX_FILE"] = str(sandbox / "index")
        # Real full baseline tree; no empty upstream, no private file checkout or blob read.
        git("read-tree", BASE, env=env)
        assert stage(env) == prior_tree
        git("apply", "--cached", "--check", str(PATCH), env=env)
        git("apply", "--cached", "--whitespace=nowarn", str(PATCH), env=env)
        applied = stage(env)
        expected = prior_tree.copy()
        for path in paths:
            expected[path] = final_tree[path]
        assert applied == expected, "Applied index changed unselected baseline entries"
        applied_tree = git("write-tree", env=env).decode().strip()
        for path in paths:
            old = prior_tree.get(path)
            target = final_tree[path]
            actual = applied[path]
            # Only explicit safe allowlist blobs are read.
            prior_bytes = git("cat-file", "blob", old["oid"]) if old else None
            final_bytes = git("cat-file", "blob", target["oid"])
            applied_bytes = git("cat-file", "blob", actual["oid"])
            assert actual == target and applied_bytes == final_bytes
            manifest.append({
                "path": path, "operation": "modify" if old else "add",
                "base_mode": old["mode"] if old else None, "base_blob": old["oid"] if old else None,
                "base_sha256": sha(prior_bytes) if prior_bytes is not None else None,
                "target_mode": target["mode"], "target_blob": target["oid"],
                "target_bytes": len(final_bytes), "target_git_sha256": sha(final_bytes),
                "target_worktree_sha256": sha((ROOT / path).read_bytes()),
                "applied_mode": actual["mode"], "applied_blob": actual["oid"],
                "applied_sha256": sha(applied_bytes), "match": True,
            })
    fixtures.rmdir()
    assert sha(current_index_path.read_bytes()) == current_index_before, "Current index changed"
    result = {
        "baseline": BASE, "target": TARGET, "baseline_tree": git("rev-parse", BASE + "^{tree}").decode().strip(),
        "applied_safe_tree": applied_tree,
        "patch": PATCH.name, "patch_sha256": sha(PATCH.read_bytes()), "patch_bytes": PATCH.stat().st_size,
        "files": len(paths), "modified": sum(x["operation"] == "modify" for x in manifest),
        "added": sum(x["operation"] == "add" for x in manifest),
        "full_real_baseline_entry_count": len(prior_tree),
        "unselected_entries_unchanged": True, "current_index_unchanged": True,
        "private_blobs_read_or_checked_out": False,
        "validation": "read-tree real BASE in GIT_INDEX_FILE; actual forward apply --cached --check and apply --cached; full index compared",
        "line_endings": "Patch and apply hash use Git blob bytes; worktree SHA retained separately, never normalized into patch",
        "manifest": manifest,
    }
    (REPORT / "file-manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    scope = {
        "baseline": BASE, "target": TARGET, "included_non_docs": len(non_docs), "included_docs_tests": sorted(EXTRA),
        "excluded_changed": [{"path": p, "reason": "report/evidence/previous package, not required source"} for p in changed if p not in paths],
        "unchanged_private_metadata_check": {
            "SharedUtils_no_delta": not any("SharedUtils.swift" in p for p in changed),
            "content_not_read": True,
        },
        "excluded_categories": ["private configuration", "real push configuration", "signing/key material", "Pods/build/runtime",
                                "screenshots/xcresult/downloaded artifacts", "generated evidence and prior patches"],
    }
    (REPORT / "scope-review.json").write_text(json.dumps(scope, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    (REPORT / "commits.tsv").write_bytes(git("log", "--reverse", "--format=%H%x09%s", BASE + ".." + TARGET))
    print(json.dumps({k: result[k] for k in ("baseline", "target", "patch_sha256", "patch_bytes", "files", "modified", "added",
                                             "unselected_entries_unchanged", "current_index_unchanged")}))

if __name__ == "__main__":
    main()
