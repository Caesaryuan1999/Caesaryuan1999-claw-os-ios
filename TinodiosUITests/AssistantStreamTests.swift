// Copyright (c) 2026 CLAW OS contributors.
import XCTest
import Foundation
import Network
import TinodeSDK
@testable import Tinodios

/// Loopback-only real TCP fixture. No configured server, model or credential is contacted.
private final class AssistantSocketServer {
    struct Request { let method: String; let path: String; let headers: [String: String]; let body: Data }
    final class Reply {
        let connection: NWConnection
        var sendObservation: ((Int, NWError?) -> Void)?
        init(_ connection: NWConnection) { self.connection = connection }
        func send(_ data: Data, completion: (() -> Void)? = nil) {
            let observation = sendObservation
            connection.send(content: data, completion: .contentProcessed { error in
                observation?(data.count, error)
                completion?()
            })
        }
        func json(_ value: Any, status: Int = 200) {
            let body = try! JSONSerialization.data(withJSONObject: value)
            send(Data("HTTP/1.1 \(status) Fixture\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body) {
                self.connection.cancel()
            }
        }
        func open() { send(Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)) }
        func close() { connection.cancel() }
        func observeClientClose(_ completion: @escaping () -> Void) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, ended, error in
                if ended || error != nil { completion() }
            }
        }
        func fragments(_ values: [Data], index: Int = 0, done: (() -> Void)? = nil) {
            guard index < values.count else { done?(); return }
            send(values[index]) { self.fragments(values, index: index + 1, done: done) }
        }
    }
    private let queue = DispatchQueue(label: "claw.assistant.test.socket")
    private let listener: NWListener
    private var peers: [NWConnection] = []
    private var handler: ((Request, Reply) -> Void)?
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any)
        let ready = DispatchSemaphore(value: 0)
        var port: UInt16?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: port = self.listener.port?.rawValue; ready.signal()
            case .failed: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self, self.peers.count < 32 else { connection.cancel(); return }
            self.peers.append(connection); connection.start(queue: self.queue)
            self.read(connection, bytes: Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 3) == .success, queue.sync(execute: { port != nil }) else {
            listener.cancel(); throw AssistantFixture.Failure.fixture
        }
        boundPort = port!
    }
    private var boundPort: UInt16 = 0
    var url: URL { URL(string: "http://127.0.0.1:\(boundPort)/")! }
    func install(_ handler: @escaping (Request, Reply) -> Void) { queue.sync { self.handler = handler } }
    func stop() {
        queue.sync {
            listener.stateUpdateHandler = nil; listener.newConnectionHandler = nil
            listener.cancel(); peers.forEach { $0.cancel() }; peers.removeAll(); handler = nil
        }
    }
    private func read(_ peer: NWConnection, bytes: Data) {
        peer.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, end, error in
            guard let self = self, error == nil, let data = data, !data.isEmpty else { peer.cancel(); return }
            let all = bytes + data
            guard all.count <= 80 * 1024 else { peer.cancel(); return }
            if let range = all.range(of: Data("\r\n\r\n".utf8)),
               let header = String(data: all[..<range.lowerBound], encoding: .utf8) {
                let lines = header.components(separatedBy: "\r\n")
                let first = (lines.first ?? "").split(separator: " ")
                guard first.count == 3 else { peer.cancel(); return }
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    if let colon = line.firstIndex(of: ":") {
                        headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    }
                }
                let length = Int(headers["content-length"] ?? "0") ?? -1
                guard length >= 0, length <= 65536 else { peer.cancel(); return }
                let body = all[range.upperBound...]
                if body.count >= length {
                    self.handler?(Request(method: String(first[0]), path: String(first[1]), headers: headers,
                                          body: Data(body.prefix(length))), Reply(peer))
                    return
                }
            }
            if end { peer.cancel() } else { self.read(peer, bytes: all) }
        }
    }
}

/// Fixed fixture categories and counts only; never captures request or response contents.
private final class AssistantRefusalTrace {
    private let lock = NSLock()
    private let started = ProcessInfo.processInfo.systemUptime
    private var rows: [[String: Any]] = []
    private var dropped = 0

