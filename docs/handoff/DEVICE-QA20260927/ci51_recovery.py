"""Bounded, authorized rerun of CI51. No source push, signing or secret output."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import urllib.error
import urllib.request

REPO = 'Caesaryuan1999/Caesaryuan1999-claw-os-ios'
SHA = '0877d9a8411b0835a1076b426a92da64e0ab9468'
BRANCH = 'codex/verify-r2-ios02-20260918'
RUN = 35497878843
DEST = Path(__file__).resolve().parent
ROOT = DEST.parents[2]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rerun-failed', action='store_true')
    parser.add_argument('--label', required=True)
    args = parser.parse_args()
    if not args.label.replace('-', '').isalnum():
        raise SystemExit('Invalid report label')
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if not token:
        env = dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never')
        result = subprocess.run(['git', 'credential', 'fill'],
            input='protocol=https\nhost=github.com\n\n', cwd=ROOT,
            capture_output=True, text=True, timeout=30, env=env)
        token = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line).get('password')
    if not token:
        raise SystemExit('GitHub credential unavailable; no value printed')

    def request(path, body=None):
        req = urllib.request.Request('https://api.github.com/repos/' + REPO + path,
            data=None if body is None else json.dumps(body).encode(),
            headers={'Accept':'application/vnd.github+json', 'Authorization':'Bearer ' + token,
                     'X-GitHub-Api-Version':'2022-11-28', 'User-Agent':'CLAW-iOS-CI51-recovery',
                     'Content-Type':'application/json'})
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None

    report = {'time':dt.datetime.now().astimezone().isoformat(), 'repository':REPO,
              'source_changed':False, 'signing':False, 'release':False}
    try:
        _, run = request(f'/actions/runs/{RUN}')
        report['run'] = {k:run.get(k) for k in ('id','html_url','head_sha','head_branch','path','workflow_id',
                                               'event','status','conclusion','run_attempt','created_at','updated_at')}
        if not (run['head_sha'] == SHA and run['head_branch'] == BRANCH and
                run['path'] == '.github/workflows/ios-smoke.yml' and run['event'] == 'workflow_dispatch'):
            raise SystemExit('Run does not match exact authorized candidate')
        _, jobs = request(f'/actions/runs/{RUN}/attempts/{run["run_attempt"]}/jobs')
        report['jobs'] = [{k:j.get(k) for k in ('id','name','status','conclusion','run_attempt','started_at','completed_at','steps')}
                          for j in jobs.get('jobs', [])]
        if args.rerun_failed:
            if not (run['run_attempt'] == 1 and run['status'] == 'completed' and run['conclusion'] == 'failure'):
                raise SystemExit('Only original failed attempt 1 may be rerun by this script')
            failures = [j for j in report['jobs'] if j['conclusion'] == 'failure']
            if len(failures) != 1 or not any(s.get('name') == 'Run SDK and production SQLite migration tests without signing'
                  and s.get('conclusion') == 'failure' for s in failures[0]['steps']):
                raise SystemExit('Failure stage differs from reviewed CI51')
            # Consume the one-shot marker before POST. An ambiguous network failure
            # must be inspected, never automatically submitted a second time.
            with (DEST / 'CI51-RERUN-ONCE.json').open('x', encoding='utf-8') as stream:
                json.dump(report, stream, ensure_ascii=False, indent=2)
            report['rerun_failed_http_status'], _ = request(f'/actions/runs/{RUN}/rerun-failed-jobs', {})
    except urllib.error.HTTPError as error:
        report['api_error_status'] = error.code
    except urllib.error.URLError:
        report['api_error'] = 'network error; no retry performed'
    with (DEST / ('CI51-' + args.label + '.json')).open('x', encoding='utf-8') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
    print(json.dumps(report, ensure_ascii=False))
    return int('api_error_status' in report or 'api_error' in report)

if __name__ == '__main__':
    raise SystemExit(main())
