"""Bounded Git/source checks only. Does not execute Swift or model/network tests."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BASE = 'cf63be2'
ALLOWED = [
    'Tinodios/ClawAssistantModels.swift', 'Tinodios/ClawAssistantService.swift',
    'Tinodios/ClawAssistantRun.swift', 'Tinodios/ClawAssistantStream.swift',
    'TinodiosUITests/AssistantRunTests.swift', 'TinodiosUITests/AssistantStreamTests.swift',
    'Tinodios.xcodeproj/project.pbxproj', 'Scripts/ci/verify_publish_outcomes_macos.sh',
]
def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

changed = git('diff', '--cached', '--name-only', BASE).decode().splitlines()
assert set(changed) == set(ALLOWED), changed
script = ALLOWED[-1]
old = git('show', f'{BASE}:{script}').decode()
new = git('show', ':' + script).decode()
selectors = ''.join(f'  -only-testing:TinodiosVoiceLayoutTests/{name} \\\n'
                    for name in ['AssistantRunTests', 'AssistantStreamTests'])
assert selectors in new and new.replace(selectors, '', 1) == old
old_tests = git('ls-tree', '-r', '--name-only', BASE, 'TinodiosUITests', 'TinodeSDKTests').decode().splitlines()
old_tests = [name for name in old_tests if name.endswith('.swift')]
for name in old_tests:
    assert git('show', f'{BASE}:{name}') == git('show', ':' + name), name
frozen = ['Tinodios/ClawAssistantSession.swift', 'Tinodios/ClawAssistantHistory.swift',
          'Tinodios/ClawAssistantViewController.swift', 'Tinodios/ClawAssistantHistoryViewController.swift',
          'Tinodios/ClawAssistantConversationViewController.swift', 'Tinodios/Cache.swift',
          'Podfile', 'Podfile.lock', '.github/workflows/ios-smoke.yml']
for name in frozen:
    assert git('show', f'{BASE}:{name}') == git('show', ':' + name), name
methods = {}
for name in ALLOWED[4:6]:
    source = git('show', ':' + name).decode()
    methods[name] = re.findall(r'func (test\w+)\(', source)
assert [len(value) for value in methods.values()] == [14, 6]
inputs = [{'path': name, 'blob': git('rev-parse', ':' + name).decode().strip(),
           'git_sha256': hashlib.sha256(git('show', ':' + name)).hexdigest(),
           'raw_sha256': hashlib.sha256((ROOT / name).read_bytes()).hexdigest()} for name in ALLOWED]
result = {'evidence_level': 'Windows source/Git checks, not Swift execution',
          'baseline': git('rev-parse', BASE).decode().strip(), 'exact_staged_paths': changed,
          'old_swift_tests_byte_unchanged': old_tests, 'frozen_files_byte_unchanged': frozen,
          'ci_delta_only_two_selectors': True, 'new_methods': methods, 'inputs': inputs,
          'native_expected': {'inherited': 269, 'new': 20, 'total': 289, 'navigation_separate': 3},
          'new_native_execution': 'NOT_RUN'}
Path(__file__).with_name('source-checks.json').write_text(
    json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
print(json.dumps({'allowed_paths': len(inputs), 'old_swift_tests_unchanged': len(old_tests),
                  'new_methods': sum(map(len, methods.values())), 'native_execution': 'NOT_RUN'}))
