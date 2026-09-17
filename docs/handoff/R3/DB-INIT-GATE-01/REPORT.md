# DB-INIT-GATE-01
Parent: 3c21ce0048108c356bee08e5f7dfdbdf0cde4328. One production file (BaseDb.swift), existing native test file, one source policy, and report/evidence.

## Evidence and scope
CI7 exact 003a1df / run35284862345: SDK30 passed; storage105 had one failing concurrent-initializer method with four assertions (rounds5/6/7/11). Safe live diagnostics: migrationBegin primary10, extended3850 (SQLITE_IOERR_LOCK), system errno9, SQLite3043002, journaldelete. errno9 alone does not distinguish a closed descriptor from a write-lock attempt using a read-only descriptor. Apple VFS internal cause is not established.
This change is an application-layer mitigation that serializes initialization lifecycles for one canonical path. It is not a claimed fix to SQLite/Apple VFS.

## Implementation
- The registry key is URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path; case is preserved.
- A short static NSLock protects only the registry lookup/insertion. Gates are retained for process lifetime to avoid parallel replacement locks while waiters still own an old gate.
- Each gate uses NSRecursiveLock plus initializing. Other threads wait; same-thread recursive initialization throws typed OpenError.reentrantInitialization rather than deadlocking or reopening. Defers reset the flag before releasing the lock on every exit.
- The production openPreparedDatabase wrapper gates the full unchanged inner function: read-only preflight/snapshot, writable open, existing migration transaction through COMMIT and return. Original error/onFailure/live diagnostics remain. The new reentry diagnostic uses only fixed stage/category, no path/SQL/bindings.
- No retry, busy-timeout change, journal setting, SQL/schema/marker change, or serialization of ordinary post-open transactions. Normal returned connections remain usable independently.
- Not claimed: hard-link identity, dynamic symlink retargeting, case-folding aliases, process-to-process coordination, or retiring already-open connections. Existing SQLite transaction protection across app/NSE still applies.

## Real native regressions, not string-only tests
The existing method remains byte-identical: 12 separate UUID old113 nonempty fixtures, two concurrent production BaseDb constructors each, every round requires available2, markers2 and status35 count5.
Four new LocalMigration methods selected by the existing CI selector:
1. Hold one real initializer at its existing readOnlyOpen observer; a different path must finish before the first is released. Barriers are bounded and only one path is deliberately held.
2. Original unsupportedSchema failure escapes unchanged; restoring the synthetic fixture version permits a subsequent successful actual open, proving gate release after throw.
3. Reenter actual open from its observer on the same thread: typed rejection within a bounded wait, outer open succeeds, subsequent open succeeds.
4. Actual production gate + actual opens through dot/dot-dot and a fixed symlink must hit the same typed reentry guard; after release aliases open successfully. This checks gate behavior, not merely path-string equality.
Native expectation is now SDK30 + storage122 = 152 methods. Twelve repetitions remain one method, not 12 tests. Windows source evidence does not execute Swift/SQLite.swift/VFS behavior; Mac CI8 is required.

## Source preservation
The old inner open body, prepareDatabase/validation tail, SQL constants and original12-round test are exact against parent3c21ce0 after EOL normalization, recorded in source-evidence.json. No UI changes are included in this commit.