    func record(_ stage: String, ordinal: Int, fixture: Int, values: [String: Any] = [:]) {
        lock.lock(); defer { lock.unlock() }
        guard rows.count < 128 else { dropped += 1; return }
        var row = values
        row["stage"] = stage; row["case_ordinal"] = ordinal; row["fixture_case"] = fixture
        row["elapsed_us"] = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000_000)
        rows.append(row)
    }
    func data() throws -> Data {
        lock.lock(); let snapshot = rows; let omitted = dropped; lock.unlock()
        return try JSONSerialization.data(withJSONObject: ["events": snapshot, "dropped": omitted],
                                          options: [.prettyPrinted, .sortedKeys])
    }
    static func sendResult(bytes: Int, error: NWError?) -> [String: Any] {
        var value: [String: Any] = ["bytes": bytes, "success": error == nil]
        if let error = error {
            switch error {
            case .posix(let code): value["error_category"] = "posix"; value["error_code"] = Int(code.rawValue)
            case .dns(let code): value["error_category"] = "dns"; value["error_code"] = Int(code)
            case .tls(let code): value["error_category"] = "tls"; value["error_code"] = Int(code)
            @unknown default: value["error_category"] = "unknown"
            }
        }
        return value
    }
    static func completionKind(_ end: ClawAssistantStreamEnd) -> String {
        switch end {
        case .eof: return "eof"
        case .deadline: return "deadline"
        case .cancelled: return "cancelled"
        case .failure(let error):
            switch error {
            case .invalidResponse: return "failure.invalid_response"
            case .transport: return "failure.transport"
            case .server: return "failure.server"
            case .retired: return "failure.retired"
            case .responseTooLarge: return "failure.response_too_large"
            default: return "failure.other"
            }
        }
    }
}

