"""Exact staged source evidence. Does not run Swift, TCP, URLSession or UIKit."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
BASE = '3cb55192054a12707a00cac6de8b8f21e3fc4521'
ORIGINAL = '02e4ebcb54e4aa7451224e7935b8bb78b840c8ba'
PATHS = [
    'Tinodios/ClawAssistantModels.swift', 'Tinodios/ClawAssistantService.swift',
    'Tinodios/ClawAssistantRun.swift', 'Tinodios/ClawAssistantStream.swift',
    'TinodiosUITests/AssistantRunTests.swift', 'TinodiosUITests/AssistantStreamTests.swift',
]

def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)

changed = git('diff', '--cached', '--name-only', BASE).decode().splitlines()
assert set(changed) == set(PATHS), changed
git('diff', '--cached', '--check', BASE, '--', *PATHS)
original_tree = git('ls-tree', '-r', '-z', BASE)
entries = [item.split(b'\t', 1) for item in original_tree.split(b'\0') if item]
for metadata, path in entries:
    name = path.decode()
    if name not in PATHS:
        assert metadata.decode().split()[2] == git('rev-parse', ':' + name).decode().strip(), name
methods = {}
for name, count in zip(PATHS[4:], [17, 7]):
    source = git('show', ':' + name).decode()
    methods[name] = re.findall(r'func (test\w+)\(', source)
    assert len(methods[name]) == count
    old_names = re.findall(r'func (test\w+)\(', git('show', ORIGINAL + ':' + name).decode())
    assert set(old_names) <= set(methods[name])

run = git('show', ':Tinodios/ClawAssistantRun.swift').decode()
old_run = git('show', ORIGINAL + ':Tinodios/ClawAssistantRun.swift').decode()
stream = git('show', ':Tinodios/ClawAssistantStream.swift').decode()
old_stream = git('show', ORIGINAL + ':Tinodios/ClawAssistantStream.swift').decode()
service = git('show', ':Tinodios/ClawAssistantService.swift').decode()
models = git('show', ':Tinodios/ClawAssistantModels.swift').decode()
facts = {
    'old_prepare_did_not_retire_stop': 'previousStop?.cancel()' not in old_run,
    'new_prepare_retires_stop_before_receipt_clear': run.index('stopOperation = UUID()', run.index('private func prepare')) < run.index('cancelReads(); receipt = nil'),
    'submit_rechecks_after_notification': 'submission = .pending; lastError = nil; notify()\n        guard current, writeOperation == op' in run,
    'stop_rechecks_after_notification': 'stopping = .pending; notify()\n        guard current, stopOperation == op' in run,
    'full_stable_identity': all(part in run for part in ['a.conversation_id == b.conversation_id', 'a.run_id == b.run_id', 'a.request_id == b.request_id', 'a.question_message_id == b.question_message_id', 'a.answer_message_id == b.answer_message_id', 'a.isLegacy == b.isLegacy']),
    'old_stream_invented_status_codes': 'if let code = codes[http.statusCode]' in old_stream,
    'new_error_envelope_matches_status': 'expected[status] == value.error.code' in stream,
    'new_errors_bounded': 'ClawAssistantSSEParser.frameLimit - errorBody.count' in stream,
    'before_consumer_duplicate_and_continuity_gate': 'if !ClawAssistantWire.less(lastDelivered, value.id)' in stream and 'ClawAssistantRunWire.next(lastDelivered) == value.id' in stream,
    'callback_and_append_capacity': 'Int64(value.id).map({ $0 <= 1024 })' in stream and 'guard frames.count < 1024' in stream,
    'event_page_tail_complete': 'last.id == last_event' in models and 'ClawAssistantWire.less(last.id, last_event)' in models,
    'requested_cursor_in_range': '!ClawAssistantWire.less(value.last_event, after)' in service,
}
assert all(facts.values()), facts
inputs = []
for name in PATHS:
    blob = git('show', ':' + name)
    raw = (ROOT / name).read_bytes()
    inputs.append({'path': name, 'blob': git('rev-parse', ':' + name).decode().strip(),
                   'git_sha256': hashlib.sha256(blob).hexdigest(), 'raw_sha256': hashlib.sha256(raw).hexdigest()})

result = {'scope': 'Windows Git/source evidence only; no Swift or URLSession execution',
          'baseline': BASE, 'original_B1_source': ORIGINAL, 'exact_paths': changed,
          'unselected_index_blobs_unchanged': True, 'original_20_B_method_names_preserved': True,
          'source_counterexamples_and_guards': facts, 'new_methods': methods, 'inputs': inputs,
          'native_expected': {'inherited': 269, 'B1': 24, 'total': 293, 'navigation_separate': 3},
          'native_execution': 'NOT_RUN'}
(OUT / 'successor-source-checks.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
print(json.dumps({'paths': len(inputs), 'source_checks': len(facts), 'new_methods': 24,
                  'unselected_index_blobs_unchanged': True, 'native_execution': 'NOT_RUN'}))
