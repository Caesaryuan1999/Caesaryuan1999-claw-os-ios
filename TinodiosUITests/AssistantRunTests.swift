// Copyright (c) 2026 CLAW OS contributors.
// Actual B service/run/session and real SDK/SQLite. URLProtocol is synthetic transport, not a model provider.
import XCTest
import Foundation
import TinodeSDK
import TinodiosDB
@testable import Tinodios

enum AssistantBFixture {
    static let cid = AssistantFixture.first
    static let rid = AssistantFixture.third
    static let requestID = "00000000-0000-4000-8000-000000000004"
    static let answerID = "00000000-0000-4000-8000-000000000005"
    static func capabilities(generation: Bool = true, stream: Bool = true) throws -> ClawAssistantCapabilities {
        try decode(capabilitiesValue(generation: generation, stream: stream))
    }
    static func capabilitiesValue(generation: Bool = true, stream: Bool = true) -> [String: Any] {
        var value = AssistantFixture.capabilities
        value["generation"] = ["available": generation]
        value["stream"] = ["available": stream]
        value["run_protocol"] = "claw-ai-run-v1"
        value["message_states"] = ["user": ["partial", "interrupted", "completed"],
                                   "assistant": ["partial", "completed", "stopped", "interrupted", "failed"]]
        return value
    }
    static func decode<T: Decodable>(_ value: Any) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
    static func snapshot(text: String = "前缀", cursor: String = "2", revision: String = "2",
                         state: String = "running", requestID: String = AssistantBFixture.requestID) -> [String: Any] {
        ["conversation_id": cid, "run_id": rid, "request_id": requestID,
         "question_message_id": AssistantFixture.second, "answer_message_id": answerID,
         "state": state, "last_event": cursor, "revision": revision,
         "created_at": AssistantFixture.date, "updated_at": AssistantFixture.date, "reason": "", "text": text]
    }
    static func event(_ id: String, kind: String = "delta", text: String = "中文🙂", state: String? = nil) -> [String: Any] {
        var value: [String: Any] = ["id": id, "kind": kind, "revision": id]
        if kind == "delta" { value["delta"] = text }
        if let state = state { value["state"] = state }
        return value
    }
    static func frame(_ value: [String: Any], newline: String = "\n") throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return Data(("id: \(value["id"] as! String)" + newline + "event: \(value["kind"] as! String)" + newline +
                     "data: " + String(data: json, encoding: .utf8)! + newline + newline).utf8)
    }
    static func open(_ transport: AssistantFixtureProtocol) {
        let response = HTTPURLResponse(url: transport.request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream", "Cache-Control": "no-store"])!
        transport.client?.urlProtocol(transport, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while true { let size = stream.read(&buffer, maxLength: buffer.count); if size <= 0 { break }; data.append(contentsOf: buffer.prefix(size)) }
        return data
    }
}

private final class AssistantTestDelay: ClawAssistantCancellation {
    var cancelled = false
    func cancel() { cancelled = true }
}

final class AssistantRunTests: XCTestCase {
    private var fixture: AssistantFixture!
    private var run: ClawAssistantRun?
    override func setUpWithError() throws {
        continueAfterFailure = false
        try AssistantFixture.main { fixture = try AssistantFixture(); AssistantFixtureProtocol.requests = [] }
    }
    override func tearDownWithError() throws {
        AssistantFixture.main {
            run?.retire(); run = nil; fixture?.retire(); fixture = nil; AssistantFixtureProtocol.handler = nil
        }
    }

    func testBRequiresExplicitCapabilitiesAndLegacyPointersStayReadOnly() throws {
        try AssistantFixture.main {
            let a: ClawAssistantCapabilities = try AssistantBFixture.decode(AssistantFixture.capabilities)
            XCTAssertThrowsError(try ClawAssistantRun(session: fixture.scope, capabilities: a))
            var legacy = AssistantBFixture.snapshot(state: "interrupted")
            legacy["legacy"] = true; legacy["question_message_id"] = ""; legacy["answer_message_id"] = ""
            let value: ClawAssistantRunSnapshot = try AssistantBFixture.decode(legacy)
            XCTAssertNoThrow(try value.validate())
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            XCTAssertFalse(run!.retryAnswer(value, history: []))
            legacy["legacy"] = false
            let invalid: ClawAssistantRunSnapshot = try AssistantBFixture.decode(legacy)
            XCTAssertThrowsError(try invalid.validate())
            var aMessage = AssistantFixture.message(state: "completed")
            aMessage["run_id"] = AssistantBFixture.rid
            let old: ClawAssistantMessage = try AssistantBFixture.decode(aMessage)
            XCTAssertThrowsError(try old.validate()) // B does not silently broaden A's history parser.
            var future = AssistantFixture.capabilities
            future["run_protocol"] = ["future": true]; future["message_states"] = "future-shape"
            let stillA: ClawAssistantCapabilities = try AssistantBFixture.decode(future)
            XCTAssertNoThrow(try stillA.validate()); XCTAssertThrowsError(try stillA.validateRuns())
            XCTAssertNoThrow(try ClawAssistantRunInput(request_id: AssistantBFixture.requestID,
                text: String(repeating: "a", count: 32000), retry_of: nil).body())
            XCTAssertThrowsError(try ClawAssistantRunInput(request_id: AssistantBFixture.requestID,
                text: String(repeating: "a", count: 32001), retry_of: nil).body())
            XCTAssertThrowsError(try ClawAssistantRunInput(request_id: AssistantBFixture.requestID,
                text: String(repeating: "\u{0}", count: 11000), retry_of: nil).body()) // Escaped JSON body > 64KiB.
            var events: [String: Any] = ["conversation_id": AssistantBFixture.cid, "run_id": AssistantBFixture.rid,
                "items": [AssistantBFixture.event("2"), AssistantBFixture.event("3")],
                "next_after_event": "", "last_event": "3", "state": "running"]
            let page: ClawAssistantRunEvents = try AssistantBFixture.decode(events)
            XCTAssertNoThrow(try page.validate())
            events["items"] = [AssistantBFixture.event("2"), AssistantBFixture.event("4")]
            let gap: ClawAssistantRunEvents = try AssistantBFixture.decode(events)
            XCTAssertThrowsError(try gap.validate())
            XCTAssertTrue(AssistantFixtureProtocol.requests.isEmpty)
        }
    }

    func testExplicitCreateAndSubmitMatchReceiptsThenGetAuthoritativePrefix() throws {
        try AssistantFixture.main {
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            var cid = ""; var requestID = ""
            fixture.owner.isConnectionAuthenticated = false // Existing valid HTTP scope survives pure WS loss.
            AssistantFixtureProtocol.handler = { transport in
                XCTAssertEqual(transport.request.value(forHTTPHeaderField: "Authorization"), "token " + AssistantFixture.token)
                XCTAssertEqual(transport.request.value(forHTTPHeaderField: "X-Tinode-APIKey"), "synthetic-ai-key")
                if transport.request.url!.path == "/v0/ai/conversations" {
                    let body = try! JSONSerialization.jsonObject(with: AssistantBFixture.body(transport.request)) as! [String: String]
                    cid = body["conversation_id"]!
                    transport.reply(AssistantFixture.conversation(cid), status: 201)
                } else if transport.request.httpMethod == "POST" {
                    let body = try! JSONSerialization.jsonObject(with: AssistantBFixture.body(transport.request)) as! [String: String]
                    XCTAssertEqual(body["text"], " 原文🙂\n"); XCTAssertNil(body["retry_of"])
                    requestID = body["request_id"]!
                    var result = AssistantBFixture.snapshot(requestID: requestID); result["conversation_id"] = cid
                    transport.reply(result, status: 202)
                } else {
                    var result = AssistantBFixture.snapshot(requestID: requestID); result["conversation_id"] = cid
                    transport.reply(result)
                }
            }
            XCTAssertTrue(run!.submit(text: " 原文🙂\n"))
            try AssistantFixture.until { self.run?.submission == .accepted }
            XCTAssertNil(run?.projection) // Hidden page must not auto-start a read after its POST receipt.
            run!.recover()
            try AssistantFixture.until { self.run?.projection != nil }
            XCTAssertEqual(run?.submission, .accepted); XCTAssertEqual(run?.projection?.text, "前缀")
            XCTAssertEqual(run?.projection?.lastEvent, "2")
            XCTAssertEqual(AssistantFixtureProtocol.requests.map { $0.httpMethod! }, ["POST", "POST", "GET"])
            XCTAssertFalse(run!.submit(text: "第二次")) // Active accepted run cannot be overwritten locally.
        }
    }

    func testLostSubmitReceiptRequiresExplicitSameKeyAndOriginalBytes() throws {
        try AssistantFixture.main {
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            var bodies: [Data] = []
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.httpMethod == "POST" {
                    bodies.append(AssistantBFixture.body(transport.request))
                    if bodies.count == 1 { transport.fail(); return }
                    let input = try! JSONSerialization.jsonObject(with: bodies.last!) as! [String: String]
                    transport.reply(AssistantBFixture.snapshot(requestID: input["request_id"]!), status: 200)
                } else {
                    transport.reply(AssistantBFixture.snapshot(requestID: self.run!.ticket!.input.request_id))
                }
            }
            XCTAssertTrue(run!.submit(text: " 保留原字节🙂 ", conversationID: AssistantBFixture.cid))
            try AssistantFixture.until { self.run?.submission == .unknown }
            XCTAssertEqual(bodies.count, 1)
            run!.setVisible(true); run!.setVisible(false)
            XCTAssertEqual(bodies.count, 1)
            XCTAssertTrue(run!.retrySubmission())
            try AssistantFixture.until { self.run?.submission == .accepted }
            run!.recover()
            try AssistantFixture.until { self.run?.projection != nil }
            XCTAssertEqual(bodies.count, 2); XCTAssertEqual(bodies[0], bodies[1])
        }
    }

    func testUnexpectedSuccessAndMismatchedReceiptRemainUnknown() throws {
        try AssistantFixture.main {
            for status in [205, 202] {
                run?.retire()
                run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
                AssistantFixtureProtocol.handler = { $0.reply(AssistantBFixture.snapshot(), status: status) }
                XCTAssertTrue(run!.submit(text: "合成", conversationID: AssistantBFixture.cid))
                try AssistantFixture.until { self.run?.submission == .unknown }
                XCTAssertNil(run?.receipt); XCTAssertNil(run?.projection)
            }
        }
    }

    func testGetPrefixDuplicateEventsGapAndTerminalCannotRegress() throws {
        try AssistantFixture.main {
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            var pipe: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/stream") { pipe = transport; AssistantBFixture.open(transport) }
                else { transport.reply(AssistantBFixture.snapshot()) }
            }
            run!.setVisible(true)
            XCTAssertTrue(run!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
            try AssistantFixture.until { pipe != nil }
            let old = try AssistantBFixture.frame(AssistantBFixture.event("2", text: "绝不能重复前缀"))
            let delta = try AssistantBFixture.frame(AssistantBFixture.event("3", text: "尾"))
            pipe!.client?.urlProtocol(pipe!, didLoad: old + delta + delta)
            try AssistantFixture.until { self.run?.projection?.lastEvent == "3" }
            XCTAssertEqual(run?.projection?.text, "前缀尾")
            let end = try AssistantBFixture.frame(AssistantBFixture.event("4", kind: "terminal", state: "completed"))
            pipe!.client?.urlProtocol(pipe!, didLoad: end)
            try AssistantFixture.until { self.run?.projection?.terminal == true }
            run!.recover() // An older active GET must not replace the known terminal or its text.
            try AssistantFixture.until { self.run?.lastError == .invalidResponse }
            XCTAssertEqual(run?.projection?.state, "completed"); XCTAssertEqual(run?.projection?.text, "前缀尾")
        }
    }

    func testReadFailuresUseBoundedOneTwoFourDelaysWithoutAutomaticPost() throws {
        try AssistantFixture.main {
            var delays: [TimeInterval] = []; var callbacks: [() -> Void] = []
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities(), schedule: { delay, body in
                delays.append(delay); callbacks.append(body); return AssistantTestDelay()
            })
            AssistantFixtureProtocol.handler = { $0.fail() }
            run!.setVisible(true)
            XCTAssertTrue(run!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
            for count in 1...3 {
                try AssistantFixture.until { callbacks.count == count }
                callbacks[count - 1]()
            }
            try AssistantFixture.until { AssistantFixtureProtocol.requests.count == 4 }
            XCTAssertEqual(delays, [1, 2, 4]); XCTAssertEqual(callbacks.count, 3)
            XCTAssertTrue(AssistantFixtureProtocol.requests.allSatisfy { $0.httpMethod == "GET" })
            run!.setVisible(false)
            callbacks[2]()
            XCTAssertEqual(AssistantFixtureProtocol.requests.count, 4)
        }
    }

    func testStopRequestIsIndependentAndUnknownSurvivesAnActiveGet() throws {
        try AssistantFixture.main {
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            var stream: AssistantFixtureProtocol?; var stopRequests = 0; var streams = 0
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/stream") { streams += 1; stream = transport; AssistantBFixture.open(transport) }
                else if transport.request.url!.path.hasSuffix("/stop") {
                    stopRequests += 1; XCTAssertTrue(AssistantBFixture.body(transport.request).isEmpty)
                    XCTAssertNil(transport.request.url!.query)
                    if stopRequests == 1 { transport.fail() }
                    else { transport.reply(AssistantBFixture.snapshot(text: "完成", cursor: "3", revision: "3", state: "completed")) }
                } else { transport.reply(AssistantBFixture.snapshot()) }
            }
            run!.setVisible(true); XCTAssertTrue(run!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
            try AssistantFixture.until { stream != nil }
            XCTAssertTrue(run!.stop())
            try AssistantFixture.until { self.run?.stopping == .unknown }
            run!.recover()
            try AssistantFixture.until { streams == 2 }
            XCTAssertEqual(run?.stopping, .unknown); XCTAssertEqual(stopRequests, 1)
            XCTAssertTrue(run!.stop())
            try AssistantFixture.until { self.run?.stopping == .confirmed }
            XCTAssertEqual(run?.projection?.state, "completed") // Never rename completed to stopped.
            XCTAssertEqual(run?.projection?.text, "完成")
        }
    }

    func testEventsServiceRejectsIncompleteFinalPagesAndImpossibleCursors() throws {
        try AssistantFixture.main {
            let caps = try AssistantBFixture.capabilities()
            let cases: [(String, [String], String, String, Bool)] = [
                ("0", ["1"], "3", "1", true),
                ("0", ["1", "2"], "2", "", true),
                ("2", [], "2", "", true),
                ("0", ["1"], "2", "", false), // Missing terminal page tail.
                ("3", [], "2", "", false), // Requested cursor beyond authoritative last.
                ("0", ["1"], "1", "1", false), // Nonempty next cannot equal last.
                ("0", [], "2", "", false),
                ("0", ["2"], "2", "", false),
                ("0", ["1", "3"], "3", "", false)
            ]
            for (after, ids, last, next, valid) in cases {
                AssistantFixtureProtocol.handler = { transport in
                    XCTAssertEqual(URLComponents(url: transport.request.url!, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "after_event" })?.value, after)
                    transport.reply(["conversation_id": AssistantBFixture.cid, "run_id": AssistantBFixture.rid,
                        "items": ids.map { AssistantBFixture.event($0) }, "last_event": last,
                        "next_after_event": next, "state": "running"])
                }
                var result: Result<ClawAssistantRunEvents, ClawAssistantError>?
                fixture.scope.service.events(AssistantBFixture.cid, runID: AssistantBFixture.rid,
                    after: after, capabilities: caps) { value in DispatchQueue.main.async { result = value } }
                try AssistantFixture.until { result != nil }
                if valid { XCTAssertNoThrow(try result!.get()) }
                else {
                    guard case .failure(.invalidResponse) = result! else { XCTFail("Incomplete event page accepted"); return }
                }
            }
        }
    }

    func testStopReplyMustMatchEveryCapturedRunIdentity() throws {
        try AssistantFixture.main {
            for key in ["conversation_id", "run_id", "request_id", "question_message_id", "answer_message_id", "legacy"] {
                run?.retire()
                run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
                AssistantFixtureProtocol.handler = { transport in
                    if transport.request.httpMethod == "POST" {
                        var value = AssistantBFixture.snapshot(text: "错误回包", cursor: "3", revision: "3", state: "stopped")
                        if key == "legacy" { value[key] = true }
                        else { value[key] = "00000000-0000-4000-8000-000000000009" }
                        transport.reply(value)
                    } else { transport.reply(AssistantBFixture.snapshot()) }
                }
                XCTAssertTrue(run!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
                try AssistantFixture.until { self.run?.projection != nil }
                let original = run?.projection
                XCTAssertTrue(run!.stop())
                try AssistantFixture.until { self.run?.stopping == .unknown }
                XCTAssertEqual(run?.lastError, .invalidResponse)
                XCTAssertEqual(run?.projection, original)
                XCTAssertEqual(run?.receipt, original?.receipt)
            }
        }
    }

    func testSynchronousChangeRetirementCannotCreateSubmitOrStopRequests() throws {
        try AssistantFixture.main {
            for existing in [false, true] {
                run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
                let unexpected = expectation(description: "retired submit must not create HTTP request")
                unexpected.isInverted = true
                AssistantFixtureProtocol.handler = { _ in unexpected.fulfill() }
                AssistantFixtureProtocol.requests = []
                run!.changed = { [weak self] in
                    guard let model = self?.run, model.submission == .pending else { return }
                    model.changed = nil; model.retire()
                }
                _ = run!.submit(text: "合成问题", conversationID: existing ? AssistantBFixture.cid : nil)
                XCTAssertEqual(run?.lastError, .retired); XCTAssertNil(run?.ticket)
                XCTAssertEqual(XCTWaiter.wait(for: [unexpected], timeout: 0.25), .completed)
                XCTAssertTrue(AssistantFixtureProtocol.requests.isEmpty)
            }
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            AssistantFixtureProtocol.handler = { $0.reply(AssistantBFixture.snapshot()) }
            XCTAssertTrue(run!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
            try AssistantFixture.until { self.run?.projection != nil }
            AssistantFixtureProtocol.requests = []
            let unexpected = expectation(description: "retired stop must not create HTTP request")
            unexpected.isInverted = true
            AssistantFixtureProtocol.handler = { _ in unexpected.fulfill() }
            run!.changed = { [weak self] in
                guard let model = self?.run, model.stopping == .pending else { return }
                model.changed = nil; model.retire()
            }
            XCTAssertFalse(run!.stop())
            XCTAssertEqual(run?.lastError, .retired); XCTAssertNil(run?.projection)
            XCTAssertEqual(XCTWaiter.wait(for: [unexpected], timeout: 0.25), .completed)
            XCTAssertTrue(AssistantFixtureProtocol.requests.isEmpty)
        }
    }

    func testOwnerRetirementAndTombstoneRejectDelayedBodies() throws {
        try AssistantFixture.main {
            for deleted in [true, false] {
                run?.retire()
                if !fixture.slotActive { fixture.slotActive = true }
                run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
                var pending: AssistantFixtureProtocol?
                AssistantFixtureProtocol.handler = { pending = $0 }
                XCTAssertTrue(run!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
                try AssistantFixture.until { pending != nil }
                if deleted { XCTAssertTrue(run!.markDeleted(conversationID: AssistantBFixture.cid)) }
                else { fixture.slotActive = false }
                pending!.reply(AssistantBFixture.snapshot(text: "旧正文"))
                if !deleted { try AssistantFixture.until { self.run?.lastError == .retired } }
                XCTAssertNil(run?.projection); XCTAssertNil(run?.ticket)
            }
        }
    }

    func testHTTP401HTMLRetiresOnlyOriginalAssistantScope() throws {
        try AssistantFixture.main {
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            AssistantFixtureProtocol.handler = { $0.replyUnauthorized(contentType: "text/html") }
            XCTAssertTrue(run!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
            try AssistantFixture.until { self.fixture.scope.isBlocked }
            XCTAssertNil(run?.projection); XCTAssertTrue(fixture.owner.isSessionActive)
            XCTAssertEqual(fixture.database.sqlStore?.myUid, "usrSyntheticAssistantA")
        }
    }

    func testRetryUsesOriginalQuestionBytesAndRejectsLegacyStoppedOrLaterQuestion() throws {
        try AssistantFixture.main {
            var source = AssistantBFixture.snapshot(state: "interrupted")
            var rawQuestion = AssistantFixture.message(text: " 原问题🙂 ")
            rawQuestion["role"] = "user"; rawQuestion["run_id"] = AssistantBFixture.rid
            let question: ClawAssistantMessage = try AssistantBFixture.decode(rawQuestion)
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            source["state"] = "stopped"
            XCTAssertFalse(run!.retryAnswer(try AssistantBFixture.decode(source), history: [question]))
            source["state"] = "failed"; source["legacy"] = true
            XCTAssertFalse(run!.retryAnswer(try AssistantBFixture.decode(source), history: [question]))
            source["legacy"] = false
            var later = rawQuestion; later["message_id"] = AssistantBFixture.answerID; later["seq"] = "2"
            XCTAssertFalse(run!.retryAnswer(try AssistantBFixture.decode(source), history: [question, try AssistantBFixture.decode(later)]))
            var input: [String: String]?
            AssistantFixtureProtocol.handler = { transport in
                input = try! JSONSerialization.jsonObject(with: AssistantBFixture.body(transport.request)) as? [String: String]
                transport.reply(AssistantFixture.error("retry_not_allowed"), status: 409)
            }
            XCTAssertTrue(run!.retryAnswer(try AssistantBFixture.decode(source), history: [question]))
            try AssistantFixture.until { input != nil }
            XCTAssertEqual(input?["text"], " 原问题🙂 "); XCTAssertEqual(input?["retry_of"], AssistantBFixture.rid)
            XCTAssertNotEqual(input?["request_id"], AssistantBFixture.requestID)
            try AssistantFixture.until { self.run?.submission == .rejected(.server(409, "retry_not_allowed")) }
        }
    }

    func testProviderUnavailableRejectsNewSubmissionButOriginalKeyReplayCanRead() throws {
        try AssistantFixture.main {
            let disabled = try AssistantBFixture.capabilities(generation: false)
            run = try ClawAssistantRun(session: fixture.scope, capabilities: disabled)
            XCTAssertFalse(run!.submit(text: "草稿", conversationID: AssistantBFixture.cid))
            XCTAssertTrue(AssistantFixtureProtocol.requests.isEmpty)
            AssistantFixtureProtocol.handler = { $0.reply(AssistantBFixture.snapshot(state: "completed")) }
            let input = ClawAssistantRunInput(request_id: AssistantBFixture.requestID, text: "原文", retry_of: nil)
            var restored: ClawAssistantRunReceipt?
            fixture.scope.service.submitRun(AssistantBFixture.cid, input: input, capabilities: disabled, retrySubmission: true) {
                if case .success(let value) = $0 { DispatchQueue.main.async { restored = value } }
            }
            try AssistantFixture.until { restored != nil }
            XCTAssertEqual(restored?.request_id, input.request_id)
        }
    }

    func testGap204AndEOFKeepPrefixAndRecoverByGetBeforeOpeningAnotherReader() throws {
        try AssistantFixture.main {
            var callbacks: [() -> Void] = []; var delays: [TimeInterval] = []
            var pipe: AssistantFixtureProtocol?; var reads = 0; var streams = 0
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities(), schedule: { delay, body in
                delays.append(delay); callbacks.append(body); return AssistantTestDelay()
            })
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/stream") {
                    streams += 1; pipe = transport
                    if streams == 2 {
                        let response = HTTPURLResponse(url: transport.request.url!, statusCode: 204,
                            httpVersion: "HTTP/1.1", headerFields: nil)!
                        transport.client?.urlProtocol(transport, didReceive: response, cacheStoragePolicy: .notAllowed)
                        transport.client?.urlProtocolDidFinishLoading(transport)
                    } else {
                        AssistantBFixture.open(transport)
                        if streams == 3 { transport.client?.urlProtocolDidFinishLoading(transport) }
                    }
                } else { reads += 1; transport.reply(AssistantBFixture.snapshot()) }
            }
            run!.setVisible(true)
            XCTAssertTrue(run!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
            try AssistantFixture.until { pipe != nil }
            pipe!.client?.urlProtocol(pipe!, didLoad: try AssistantBFixture.frame(AssistantBFixture.event("4", text: "不能越过3")))
            try AssistantFixture.until { callbacks.count == 1 }
            XCTAssertEqual(run?.projection?.text, "前缀"); XCTAssertEqual(run?.projection?.lastEvent, "2")
            callbacks[0]()
            try AssistantFixture.until { callbacks.count == 2 }
            XCTAssertEqual(reads, 2); XCTAssertEqual(run?.projection?.state, "running")
            callbacks[1]()
            try AssistantFixture.until { callbacks.count == 3 }
            XCTAssertEqual(reads, 3); XCTAssertEqual(delays, [1, 2, 4])
            XCTAssertEqual(run?.projection?.text, "前缀"); XCTAssertFalse(run?.projection?.terminal ?? true)
            XCTAssertTrue(AssistantFixtureProtocol.requests.allSatisfy { $0.httpMethod == "GET" })
            run!.setVisible(false); callbacks[2]()
            XCTAssertEqual(reads, 3)
        }
    }

    func testManualCapabilityRecheckKeepsPrefixWhenStreamBecomesUnavailable() throws {
        try AssistantFixture.main {
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            var enabled = true; var streams = 0; var capReads = 0
            AssistantFixtureProtocol.handler = { transport in
                let path = transport.request.url!.path
                if path.hasSuffix("/capabilities") {
                    capReads += 1; transport.reply(AssistantBFixture.capabilitiesValue(stream: enabled))
                } else if path.hasSuffix("/stream") { streams += 1; AssistantBFixture.open(transport) }
                else { transport.reply(AssistantBFixture.snapshot()) }
            }
            run!.setVisible(true)
            XCTAssertTrue(run!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
            try AssistantFixture.until { streams == 1 }
            enabled = false; run!.renegotiateAndRecover()
            try AssistantFixture.until { self.run?.lastError == .server(503, "history_unavailable") }
            XCTAssertEqual(run?.projection?.text, "前缀"); XCTAssertEqual(run?.projection?.state, "running")
            XCTAssertEqual(streams, 1); XCTAssertEqual(capReads, 1)
            enabled = true; run!.renegotiateAndRecover()
            try AssistantFixture.until { streams == 2 }
            XCTAssertEqual(capReads, 2); XCTAssertNil(run?.lastError)
            XCTAssertTrue(AssistantFixtureProtocol.requests.allSatisfy { $0.httpMethod == "GET" })
        }
    }

    func testConversationSwitchDropsOldPrefixAndForeignTombstoneCannotClearNewTicket() throws {
        try AssistantFixture.main {
            run = try ClawAssistantRun(session: fixture.scope, capabilities: AssistantBFixture.capabilities())
            var pending: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.httpMethod == "POST" { pending = transport }
                else { transport.reply(AssistantBFixture.snapshot(text: "A旧正文", state: "completed")) }
            }
            XCTAssertTrue(run!.recover(conversationID: AssistantBFixture.cid, runID: AssistantBFixture.rid))
            try AssistantFixture.until { self.run?.projection?.terminal == true }
            XCTAssertFalse(run!.recover(conversationID: AssistantFixture.second, runID: AssistantBFixture.rid))
            XCTAssertTrue(run!.submit(text: "B原问题", conversationID: AssistantFixture.second))
            try AssistantFixture.until { pending != nil }
            XCTAssertNil(run?.projection); XCTAssertNil(run?.receipt)
            XCTAssertEqual(run?.ticket?.conversationID, AssistantFixture.second)
            XCTAssertFalse(run!.markDeleted(conversationID: AssistantBFixture.cid))
            XCTAssertEqual(run?.ticket?.input.text, "B原问题")
            let requestID = try XCTUnwrap(run?.ticket?.input.request_id)
            XCTAssertTrue(run!.markDeleted(conversationID: AssistantFixture.second))
            var late = AssistantBFixture.snapshot(requestID: requestID)
            late["conversation_id"] = AssistantFixture.second
            pending!.reply(late, status: 202)
            XCTAssertNil(run?.ticket); XCTAssertNil(run?.projection); XCTAssertNil(run?.receipt)
        }
    }
}
