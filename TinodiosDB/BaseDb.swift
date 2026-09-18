//
//  BaseDb.swift
//  ios
//
//  Copyright © 2019-2024 Tinode. All rights reserved.
//

import Foundation
import SQLite
import SQLite3
import TinodeSDK

public class BaseDb {
    // Current database schema version. Increment on schema changes.
    public static let kSchemaVersion: Int32 = 113

    // Object statuses. Values are incremented by 10 to make it easier to add new statuses.
    public enum Status: Int, Comparable {
        // Status undefined/not set.
        case undefined = 0
        // Object is not ready to be sent to the server.
        case draft = 10
        // Object is ready but not yet sent to the server.
        case queued = 20
        // Object is in the process of being sent to the server.
        case sending = 30
        // Claimed under the C3 capability with a persisted client message UUID.
        case sendingC3 = 31
        // Dispatched but not confirmed. Never eligible for automatic queued replay.
        // Keep schema version unchanged: adding this raw value does not alter tables.
        case unconfirmed = 35
        // Only this unknown state carries durable C3 retry eligibility.
        case unconfirmedC3 = 36
        // Sending failed
        case failed = 40
        // Object is received by the server.
        case synced = 50
        // Object is hard-deleted.
        case deletedHard = 60
        // Object is soft-deleted.
        case deletedSoft = 70
        // Object is a deletion range marker synchronized with the server.
        case deletedSynced = 80

        public static func < (lhs: BaseDb.Status, rhs: BaseDb.Status) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    // Meta-status: object should be visible in the UI.
    public static let kStatusVisible = Status.synced

    public static let kBundleId = "app.veilping.clawoschat.db"
    public static let kAppGroupId = "group." + BaseDb.kBundleId
    // No direct access to the shared instance.
    private static var `default`: BaseDb?
    private static let accessQueue = DispatchQueue(label: BaseDb.kBundleId)
    var db: SQLite.Connection?
    private let pathToDatabase: String
    public static let unavailableMessage = "本地消息数据库暂不可用，已暂停连接和发送。请关闭并重新打开应用；若仍失败，请保留应用和本机数据，安装兼容版本或联系支持人员。请勿卸载或清除数据。"
    public private(set) var initializationError: String? = BaseDb.unavailableMessage
    internal private(set) var initializationDiagnostic: InitializationDiagnostic?
    public var isStoreAvailable: Bool { initializationError == nil && db != nil }
    public var sqlStore: SqlStore?
    public var topicDb: TopicDb?
    public var accountDb: AccountDb?
    public var subscriberDb: SubscriberDb?
    public var userDb: UserDb?
    public var messageDb: MessageDb?

    var account: StoredAccount?
    var isCredValidationRequired: Bool {
        return !(self.account?.credMethods?.isEmpty ?? true)
    }
    public var isReady: Bool {
        return isStoreAvailable && self.account != nil && !self.isCredValidationRequired
    }

    internal static let log = TinodeSDK.Log(subsystem: BaseDb.kBundleId)

    /// The init is private to ensure that the class is a singleton.
    private init() {
        let fileManager = FileManager.default
        let databaseDirectory = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: BaseDb.kAppGroupId)
            ?? fileManager
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(BaseDb.kBundleId, isDirectory: true)
        try? fileManager.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        var documentsDirectory = databaseDirectory.path
        if documentsDirectory.last! != "/" {
            documentsDirectory.append("/")
        }
        self.pathToDatabase = documentsDirectory.appending("database.sqlite")

        self.sqlStore = SqlStore(dbh: self)
    }

    // Test seam uses the same opening and migration path, never the app's store.
    internal init(databasePath: String) {
        self.pathToDatabase = databasePath
        self.sqlStore = SqlStore(dbh: self)
        self.initDb()
    }

