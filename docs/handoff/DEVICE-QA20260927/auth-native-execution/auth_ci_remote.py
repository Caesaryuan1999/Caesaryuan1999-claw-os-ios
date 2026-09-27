"""One authorized auth-only dispatch; read-only status. No secrets in reports."""
import argparse
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.parse
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
REPO = 'Caesaryuan1999/Caesaryuan1999-claw-os-ios'
BRANCH = 'codex/verify-ios-auth-20260927'
SHA = 'fe66b7f3e80fc3a521c40e046f362829f884a27a'
WORKFLOW = 310211684


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dispatch', action='store_true')
    args = parser.parse_args()
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if not token:
        response = subprocess.run(['git', 'credential', 'fill'],
            input='protocol=https\nhost=github.com\n\n', cwd=ROOT, capture_output=True,
            text=True, timeout=30, env=dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never'))
        token = dict(line.split('=', 1) for line in response.stdout.splitlines() if '=' in line).get('password')
    if not token:
        raise SystemExit('Credential unavailable; no value printed')

    def api(path, payload=None):
        request = urllib.request.Request('https://api.github.com/repos/' + REPO + path,
            data=None if payload is None else json.dumps(payload).encode(),
            headers={'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + token,
                     'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'CLAW-auth-only-evidence',
                     'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None

    stamp = dt.datetime.now(dt.timezone.utc)
    report = {'time': stamp.isoformat(), 'repository': REPO, 'branch': BRANCH, 'source_sha': SHA,
              'workflow_id': WORKFLOW, 'signed': False, 'full_app_build': False}
    code = 0
    try:
        _, ref = api('/git/ref/heads/' + BRANCH)
        assert ref['object']['sha'] == SHA, 'Remote branch changed; refusing action'
        report['remote_sha_verified'] = True
        _, workflow = api(f'/actions/workflows/{WORKFLOW}')
        assert workflow['path'] == '.github/workflows/ios-smoke.yml' and workflow['state'] == 'active'
        _, content = api('/contents/.github/workflows/ios-smoke.yml?ref=' + urllib.parse.quote(BRANCH, safe=''))
        remote_yaml = base64.b64decode(content['content']).decode().replace('\r\n', '\n')
        local_yaml = (ROOT / '.github/workflows/ios-smoke.yml').read_text(encoding='utf-8')
        assert remote_yaml == local_yaml, 'Remote workflow differs from reviewed local file'
        report['workflow_lf_sha256'] = hashlib.sha256(remote_yaml.encode()).hexdigest()
        if args.dispatch:
            report['dispatch_payload'] = {'ref': BRANCH, 'inputs': {'auth_only': True}}
            with (HERE / 'DISPATCH-ONCE.json').open('x', encoding='utf-8') as stream:
                json.dump(report, stream, indent=2)
            report['dispatch_http_status'], _ = api(f'/actions/workflows/{WORKFLOW}/dispatches', report['dispatch_payload'])
        else:
            _, runs = api(f'/actions/workflows/{WORKFLOW}/runs?branch=' + urllib.parse.quote(BRANCH, safe='')
                          + '&event=workflow_dispatch&per_page=20')
            matches = [run for run in runs['workflow_runs'] if run['head_sha'] == SHA and run['head_branch'] == BRANCH]
            assert len(matches) <= 1, 'Multiple runs require controller review; never automatically rerun'
            report['matches'] = len(matches)
            if matches:
                run = matches[0]
                assert run['run_attempt'] == 1, 'Unexpected retry'
                report['run'] = {key: run.get(key) for key in ('id', 'html_url', 'head_sha', 'head_branch',
                    'event', 'status', 'conclusion', 'run_attempt', 'created_at', 'updated_at')}
                _, jobs = api(f'/actions/runs/{run["id"]}/attempts/1/jobs')
                report['jobs'] = [{key: job.get(key) for key in ('id', 'name', 'status', 'conclusion',
                    'started_at', 'completed_at', 'steps')} for job in jobs['jobs']]
    except urllib.error.HTTPError as error:
        report['api_error_status'] = error.code
        code = 1
    except urllib.error.URLError:
        report['api_error'] = 'network error; no retry performed'
        code = 1
    except (AssertionError, FileExistsError) as error:
        report['safety_stop'] = str(error)
        code = 1
    name = 'dispatch-result.json' if args.dispatch else 'status-' + stamp.strftime('%Y%m%dT%H%M%SZ') + '.json'
    with (HERE / name).open('x', encoding='utf-8') as stream:
        json.dump(report, stream, indent=2)
    print(json.dumps(report, indent=2))
    return code


if __name__ == '__main__':
    raise SystemExit(main())
