//
//  Cache.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB
import Firebase

class Cache {
    private static let shared = Cache()

    private var mediaRecorderInstance: MediaRecorder?
    private var tinodeInstance: Tinode?
    private var timer = RepeatingTimer(timeInterval: 60 * 60 * 4) // Once every 4 hours.
    private var largeFileHelper: LargeFileHelper?
    private var assistantScope: ClawAssistantSession?
    private let lock = NSRecursiveLock()
    private var generation: UInt64 = 0

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    static var sessionGeneration: UInt64 { shared.locked { shared.generation } }

    static func isLoggedOut(generation: UInt64) -> Bool {
        shared.locked { shared.generation == generation && shared.tinodeInstance?.myUid == nil }
    }

    // Lock order is SDK session, then Cache; no callback can act between this
    // identity check and its credential/UI side effect.
    @discardableResult
    static func ifCurrent<T>(_ tinode: Tinode, _ body: () -> T) -> T? {
        return tinode.withActiveSession {
            shared.locked {
                guard shared.tinodeInstance === tinode else { return nil }
                return body()
            }
        } ?? nil
    }

    static func isCurrent(_ tinode: Tinode) -> Bool {
        return ifCurrent(tinode) { true } ?? false
    }
    internal static let log = TinodeSDK.Log(subsystem: "app.veilping.clawoschat")

    // Video call handling.
    public static var callManager = CallManager()

    public static var tinode: Tinode {
        return Cache.shared.getTinode()
    }
    public static func getLargeFileHelper(withIdentifier identifier: String? = nil) -> LargeFileHelper {
        return Cache.shared.getLargeFileHelper(withIdentifier: identifier)
    }
    @discardableResult
    public static func invalidate(ifCurrent expected: Tinode? = nil) -> Bool {
        var retiredRecorder: MediaRecorder?
        var retiredAssistant: ClawAssistantSession?
        // Physical AV stop and page callbacks must run after both locks are released.
        defer {
            retiredRecorder?.finishRetirement()
            retiredAssistant?.finishRetirement()
        }
        guard let current = shared.locked({ shared.tinodeInstance }) else {
            return shared.locked {
                guard expected == nil, shared.tinodeInstance == nil else { return false }
                retiredRecorder = shared.detachRecorderLocked()
                retiredAssistant = shared.detachAssistantLocked()
                SharedUtils.removeAuthToken()
                BaseDb.sharedInstance.sqlStore?.logout()
                shared.generation &+= 1
                return true
            }
        }
        guard expected == nil || current === expected else { return false }
        return current.withSessionLock {
            shared.locked {
                guard shared.tinodeInstance === current else { return false }
            retiredRecorder = shared.detachRecorderLocked()
            retiredAssistant = shared.detachAssistantLocked()
            SharedUtils.removeAuthToken()
            shared.timer.suspend()
            shared.largeFileHelper?.invalidateSession()
            shared.largeFileHelper = nil
            current.remoteAllListeners()
            current.logout()
            shared.tinodeInstance = nil
            shared.generation &+= 1
            // FCM installation token is shared: deleting it asynchronously here
            // can remove a new account's registration. Old-server unregistration
            // is best effort in the retired SDK; no global delete-token callback.
            return true
            }
        }
    }
    private func detachAssistantLocked() -> ClawAssistantSession? {
        let scope = assistantScope
        assistantScope = nil
        scope?.markRetired(clearAccount: true)
        return scope
    }

