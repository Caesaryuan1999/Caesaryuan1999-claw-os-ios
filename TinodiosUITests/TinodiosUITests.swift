//
//  TinodiosUITests.swift
//  TinodiosUITests
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import XCTest

import Network
@testable import TinodeSDK
@testable import TinodiosDB
import SQLite

// Runs against isolated SQLite files; does not launch or clear the app database.
final class PublishStorageTests: XCTestCase {
    func testTwoConcurrentClaimsDispatchOnlyOneCopy() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        // Retain this unique synthetic fixture until the test process exits.
        // Never unlink an SQLite file while a connection may still own it.
        let first = try SQLite.Connection(url.path)
        let second = try SQLite.Connection(url.path)
        first.busyTimeout = 2
        second.busyTimeout = 2
        try first.run("CREATE TABLE messages (id INTEGER PRIMARY KEY, status INTEGER, content TEXT)")
        try first.run("INSERT INTO messages VALUES (1, 20, 'preserve me')")
        let lock = NSLock()
        var claims = [Bool]()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let claimed = MessageDb.transitionStatus(in: index == 0 ? first : second,
                msgId: 1, from: .queued, to: .sending)
            lock.lock()
            claims.append(claimed)
            lock.unlock()
        }
        XCTAssertEqual(claims.filter { $0 }.count, 1)
        XCTAssertEqual(try first.scalar("SELECT status FROM messages WHERE id=1") as? Int64, 30)
        XCTAssertEqual(try first.scalar("SELECT content FROM messages WHERE id=1") as? String, "preserve me")
    }

    func testReopenPreservesUnknownAndOnlyReplaysNeverSentMessages() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        // Keep the synthetic file until process teardown closes all handles.
        do {
            let db = try SQLite.Connection(url.path)
            try db.run("CREATE TABLE messages (id INTEGER PRIMARY KEY, status INTEGER, content TEXT)")
            try db.run("INSERT INTO messages VALUES (1,20,'queued'),(2,30,'interrupted'),(3,35,'unknown'),(4,40,'failed'),(5,50,'accepted')")
        }
        let reopened = try SQLite.Connection(url.path)
        XCTAssertTrue(MessageDb.recoverInterruptedPublishes(in: reopened))
        XCTAssertEqual(try reopened.scalar("SELECT COUNT(*) FROM messages WHERE status=20") as? Int64, 1)
        XCTAssertEqual(try reopened.scalar("SELECT COUNT(*) FROM messages WHERE status=35") as? Int64, 2)
        XCTAssertEqual(try reopened.scalar("SELECT COUNT(*) FROM messages") as? Int64, 5)
        XCTAssertFalse(MessageDb.transitionStatus(in: reopened, msgId: 2, from: .queued, to: .sending))
        XCTAssertFalse(MessageDb.transitionStatus(in: reopened, msgId: 3, from: .queued, to: .sending))
        XCTAssertFalse(MessageDb.transitionStatus(in: reopened, msgId: 4, from: .queued, to: .sending))
    }

    func testOnlyConfirmedMessagesAreSynced() {
        for status in [BaseDb.Status.sending, .unconfirmed, .failed] {
            let message = StoredMessage()
            message.dbStatus = status
            XCTAssertFalse(message.isSynced)
        }
        let unknown = StoredMessage()
        unknown.dbStatus = .unconfirmed
        XCTAssertTrue(unknown.isUnconfirmed)
        XCTAssertFalse(unknown.isReady)
    }

    func testLateFailureCannotDowngradeAcceptedOrUnknownMessages() throws {
        let db = try SQLite.Connection(.inMemory)
        try db.run("CREATE TABLE messages (id INTEGER PRIMARY KEY, status INTEGER)")
        try db.run("INSERT INTO messages VALUES (1,50),(2,35),(3,10),(4,30)")
        XCTAssertFalse(MessageDb.markPendingFailed(in: db, msgId: 1))
        XCTAssertFalse(MessageDb.markPendingFailed(in: db, msgId: 2))
        XCTAssertTrue(MessageDb.markPendingFailed(in: db, msgId: 3))
        XCTAssertFalse(MessageDb.markPendingFailed(in: db, msgId: 4))
        XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=1") as? Int64, 50)
        XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=2") as? Int64, 35)
        XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM messages WHERE status=40") as? Int64, 1)
    }
}

class FakeTinodeServer {
    var listener: NWListener
    var connectedClients: [NWConnection] = []
    private let startupSemaphore = DispatchSemaphore(value: 0)
    private var startupSucceeded = false

    // Request types.
    enum RequestType {
        case none, hi, acc, login, sub, get, set, pub, leave, note, del
    }
    // Request handlers.
    var requestHandlers: [RequestType : ((ClientMessage<Int, Int>) -> [ServerMessage])] = [:]

    init(port: UInt16) {
        let parameters = NWParameters(tls: nil)
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true

        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        do {
            if let port = NWEndpoint.Port(rawValue: port) {
                listener = try NWListener(using: parameters, on: port)
            } else {
                fatalError("Unable to start WebSocket server on port \(port)")
            }
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    func startServer() {
        let serverQueue = DispatchQueue(label: "ServerQueue")

        listener.newConnectionHandler = { newConnection in
            print("New connection connecting")

            self.connectedClients.append(newConnection)
            func receive() {
                newConnection.receiveMessage { (data, context, isComplete, error) in
                    if let data = data, let context = context {
                        print("Received a new message from client")
                        try! self.handleClientMessage(data: data, context: context, stringVal: "", connection: newConnection)
                        receive()
                    }
                }
            }
            receive()

            newConnection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("Client ready")
                case .failed(let error):
                    print("Client connection failed \(error.localizedDescription)")
                case .waiting(let error):
                    print("Waiting for long time \(error.localizedDescription)")
                default:
                    break
                }
            }

            newConnection.start(queue: serverQueue)
        }

        listener.stateUpdateHandler = { state in
            print(state)
            switch state {
            case .ready:
                print("Server Ready")
                self.startupSucceeded = true
                self.startupSemaphore.signal()
            case .failed(let error):
                print("Server failed with \(error.localizedDescription)")
                self.startupSucceeded = false
                self.startupSemaphore.signal()
            default:
                break
            }
        }

        listener.start(queue: serverQueue)
    }

    func waitUntilReady(timeout: TimeInterval = 5) -> Bool {
        startupSemaphore.wait(timeout: .now() + timeout) == .success && startupSucceeded
    }

    func stopServer() {
        listener.cancel()
    }

    func handleClientMessage(data: Data, context: NWConnection.ContentContext, stringVal: String, connection: NWConnection) throws {
        let message = try Tinode.jsonDecoder.decode(ClientMessage<Int, Int>.self, from: data)

        print("--> received: \(String(decoding: data, as: UTF8.self))")
        var reqType: RequestType = .none
        if message.hi != nil {
            reqType = .hi
        } else if message.login != nil {
            reqType = .login
        } else if message.sub != nil {
            reqType = .sub
        } else if message.get != nil {
            reqType = .get
        } else if message.set != nil {
            reqType = .set
        } else if message.pub != nil {
            reqType = .pub
        } else if message.leave != nil {
            reqType = .leave
        } else if message.note != nil {
            reqType = .note
        } else if message.del != nil {
            reqType = .del
        }
        self.requestHandlers[reqType]?(message).forEach { self.sendResponse(response: $0, into: connection) }
    }

