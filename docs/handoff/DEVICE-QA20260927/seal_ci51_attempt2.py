"""Offline, append-only evidence digest. No network, credentials or test rerun."""
import datetime as dt
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ORIGINAL = HERE / 'CI51-attempt2-original'
RUN_ROOT = ORIGINAL / 'ios-01-a-20260926-232942'
ATTACHMENTS = RUN_ROOT / 'storage-attachments'


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def item(path):
    raw = path.read_bytes()
    return {'file': path.relative_to(HERE).as_posix(), 'bytes': len(raw),
            'sha256': hashlib.sha256(raw).hexdigest()}


def append_json(name, value):
    with (HERE / name).open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


report = read(HERE / 'CI51-attempt2-result.json')
assert (report['run'], report['job'], report['attempt'], report['run_conclusion']) == (
    35497878843, 108508510112, 2, 'failure')
assert report['sha'] == '0877d9a8411b0835a1076b426a92da64e0ab9468'
artifact, = report['artifacts']
for entry in [report['job_log'], artifact]:
    actual = item(HERE / entry['file'])
    assert (actual['bytes'], actual['sha256']) == (entry['bytes'], entry['sha256'])
assert artifact['digest'] == 'sha256:' + artifact['sha256']
for entry in artifact['extracted_originals']:
    actual = item(ORIGINAL / entry['file'])
    assert (actual['bytes'], actual['sha256']) == (entry['bytes'], entry['sha256'])

sdk, storage, static = (read(RUN_ROOT / name) for name in
                        ['sdk-summary.json', 'storage-summary.json', 'static.json'])
keys = ['totalTestCount', 'passedTests', 'failedTests', 'skippedTests']
counts = {label: {key: source[key] for key in keys}
          for label, source in [('sdk', sdk), ('app_sqlite', storage)]}
counts['total_native'] = {key: sdk[key] + storage[key] for key in keys}
assert list(counts['total_native'].values()) == [337, 332, 5, 0]
assert len(storage['testFailures']) == 5

images = []
for name in ['46F6EFE3-784C-4383-9F14-558C011F7B73.json',
             '5D4D09FB-CE32-4146-B742-8CF514C8F64C.json',
             '6808C4DE-6597-4384-96B3-CCC2F7B86AAE.json']:
    path = ATTACHMENTS / name
    images.append({'original': item(path), 'snapshot': read(path)})
audio = []
for label, name in [
    ('production_aac', '38E487D7-63BB-4B9C-8A72-D75D337080C1.json'),
    ('bare_aac_control', 'DAF2F21E-6205-4834-9BB9-14492366B4A9.json'),
    ('independent_pcm_control', '96604974-5B23-4757-AA1B-7C8725B27FD0.json')]:
    path = ATTACHMENTS / name
    data = read(path)
    audio.append({'case': label, 'original': item(path),
                  'metadata': {key: value for key, value in data.items() if key != 'events'},
                  'event_count': len(data['events']), 'last_events': data['events'][-2:]})

append_json('CI51-ATTEMPT2-DIAGNOSIS.json', {
    'evidence_level': 'remote_ios_simulator_native_tests_and_original_attachments',
    'source_sha': report['sha'], 'run': report['run'], 'job': report['job'],
    'attempt': 2, 'conclusion': 'failure',
    'counts': counts, 'static_scripts': static['scripts'], 'static_failed': static['failed'],
    'failures': storage['testFailures'], 'images_post_wait': images, 'audio_at_deadline': audio,
    'navigation': read(RUN_ROOT / 'navigation-export-status.json'),
    'limits': [
        'Does not include auth fixes 92208c6 or 3d94981.',
        'Image predicate true was recorded after wait; no exact predicate timestamp proves it met deadline.',
        'Independent PCM and AAC finish failures do not establish an AAC-only or platform root cause.',
        'No synthetic finish or deadline extension was used.',
        'Packaging, cold launch, real iPhone and Android/iOS integration were not verified.']})

compact_names = [
    'CI51-ATTEMPT2.md', 'CI51-ATTEMPT2-DIAGNOSIS.json', 'CI51-attempt2-result.json',
    'CI51-preflight.json', 'CI51-RERUN-ONCE.json', 'CI51-rerun-request.json',
    'CI51-attempt2-start.json', 'CI51-attempt2-progress8.json',
    'ci51_recovery.py', 'collect_ci51_attempt2.py', 'seal_ci51_attempt2.py']
append_json('CI51-ATTEMPT2-SEAL.json', {
    'created_at': dt.datetime.now().astimezone().isoformat(),
    'run': report['run'], 'job': report['job'], 'attempt': 2, 'source_sha': report['sha'],
    'verified_original_count': len(artifact['extracted_originals']),
    'files': [item(HERE / name) for name in compact_names],
    'upstream_originals': [item(HERE / report['job_log']['file']), item(HERE / artifact['file'])],
    'separate_local_source_seal': item(HERE / 'SOURCE-SEAL.json'),
    'policy': 'Original archive/log/312 extracted files remain local and byte-identical; no new CI action.'})
print(json.dumps({'run': report['run'], 'attempt': 2, 'verified_original_count':
                  len(artifact['extracted_originals']), 'native_counts': counts['total_native'],
                  'seal': item(HERE / 'CI51-ATTEMPT2-SEAL.json')}, ensure_ascii=False))