    static func assistantSession() throws -> ClawAssistantSession {
        let owner = tinode
        var previous: ClawAssistantSession?
        defer { previous?.finishRetirement() }
        guard let result = ifCurrent(owner, { () -> Result<ClawAssistantSession, ClawAssistantError> in
            let connection = Tinode.getConnectionParams()
            guard let url = URL(string: (connection.1 ? "https://" : "http://") + connection.0 + "/"),
                  let origin = try? ClawAssistantService.origin(url) else { return .failure(.insecureOrigin) }
            let generation = shared.generation
            if let scope = shared.assistantScope, scope.matches(owner: owner, generation: generation, origin: origin) {
                return .success(scope)
            }
            guard owner.isConnectionAuthenticated, let uid = owner.myUid, owner.store?.myUid == uid,
                  let token = owner.authToken, SharedUtils.getAuthToken() == token else {
                return .failure(.signInRequired)
            }
            do {
                let account = shared.assistantScope?.account
                let scope = try ClawAssistantSession(owner: owner, generation: generation, origin: origin,
                    account: account, gate: { work in
                        Cache.ifCurrent(owner) {
                            let current = Tinode.getConnectionParams()
                            guard shared.generation == generation, current.0 == connection.0,
                                  current.1 == connection.1 else { return false }
                            work(); return true
                        } ?? false
                    })
                previous = shared.assistantScope
                previous?.markRetired(clearAccount: previous?.account !== scope.account)
                shared.assistantScope = scope
                return .success(scope)
            } catch let error as ClawAssistantError { return .failure(error) }
              catch { return .failure(.signInRequired) }
        }) else { throw ClawAssistantError.retired }
        return try result.get()
    }

    public static func isContactSynchronizerActive() -> Bool {
        return Cache.shared.timer.state == .resumed
    }
    public static func synchronizeContactsPeriodically() {
        Cache.shared.timer.suspend()
        // Try to synchronize contacts immediately
        ContactsSynchronizer.default.run()
        // And repeat once every 4 hours.
        Cache.shared.timer.eventHandler = { ContactsSynchronizer.default.run() }
        Cache.shared.timer.resume()
    }
    private func getTinode() -> Tinode {
        if let existing = locked({ tinodeInstance }) {
            if existing.isSessionActive { return existing }
            Cache.invalidate(ifCurrent: existing)
            return getTinode()
        }
        return locked {
            if let existing = tinodeInstance { return existing }
            let store = BaseDb.sharedInstance.sqlStore
            // A retained account is not a local login without its Keychain token.
            if SharedUtils.getAuthToken() == nil { store?.logout() }
            if store?.recoverInterruptedPublishes() != true {
                Cache.log.error("Could not recover interrupted publishes; sending remains blocked")
            }
            let created = SharedUtils.createTinode()
            tinodeInstance = created
            DispatchQueue.main.async {
                Cache.ifCurrent(created) {
                    created.addListener((UIApplication.shared.delegate as! AppDelegate).callListener)
                    ContactsSynchronizer.default.appBecameActive()
                }
            }
            return created
        }
    }

    // Audio callers already own an SDK lease. Never replace a retired owner.
    static func largeFileHelper(for owner: Tinode) -> LargeFileHelper? {
        return ifCurrent(owner) {
            if let helper = shared.largeFileHelper { return helper }
            let config = URLSessionConfiguration.background(withIdentifier: "tinode-" + UUID().uuidString)
            let helper = LargeFileHelper(with: owner, config: config)
            shared.largeFileHelper = helper
            return helper
        }
    }

    private func getLargeFileHelper(withIdentifier identifier: String?) -> LargeFileHelper {
        let owner = getTinode()
        let result: LargeFileHelper? = owner.withActiveSession {
            locked {
                guard tinodeInstance === owner else { return nil }
                if let helper = largeFileHelper { return helper }
                let id = identifier ?? "tinode-\(Date().millisecondsSince1970)"
                let config = URLSessionConfiguration.background(withIdentifier: id)
                let helper = LargeFileHelper(with: owner, config: config)
                largeFileHelper = helper
                return helper
            }
        } ?? nil
        return result ?? getLargeFileHelper(withIdentifier: identifier)
    }

