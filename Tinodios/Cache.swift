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
    private let lock = NSRecursiveLock()
    private var generation: UInt64 = 0

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    static var sessionGeneration: UInt64 { shared.locked { shared.generation } }

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
        guard let current = shared.locked({ shared.tinodeInstance }) else {
            return shared.locked {
                guard expected == nil, shared.tinodeInstance == nil else { return false }
                SharedUtils.removeAuthToken()
                BaseDb.sharedInstance.sqlStore?.logout()
                shared.generation &+= 1
                return true
            }
        }
        guard expected == nil || current === expected else { return false }
        return ifCurrent(current) {
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
        } ?? false
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

    private func getLargeFileHelper(withIdentifier identifier: String?) -> LargeFileHelper {
        return locked {
            if let helper = largeFileHelper { return helper }
            let id = identifier ?? "tinode-\(Date().millisecondsSince1970)"
            let config = URLSessionConfiguration.background(withIdentifier: id)
            let helper = LargeFileHelper(with: getTinode(), config: config)
            largeFileHelper = helper
            return helper
        }
    }

    // Blocking network work stays outside both locks. Only the final credential
    // write is guarded; SharedUtils' legacy synchronous helper cannot enforce it.
    static func connectAndLogin(using tinode: Tinode, inBackground: Bool) -> Bool {
        guard let credentials = ifCurrent(tinode, { () -> (String, String)? in
            guard let name = SharedUtils.getSavedLoginUserName(),
                  let token = SharedUtils.getAuthToken() else { return nil }
            tinode.setAutoLoginWithToken(token: token)
            return (name, token)
        }) ?? nil else { return false }
        do {
            let result = try tinode.connectDefault(inBackground: inBackground)?.getResult()
            guard (result?.ctrl?.code ?? 500) < 300 else { return false }
            return ifCurrent(tinode) {
                guard tinode.isConnectionAuthenticated, let token = tinode.authToken else { return false }
                SharedUtils.saveAuthToken(for: credentials.0, token: token, expires: tinode.authTokenExpires)
                return true
            } ?? false
        } catch {
            return false
        }
    }

    public static func totalUnreadCount() -> Int {
        guard let topics = tinode.getTopics() else {
            return 0
        }
        return topics.reduce(into: 0, { result, topic in
            result += topic.isReader && !topic.isMuted ? topic.unread : 0
        })
    }

    private func initMediaRecorder() -> MediaRecorder {
        mediaRecorderInstance = MediaRecorder()
        mediaRecorderInstance!.maxDuration = 600_000 // 10 min
        return mediaRecorderInstance!
    }

    public static var mediaRecorder: MediaRecorder {
        if let recorder = Cache.shared.mediaRecorderInstance {
            return recorder
        }
        return Cache.shared.initMediaRecorder()
    }
}
