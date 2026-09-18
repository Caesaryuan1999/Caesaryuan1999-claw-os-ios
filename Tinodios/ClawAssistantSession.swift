// Copyright (c) 2026 CLAW OS contributors.
import Foundation
import TinodeSDK

/// Separate lifetime from HTTP tokens: same-account refresh may retain a draft;
/// logout retires this memory. It is never persisted or shared with another UID/origin.
final class ClawAssistantAccountMemory {
    let uid: String
    let origin: URL
    let generation: UInt64
    private let lock = NSLock()
    private var text = ""
    private var retired = false
    init(uid: String, origin: URL, generation: UInt64) {
        self.uid = uid; self.origin = origin; self.generation = generation
    }
    var draft: String {
        lock.lock(); defer { lock.unlock() }
        return retired ? "" : text
    }
    func updateDraft(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        guard !retired else { return }
        text = value
    }
    func retire() {
        lock.lock(); retired = true; text = ""; lock.unlock()
    }
}

final class ClawAssistantSession {
    static let changed = Notification.Name("ClawAssistantSessionChanged")
    let owner: Tinode
    let uid: String
    let generation: UInt64
    let origin: URL
    let account: ClawAssistantAccountMemory
    private let token: String
    private let gate: (_ work: () -> Void) -> Bool
    private let lock = NSRecursiveLock()
    private var retired = false
    private var authorizationBlocked = false
    private(set) var service: ClawAssistantService!
    lazy var history = ClawAssistantHistory(session: self)

    /// gate is the real Cache.ifCurrent in production. Tests provide only the slot
    /// boundary while this method still checks actual Tinode identity/token/lifetime.
    init(owner: Tinode, generation: UInt64, origin: URL, account: ClawAssistantAccountMemory? = nil,
         configuration: URLSessionConfiguration = .ephemeral,
         gate: @escaping (_ work: () -> Void) -> Bool) throws {
        guard owner.isSessionActive, owner.isConnectionAuthenticated,
              let uid = owner.myUid, !uid.isEmpty, let token = owner.authToken,
              owner.authTokenExpires.map({ $0 > Date() }) ?? true else {
            throw ClawAssistantError.signInRequired
        }
        let origin = try ClawAssistantService.origin(origin)
        guard owner.hostURL(useWebsocketProtocol: false) == origin else { throw ClawAssistantError.retired }
        self.owner = owner; self.uid = uid; self.token = token
        self.generation = generation; self.origin = origin; self.gate = gate
        if let account = account, account.uid == uid, account.origin == origin, account.generation == generation {
            self.account = account
        } else { self.account = ClawAssistantAccountMemory(uid: uid, origin: origin, generation: generation) }
        self.service = try ClawAssistantService(origin: origin, apiKey: owner.apiKey, token: token,
                                               configuration: configuration, isCurrent: { [weak self] in
            self?.isCurrent ?? false
        })
    }

    /// SDK -> Cache -> scope. Callers put only state changes inside, never UIKit/network.
    func withCurrent<T>(_ body: () -> T) -> T? {
        var result: T?
        _ = gate {
            guard self.owner.myUid == self.uid, self.owner.authToken == self.token,
                  self.owner.isSessionActive,
                  self.owner.store.map({ $0.myUid == self.uid }) ?? true,
                  self.owner.authTokenExpires.map({ $0 > Date() }) ?? true,
                  self.owner.hostURL(useWebsocketProtocol: false) == self.origin else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            guard !self.retired, !self.authorizationBlocked else { return }
            result = body()
        }
        return result
    }
    var isCurrent: Bool { withCurrent { true } ?? false }
    var isBlocked: Bool { lock.lock(); defer { lock.unlock() }; return authorizationBlocked }
    func matches(owner: Tinode, generation: UInt64, origin: URL) -> Bool {
        // Called only inside Cache's SDK -> Cache gate.
        lock.lock(); defer { lock.unlock() }
        return !retired && self.owner === owner && self.generation == generation &&
            self.origin == origin && owner.myUid == uid && owner.authToken == token
    }
    func updateDraft(_ value: String) {
        _ = withCurrent { account.updateDraft(value) }
    }
    var draft: String { withCurrent { account.draft } ?? "" }

    /// Cache calls this synchronously while detaching. No network/UI callbacks here.
    func markRetired(clearAccount: Bool) {
        lock.lock(); retired = true; lock.unlock()
        if clearAccount { account.retire() }
    }
    /// All cancellation/observers are outside SDK/Cache locks.
    func finishRetirement() {
        service.cancelAll()
        notify()
    }
    func blockAuthorization() {
        let changed = withCurrent { () -> Bool in
            self.authorizationBlocked = true
            return true
        } ?? false
        guard changed else { return } // Late old-token 401 cannot block a new scope.
        service.cancelAll()
        notify()
    }
    private func notify() {
        let work = {
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}