    // Blocking network work stays outside both locks. Only the final credential
    // write is guarded; SharedUtils' legacy synchronous helper cannot enforce it.
    static func connectAndLogin(using tinode: Tinode, inBackground: Bool) -> Bool {
        guard let credentials = ifCurrent(tinode, { () -> (String, String)? in
            guard let name = SharedUtils.getSavedLoginUserName(),
                  let token = SharedUtils.getAuthToken(), !token.isEmpty,
                  SharedUtils.getAuthTokenExpiryDate().map({ $0 > Date() }) ?? true else { return nil }
            tinode.setAutoLoginWithToken(token: token)
            return (name, token)
        }) ?? nil else { return false }
        do {
            _ = try tinode.connectDefault(inBackground: inBackground)?.getResult()
            return ifCurrent(tinode) {
                guard tinode.isConnectionAuthenticated, let token = tinode.authToken else { return false }
                SharedUtils.saveAuthToken(for: credentials.0, token: token, expires: tinode.authTokenExpires)
                return true
            } ?? false
        } catch {
            if case TinodeError.serverResponseError(let code, _, _) = error, (400..<500).contains(code) {
                return false
            }
            // A network outage does not log out a retained, locally authenticated account.
            return ifCurrent(tinode) { tinode.myUid != nil && SharedUtils.getAuthToken() != nil } ?? false
        }
    }

    static func fetchData(using tinode: Tinode, for topicName: String, seq: Int, keepConnection: Bool) -> UIBackgroundFetchResult {
        guard tinode.isConnectionAuthenticated || connectAndLogin(using: tinode, inBackground: true) else { return .failed }
        guard let topic = ifCurrent(tinode, { () -> DefaultComTopic? in
            guard tinode.isConnectionAuthenticated else { return nil }
            return (tinode.getTopic(topicName: topicName) ?? tinode.newTopic(for: topicName)) as? DefaultComTopic
        }) ?? nil else { return .failed }
        if topic.attached || (topic.recv ?? 0) >= seq { return .noData }
        let get = topic.metaGetBuilder().withDesc().withSub().withLaterData(limit: 10).withDel().build()
        guard let result = try? topic.subscribe(set: nil, get: get).getResult(),
              (result.ctrl?.code ?? 500) < 300, isCurrent(tinode) else { return .failed }
        if !keepConnection {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                ifCurrent(tinode) { if topic.attached { topic.leave() } }
            }
        }
        return .newData
    }

    static func fetchDesc(using tinode: Tinode, for topicName: String) -> UIBackgroundFetchResult {
        guard tinode.isConnectionAuthenticated || connectAndLogin(using: tinode, inBackground: true),
              isCurrent(tinode), tinode.isConnectionAuthenticated else { return .failed }
        if tinode.isTopicTracked(topicName: topicName) { return .noData }
        guard let result = try? tinode.getMeta(topic: topicName, query: MsgGetMeta.desc()).getResult(),
              (result.ctrl?.code ?? 500) < 300, isCurrent(tinode) else { return .failed }
        return .newData
    }

    public static func totalUnreadCount() -> Int {
        guard let topics = tinode.getTopics() else {
            return 0
        }
        return topics.reduce(into: 0, { result, topic in
            result += topic.isReader && !topic.isMuted ? topic.unread : 0
        })
    }

    private func detachRecorderLocked() -> MediaRecorder? {
        let recorder = mediaRecorderInstance
        mediaRecorderInstance = nil
        recorder?.markRetired()
        return recorder
    }

    static func makeMediaRecorder(for owner: Tinode) -> MediaRecorder? {
        guard let uid = owner.myUid, !uid.isEmpty,
              let generation = ifCurrent(owner, { shared.generation }) else { return nil }
        let recorder = MediaRecorder(ownerIsCurrent: {
            Cache.ifCurrent(owner) { shared.generation == generation && owner.myUid == uid } ?? false
        }, log: { event in Cache.log.error("%@", event) })
        recorder.maxDuration = 600_000
        var previous: MediaRecorder?
        let accepted = ifCurrent(owner) {
            guard shared.generation == generation, owner.myUid == uid else { return false }
            previous = shared.detachRecorderLocked()
            shared.mediaRecorderInstance = recorder
            return true
        } ?? false
        previous?.finishRetirement()
        guard accepted else { recorder.retire(); return nil }
        return recorder
    }

    static func releaseMediaRecorder(_ recorder: MediaRecorder) {
        shared.locked {
            if shared.mediaRecorderInstance === recorder { shared.mediaRecorderInstance = nil }
            recorder.markRetired()
        }
        recorder.finishRetirement()
    }
}
