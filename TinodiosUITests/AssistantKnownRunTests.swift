// Copyright (c) 2026 CLAW OS contributors.
// Actual Session/History/Run/URLSession with real isolated SDK/SQLite.
// Existing internal fixtures control URLProtocol transport, not TCP or a model provider.
import XCTest
import Foundation
import TinodeSDK
@testable import Tinodios

final class AssistantKnownRunTests: XCTestCase {
    private var fixture: AssistantFixture!
    private let cid = AssistantBFixture.cid
    private let rid = AssistantBFixture.rid
    private let otherCID = "00000000-0000-4000-8000-000000000020"
    private let otherRID = "00000000-0000-4000-8000-000000000021"
    override func setUpWithError() throws {
        continueAfterFailure = false
        try AssistantFixture.main {
            AssistantFixtureProtocol.requests = []
            fixture = try AssistantFixture()
        }
    }
    override func tearDownWithError() throws {
        AssistantFixture.main { fixture?.retire(); fixture = nil; AssistantFixtureProtocol.handler = nil }
    }
    private func prepare(stream: Bool = false) throws {
        AssistantFixtureProtocol.handler = { $0.reply(AssistantBFixture.capabilitiesValue(stream: stream)) }
        fixture.scope.history.loadCapabilities()
        try AssistantFixture.until { !self.fixture.scope.history.capabilityLoading }
        XCTAssertNotNil(fixture.scope.history.capabilities)
        AssistantFixtureProtocol.requests = []
    }
    private func row(_ seq: Int, role: String = "assistant", text: String = "已保存正文",
                     state: String = "partial", run: String? = nil, id: String? = nil) -> [String: Any] {
        ["message_id": id ?? String(format: "00000000-0000-4000-8000-%012d", seq + 100),
         "conversation_id": cid, "run_id": run ?? rid, "seq": String(seq), "role": role,
         "state": state, "text": text, "created_at": AssistantFixture.date, "updated_at": AssistantFixture.date]
    }
    private func pair(text: String = "已保存正文", state: String = "partial") -> [[String: Any]] {
        [row(1, role: "user", text: "原问题", state: "completed", run: otherRID, id: AssistantFixture.second),
         row(2, text: text, state: state, id: AssistantBFixture.answerID)]
    }
    private func page(_ rows: [[String: Any]], revision: String = "2", next: String = "") -> [String: Any] {
        AssistantFixture.messages(rows, revision: revision, next: next)
    }
    private func load() throws {
        fixture.scope.history.loadMessages(cid)
        try AssistantFixture.until { !self.fixture.scope.history.detailLoading.contains(self.cid) }
    }
    private func open(_ response: [String: Any]? = nil, historyRevision: String = "2") throws -> UUID {
        let snapshot = response ?? AssistantBFixture.snapshot()
        AssistantFixtureProtocol.handler = { transport in
            if transport.request.url!.path.hasSuffix("/messages") {
                transport.reply(self.page(self.pair(), revision: historyRevision))
            } else { transport.reply(snapshot) }
        }
        let lease = UUID()
        XCTAssertTrue(fixture.scope.acquireReader(conversationID: cid, lease: lease))
        try load()
        try AssistantFixture.until { self.fixture.scope.knownRun?.projection != nil }
        return lease
    }

