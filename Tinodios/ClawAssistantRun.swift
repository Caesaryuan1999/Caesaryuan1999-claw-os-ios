// Copyright (c) 2026 CLAW OS contributors.
import Foundation

private final class ClawAssistantReadDelay: ClawAssistantCancellation {
    let item: DispatchWorkItem
    init(delay: TimeInterval, work: @escaping () -> Void) {
        item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    func cancel() { item.cancel() }
}

/// B1 is not attached to UI. No disk journal or automatic POST replay exists here.
/// All entry points and state observations are on main; SDK/Cache locks only protect state commits.
final class ClawAssistantRun {
    enum Submission: Equatable { case idle, pending, unknown, accepted, rejected(ClawAssistantError) }
    enum Stop: Equatable { case idle, pending, unknown, confirmed, rejected(ClawAssistantError) }
    struct Ticket: Equatable {
        let conversationID: String
        let input: ClawAssistantRunInput
        let body: Data
    }
    struct Projection: Equatable {
        let receipt: ClawAssistantRunReceipt
        var text: String
        var state: String
        var reason: String
        var lastEvent: String
        var revision: String
        var terminal: Bool { ClawAssistantRunWire.terminal.contains(state) }
    }
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> ClawAssistantCancellation
    private let session: ClawAssistantSession
    private var capabilities: ClawAssistantCapabilities
    private let schedule: Schedule
    private var retirement: NSObjectProtocol?
    private var readOperation = UUID()
    private var writeOperation = UUID()
    private var stopOperation = UUID()
    private var readTask: ClawAssistantCancellation?
    private var streamTask: ClawAssistantCancellation?
    private var writeTask: ClawAssistantCancellation?
    private var stopTask: ClawAssistantCancellation?
    private var delayTask: ClawAssistantCancellation?
    private var conversationReady = false
    private var visible = false
    private var retired = false
    private var tombstoned = false
    private var failures = 0
    private var seen: [String: ClawAssistantRunEvent] = [:]
    private var readAddress: (conversationID: String, runID: String)?
    private(set) var ticket: Ticket?
    private(set) var receipt: ClawAssistantRunReceipt?
    private(set) var projection: Projection?
    private(set) var submission = Submission.idle
    private(set) var stopping = Stop.idle
    private(set) var lastError: ClawAssistantError?
    var changed: (() -> Void)?

    init(session: ClawAssistantSession, capabilities: ClawAssistantCapabilities,
         schedule: @escaping Schedule = { ClawAssistantReadDelay(delay: $0, work: $1) }) throws {
        try capabilities.validateRuns()
        guard session.isCurrent else { throw ClawAssistantError.retired }
        self.session = session; self.capabilities = capabilities; self.schedule = schedule
        retirement = NotificationCenter.default.addObserver(forName: ClawAssistantSession.changed,
            object: nil, queue: .main) { [weak self, weak session] note in
                guard let session = session, note.object as? ClawAssistantSession === session else { return }
                self?.retire()
            }
    }
    deinit {
        if let retirement = retirement { NotificationCenter.default.removeObserver(retirement) }
        readTask?.cancel(); streamTask?.cancel(); writeTask?.cancel(); stopTask?.cancel(); delayTask?.cancel()
    }
    private var current: Bool { !retired && !tombstoned && session.isCurrent }
    private func notify() { changed?() }

    /// Explicit user action only. Generation remains disabled in the A UI.
    @discardableResult
    func submit(text: String, conversationID: String? = nil) -> Bool {
        precondition(Thread.isMainThread)
        guard current, capabilities.generation.available, submission != .pending, submission != .unknown,
              receipt == nil || projection?.terminal == true,
              stopping != .pending, stopping != .unknown else { return false }
        let cid = conversationID ?? UUID().uuidString.lowercased()
        let input = ClawAssistantRunInput(request_id: UUID().uuidString.lowercased(), text: text, retry_of: nil)
        return prepare(cid: cid, input: input, exists: conversationID != nil)
    }

