#!/usr/bin/env python3
"""Narrow source-wiring regression; not Swift execution or device acceptance."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]

def method(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth, end = 1, brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-ref')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    def read(path):
        return (subprocess.check_output(['git', 'show', f'{args.source_ref}:{path}'], cwd=ROOT).decode('utf-8')
                if args.source_ref else (ROOT / path).read_text(encoding='utf-8'))
    sources = {p: read(p) for p in ['Tinodios/UiUtils.swift', 'Tinodios/ChatListInteractor.swift',
                                   'TinodeSDK/PromisedReply.swift', 'TinodiosDB/BaseDb.swift']}
    helper = method(sources['Tinodios/UiUtils.swift'], 'public static func attachToMeTopic(')
    caller = method(sources['Tinodios/ChatListInteractor.swift'], '    func attachToMeTopic() {')
    catch = helper.split('.thenCatch', 1)[1]
    success = caller.split('onSuccess:', 1)[1].split('onFailure:', 1)[0]
    failure = caller.split('onFailure:', 1)[1]
    checks = {
        'subscription_failure_stays_rejected': 'return PromisedReply<ServerMessage>(error: err)' in catch and 'return nil' not in catch,
        'all_auth_failures_route_with_request_owner': 'case 401, 403, 404:' in catch and 'logoutAndRouteToLoginVC(ifCurrent: tinode)' in catch,
        'retry_uses_captured_owner_under_current_gate': 'Cache.ifCurrent(tinode)' in catch and 'tinode.reconnectNow' in catch and 'Cache.tinode' not in catch,
        'caller_passes_its_same_owner_to_subscribe': 'meListener: self.meListener, for: tinode' in caller,
        'success_does_not_update_replacement_session': 'Cache.ifCurrent(tinode)' in success,
        'already_attached_original_me_is_idempotent': 'if me!.attached {' in helper and
            'return PromisedReply<ServerMessage>(value: ServerMessage())' in helper and
            helper.index('if me!.attached {') < helper.index('let get ='),
        'failure_does_not_route_replacement_session': 'logoutAndRouteToLoginVC(ifCurrent: tinode)' in failure and 'router?.routeToLogin()' not in failure,
        'store_logout_retains_messages': 'UPDATE accounts SET last_active=0,device_id=NULL WHERE id=? AND uid=?' in sources['TinodiosDB/BaseDb.swift']
            and 'DELETE' not in method(sources['TinodiosDB/BaseDb.swift'], 'public func logout()'),
        'promise_nil_failure_handler_is_recovery': 'try handleSuccess(ret: fh(err))' in sources['TinodeSDK/PromisedReply.swift']
            and 'try np.resolve(result: value)' in sources['TinodeSDK/PromisedReply.swift'],
    }
    report = {'level':'source_wiring_only_not_Swift_or_UIKit', 'source':args.source_ref or 'working-tree',
              'passed':sum(checks.values()), 'total':len(checks), 'checks':checks,
              'inputs_lf_sha256':{p:hashlib.sha256(s.encode()).hexdigest() for p,s in sources.items()}}
    if args.report:
        with args.report.open('x', encoding='utf-8') as stream:
            json.dump(report, stream, indent=2)
    print(json.dumps(report, indent=2))
    return 0 if all(checks.values()) else 1

if __name__ == '__main__':
    raise SystemExit(main())