    private func initDb() {
        do {
            let database = try BaseDb.openPreparedDatabase(at: pathToDatabase, onFailure: {
                self.initializationDiagnostic = $0
            })
            // No table accessors or SDK writes are exposed before COMMIT succeeds.
            self.db = database
            self.accountDb = AccountDb(database)
            self.userDb = UserDb(database, baseDb: self)
            self.topicDb = TopicDb(database, baseDb: self)
            self.subscriberDb = SubscriberDb(database, baseDb: self)
            self.messageDb = MessageDb(database, baseDb: self)
            self.account = self.accountDb?.getActiveAccount()
            self.initializationError = nil
            self.initializationDiagnostic = nil
        } catch {
            self.db = nil
            self.initializationError = BaseDb.unavailableMessage
            if self.initializationDiagnostic == nil {
                self.initializationDiagnostic = BaseDb.safeInitializationDiagnostic(error, stage: .accessors)
            }
            // Only fixed stage/category names and numeric codes; never SQL, paths or bindings.
            BaseDb.log.error("Local store initialization blocked (%@); original data retained",
                             self.initializationDiagnostic?.summary ?? "unknown")
        }
    }

    public static var sharedInstance: BaseDb {
        return BaseDb.accessQueue.sync {
            if let instance = BaseDb.default {
                return instance
            }
            let instance = BaseDb()
            BaseDb.default = instance
            instance.initDb()
            return instance
        }
    }
    func isMe(uid: String?) -> Bool {
        guard let uid = uid, let acctUid = BaseDb.sharedInstance.uid else { return false }
        return uid == acctUid
    }
    var uid: String? {
        return self.account?.uid
    }
    func setUid(uid: String?, credMethods: [String]?) {
        guard isStoreAvailable else { return }
        guard let uid = uid else {
            self.account = nil
            return
        }
        do {
            if self.account != nil {
                try self.accountDb?.deactivateAll()
            }
            self.account = self.accountDb?.addOrActivateAccount(for: uid, withCredMethods: credMethods)
        } catch {
            BaseDb.log.error("BaseDb - setUid failed %@", error.localizedDescription)
            self.account = nil
        }
    }
    static let deactivateAccountSQL = "UPDATE accounts SET last_active=0,device_id=NULL WHERE id=? AND uid=?"

    public func logout() {
        BaseDb.accessQueue.sync {
            let previousAccount = self.account
            // Detach even if an unavailable/corrupt store cannot be written.
            self.account = nil
            guard self.isStoreAvailable, let previousAccount = previousAccount, let db = self.db else { return }
            do {
                try db.transaction(.immediate) {
                    try db.run(Self.deactivateAccountSQL,
                               previousAccount.id, previousAccount.uid)
                }
            } catch {
                // Preserve file/WAL and block reopening the old active account in this process.
                self.initializationError = BaseDb.unavailableMessage
                BaseDb.log.error("Could not deactivate local account; store is blocked")
            }
        }
    }

    public func deleteUid(_ uid: String) -> Bool {
        BaseDb.accessQueue.sync {
            guard !uid.isEmpty, isStoreAvailable, let database = db,
                  self.account == nil || self.account?.uid == uid else { return false }
            do {
                try database.transaction(.immediate) {
                    guard let accountId = try database.scalar("SELECT id FROM accounts WHERE uid=?", uid) as? Int64 else {
                        return // Already absent is a successful local-only retry.
                    }
                    try database.run("DELETE FROM messages WHERE topic_id IN (SELECT id FROM topics WHERE account_id=?)", accountId)
                    try database.run("DELETE FROM subscriptions WHERE topic_id IN (SELECT id FROM topics WHERE account_id=?)", accountId)
                    try database.run("DELETE FROM topics WHERE account_id=?", accountId)
                    try database.run("DELETE FROM users WHERE account_id=?", accountId)
                    try database.run("DELETE FROM accounts WHERE id=? AND uid=?", accountId, uid)
                    guard database.changes == 1 else { throw LocalAccountDeletionError.incomplete }
                }
                // A failed statement or COMMIT leaves both the data and active pointer intact.
                if self.account?.uid == uid { self.account = nil }
                return true
            } catch {
                BaseDb.log.error("local_account_cleanup_failed")
                return false
            }
        }
    }

    private enum LocalAccountDeletionError: Error { case incomplete }

