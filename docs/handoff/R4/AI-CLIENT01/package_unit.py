"""Safe 13-path unit export and real forward application in a private index.

No original index mutation, checkout, private source read, build or remote action.
"""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
BASE = 'd21d69fcd69ecc5946df2cad134bddef98a24a96'
TARGET = 'f3640f69171490c8278796e8026ae1fdb32058ed'
checks = json.loads((OUT / 'source-checks.json').read_text(encoding='utf-8'))
paths = [entry['path'] for entry in checks['files']]
assert len(paths) == 13 and len(set(paths)) == 13

def git(*args, env=None):
    return subprocess.check_output(['git', *args], cwd=ROOT, env=env)

changed = git('diff', '--name-only', BASE, TARGET).decode().splitlines()
assert set(changed) == set(paths)
patch = git('diff', '--binary', '--full-index', '--no-ext-diff', BASE, TARGET, '--', *paths)
(OUT / 'unit.patch').write_bytes(patch)
manifest = []
for path in paths:
    entry = git('ls-tree', TARGET, '--', path).decode().strip()
    mode, _, blob = entry.split('\t')[0].split()
    raw = git('show', TARGET + ':' + path)
    manifest.append({'path': path, 'mode': mode, 'blob': blob, 'bytes': len(raw),
                     'git_bytes_sha256': hashlib.sha256(raw).hexdigest()})
index_path = Path(git('rev-parse', '--git-path', 'index').decode().strip())
if not index_path.is_absolute():
    index_path = ROOT / index_path
original_index = hashlib.sha256(index_path.read_bytes()).hexdigest()
temp = Path(tempfile.mkdtemp(prefix='claw-ai-a-forward-'))
env = dict(os.environ, GIT_INDEX_FILE=str(temp / 'index'))
git('read-tree', BASE, env=env)
before = git('ls-files', '--stage', '-z', env=env)
git('apply', '--cached', '--check', str(OUT / 'unit.patch'), env=env)
git('apply', '--cached', str(OUT / 'unit.patch'), env=env)
after = git('ls-files', '--stage', '-z', env=env)
actual_tree = git('write-tree', env=env).decode().strip()
target_tree = git('rev-parse', TARGET + '^{tree}').decode().strip()
assert actual_tree == target_tree
assert hashlib.sha256(index_path.read_bytes()).hexdigest() == original_index
# Also materialize only the approved safe source paths and verify their Git bytes.
for entry in manifest:
    path = entry['path']
    source = temp / 'source' / path
    source.parent.mkdir(parents=True, exist_ok=True)
    raw = git('show', ':' + path, env=env)
    source.write_bytes(raw)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == entry['git_bytes_sha256']
(OUT / 'manifest.json').write_text(json.dumps({'base': BASE, 'target': TARGET, 'paths': manifest},
    ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
(OUT / 'forward-checks.json').write_text(json.dumps({
    'base': BASE, 'target': TARGET, 'scope': 'Git source recovery only; native NOT_RUN',
    'path_count': len(paths), 'actual_apply': True, 'mode_blob_all_tree_match': actual_tree == target_tree,
    'tree': actual_tree, 'base_index_entries': len(before.split(b'\0')) - 1,
    'target_index_entries': len(after.split(b'\0')) - 1,
    'original_index_sha256_before_after': original_index, 'original_index_unchanged': True,
    'safe_materialized_sha_match': len(manifest), 'private_index_directory': str(temp),
    'patch_bytes': len(patch), 'patch_sha256': hashlib.sha256(patch).hexdigest(),
}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
print(f'PASS: 13-path forward apply; tree {actual_tree}; patch {len(patch)} bytes SHA {hashlib.sha256(patch).hexdigest()}')
