"""Seal the exact eight-path source unit and actually apply it to an independent index."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
BASE = 'cf63be2'
TARGET = '02e4ebcb54e4aa7451224e7935b8bb78b840c8ba'
PATHS = [
    'Tinodios/ClawAssistantModels.swift', 'Tinodios/ClawAssistantService.swift',
    'Tinodios/ClawAssistantRun.swift', 'Tinodios/ClawAssistantStream.swift',
    'TinodiosUITests/AssistantRunTests.swift', 'TinodiosUITests/AssistantStreamTests.swift',
    'Tinodios.xcodeproj/project.pbxproj', 'Scripts/ci/verify_publish_outcomes_macos.sh',
]

def git(*args, env=None):
    return subprocess.check_output(['git', *args], cwd=ROOT, env=env)

def sha(data):
    return hashlib.sha256(data).hexdigest()

base = git('rev-parse', BASE).decode().strip()
assert set(git('diff', '--name-only', base, TARGET).decode().splitlines()) == set(PATHS)
patch = git('diff', '--binary', '--full-index', '--no-ext-diff', base, TARGET, '--', *PATHS)
patch_path = OUT / 'unit.patch'
patch_path.write_bytes(patch)
index_path = Path(git('rev-parse', '--git-path', 'index').decode().strip())
if not index_path.is_absolute():
    index_path = ROOT / index_path
index_before = sha(index_path.read_bytes())
base_tree = git('ls-tree', '-r', '-z', base)
target_tree = git('ls-tree', '-r', '-z', TARGET)
folder = Path(tempfile.mkdtemp(prefix='claw-ios-b1-forward-'))
env = os.environ.copy()
env['GIT_INDEX_FILE'] = str(folder / 'index')
git('read-tree', base, env=env)
git('apply', '--cached', '--binary', str(patch_path), env=env)
tree = git('write-tree', env=env).decode().strip()
assert tree == git('rev-parse', TARGET + '^{tree}').decode().strip()
assert git('ls-tree', '-r', '-z', tree) == target_tree
assert sha(index_path.read_bytes()) == index_before
def entries(raw):
    return {part.split(b'\t', 1)[1].decode(): part.split(b'\t', 1)[0].decode()
            for part in raw.split(b'\0') if part}
before, after = entries(base_tree), entries(target_tree)
assert all(after.get(path) == value for path, value in before.items() if path not in PATHS)
manifest = []
for path in PATHS:
    blob = git('show', TARGET + ':' + path)
    metadata = after[path].split()
    manifest.append({'path': path, 'mode': metadata[0], 'blob': metadata[2],
                     'bytes': len(blob), 'sha256': sha(blob)})
result = {'baseline': base, 'target_source': TARGET, 'paths': manifest,
          'patch': {'path': 'unit.patch', 'bytes': len(patch), 'sha256': sha(patch)},
          'forward': {'scope': 'real git apply --cached in independent temporary index',
                      'directory': str(folder), 'tree': tree, 'whole_target_tree_matches': True,
                      'unselected_entries_unchanged': True, 'original_index_unchanged': True},
          'new_native_execution': 'NOT_RUN', 'new_native_methods': 20,
          'expected_cumulative_native': 289, 'navigation_separate': 3}
(OUT / 'unit-manifest.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
print(json.dumps({'base': base, 'target': TARGET, 'patch': result['patch'], 'forward_tree': tree}))
