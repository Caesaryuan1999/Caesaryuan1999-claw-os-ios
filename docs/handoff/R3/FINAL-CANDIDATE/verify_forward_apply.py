#!/usr/bin/env python3
"""Rebuild only safe changed baseline files and apply the cumulative patch in a disposable repository."""
from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
REPORT = Path(__file__).resolve().parent
BASE = "34a8b3e5ad4df210117e2e03b308576796ba55b2"
TARGET = "f3043d923aa0f0c996b6a2967a9d2c33acefb435"
PATCH = REPORT / "CLAW-IOS-R3-source-test-ci.patch"
PREFIXES = (".github/workflows/", "Scripts/ci/", "TinodeSDK/", "Tinodios/", "TinodiosDB/",
            "TinodiosUITests/", "Tinodios.xcodeproj/")


def git(*args, cwd=ROOT, data=None):
    result = subprocess.run(["git", *args], cwd=cwd, input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace"))
    return result.stdout


def blob(ref, path):
    tree = git("ls-tree", ref, "--", path)
    if not tree:
        return None
    mode, _, oid = tree.split(b"\t", 1)[0].decode().split()
    return {"mode": mode, "oid": oid, "bytes": git("cat-file", "blob", oid)}


def main():
    paths = [x.decode() for x in git("diff", "--no-renames", "--name-only", "-z", BASE, TARGET).split(b"\0") if x]
    selected = []
    for path in paths:
        allowed = path in ("Podfile", "Podfile.lock") or path.startswith(PREFIXES)
        forbidden = any(word in path.lower() for word in
                        ("sharedutils.swift", "__pycache__", "runtime", "client-private",
                         "google-service", ".p12", ".mobileprovision"))
        if allowed and not forbidden:
            selected.append(path)
    assert len(selected) == 55
    git("diff", "--quiet", TARGET, "--", *selected)
    expected_patch = git("diff", "--binary", "--full-index", "--no-ext-diff", "--no-renames",
                         BASE, TARGET, "--", *selected)
    assert PATCH.read_bytes() == expected_patch, "Patch differs from the sealed source range"
    manifest = []
    staging_parent = REPORT / ".apply-fixtures"
    staging_parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="forward-", dir=staging_parent) as name:
        staging = Path(name).resolve()
        # Verify the disposable directory stays under this exact handoff directory before cleanup.
        assert staging.is_relative_to(REPORT.resolve()) and staging != REPORT.resolve()
        git("init", "--quiet", cwd=staging)
        git("config", "core.autocrlf", "false", cwd=staging)
        git("config", "core.filemode", "false", cwd=staging)
        for path in selected:
            prior = blob(BASE, path)
            if not prior:
                continue
            destination = staging / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(prior["bytes"])
            oid = git("hash-object", "-w", "--stdin", cwd=staging, data=prior["bytes"]).decode().strip()
            git("update-index", "--add", "--cacheinfo", prior["mode"], oid, path, cwd=staging)
        # cacheinfo intentionally starts without worktree stat data; refresh before --index validation.
        git("update-index", "--refresh", cwd=staging)
        git("apply", "--check", "--index", str(PATCH), cwd=staging)
        git("apply", "--index", str(PATCH), cwd=staging)
        for path in selected:
            prior, final = blob(BASE, path), blob(TARGET, path)
            destination = staging / path
            index = git("ls-files", "--stage", "--", path, cwd=staging).split(b"\t", 1)[0].decode().split()
            if final:
                actual = destination.read_bytes()
                assert actual == final["bytes"], path
                assert index[0] == final["mode"] and index[1] == final["oid"], path
                manifest.append({
                    "path": path, "operation": "modify" if prior else "add",
                    "base_sha256": hashlib.sha256(prior["bytes"]).hexdigest() if prior else None,
                    "target_git_blob_sha256": hashlib.sha256(final["bytes"]).hexdigest(),
                    "target_worktree_sha256": hashlib.sha256((ROOT / path).read_bytes()).hexdigest(),
                    "applied_sha256": hashlib.sha256(actual).hexdigest(),
                    "git_mode": final["mode"], "git_blob_oid": final["oid"], "forward_apply_match": True,
                })
            else:
                assert not destination.exists() and not index
                manifest.append({"path": path, "operation": "delete", "forward_apply_match": True})
    staging_parent.rmdir()
    result = {
        "base_commit": BASE, "source_commit": TARGET,
        "patch_sha256": hashlib.sha256(PATCH.read_bytes()).hexdigest(),
        "files": len(manifest), "new_files": sum(x["operation"] == "add" for x in manifest),
        "validation": "actual git apply --check --index, then git apply --index; all SHA256 and Git modes/blob OIDs match",
        "line_endings": "patch and SHA comparison use sealed Git bytes; Windows worktree SHA retained separately",
        "private_configuration_included": False,
        "excluded_changed_path_count": len(paths) - len(selected),
        "manifest": manifest,
    }
    (REPORT / "file-manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    commits = git("log", "--reverse", "--format=%H%x09%s", BASE + ".." + TARGET).decode("utf-8")
    (REPORT / "commits.tsv").write_text(commits, encoding="utf-8", newline="\n")
    print(json.dumps({key: result[key] for key in ("source_commit", "patch_sha256", "files", "new_files", "validation")}))


if __name__ == "__main__":
    main()
