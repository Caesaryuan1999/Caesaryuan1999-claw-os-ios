"""Stage only named handoff artifacts and prove staged bytes equal preserved raw bytes."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
B = 'docs/handoff/R4/AI-CLIENT-B01/'
PATHS = [B + name for name in [
    'REPORT.md', 'a-page-order.patch', 'b-successor.patch', 'check_project.rb',
    'check_sources.py', 'check_successor.py', 'core-title.patch', 'project-check.json',
    'seal_successors.py', 'seal_unit.py', 'seal_docs.py', 'source-checks.json',
    'static-policies.json', 'successor-manifests.json', 'successor-source-checks.json',
    'successor-static-policies.json', 'unit-manifest.json', 'unit.patch', 'wire_project.py',
]] + [
    'docs/handoff/R4/AI-CLIENT01/CI38-PAGE-ORDER.md',
    'docs/handoff/R4/UI-CORE01/CI38-TITLE-FIX.md',
    'docs/handoff/R4/UI-CORE01/CI38-title-checks.json',
    'docs/handoff/R4/UI-CORE01/CI38-title-static.json',
    'docs/handoff/R4/UI-CORE01/check_ci38_title.py',
]

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

allowed = set(PATHS + [B + 'bundle-hashes.json'])
assert set(git('diff', '--name-only').decode().splitlines()) <= allowed, 'Do not seal while source is dirty'
assert set(git('diff', '--cached', '--name-only').decode().splitlines()) <= allowed, 'Do not mix unrelated staged changes'
assert git('rev-parse', 'HEAD').decode().strip() == 'b004af0d5c5d8ce2f7560fad04ed8711694c8e23'
entities = []
for path in PATHS:
    data = (ROOT / path).read_bytes()
    data.decode('utf-8')
    entities.append({'path': path, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                     'crlf': data.count(b'\r\n'), 'lone_lf': data.count(b'\n') - data.count(b'\r\n')})
manifest = B + 'bundle-hashes.json'
(ROOT / manifest).write_text(json.dumps({'source': 'b004af0d5c5d8ce2f7560fad04ed8711694c8e23',
    'scope': 'Named handoff artifacts, original patch/evidence bytes preserved', 'entities': entities}, indent=2) + '\n',
    encoding='utf-8', newline='\n')
paths = PATHS + [manifest]
git('-c', 'core.autocrlf=false', 'add', '--', *paths)
assert set(git('diff', '--cached', '--name-only').decode().splitlines()) == set(paths)
for path in paths:
    assert git('show', ':' + path) == (ROOT / path).read_bytes(), path
text_paths = [path for path in paths if not path.endswith('.patch')]
# Preserve Windows-generated evidence CRLF bytes; recognize CR as the line ending,
# while retaining the ordinary trailing-whitespace checks. Raw patches are artifacts.
git('-c', 'core.whitespace=blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol',
    'diff', '--cached', '--check', '--', *text_paths)
print(json.dumps({'docs_staged': len(paths), 'raw_equals_index': True,
                  'bundle_hashes_sha256': hashlib.sha256((ROOT / manifest).read_bytes()).hexdigest()}))