final class AssistantStreamTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testProductionParserHandlesEveryUTF8BoundaryCRLFMultilineAndHeartbeat() throws {
        let frame = try AssistantBFixture.frame(AssistantBFixture.event("1"), newline: "\r\n")
        var parser = ClawAssistantSSEParser()
        var events: [ClawAssistantRunEvent] = []
        let bytes = Data(": heartbeat\r\n\r\n".utf8) + frame
        for byte in bytes {
            for value in try parser.append(Data([byte])) { if case .event(let value) = value { events.append(value) } }
        }
        XCTAssertEqual(events.count, 1); XCTAssertEqual(events[0].delta, "中文🙂")
        let multi = Data("id: 2\revent: terminal\rdata: {\"id\":\"2\",\"kind\":\"terminal\",\rdata: \"revision\":\"2\",\"state\":\"completed\"}\r\r".utf8)
        let terminal = try parser.append(multi)
        XCTAssertEqual(terminal.count, 1)
        if case .event(let event) = terminal[0] { XCTAssertNil(event.reason); XCTAssertEqual(event.state, "completed") }
        else { XCTFail("Expected persistent terminal") }
        XCTAssertNoThrow(try parser.validateEOF())
    }

    func testMalformedIDsUnknownStatesLargeFramesAndTruncatedUTF8FailClosed() throws {
        let cases = [
            "id: 2\nevent: delta\ndata: {\"id\":\"1\",\"kind\":\"delta\",\"revision\":\"1\",\"delta\":\"a\"}\n\n",
            "id: 9223372036854775808\n\n",
            "id: 1\nevent: terminal\ndata: {\"id\":\"1\",\"kind\":\"terminal\",\"revision\":\"1\",\"state\":\"future\"}\n\n",
            "event: access_error\ndata: {\"code\":\"provider_raw_secret\"}\n\n"
        ]
        for text in cases { var parser = ClawAssistantSSEParser(); XCTAssertThrowsError(try parser.append(Data(text.utf8))) }
        var big = ClawAssistantSSEParser()
        XCTAssertThrowsError(try big.append(Data(repeating: 65, count: ClawAssistantSSEParser.frameLimit + 1)))
        var delta = ClawAssistantSSEParser()
        XCTAssertThrowsError(try delta.append(AssistantBFixture.frame(AssistantBFixture.event("1", text: String(repeating: "a", count: 4097)))))
        var utf8 = ClawAssistantSSEParser()
        XCTAssertThrowsError(try utf8.append(Data([0x64, 0x61, 0x74, 0x61, 0x3A, 0xF0, 0x0A])))
        var partial = ClawAssistantSSEParser()
        XCTAssertNoThrow(try partial.append(Data("data: {".utf8))); XCTAssertThrowsError(try partial.validateEOF())
        XCTAssertTrue(ClawAssistantWire.decimal("9223372036854775807"))
        XCTAssertFalse(ClawAssistantWire.decimal("9223372036854775808"))
        var burst = ClawAssistantSSEParser()
        let frame = try AssistantBFixture.frame(AssistantBFixture.event("1"))
        XCTAssertThrowsError(try burst.append((0..<1025).reduce(into: Data()) { data, _ in data.append(frame) }))
    }

    func testAccessControlHasNoPersistentIDAndDeadlineNeverSlides() throws {
        var parser = ClawAssistantSSEParser()
        let values = try parser.append(Data("event: access_error\ndata: {\"code\":\"authentication_required\"}\n\n".utf8))
        XCTAssertEqual(values.count, 1)
        if case .access(let error) = values[0] { XCTAssertEqual(error, .server(401, "authentication_required")) }
        else { XCTFail("Expected access control") }
        var invalid = ClawAssistantSSEParser()
        XCTAssertThrowsError(try invalid.append(Data("id: 1\nevent: access_error\ndata: {\"code\":\"authentication_required\"}\n\n".utf8)))
        let deadline = ClawAssistantStreamDeadline(now: 100)
        for offset in [0.0, 1.0, 59.999] { XCTAssertFalse(deadline.expired(now: 100 + offset)) }
        XCTAssertTrue(deadline.expired(now: 160)); XCTAssertTrue(deadline.expired(now: 161))
    }

    func testRealSocketChunksProduceEventsBeforeEOFAndStopUsesAnotherConnection() throws {
        let server = try AssistantSocketServer(); defer { server.stop() }
        let gotEvent = expectation(description: "real stream event before EOF")
        gotEvent.assertForOverFulfill = true
        let gotAfterDuplicates = expectation(description: "ordered event after duplicate burst")
        gotAfterDuplicates.assertForOverFulfill = true
        let gotStop = expectation(description: "independent HTTP stop")
        let streamEnd = expectation(description: "cancelled reader")
        let caps = try AssistantBFixture.capabilities()
        let service = try ClawAssistantService(origin: server.url, apiKey: "synthetic-key", token: AssistantFixture.token,
                                               isCurrent: { true })
        defer { service.cancelAll() }
        let frame = try AssistantBFixture.frame(AssistantBFixture.event("3"), newline: "\r\n")
        let afterDuplicates = try AssistantBFixture.frame(AssistantBFixture.event("4", text: "尾"))
        server.install { request, reply in
            XCTAssertEqual(request.headers["authorization"], "token " + AssistantFixture.token)
            XCTAssertEqual(request.headers["x-tinode-apikey"], "synthetic-key")
            XCTAssertNil(request.headers["cookie"])
            if request.path.hasSuffix("/stream") {
                XCTAssertEqual(request.headers["last-event-id"], "2"); XCTAssertFalse(request.path.contains("?"))
                reply.open()
                reply.fragments(frame.map { Data([$0]) }) {
                    reply.send((0..<128).reduce(into: Data()) { data, _ in data.append(frame) } + afterDuplicates)
                } // Duplicate frames must not enqueue duplicate consumer callbacks; leave stream open.
            } else if request.path.hasSuffix("/stop") {
                XCTAssertEqual(request.method, "POST"); XCTAssertTrue(request.body.isEmpty)
                reply.json(AssistantBFixture.snapshot(cursor: "3", revision: "3", state: "stopped"))
            } else { XCTFail("Unexpected fixture route"); reply.json(AssistantFixture.error("not_found"), status: 404) }
        }
        let stream = service.stream(AssistantBFixture.cid, runID: AssistantBFixture.rid, after: "2", capabilities: caps,
            event: { event in
                if event.id == "3" { XCTAssertEqual(event.delta, "中文🙂"); gotEvent.fulfill() }
                else { XCTAssertEqual(event.id, "4"); XCTAssertEqual(event.delta, "尾"); gotAfterDuplicates.fulfill() }
            },
            completion: { end in if case .cancelled = end { streamEnd.fulfill() } else { XCTFail("Expected explicit cancellation") } })
        wait(for: [gotEvent, gotAfterDuplicates], timeout: 5, enforceOrder: true)
        service.run(AssistantBFixture.cid, runID: AssistantBFixture.rid, capabilities: caps, stop: true) { result in
            if case .success(let value) = result { XCTAssertEqual(value.receipt.state, "stopped"); gotStop.fulfill() }
            else { XCTFail("Real control request failed") }
        }
        wait(for: [gotStop], timeout: 5)
        stream?.cancel(); wait(for: [streamEnd], timeout: 3)
    }

    func testRealSocketRedirectAndNonJSON401NeverDeliverBody() throws {
        let trace = AssistantRefusalTrace()
        defer {
            do {
                let attachment = XCTAttachment(data: try trace.data(), uniformTypeIdentifier: "public.json")
                attachment.name = "assistant-stream-refusal-stages"; attachment.lifetime = .keepAlways
                add(attachment)
            } catch { XCTFail("Unable to encode fixed refusal fixture evidence") }
        }
        let server = try AssistantSocketServer(); defer { server.stop() }
        let lock = NSLock(); var redirectedRequests = 0; var mode = 302
        var caseOrdinal = 0; var requestOrdinal = 0
        server.install { request, reply in
            lock.lock(); let status = mode
            let ordinal = caseOrdinal; requestOrdinal += 1; let requestNumber = requestOrdinal
            if request.path == "/redirect-target" { redirectedRequests += 1 }
            lock.unlock()
            trace.record("request_seen", ordinal: ordinal, fixture: status, values: ["request_ordinal": requestNumber])
            reply.sendObservation = { bytes, error in
                var values = AssistantRefusalTrace.sendResult(bytes: bytes, error: error)
                values["request_ordinal"] = requestNumber
                trace.record("send_completion", ordinal: ordinal, fixture: status, values: values)
            }
            if status == 302 {
                let header = "HTTP/1.1 302 Found\r\nLocation: \(server.url.absoluteString)redirect-target\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                reply.send(Data(header.utf8)) { reply.close() }
            } else if status == 1410 {
                reply.json(AssistantFixture.error("conversation_deleted"), status: 410)
            } else if status == 2410 {
                reply.json(AssistantFixture.error("permission_denied"), status: 410)
            } else if status == 3410 {
                reply.send(Data("HTTP/1.1 410 Fixture\r\nContent-Type: application/json\r\nContent-Length: 1\r\nConnection: close\r\n\r\n".utf8) + Data([0xFF])) { reply.close() }
            } else if status == 4410 {
                reply.send(Data("HTTP/1.1 410 Fixture\r\nContent-Type: application/json\r\nContent-Length: 65537\r\nConnection: close\r\n\r\n".utf8))
            } else {
                let actualStatus = status == 410 ? 410 : 401
                reply.send(Data("HTTP/1.1 \(actualStatus) Fixture\r\nContent-Type: text/html\r\nContent-Length: 4\r\nConnection: close\r\n\r\nnope".utf8)) { reply.close() }
            }
        }
        let service = try ClawAssistantService(origin: server.url, apiKey: "synthetic-key", token: AssistantFixture.token, isCurrent: { true })
        defer { service.cancelAll() }
        for (index, status) in [302, 401, 410, 1410, 2410, 3410, 4410].enumerated() {
            let ordinal = index + 1
            try XCTContext.runActivity(named: "refusal case \(ordinal) fixture \(status)") { _ in
                lock.lock(); mode = status; caseOrdinal = ordinal; lock.unlock()
                trace.record("case_started", ordinal: ordinal, fixture: status)
                let done = expectation(description: "real refused response case \(ordinal) fixture \(status)")
                _ = service.stream(AssistantBFixture.cid, runID: AssistantBFixture.rid, after: "0", capabilities: try AssistantBFixture.capabilities(),
                    event: { _ in XCTFail("Refused response leaked a frame") }, completion: { end in
                        trace.record("stream_completion", ordinal: ordinal, fixture: status,
                                     values: ["kind": AssistantRefusalTrace.completionKind(end)])
                        guard case .failure(let error) = end else { XCTFail("Expected refusal"); return }
                        let expected: ClawAssistantError = status == 401 ? .server(401, "authentication_required") :
                            (status == 1410 ? .server(410, "conversation_deleted") : .invalidResponse)
                        XCTAssertEqual(error, expected)
                        done.fulfill()
                    })
                wait(for: [done], timeout: 5)
                trace.record("wait_returned", ordinal: ordinal, fixture: status)
            }
        }
        lock.lock(); let actualRedirects = redirectedRequests; lock.unlock()
        XCTAssertEqual(actualRedirects, 0)
    }

    func testRealSocketOldStopIsRetiredBeforeNewConversationSubmission() throws {
        let server = try AssistantSocketServer(); defer { server.stop() }
        let fixture = try AssistantFixture.main { try AssistantFixture() }
        var model: ClawAssistantRun?
        defer { AssistantFixture.main { model?.retire(); fixture.retire() } }
        try AssistantFixture.main {
            fixture.scope.markRetired(clearAccount: false); fixture.scope.finishRetirement()
            fixture.owner.hostName = "127.0.0.1:\(server.url.port!)"; fixture.owner.useTLS = false
            fixture.scope = try ClawAssistantSession(owner: fixture.owner, generation: 2, origin: server.url,
                gate: { [weak fixture] work in
                    guard let fixture = fixture, fixture.slotActive else { return false }
                    return fixture.owner.withActiveSession { work(); return true } ?? false
                })
            model = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            var stream: AssistantSocketServer.Reply?
            var oldStop: AssistantSocketServer.Reply?
            var newSubmission: AssistantSocketServer.Reply?
            var oldStopClosed = false
            server.install { request, reply in
                DispatchQueue.main.async {
                    if request.path.hasSuffix("/stop") {
                        oldStop = reply
                        reply.observeClientClose { DispatchQueue.main.async { oldStopClosed = true } }
                    } else if request.path.hasSuffix("/stream") { stream = reply; reply.open() }
                    else if request.method == "POST" { newSubmission = reply }
                    else { reply.json(AssistantBFixture.snapshot()) }
                }
            }
            model!.setVisible(true)
            XCTAssertTrue(model!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
            try AssistantFixture.until { stream != nil }
            XCTAssertTrue(model!.stop())
            try AssistantFixture.until { oldStop != nil }
            stream!.send(try AssistantBFixture.frame(AssistantBFixture.event("3", kind: "terminal", state: "completed")))
            try AssistantFixture.until { model?.projection?.terminal == true }
            XCTAssertEqual(model?.stopping, .confirmed)
            XCTAssertTrue(model!.submit(text: "B合成问题", conversationID: AssistantFixture.second))
            model!.setVisible(false) // Pending POST remains; no unrelated B GET is needed for this assertion.
            try AssistantFixture.until { newSubmission != nil && oldStopClosed }
            XCTAssertEqual(model?.submission, .pending); XCTAssertEqual(model?.stopping, .idle)
            XCTAssertNil(model?.projection); XCTAssertNil(model?.receipt)
            // Even a queued old completion is also fenced by operation + all captured run identities.
            oldStop!.json(AssistantBFixture.snapshot(cursor: "3", revision: "3", state: "completed"))
            var value = AssistantBFixture.snapshot(requestID: try XCTUnwrap(model?.ticket?.input.request_id))
            value["conversation_id"] = AssistantFixture.second
            newSubmission!.json(value, status: 202)
            try AssistantFixture.until { model?.submission == .accepted }
            XCTAssertEqual(model?.receipt?.conversation_id, AssistantFixture.second)
            XCTAssertEqual(model?.stopping, .idle)
        }
    }

    func testRealSocketHeartbeatCannotExtendAbsoluteSixtySecondDeadline() throws {
        let server = try AssistantSocketServer(); defer { server.stop() }
        let queue = DispatchQueue(label: "claw.assistant.test.heartbeats")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let lock = NSLock(); var pipe: AssistantSocketServer.Reply?; var comments = 0
        server.install { _, reply in lock.lock(); pipe = reply; lock.unlock(); reply.open() }
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler {
            lock.lock(); let reply = pipe; if reply != nil { comments += 1 }; lock.unlock()
            reply?.send(Data(": synthetic heartbeat\n\n".utf8))
        }
        timer.resume(); defer { timer.cancel() }
        let service = try ClawAssistantService(origin: server.url, apiKey: "synthetic-key", token: AssistantFixture.token, isCurrent: { true })
        defer { service.cancelAll() }
        let done = expectation(description: "absolute stream deadline despite heartbeats")
        let started = ProcessInfo.processInfo.systemUptime
        _ = service.stream(AssistantBFixture.cid, runID: AssistantBFixture.rid, after: "0", capabilities: try AssistantBFixture.capabilities(),
            event: { _ in XCTFail("Heartbeat is not a persistent event") }, completion: { end in
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                guard case .deadline = end else { XCTFail("Expected production absolute deadline"); done.fulfill(); return }
                XCTAssertGreaterThanOrEqual(elapsed, 60); XCTAssertLessThan(elapsed, 64)
                lock.lock(); let count = comments; lock.unlock(); XCTAssertGreaterThan(count, 50)
                let attachment = XCTAttachment(string: "{\"kind\":\"synthetic-loopback-deadline\",\"elapsed\":\(elapsed),\"comments\":\(count)}")
                attachment.name = "assistant-stream-deadline.json"; attachment.lifetime = .keepAlways; self.add(attachment)
                done.fulfill()
            })
        wait(for: [done], timeout: 65)
    }
}
