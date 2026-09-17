#!/usr/bin/env python3
"""Execute standalone source-policy scripts; this does not build or run iOS.

These scripts use both top-level assertions and main() guards, so unittest
discovery does not execute the full suite. Run each in its own interpreter.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]


def run_checks(paths, root, timeout):
    paths = sorted(paths)
    if not paths:
        raise ValueError("No static policy scripts found; refusing an empty pass")
    results = []
    for path in paths:
        entry = {
            "script": path.relative_to(root).as_posix(),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }
        try:
            result = subprocess.run(
                # -E prevents PYTHONOPTIMIZE from silently disabling assertions.
                [sys.executable, "-B", "-E", str(path)],
                cwd=root, capture_output=True, text=True,
                encoding="utf-8", errors="replace", timeout=timeout,
            )
            entry.update(
                status="pass" if result.returncode == 0 else "fail",
                exit_code=result.returncode,
                stdout=result.stdout, stderr=result.stderr,
            )
        except subprocess.TimeoutExpired:
            entry.update(status="timeout", exit_code=None,
                         stdout="", stderr=f"Exceeded {timeout} seconds")
        except OSError as error:
            entry.update(status="error", exit_code=None,
                         stdout="", stderr=str(error))
        results.append(entry)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="Write a JSON evidence report")
    parser.add_argument("--timeout", type=float, default=60,
                        help="Maximum seconds per policy script (default: 60)")
    args = parser.parse_args()
    if not 0 < args.timeout <= 600:
        parser.error("--timeout must be greater than 0 and at most 600 seconds")
    try:
        results = run_checks((ROOT / "Scripts" / "ci").glob("test_*.py"),
                             ROOT, args.timeout)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    failed = sum(result["status"] != "pass" for result in results)
    for result in results:
        print(f"{result['status'].upper()}: {result['script']}")
        if result["status"] != "pass":
            print(result["stdout"] + result["stderr"])
    print(f"Static scripts: {len(results)}; passed: {len(results) - failed}; failed: {failed}")
    print("Evidence level: source policy only; no Swift build or device validation.")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "evidence_level": "static_source_policy",
            "scripts": len(results), "failed": failed, "results": results,
        }, indent=2) + "\n", encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