    public static func updateCounter(db: SQLite.Connection, table: Table,
                                     usingIdColumn idColumn: SQLite.Expression<Int64>, forId id: Int64,
                                     in column: SQLite.Expression<Int?>, with value: Int) -> Bool {
        let record = table.filter(idColumn == id && column < value)
        do {
            return try db.run(record.update(column <- value)) > 0
        } catch {
            if let result = error as? Result {
                // Skip logging "success" errors: they just mean the row was not found and some such.
                switch result {
                case let .error(_, code, _):
                    if code == SQLITE_OK || code == SQLITE_DONE || code == SQLITE_ROW {
                        return false
                    }
                default:
                    break
                }
            }
            BaseDb.log.error("BaseDb - updateCounter failed %@", error.localizedDescription)
            return false
        }
    }
}

// C2-L1-20260918 is a local compatibility rule; the wire protocol is unchanged.
extension BaseDb {
    enum OpenError: Error { case unsupportedSchema, invalidStructure, invalidMarker, reentrantInitialization }

    enum OpenStage: String {
        case initializationGate
        case readOnlyOpen, readOnlyBegin, readOnlySchema, readOnlyCommit
        case writableOpen, foreignKeys, migrationBegin, migrationSchema, freshSchema
        case markerCreate, c2Read, c2Quarantine, c2Write, c3Read, c3Quarantine, c3Write
        case migrationCommit, accessors
    }

    struct InitializationDiagnostic {
        let stage: OpenStage
        let category: String
        let primaryCode: Int32?
        var extendedCode: Int32?
        var systemErrno: Int32?
        var sqliteVersionNumber: Int32?
        var journalMode: JournalMode?
        var liveErrorState: LiveErrorState?
        var summary: String {
            let base = "\(stage.rawValue):\(category):primary=\(primaryCode.map { String($0) } ?? "none"):extended=\(extendedCode.map { String($0) } ?? "none")"
            guard let liveErrorState = liveErrorState else { return base }
            return base + ":live=\(liveErrorState.rawValue):errno=\(systemErrno.map { String($0) } ?? "none"):sqlite=\(sqliteVersionNumber.map { String($0) } ?? "none"):journal=\(journalMode?.rawValue ?? "unknown")"
        }
    }

    enum JournalMode: String {
        case delete, truncate, persist, memory, wal, off, unknown
    }

    enum LiveErrorState: String {
        case matched, mismatched
    }

    // Do not use Error.description, localizedDescription, SQL statements or NSError userInfo.
    static func safeInitializationDiagnostic(_ error: Error, stage: OpenStage) -> InitializationDiagnostic {
        var category = "other"
        var primary: Int32?
        var extended: Int32?
        if let sqlite = error as? SQLite.Result {
            category = "sqlite"
            switch sqlite {
            case let .error(_, code, _): primary = code & 0xff
            case let .extendedError(_, code, _):
                primary = code & 0xff
                extended = code
            }
        } else if let known = error as? OpenError {
            switch known {
            case .unsupportedSchema: category = "unsupportedSchema"
            case .invalidStructure: category = "invalidStructure"
            case .invalidMarker: category = "invalidMarker"
            case .reentrantInitialization: category = "reentrantInitialization"
            }
        }
        return InitializationDiagnostic(stage: stage, category: category, primaryCode: primary, extendedCode: extended)
    }

    // The connection is still owned by its original scope. Snapshot error codes
    // before any SQL: a diagnostic PRAGMA can overwrite SQLite's last error.
    static func liveInitializationDiagnostic(_ error: Error, stage: OpenStage,
                                             in database: SQLite.Connection) -> InitializationDiagnostic {
        var diagnostic = safeInitializationDiagnostic(error, stage: stage)
        guard diagnostic.category == "sqlite" else { return diagnostic }
        let extended = sqlite3_extended_errcode(database.handle)
        let systemError = sqlite3_system_errno(database.handle)
        if let primary = diagnostic.primaryCode, extended != SQLITE_OK, extended & 0xff == primary {
            diagnostic.extendedCode = extended
            diagnostic.systemErrno = systemError
            diagnostic.liveErrorState = .matched
        } else {
            // A rollback may already have overwritten the connection's code.
            // Never attribute a mismatching live code/errno to the original error.
            diagnostic.liveErrorState = .mismatched
        }
        diagnostic.sqliteVersionNumber = sqlite3_libversion_number()
        let mode = (try? database.scalar("PRAGMA main.journal_mode")) as? String
        diagnostic.journalMode = mode.flatMap { JournalMode(rawValue: $0) } ?? .unknown
        return diagnostic
    }

