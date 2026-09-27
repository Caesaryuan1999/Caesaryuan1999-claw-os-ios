"""Read-only collection of the exact authorized auth-only run, without secret output."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REPO = 'Caesaryuan1999/Caesaryuan1999-claw-os-ios'
SHA = 'fe66b7f3e80fc3a521c40e046f362829f884a27a'
RUN, JOB = 36281964469, 108515388746
sys.excepthook = lambda kind, value, trace: print(json.dumps({
    'collection_error': kind.__name__, 'http_status': getattr(value, 'code', None)}), file=sys.stderr)
token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
if not token:
    credentials = subprocess.run(['git', 'credential', 'fill'],
        input='protocol=https\nhost=github.com\n\n', cwd=ROOT, capture_output=True,
        text=True, timeout=30, env=dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never'))
    token = dict(line.split('=', 1) for line in credentials.stdout.splitlines() if '=' in line).get('password')
if not token:
    raise SystemExit('Credential unavailable; no value printed')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


opener = urllib.request.build_opener(NoRedirect)
def api(path):
    request = urllib.request.Request('https://api.github.com/repos/' + REPO + path,
        headers={'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + token,
                 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'CLAW-auth-evidence'})
    return opener.open(request, timeout=30)


def read_json(path):
    with api(path) as response:
        return json.load(response)


def download(path, target, limit):
    try:
        response = api(path)
    except urllib.error.HTTPError as error:
        if error.code not in (301, 302, 303, 307, 308):
            raise SystemExit(f'GitHub download HTTP {error.code}') from None
        location = error.headers.get('Location', '')
        assert urllib.parse.urlparse(location).scheme == 'https'
        # GitHub's signed storage location is not printed. Never forward Authorization.
        response = urllib.request.urlopen(urllib.request.Request(location,
            headers={'User-Agent': 'CLAW-auth-evidence'}), timeout=60)
    sha, size = hashlib.sha256(), 0
    with response, target.open('xb') as stream:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            assert size <= limit
            sha.update(chunk)
            stream.write(chunk)
    return {'file': target.name, 'bytes': size, 'sha256': sha.hexdigest()}


run = read_json(f'/actions/runs/{RUN}')
assert run['head_sha'] == SHA and run['run_attempt'] == 1 and run['status'] == 'completed'
assert run['head_branch'] == 'codex/verify-ios-auth-20260927' and run['event'] == 'workflow_dispatch'
jobs = read_json(f'/actions/runs/{RUN}/attempts/1/jobs')['jobs']
assert len(jobs) == 2
auth, = [job for job in jobs if job['name'] == 'auth-only']
full, = [job for job in jobs if job['name'] == 'simulator']
assert auth['id'] == JOB and auth['status'] == 'completed'
assert full['conclusion'] == 'skipped' and not full['steps']
report = {'captured_at': dt.datetime.now().astimezone().isoformat(),
          'repository': REPO, 'source_sha': SHA, 'run': RUN, 'attempt': 1, 'job': JOB,
          'conclusion': run['conclusion'], 'started_at': auth['started_at'], 'completed_at': auth['completed_at'],
          'jobs': [{key: job.get(key) for key in ('id', 'name', 'status', 'conclusion', 'steps')} for job in jobs]}
report['job_log'] = download(f'/actions/jobs/{JOB}/logs', HERE / 'auth-native-job.log', 16 * 1024 * 1024)
artifacts = read_json(f'/actions/runs/{RUN}/artifacts')['artifacts']
artifact, = [value for value in artifacts if value['name'] == f'ios-auth-functions-{SHA}-1' and not value['expired']]
archive = HERE / 'auth-native-original.zip'
entry = {key: artifact.get(key) for key in ('id', 'name', 'size_in_bytes', 'digest', 'created_at')}
entry.update(download(f'/actions/artifacts/{artifact["id"]}/zip', archive, 32 * 1024 * 1024))
assert entry['digest'] == 'sha256:' + entry['sha256']
dest = HERE / 'original'
dest.mkdir(exist_ok=False)
entry['originals'] = []
with zipfile.ZipFile(archive) as stream:
    for member in stream.infolist():
        if member.is_dir():
            continue
        path = Path(member.filename)
        target = (dest / path).resolve()
        assert not path.is_absolute() and target.is_relative_to(dest.resolve())
        assert path.suffix in ('.json', '.swift', '.log') and member.file_size <= 8 * 1024 * 1024
        raw = stream.read(member)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as output:
            output.write(raw)
        entry['originals'].append({'file': member.filename, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
report['artifact'] = entry
with (HERE / 'collection.json').open('x', encoding='utf-8') as output:
    json.dump(report, output, indent=2)
print(json.dumps({'run': RUN, 'attempt': 1, 'job': JOB, 'conclusion': run['conclusion'],
                  'artifact_id': entry['id'], 'originals': len(entry['originals']), 'sha256': entry['sha256']}))
