"""Allowlisted code-only Git patch and independent-index forward verification."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[5]
OUT = Path(__file__).resolve().parent
BASE = "0a54fcf1ecb35a6f3511815ed59c7750f692ea2d"
TARGET = "fdedf825490ea9fa420b54033e8c48d65f8fc8aa"

def git(*args, env=None):
    return subprocess.check_output(["git", *args], cwd=ROOT, env=env)

def digest(data):
    return hashlib.sha256(data).hexdigest()

sources = json.loads((OUT.parent / "source-checks.json").read_text(encoding="utf-8"))["sources"]
paths = [row["path"] for row in sources]
assert len(paths) == 13 and len(set(paths)) == 13
assert all(p.startswith(("Tinodios/", "TinodiosUITests/", "Scripts/ci/", "Tinodios.xcodeproj/")) for p in paths)
assert not any(any(word in p.lower() for word in ["sharedutils", "google-service", "runtime", "private", "pods/"]) for p in paths)
actual_scope = git("diff", "--name-only", BASE, TARGET).decode().splitlines()
assert sorted(p for p in actual_scope if not p.startswith("docs/")) == sorted(paths)
index = Path(git("rev-parse", "--path-format=absolute", "--git-path", "index").decode().strip())
before = digest(index.read_bytes())
patch = git("diff", "--binary", "--full-index", BASE, TARGET, "--", *paths)
(OUT / "unit.patch").write_bytes(patch)
work = ROOT / "artifacts" / ("chat-scroll-apply-" + uuid.uuid4().hex)
work.mkdir()
env = os.environ.copy()
env["GIT_INDEX_FILE"] = str(work / "verification.index")
git("read-tree", BASE, env=env)
base_entries = git("ls-files", "--stage", env=env).decode().splitlines()
git("apply", "--cached", "--check", str(OUT / "unit.patch"), env=env)
git("apply", "--cached", str(OUT / "unit.patch"), env=env)
actual_entries = git("ls-files", "--stage", env=env).decode().splitlines()
actual = {line.split("\t", 1)[1]: line.split("\t", 1)[0].split()[:2] for line in actual_entries}
expected = {}
for p in paths:
    record = git("ls-tree", TARGET, "--", p).decode().strip()
    mode, _, blob = record.split("\t")[0].split()
    assert actual[p] == [mode, blob], p
    body = git("show", TARGET + ":" + p)
    expected[p] = {"mode": mode, "gitBlob": blob, "gitBytesSHA256": digest(body), "bytes": len(body)}
before_other = {line for line in base_entries if line.split("\t", 1)[1] not in paths}
after_other = {line for line in actual_entries if line.split("\t", 1)[1] not in paths}
assert before_other == after_other
assert digest(index.read_bytes()) == before
result = {
    "base": BASE, "sourceTarget": TARGET, "patch": {"path": "unit.patch", "sha256": digest(patch), "bytes": len(patch)},
    "paths": expected, "independentIndexForwardApply": "PASS --check then actual --cached apply",
    "unselectedEntriesUnchanged": True, "originalIndexUnchanged": True,
    "resultTree": git("write-tree", env=env).decode().strip(),
    "validation": "Windows packaging/source only; candidate Mac/native NOT_RUN",
    "nativeExpected": {"existing": 232, "new": 10, "total": 242, "navigationSeparate": 3},
    "excluded": ["private configuration", "SharedUtils", "credentials/push/signing", "Pods/build/runtime", "historical WIP", "docs/evidence"],
    "restore": "In an isolated checkout of the exact base with private configuration preserved: git apply --check unit.patch; git apply unit.patch. Verify listed Git blobs/modes before CI. No reset/clean or database deletion.",
    "rollback": "Use preserved base code/checkpoint in a separate checkout; retain the current account database and private configuration. This patch makes no schema changes."
}
(OUT / "unit-package.json").write_bytes((json.dumps(result, indent=2) + "\n").encode("utf-8"))
print(json.dumps({"sha256": result["patch"]["sha256"], "bytes": len(patch), "paths": len(paths), "apply": "PASS"}))
