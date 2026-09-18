"""Seal three separately committed fixes without changing the original B1 package."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
UNITS = [
    ('a-page-order', '02e4ebcb54e4aa7451224e7935b8bb78b840c8ba',
     '3cb55192054a12707a00cac6de8b8f21e3fc4521', ['TinodiosUITests/AssistantHistoryTests.swift']),
    ('b-successor', '3cb55192054a12707a00cac6de8b8f21e3fc4521',
     'e9eba400129c734315e8176d00e5b2a52e2bc74f', [
         'Tinodios/ClawAssistantModels.swift', 'Tinodios/ClawAssistantService.swift',
         'Tinodios/ClawAssistantRun.swift', 'Tinodios/ClawAssistantStream.swift',
         'TinodiosUITests/AssistantRunTests.swift', 'TinodiosUITests/AssistantStreamTests.swift']),
    ('core-title', 'e9eba400129c734315e8176d00e5b2a52e2bc74f',
     'b004af0d5c5d8ce2f7560fad04ed8711694c8e23', [
         'Tinodios/widgets/ChatListViewCell.swift', 'TinodiosUITests/CoreListLayoutTests.swift']),
]

def git(*args, env=None):
    return subprocess.check_output(['git', *args], cwd=ROOT, env=env)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def entries(tree):
    return {item.split(b'\t', 1)[1].decode(): item.split(b'\t', 1)[0].decode()
            for item in git('ls-tree', '-r', '-z', tree).split(b'\0') if item}

index = Path(git('rev-parse', '--git-path', 'index').decode().strip())
if not index.is_absolute():
    index = ROOT / index
index_before = sha(index.read_bytes())
results = []
for name, base, target, paths in UNITS:
    changed = git('diff', '--name-only', base, target).decode().splitlines()
    assert set(changed) == set(paths), (name, changed)
    patch = git('diff', '--binary', '--full-index', '--no-ext-diff', base, target, '--', *paths)
    patch_path = OUT / (name + '.patch')
    patch_path.write_bytes(patch)
    directory = Path(tempfile.mkdtemp(prefix='claw-ios-' + name + '-'))
    env = os.environ.copy()
    env['GIT_INDEX_FILE'] = str(directory / 'index')
    git('read-tree', base, env=env)
    git('apply', '--cached', '--binary', str(patch_path), env=env)
    tree = git('write-tree', env=env).decode().strip()
    assert tree == git('rev-parse', target + '^{tree}').decode().strip()
    before, after = entries(base), entries(target)
    assert entries(tree) == after
    assert all(after.get(path) == value for path, value in before.items() if path not in paths)
    manifest = []
    for path in paths:
        data = git('show', target + ':' + path)
        mode, _, blob = after[path].split()
        manifest.append({'path': path, 'mode': mode, 'blob': blob, 'bytes': len(data), 'sha256': sha(data)})
    results.append({'name': name, 'baseline': base, 'target_source': target, 'paths': manifest,
                    'patch': {'path': patch_path.name, 'bytes': len(patch), 'sha256': sha(patch)},
                    'forward_apply': {'independent_index_directory': str(directory), 'tree': tree,
                                      'whole_tree_matches': True, 'unselected_entries_unchanged': True}})
assert sha(index.read_bytes()) == index_before
report = {'scope': 'Actual Git forward application; not compilation or native execution',
          'original_index_unchanged': True, 'units': results,
          'final_source': UNITS[-1][2], 'native_execution': 'NOT_RUN',
          'expected_native': 293, 'navigation_separate': 3}
(OUT / 'successor-manifests.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
print(json.dumps({'units': [{k: value[k] for k in ['name', 'patch']} for value in results],
                  'whole_tree_forward_apply': True, 'original_index_unchanged': True}))
