"""Fixed auth-only Swift red/green runner. No iOS build, Pods, network or secrets."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / 'docs/handoff/DEVICE-QA20260927'
BASELINE = '79f015f47b15fd7124f81d52205de5c5508f370e'
CANDIDATE = '3d9498144a8ea95a5d581d777e6b78a246128ebc'
FILES = ['Tinodios/UiUtils.swift', 'Tinodios/ChatListInteractor.swift', 'TinodeSDK/PromisedReply.swift']
EXPECTED_INPUTS = {
    BASELINE: [
        '9ab72967d2fb8e9e1a7e6122563f6f01e9f126f0a1506461a4acbfe95e1bfb00',
        '736b16faeb1c89e24208d8acbc4fa2ddce11a14e07561f9c4623292e64c8b93d',
        '358e36aff8107208a5254d7ad1933cbb8228f6c02e716eec8df9886f5068aa30'],
    CANDIDATE: [
        '60a98dfdecca47b8730871a41986f01318f63fac0c9c93ac86cc38028219e1c3',
        '5074d3b224fdd8b777c094628e4025166f0d032ea4a5af34e1c744441ba40363',
        '358e36aff8107208a5254d7ad1933cbb8228f6c02e716eec8df9886f5068aa30']}
EXPECTED_FIXTURE = {
    'me_subscription_fixture.swift': '33e6a7a2ed144caead02358b383fc55eff66b9d615b3536a27ea0d264c384b61',
    'run_me_subscription_fixture.py': 'dfa99db5db306bebce91dc8fe4b35c4bb357f77b2a88a5e906fe8746fb4c64bc'}
EXPECTED_CHECKS = {
    *(f'current_{code}_rejects_and_routes_once' for code in (401, 403, 404)),
    *(f'stale_{code}_cannot_logout_replacement' for code in (401, 403, 404)),
    'current_502_reconnects_original_and_rejects', 'stale_502_does_not_reconnect_any_session',
    'other_502_does_not_request_reconnect', 'server_failure_is_not_sync_success_or_logout',
    'current_success_presents_topics', 'stale_success_does_not_present_new_account',
    'stale_caller_failure_has_no_new_account_effect', 'current_failure_does_not_present_success',
    'already_attached_uses_original_me_and_presents',
    'already_attached_installs_listener_without_subscribe', 'repeated_attach_is_idempotent'}
REQUIRED_RED = {'current_401_rejects_and_routes_once', 'current_403_rejects_and_routes_once',
                'stale_404_cannot_logout_replacement', 'stale_502_does_not_reconnect_any_session',
                'current_failure_does_not_present_success',
                'already_attached_installs_listener_without_subscribe'}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--prepare-only', action='store_true', help='Generate input only; explicitly NOT_RUN')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    summary = {'status': 'NOT_RUN', 'evidence_level': 'Swift_functions_with_controlled_boundaries',
               'baseline': BASELINE, 'candidate': CANDIDATE, 'phases': {},
               'limits': 'Not UIKit, full App build, Store/Keychain/locks, iPhone or cross-platform acceptance'}
    result = 1
    try:
        summary['checkout_sha'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        summary['inputs_sha256'] = {}
        for ref, expected in EXPECTED_INPUTS.items():
            observed = [digest(subprocess.check_output(['git', 'show', f'{ref}:{name}'], cwd=ROOT)) for name in FILES]
            require(observed == expected, f'Fixed source input changed: {ref}')
            summary['inputs_sha256'][ref] = dict(zip(FILES, observed))
        current = [digest((ROOT / name).read_text(encoding='utf-8').encode()) for name in FILES]
        require(current == EXPECTED_INPUTS[CANDIDATE], 'Checkout production files differ from reviewed candidate')
        for name, expected in EXPECTED_FIXTURE.items():
            require(digest((FIXTURE / name).read_text(encoding='utf-8').encode()) == expected,
                    f'Reviewed fixture changed: {name}')
        if not args.prepare_only:
            compiler = shutil.which('swiftc')
            require(platform.system() == 'Darwin', 'Native execution requires macOS; no substitute runner')
            require(compiler is not None, 'swiftc unavailable; cannot count preparation as native PASS')
            summary['platform'] = platform.platform()
            summary['swift_version'] = subprocess.check_output([compiler, '--version'], text=True, timeout=30).strip()
            summary['xcode_version'] = subprocess.check_output(['xcodebuild', '-version'], text=True, timeout=30).strip()
        for label, ref in [('red', BASELINE), ('green', CANDIDATE)]:
            dest = output / label
            command = [sys.executable, str(FIXTURE / 'run_me_subscription_fixture.py'),
                       '--source-ref', ref, '--output', str(dest)]
            if not args.prepare_only:
                command.append('--execute')
            adapter = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
            (output / f'{label}-adapter.log').write_text(adapter.stdout + adapter.stderr, encoding='utf-8')
            info = json.loads((dest / 'result.json').read_text(encoding='utf-8'))
            summary['phases'][label] = {'adapter_exit': adapter.returncode, 'result': info}
            require(info['inputs_lf_sha256'] == summary['inputs_sha256'][ref], f'{label} input mismatch')
            if args.prepare_only:
                require(adapter.returncode == 0 and info['native_status'] == 'NOT_RUN', 'Preparation status mismatch')
                continue
            require(info.get('compile_exit') == 0, f'{label} did not compile; compile failure is not a red test')
            runtime = json.loads((dest / 'runtime.log').read_text(encoding='utf-8'))
            checks = runtime.get('checks', {})
            summary['phases'][label]['runtime'] = runtime
            require(set(checks) == EXPECTED_CHECKS and len(checks) == 17, f'{label} must execute exact 17 cases')
            require(all(type(value) is bool for value in checks.values()), f'{label} invalid case results')
            require(runtime['total'] == 17 and runtime['passed'] == sum(checks.values()), f'{label} inconsistent counts')
            if label == 'red':
                require(adapter.returncode == 1 and info.get('runtime_exit') == 1 and info['native_status'] == 'FAIL',
                        'Baseline must fail at runtime with expected regressions')
                require(all(checks[name] is False for name in REQUIRED_RED), 'Baseline no longer demonstrates required regressions')
            else:
                require(adapter.returncode == 0 and info.get('runtime_exit') == 0 and info['native_status'] == 'PASS'
                        and all(checks.values()), 'Candidate must pass all 17 Swift runtime cases')
        summary['status'] = 'NOT_RUN' if args.prepare_only else 'PASS'
        result = 0
    except Exception as error:
        summary['status'] = 'FAIL'
        summary['error'] = f'{type(error).__name__}: {error}'
    finally:
        (output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    return result


if __name__ == '__main__':
    raise SystemExit(main())