    /// history must be the caller's complete current conversation snapshot, not the editor's text.
    @discardableResult
    func retryAnswer(_ original: ClawAssistantRunSnapshot, history: [ClawAssistantMessage]) -> Bool {
        precondition(Thread.isMainThread)
        guard current, capabilities.generation.available, submission != .pending, submission != .unknown,
              stopping != .pending, stopping != .unknown,
              receipt == nil || projection?.terminal == true,
              !original.receipt.isLegacy, ["interrupted", "failed"].contains(original.receipt.state),
              (try? original.validate()) != nil,
              let question = history.last(where: { $0.role == "user" }),
              question.message_id == original.receipt.question_message_id,
              question.conversation_id == original.receipt.conversation_id,
              history.allSatisfy({ $0.conversation_id == original.receipt.conversation_id }) else { return false }
        let input = ClawAssistantRunInput(request_id: UUID().uuidString.lowercased(), text: question.text,
                                          retry_of: original.receipt.run_id)
        return prepare(cid: original.receipt.conversation_id, input: input, exists: true)
    }
    private func prepare(cid: String, input: ClawAssistantRunInput, exists: Bool) -> Bool {
        guard ClawAssistantWire.uuid(cid), let body = try? input.body() else { return false }
        // Terminal observation can precede the old stop HTTP response. Retire that
        // response before clearing its receipt or installing a new conversation ticket.
        stopOperation = UUID()
        let previousStop = stopTask; stopTask = nil
        previousStop?.cancel() // Local transport only, outside SDK/Cache gates; never sends stop.
        cancelReads(); receipt = nil; projection = nil; readAddress = nil; seen.removeAll()
        ticket = Ticket(conversationID: cid, input: input, body: body)
        conversationReady = exists; stopping = .idle; failures = 0; lastError = nil
        dispatchSubmission(retry: false); return true
    }

    /// A POST, never labelled a read-only reconciliation. Retains the exact in-memory key/body.
    @discardableResult
    func retrySubmission() -> Bool {
        precondition(Thread.isMainThread)
        guard current, submission == .unknown, ticket != nil, receipt == nil else { return false }
        dispatchSubmission(retry: true); return true
    }
    private func dispatchSubmission(retry: Bool) {
        guard current, let ticket = ticket else { return }
        let op = UUID(); writeOperation = op
        submission = .pending; lastError = nil; notify()
        guard current, writeOperation == op else { return }
        if !conversationReady {
            writeTask = session.service.createConversation(ticket.conversationID, capabilities: capabilities,
                retrySubmission: retry) { [weak self] result in
                    self?.receive(result, valid: { $0.writeOperation == op }) { model, result in
                        switch result {
                        case .success(let value) where value.value.conversation_id == ticket.conversationID && !value.value.deleted:
                            model.conversationReady = true
                            return { [weak model] in model?.dispatchSubmission(retry: retry) }
                        default: model.submissionFailure(result.error ?? .invalidResponse, wasUnknown: retry)
                        }
                        return nil
                    }
                }
            return
        }
        writeTask = session.service.submitRun(ticket.conversationID, input: ticket.input,
            capabilities: capabilities, retrySubmission: retry) { [weak self] result in
                self?.receive(result, valid: { $0.writeOperation == op }) { model, result in
                    switch result {
                    case .success(let value) where value.conversation_id == ticket.conversationID &&
                        value.request_id == ticket.input.request_id && !value.isLegacy:
                        model.receipt = value; model.submission = .accepted
                        // Receipt has no output prefix: do not consume its last_event without GET text.
                        return model.visible ? { [weak model] in model?.recover() } : nil
                    default: model.submissionFailure(result.error ?? .invalidResponse, wasUnknown: retry)
                    }
                    return nil
                }
            }
    }
    private func submissionFailure(_ error: ClawAssistantError, wasUnknown: Bool) {
        lastError = error
        if !wasUnknown, case .server(let status, let code) = error,
           ((400..<500).contains(status) && status != 408 || status == 503 && code == "provider_not_configured") {
            submission = .rejected(error)
        } else { submission = .unknown }
    }

