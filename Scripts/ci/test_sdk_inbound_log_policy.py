#!/usr/bin/env python3
"""Exact inbound log entry check; source evidence, not runtime log interception."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
source = (subprocess.check_output(["git", "show", sys.argv[1] + ":TinodeSDK/Tinode.swift"], cwd=root).decode("utf-8")
          if len(sys.argv) > 1 else (root / "TinodeSDK/Tinode.swift").read_text(encoding="utf-8"))
entry = source.split("func onMessage(with message: String)", 1)[1].split("func onDisconnect(", 1)[0]
debug = [line.strip() for line in entry.splitlines() if "Log.default.debug(" in line]
assert debug == ['Log.default.debug("packet_in")'], "Inbound packet log must be one fixed event"
errors = [line.strip() for line in entry.splitlines() if "Log.default.error(" in line]
assert errors == ['Log.default.error("packet_in_failed")'], "Receive failures must not print arbitrary error descriptions"
assert "localizedDescription" not in entry
assert "try tinode.dispatch(message)" in entry, "Actual dispatch path must remain"
print("Inbound log source entry PASS; runtime log interception NOT_RUN")
