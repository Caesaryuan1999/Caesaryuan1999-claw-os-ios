// Copyright (c) 2026 CLAW OS contributors.
import Foundation

/// Main-thread state machine. Pages are staged separately; callbacks never adopt a new account.
final class ClawAssistantHistory {
    enum Deletion: Equatable {
        case pending, unknown, confirmed, rejected(ClawAssistantError)
    }
    private weak var session: ClawAssistantSession?
    private var observers: [UUID: () -> Void] = [:]
    private var retirement: NSObjectProtocol?
    private var capabilityRead = UUID()
    private var listRead = UUID()
    private var detailReads: [String: UUID] = [:]
    private var deleteWrites: [String: UUID] = [:]
    private var tombstones = Set<String>()
    private(set) var capabilities: ClawAssistantCapabilities?
    private(set) var capabilityError: ClawAssistantError?
    private(set) var capabilityLoading = false
    private(set) var listLoading = false
    private(set) var listError: ClawAssistantError?
    private(set) var hasListSnapshot = false
    private(set) var conversations: [ClawAssistantConversation] = []
    private(set) var details: [String: [ClawAssistantMessage]] = [:]
    private(set) var bDetails: [String: [ClawAssistantBMessage]] = [:]
    private(set) var bDetailRevisions: [String: String] = [:]
    private(set) var bSnapshotTokens: [String: UUID] = [:]
    private(set) var detailErrors: [String: ClawAssistantError] = [:]
    private(set) var detailLoading = Set<String>()
    private(set) var deletions: [String: Deletion] = [:]

    init(session: ClawAssistantSession) {
        self.session = session
        retirement = NotificationCenter.default.addObserver(forName: ClawAssistantSession.changed,
            object: nil, queue: .main) { [weak self, weak session] notification in
            guard let session = session, notification.object as? ClawAssistantSession === session else { return }
            self?.clear()
        }
    }
    deinit { if let retirement = retirement { NotificationCenter.default.removeObserver(retirement) } }