    func addHandler(forRequestType type: RequestType, handler: @escaping ((ClientMessage<Int, Int>) -> [ServerMessage])) {
        self.requestHandlers[type] = handler
    }

    func sendResponse(response: ServerMessage, into connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "textContext",
                                                  metadata: [metadata])
        do {
            let data = try Tinode.jsonEncoder.encode(response)
            print("sending --> \(String(decoding: data, as: UTF8.self))")
            connection.send(content: data, contentContext: context, isComplete: true,
                            completion: .contentProcessed({ error in
                                if let error = error {
                                    print(error.localizedDescription)
                                }
                            }))
        } catch {
            print("Error sending response: \(error)")
        }
    }
}

// These tests use BaseDb's production path with independent synthetic old data.
// Prepared on Windows; execution requires the Mac SQLite.swift/XCTest target.
final class LocalMigrationTests: XCTestCase {
    func testSchemaReadPropagatesSQLiteStepError() throws {
        let database = try SQLite.Connection(.inMemory)
        // Valid preparation followed by an integer-overflow error during step.
        // The gate must throw, not crash through Sequence.next()'s try!.
        XCTAssertThrowsError(try BaseDb.schemaRows(in: database, sql: "SELECT abs(-9223372036854775808)"))
        let rows = try BaseDb.schemaRows(in: database, sql: "SELECT 1 UNION ALL SELECT 2")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0][0] as? Int64, 1)
        XCTAssertEqual(rows[1][0] as? Int64, 2)
    }

    private static let fixtureSQL = """
    -- Synthetic old-version 113 fixture, transcribed from the five table builders
    -- at 97e21f49 / takeover-20260917-214922. No real accounts or attachment data.
    PRAGMA user_version = 113;
    CREATE TABLE accounts (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, uid TEXT, last_active INTEGER, cred_methods TEXT, device_id TEXT);
    CREATE UNIQUE INDEX accounts_uid ON accounts(uid);
    CREATE TABLE users (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, account_id INTEGER REFERENCES accounts(id), uid TEXT, updated TEXT, pub TEXT, account_name TEXT);
    CREATE INDEX users_account_uid ON users(account_id, uid);
    CREATE TABLE topics (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, account_id INTEGER REFERENCES accounts(id), status INTEGER, topic TEXT, type INTEGER, visible INTEGER, created TEXT, updated TEXT, read INTEGER, recv INTEGER, seq INTEGER, clear INTEGER, max_del INTEGER, mode TEXT, defacs TEXT, last_used TEXT, min_local_seq INTEGER, max_local_seq INTEGER, next_unsent_seq INTEGER, tags TEXT, creds TEXT, pub TEXT, priv TEXT, trusted TEXT);
    CREATE UNIQUE INDEX topics_account_topic ON topics(account_id, topic);
    CREATE TABLE subscriptions (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, topic_id INTEGER REFERENCES topics(id), user_id INTEGER REFERENCES users(id), status INTEGER, mode TEXT, updated TEXT, read INTEGER, recv INTEGER, clear INTEGER, priv TEXT, last_seen TEXT, user_agent TEXT, subscription_class TEXT NOT NULL);
    CREATE UNIQUE INDEX subscriptions_topic_user ON subscriptions(topic_id, user_id);
    CREATE TABLE messages (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, topic_id INTEGER REFERENCES topics(id), user_id INTEGER REFERENCES users(id), status INTEGER, sender TEXT, ts TEXT, seq INTEGER, high INTEGER, del_id INTEGER, repl_seq INTEGER, effective_seq INTEGER, effective_ts TEXT, head TEXT, content TEXT);
    CREATE UNIQUE INDEX messages_topic_seq ON messages(topic_id, seq DESC);
    CREATE UNIQUE INDEX messages_topic_effective ON messages(topic_id, effective_seq DESC) WHERE effective_seq IS NOT NULL;
    INSERT INTO accounts VALUES (1,'usrFixtureA',1,NULL,'fixture-device'),(2,'usrFixtureB',0,NULL,NULL);
    INSERT INTO users(id,account_id,uid,updated,pub,account_name) VALUES (1,1,'usrFixtureA','2026-09-01T00:00:00.000','{"fn":"甲"}','fixtureA'),(2,2,'usrFixtureB','2026-09-01T00:00:00.000','{"fn":"乙"}','fixtureB');
    INSERT INTO topics(id,account_id,status,topic,type,visible,seq,next_unsent_seq) VALUES (1,1,50,'grpFixtureA',2,1,8,2000000007),(2,2,50,'grpFixtureB',2,1,1,2000000001);
    INSERT INTO subscriptions(id,topic_id,user_id,status,mode,subscription_class) VALUES (1,1,1,50,'JRWP','DefaultSubscription'),(2,2,2,50,'JRWP','DefaultSubscription');
    -- Rows 2 and 3 deliberately have identical content/head/timestamp: only the
    -- external event history knows whether dispatch happened; SQLite cannot know.
    INSERT INTO messages(id,topic_id,user_id,status,sender,ts,seq,effective_seq,head,content) VALUES
    (1,1,1,10,'usrFixtureA','2026-09-01T00:00:00.000',2000000001,2000000001,NULL,'草稿'),
    (2,1,1,20,'usrFixtureA','2026-09-01T00:00:00.000',2000000002,2000000002,'{"attachments":["/v0/file/s/fixture-safe"]}','同样文本与附件'),
    (3,1,1,20,'usrFixtureA','2026-09-01T00:00:00.000',2000000003,2000000003,'{"attachments":["/v0/file/s/fixture-safe"]}','同样文本与附件'),
    (4,1,1,30,'usrFixtureA','2026-09-01T00:00:00.000',2000000004,2000000004,NULL,'在途'),
    (5,1,1,40,'usrFixtureA','2026-09-01T00:00:00.000',2000000005,2000000005,NULL,'明确失败'),
    (6,1,1,50,'usrFixtureA','2026-09-01T00:00:00.000',6,6,NULL,'已确认'),
    (7,2,2,20,'usrFixtureB','2026-09-01T00:00:00.000',2000000001,2000000001,NULL,'另一个账户');
    INSERT INTO messages(id,topic_id,user_id,status,sender,ts,seq,repl_seq,effective_seq,effective_ts,head,content) VALUES
    (8,1,1,20,'usrFixtureA','2026-09-01T00:00:00.000',2000000006,6,2000000006,'2026-09-01T00:00:00.000','{"replace":"msg:6"}','编辑修订');
    INSERT INTO messages(id,topic_id,status,seq,high,del_id) VALUES (9,1,80,7,9,1);
    """

    private func withFixture(_ body: (URL, SQLite.Connection) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // BaseDb accessors may retain their connection for the process lifetime.
        // Preserve this unique fixture instead of unlinking a live SQLite inode.
        let file = folder.appendingPathComponent("old113.sqlite")
        let database = try SQLite.Connection(file.path)
        try database.execute(Self.fixtureSQL)
        try body(file, database)
    }

    private func preservedData(_ database: SQLite.Connection) throws -> [String] {
        var snapshot = [String]()
        for table in ["accounts", "users", "topics", "subscriptions", "messages"] {
            let columns = try database.prepare("PRAGMA table_info(\(table))").compactMap { $0[1] as? String }
                .filter { table != "messages" || $0 != "status" }
            for row in try database.prepare("SELECT \(columns.joined(separator: ",")) FROM \(table) ORDER BY id") {
                snapshot.append(table + ":" + row.map { String(describing: $0) }.joined(separator: "|"))
            }
        }
        return snapshot
    }

    func testFirstUpgradeIsolatesLegacy20And30AndPreservesAllOtherData() throws {
        try withFixture { file, database in
            let before = try preservedData(database)
            let opened = BaseDb(databasePath: file.path)
            XCTAssertTrue(opened.isStoreAvailable)
            XCTAssertEqual(opened.sqlStore?.myUid, "usrFixtureA")
            XCTAssertEqual(try database.scalar("SELECT COUNT(*) FROM messages WHERE status=35") as? Int64, 5)
            XCTAssertEqual(try database.scalar("SELECT COUNT(*) FROM messages WHERE status=20") as? Int64, 0)
            XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=6") as? Int64, 50)
            XCTAssertEqual(try database.scalar("PRAGMA user_version") as? Int64, 113)
            XCTAssertEqual(try preservedData(database), before)
        }
    }

    func testRepeatedNSEOpenLeavesNew20AndMainApp30Untouched() throws {
        try withFixture { file, database in
            XCTAssertTrue(BaseDb(databasePath: file.path).isStoreAvailable)
            try database.run("UPDATE messages SET status=20 WHERE id=1")
            try database.run("UPDATE messages SET status=30 WHERE id=5")
            XCTAssertTrue(BaseDb(databasePath: file.path).isStoreAvailable)
            XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=1") as? Int64, 20)
            XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=5") as? Int64, 30)
            XCTAssertTrue(MessageDb.recoverInterruptedPublishes(in: database))
            XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=1") as? Int64, 20)
            XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=5") as? Int64, 35)
        }
    }

    func testFreshDatabaseHasMarkerBeforeFirstMessage() throws {
        let database = try SQLite.Connection(.inMemory)
        try BaseDb.prepareDatabase(in: database)
        XCTAssertEqual(try database.scalar(BaseDb.migrationReadSQL) as? Int64, 1)
        XCTAssertFalse(try BaseDb.validateSchema(in: database))
        try database.run("INSERT INTO messages(status,content) VALUES (20,'new pending')")
        try BaseDb.prepareDatabase(in: database)
        XCTAssertEqual(try database.scalar("SELECT status FROM messages") as? Int64, 20)
    }

    func testUnsupportedVersionsAndLogoutPreserveExistingTables() throws {
        for version in [0, 112, 114] {
            try withFixture { file, database in
                try database.run("PRAGMA user_version=\(version)")
                let before = try preservedData(database)
                let blocked = BaseDb(databasePath: file.path)
                XCTAssertFalse(blocked.isStoreAvailable)
                XCTAssertNotNil(blocked.sqlStore?.initializationError)
                blocked.logout()
                XCTAssertFalse(blocked.deleteUid("usrFixtureA"))
                XCTAssertEqual(try preservedData(database), before)
                XCTAssertEqual(try database.scalar("PRAGMA user_version") as? Int64, Int64(version))
            }
        }
    }

    func testUnknownColumnTableAndTriggerAreRejectedWithoutRepair() throws {
        for mutation in ["ALTER TABLE messages RENAME COLUMN content TO other_content",
                         "CREATE TABLE unsupported_extension(id INTEGER)",
                         "CREATE TRIGGER unexpected AFTER UPDATE ON messages BEGIN SELECT 1; END"] {
            try withFixture { file, database in
                try database.execute(mutation)
                let schema = try database.scalar("SELECT group_concat(sql) FROM sqlite_master") as? String
                XCTAssertFalse(BaseDb(databasePath: file.path).isStoreAvailable)
                XCTAssertEqual(try database.scalar("SELECT group_concat(sql) FROM sqlite_master") as? String, schema)
                XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=2") as? Int64, 20)
            }
        }
    }

    func testMissingUniqueIndexAndWrongPartialPredicateAreRejected() throws {
        for mutation in ["DROP INDEX messages_topic_seq",
                         "DROP INDEX messages_topic_effective; CREATE UNIQUE INDEX wrong ON messages(topic_id,effective_seq) WHERE effective_seq>0"] {
            try withFixture { file, database in
                try database.execute(mutation)
                XCTAssertFalse(BaseDb(databasePath: file.path).isStoreAvailable)
                XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=2") as? Int64, 20)
            }
        }
    }

    func testForeignKeyViolationsAndWrongDefinitionsAreRejected() throws {
        try withFixture { file, database in
            try database.run("UPDATE users SET account_id=999 WHERE id=1")
            XCTAssertFalse(BaseDb(databasePath: file.path).isStoreAvailable)
        }
        let database = try SQLite.Connection(.inMemory)
        try database.execute(Self.fixtureSQL.replacingOccurrences(of: "REFERENCES accounts(id)", with: "REFERENCES accounts(uid)"))
        XCTAssertThrowsError(try BaseDb.prepareDatabase(in: database))
        XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=2") as? Int64, 20)
    }

    func testUnknownMarkerRuleBlocksWithoutQuarantine() throws {
        try withFixture { file, database in
            try database.run(BaseDb.migrationCreateSQL)
            try database.run("INSERT INTO claw_local_migrations VALUES ('future-rule',1)")
            XCTAssertFalse(BaseDb(databasePath: file.path).isStoreAvailable)
            XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=2") as? Int64, 20)
        }
    }

    func testMarkerInsertFailureRollsBackPriorStatusUpdates() throws {
        try withFixture { _, database in
            try database.run("CREATE TABLE claw_local_migrations(rule TEXT NOT NULL PRIMARY KEY, completed INTEGER NOT NULL CHECK(completed=0))")
            XCTAssertThrowsError(try BaseDb.prepareDatabase(in: database))
            XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=2") as? Int64, 20)
            XCTAssertEqual(try database.scalar("SELECT COUNT(*) FROM claw_local_migrations") as? Int64, 0)
        }
    }

    func testCommitFailureCannotExposeSuccessfulMarker() throws {
        try withFixture { _, database in
            enum Injected: Error { case commit }
            database.commitHook { throw Injected.commit }
            XCTAssertThrowsError(try BaseDb.prepareDatabase(in: database))
            database.commitHook(nil)
            XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=2") as? Int64, 20)
            XCTAssertEqual(try database.scalar("SELECT COUNT(*) FROM sqlite_master WHERE name='claw_local_migrations'") as? Int64, 0)
        }
    }

    func testTwoConcurrentInitializersCommitOnlyOneMarker() throws {
        try withFixture { file, database in
            let lock = NSLock()
            var available = [Bool]()
            DispatchQueue.concurrentPerform(iterations: 2) { _ in
                let opened = BaseDb(databasePath: file.path)
                lock.lock()
                available.append(opened.isStoreAvailable)
                lock.unlock()
            }
            XCTAssertEqual(available.filter { $0 }.count, 2)
            XCTAssertEqual(try database.scalar("SELECT COUNT(*) FROM claw_local_migrations") as? Int64, 2)
            XCTAssertEqual(try database.scalar("SELECT COUNT(*) FROM messages WHERE status=35") as? Int64, 5)
        }
    }

    func testUnsupportedWalDatabaseBytesSurviveBlockedOpenAndLogout() throws {
        try withFixture { file, database in
            try database.run("PRAGMA journal_mode=WAL")
            try database.run("PRAGMA wal_autocheckpoint=0")
            try database.run("UPDATE messages SET content='preserved WAL content' WHERE id=1")
            try database.run("PRAGMA user_version=114")
            let wal = URL(fileURLWithPath: file.path + "-wal")
            let originalDb = try Data(contentsOf: file)
            let originalWal = try Data(contentsOf: wal)
            let blocked = BaseDb(databasePath: file.path)
            XCTAssertFalse(blocked.isStoreAvailable)
            blocked.logout()
            XCTAssertEqual(try Data(contentsOf: file), originalDb)
            XCTAssertEqual(try Data(contentsOf: wal), originalWal)
        }
    }


    private func withC3Store(_ body: (BaseDb, SQLite.Connection, SqlStore, DefaultComTopic) throws -> Void) throws {
        try withFixture { file, _ in
            let base = BaseDb(databasePath: file.path)
            let db = try XCTUnwrap(base.db)
            let store = try XCTUnwrap(base.sqlStore)
            let sdk = Tinode(for: "fixture", authenticateWith: "fixture", persistDataIn: nil)
            let topic = DefaultComTopic(tinode: sdk, name: "grpFixtureA")
            let stored = StoredTopic()
            stored.id = 1
            stored.minLocalSeq = 6
            stored.maxLocalSeq = 6
            stored.nextUnsentId = 2_000_000_020
            topic.payload = stored
            topic.store = store
            try body(base, db, store, topic)
        }
    }

    private func newC3Message(_ store: SqlStore, _ topic: DefaultComTopic) throws -> Message {
        return try XCTUnwrap(store.msgSend(topic: topic, data: Drafty(plainText: "frozen"), head: nil))
    }

    func testLogoutPreservesOutboundIdentityAndReactivation() throws {
        try withC3Store { base, db, store, topic in
            let queued = try self.newC3Message(store, topic)
            let unknown = try self.newC3Message(store, topic)
            XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: unknown.msgId, sync: true))
            XCTAssertTrue(store.msgUnconfirmed(topic: topic, dbMessageId: unknown.msgId))
            let before = try self.preservedData(db).filter { !$0.hasPrefix("accounts:") }
            let sequence = try db.scalar("SELECT seq FROM sqlite_sequence WHERE name='messages'") as? Int64
            let sdk = Tinode(for: "fixture", authenticateWith: "fixture", persistDataIn: store)
            sdk.authToken = "synthetic"
            sdk.isConnectionAuthenticated = true
            sdk.logout()
            XCTAssertNil(store.myUid)
            XCTAssertFalse(store.isReady)
            XCTAssertNil(sdk.authToken)
            XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM accounts WHERE last_active=1") as? Int64, 0)
            XCTAssertEqual(try self.preservedData(db).filter { !$0.hasPrefix("accounts:") }, before)
            XCTAssertEqual(try db.scalar("SELECT seq FROM sqlite_sequence WHERE name='messages'") as? Int64, sequence)
            store.myUid = "usrFixtureA"
            XCTAssertEqual(store.getMessageById(dbMessageId: queued.msgId)?.head?["clientmsgid"]?.asString(),
                           queued.head?["clientmsgid"]?.asString())
            XCTAssertEqual(store.getMessageById(dbMessageId: unknown.msgId)?.head?["clientmsgid"]?.asString(),
                           unknown.head?["clientmsgid"]?.asString())
            XCTAssertTrue(store.getMessageById(dbMessageId: unknown.msgId)?.isUnconfirmed == true)
            XCTAssertTrue(base.isStoreAvailable)
        }
    }

    func testStaleSDKLogoutAndDeviceFailureCannotDeactivateNewAccount() throws {
        try withC3Store { _, db, store, _ in
            let old = Tinode(for: "fixture", authenticateWith: "fixture", persistDataIn: store)
            old.authToken = "synthetic-A"
            old.logout()
            store.myUid = "usrFixtureB"
            store.deviceToken = "synthetic-device-B"
            old.logout()
            XCTAssertThrowsError(try old.setDeviceToken(token: "old-device").getResult())
            XCTAssertThrowsError(try old.loginToken(token: "old-token", creds: nil).getResult())
            XCTAssertEqual(store.myUid, "usrFixtureB")
            XCTAssertEqual(store.deviceToken, "synthetic-device-B")
            XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM messages") as? Int64, 9)
        }
    }

    func testLogoutCommitFailureDetachesAndBlocksWithoutClearingData() throws {
        try withC3Store { base, db, store, _ in
            let before = try self.preservedData(db)
            enum LogoutFailure: Error { case commit }
            db.commitHook { throw LogoutFailure.commit }
            store.logout()
            db.commitHook(nil)
            XCTAssertNil(store.myUid)
            XCTAssertFalse(store.isReady)
            XCTAssertNotNil(store.initializationError)
            XCTAssertEqual(try self.preservedData(db), before)
            store.myUid = "usrFixtureB"
            XCTAssertNil(store.myUid)
            XCTAssertFalse(base.isStoreAvailable)
        }
    }

    func testC3BoundaryDoesNotTrustInheritedUUIDOr31And36() throws {
        try withFixture { file, db in
            try db.run(BaseDb.migrationCreateSQL)
            try db.run(BaseDb.migrationWriteSQL)
            try db.run("UPDATE messages SET status=31 WHERE id=4")
            try db.run("UPDATE messages SET status=36 WHERE id=5")
            try db.run("UPDATE messages SET head=? WHERE id IN (2,3,4,5)", "{\"clientmsgid\":\"abcdefab-1111-4111-8111-abcdefabcdef\"}")
            let before = try preservedData(db)
            XCTAssertTrue(BaseDb(databasePath: file.path).isStoreAvailable)
            XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM messages WHERE id IN (2,3,4,5) AND status=35") as? Int64, 4)
            XCTAssertEqual(try db.scalar(BaseDb.c3MigrationReadSQL) as? Int64, 1)
            XCTAssertEqual(try preservedData(db), before)
        }
    }

    func testC3RecoveryAndRepeatedNSEInitialization() throws {
        try withC3Store { _, db, _, _ in
            try db.run("UPDATE messages SET status=31 WHERE id=2")
            try db.run("UPDATE messages SET status=30 WHERE id=3")
            try BaseDb.prepareDatabase(in: db)
            XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=2") as? Int64, 31)
            XCTAssertTrue(MessageDb.recoverInterruptedPublishes(in: db))
            XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=2") as? Int64, 36)
            XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=3") as? Int64, 35)
        }
    }

    func testC3NewMessagesOverrideForwardedUUIDAndDraftReadyFreezesPayload() throws {
        try withC3Store { _, db, store, topic in
            let old = "abcdefab-1111-4111-8111-abcdefabcdef"
            let headers: [String: JSONValue] = ["clientmsgid": .string(old), "forwarded": .string("grpOld:7")]
            let first = try XCTUnwrap(store.msgSend(topic: topic, data: Drafty(plainText: "new"), head: headers))
            let second = try XCTUnwrap(store.msgSend(topic: topic, data: Drafty(plainText: "new"), head: headers))
            let key = try XCTUnwrap(C3PublishPolicy.clientMessageId(in: first.head))
            XCTAssertNotEqual(key, old)
            XCTAssertNotEqual(key, C3PublishPolicy.clientMessageId(in: second.head))
            XCTAssertEqual(C3PublishPolicy.clientMessageId(in: store.getMessageById(dbMessageId: first.msgId)?.head), key)
            XCTAssertTrue(store.msgReady(topic: topic, dbMessageId: 1, data: Drafty(plainText: "attachment complete")))
            let ready = try XCTUnwrap(store.getMessageById(dbMessageId: 1))
            XCTAssertNotNil(C3PublishPolicy.clientMessageId(in: ready.head))
            XCTAssertFalse(store.msgReady(topic: topic, dbMessageId: 1, data: Drafty(plainText: "late overwrite")))
            XCTAssertFalse(store.msgDraftUpdate(topic: topic, dbMessageId: 1, data: Drafty(plainText: "late overwrite")))
            XCTAssertEqual(try db.scalar("SELECT content FROM messages WHERE id=1") as? String, ready.content?.serialize())
        }
    }

    func testC3AtomicClaimChecksScopeAndRetainsOriginalKey() throws {
        try withC3Store { _, db, store, topic in
            let message = try newC3Message(store, topic)
            XCTAssertFalse(MessageDb.claimC3(in: db, msgId: message.msgId, topicId: 2, accountId: 1, uid: "usrFixtureA"))
            XCTAssertFalse(MessageDb.claimC3(in: db, msgId: message.msgId, topicId: 1, accountId: 2, uid: "usrFixtureB"))
            XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            XCTAssertFalse(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            XCTAssertTrue(store.msgUnconfirmed(topic: topic, dbMessageId: message.msgId))
            XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            XCTAssertEqual(C3PublishPolicy.clientMessageId(in: store.getMessageById(dbMessageId: message.msgId)?.head),
                           C3PublishPolicy.clientMessageId(in: message.head))
        }
    }

    func testC3TwoConcurrentConnectionsOnlyOneClaim() throws {
        try withFixture { file, _ in
            let base = BaseDb(databasePath: file.path)
            let first = try XCTUnwrap(base.db)
            try first.run("UPDATE messages SET status=20,head=? WHERE id=2", "{\"clientmsgid\":\"abcdefab-1111-4111-8111-abcdefabcdef\"}")
            let second = try SQLite.Connection(file.path)
            second.busyTimeout = 5
            let lock = NSLock()
            var claims = [Bool]()
            DispatchQueue.concurrentPerform(iterations: 2) { index in
                let claimed = MessageDb.claimC3(in: index == 0 ? first : second, msgId: 2, topicId: 1, accountId: 1, uid: "usrFixtureA")
                lock.lock(); claims.append(claimed); lock.unlock()
            }
            XCTAssertEqual(claims.filter { $0 }.count, 1)
        }
    }

    func testC3ClaimCommitFailureDoesNotAuthorizeDispatch() throws {
        try withC3Store { _, db, store, topic in
            let message = try newC3Message(store, topic)
            db.commitHook { throw NSError(domain: "fixture.commit", code: 1) }
            XCTAssertFalse(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            db.commitHook(nil)
            XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=?", message.msgId) as? Int64, 20)
        }
    }

    func testC3LateUploadFailureAndCancelCannotTouchClaimedOrUnknown() throws {
        try withC3Store { _, db, store, topic in
            let message = try newC3Message(store, topic)
            for status in [20,31,35,36,40,50] {
                try db.run("UPDATE messages SET status=? WHERE id=?", status, message.msgId)
                XCTAssertFalse(store.msgFailed(topic: topic, dbMessageId: message.msgId))
                XCTAssertFalse(store.msgDiscardDraft(topic: topic, dbMessageId: message.msgId))
                XCTAssertFalse(store.msgReady(topic: topic, dbMessageId: message.msgId, data: Drafty(plainText: "late")))
                XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=?", message.msgId) as? Int64, Int64(status))
            }
            XCTAssertTrue(store.msgFailed(topic: topic, dbMessageId: 1))
            XCTAssertTrue(store.msgPruneFailed(topic: topic))
            XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=1") as? Int64, 40)
        }
    }

    func testC3Legacy35WithUUIDNeverClaimsAndRaw36DisplaysUnknown() throws {
        try withC3Store { _, db, store, topic in
            let message = try newC3Message(store, topic)
            try db.run("UPDATE messages SET status=35 WHERE id=?", message.msgId)
            XCTAssertFalse(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            let unknown = StoredMessage()
            unknown.dbStatus = .unconfirmedC3
            XCTAssertTrue(unknown.isUnconfirmed)
            XCTAssertTrue(unknown.isReady)
            XCTAssertFalse(unknown.isSynced)
        }
    }

    func testC3NoCapabilityKeepsPersistentQueueAndPromiseRejected() throws {
        try withC3Store { _, db, store, topic in
            let result = topic.publish(content: Drafty(plainText: "retain without C3"))
            XCTAssertTrue(result.isRejected)
            XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM messages WHERE status=20") as? Int64, 1)
            let queued = try XCTUnwrap(store.getQueuedMessages(topic: topic)?.first)
            XCTAssertNotNil(C3PublishPolicy.clientMessageId(in: queued.head))
        }
    }

    func testC3AckAfterUnknownConfirmsAndLateErrorsCannotDowngrade() throws {
        try withC3Store { _, db, store, topic in
            let message = try newC3Message(store, topic)
            XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            XCTAssertTrue(store.msgUnconfirmed(topic: topic, dbMessageId: message.msgId))
            XCTAssertTrue(store.msgDelivered(topic: topic, dbMessageId: message.msgId, timestamp: Date(), seq: 10))
            XCTAssertFalse(store.msgRejected(topic: topic, dbMessageId: message.msgId))
            XCTAssertFalse(store.msgUnconfirmed(topic: topic, dbMessageId: message.msgId))
            XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=?", message.msgId) as? Int64, 50)
        }
    }

    func testC3RetrySecondGateFailureRestoresUnknownRatherThanNewQueue() throws {
        for error in [TinodeError.requestNotSent(C3PublishPolicy.upgradeRequired), .notConnected("connection changed")] {
            try withC3Store { _, db, store, topic in
                let message = try newC3Message(store, topic)
                XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
                XCTAssertTrue(store.msgUnconfirmed(topic: topic, dbMessageId: message.msgId))
                let beforeClaim = try XCTUnwrap(store.getMessageById(dbMessageId: message.msgId))
                XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
                topic.restorePublishFailure(error, msgId: message.msgId, wasUnconfirmed: beforeClaim.isUnconfirmed)
                XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=?", message.msgId) as? Int64, 36)
                XCTAssertFalse(store.msgDiscard(topic: topic, dbMessageId: message.msgId))
            }
        }
    }

    func testC3NewSendSecondGateFailureReturnsToNewQueue() throws {
        try withC3Store { _, db, store, topic in
            let message = try newC3Message(store, topic)
            XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            topic.restorePublishFailure(TinodeError.requestNotSent(C3PublishPolicy.upgradeRequired),
                                        msgId: message.msgId, wasUnconfirmed: message.isUnconfirmed)
            XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=?", message.msgId) as? Int64, 20)
        }
    }

    func testC3LateSecondGateFailureCannotDowngradeCommittedAck() throws {
        try withC3Store { _, db, store, topic in
            let message = try newC3Message(store, topic)
            XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            XCTAssertTrue(store.msgDelivered(topic: topic, dbMessageId: message.msgId, timestamp: Date(), seq: 10))
            for previousUnknown in [false, true] {
                topic.restorePublishFailure(TinodeError.notConnected("late disconnect"),
                                            msgId: message.msgId, wasUnconfirmed: previousUnknown)
            }
            XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=?", message.msgId) as? Int64, 50)
        }
    }

    func testC3HistoryBeforeAckPreservesLocalIdAndOneServerSequence() throws {
        try withC3Store { _, db, store, topic in
            let message = try newC3Message(store, topic)
            XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            let data = MsgServerData()
            data.topic = topic.name; data.from = "usrFixtureA"; data.seq = 10
            data.ts = Date(); data.head = message.head; data.content = message.content
            let received = try XCTUnwrap(store.msgReceived(topic: topic, sub: nil, msg: data))
            XCTAssertEqual(received.msgId, message.msgId)
            XCTAssertTrue(store.msgDelivered(topic: topic, dbMessageId: message.msgId, timestamp: data.ts!, seq: 10))
            XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM messages WHERE topic_id=1 AND seq=10") as? Int64, 1)
        }
    }

    func testC3ExistingHistoryCollisionMergesOnlyMatchingIdentity() throws {
        try withC3Store { _, db, store, topic in
            let message = try newC3Message(store, topic)
            XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            try db.run("INSERT INTO messages(topic_id,user_id,status,sender,seq,effective_seq,head,content) VALUES (1,1,50,'usrFixtureA',10,10,?,'history')", Tinode.serializeObject(message.head!))
            XCTAssertTrue(store.msgDelivered(topic: topic, dbMessageId: message.msgId, timestamp: Date(), seq: 10))
            XCTAssertEqual(try db.scalar("SELECT id FROM messages WHERE topic_id=1 AND seq=10") as? Int64, message.msgId)
            XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM messages WHERE id=8") as? Int64, 1)
        }
    }

    func testC3DifferentUUIDOrSenderCollisionCannotDeleteHistory() throws {
        for kind in ["different-key", "missing-key", "different-sender"] {
            try withC3Store { _, db, store, topic in
                let message = try newC3Message(store, topic)
                XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
                let wrong = kind == "different-sender" ? Tinode.serializeObject(message.head!) :
                    (kind == "different-key" ? "{\"clientmsgid\":\"bbbbbbbb-1111-4111-8111-abcdefabcdef\"}" : nil)
                let sender = kind == "different-sender" ? "usrFixtureB" : "usrFixtureA"
                try db.run("INSERT INTO messages(topic_id,user_id,status,sender,seq,effective_seq,head,content) VALUES (1,1,50,?,10,10,?,'unrelated')", sender, wrong)
                XCTAssertFalse(store.msgDelivered(topic: topic, dbMessageId: message.msgId, timestamp: Date(), seq: 10))
                XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM messages WHERE topic_id=1 AND seq=10") as? Int64, 1)
                XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=?", message.msgId) as? Int64, 31)
            }
        }
    }

    func testC3AckCommitFailureDoesNotAdvanceCacheOrLoseHistory() throws {
        try withC3Store { _, db, store, topic in
            let message = try newC3Message(store, topic)
            XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            try db.run("INSERT INTO messages(topic_id,user_id,status,sender,seq,effective_seq,head,content) VALUES (1,1,50,'usrFixtureA',10,10,?,'history')", Tinode.serializeObject(message.head!))
            let stored = try XCTUnwrap(topic.payload as? StoredTopic)
            let before = stored.maxLocalSeq
            db.commitHook { throw NSError(domain: "fixture.commit", code: 1) }
            XCTAssertFalse(store.msgDelivered(topic: topic, dbMessageId: message.msgId, timestamp: Date(), seq: 10))
            db.commitHook(nil)
            XCTAssertEqual(stored.maxLocalSeq, before)
            XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=?", message.msgId) as? Int64, 31)
            XCTAssertEqual(try db.scalar("SELECT COUNT(*) FROM messages WHERE seq=10") as? Int64, 1)
            XCTAssertFalse(store.msgDelivered(topic: topic, dbMessageId: 99999, timestamp: Date(), seq: 10))
        }
    }

    func testC3ServerDeleteRangePreservesUnconfirmedLocalRows() throws {
        try withC3Store { base, db, store, topic in
            let message = try newC3Message(store, topic)
            XCTAssertTrue(store.msgSyncing(topic: topic, dbMessageId: message.msgId, sync: true))
            XCTAssertTrue(store.msgUnconfirmed(topic: topic, dbMessageId: message.msgId))
            _ = base.messageDb?.deleteOrMarkDeleted(topicId: 1, delId: 2, from: 1, to: nil, hard: false)
            XCTAssertEqual(try db.scalar("SELECT status FROM messages WHERE id=?", message.msgId) as? Int64, 36)
        }
    }

    func testBlockedStoragePreventsSDKConnectPublishAndLocalAcknowledgement() throws {
        try withFixture { file, database in
            try database.run("PRAGMA user_version=114")
            let blocked = BaseDb(databasePath: file.path)
            let sdk = Tinode(for: "fixture", authenticateWith: "fixture", persistDataIn: blocked.sqlStore)
            XCTAssertThrowsError(try sdk.connect(to: "127.0.0.1:9", useTLS: false, inBackground: false)) { error in
                guard case TinodeError.requestNotSent = error else { return XCTFail("Wrong blocked-store outcome") }
            }
            XCTAssertFalse(sdk.reconnectNow(interactively: true, reset: false))
            let result = sdk.publish(topic: "grpFixtureA", head: nil, content: Drafty(plainText: "must not leave device"), attachments: nil)
            XCTAssertTrue(result.isRejected)
            let topic = DefaultComTopic(tinode: sdk, name: "grpFixtureA")
            XCTAssertFalse(blocked.sqlStore!.msgDelivered(topic: topic, dbMessageId: 2, timestamp: Date(), seq: 9))
            XCTAssertEqual(try database.scalar("SELECT status FROM messages WHERE id=2") as? Int64, 20)
        }
    }
}

final class TinodiosUITests: XCTestCase {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    var tinodeServer: FakeTinodeServer!
    var app: XCUIApplication!

    // Delete installed Tinode app.
    private func deleteTinode() {
        app.terminate()
        let clawIcon = springboard.icons["CLAW OS"]
        let icon = clawIcon.exists ? clawIcon : springboard.icons["Tinode"]
        if icon.exists {
            let iconFrame = icon.frame
            let springboardFrame = springboard.frame
            icon.press(forDuration: 5)

            // Tap the little "-" button at approximately where it is. The "-" is not exposed directly
            springboard.coordinate(withNormalizedOffset: CGVector(dx: (iconFrame.minX + 3) / springboardFrame.maxX, dy: (iconFrame.minY + 3) / springboardFrame.maxY)).tap()

            let deleteAppButton = springboard.alerts.buttons["Delete App"]
            guard deleteAppButton.waitForExistence(timeout: 2) else {
                return
            }
            deleteAppButton.tap()

            // Confirm the choice once again when SpringBoard presents it.
            let confirmDeleteButton = springboard.alerts.buttons["Delete"]
            if confirmDeleteButton.waitForExistence(timeout: 2) {
                confirmDeleteButton.tap()
            }
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Tinode will connect to localhost:6060 by default.
        tinodeServer = FakeTinodeServer(port: 6060)
        tinodeServer.startServer()
        XCTAssertTrue(tinodeServer.waitUntilReady(), "Fake Tinode server did not become ready")

        // The CLAW OS development configuration points at the production host.
        // Override the standard defaults before launch so SharedUtils copies the
        // test endpoint into the app-group defaults used by the Tinode client.
        app.launchArguments += [
            "-host_name_preference", "127.0.0.1:6060",
            "-use_tls_preference", "false"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        deleteTinode()
        tinodeServer.requestHandlers.removeAll()
        tinodeServer.stopServer()
    }

    // Tinode message handlers.
    private func hiHandler() {
        tinodeServer.addHandler(forRequestType: .hi, handler: { req in
            let hi = req.hi!
            let response = ServerMessage()
            response.ctrl = MsgServerCtrl(id: hi.id, topic: nil, code: 200, text: "", ts: Date(), params: nil)
            return [response]
        })
    }

    private func loginHandler(success: Bool) {
        tinodeServer.addHandler(forRequestType: .login, handler: { req in
            let login = req.login!
            let response = ServerMessage()
            response.ctrl = success ?
                MsgServerCtrl(id: login.id, topic: nil, code: 200, text: "ok", ts: Date(),
                                          params: ["authlvl": .string("auth"), "token": .string("fake"),
                                                   "user": .string("usrAlice")]) :
                MsgServerCtrl(id: login.id, topic: nil, code: 401, text: "authentication failed", ts: Date(), params: nil)
            return [response]
        })
    }

    private func subHandler() {
        func metaDescMsg(forId id: String?, onTopic topic: String?, currentTime now: Date,
                         defacs: Defacs?, acs: Acs?, lastSeen: Date?, pub: TheCard?, priv: PrivateType?) -> ServerMessage {
            let result = ServerMessage()
            let desc = Description<TheCard, PrivateType>()
            if topic == "me" {
                desc.created = now.addingTimeInterval(-86400)
                desc.updated = desc.created
                desc.touched = desc.created
            }
            desc.defacs = defacs
            desc.acs = acs
            desc.pub = pub
            desc.priv = priv
            if let lastSeen = lastSeen {
                desc.seen = LastSeen(when: lastSeen, ua: "dummy")
            }
            result.meta = MsgServerMeta(id: id, topic: topic, ts: now, desc: desc, sub: nil, del: nil, tags: nil, cred: nil, aux: nil)

            return result
        }
        func subMsg(topic: String, updatedTs: Date?, read: Int, recv: Int, acs: Acs?, pub: TheCard?, priv: PrivateType?) -> DefaultSubscription {
            let sub = DefaultSubscription()
            sub.topic = topic
            sub.updated = updatedTs
            sub.read = read
            sub.recv = recv
            sub.pub = pub
            sub.priv = priv
            sub.acs = acs
            return sub
        }
        tinodeServer.addHandler(forRequestType: .sub, handler: { req in
            let sreq = req.sub!
            guard let topic = sreq.topic else { return [] }
            switch topic {
            case "me":
                let now = Date()
                let responseCtrl = ServerMessage()
                responseCtrl.ctrl = MsgServerCtrl(id: sreq.id, topic: sreq.topic, code: 200, text: "ok", ts: now, params: nil)

                let metaDesc = metaDescMsg(forId: sreq.id, onTopic: "me", currentTime: now, defacs: Defacs(auth: "JRWPA", anon: "N"), acs: nil, lastSeen: nil, pub: TheCard(fn: "Alice"), priv: ["comment": .string("no comment")])

                let metaSub = ServerMessage()
                let subBob = subMsg(topic: "usrBob", updatedTs: now.addingTimeInterval(-86400), read: 2, recv: 2, acs: Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS"), pub: TheCard(fn: "Bob"), priv: ["comment": .string("bla")])

                let subGrp = subMsg(topic: "grpGroup", updatedTs: now.addingTimeInterval(-100000), read: 0, recv: 0, acs: Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS"), pub: TheCard(fn: "Test group"), priv: ["comment": .string("Group description")])
                metaSub.meta = MsgServerMeta(id: sreq.id, topic: "me", ts: now, desc: nil, sub: [subBob, subGrp], del: nil, tags: nil, cred: nil, aux: nil)
                return [responseCtrl, metaDesc, metaSub]
            case "usrBob":
                let now = Date()
                let responseCtrl = ServerMessage()
                responseCtrl.ctrl = MsgServerCtrl(id: sreq.id, topic: sreq.topic, code: 200, text: "ok", ts: now, params: nil)

                let metaDesc = metaDescMsg(forId: sreq.id, onTopic: sreq.topic, currentTime: now, defacs: nil, acs: Acs(given: "JRWPA", want: "JRWPA", mode: "JRWPA"), lastSeen: now.addingTimeInterval(-10), pub: nil, priv: nil)

                let metaSub = ServerMessage()
                let sub1 = subMsg(topic: "usrBob", updatedTs: now.addingTimeInterval(-100), read: 2, recv: 2, acs: Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS"), pub: nil, priv: nil)
                let sub2 = subMsg(topic: "usrAlice", updatedTs: now.addingTimeInterval(-100), read: 2, recv: 2, acs: Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS"), pub: nil, priv: nil)
                metaSub.meta = MsgServerMeta(id: sreq.id, topic: sreq.topic, ts: now, desc: nil, sub: [sub1, sub2], del: nil, tags: nil, cred: nil, aux: nil)

                let data1 = ServerMessage()
                data1.data = MsgServerData(id: sreq.id, topic: sreq.topic, from: sreq.topic, ts: now.addingTimeInterval(-2000), head: nil, seq: 1, content: Drafty(plainText: "hello message"))

                let data2 = ServerMessage()
                data2.data = MsgServerData(id: sreq.id, topic: sreq.topic, from: "usrAlice", ts: now.addingTimeInterval(-1000), head: nil, seq: 2, content: Drafty(plainText: "wassup?"))

                return [responseCtrl, metaDesc, metaSub, data1, data2]
            case "grpGroup":
                let now = Date()
                let responseCtrl = ServerMessage()
                responseCtrl.ctrl = MsgServerCtrl(id: sreq.id, topic: sreq.topic, code: 200, text: "ok", ts: now, params: nil)

                let metaDesc = metaDescMsg(forId: sreq.id, onTopic: sreq.topic, currentTime: now, defacs: Defacs(auth: "JRWPS", anon: "JR"), acs: Acs(given: "JRWPA", want: "JRWPA", mode: "JRWPA"), lastSeen: nil, pub: nil, priv: nil)

                let metaSub = ServerMessage()
                let sub1 = subMsg(topic: "usrBob", updatedTs: now.addingTimeInterval(-100000), read: 0, recv: 0, acs: Acs(given: "JRWPS", want: "JRWPS", mode: "JRWPS"), pub: nil, priv: nil)
                let sub2 = subMsg(topic: "usrAlice", updatedTs: now.addingTimeInterval(-100000), read: 0, recv: 0, acs: Acs(given: "JRWPASDO", want: "JRWPASDO", mode: "JRWPASDO"), pub: nil, priv: nil)
                metaSub.meta = MsgServerMeta(id: sreq.id, topic: sreq.topic, ts: now, desc: nil, sub: [sub1, sub2], del: nil, tags: nil, cred: nil, aux: nil)

                return [responseCtrl, metaDesc, metaSub]
            default:
                return []
            }
        })
    }

    private func pubHandler(responseSeq: Int) {
        tinodeServer.addHandler(forRequestType: .pub, handler: { req in
            let preq = req.pub!
            let now = Date()
            let responseCtrl = ServerMessage()
            responseCtrl.ctrl = MsgServerCtrl(id: preq.id, topic: preq.topic, code: 200, text: "accepted", ts: now,
                                              params: ["seq": .int(responseSeq)])
            return [responseCtrl]
        })
    }

    private func allowLocalNotifications() -> NSObjectProtocol {
        return addUIInterruptionMonitor(withDescription: "Local Notifications") { (alert) -> Bool in
            let notifPermission = "Would Like to Send You Notifications"
            if alert.label.contains(notifPermission) {
                alert.buttons["Allow"].tap()
                return true
            }
            return false
        }
    }

    private func logIntoTinode(shouldSucceed: Bool) {
        // Log in as "alice".
        let elementsQuery = app.scrollViews.otherElements
        let loginText = elementsQuery.textFields["usernameText"]
        XCTAssertTrue(loginText.waitForExistence(timeout: 5))
        loginText.tap()
        loginText.typeText("alice")

        let passwordText = elementsQuery.secureTextFields["passwordText"]
        XCTAssertTrue(passwordText.exists)
        passwordText.tap()
        passwordText.typeText("alice123")

        let signInButton = app.buttons["Sign In"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))
        signInButton.tap()

        if shouldSucceed {
            XCTAssertTrue(loginText.waitForNonExistence(timeout: 10), "Login screen did not transition to the chat list")
        } else {
            XCTAssertTrue(loginText.waitForExistence(timeout: 5), "Login screen unexpectedly disappeared")
        }
    }

    func testLoginFailure() throws {
        hiHandler()
        loginHandler(success: false)

        logIntoTinode(shouldSucceed: false)
    }

    func testLoginBasic() throws {
        hiHandler()
        loginHandler(success: true)
        subHandler()

        // Allow notifications.
        let monitor = allowLocalNotifications()
        defer { removeUIInterruptionMonitor(monitor) }

        logIntoTinode(shouldSucceed: true)

        // "Allow Notifications?" dialog. Make sure modal dialog handler gets triggered.
        app.tap()

        let table = app.tables.element
        XCTAssertTrue(table.waitForExistence(timeout: 10))

        table.cells.waitForCount(2)
        XCTAssertTrue(table.staticTexts["Bob"].exists)
        XCTAssertTrue(table.staticTexts["Test group"].exists)

        // Cached subscriptions are loaded before the background session refresh.
        // Relaunch to verify persisted chat data cannot crash the app at startup.
        app.terminate()
        app.launch()

        let relaunchedTable = app.tables.element
        if relaunchedTable.waitForExistence(timeout: 10) {
            relaunchedTable.cells.waitForCount(2)
            XCTAssertTrue(relaunchedTable.staticTexts["Bob"].exists)
            XCTAssertTrue(relaunchedTable.staticTexts["Test group"].exists)
        } else {
            // Unsigned simulator builds do not receive the App Group entitlement,
            // so their test token cannot survive a relaunch. Returning to login is
            // acceptable there as long as the application remains alive.
            let relaunchedLogin = app.scrollViews.otherElements.textFields["usernameText"]
            XCTAssertTrue(relaunchedLogin.waitForExistence(timeout: 5), "App did not expose a usable screen after cold relaunch")
        }
        XCTAssertEqual(app.state, .runningForeground, "App terminated during cold relaunch")
    }

    private func sendMessage(withContent content: String) {
        // Send another one.
        let inputField = app.children(matching: .window).element(boundBy: 1).children(matching: .other).element.children(matching: .other).element(boundBy: 1)
        inputField.tap()
        inputField.typeText(content)

        let arrowUpCircleButton = app.buttons["Arrow Up Circle"]
        arrowUpCircleButton.tap()
    }

    func testPublishP2P() {
        hiHandler()
        loginHandler(success: true)
        subHandler()
        pubHandler(responseSeq: 3)

        // Allow notifications.
        let monitor = allowLocalNotifications()
        defer { removeUIInterruptionMonitor(monitor) }

        logIntoTinode(shouldSucceed: true)

        // "Allow Notifications?" dialog. Make sure modal dialog handler gets triggered.
        app.tap()

        let table = app.tables.element
        XCTAssertTrue(table.exists)

        table.cells.waitForCount(2)
        let cell = table.cells.staticTexts["Bob"]
        cell.tap()
        let messageView = app.collectionViews.element

        // 2 messages.
        messageView.cells.waitForCount(2)
        XCTAssertTrue(messageView.containsMessage(text: "hello message"))
        XCTAssertTrue(messageView.containsMessage(text: "wassup?"))

        // Send another one.
        sendMessage(withContent: "new msg")

        // We should now have 3 messages.
        messageView.cells.waitForCount(3)
        XCTAssertTrue(messageView.containsMessage(text: "new msg"))
    }

    func testPublishGroup() {
        hiHandler()
        loginHandler(success: true)
        subHandler()
        pubHandler(responseSeq: 1)

        // Allow notifications.
        let monitor = allowLocalNotifications()
        defer { removeUIInterruptionMonitor(monitor) }

        logIntoTinode(shouldSucceed: true)

        // "Allow Notifications?" dialog. Make sure modal dialog handler gets triggered.
        app.tap()

        let table = app.tables.element
        XCTAssertTrue(table.exists)

        table.cells.waitForCount(2)
        let cell = table.cells.staticTexts["Test group"]
        cell.tap()
        let messageView = app.collectionViews.element

        // 0 messages.
        messageView.cells.waitForCount(0)

        // Send a message.
        sendMessage(withContent: "msg from alice")

        // We should now have 1 message.
        messageView.cells.waitForCount(1)
        XCTAssertTrue(messageView.containsMessage(text: "msg from alice"))

        // Simulate a message from Bob.
        let msgFromBob = ServerMessage()
        msgFromBob.data = MsgServerData(id: nil, topic: "grpGroup", from: "usrBob", ts: Date(), head: nil, seq: 2, content: Drafty(plainText: "msg from bob"))
        tinodeServer.sendResponse(response: msgFromBob, into: tinodeServer.connectedClients.first!)

        messageView.cells.waitForCount(2)
        XCTAssertTrue(messageView.containsMessage(text: "msg from bob"))
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}

extension XCUIElementQuery {
    func waitForCount(_ count: Int) {
        let predicate = NSPredicate(format: "count == %d", count)
        let expectation = XCTNSPredicateExpectation(predicate: predicate,
                                                    object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: 2)
        XCTAssertEqual(result, XCTWaiter.Result.completed)
    }
}

extension XCUIElement {
    func containsMessage(text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        return self.descendants(matching: .textView).containing(predicate).element.exists
    }
}