    func testExplicitBServiceRoleByteBoundariesAndMaximumEscapedPage() throws {
        try AssistantFixture.main {
            try prepare()
            let capabilities = try XCTUnwrap(fixture.scope.history.capabilities)
            let cases: [(String, String, Bool)] = [
                ("user", String(repeating: "a", count: 32000), true),
                ("user", String(repeating: "a", count: 32001), false),
                ("user", String(repeating: "🙂", count: 8000), true),
                ("user", String(repeating: "🙂", count: 8000) + "a", false),
                ("assistant", String(repeating: "a", count: 262144), true),
                ("assistant", String(repeating: "a", count: 262145), false),
                ("assistant", String(repeating: "🙂", count: 65536), true),
                ("assistant", String(repeating: "🙂", count: 65536) + "a", false)]
            for (role, text, accepted) in cases {
                var result: Result<ClawAssistantBMessagePage, ClawAssistantError>?
                AssistantFixtureProtocol.handler = { $0.reply(self.page([self.row(1, role: role, text: text)])) }
                fixture.scope.service.messagesB(cid, capabilities: capabilities) { result = $0 }
                try AssistantFixture.until { result != nil }
                if accepted { XCTAssertEqual(try result!.get().items.first?.text, text) }
                else { XCTAssertThrowsError(try result!.get()) }
            }
            let largest = (1...10).map { row($0, text: String(repeating: "\u{0}", count: 262144)) }
            let raw = try JSONSerialization.data(withJSONObject: page(largest))
            XCTAssertGreaterThan(raw.count, 15 * 1024 * 1024)
            XCTAssertLessThan(raw.count, ClawAssistantService.responseLimit)
            AssistantFixtureProtocol.handler = { $0.reply(self.page(largest)) }
            try load()
            XCTAssertEqual(fixture.scope.history.bDetails[cid]?.count, 10)
            XCTAssertEqual(fixture.scope.history.bDetails[cid]?.last?.text.utf8.count, 262144)
            for request in AssistantFixtureProtocol.requests {
                XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first {
                    $0.name == "limit"
                }?.value, "10")
            }
            var called = false
            let a: ClawAssistantCapabilities = try AssistantBFixture.decode(AssistantFixture.capabilities)
            let count = AssistantFixtureProtocol.requests.count
            fixture.scope.service.messagesB(cid, capabilities: a) { result in
                called = true; XCTAssertThrowsError(try result.get())
            }
            XCTAssertTrue(called); XCTAssertEqual(AssistantFixtureProtocol.requests.count, count)
        }
    }

    func testAllPagesStageAtomicallyRejectDuplicatesAndBoundSnapshotRestarts() throws {
        try AssistantFixture.main {
            try prepare()
            AssistantFixtureProtocol.handler = { $0.reply(self.page(self.pair(text: "旧完整快照"))) }
            try load()
            let old = try XCTUnwrap(fixture.scope.history.bDetails[cid])
            var second: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = { transport in
                let after = URLComponents(url: transport.request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first {
                    $0.name == "after_seq"
                }?.value
                if after == "0" { transport.reply(self.page([self.row(1)], revision: "3", next: "1")) }
                else { second = transport }
            }
            fixture.scope.history.loadMessages(cid)
            try AssistantFixture.until { second != nil }
            XCTAssertEqual(fixture.scope.history.bDetails[cid], old)
            XCTAssertTrue(fixture.scope.history.detailLoading.contains(cid))
            second!.reply(page([row(2)], revision: "3"))
            try AssistantFixture.until { !self.fixture.scope.history.detailLoading.contains(self.cid) }
            XCTAssertEqual(fixture.scope.history.bDetails[cid]?.map { $0.seq }, ["1", "2"])
            let complete = fixture.scope.history.bDetails[cid]
            second = nil
            fixture.scope.history.loadMessages(cid)
            try AssistantFixture.until { second != nil }
            second!.reply(page([row(2, id: row(1)["message_id"] as? String)], revision: "3"))
            try AssistantFixture.until { !self.fixture.scope.history.detailLoading.contains(self.cid) }
            XCTAssertEqual(fixture.scope.history.detailErrors[cid], .invalidResponse)
            XCTAssertEqual(fixture.scope.history.bDetails[cid], complete)
            var restarts = 0
            AssistantFixtureProtocol.handler = { transport in
                restarts += 1; transport.reply(AssistantFixture.error("snapshot_changed"), status: 409)
            }
            try load()
            XCTAssertEqual(restarts, 3); XCTAssertEqual(fixture.scope.history.detailErrors[cid], .historyChanged)
            XCTAssertEqual(fixture.scope.history.bDetails[cid], complete)
            AssistantFixtureProtocol.handler = { $0.reply(self.page([self.row(1, state: "future")])) }
            try load()
            XCTAssertEqual(fixture.scope.history.detailErrors[cid], .incompatible)
            XCTAssertEqual(fixture.scope.history.bDetails[cid], complete)
        }
    }

    func testLatestRealRunReusesEarlierQuestionAndHardRejectsAllGenerationEntrypoints() throws {
        try AssistantFixture.main {
            try prepare()
            _ = try open()
            let run = try XCTUnwrap(fixture.scope.knownRun)
            XCTAssertEqual(run.projection?.text, "前缀")
            XCTAssertEqual(fixture.scope.knownAddress?.runID, rid)
            XCTAssertEqual(AssistantFixtureProtocol.requests.filter { $0.url!.path.contains("/runs/") }.count, 1)
            var notifications = 0; run.changed = { notifications += 1 }
            let count = AssistantFixtureProtocol.requests.count
            XCTAssertFalse(run.submit(text: "不应发送"))
            XCTAssertFalse(run.retrySubmission())
            let previous: ClawAssistantRunSnapshot = try AssistantBFixture.decode(AssistantBFixture.snapshot(state: "interrupted"))
            XCTAssertFalse(run.retryAnswer(previous, history: []))
            XCTAssertEqual(notifications, 0); XCTAssertEqual(AssistantFixtureProtocol.requests.count, count)
            XCTAssertFalse(AssistantFixtureProtocol.requests.contains { $0.httpMethod == "POST" })
            XCTAssertEqual(fixture.scope.messageRows(cid).map { $0.id }, [AssistantFixture.second, AssistantBFixture.answerID])
        }
    }

    func testAccountGlobalRevisionDoesNotRequireOldTerminalOverlayAndAlignmentIsFinite() throws {
        try AssistantFixture.main {
            try prepare()
            _ = try open(AssistantBFixture.snapshot(text: "旧run正文", state: "completed"), historyRevision: "50")
            XCTAssertEqual(fixture.scope.messageRows(cid).last?.text, "已保存正文")
            XCTAssertEqual(AssistantFixtureProtocol.requests.filter { $0.url!.path.hasSuffix("/messages") }.count, 1)
            // This run later has a newer authoritative terminal than its history row.
            fixture.scope.releaseReader(lease: UUID()) // Wrong lease has no effect.
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/capabilities") {
                    transport.reply(AssistantBFixture.capabilitiesValue(stream: false))
                } else if transport.request.url!.path.hasSuffix("/messages") {
                    transport.reply(self.page(self.pair(text: "仍旧快照"), revision: "1"))
                } else { transport.reply(AssistantBFixture.snapshot(text: "旧run正文", state: "completed")) }
            }
            try load()
            XCTAssertEqual(fixture.scope.messageRows(cid).last?.text, "旧run正文")
            XCTAssertEqual(fixture.scope.messageRows(cid).count, 2)
        }
    }

    func testReaderLeaseHandoverAndStopUnknownSurviveLeavingAndBlockAnotherConversation() throws {
        try AssistantFixture.main {
            try prepare()
            let firstLease = try open()
            let run = try XCTUnwrap(fixture.scope.knownRun)
            fixture.owner.isConnectionAuthenticated = false // Pure WS loss preserves the established HTTP scope.
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.httpMethod == "POST" { transport.fail() }
                else if transport.request.url!.path.hasSuffix("/capabilities") {
                    transport.reply(AssistantBFixture.capabilitiesValue(stream: false))
                } else { transport.reply(AssistantBFixture.snapshot()) }
            }
            XCTAssertTrue(fixture.scope.stopKnownRun(conversationID: cid, lease: firstLease))
            fixture.scope.releaseReader(lease: firstLease)
            try AssistantFixture.until { run.stopping == .unknown }
            XCTAssertEqual(fixture.scope.blockingStop(for: otherCID)?.conversationID, cid)
            XCTAssertFalse(fixture.scope.acquireReader(conversationID: otherCID, lease: UUID()))
            XCTAssertEqual(fixture.scope.selectedConversationID, cid)
            let secondLease = UUID()
            XCTAssertTrue(fixture.scope.acquireReader(conversationID: cid, lease: secondLease))
            fixture.scope.releaseReader(lease: firstLease)
            XCTAssertTrue(fixture.scope.recoverKnownRun(conversationID: cid, lease: secondLease))
            try AssistantFixture.until { AssistantFixtureProtocol.requests.filter { $0.httpMethod == "GET" }.count >= 3 }
            XCTAssertEqual(run.stopping, .unknown)
            XCTAssertEqual(AssistantFixtureProtocol.requests.filter { $0.httpMethod == "POST" }.count, 1)
            XCTAssertFalse(fixture.scope.stopKnownRun(conversationID: cid, lease: firstLease))
        }
    }

    func testLateStopCannotOverwriteReplacementRunAndCompletedIsNotStopped() throws {
        try AssistantFixture.main {
            try prepare()
            let lease = try open()
            let old = try XCTUnwrap(fixture.scope.knownRun)
            var held: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.httpMethod == "POST" { held = transport }
                else if transport.request.url!.path.hasSuffix("/capabilities") {
                    transport.reply(AssistantBFixture.capabilitiesValue(stream: false))
                } else { transport.reply(AssistantBFixture.snapshot(text: "完成", cursor: "3", revision: "3", state: "completed")) }
            }
            XCTAssertTrue(fixture.scope.stopKnownRun(conversationID: cid, lease: lease))
            try AssistantFixture.until { held != nil }
            // Avoid terminal-history alignment introducing an unrelated held transport in this case.
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/capabilities") { transport.reply(AssistantBFixture.capabilitiesValue(stream: false)) }
                else if transport.request.url!.path.hasSuffix("/messages") { transport.reply(self.page(self.pair(text: "完成", state: "completed"), revision: "3")) }
                else { transport.reply(AssistantBFixture.snapshot(text: "完成", cursor: "3", revision: "3", state: "completed")) }
            }
            XCTAssertTrue(fixture.scope.recoverKnownRun(conversationID: cid, lease: lease))
            try AssistantFixture.until { old.stopping == .confirmed }
            XCTAssertEqual(old.projection?.state, "completed")
            XCTAssertTrue(fixture.scope.acquireReader(conversationID: otherCID, lease: UUID()))
            XCTAssertNil(fixture.scope.knownRun)
            held!.reply(AssistantBFixture.snapshot(text: "晚停止", cursor: "4", revision: "4", state: "stopped"))
            XCTAssertEqual(fixture.scope.selectedConversationID, otherCID)
            XCTAssertNil(fixture.scope.knownRun); XCTAssertNil(old.projection)
        }
    }

    func testDeletionPausesCurrentReaderAndTombstoneOfOtherConversationDoesNotClearIt() throws {
        try AssistantFixture.main {
            try prepare()
            let lease = try open()
            let run = try XCTUnwrap(fixture.scope.knownRun)
            fixture.scope.history.acceptKnownRunTombstone(otherCID)
            XCTAssertTrue(fixture.scope.knownRun === run)
            var held: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = { held = $0 }
            fixture.scope.history.deleteConversation(cid)
            try AssistantFixture.until { held != nil }
            XCTAssertFalse(fixture.scope.stopKnownRun(conversationID: cid, lease: lease))
            XCTAssertFalse(fixture.scope.recoverKnownRun(conversationID: cid, lease: lease))
            held!.fail()
            try AssistantFixture.until { self.fixture.scope.history.deletions[self.cid] == .unknown }
            XCTAssertNotNil(run.projection)
            fixture.scope.history.acceptKnownRunTombstone(cid)
            XCTAssertNil(fixture.scope.knownRun); XCTAssertNil(run.projection)
            XCTAssertTrue(fixture.scope.messageRows(cid).isEmpty)
            XCTAssertTrue(fixture.scope.history.bDetails.isEmpty)
        }
    }

    func testMissingBindingRereadsOnceInvalidIdentityRejectsAndLegacyStaysHistoryOnly() throws {
        try AssistantFixture.main {
            try prepare()
            var historyReads = 0; var runReads = 0
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/messages") {
                    historyReads += 1; transport.reply(self.page([self.pair()[1]]))
                } else { runReads += 1; transport.reply(AssistantBFixture.snapshot()) }
            }
            XCTAssertTrue(fixture.scope.acquireReader(conversationID: cid, lease: UUID()))
            try load()
            try AssistantFixture.until { runReads == 2 && self.fixture.scope.knownRun?.lastError == .historyChanged }
            XCTAssertEqual(historyReads, 2); XCTAssertNil(fixture.scope.knownRun?.projection)
            var wrongAnswer = pair()[1]; wrongAnswer["role"] = "user"
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/messages") { transport.reply(self.page([self.pair()[0], wrongAnswer])) }
                else { transport.reply(AssistantBFixture.snapshot()) }
            }
            try load()
            try AssistantFixture.until { self.fixture.scope.knownRun?.lastError == .invalidResponse }
            XCTAssertNil(fixture.scope.knownRun?.projection)
            var legacy = AssistantBFixture.snapshot(state: "interrupted")
            legacy["legacy"] = true; legacy["question_message_id"] = ""; legacy["answer_message_id"] = ""
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/messages") { transport.reply(self.page([self.pair()[1]])) }
                else { transport.reply(legacy) }
            }
            try load()
            fixture.scope.knownRun!.recover() // Explicit existing-rid read; never creates an answer.
            try AssistantFixture.until { self.fixture.scope.knownRun?.projection?.receipt.isLegacy == true }
            XCTAssertFalse(fixture.scope.knownRun!.stop())
            XCTAssertEqual(fixture.scope.messageRows(cid).last?.text, "已保存正文")
        }
    }

    func testStreamPrefixUpdatesExistingAnswerAndReconnectNeverDoubleAppends() throws {
        try AssistantFixture.main {
            try prepare(stream: true)
            var stream: AssistantFixtureProtocol?
            var latest = AssistantBFixture.snapshot()
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/messages") { transport.reply(self.page(self.pair())) }
                else if transport.request.url!.path.hasSuffix("/stream") { stream = transport; AssistantBFixture.open(transport) }
                else { transport.reply(latest) }
            }
            let lease = UUID()
            XCTAssertTrue(fixture.scope.acquireReader(conversationID: cid, lease: lease))
            try load()
            try AssistantFixture.until { stream != nil }
            stream!.client?.urlProtocol(stream!, didLoad: try AssistantBFixture.frame(AssistantBFixture.event("3", text: "增量")))
            try AssistantFixture.until { self.fixture.scope.messageRows(self.cid).last?.text == "前缀增量" }
            latest = AssistantBFixture.snapshot(text: "前缀增量", cursor: "3", revision: "3")
            fixture.scope.releaseReader(lease: lease); stream = nil
            XCTAssertTrue(fixture.scope.acquireReader(conversationID: cid, lease: UUID()))
            try AssistantFixture.until { stream != nil }
            XCTAssertEqual(fixture.scope.messageRows(cid).last?.text, "前缀增量")
            XCTAssertEqual(fixture.scope.messageRows(cid).count, 2)
        }
    }

    func test401AndSynchronousRetirementHideKnownContentWithoutLogoutOrNewRequest() throws {
        try AssistantFixture.main {
            try prepare()
            let lease = try open()
            fixture.scope.updateDraft("仅内存草稿")
            AssistantFixtureProtocol.handler = { $0.replyUnauthorized(contentType: "text/html") }
            XCTAssertTrue(fixture.scope.recoverKnownRun(conversationID: cid, lease: lease))
            try AssistantFixture.until { self.fixture.scope.isBlocked }
            XCTAssertNil(fixture.scope.knownRun); XCTAssertTrue(fixture.scope.messageRows(cid).isEmpty)
            XCTAssertEqual(fixture.scope.draft, "")
            XCTAssertTrue(fixture.owner.isSessionActive); XCTAssertEqual(fixture.owner.store?.myUid, "usrSyntheticAssistantA")
            fixture.scope = try fixture.newScope(generation: 2)
            try prepare()
            _ = try open()
            let observation = NotificationCenter.default.addObserver(forName: ClawAssistantSession.knownRunChanged,
                object: nil, queue: .main) { [weak self] notification in
                    guard let self = self, notification.object as? ClawAssistantSession === self.fixture.scope else { return }
                    self.fixture.scope.markRetired(clearAccount: true)
                }
            defer { NotificationCenter.default.removeObserver(observation) }
            let count = AssistantFixtureProtocol.requests.count
            XCTAssertFalse(fixture.scope.knownRun!.stop()) // pending notify retires before POST construction.
            XCTAssertEqual(AssistantFixtureProtocol.requests.count, count)
            fixture.scope.finishRetirement()
            XCTAssertNil(fixture.scope.knownRun)
        }
    }

    func testNewHistoryTokenWaitsForUnknownStopThenBindsLatestRealRun() throws {
        try AssistantFixture.main {
            try prepare()
            let lease = try open()
            let old = try XCTUnwrap(fixture.scope.knownRun)
            AssistantFixtureProtocol.handler = { $0.fail() }
            XCTAssertTrue(fixture.scope.stopKnownRun(conversationID: cid, lease: lease))
            try AssistantFixture.until { old.stopping == .unknown }
            let newAnswer = "00000000-0000-4000-8000-000000000022"
            let rows = pair() + [row(3, text: "另一已存回答", run: otherRID, id: newAnswer)]
            var held: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/messages") {
                    transport.reply(self.page(rows, revision: "5"))
                } else if transport.request.httpMethod == "POST" { held = transport }
                else {
                    var snapshot = AssistantBFixture.snapshot(text: "最新run", revision: "5")
                    snapshot["run_id"] = self.otherRID; snapshot["answer_message_id"] = newAnswer
                    transport.reply(snapshot)
                }
            }
            try load()
            XCTAssertEqual(fixture.scope.knownAddress?.runID, rid)
            XCTAssertEqual(old.stopping, .unknown)
            XCTAssertTrue(fixture.scope.stopKnownRun(conversationID: cid, lease: lease))
            try AssistantFixture.until { held != nil }
            held!.reply(AssistantBFixture.snapshot(text: "原回答完成", cursor: "3", revision: "3", state: "completed"))
            try AssistantFixture.until { self.fixture.scope.knownRun?.projection?.text == "最新run" }
            XCTAssertEqual(fixture.scope.knownAddress?.runID, otherRID)
            XCTAssertEqual(fixture.scope.messageRows(cid).last?.id, newAnswer)
            XCTAssertEqual(AssistantFixtureProtocol.requests.filter { $0.url!.path.hasSuffix("/" + self.otherRID) }.count, 1)
        }
    }

    func testCapabilityDowngradePausesReadAndStopButManualNegotiationPreservesUnknown() throws {
        try AssistantFixture.main {
            try prepare(stream: true)
            var stream: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/messages") { transport.reply(self.page(self.pair())) }
                else if transport.request.url!.path.hasSuffix("/stream") { stream = transport; AssistantBFixture.open(transport) }
                else { transport.reply(AssistantBFixture.snapshot()) }
            }
            let lease = UUID()
            XCTAssertTrue(fixture.scope.acquireReader(conversationID: cid, lease: lease))
            try load(); try AssistantFixture.until { stream != nil }
            let run = try XCTUnwrap(fixture.scope.knownRun)
            AssistantFixtureProtocol.handler = { $0.fail() }
            XCTAssertTrue(fixture.scope.stopKnownRun(conversationID: cid, lease: lease))
            try AssistantFixture.until { run.stopping == .unknown }
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.capabilities) }
            fixture.scope.history.loadCapabilities()
            try AssistantFixture.until { !self.fixture.scope.history.capabilityLoading }
            XCTAssertTrue(fixture.scope.knownRun === run)
            XCTAssertEqual(run.lastError, .unavailable); XCTAssertEqual(run.stopping, .unknown)
            let count = AssistantFixtureProtocol.requests.count
            XCTAssertFalse(run.recover(conversationID: cid, runID: rid)); XCTAssertFalse(run.stop())
            XCTAssertEqual(AssistantFixtureProtocol.requests.count, count)
            XCTAssertEqual(run.projection?.text, "前缀")
            var resumed = false
            let observer = NotificationCenter.default.addObserver(forName: ClawAssistantSession.knownRunChanged,
                object: nil, queue: .main) { _ in
                    if run.lastError == .server(503, "history_unavailable") { resumed = true }
                }
            defer { NotificationCenter.default.removeObserver(observer) }
            AssistantFixtureProtocol.handler = { transport in
                if transport.request.url!.path.hasSuffix("/capabilities") {
                    transport.reply(AssistantBFixture.capabilitiesValue(stream: false))
                } else { transport.reply(AssistantBFixture.snapshot()) }
            }
            XCTAssertTrue(fixture.scope.recoverKnownRun(conversationID: cid, lease: lease))
            try AssistantFixture.until { resumed }
            XCTAssertNoThrow(try fixture.scope.history.capabilities!.validateRuns())
            XCTAssertEqual(run.stopping, .unknown); XCTAssertEqual(run.projection?.text, "前缀")
            XCTAssertEqual(AssistantFixtureProtocol.requests.filter { $0.httpMethod == "POST" }.count, 1)
        }
    }
}
