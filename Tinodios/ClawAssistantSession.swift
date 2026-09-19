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
    static let knownRunChanged = Notification.Name("ClawAssistantKnownRunChanged")
    struct KnownAddress: Equatable, Hashable {
        let conversationID: String
        let runID: String
    }
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
    // Main-thread UI/read ownership. Retirement flags above remain synchronously lock-protected.
    private(set) var knownRun: ClawAssistantRun?
    private(set) var knownAddress: KnownAddress?
    private(set) var selectedConversationID: String?
    private var readerLease: UUID?
    private var readerVisible = false
    private var boundSnapshot: UUID?
    private var repairedBindings = Set<KnownAddress>()
    private var alignedTerminals = Set<KnownAddress>()

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

    /// Check before mutating navigation selection. Going home/list never calls this.
    func blockingStop(for conversationID: String) -> KnownAddress? {
        precondition(Thread.isMainThread)
        guard isCurrent, knownRun?.hasUnresolvedStop == true,
              let address = knownAddress, address.conversationID != conversationID else { return nil }
        return address
    }
    @discardableResult
    func acquireReader(conversationID: String, lease: UUID) -> Bool {
        precondition(Thread.isMainThread)
        guard isCurrent, ClawAssistantWire.uuid(conversationID), blockingStop(for: conversationID) == nil else { return false }
        if selectedConversationID != conversationID {
            clearKnownRun()
            selectedConversationID = conversationID
        }
        // A new page takes over; callbacks from its predecessor cannot release this lease.
        readerLease = lease; readerVisible = true
        knownRun?.setVisible(false)
        historyDidChange(history)
        guard isCurrent, readerLease == lease, selectedConversationID == conversationID else { return false }
        knownRun?.setVisible(true)
        return isCurrent && readerLease == lease
    }
    func releaseReader(lease: UUID) {
        precondition(Thread.isMainThread)
        guard readerLease == lease else { return }
        readerLease = nil; readerVisible = false
        knownRun?.setVisible(false) // Never sends stop, or cancels an in-flight stop.
    }
    @discardableResult
    func recoverKnownRun(conversationID: String, lease: UUID) -> Bool {
        precondition(Thread.isMainThread)
        guard canUseKnownRun(conversationID, lease: lease) else { return false }
        knownRun?.renegotiateAndRecover(); return true
    }
    @discardableResult
    func stopKnownRun(conversationID: String, lease: UUID) -> Bool {
        precondition(Thread.isMainThread)
        guard canUseKnownRun(conversationID, lease: lease) else { return false }
        return knownRun?.stop() ?? false
    }
    private func canUseKnownRun(_ cid: String, lease: UUID) -> Bool {
        isCurrent && readerVisible && readerLease == lease && selectedConversationID == cid &&
            knownAddress?.conversationID == cid && history.deletions[cid] != .pending &&
            history.deletions[cid] != .unknown && history.deletions[cid] != .confirmed
    }

    /// Called only after History has released all SDK/Cache/scope gates.
    func historyDidChange(_ history: ClawAssistantHistory) {
        precondition(Thread.isMainThread)
        guard isCurrent else { clearKnownRun(); return }
        knownRun?.updateReadCapabilities(history.capabilityError == nil ? history.capabilities : nil)
        if let address = knownAddress {
            if history.deletions[address.conversationID] == .confirmed {
                clearKnownRun(); publishKnownChange(); return
            }
            let deletion = history.deletions[address.conversationID]
            knownRun?.setDeletionPaused(deletion == .pending || deletion == .unknown)
        }
        guard isCurrent, let cid = selectedConversationID,
              history.deletions[cid] != .pending, history.deletions[cid] != .unknown,
              history.deletions[cid] != .confirmed,
              history.capabilityError == nil, let capabilities = history.capabilities,
              capabilities.history.available, (try? capabilities.validateRuns()) != nil,
              let token = history.bSnapshotTokens[cid], token != boundSnapshot,
              let rows = history.bDetails[cid] else { return }
        guard let row = rows.last(where: { !$0.run_id.isEmpty }) else {
            if knownRun?.hasUnresolvedStop != true { clearKnownRun(); boundSnapshot = token }
            publishKnownChange(); return
        }
        let address = KnownAddress(conversationID: cid, runID: row.run_id)
        if knownAddress == address, let run = knownRun {
            boundSnapshot = token
            if run.lastError == .historyChanged, readerVisible { run.recover() }
            publishKnownChange(); return
        }
        guard knownRun?.hasUnresolvedStop != true else { return }
        clearKnownRun()
        boundSnapshot = token
        do {
            let run = try ClawAssistantRun(session: self, capabilities: capabilities, knownRunsOnly: true,
                validateBinding: { [weak self] snapshot in
                    guard let self = self else { return .retired }
                    return self.bindingError(snapshot, address: address)
                }, capabilitiesChanged: { [weak self] capabilities in
                    guard let self = self, self.isCurrent, self.knownAddress == address else { return }
                    self.history.acceptKnownCapabilities(capabilities)
                })
            knownRun = run; knownAddress = address
            run.changed = { [weak self, weak run] in
                guard let self = self, let run = run, self.knownRun === run else { return }
                self.runDidChange(run, address: address)
            }
            run.setVisible(readerVisible)
            if readerVisible { _ = run.recover(conversationID: cid, runID: address.runID) }
        } catch { clearKnownRun() }
        publishKnownChange()
    }
    private func bindingError(_ snapshot: ClawAssistantRunSnapshot, address: KnownAddress) -> ClawAssistantError? {
        let receipt = snapshot.receipt
        guard receipt.conversation_id == address.conversationID, receipt.run_id == address.runID else { return .invalidResponse }
        if receipt.isLegacy { return nil } // Empty legacy pointers are historical, never live overlays.
        guard let rows = history.bDetails[address.conversationID],
              let question = rows.first(where: { $0.message_id == receipt.question_message_id }),
              let answer = rows.first(where: { $0.message_id == receipt.answer_message_id }) else { return .historyChanged }
        guard question.role == "user", answer.role == "assistant",
              question.conversation_id == address.conversationID, answer.conversation_id == address.conversationID,
              answer.run_id == address.runID, ClawAssistantWire.less(question.seq, answer.seq) else { return .invalidResponse }
        // retry_of legitimately reuses a question whose run_id names the earlier attempt.
        return nil
    }
    private func runDidChange(_ run: ClawAssistantRun, address: KnownAddress) {
        guard isCurrent else { clearKnownRun(); return }
        if run.isDeleted {
            // Detach first so the authoritative History notification cannot recurse into this run.
            clearKnownRun()
            history.acceptKnownRunTombstone(address.conversationID)
            publishKnownChange(); return
        }
        var align = false
        if readerVisible, run.lastError == .historyChanged, !repairedBindings.contains(address) {
            repairedBindings.insert(address); align = true
        } else if readerVisible, let projection = run.projection, projection.terminal,
                  !alignedTerminals.contains(address) {
            alignedTerminals.insert(address)
            align = history.bDetailRevisions[address.conversationID].map {
                ClawAssistantWire.less($0, projection.revision)
            } ?? true
        }
        publishKnownChange()
        // Notifications may synchronously retire the scope. New reads must recheck afterwards.
        if isCurrent, knownRun === run, !run.hasUnresolvedStop,
           history.bSnapshotTokens[address.conversationID] != boundSnapshot {
            // A newer complete snapshot may have waited behind the old stop's unresolved result.
            historyDidChange(history)
        }
        if align, isCurrent, knownRun === run, history.deletions[address.conversationID] != .pending,
           history.deletions[address.conversationID] != .unknown {
            history.loadMessages(address.conversationID)
        }
    }
    private func clearKnownRun() {
        let old = knownRun
        knownRun = nil; knownAddress = nil; boundSnapshot = nil
        old?.changed = nil; old?.retire()
    }
    private func publishKnownChange() {
        NotificationCenter.default.post(name: Self.knownRunChanged, object: self)
    }
    func messageRows(_ conversationID: String) -> [ClawAssistantMessageViewValue] {
        precondition(Thread.isMainThread)
        guard isCurrent, history.deletions[conversationID] != .confirmed else { return [] }
        if let rows = history.bDetails[conversationID] {
            let projection = knownAddress?.conversationID == conversationID ? knownRun?.projection : nil
            return rows.map { row in
                if let projection = projection, !projection.receipt.isLegacy,
                   projection.receipt.conversation_id == conversationID,
                   projection.receipt.run_id == row.run_id, projection.receipt.answer_message_id == row.message_id,
                   row.role == "assistant", let revision = history.bDetailRevisions[conversationID],
                   !ClawAssistantWire.less(projection.revision, revision) {
                    return ClawAssistantMessageViewValue(id: row.message_id, role: row.role, text: projection.text,
                        state: ClawAssistantMessageViewValue.caption(projection.state))
                }
                return ClawAssistantMessageViewValue(id: row.message_id, role: row.role, text: row.text,
                    state: row.role == "assistant" ? ClawAssistantMessageViewValue.caption(row.state) : nil)
            }
        }
        return (history.details[conversationID] ?? []).map {
            ClawAssistantMessageViewValue(id: $0.message_id, role: $0.role, text: $0.text,
                state: $0.role == "assistant" ? ClawAssistantMessageViewValue.caption($0.state) : nil)
        }
    }

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
            self.clearKnownRun()
            self.readerLease = nil; self.readerVisible = false; self.selectedConversationID = nil
            self.repairedBindings.removeAll(); self.alignedTerminals.removeAll()
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }
}
