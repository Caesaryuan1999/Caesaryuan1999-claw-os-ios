#!/usr/bin/env python3
"""Static session contract for the App-only contacts caller (not Swift execution)."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
RELATIVE = "Tinodios/account/ContactsSynchronizer.swift"


def body_after(source, marker):
    start = source.index(marker) + len(marker)
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return brace, end, source[brace + 1:end - 1]


def checks(source):
    _, _, function = body_after(source, "private func synchronizeInternal()")
    code = re.sub(r"//[^\n]*", "", function)
    gates = []
    for match in re.finditer(r"Cache\.ifCurrent\(tinode,", code):
        # Extract each occurrence from its own offset.
        offset = match.start()
        local_start, local_end, body = body_after(code[offset:], match.group())
        gates.append((offset + local_start, offset + local_end, body))
    fetch = code.index("self.fetchContacts()")
    auto = [g for g in gates if "setAutoLoginWithToken(token: token)" in g[2]]
    snapshot = [g for g in gates if "SharedUtils.getAuthToken()" in g[2]]
    result = [g for g in gates if "contactsManager.processSubscription(sub: sub)" in g[2]]
    return {
        "one_captured_sdk_before_enumeration":
            code.count("Cache.tinode") == 1 and code.index("let tinode = Cache.tinode") < fetch,
        "credentials_in_same_owner_gate_before_enumeration":
            len(snapshot) == 1 and snapshot[0][1] < fetch,
        "post_enumeration_auto_login_requires_same_owner":
            len(auto) == 1 and auto[0][0] > fetch
            and "== true else { return }" in code[auto[0][1]:auto[0][1] + 40],
        "blocking_network_wait_outside_all_gates":
            all(not re.search(r"\.(?:getResult|waitResult)\(", g[2]) for g in gates),
        "contact_and_marker_writes_require_owner_after_reply":
            len(result) == 1 and result[0][0] > code.index("future.waitResult()")
            and "serverSyncMarker = lastSyncMarker" in result[0][2]
            and "== true else { return }" in code[result[0][1]:result[0][1] + 40],
        "normal_same_owner_network_path_retained":
            all(s in code for s in [
                "tinode.connectDefault(inBackground: true)", "tinode.loginToken(token: token, creds: nil)",
                "tinode.subscribe(to: Tinode.kTopicFnd", "tinode.setMeta(for: Tinode.kTopicFnd",
                "tinode.getMeta(topic: Tinode.kTopicFnd"])
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-revision")
    args = parser.parse_args()
    source = (subprocess.check_output(
        ["git", "show", f"{args.source_revision}:{RELATIVE}"], cwd=ROOT).decode("utf-8")
        if args.source_revision else (ROOT / RELATIVE).read_text(encoding="utf-8"))
    results = checks(source)
    print(json.dumps({"level": "source-contract-only", "source": args.source_revision or "working-tree",
                      "passed": sum(results.values()), "total": len(results), "checks": results}, indent=2))
    raise SystemExit(0 if all(results.values()) else 1)


if __name__ == "__main__":
    main()

