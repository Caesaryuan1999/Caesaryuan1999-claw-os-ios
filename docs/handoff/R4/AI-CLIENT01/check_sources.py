"""Bounded source/target checks. Does not compile Swift or execute UIKit/HTTP."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
BASE = 'd21d69fcd69ecc5946df2cad134bddef98a24a96'
PRODUCTION = ['Tinodios/NewChatTabController.swift', 'Tinodios/Cache.swift'] + [
    'Tinodios/' + name + '.swift' for name in ['ClawAssistantModels', 'ClawAssistantService',
    'ClawAssistantSession', 'ClawAssistantHistory', 'ClawAssistantViewController',
    'ClawAssistantHistoryViewController', 'ClawAssistantConversationViewController']]
TESTS = ['TinodiosUITests/AssistantHistoryTests.swift', 'TinodiosUITests/AssistantLayoutTests.swift']
WIRING = ['Tinodios.xcodeproj/project.pbxproj', 'Scripts/ci/verify_publish_outcomes_macos.sh']

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

def read(path):
    return (ROOT / path).read_text(encoding='utf-8')

assert len(PRODUCTION) == 9
service = read(PRODUCTION[3])
assert '"Authorization"' in service and '"X-Tinode-APIKey"' in service
assert '"X-Tinode-Auth"' not in service
assert 'method: "POST"' not in service and 'httpMethod = "POST"' not in service
assert 'completionHandler(nil)' in service
assert 'urlCache = nil' in service and 'httpShouldSetCookies = false' in service
assert '24 * 1024 * 1024' in service
assert not re.search(r'\b(print|NSLog|debugPrint)\s*\(', '\n'.join(read(p) for p in PRODUCTION[2:]))
selector = WIRING[1]
old = git('show', BASE + ':' + selector).decode('utf-8')
new = read(selector)
added = [f'  -only-testing:TinodiosVoiceLayoutTests/{Path(p).stem} \\\n' for p in TESTS]
for line in added:
    assert new.count(line) == 1
    new = new.replace(line, '')
assert new == old, 'Existing selectors/timeout/script bytes must remain unchanged'
old_tests = git('ls-tree', '-r', '--name-only', BASE, 'TinodeSDKTests', 'TinodiosUITests').decode().splitlines()
old_tests = [p for p in old_tests if p.endswith('.swift')]
for path in old_tests:
    original = git('show', BASE + ':' + path)
    assert original.replace(b'\r\n', b'\n') == (ROOT / path).read_bytes().replace(b'\r\n', b'\n'), path
methods = {p: re.findall(r'^    func (test\w+)\(', read(p), re.M) for p in TESTS}
assert [len(methods[p]) for p in TESTS] == [14, 5]
pbx = read(WIRING[0])
for path in PRODUCTION[2:] + TESTS:
    assert pbx.count('path = ' + Path(path).name + ';') == 1, path
assert 'asyncAfter' not in read(TESTS[0]), 'Late responses must wait on the actual consumer gate, not a delay'
for path in PRODUCTION[2:] + TESTS:
    raw = (ROOT / path).read_bytes()
    assert not raw.startswith(b'\xef\xbb\xbf') and b'\r' not in raw and raw.endswith(b'\n')
    assert not raw.endswith(b'\n\n'), path
files = []
for path in PRODUCTION + TESTS + WIRING:
    raw = (ROOT / path).read_bytes()
    files.append({'path': path, 'bytes': len(raw), 'raw_sha256': hashlib.sha256(raw).hexdigest(),
                  'git_clean_blob': git('hash-object', '--path=' + path, path).decode().strip()})
report = {'scope': 'source and target wiring only; Swift/UIKit/URLSession native NOT_RUN',
          'base': BASE, 'core_dependency': 'bff92a46301891a0b67055611e3eb0a8c10dc6e5',
          'production_count': 9, 'test_files': 2, 'wiring_files': 2, 'methods': methods,
          'new_native_expected': 19, 'cumulative_native_expected': 267, 'navigation_expected': 3,
          'existing_swift_test_files_unchanged': len(old_tests), 'only_two_selectors_added': True,
          'files': files}
output = Path(__file__).with_name('source-checks.json')
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
print(f'PASS: 13 source inputs; {len(old_tests)} existing Swift test files unchanged; new native 19 NOT_RUN')
