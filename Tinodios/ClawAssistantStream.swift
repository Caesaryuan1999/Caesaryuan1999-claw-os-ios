// Copyright (c) 2026 CLAW OS contributors.
import Foundation

enum ClawAssistantStreamEnd {
    case eof, deadline, cancelled
    case failure(ClawAssistantError)
}

/// Incremental framing. UTF-8 is decoded only after a complete line, never per network chunk.
struct ClawAssistantSSEParser {
    enum Frame { case event(ClawAssistantRunEvent), access(ClawAssistantError) }
    static let frameLimit = 64 * 1024
    private var line = Data()
    private var payload = Data()
    private var kind: String?
    private var id: String?
    private var frameBytes = 0
    private var skipLF = false
    private var firstLine = true

    mutating func append(_ bytes: Data) throws -> [Frame] {
        var frames: [Frame] = []
        for byte in bytes {
            if skipLF { skipLF = false; if byte == 10 { continue } }
            if byte == 10 || byte == 13 {
                if let frame = try finishLine() { frames.append(frame) }
                skipLF = byte == 13
            } else {
                guard line.count < Self.frameLimit, frameBytes < Self.frameLimit else {
                    throw ClawAssistantError.responseTooLarge
                }
                line.append(byte); frameBytes += 1
            }
        }
        return frames
    }

    private mutating func finishLine() throws -> Frame? {
        if firstLine {
            firstLine = false
            if line.starts(with: [0xEF, 0xBB, 0xBF]) { line.removeFirst(3) }
        }
        guard let value = String(data: line, encoding: .utf8) else { throw ClawAssistantError.invalidResponse }
        line.removeAll(keepingCapacity: true)
        if value.isEmpty {
            defer { kind = nil; id = nil; payload.removeAll(keepingCapacity: true); frameBytes = 0 }
            guard !payload.isEmpty else {
                guard kind == nil, id == nil else { throw ClawAssistantError.invalidResponse }
                return nil
            }
            payload.removeLast() // SSE joins data lines with LF and removes the final LF.
            if kind == "access_error" {
                struct Control: Decodable { let code: String }
                guard id == nil, let control = try? JSONDecoder().decode(Control.self, from: payload) else {
                    throw ClawAssistantError.invalidResponse
                }
                let codes = ["authentication_required": 401, "conversation_deleted": 410,
                             "not_found": 404, "history_unavailable": 503, "permission_denied": 403]
                guard let status = codes[control.code] else { throw ClawAssistantError.incompatible }
                return .access(.server(status, control.code))
            }
            guard let decoded = try? JSONDecoder().decode(ClawAssistantRunEvent.self, from: payload),
                  kind == decoded.kind, id == decoded.id else { throw ClawAssistantError.invalidResponse }
            try decoded.validate()
            return .event(decoded)
        }
        if value.hasPrefix(":") {
            // Keep-alive comments do not consume a persistent id or an unbounded frame budget.
            frameBytes -= value.utf8.count
            return nil
        }
        let pieces = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(pieces[0])
        var text = pieces.count == 2 ? String(pieces[1]) : ""
        if text.hasPrefix(" ") { text.removeFirst() }
        switch field {
        case "event":
            guard kind == nil else { throw ClawAssistantError.invalidResponse }; kind = text
        case "id":
            guard id == nil, ClawAssistantWire.decimal(text), text != "0" else {
                throw ClawAssistantError.invalidResponse
            }
            id = text
        case "data":
            guard payload.count + text.utf8.count + 1 <= Self.frameLimit else { throw ClawAssistantError.responseTooLarge }
            payload.append(contentsOf: text.utf8); payload.append(10)
        default: break // Unknown SSE fields, including retry, never alter client deadlines/retry policy.
        }
        return nil
    }

    func validateEOF() throws {
        guard line.isEmpty, payload.isEmpty, kind == nil, id == nil else { throw ClawAssistantError.invalidResponse }
    }
}

/// This deadline does not slide on data or heartbeats. The injected clock also tests the real decision.
struct ClawAssistantStreamDeadline {
    let end: TimeInterval
    init(now: TimeInterval) { end = now + 60 }
    func expired(now: TimeInterval) -> Bool { now >= end }
}