    // Catch in the live connection's scope, without changing its successful path,
    // error type, transaction policy, or return value.
    static func withInitializationFailureDiagnostics<Value>(
        in database: SQLite.Connection, stage: () -> OpenStage,
        onFailure: (InitializationDiagnostic) -> Void,
        _ operation: () throws -> Value
    ) rethrows -> Value {
        do {
            return try operation()
        } catch {
            onFailure(liveInitializationDiagnostic(error, stage: stage(), in: database))
            throw error
        }
    }

    static let migrationCreateSQL = "CREATE TABLE IF NOT EXISTS claw_local_migrations (rule TEXT NOT NULL PRIMARY KEY, completed INTEGER NOT NULL CHECK(completed=1))"
    static let migrationReadSQL = "SELECT completed FROM claw_local_migrations WHERE rule='C2-L1-20260918'"
    static let migrationQuarantineSQL = "UPDATE messages SET status=35 WHERE status IN (20,30)"
    static let migrationWriteSQL = "INSERT INTO claw_local_migrations(rule,completed) VALUES ('C2-L1-20260918',1)"
    static let c3MigrationReadSQL = "SELECT completed FROM claw_local_migrations WHERE rule='C3-20260918'"
    static let c3MigrationQuarantineSQL = "UPDATE messages SET status=35 WHERE status IN (20,30,31,36)"
    static let c3MigrationWriteSQL = "INSERT INTO claw_local_migrations(rule,completed) VALUES ('C3-20260918',1)"

    // Matches the existing v113 table builders. No destructive version fallback.
    static let schema113SQL = """
    CREATE TABLE accounts (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, uid TEXT, last_active INTEGER, cred_methods TEXT, device_id TEXT);
    CREATE UNIQUE INDEX accounts_uid ON accounts(uid);
    CREATE INDEX accounts_last_active ON accounts(last_active);
    CREATE TABLE users (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, account_id INTEGER REFERENCES accounts(id), uid TEXT, updated TEXT, pub TEXT, account_name TEXT);
    CREATE INDEX users_account_uid ON users(account_id, uid);
    CREATE TABLE topics (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, account_id INTEGER REFERENCES accounts(id), status INTEGER, topic TEXT, type INTEGER, visible INTEGER, created TEXT, updated TEXT, read INTEGER, recv INTEGER, seq INTEGER, clear INTEGER, max_del INTEGER, mode TEXT, defacs TEXT, last_used TEXT, min_local_seq INTEGER, max_local_seq INTEGER, next_unsent_seq INTEGER, tags TEXT, creds TEXT, pub TEXT, priv TEXT, trusted TEXT);
    CREATE UNIQUE INDEX topics_account_topic ON topics(account_id, topic);
    CREATE TABLE subscriptions (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, topic_id INTEGER REFERENCES topics(id), user_id INTEGER REFERENCES users(id), status INTEGER, mode TEXT, updated TEXT, read INTEGER, recv INTEGER, clear INTEGER, priv TEXT, last_seen TEXT, user_agent TEXT, subscription_class TEXT NOT NULL);
    CREATE INDEX subscriptions_topic ON subscriptions(topic_id);
    CREATE UNIQUE INDEX subscriptions_topic_user ON subscriptions(topic_id, user_id);
    CREATE TABLE messages (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, topic_id INTEGER REFERENCES topics(id), user_id INTEGER REFERENCES users(id), status INTEGER, sender TEXT, ts TEXT, seq INTEGER, high INTEGER, del_id INTEGER, repl_seq INTEGER, effective_seq INTEGER, effective_ts TEXT, head TEXT, content TEXT);
    CREATE UNIQUE INDEX messages_topic_seq ON messages(topic_id, seq DESC);
    CREATE UNIQUE INDEX messages_topic_effective ON messages(topic_id, effective_seq DESC) WHERE effective_seq IS NOT NULL;
    PRAGMA user_version = 113;
    """

