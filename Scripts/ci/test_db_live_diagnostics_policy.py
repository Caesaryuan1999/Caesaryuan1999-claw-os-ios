"""Source privacy/order check only; native XCTest validates the live SQLite getter."""
from pathlib import Path

source = (Path(__file__).resolve().parents[2] / "TinodiosDB/BaseDb.swift").read_text(encoding="utf-8")
live = source.split("static func liveInitializationDiagnostic", 1)[1].split(
    "static func withInitializationFailureDiagnostics", 1)[0]
assert live.index("sqlite3_extended_errcode") < live.index("sqlite3_system_errno")
assert live.index("sqlite3_system_errno") < live.index('database.scalar("PRAGMA main.journal_mode")')
assert "extended & 0xff == primary" in live
assert "diagnostic.liveErrorState = .mismatched" in live
assert "JournalMode(rawValue:" in live and "?? .unknown" in live
for forbidden in ("localizedDescription", "sqlite3_errmsg", "strerror", "String(cString", "print(", "Log."):
    assert forbidden not in live, forbidden
wrapper = source.split("static func withInitializationFailureDiagnostics", 1)[1].split(
    "static let migrationCreateSQL", 1)[0]
assert "return try operation()" in wrapper and "throw error" in wrapper
assert "usesExtendedErrorCodes =" not in source
print("PASS: live initialization diagnostic uses numeric codes, fixed enum, original error")