    /// Recovered authoritative history supplies rid after process death. Never guesses it from text.
    @discardableResult
    func recover(conversationID: String, runID: String) -> Bool {
        precondition(Thread.isMainThread)
        guard current, ClawAssistantWire.uuid(conversationID), ClawAssistantWire.uuid(runID),
              submission != .pending, submission != .unknown,
              receipt.map({ $0.conversation_id == conversationID && $0.run_id == runID }) ?? true else { return false }
        read(conversationID, runID: runID); return true
    }
    func recover() {
        precondition(Thread.isMainThread)
        guard current else { return }
        if let receipt = receipt { read(receipt.conversation_id, runID: receipt.run_id) }
        else if let address = readAddress { read(address.conversationID, runID: address.runID) }
    }
    /// Explicit manual recovery re-negotiates capabilities; it never retries a POST.
    func renegotiateAndRecover() {
        precondition(Thread.isMainThread)
        guard current, submission != .pending, submission != .unknown else { return }
        cancelReads()
        let op = readOperation
        readTask = session.service.capabilities { [weak self] result in
            self?.receive(result, valid: { $0.readOperation == op }) { model, result in
                switch result {
                case .success(let capabilities):
                    do { try capabilities.validateRuns() }
                    catch { model.lastError = .incompatible; return nil }
                    model.capabilities = capabilities
                    return { [weak model] in model?.recover() }
                case .failure(let error): model.lastError = error; return nil
                }
            }
        }
    }
    func setVisible(_ value: Bool) {
        precondition(Thread.isMainThread)
        guard visible != value else { return }
        visible = value
        if !value { cancelReads() }
        else if current, receipt != nil || readAddress != nil { recover() }
    }
    private func cancelReads() {
        readOperation = UUID()
        let tasks = [readTask, streamTask, delayTask]
        readTask = nil; streamTask = nil; delayTask = nil
        tasks.forEach { $0?.cancel() }
    }
    private func read(_ cid: String, runID: String) {
        cancelReads()
        readAddress = (cid, runID)
        let op = readOperation
        readTask = session.service.run(cid, runID: runID, capabilities: capabilities) { [weak self] result in
            self?.receive(result, valid: { $0.readOperation == op }) { model, result in
                switch result {
                case .success(let snapshot):
                    guard model.install(snapshot, cid: cid, rid: runID) else {
                        return { [weak model] in model?.readFailed(.invalidResponse) }
                    }
                    model.lastError = nil
                    if snapshot.receipt.isTerminal { model.failures = 0; model.stopping = model.stopping == .idle ? .idle : .confirmed }
                    return { [weak model] in model?.openStream() }
                case .failure(let error): return { [weak model] in model?.readFailed(error) }
                }
            }
        }
    }
    private func install(_ value: ClawAssistantRunSnapshot, cid: String, rid: String) -> Bool {
        guard value.receipt.conversation_id == cid, value.receipt.run_id == rid,
              receipt.map({ sameRunIdentity($0, value.receipt) }) ?? true else { return false }
        if let old = projection {
            guard !ClawAssistantWire.less(value.receipt.last_event, old.lastEvent),
                  !ClawAssistantWire.less(value.receipt.revision, old.revision),
                  !old.terminal || value.receipt.state == old.state else { return false }
            if value.receipt.last_event == old.lastEvent && value.text != old.text { return false }
        }
        receipt = value.receipt
        projection = Projection(receipt: value.receipt, text: value.text, state: value.receipt.state,
                                reason: value.reason, lastEvent: value.receipt.last_event, revision: value.receipt.revision)
        seen.removeAll(); return true
    }
    private func sameRunIdentity(_ a: ClawAssistantRunReceipt, _ b: ClawAssistantRunReceipt) -> Bool {
        a.conversation_id == b.conversation_id && a.run_id == b.run_id && a.request_id == b.request_id &&
            a.question_message_id == b.question_message_id && a.answer_message_id == b.answer_message_id &&
            a.isLegacy == b.isLegacy
    }
    private func openStream() {
        guard current, visible, let value = projection, !value.terminal, !value.receipt.isLegacy else { return }
        guard capabilities.stream.available else {
            lastError = .server(503, "history_unavailable"); notify(); return
        }
        let op = readOperation
        streamTask = session.service.stream(value.receipt.conversation_id, runID: value.receipt.run_id,
            after: value.lastEvent, capabilities: capabilities, event: { [weak self] event in
                self?.receive(Result<ClawAssistantRunEvent, ClawAssistantError>.success(event),
                    valid: { $0.readOperation == op }) { model, result in
                        guard case .success(let event) = result else { return nil }
                        let previous = model.projection?.lastEvent
                        guard model.apply(event) else { return { [weak model] in model?.readFailed(.invalidResponse) } }
                        if model.projection?.lastEvent != previous { model.failures = 0; model.lastError = nil }
                        if model.projection?.terminal == true {
                            if model.stopping != .idle { model.stopping = .confirmed }
                            return { [weak model] in model?.cancelReads() }
                        }
                        return nil
                    }
            }, completion: { [weak self] end in
                DispatchQueue.main.async {
                    guard let self = self, self.current, self.readOperation == op,
                          self.projection?.terminal == false else { return }
                    switch end {
                    case .cancelled: break
                    case .deadline: self.recover() // Normal rotation never resets consecutive failures.
                    case .eof: self.readFailed(.transport)
                    case .failure(let error):
                        if case .server(401, _) = error { self.session.blockAuthorization(); self.retire() }
                        else if case .server(410, _) = error { self.retireDeleted() }
                        else { self.readFailed(error) }
                    }
                }
            })
    }
    private func apply(_ event: ClawAssistantRunEvent) -> Bool {
        guard var value = projection else { return false }
        if !ClawAssistantWire.less(value.lastEvent, event.id) {
            return seen[event.id].map({ $0 == event }) ?? true // Already included by authoritative GET.
        }
        guard !value.terminal, ClawAssistantRunWire.next(value.lastEvent) == event.id,
              ClawAssistantWire.less(value.revision, event.revision), seen.count < 1024,
              Int64(event.id).map({ $0 <= 1024 }) ?? false else { return false }
        switch event.kind {
        case "accepted":
            guard value.state == "queued", event.id == "1", value.text.isEmpty else { return false }
        case "delta":
            guard let delta = event.delta, value.text.utf8.count + delta.utf8.count <= ClawAssistantRunWire.outputLimit else { return false }
            value.text += delta; value.state = "running"
        case "terminal": value.state = event.state ?? ""; value.reason = event.reason ?? ""
        default: return false
        }
        value.lastEvent = event.id; value.revision = event.revision
        projection = value; seen[event.id] = event; return true
    }
    private func readFailed(_ error: ClawAssistantError) {
        guard current else { return }
        cancelReads(); lastError = error; notify()
        guard visible, readAddress != nil, projection?.terminal != true else { return }
        if case .server(let status, _) = error, status == 403 || status == 404 { return }
        guard failures < 3 else { return }
        let delays: [TimeInterval] = [1, 2, 4]
        let seconds = delays[failures]; failures += 1
        let op = readOperation
        delayTask = schedule(seconds) { [weak self] in
            guard let self = self, self.current, self.visible, self.readOperation == op else { return }
            self.recover()
        }
    }
    @discardableResult
    func stop() -> Bool {
        precondition(Thread.isMainThread)
        guard current, let value = projection, !value.terminal, !value.receipt.isLegacy, stopping != .pending else { return false }
        let wasUnknown = stopping == .unknown
        let op = UUID(); stopOperation = op; stopping = .pending; notify()
        guard current, stopOperation == op else { return false }
        stopTask = session.service.run(value.receipt.conversation_id, runID: value.receipt.run_id,
            capabilities: capabilities, stop: true) { [weak self] result in
                self?.receive(result, valid: { model in
                    model.stopOperation == op &&
                        (model.receipt.map { model.sameRunIdentity($0, value.receipt) } ?? false)
                }) { model, result in
                    if case .success(let snapshot) = result, snapshot.receipt.isTerminal,
                       model.sameRunIdentity(snapshot.receipt, value.receipt),
                       model.install(snapshot, cid: value.receipt.conversation_id, rid: value.receipt.run_id) {
                        model.stopping = .confirmed; model.lastError = nil; model.failures = 0
                        return { [weak model] in model?.cancelReads() }
                    }
                    // A stream/GET terminal wins over a late stop failure.
                    if model.projection?.terminal == true { model.stopping = .confirmed; return nil }
                    let error = result.error ?? .invalidResponse; model.lastError = error
                    if !wasUnknown, case .server(let status, _) = error, (400..<500).contains(status), status != 408 {
                        model.stopping = .rejected(error)
                    } else { model.stopping = .unknown }
                    return nil
                }
            }
        return true
    }
    @discardableResult
    func markDeleted(conversationID: String) -> Bool {
        precondition(Thread.isMainThread)
        let currentID = receipt?.conversation_id ?? ticket?.conversationID ?? readAddress?.conversationID
        guard currentID == conversationID else { return false }
        retireDeleted(); return true
    }
    private func retireDeleted() {
        tombstoned = true; retire()
    }
    func retire() {
        precondition(Thread.isMainThread)
        guard !retired else { return }
        retired = true; visible = false; writeOperation = UUID(); stopOperation = UUID()
        cancelReads(); writeTask?.cancel(); stopTask?.cancel(); writeTask = nil; stopTask = nil
        ticket = nil; receipt = nil; projection = nil; readAddress = nil; seen.removeAll(); lastError = .retired; notify()
    }
    private func receive<T>(_ result: Result<T, ClawAssistantError>, valid: @escaping (ClawAssistantRun) -> Bool,
                            apply: @escaping (ClawAssistantRun, Result<T, ClawAssistantError>) -> (() -> Void)?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.current else { self.retire(); return }
            guard valid(self) else { return }
            if case .failure(.server(401, _)) = result { self.session.blockAuthorization(); self.retire(); return }
            if case .failure(.server(410, _)) = result { self.retireDeleted(); return }
            var next: (() -> Void)?
            let committed = self.session.withCurrent { () -> Bool in
                guard valid(self), !self.retired, !self.tombstoned else { return false }
                next = apply(self, result); return true
            } ?? false
            if committed {
                self.notify()
                if self.current, valid(self) { next?() }
            }
        }
    }
}

private extension Result where Failure == ClawAssistantError {
    var error: ClawAssistantError? { if case .failure(let error) = self { return error }; return nil }
}
