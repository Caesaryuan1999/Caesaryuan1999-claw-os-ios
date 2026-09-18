"""Keep the initial package; export/replay the three narrowly approved successors."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
BASE = 'f3640f69171490c8278796e8026ae1fdb32058ed'
TARGET = '6a0e8584ff9f135528f4832184eb92b3f0eeb9a3'
STEPS = [
    ('9a6f8153a6b7b7314a2abb1ee43749beabe6ad11', ['TinodiosUITests/CoreListLayoutTests.swift']),
    ('f586434c8d8145db00c623c78028ff48a41a0603', ['Tinodios/ClawAssistantService.swift',
       'Tinodios/ClawAssistantModels.swift', 'TinodiosUITests/AssistantHistoryTests.swift']),
    ('6a0e8584ff9f135528f4832184eb92b3f0eeb9a3', ['Tinodios/ClawAssistantHistoryViewController.swift',
       'TinodiosUITests/AssistantLayoutTests.swift'])]

def git(*args, env=None):
    return subprocess.check_output(['git', *args], cwd=ROOT, env=env)

def entries(commit):
    result = {}
    for row in git('ls-tree', '-r', '-z', commit).split(b'\0'):
        if row:
            head, path = row.split(b'\t', 1)
            result[path.decode()] = head.decode()
    return result

index = Path(git('rev-parse', '--git-path', 'index').decode().strip())
if not index.is_absolute(): index = ROOT / index
index_hash = hashlib.sha256(index.read_bytes()).hexdigest()
env = dict(os.environ, GIT_INDEX_FILE=str(Path(tempfile.mkdtemp(prefix='claw-ai-review-followup-')) / 'index'))
git('read-tree', BASE, env=env)
reports, selected = [], set()
for commit, paths in STEPS:
    assert set(git('diff', '--name-only', commit + '^', commit).decode().splitlines()) == set(paths)
    patch = git('diff', '--binary', '--full-index', '--no-ext-diff', commit + '^', commit, '--', *paths)
    output = OUT / ('successor-' + commit[:7] + '.patch')
    output.write_bytes(patch)
    git('apply', '--cached', '--check', str(output), env=env)
    git('apply', '--cached', str(output), env=env)
    git('diff', '--check', commit + '^', commit)
    reports.append({'commit': commit, 'paths': paths, 'patch': output.name, 'bytes': len(patch),
                    'sha256': hashlib.sha256(patch).hexdigest(), 'forward_apply': True})
    selected.update(paths)
tree = git('write-tree', env=env).decode().strip()
base, target, actual = entries(BASE), entries(TARGET), entries(tree)
assert actual == {**base, **{path: target[path] for path in selected}}
assert hashlib.sha256(index.read_bytes()).hexdigest() == index_hash
assert git('diff', '--name-only', BASE, TARGET, '--', 'TinodeSDK', 'TinodiosDB', 'Podfile', 'Podfile.lock', '.github', 'Scripts/ci/verify_publish_outcomes_macos.sh') == b''
counts = {}
method_names = {}
for name, expected in [('CoreListLayoutTests', 6), ('AssistantHistoryTests', 15), ('AssistantLayoutTests', 6)]:
    path = 'TinodiosUITests/' + name + '.swift'
    old, new = git('show', BASE + ':' + path).decode(), git('show', TARGET + ':' + path).decode()
    assert all(line in new for line in old.splitlines() if 'XCTAssert' in line)
    method_names[name] = re.findall(r'^    func (test[A-Za-z0-9_]+)\(', new, re.M)
    counts[name] = len(method_names[name])
    assert counts[name] == expected
report = {'base': BASE, 'target': TARGET, 'level': 'source/Git recovery only; native NOT_RUN',
          'steps': reports, 'all_selected_mode_blob_match': True, 'unselected_base_entries_unchanged': True,
          'source_overlay_tree': tree, 'original_index_unchanged': True, 'original_index_sha256': index_hash,
          'method_counts': counts, 'method_names': method_names, 'old_assertion_lines_retained': True,
          'changed_inputs': [{'path': path, 'mode_type_blob': target[path],
              'git_bytes_sha256': hashlib.sha256(git('show', TARGET + ':' + path)).hexdigest()}
              for path in sorted(selected)],
          'new_assistant_methods': 21, 'cumulative_native_expected': 269, 'navigation_expected': 3}
(OUT / 'successor-checks.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n',
                                        encoding='utf-8', newline='\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
