"""Source preservation check only; actual UIKit/PNG verification belongs to Mac CI."""
from pathlib import Path
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
PATHS = ['Tinodios/widgets/ChatListViewCell.swift', 'TinodiosUITests/CoreListLayoutTests.swift']
BASE = 'e9eba400129c734315e8176d00e5b2a52e2bc74f'
old = subprocess.check_output(['git', 'show', BASE + ':' + PATHS[1]], cwd=ROOT).decode()
new = (ROOT / PATHS[1]).read_text(encoding='utf-8')
methods = lambda text: re.findall(r'func (test\w+)\(', text)
assert methods(old) == methods(new) and len(methods(new)) == 6
assertions = lambda text: [line.strip() for line in text.splitlines() if 'XCTAssert' in line]
assert all(line in assertions(new) for line in assertions(old))
assert '1_700_000_000' in new and 'systemUptime + 3' in new
data = {'scope': 'Windows source preservation; not UIKit execution', 'parent': BASE,
        'paths': PATHS, 'methods': methods(new), 'original_assertions_retained': len(assertions(old)),
        'fixture_timestamp_unchanged': True, 'three_second_deadline_unchanged': True,
        'native_execution': 'NOT_RUN', 'new_native_methods': 0}
Path(__file__).with_name('CI38-title-checks.json').write_text(json.dumps(data, indent=2) + '\n',
                                                          encoding='utf-8', newline='\n')
print(json.dumps(data))
