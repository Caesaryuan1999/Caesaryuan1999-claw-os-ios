"""Collect the one authorized CI51 attempt. Read-only GitHub; never prints secrets."""
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

# A network exception can contain a temporary signed artifact URL. Report only
# the exception class/status; original credentials and download URLs stay private.
sys.excepthook = lambda kind, value, trace: print(json.dumps({
    'collection_error':kind.__name__, 'http_status':getattr(value, 'code', None)}), file=sys.stderr)

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
REPO = 'Caesaryuan1999/Caesaryuan1999-claw-os-ios'
SHA = '0877d9a8411b0835a1076b426a92da64e0ab9468'
RUN, JOB, ATTEMPT = 35497878843, 108508510112, 2
token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
if not token:
    result = subprocess.run(['git','credential','fill'], input='protocol=https\nhost=github.com\n\n',
        cwd=ROOT, capture_output=True, text=True, timeout=30,
        env=dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never'))
    token = dict(x.split('=',1) for x in result.stdout.splitlines() if '=' in x).get('password')
if not token:
    raise SystemExit('Credential unavailable; no value printed')

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

opener = urllib.request.build_opener(NoRedirect)
def api(path):
    request = urllib.request.Request('https://api.github.com/repos/' + REPO + path,
        headers={'Accept':'application/vnd.github+json','Authorization':'Bearer '+token,
                 'User-Agent':'CLAW-CI51-evidence','X-GitHub-Api-Version':'2022-11-28'})
    return opener.open(request, timeout=30)

def read_json(path):
    with api(path) as response:
        return json.load(response)

def download(path, output, limit):
    try:
        response = api(path)
    except urllib.error.HTTPError as error:
        if error.code not in (301,302,303,307,308):
            raise SystemExit(f'GitHub download returned HTTP {error.code}') from None
        location = error.headers.get('Location','')
        if urllib.parse.urlparse(location).scheme != 'https':
            raise SystemExit('Refused non-HTTPS download redirect')
        # Signed asset URL obtained from authenticated GitHub. Do not forward
        # the GitHub Authorization header to the storage host or print the URL.
        response = urllib.request.urlopen(urllib.request.Request(location,
            headers={'User-Agent':'CLAW-CI51-evidence'}), timeout=90)
    digest, size = hashlib.sha256(), 0
    with response, output.open('xb') as stream:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk: break
            size += len(chunk)
            if size > limit: raise SystemExit('Download exceeds bounded evidence size')
            digest.update(chunk); stream.write(chunk)
    return {'file':output.name,'bytes':size,'sha256':digest.hexdigest()}

run = read_json(f'/actions/runs/{RUN}')
assert run['head_sha'] == SHA and run['path'] == '.github/workflows/ios-smoke.yml'
assert run['run_attempt'] == ATTEMPT and run['status'] == 'completed', 'Attempt 2 has not completed; no collection or repeat run'
job = read_json(f'/actions/jobs/{JOB}')
assert job['run_id'] == RUN and job['run_attempt'] == ATTEMPT and job['status'] == 'completed'
report = {'time':dt.datetime.now().astimezone().isoformat(), 'repository':REPO,'sha':SHA,
          'run':RUN,'job':JOB,'attempt':ATTEMPT,'run_conclusion':run['conclusion'],
          'started_at':job['started_at'],'completed_at':job['completed_at'], 'steps':job['steps']}
report['job_log'] = download(f'/actions/jobs/{JOB}/logs', HERE/'CI51-attempt2-job.log', 32*1024*1024)
artifacts = read_json(f'/actions/runs/{RUN}/artifacts')['artifacts']
selected = [a for a in artifacts if a['name'] == 'ios-local-store-'+SHA and not a['expired']
            and a['created_at'] >= job['started_at']]
assert len(selected) <= 1, 'Multiple candidate artifacts need manual review'
report['artifacts'] = []
for artifact in selected:
    archive = HERE/'CI51-attempt2-evidence.zip'
    entry = {k:artifact.get(k) for k in ('id','name','size_in_bytes','digest','created_at','expired')}
    entry.update(download(f'/actions/artifacts/{artifact["id"]}/zip', archive, 512*1024*1024))
    if entry.get('digest'):
        assert entry['digest'] == 'sha256:'+entry['sha256'], 'Artifact digest mismatch'
    report['artifacts'].append(entry)
    output = HERE/'CI51-attempt2-original'
    output.mkdir(exist_ok=False)
    extracted, expanded = [], 0
    with zipfile.ZipFile(archive) as stream:
        for member in stream.infolist():
            # Keep compact original summaries, logs and attachment diagnostics.
            # Full xcresult stays preserved byte-for-byte in the original ZIP.
            path = Path(member.filename)
            if member.is_dir() or path.suffix.lower() not in ('.json','.log','.txt','.err','.png'):
                continue
            if '.xcresult/' in member.filename: continue
            destination = (output/path).resolve()
            assert destination.is_relative_to(output.resolve()) and not path.is_absolute()
            assert member.file_size <= 64*1024*1024
            expanded += member.file_size
            assert expanded <= 256*1024*1024
            raw = stream.read(member)
            destination.parent.mkdir(parents=True,exist_ok=True)
            with destination.open('xb') as target: target.write(raw)
            extracted.append({'file':member.filename,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()})
    entry['extracted_originals'] = extracted
with (HERE/'CI51-attempt2-result.json').open('x',encoding='utf-8') as stream:
    json.dump(report,stream,ensure_ascii=False,indent=2)
print(json.dumps({'run':RUN,'attempt':ATTEMPT,'job':JOB,'conclusion':report['run_conclusion'],
                  'artifact_count':len(report['artifacts']),'originals':sum(len(a.get('extracted_originals',[])) for a in report['artifacts'])}))
