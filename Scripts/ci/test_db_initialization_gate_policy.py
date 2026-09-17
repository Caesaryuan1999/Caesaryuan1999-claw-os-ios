"""Production gate wiring only. Concurrency and SQLite behavior require native XCTest."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "TinodiosDB/BaseDb.swift").read_text(encoding="utf-8")
tests = (ROOT / "TinodiosUITests/TinodiosUITests.swift").read_text(encoding="utf-8")
registry = source.split("private static func initializationGate(at", 1)[1].split(
    "// Serializes only initialization", 1)[0]
assert ".standardizedFileURL.resolvingSymlinksInPath().path" in registry
assert ".lowercased()" not in registry
assert "defer { initializationRegistryLock.unlock() }" in registry
assert "gate.lock.lock()" not in registry
gate = source.split("static func withInitializationGate<Value>", 1)[1].split(
    "static func openPreparedDatabase(at", 1)[0]
assert "NSRecursiveLock()" in source
assert "defer { gate.lock.unlock() }" in gate
assert "guard !gate.initializing else { throw OpenError.reentrantInitialization }" in gate
assert "defer { gate.initializing = false }" in gate
assert "return try operation()" in gate
wrapper = source.split("static func openPreparedDatabase(at", 1)[1].split(
    "private static func openPreparedDatabaseWithinGate", 1)[0]
assert "return try withInitializationGate(at: path)" in wrapper
assert "try openPreparedDatabaseWithinGate" in wrapper
assert "stage: .initializationGate" in wrapper and "throw error" in wrapper
assert "case .reentrantInitialization" in wrapper
assert "initializationGates.remove" not in source
assert "readOnly.busyTimeout = 5" in source and "database.busyTimeout = 5" in source
concurrent = tests.split("func testTwoConcurrentInitializersCommitOnlyOneMarker", 1)[1].split(
    "func testInitializationGateAllowsDifferentPaths", 1)[0]
assert "for round in 1...12" in concurrent
assert "DispatchQueue.concurrentPerform(iterations: 2)" in concurrent
assert "available.filter { $0 }.count, 2" in concurrent
assert 'WHERE status=35") as? Int64, 5' in concurrent
for method in ("AllowsDifferentPathsToOpenConcurrently", "ReleasesAfterOriginalSchemaError",
               "RejectsSameThreadReentryWithoutDeadlock", "CanonicalAliasesUseTheActualSameGate"):
    assert "func testInitializationGate" + method in tests
print("DB initialization lifecycle gate source wiring PASS; native execution required")
