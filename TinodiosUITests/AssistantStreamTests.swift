// Copyright (c) 2026 CLAW OS contributors.
import XCTest
import Foundation
import Network
@testable import Tinodios

/// Loopback-only real TCP fixture. No configured server, model or credential is contacted.
private final class AssistantSocketServer {
    struct Request { let method: String; let path: String; let headers: [String: String]; let body: Data }
    final class Reply {
        let connection: NWConnection
        init(_ connection: NWConnection) { self.connection = connection }
        func send(_ data: Data, completion: (() -> Void)? = nil) {
            connection.send(content: data, completion: .contentProcessed { _ in completion?() })
        }
        func json(_ value: Any, status: Int = 200) {
            let body = try! JSONSerialization.data(withJSONObject: value)
            send(Data("HTTP/1.1 \(status) Fixture\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body) {
                self.connection.cancel()
            }
        }
        func open() { send(Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)) }
        func close() { connection.cancel() }
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
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 3) == .success, queue.sync(execute: { port != nil }) else {
            listener.cancel(); throw AssistantFixture.Failure.fixture
        }
        boundPort = port!
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self, self.peers.count < 32 else { connection.cancel(); return }
            self.peers.append(connection); connection.start(queue: self.queue)
            self.read(connection, bytes: Data())
        }
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
        let gotStop = expectation(description: "independent HTTP stop")
        let streamEnd = expectation(description: "cancelled reader")
        let caps = try AssistantBFixture.capabilities()
        let service = try ClawAssistantService(origin: server.url, apiKey: "synthetic-key", token: AssistantFixture.token,
                                               isCurrent: { true })
        defer { service.cancelAll() }
        let frame = try AssistantBFixture.frame(AssistantBFixture.event("3"), newline: "\r\n")
        server.install { request, reply in
            XCTAssertEqual(request.headers["authorization"], "token " + AssistantFixture.token)
            XCTAssertEqual(request.headers["x-tinode-apikey"], "synthetic-key")
            XCTAssertNil(request.headers["cookie"])
            if request.path.hasSuffix("/stream") {
                XCTAssertEqual(request.headers["last-event-id"], "2"); XCTAssertFalse(request.path.contains("?"))
                reply.open(); reply.fragments(frame.map { Data([$0]) }) // Deliberately leave connection open.
            } else if request.path.hasSuffix("/stop") {
                XCTAssertEqual(request.method, "POST"); XCTAssertTrue(request.body.isEmpty)
                reply.json(AssistantBFixture.snapshot(cursor: "3", revision: "3", state: "stopped"))
            } else { XCTFail("Unexpected fixture route"); reply.json(AssistantFixture.error("not_found"), status: 404) }
        }
        let stream = service.stream(AssistantBFixture.cid, runID: AssistantBFixture.rid, after: "2", capabilities: caps,
            event: { event in XCTAssertEqual(event.delta, "中文🙂"); gotEvent.fulfill() },
            completion: { end in if case .cancelled = end { streamEnd.fulfill() } else { XCTFail("Expected explicit cancellation") } })
        wait(for: [gotEvent], timeout: 5)
        service.run(AssistantBFixture.cid, runID: AssistantBFixture.rid, capabilities: caps, stop: true) { result in
            if case .success(let value) = result { XCTAssertEqual(value.receipt.state, "stopped"); gotStop.fulfill() }
            else { XCTFail("Real control request failed") }
        }
        wait(for: [gotStop], timeout: 5)
        stream?.cancel(); wait(for: [streamEnd], timeout: 3)
    }

    func testRealSocketRedirectAndNonJSON401NeverDeliverBody() throws {
        let server = try AssistantSocketServer(); defer { server.stop() }
        let lock = NSLock(); var redirectedRequests = 0; var mode = 302
        server.install { request, reply in
            lock.lock(); let status = mode
            if request.path == "/redirect-target" { redirectedRequests += 1 }
            lock.unlock()
            if status == 302 {
                let header = "HTTP/1.1 302 Found\r\nLocation: \(server.url.absoluteString)redirect-target\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                reply.send(Data(header.utf8)) { reply.close() }
            } else {
                reply.send(Data("HTTP/1.1 401 Unauthorized\r\nContent-Type: text/html\r\nContent-Length: 4\r\nConnection: close\r\n\r\nnope".utf8)) { reply.close() }
            }
        }
        let service = try ClawAssistantService(origin: server.url, apiKey: "synthetic-key", token: AssistantFixture.token, isCurrent: { true })
        defer { service.cancelAll() }
        for status in [302, 401] {
            lock.lock(); mode = status; lock.unlock()
            let done = expectation(description: "real refused response")
            _ = service.stream(AssistantBFixture.cid, runID: AssistantBFixture.rid, after: "0", capabilities: try AssistantBFixture.capabilities(),
                event: { _ in XCTFail("Refused response leaked a frame") }, completion: { end in
                    guard case .failure(let error) = end else { XCTFail("Expected refusal"); return }
                    XCTAssertEqual(error, status == 401 ? .server(401, "authentication_required") : .invalidResponse)
                    done.fulfill()
                })
            wait(for: [done], timeout: 5)
        }
        lock.lock(); let actualRedirects = redirectedRequests; lock.unlock()
        XCTAssertEqual(actualRedirects, 0)
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
