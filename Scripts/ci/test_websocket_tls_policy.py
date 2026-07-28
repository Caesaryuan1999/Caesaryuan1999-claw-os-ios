#!/usr/bin/env python3

from pathlib import Path


source = Path("TinodeSDK/WebSocket.swift").read_text(encoding="utf-8")

for forbidden in (
    "URLCredential(trust:",
    "serverTrust!",
    ".cancelAuthenticationChallenge",
):
    if forbidden in source:
        raise SystemExit(
            f"WebSocket TLS policy violation: forbidden expression {forbidden!r}"
        )

print("WebSocket TLS policy OK: URLSession uses system trust evaluation.")
