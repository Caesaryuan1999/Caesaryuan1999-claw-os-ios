# SDK-DELETE-ACK01

Base d61855fd1534cb864fb5f6848eec3fa1b7dcce4a. One production file: TinodeSDK/Tinode.swift.
Confirmed source counterexample: generic dispatch resolves matching ctrl 200..<400. The prior delCurrentUser ignored that packet and deleted local storage/retired the SDK even for 205/300. source-before.json records a failing source constraint, not an executed Swift red test.

The public delCurrentUser request still creates its ID and calls the unchanged sendWithPromise. Its actual callback passes packet plus captured request ID and UID into internal finishAccountDeletion. Only present ctrl, exact request ID and code200 permits existing owner/Store/session-gated cleanup. Missing/other request/non200 returns fixed requestOutcomeUnknown and performs no cleanup. Generic dispatch is byte-identical; 403 still takes its original explicit rejection before the finish helper. No socket/public protocol change.

Seven native methods in the existing SDK test class call the same production finish helper using actual Tinode and a Storage protocol spy: 300,205,exact200,missing control/wrong ID/malformed JSON,403 defense,retired late200,Store switched to B. Real decoding/session retirement/credential clearing execute; the spy only observes delete/logout. No WebSocket, real service or real database deletion is claimed. The helper403 test does not substitute for source-preserved dispatcher behavior.
Expected SDK37 plus storage132 =169 methods, pending Mac. Prior CI9 only verified152 and CI10 is fixed earlier d61855f/162; do not count this delta as run.

Local cleanup limitation discovered during review: Storage.deleteAccount is Void; SqlStore58–62 only logs false from BaseDb.deleteUid. BaseDb188–220 clears account pointer before the savepoint and only logs false accessor results, potentially returning true despite a failed sub-delete. Exact200 here confirms the remote response and requests existing local cleanup; it does not prove local purge succeeded. This separate local atomicity unit is pending proposal, not silently fixed or represented as complete. Copy must not promise local data fully erased.