/// Separate ephemeral session: a busy reader never queues stop behind its body consumption.
final class ClawAssistantStream: NSObject, URLSessionDataDelegate, ClawAssistantCancellation {
    private let lock = NSRecursiveLock()
    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private let isCurrent: () -> Bool
    private let event: (ClawAssistantRunEvent) -> Void
    private var completion: ((ClawAssistantStreamEnd) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var timer: DispatchSourceTimer?
    private var deadline: ClawAssistantStreamDeadline?
    private var parser = ClawAssistantSSEParser()
    private var opened = false
    private var finished = false

    init(request: URLRequest, configuration: URLSessionConfiguration, isCurrent: @escaping () -> Bool,
         event: @escaping (ClawAssistantRunEvent) -> Void, completion: @escaping (ClawAssistantStreamEnd) -> Void) {
        self.request = request; self.isCurrent = isCurrent; self.event = event; self.completion = completion
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.configuration.timeoutIntervalForRequest = 60
        self.configuration.timeoutIntervalForResource = 60
        self.configuration.httpCookieStorage = nil; self.configuration.httpShouldSetCookies = false
        self.configuration.urlCache = nil; self.configuration.urlCredentialStorage = nil
        self.configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.configuration.httpAdditionalHeaders = nil
    }
    func start() {
        guard isCurrent() else { finish(.failure(.retired)); return }
        lock.lock(); defer { lock.unlock() }
        guard !finished, session == nil else { return }
        deadline = ClawAssistantStreamDeadline(now: ProcessInfo.processInfo.systemUptime)
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request); self.task = task
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        self.timer = timer
        timer.schedule(deadline: .now() + 60)
        timer.setEventHandler { [weak self] in self?.finish(.deadline) }
        timer.resume(); task.resume()
    }
    func cancel() { finish(.cancelled) }
    private func finish(_ result: ClawAssistantStreamEnd) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let completion = self.completion; self.completion = nil
        let session = self.session; self.session = nil; task = nil
        let timer = self.timer; self.timer = nil; parser = ClawAssistantSSEParser()
        lock.unlock()
        timer?.cancel(); session?.invalidateAndCancel(); completion?(result)
    }
    private func allowed() -> Bool {
        // Never call the SDK/Cache gate while holding the stream lock.
        guard isCurrent() else { finish(.failure(.retired)); return false }
        lock.lock()
        let ended = finished
        let expired = deadline?.expired(now: ProcessInfo.processInfo.systemUptime) ?? false
        lock.unlock()
        if expired { finish(.deadline); return false }
        return !ended
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); finish(.failure(.invalidResponse))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard allowed() else { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse, http.url == request.url else {
            completionHandler(.cancel); finish(.failure(.invalidResponse)); return
        }
        if http.statusCode == 401 {
            completionHandler(.cancel); finish(.failure(.server(401, "authentication_required"))); return
        }
        if http.statusCode == 204 { completionHandler(.cancel); finish(.eof); return }
        guard http.statusCode == 200, http.mimeType?.lowercased() == "text/event-stream" else {
            completionHandler(.cancel)
            let codes = [403: "permission_denied", 404: "not_found", 410: "conversation_deleted"]
            if let code = codes[http.statusCode] { finish(.failure(.server(http.statusCode, code))) }
            else { finish(.failure(.invalidResponse)) }
            return
        }
        lock.lock(); opened = true; let ended = finished; lock.unlock()
        completionHandler(ended ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard allowed() else { return }
        let frames: [ClawAssistantSSEParser.Frame]
        lock.lock()
        guard !finished, opened else { lock.unlock(); return }
        do { frames = try parser.append(data) }
        catch { lock.unlock(); finish(.failure((error as? ClawAssistantError) ?? .invalidResponse)); return }
        lock.unlock()
        for frame in frames {
            guard allowed() else { return }
            switch frame {
            case .event(let value): event(value)
            case .access(let error): finish(.failure(error)); return
            }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard allowed() else { return }
        lock.lock(); let parser = self.parser; let opened = self.opened; lock.unlock()
        guard error == nil else { finish(.failure(.transport)); return }
        do { try parser.validateEOF() }
        catch { finish(.failure(.invalidResponse)); return }
        finish(opened ? .eof : .failure(.invalidResponse))
    }
}