    private static let columns113: [String: String] = [
        "accounts": "id:INTEGER uid:TEXT last_active:INTEGER cred_methods:TEXT device_id:TEXT",
        "users": "id:INTEGER account_id:INTEGER uid:TEXT updated:TEXT pub:TEXT account_name:TEXT",
        "topics": "id:INTEGER account_id:INTEGER status:INTEGER topic:TEXT type:INTEGER visible:INTEGER created:TEXT updated:TEXT read:INTEGER recv:INTEGER seq:INTEGER clear:INTEGER max_del:INTEGER mode:TEXT defacs:TEXT last_used:TEXT min_local_seq:INTEGER max_local_seq:INTEGER next_unsent_seq:INTEGER tags:TEXT creds:TEXT pub:TEXT priv:TEXT trusted:TEXT",
        "subscriptions": "id:INTEGER topic_id:INTEGER user_id:INTEGER status:INTEGER mode:TEXT updated:TEXT read:INTEGER recv:INTEGER clear:INTEGER priv:TEXT last_seen:TEXT user_agent:TEXT subscription_class:TEXT",
        "messages": "id:INTEGER topic_id:INTEGER user_id:INTEGER status:INTEGER sender:TEXT ts:TEXT seq:INTEGER high:INTEGER del_id:INTEGER repl_seq:INTEGER effective_seq:INTEGER effective_ts:TEXT head:TEXT content:TEXT"
    ]
    private static let foreignKeys113: [String: Set<String>] = [
        "accounts": [], "users": ["account_id:accounts:id"], "topics": ["account_id:accounts:id"],
        "subscriptions": ["topic_id:topics:id", "user_id:users:id"],
        "messages": ["topic_id:topics:id", "user_id:users:id"]
    ]
    private static let uniqueIndexes113: [String: Set<String>] = [
        "accounts": ["0:uid"], "users": [], "topics": ["0:account_id,topic"],
        "subscriptions": ["0:topic_id,user_id"],
        "messages": ["0:topic_id,seq", "1:topic_id,effective_seq"]
    ]

