# LOCAL-DELETE

Base 4da8391b19ebe03d4a4ed7d4fb21ae428a89167e. Four production files only; manifest.json identifies exact files/hashes and twelve added native methods.

## Behavior
AccountDeletionStorage is an optional observable capability in Tinode.swift; the existing Storage.deleteAccount Void requirement is unchanged. SqlStore implements Bool deleteAccountData; old Void delegates with a fixed failure event. Unsupported Storage does not receive a blind Void cleanup call.
After exact matching200, Tinode always retires the original session. Bool false or unsupported produces accountDeletedLocalCleanupIncomplete: remote account deletion is confirmed, local database cleanup incomplete. Neither the finish helper nor recovery retries the remote request.
BaseDb now performs direct bound SQL in accessQueue → one immediate SQLite transaction. Any statement/commit failure returns false with all database data rolled back; active memory pointer changes only after commit. Zero child rows are valid; missing account is local idempotent success; an existing target account DELETE must affect exactly one row. The original pointer survives failure so existing logout deactivates the retained account, or blocks the database if deactivation itself fails.
Recovery captures original Store/UID and the post-logout anonymous SDK. The actual shared AccountDeletionRecovery method locks SDK session, then injected production Cache.ifCurrent/generation scope, verifies both UIDs nil and exact Store instance, and holds that scope through the synchronous local write. B, replacement slot/generation/Store or retirement rejects the retry. The page uses this production helper and offers 重试本机清理 / 暂不处理. Success means local account database records were removed, not filesystem erasure.

## Schema and scope
Schema113 strict gate allows accounts, users, topics, subscriptions, messages plus global claw_local_migrations and SQLite internal tables. No FTS or separate attachment table. Dependency order: messages by captured account topic → subscriptions by topic → topics by account → users by account → account by id AND uid. head/content attachment metadata is inside the removed message rows. Cross-account user_id references fail FK and roll back; scope never expands to B. Global migration markers and sqlite_sequence remain.
Lock order remains SDK → Cache → SqlStore.accountLock → BaseDb.accessQueue → SQLite. No accessQueue recursion through sharedInstance/logout and no SDK/Cache call inside the database transaction.

## Evidence
Prior LOCAL-DELETE-PLAN/sqlite-red.json: three real SQLite faults with a source call-order adapter reproduce partial commits reported successful. This is not Swift execution.
Current check_local_delete_sqlite.py extracts the five production DELETE strings and executes them in SQLite: eleven cases PASS, including each statement ABORT, COMMIT authorization rejection, ignored account delete/zero effect, success/empty children/repeat and cross-account FK. All failed cases fully preserve A and B; successful cases preserve B.
All44 standalone source policies PASS and diff --check PASS on Windows.
Twelve additional native methods: four SDK tests execute actual finish/recovery with observable/legacy Storage spies; eight LocalMigration tests execute actual BaseDb/SqlStore with genuine SQLite triggers/commitHook, complete five-table snapshots, empty/repeat, markers/sequences and another-account protections. Actual UI Cache injection wiring is source-checked; controlled slot closures are not a full UIKit interaction test.
Expected next cumulative native: SDK41 + storage140 =181. This delta and preceding ACK/COPY are NOT_RUN on Mac at seal time. CI10 d61855f run35309485402/job105488355128 passed the earlier162 and cold launch; its result does not validate these later commits.

## Limits
No deletion of real user accounts or production server in tests. No durable cross-restart automatic local-cleanup queue; dismissing recovery does not promise later automatic cleanup. Kingfisher cache, exported files, backups, filesystem free space and remote replicas are not securely erased by SQLite row deletion. No claim of disk-wide purge or universal account-data destruction.
