"""Prepare/run exact production Promise and two functions. No network/account data."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

def function(source, marker):
    assert source.count(marker) == 1
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
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    dest = args.output.resolve()
    dest.mkdir(parents=True, exist_ok=False)
    def source(path):
        return (subprocess.check_output(['git', 'show', f'{args.source_ref}:{path}'], cwd=ROOT).decode('utf-8')
                if args.source_ref else (ROOT / path).read_text(encoding='utf-8'))
    sources = {p:source(p) for p in ['Tinodios/UiUtils.swift','Tinodios/ChatListInteractor.swift','TinodeSDK/PromisedReply.swift']}
    helper = function(sources['Tinodios/UiUtils.swift'], 'public static func attachToMeTopic(')
    caller = function(sources['Tinodios/ChatListInteractor.swift'], '    func attachToMeTopic() {')
    template = (HERE / 'me_subscription_fixture.swift').read_text(encoding='utf-8')
    rendered = template.replace('// INSERT_PRODUCTION_HELPER', helper).replace('// INSERT_PRODUCTION_CALLER', caller)
    swift = sources['TinodeSDK/PromisedReply.swift'] + '\n' + rendered
    # Top-level main.swift is required when compiling an executable.
    (dest / 'main.swift').write_text(swift, encoding='utf-8')
    report = {'source':args.source_ref or 'working-tree', 'native_status':'NOT_RUN',
              'inputs_lf_sha256':{p:hashlib.sha256(s.encode()).hexdigest() for p,s in sources.items()},
              'generated_sha256':hashlib.sha256(swift.encode()).hexdigest(),
              'scope':'Actual Promise and verbatim helper/caller; Cache, transport, UI are controlled fixtures; no iOS build/device proof'}
    result = 0
    if args.execute:
        compiler = shutil.which('swiftc')
        if compiler:
            binary = dest / ('probe.exe' if sys.platform == 'win32' else 'probe')
            build = subprocess.run([compiler, '-swift-version','5', str(dest/'main.swift'), '-o', str(binary)],
                                   capture_output=True, text=True, timeout=120)
            (dest/'compile.log').write_text(build.stdout + build.stderr, encoding='utf-8')
            report['compile_exit'] = build.returncode
            result = build.returncode
            if result == 0:
                run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
                (dest/'runtime.log').write_text(run.stdout + run.stderr, encoding='utf-8')
                report.update(native_status='PASS' if run.returncode == 0 else 'FAIL', runtime_exit=run.returncode)
                result = run.returncode
            else:
                report['native_status'] = 'COMPILE_FAIL'
        else:
            report['reason'] = 'swiftc is unavailable; fixture prepared without execution'
    (dest/'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    return result

if __name__ == '__main__':
    raise SystemExit(main())