    private static func quotedIdentifier(_ name: String) -> String {
        return "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // Read-only preflight protects unsupported databases and their WAL from writes.
    private final class InitializationGate {
        let lock = NSRecursiveLock()
        var initializing = false
    }

    // Gates remain alive for this process. Removing a gate while a waiter holds
    // it could create two independent locks for the same database.
    private static let initializationRegistryLock = NSLock()
    private static var initializationGates: [String: InitializationGate] = [:]

    private static func initializationGate(at path: String) -> InitializationGate {
        let key = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        initializationRegistryLock.lock()
        defer { initializationRegistryLock.unlock() }
        if let gate = initializationGates[key] { return gate }
        let gate = InitializationGate()
        initializationGates[key] = gate
        return gate
    }

    // Serializes only initialization lifecycles for one canonical path, not
    // normal transactions or unrelated databases. Also used by native tests.
    static func withInitializationGate<Value>(at path: String, _ operation: () throws -> Value) throws -> Value {
        let gate = initializationGate(at: path)
        gate.lock.lock()
        defer { gate.lock.unlock() }
        guard !gate.initializing else { throw OpenError.reentrantInitialization }
        gate.initializing = true
        defer { gate.initializing = false }
        return try operation()
    }

    static func openPreparedDatabase(at path: String,
                                     onFailure: ((InitializationDiagnostic) -> Void)? = nil,
                                     observeStage: ((OpenStage) -> Void)? = nil) throws -> SQLite.Connection {
        do {
            return try withInitializationGate(at: path) {
                try openPreparedDatabaseWithinGate(at: path, onFailure: onFailure, observeStage: observeStage)
            }
        } catch {
            if let known = error as? OpenError, case .reentrantInitialization = known {
                onFailure?(safeInitializationDiagnostic(error, stage: .initializationGate))
            }
            throw error
        }
    }

    private static func openPreparedDatabaseWithinGate(at path: String,
                                     onFailure: ((InitializationDiagnostic) -> Void)?,
                                     observeStage: ((OpenStage) -> Void)?) throws -> SQLite.Connection {
        var stage = OpenStage.readOnlyOpen
        var failureDiagnostic: InitializationDiagnostic?
        func advance(_ value: OpenStage) {
            stage = value
            observeStage?(value)
        }
        do {
            if FileManager.default.fileExists(atPath: path) {
                advance(.readOnlyOpen)
                let readOnly = try SQLite.Connection(path, readonly: true)
                readOnly.busyTimeout = 5
                try withInitializationFailureDiagnostics(in: readOnly, stage: { stage },
                    onFailure: { failureDiagnostic = $0 }) {
                    // All schema reads observe one snapshot during concurrent migration.
                    advance(.readOnlyBegin)
                    try readOnly.transaction(.deferred) {
                        advance(.readOnlySchema)
                        _ = try validateSchema(in: readOnly)
                        advance(.readOnlyCommit)
                    }
                }
            }
            advance(.writableOpen)
            let database = try SQLite.Connection(path)
            database.busyTimeout = 5
            try withInitializationFailureDiagnostics(in: database, stage: { stage },
                onFailure: { failureDiagnostic = $0 }) {
                advance(.foreignKeys)
                try database.run("PRAGMA foreign_keys = ON")
                try prepareDatabase(in: database, observeStage: advance)
            }
            return database
        } catch {
            onFailure?(failureDiagnostic ?? safeInitializationDiagnostic(error, stage: stage))
            throw error
        }
    }

    // Main app and NSE acquire the same SQLite lock and recheck inside it.
    // No marker, status changes or new schema survive a failed COMMIT.
    static func prepareDatabase(in database: SQLite.Connection, observeStage: ((OpenStage) -> Void)? = nil) throws {
        observeStage?(.migrationBegin)
        try database.transaction(.immediate) {
            observeStage?(.migrationSchema)
            if try validateSchema(in: database) {
                observeStage?(.freshSchema)
                try database.execute(schema113SQL)
            }
            observeStage?(.markerCreate)
            try database.run(migrationCreateSQL)
            observeStage?(.c2Read)
            if let value = try database.scalar(migrationReadSQL) {
                guard value as? Int64 == 1 else { throw OpenError.invalidMarker }
            } else {
                observeStage?(.c2Quarantine)
                try database.run(migrationQuarantineSQL)
                observeStage?(.c2Write)
                try database.run(migrationWriteSQL)
            }
            observeStage?(.c3Read)
            if let value = try database.scalar(c3MigrationReadSQL) {
                guard value as? Int64 == 1 else { throw OpenError.invalidMarker }
            } else {
                // A pre-existing UUID does not prove an earlier C3 dispatch.
                observeStage?(.c3Quarantine)
                try database.run(c3MigrationQuarantineSQL)
                observeStage?(.c3Write)
                try database.run(c3MigrationWriteSQL)
            }
            observeStage?(.migrationCommit)
        }
        // Subsequent startup recovery of 30 is main-app-only, in Cache. NSE must
        // not turn a concurrently running main app's newly claimed 30 into 35.
    }

    // Statement is both Sequence and FailableIterator. Select the throwing
    // iterator explicitly: Array(statement) is ambiguous, while Sequence.next()
    // uses try! and would terminate the app on an SQLite step error.
    static func schemaRows(in database: SQLite.Connection, sql: String) throws -> [SQLite.Statement.Element] {
        let statement = try database.prepare(sql)
        var rows: [SQLite.Statement.Element] = []
        while let row = try statement.failableNext() {
            rows.append(row)
        }
        return rows
    }

    // Returns true only for an empty version-zero database. Existing databases
    // must match the known v113 structure; unfamiliar structures are retained.
    static func validateSchema(in database: SQLite.Connection) throws -> Bool {
        let objects = try schemaRows(in: database, sql: "SELECT name,type FROM sqlite_master WHERE name NOT GLOB 'sqlite_*' AND type IN ('table','view','trigger')")
        let version = try database.scalar("PRAGMA user_version") as? Int64
        if version == 0 && objects.isEmpty { return true }
        guard version == Int64(kSchemaVersion) else { throw OpenError.unsupportedSchema }
        let tables = Set(objects.compactMap { $0[0] as? String })
        let expected = Set(columns113.keys)
        guard expected.isSubset(of: tables), tables.subtracting(expected).isSubset(of: ["claw_local_migrations"]),
              objects.allSatisfy({ $0[1] as? String == "table" }) else { throw OpenError.invalidStructure }

        for (table, definition) in columns113 {
            let expectedColumns = Set(definition.split(separator: " ").map(String.init))
            let rows = try schemaRows(in: database, sql: "PRAGMA table_xinfo(\(quotedIdentifier(table)))")
            let columns = Set(rows.map { "\($0[1] as? String ?? ""):\(($0[2] as? String ?? "").uppercased())" })
            guard columns == expectedColumns else { throw OpenError.invalidStructure }
            for row in rows {
                let name = row[1] as? String ?? ""
                let required: Int64 = (name == "id" || (table == "subscriptions" && name == "subscription_class")) ? 1 : 0
                guard row[3] as? Int64 == required, row[4] == nil,
                      row[5] as? Int64 == (name == "id" ? 1 : 0), row[6] as? Int64 == 0 else {
                    throw OpenError.invalidStructure
                }
            }
            let keys = try schemaRows(in: database, sql: "PRAGMA foreign_key_list(\(quotedIdentifier(table)))")
            let actualKeys = Set(keys.map { "\($0[3] as? String ?? ""):\($0[2] as? String ?? ""):\($0[4] as? String ?? "")" })
            guard actualKeys == foreignKeys113[table], keys.allSatisfy({
                $0[5] as? String == "NO ACTION" && $0[6] as? String == "NO ACTION"
            }) else { throw OpenError.invalidStructure }

            var unique = Set<String>()
            for index in try schemaRows(in: database, sql: "PRAGMA index_list(\(quotedIdentifier(table)))") where index[2] as? Int64 == 1 {
                guard let name = index[1] as? String, let partial = index[4] as? Int64 else { throw OpenError.invalidStructure }
                let columnNames = try schemaRows(in: database, sql: "PRAGMA index_info(\(quotedIdentifier(name)))").compactMap { $0[2] as? String }
                unique.insert("\(partial):" + columnNames.joined(separator: ","))
                if partial == 1 {
                    guard let sql = try database.scalar("SELECT sql FROM sqlite_master WHERE type='index' AND name=?", name) as? String else { throw OpenError.invalidStructure }
                    let normalized = sql.lowercased().filter { !$0.isWhitespace && $0 != "\"" && $0 != "(" && $0 != ")" }
                    guard normalized.hasSuffix("whereeffective_seqisnotnull") else { throw OpenError.invalidStructure }
                }
            }
            guard unique == uniqueIndexes113[table] else { throw OpenError.invalidStructure }
        }
        guard try schemaRows(in: database, sql: "PRAGMA foreign_key_check").isEmpty else { throw OpenError.invalidStructure }
        if tables.contains("claw_local_migrations") {
            let rows = try schemaRows(in: database, sql: "PRAGMA table_info(claw_local_migrations)")
            guard rows.count == 2,
                  rows[0][1] as? String == "rule", rows[0][2] as? String == "TEXT", rows[0][3] as? Int64 == 1, rows[0][5] as? Int64 == 1,
                  rows[1][1] as? String == "completed", rows[1][2] as? String == "INTEGER", rows[1][3] as? Int64 == 1, rows[1][5] as? Int64 == 0,
                  try database.scalar("SELECT COUNT(*) FROM claw_local_migrations WHERE rule NOT IN ('C2-L1-20260918','C3-20260918') OR completed<>1") as? Int64 == 0 else {
                throw OpenError.invalidMarker
            }
        }
        return false
    }
}

// Database schema versioning.
extension SQLite.Connection {
    public var schemaVersion: Int32 {
        get { return Int32((try? scalar("PRAGMA user_version") as? Int64) ?? -1) }
        set { try! run("PRAGMA user_version = \(newValue)") }
    }

    /// Releases a savepoint explicitly.
    public func releaseSavepoint(withName savepointName: String) {
        do {
            try self.execute("RELEASE '\(savepointName)'")
        } catch {
            BaseDb.log.error("BaseDb - failed to release savepoint %@: %@", savepointName, error.localizedDescription)
        }
    }
}