    var isCurrent: Bool { session?.isCurrent ?? false }
    var draft: String { session?.draft ?? "" }
    func setDraft(_ value: String) {
        precondition(Thread.isMainThread)
        session?.updateDraft(value); changed()
    }
    var providerNotice: String {
        if capabilities?.generation.available == true && capabilityError == nil {
            return draft.isEmpty ? "当前版本暂不支持发送提问，请更新应用。" : "你的问题已保留。请更新应用后再发送。"
        }
        return draft.isEmpty ? "服务暂未开通。" : "服务暂未开通，你的问题已保留。"
    }
    @discardableResult func observe(_ callback: @escaping () -> Void) -> UUID {
        precondition(Thread.isMainThread)
        let id = UUID(); observers[id] = callback; return id
    }
    func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }
    private func changed() {
        // receive has released SDK/Cache/scope locks before this one-way coordination.
        session?.historyDidChange(self)
        Array(observers.values).forEach { $0() }
    }
    private func clear() {
        precondition(Thread.isMainThread)
        capabilityRead = UUID(); listRead = UUID(); detailReads.removeAll(); deleteWrites.removeAll()
        capabilities = nil; conversations.removeAll(); details.removeAll(); tombstones.removeAll()
        bDetails.removeAll(); bDetailRevisions.removeAll(); bSnapshotTokens.removeAll()
        deletions.removeAll(); detailErrors.removeAll(); detailLoading.removeAll()
        hasListSnapshot = false; capabilityLoading = false; listLoading = false
        capabilityError = .signInRequired; listError = .signInRequired
        changed()
    }
    private func receive<T>(_ result: Result<T, ClawAssistantError>, operation: @escaping () -> Bool,
                            apply: @escaping (Result<T, ClawAssistantError>) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let session = self.session else { return }
            guard session.isCurrent else { self.clear(); return }
            guard operation() else { return }
            if case .failure(.server(401, _)) = result {
                session.blockAuthorization()
                return
            }
            let applied = session.withCurrent { () -> Bool in
                guard operation() else { return false }
                apply(result); return true
            } ?? false
            if applied { self.changed() }
        }
    }

    func loadCapabilities() {
        precondition(Thread.isMainThread)
        guard let session = session, session.isCurrent else { clear(); return }
        let id = UUID(); capabilityRead = id
        capabilityLoading = true; capabilityError = nil; changed()
        session.service.capabilities { [weak self] result in
            self?.receive(result, operation: { [weak self] in self?.capabilityRead == id }) { [weak self] result in
                guard let self = self else { return }
                self.capabilityLoading = false
                switch result {
                case .success(let value): self.capabilities = value; self.capabilityError = nil
                case .failure(let error): self.capabilityError = error
                }
            }
        }
    }
    /// The known Run's explicit manual negotiation completed on this same scope.
    func acceptKnownCapabilities(_ capabilities: ClawAssistantCapabilities) {
        precondition(Thread.isMainThread)
        guard let session = session, (try? capabilities.validateRuns()) != nil else { return }
        let applied = session.withCurrent { () -> Bool in
            self.capabilityRead = UUID(); self.capabilityLoading = false
            self.capabilities = capabilities; self.capabilityError = nil; return true
        } ?? false
        if applied { changed() }
    }

    func loadConversations() {
        precondition(Thread.isMainThread)
        guard let session = session, session.isCurrent else { clear(); return }
        guard capabilities?.history.available == true else { listError = .unavailable; changed(); return }
        let id = UUID(); listRead = id; listLoading = true; listError = nil; changed()
        listPage(id: id, cursor: nil, revision: nil, staged: [], restarts: 0, pages: 0)
    }
    private func listPage(id: UUID, cursor: String?, revision: String?, staged: [ClawAssistantConversation],
                          restarts: Int, pages: Int) {
        guard let session = session, session.isCurrent, id == listRead else { return }
        guard pages < 1000 else { listLoading = false; listError = .responseTooLarge; changed(); return }
        session.service.conversations(cursor: cursor, revision: revision) { [weak self] result in
            // Validation/commit is gated; further network work is deliberately after receive's locks.
            var next: (() -> Void)?
            self?.receive(result, operation: { [weak self] in self?.listRead == id }) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(.historyChanged) where restarts < 2:
                    next = { [weak self] in self?.listPage(id: id, cursor: nil, revision: nil,
                                                          staged: [], restarts: restarts + 1, pages: 0) }
                case .failure(let error):
                    self.listLoading = false; self.listError = error
                case .success(let page):
                    guard revision == nil || page.snapshot_revision == revision,
                          page.items.first.map({ $0.conversation_id > (cursor ?? "") }) ?? page.next_cursor.isEmpty,
                          !page.items.contains(where: { self.tombstones.contains($0.conversation_id) && !$0.deleted }),
                          staged.count + page.items.count <= 20000 else {
                        self.listLoading = false; self.listError = .invalidResponse; return
                    }
                    let combined = staged + page.items
                    if page.next_cursor.isEmpty {
                        self.conversations = combined.filter { !$0.deleted }
                        for item in combined where item.deleted { self.confirmDeleted(item.conversation_id) }
                        self.hasListSnapshot = true; self.listLoading = false; self.listError = nil
                    } else {
                        next = { [weak self] in self?.listPage(id: id, cursor: page.next_cursor,
                            revision: page.snapshot_revision, staged: combined, restarts: restarts, pages: pages + 1) }
                    }
                }
            }
            DispatchQueue.main.async { next?() }
        }
    }

    func loadMessages(_ conversationID: String) {
        precondition(Thread.isMainThread)
        guard let session = session, session.isCurrent else { clear(); return }
        guard ClawAssistantWire.uuid(conversationID), !tombstones.contains(conversationID),
              deletions[conversationID] != .pending else { return }
        let id = UUID(); detailReads[conversationID] = id
        detailErrors[conversationID] = nil; detailLoading.insert(conversationID); changed()
        if let capabilities = capabilities, (try? capabilities.validateRuns()) != nil {
            bMessagePage(conversationID, capabilities: capabilities, id: id, after: "0", revision: nil,
                         staged: [], restarts: 0, pages: 0, bytes: 0)
        } else {
            messagePage(conversationID, id: id, after: "0", revision: nil, staged: [], restarts: 0, pages: 0, bytes: 0)
        }
    }
    private func messagePage(_ conversationID: String, id: UUID, after: String, revision: String?,
                             staged: [ClawAssistantMessage], restarts: Int, pages: Int, bytes: Int) {
        guard let session = session, session.isCurrent, detailReads[conversationID] == id else { return }
        guard pages < 1000 else {
            detailLoading.remove(conversationID); detailErrors[conversationID] = .responseTooLarge; changed(); return
        }
        session.service.messages(conversationID, after: after, revision: revision) { [weak self] result in
            var next: (() -> Void)?
            self?.receive(result, operation: { [weak self] in
                self?.detailReads[conversationID] == id && self?.tombstones.contains(conversationID) == false
            }) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(.historyChanged) where restarts < 2:
                    next = { [weak self] in self?.messagePage(conversationID, id: id, after: "0", revision: nil,
                        staged: [], restarts: restarts + 1, pages: 0, bytes: 0) }
                case .failure(.server(410, "conversation_deleted")):
                    self.confirmDeleted(conversationID)
                case .failure(let error):
                    self.detailLoading.remove(conversationID); self.detailErrors[conversationID] = error
                case .success(let page):
                    let total = bytes + page.items.reduce(0) { $0 + $1.text.utf8.count + 1024 }
                    let knownIDs = Set(staged.map { $0.message_id })
                    guard page.conversation_id == conversationID,
                          revision == nil || page.snapshot_revision == revision,
                          page.items.first.map({ ClawAssistantWire.less(after, $0.seq) }) ?? page.next_after_seq.isEmpty,
                          !page.items.contains(where: { knownIDs.contains($0.message_id) }),
                          total <= 64 * 1024 * 1024 else {
                        self.detailLoading.remove(conversationID); self.detailErrors[conversationID] = .invalidResponse
                        return
                    }
                    let combined = staged + page.items
                    if page.next_after_seq.isEmpty {
                        self.details[conversationID] = combined
                        self.bDetails[conversationID] = nil; self.bDetailRevisions[conversationID] = nil
                        self.bSnapshotTokens[conversationID] = nil
                        self.detailLoading.remove(conversationID); self.detailErrors[conversationID] = nil
                    } else {
                        next = { [weak self] in self?.messagePage(conversationID, id: id, after: page.next_after_seq,
                            revision: page.snapshot_revision, staged: combined, restarts: restarts,
                            pages: pages + 1, bytes: total) }
                    }
                }
            }
            DispatchQueue.main.async { next?() }
        }
    }

    private func bMessagePage(_ conversationID: String, capabilities: ClawAssistantCapabilities, id: UUID, after: String, revision: String?,
                             staged: [ClawAssistantBMessage], restarts: Int, pages: Int, bytes: Int) {
        guard let session = session, session.isCurrent, detailReads[conversationID] == id else { return }
        guard pages < 1000 else {
            detailLoading.remove(conversationID); detailErrors[conversationID] = .responseTooLarge; changed(); return
        }
        session.service.messagesB(conversationID, after: after, revision: revision, capabilities: capabilities) { [weak self] result in
            var next: (() -> Void)?
            self?.receive(result, operation: { [weak self] in
                self?.detailReads[conversationID] == id && self?.tombstones.contains(conversationID) == false
            }) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(.historyChanged) where restarts < 2:
                    next = { [weak self] in self?.bMessagePage(conversationID, capabilities: capabilities, id: id, after: "0", revision: nil,
                        staged: [], restarts: restarts + 1, pages: 0, bytes: 0) }
                case .failure(.server(410, "conversation_deleted")):
                    self.confirmDeleted(conversationID)
                case .failure(let error):
                    self.detailLoading.remove(conversationID); self.detailErrors[conversationID] = error
                case .success(let page):
                    let total = bytes + page.items.reduce(0) { $0 + $1.text.utf8.count + 1024 }
                    let knownIDs = Set(staged.map { $0.message_id })
                    guard page.conversation_id == conversationID,
                          revision == nil || page.snapshot_revision == revision,
                          page.items.first.map({ ClawAssistantWire.less(after, $0.seq) }) ?? page.next_after_seq.isEmpty,
                          !page.items.contains(where: { knownIDs.contains($0.message_id) }),
                          total <= 64 * 1024 * 1024 else {
                        self.detailLoading.remove(conversationID); self.detailErrors[conversationID] = .invalidResponse
                        return
                    }
                    let combined = staged + page.items
                    if page.next_after_seq.isEmpty {
                        self.bDetails[conversationID] = combined
                        self.bDetailRevisions[conversationID] = page.snapshot_revision
                        self.bSnapshotTokens[conversationID] = UUID()
                        self.details[conversationID] = nil
                        self.detailLoading.remove(conversationID); self.detailErrors[conversationID] = nil
                    } else {
                        next = { [weak self] in self?.bMessagePage(conversationID, capabilities: capabilities, id: id, after: page.next_after_seq,
                            revision: page.snapshot_revision, staged: combined, restarts: restarts,
                            pages: pages + 1, bytes: total) }
                    }
                }
            }
            DispatchQueue.main.async { next?() }
        }
    }

    /// Only the explicit confirmation consumer calls this, including same-ID retry.
    func deleteConversation(_ conversationID: String) {
        precondition(Thread.isMainThread)
        guard let session = session, session.isCurrent else { clear(); return }
        guard ClawAssistantWire.uuid(conversationID), !tombstones.contains(conversationID),
              deletions[conversationID] != .pending else { return }
        let id = UUID(); deleteWrites[conversationID] = id
        let wasUnknown = deletions[conversationID] == .unknown
        listRead = UUID(); listLoading = false // A pre-delete snapshot must never resurrect content.
        detailReads[conversationID] = UUID(); detailLoading.remove(conversationID)
        deletions[conversationID] = .pending; changed()
        session.service.delete(conversationID) { [weak self] result in
            self?.receive(result, operation: { [weak self] in self?.deleteWrites[conversationID] == id }) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let receipt) where receipt.conversation_id == conversationID:
                    self.confirmDeleted(conversationID)
                case .failure(.server(410, "conversation_deleted")):
                    self.confirmDeleted(conversationID)
                case .failure(.server(let code, let reason)) where (400..<500).contains(code) && code != 408:
                    self.deletions[conversationID] = wasUnknown ? .unknown : .rejected(.server(code, reason))
                default:
                    self.deletions[conversationID] = .unknown
                }
            }
        }
    }
    private func confirmDeleted(_ id: String) {
        tombstones.insert(id); deletions[id] = .confirmed
        deleteWrites[id] = UUID() // A late uncertain reply cannot undo an authoritative tombstone.
        conversations.removeAll { $0.conversation_id == id }
        details[id] = nil; detailErrors[id] = nil; detailLoading.remove(id); detailReads[id] = UUID()
        bDetails[id] = nil; bDetailRevisions[id] = nil; bSnapshotTokens[id] = nil
    }
    /// Only a validated Run 410 reaches here. Commit the tombstone before notifying Run/UI.
    func acceptKnownRunTombstone(_ id: String) {
        precondition(Thread.isMainThread)
        guard let session = session, !tombstones.contains(id) else { return }
        let applied = session.withCurrent { self.confirmDeleted(id); return true } ?? false
        if applied { changed() }
    }
    func reconcileDeletion(_ id: String) {
        precondition(Thread.isMainThread)
        guard deletions[id] == .unknown else { return }
        // Active is NOT proof that a previously dispatched DELETE cannot still commit.
        loadConversations()
    }
}
