#!/usr/bin/env python3
"""Exact production logout caller wiring; this is not a UIKit runtime test."""
import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def source(name, ref):
    if ref:
        return subprocess.check_output(["git", "show", f"{ref}:Tinodios/{name}"], cwd=ROOT).decode("utf-8")
    return (ROOT / "Tinodios" / name).read_text(encoding="utf-8")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-ref")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    account = source("AccountSettingsViewController.swift", args.source_ref)
    security = source("SettingsSecurityViewController.swift", args.source_ref)
    ac = account.split("private func confirmLogout()", 1)[1].split("private func reloadData()", 1)[0]
    sc = security.split("@objc func logoutClicked", 1)[1].split("private func updatePassword", 1)[0]
    tail = security.split("private func logout(", 1)[1]
    success = tail.split(".thenApply", 1)[1].split(".thenCatch", 1)[0]
    failure = tail.split(".thenCatch", 1)[1]
    copy = "退出后需重新登录。本机待发送和发送结果待确认的消息将保留。"
    owner_gate = "Cache.sessionGeneration == generation, owner.myUid == uid, Cache.isCurrent(owner)"
    checks = {
        "account-dialog-captures-owner-uid-generation": all(v in ac for v in ("let owner = tinode", "let uid = owner.myUid", "let generation = Cache.sessionGeneration")),
        "security-dialog-captures-owner-uid-generation": all(v in sc for v in ("let owner = tinode", "let uid = owner.myUid", "let generation = Cache.sessionGeneration")),
        "both-logout-actions-use-original-owner": "logout(owner: owner, uid: uid, generation: generation)" in ac and "logout(owner: owner, uid: uid, generation: generation)" in sc,
        "both-execute-gate-offline-without-auth": owner_gate in ac and owner_gate in tail and "isConnectionAuthenticated" not in ac + sc + tail,
        "both-clear-with-ifCurrent-not-current-sdk": "logoutAndRouteToLoginVC(ifCurrent: owner)" in ac and "logoutAndRouteToLoginVC(ifCurrent: owner)" in tail and "Cache.tinode" not in ac,
        "both-copy-and-destructive-action": copy in ac and copy in sc and ".destructive" in ac and ".destructive" in sc,
        "delete-dispatch-bound-to-confirmed-owner": "deleteAccount(owner: owner, uid: uid, generation: generation)" in sc and "owner.delCurrentUser(hard: true)" in tail,
        "delete-success-can-clear-retired-original-owner": "DispatchQueue.main.async" in success and "logoutAndRouteToLoginVC(ifCurrent: owner)" in success and "guard Cache.isCurrent" not in success,
        "delete-failure-cannot-toast-new-owner": "DispatchQueue.main.async" in failure and owner_gate in failure and "ToastFailureHandler(err: error)" in failure,
    }
    result = {"level": "source_wiring_not_UIKit", "ref": args.source_ref or "working-tree",
              "passed": sum(checks.values()), "total": len(checks), "checks": checks}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result))
    assert all(checks.values()), result

if __name__ == "__main__":
    main()
