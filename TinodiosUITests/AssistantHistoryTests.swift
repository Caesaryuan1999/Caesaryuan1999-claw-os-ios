// Copyright (c) 2026 CLAW OS contributors.
// Actual app Service/Session/History and SDK + isolated SQLite; URLProtocol controls transport only.
import XCTest
import Foundation
import TinodeSDK
@testable import TinodiosDB
@testable import Tinodios

final class AssistantFixtureProtocol: URLProtocol {
    static var handler: ((AssistantFixtureProtocol) -> Void)?
    static var requests: [URLRequest] = []
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.main.async {
            guard !self.stopped else { return }
            Self.requests.append(self.request)
            guard let handler = Self.handler else {
                self.client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
            }
            handler(self)
        }
    }
    override func stopLoading() { DispatchQueue.main.async { self.stopped = true } }
    func reply(_ value: Any, status: Int = 200, length: Int? = nil) {
        guard !stopped else { return }
        var headers = ["Content-Type": "application/json", "Cache-Control": "no-store"]
        if let length = length { headers["Content-Length"] = String(length) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: value))
        client?.urlProtocolDidFinishLoading(self)
    }
    func fail() { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)) }
    func replyUnauthorized(contentType: String?) {
        guard !stopped else { return }
        var headers = ["Cache-Control": "no-store"]
        if let contentType = contentType { headers["Content-Type"] = contentType }
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("<html>synthetic unauthorized gateway</html>".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    func redirect() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                                       headerFields: ["Location": "https://other.invalid/"])!
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://other.invalid/")!),
                            redirectResponse: response)
    }
}

final class AssistantFixture {
    static let first = "00000000-0000-4000-8000-000000000001"
    static let second = "00000000-0000-4000-8000-000000000002"
    static let third = "00000000-0000-4000-8000-000000000003"
    static let date = "2026-09-19T01:00:00Z"
    static let token = Data("synthetic-assistant-token".utf8).base64EncodedString()
    let database: BaseDb
    let owner: Tinode
    var slotActive = true
    var afterNextMainGate: (() -> Void)?
    var scope: ClawAssistantSession!
    init() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-fixture-" + UUID().uuidString + ".sqlite").path
        // Do not unlink open SQLite connections (existing fixture policy).
        database = BaseDb(databasePath: path)
        guard database.isStoreAvailable, let store = database.sqlStore else { throw Failure.fixture }
        store.setMyUid(uid: "usrSyntheticAssistantA", credMethods: nil)
        owner = Tinode(for: "AssistantFixture", authenticateWith: "synthetic-ai-key", persistDataIn: store)
        owner.hostName = "assistant.invalid"; owner.useTLS = true
        owner.authToken = Self.token; owner.authTokenExpires = Date().addingTimeInterval(3600)
        owner.isConnectionAuthenticated = true
        scope = try newScope(generation: 1)
    }
    enum Failure: Error { case fixture, deadline }
    func newScope(generation: UInt64, account: ClawAssistantAccountMemory? = nil) throws -> ClawAssistantSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AssistantFixtureProtocol.self]
        return try ClawAssistantSession(owner: owner, generation: generation,
            origin: URL(string: "https://assistant.invalid/")!, account: account, configuration: config,
            gate: { [weak self] work in
                guard let self = self else { return false }
                return self.owner.withActiveSession {
                    guard self.slotActive else { return false }
                    work()
                    if Thread.isMainThread, let observation = self.afterNextMainGate {
                        self.afterNextMainGate = nil
                        // Runs after receive's synchronous main-thread identity/operation check.
                        // This observes the real injected slot boundary, not elapsed time.
                        DispatchQueue.main.async(execute: observation)
                    }
                    return true
                } ?? false
            })
    }
    func retire() {
        scope.markRetired(clearAccount: true); scope.finishRetirement()
        owner.logout()
    }
    static var capabilities: [String: Any] {
        ["version": "claw-ai-v1", "history": ["available": true],
         "generation": ["available": false, "reason": "provider_not_configured"], "stream": ["available": false],
         "limits": ["body_bytes": 65536, "text_bytes": 32000, "page_size_max": 100]]
    }
    static func conversation(_ id: String = first, revision: String = "1", title: String = "合成历史") -> [String: Any] {
        ["conversation_id": id, "revision": revision, "deleted": false, "title": title,
         "created_at": date, "updated_at": date]
    }
    static func tombstone(_ id: String = first, revision: String = "2") -> [String: Any] {
        ["conversation_id": id, "revision": revision, "deleted": true]
    }
    static func list(_ items: [[String: Any]], revision: String = "1", next: String = "") -> [String: Any] {
        ["items": items, "snapshot_revision": revision, "next_cursor": next]
    }
    static func message(state: String = "partial", text: String = "合成历史正文", seq: String = "1") -> [String: Any] {
        ["message_id": second, "conversation_id": first, "run_id": "", "seq": seq, "role": "assistant",
         "state": state, "text": text, "created_at": date, "updated_at": date]
    }
    static func messages(_ values: [[String: Any]], revision: String = "1", next: String = "") -> [String: Any] {
        ["conversation_id": first, "items": values, "snapshot_revision": revision, "next_after_seq": next]
    }
    static func error(_ code: String) -> [String: Any] { ["error": ["code": code]] }
    static func main<T>(_ work: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try work() }
        return try DispatchQueue.main.sync(execute: work)
    }
    static func until(_ condition: () -> Bool) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !condition() && ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        guard condition() else { XCTFail("Bounded real consumer condition not reached"); throw Failure.deadline }
    }
    func prepare() throws {
        AssistantFixtureProtocol.handler = { $0.reply(Self.capabilities) }
        scope.history.loadCapabilities()
        try Self.until { !self.scope.history.capabilityLoading }
        XCTAssertNotNil(scope.history.capabilities)
    }
}

final class AssistantHistoryTests: XCTestCase {
    private var fixture: AssistantFixture!
    override func setUpWithError() throws {
        continueAfterFailure = false
        try AssistantFixture.main {
            AssistantFixtureProtocol.requests = []
            fixture = try AssistantFixture()
        }
    }
    override func tearDownWithError() throws {
        AssistantFixture.main {
            fixture?.retire(); fixture = nil
            AssistantFixtureProtocol.handler = nil
        }
    }

    func testRealHeadersAndOriginRejectUnsafeSourcesWithoutPost() throws {
        try AssistantFixture.main {
            for value in ["http://192.168.1.1/", "http://localhost/", "https://user@assistant.invalid/",
                          "https://assistant.invalid/?token=x", "https://assistant.invalid/v0/"] {
                XCTAssertThrowsError(try ClawAssistantService.origin(URL(string: value)!))
            }
            XCTAssertNoThrow(try ClawAssistantService.origin(URL(string: "http://127.0.0.1:9/")!))
            XCTAssertNoThrow(try ClawAssistantService.origin(URL(string: "http://[::1]:9/")!))
            try fixture.prepare()
            let request = try XCTUnwrap(AssistantFixtureProtocol.requests.last)
            XCTAssertEqual(request.url?.path, "/v0/ai/capabilities")
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token " + AssistantFixture.token)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Tinode-APIKey"), "synthetic-ai-key")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Tinode-Auth"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertNil(request.httpBody)
        }
    }

    func testRedirectIsRejectedByActualSessionDelegate() throws {
        try AssistantFixture.main {
            AssistantFixtureProtocol.handler = { $0.redirect() }
            fixture.scope.history.loadCapabilities()
            try AssistantFixture.until { !self.fixture.scope.history.capabilityLoading }
            XCTAssertNotNil(fixture.scope.history.capabilityError)
            XCTAssertEqual(AssistantFixtureProtocol.requests.count, 1)
            XCTAssertEqual(AssistantFixtureProtocol.requests[0].url?.host, "assistant.invalid")
        }
    }

    func testResponseBudgetRejectsAdvertisedOverflowButAcceptsFullLargeText() throws {
        try AssistantFixture.main {
            try fixture.prepare()
            AssistantFixtureProtocol.handler = {
                $0.reply(AssistantFixture.messages([AssistantFixture.message(text: String(repeating: "合", count: 20000))]))
            }
            fixture.scope.history.loadMessages(AssistantFixture.first)
            try AssistantFixture.until { !self.fixture.scope.history.detailLoading.contains(AssistantFixture.first) }
            XCTAssertEqual(fixture.scope.history.details[AssistantFixture.first]?.first?.text.utf8.count, 60000)
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.capabilities,
                length: ClawAssistantService.responseLimit + 1) }
            fixture.scope.history.loadCapabilities()
            try AssistantFixture.until { !self.fixture.scope.history.capabilityLoading }
            XCTAssertEqual(fixture.scope.history.capabilityError, .responseTooLarge)
        }
    }

    func testFreshScopeNeedsActualLoginAndExistingScopeSurvivesOnlyUnchangedTokenOffline() throws {
        try AssistantFixture.main {
            fixture.owner.isConnectionAuthenticated = false
            XCTAssertThrowsError(try fixture.newScope(generation: 1))
            XCTAssertTrue(fixture.scope.isCurrent)
            fixture.owner.hostName = "changed.invalid"
            XCTAssertFalse(fixture.scope.isCurrent)
            fixture.owner.hostName = "assistant.invalid"
            fixture.owner.authToken = Data("new-token".utf8).base64EncodedString()
            XCTAssertFalse(fixture.scope.isCurrent)
            fixture.owner.isConnectionAuthenticated = true
            let renewed = try fixture.newScope(generation: 1)
            XCTAssertTrue(renewed.isCurrent)
            let separateLifetime = try fixture.newScope(generation: 2, account: renewed.account)
            XCTAssertFalse(separateLifetime.account === renewed.account)
            separateLifetime.markRetired(clearAccount: true); separateLifetime.finishRetirement()
            fixture.database.sqlStore?.setMyUid(uid: "usrSyntheticAssistantB", credMethods: nil)
            XCTAssertFalse(renewed.isCurrent)
            renewed.markRetired(clearAccount: true); renewed.finishRetirement()
        }
    }

    func testAccountDraftPersistsAcrossTokenRefreshButRetiresOnLogout() throws {
        try AssistantFixture.main {
            let old = try XCTUnwrap(fixture.scope)
            old.updateDraft("只属于本账号的合成草稿")
            fixture.owner.authToken = Data("rotated-token".utf8).base64EncodedString()
            let renewed = try fixture.newScope(generation: 1, account: old.account)
            old.markRetired(clearAccount: false); old.finishRetirement()
            XCTAssertEqual(renewed.draft, "只属于本账号的合成草稿")
            XCTAssertEqual(old.draft, "")
            renewed.markRetired(clearAccount: true); renewed.finishRetirement()
            XCTAssertEqual(renewed.account.draft, "")
        }
    }

    func testSnapshotChangedDiscardsStagingAndReplacesOnlyCompleteAccountList() throws {
        try AssistantFixture.main {
            try fixture.prepare()
            let model = fixture.scope.history
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.list([AssistantFixture.conversation(title: "旧完整快照")])) }
            model.loadConversations()
            try AssistantFixture.until { !model.listLoading }
            var page = 0
            var last: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = { response in
                page += 1
                switch page {
                case 1:
                    response.reply(AssistantFixture.list([AssistantFixture.conversation()], next: AssistantFixture.first))
                case 2:
                    let query = URLComponents(url: response.request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    XCTAssertEqual(query.first { $0.name == "cursor" }?.value, AssistantFixture.first)
                    XCTAssertEqual(query.first { $0.name == "snapshot_revision" }?.value, "1")
                    response.reply(AssistantFixture.error("snapshot_changed"), status: 409)
                case 3:
                    XCTAssertFalse(response.request.url!.absoluteString.contains("cursor="))
                    response.reply(AssistantFixture.list([AssistantFixture.tombstone()], revision: "2",
                                                        next: AssistantFixture.first))
                default: last = response
                }
            }
            model.loadConversations()
            try AssistantFixture.until { last != nil }
            XCTAssertEqual(model.conversations.first?.title, "旧完整快照")
            last?.reply(AssistantFixture.list([AssistantFixture.conversation(AssistantFixture.second, revision: "2", title: "")],
                                             revision: "2"))
            try AssistantFixture.until { !model.listLoading }
            XCTAssertEqual(model.conversations.map { $0.conversation_id }, [AssistantFixture.second])
            XCTAssertEqual(model.conversations.first?.displayTitle, "新对话")
            XCTAssertEqual(model.deletions[AssistantFixture.first], .confirmed)
        }
    }

    func testContinuousRevisionChangesEndBoundedlyWithoutDroppingPreviousSnapshot() throws {
        try AssistantFixture.main {
            try fixture.prepare()
            let model = fixture.scope.history
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.list([AssistantFixture.conversation()])) }
            model.loadConversations(); try AssistantFixture.until { !model.listLoading }
            let before = AssistantFixtureProtocol.requests.count
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.error("snapshot_changed"), status: 409) }
            model.loadConversations(); try AssistantFixture.until { !model.listLoading }
            XCTAssertEqual(AssistantFixtureProtocol.requests.count - before, 3)
            XCTAssertEqual(model.listError, .historyChanged)
            XCTAssertEqual(model.conversations.count, 1)
        }
    }

    func testUnknownStateInvalidatesWholeDetailAndPreservesOriginalCompleteMessages() throws {
        try AssistantFixture.main {
            try fixture.prepare()
            let model = fixture.scope.history
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.messages([AssistantFixture.message()])) }
            model.loadMessages(AssistantFixture.first)
            try AssistantFixture.until { !model.detailLoading.contains(AssistantFixture.first) }
            let old = model.details[AssistantFixture.first]
            XCTAssertEqual(old?.first?.run_id, "")
            XCTAssertEqual(old?.first?.stateText, "回答尚未完成")
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.messages([AssistantFixture.message(state: "completed")])) }
            model.loadMessages(AssistantFixture.first)
            try AssistantFixture.until { !model.detailLoading.contains(AssistantFixture.first) }
            XCTAssertEqual(model.detailErrors[AssistantFixture.first], .incompatible)
            XCTAssertEqual(model.details[AssistantFixture.first], old)
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.messages([AssistantFixture.message(state: "interrupted")])) }
            model.loadMessages(AssistantFixture.first)
            try AssistantFixture.until { !model.detailLoading.contains(AssistantFixture.first) }
            XCTAssertEqual(model.details[AssistantFixture.first]?.first?.stateText, "回答已中断")
        }
    }

    func testDecimalMessageCursorIsNotUUIDAndMalformedPageNeverReplacesSnapshot() throws {
        try AssistantFixture.main {
            try fixture.prepare()
            let model = fixture.scope.history
            var page = 0
            AssistantFixtureProtocol.handler = { response in
                page += 1
                if page == 1 {
                    response.reply(AssistantFixture.messages([AssistantFixture.message(seq: "9007199254740993")],
                                                            next: "9007199254740993"))
                } else {
                    let query = URLComponents(url: response.request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    XCTAssertEqual(query.first { $0.name == "after_seq" }?.value, "9007199254740993")
                    response.reply(AssistantFixture.messages([]))
                }
            }
            model.loadMessages(AssistantFixture.first)
            try AssistantFixture.until { !model.detailLoading.contains(AssistantFixture.first) }
            XCTAssertEqual(model.details[AssistantFixture.first]?.first?.seq, "9007199254740993")
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.list([], next: "12")) }
            model.loadConversations(); try AssistantFixture.until { !model.listLoading }
            XCTAssertEqual(model.listError, .invalidResponse)
            XCTAssertFalse(model.hasListSnapshot)
            let maximum = "9223372036854775807"
            let overflow = "9223372036854775808"
            XCTAssertTrue(ClawAssistantWire.decimal(maximum))
            XCTAssertFalse(ClawAssistantWire.decimal(overflow))
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.messages([AssistantFixture.message(seq: maximum)])) }
            model.loadMessages(AssistantFixture.first)
            try AssistantFixture.until { !model.detailLoading.contains(AssistantFixture.first) }
            XCTAssertEqual(model.details[AssistantFixture.first]?.first?.seq, maximum)
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.messages([AssistantFixture.message(seq: overflow)])) }
            model.loadMessages(AssistantFixture.first)
            try AssistantFixture.until { !model.detailLoading.contains(AssistantFixture.first) }
            XCTAssertEqual(model.detailErrors[AssistantFixture.first], .invalidResponse)
            XCTAssertEqual(model.details[AssistantFixture.first]?.first?.seq, maximum)
        }
    }

    func testAccountAndPageGenerationsRejectLateOldResponses() throws {
        try AssistantFixture.main {
            try fixture.prepare()
            let model = fixture.scope.history
            var held: [AssistantFixtureProtocol] = []
            AssistantFixtureProtocol.handler = { held.append($0) }
            model.loadConversations(); model.loadConversations()
            try AssistantFixture.until { held.count == 2 }
            held[1].reply(AssistantFixture.list([AssistantFixture.conversation(AssistantFixture.second)]))
            try AssistantFixture.until { !model.listLoading }
            var oldConsumed = false
            fixture.afterNextMainGate = { oldConsumed = true }
            held[0].reply(AssistantFixture.list([AssistantFixture.conversation()]))
            try AssistantFixture.until { oldConsumed }
            XCTAssertEqual(model.conversations.first?.conversation_id, AssistantFixture.second)
            fixture.slotActive = false
            XCTAssertFalse(fixture.scope.isCurrent)
            fixture.scope.markRetired(clearAccount: true); fixture.scope.finishRetirement()
            XCTAssertTrue(model.conversations.isEmpty)
            XCTAssertEqual(fixture.owner.store?.myUid, "usrSyntheticAssistantA")
        }
    }

    func testCurrent401BlocksOnlyAssistantAndOldToken401CannotBlockRenewedScope() throws {
        try AssistantFixture.main {
            let old = try XCTUnwrap(fixture.scope)
            var held: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = { held = $0 }
            old.history.loadCapabilities()
            try AssistantFixture.until { held != nil }
            fixture.owner.authToken = Data("replacement-token".utf8).base64EncodedString()
            let renewed = try fixture.newScope(generation: 1, account: old.account)
            held?.reply(AssistantFixture.error("authentication_required"), status: 401)
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.capabilities) }
            renewed.history.loadCapabilities()
            try AssistantFixture.until { !renewed.history.capabilityLoading }
            XCTAssertTrue(renewed.isCurrent)
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.error("authentication_required"), status: 401) }
            renewed.history.loadCapabilities()
            try AssistantFixture.until { renewed.isBlocked }
            XCTAssertNil(renewed.history.capabilities)
            XCTAssertEqual(fixture.owner.myUid, "usrSyntheticAssistantA")
            XCTAssertEqual(fixture.owner.store?.myUid, "usrSyntheticAssistantA")
            XCTAssertTrue(fixture.owner.isSessionActive)
            renewed.markRetired(clearAccount: true); renewed.finishRetirement()
        }
    }

    func testNonJSONAndMissingMIME401BlockTheActualScopeWithoutOrdinaryLogout() throws {
        try AssistantFixture.main {
            for contentType: String? in ["text/html", nil] {
                let sample = try AssistantFixture()
                defer { sample.retire() }
                try sample.prepare()
                let model = sample.scope.history
                model.setDraft("仅原账号可见的合成草稿")
                AssistantFixtureProtocol.handler = { $0.replyUnauthorized(contentType: contentType) }
                model.loadCapabilities()
                try AssistantFixture.until { sample.scope.isBlocked }
                XCTAssertNil(model.capabilities)
                XCTAssertEqual(model.draft, "")
                XCTAssertEqual(model.capabilityError, .signInRequired)
                XCTAssertTrue(sample.owner.isSessionActive)
                XCTAssertEqual(sample.owner.myUid, "usrSyntheticAssistantA")
                XCTAssertEqual(sample.owner.store?.myUid, "usrSyntheticAssistantA")
            }
        }
    }

    func testDeleteUnknownRemainsAfterActiveReadAndRetryCannotResurrectFromLateGet() throws {
        try AssistantFixture.main {
            try fixture.prepare()
            let model = fixture.scope.history
            model.setDraft("未发送的草稿")
            AssistantFixtureProtocol.handler = { $0.fail() }
            model.deleteConversation(AssistantFixture.first)
            try AssistantFixture.until { model.deletions[AssistantFixture.first] == .unknown }
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.list([AssistantFixture.conversation()])) }
            model.reconcileDeletion(AssistantFixture.first)
            try AssistantFixture.until { !model.listLoading }
            XCTAssertEqual(model.deletions[AssistantFixture.first], .unknown)
            var held: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = {
                if $0.request.httpMethod == "DELETE" {
                    XCTAssertNil($0.request.httpBody); XCTAssertNil($0.request.url?.query)
                    $0.reply(["conversation_id": AssistantFixture.first, "deleted": true, "revision": "2"])
                } else { held = $0 }
            }
            model.loadConversations()
            try AssistantFixture.until { held != nil }
            model.deleteConversation(AssistantFixture.first)
            try AssistantFixture.until { model.deletions[AssistantFixture.first] == .confirmed }
            var oldConsumed = false
            fixture.afterNextMainGate = { oldConsumed = true }
            held?.reply(AssistantFixture.list([AssistantFixture.conversation()]))
            try AssistantFixture.until { oldConsumed }
            XCTAssertTrue(model.conversations.isEmpty)
            XCTAssertEqual(model.draft, "未发送的草稿")
            XCTAssertEqual(AssistantFixtureProtocol.requests.filter { $0.httpMethod == "DELETE" }.count, 2)
        }
    }

    func testDeleteBadReceiptAndUnexpectedSuccessAreUnknownButExplicitRejectionIsSeparate() throws {
        try AssistantFixture.main {
            try fixture.prepare()
            let model = fixture.scope.history
            AssistantFixtureProtocol.handler = {
                $0.reply(["conversation_id": AssistantFixture.second, "deleted": true, "revision": "2"])
            }
            model.deleteConversation(AssistantFixture.first)
            try AssistantFixture.until { model.deletions[AssistantFixture.first] == .unknown }
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.error("permission_denied"), status: 403) }
            model.deleteConversation(AssistantFixture.first)
            try AssistantFixture.until { model.deletions[AssistantFixture.first] != .pending }
            XCTAssertEqual(model.deletions[AssistantFixture.first], .unknown) // prior write remains uncertain
            model.deleteConversation(AssistantFixture.second)
            try AssistantFixture.until { model.deletions[AssistantFixture.second] != .pending }
            XCTAssertEqual(model.deletions[AssistantFixture.second], .rejected(.server(403, "permission_denied")))
            AssistantFixtureProtocol.handler = { $0.reply([:], status: 205) }
            model.deleteConversation(AssistantFixture.third)
            try AssistantFixture.until { model.deletions[AssistantFixture.third] != .pending }
            XCTAssertEqual(model.deletions[AssistantFixture.third], .unknown)
        }
    }

    func testTombstoneReconcilesUnknownAnd503KeepsDraftWithoutAnyPost() throws {
        try AssistantFixture.main {
            try fixture.prepare()
            let model = fixture.scope.history
            model.setDraft("保留原字节 + 换行\n合成文本")
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.error("internal_error"), status: 500) }
            model.deleteConversation(AssistantFixture.first)
            try AssistantFixture.until { model.deletions[AssistantFixture.first] == .unknown }
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.list([AssistantFixture.tombstone()], revision: "2")) }
            model.reconcileDeletion(AssistantFixture.first)
            try AssistantFixture.until { !model.listLoading }
            XCTAssertEqual(model.deletions[AssistantFixture.first], .confirmed)
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.error("provider_not_configured"), status: 503) }
            model.loadCapabilities()
            try AssistantFixture.until { !model.capabilityLoading }
            XCTAssertEqual(model.draft, "保留原字节 + 换行\n合成文本")
            XCTAssertEqual(model.providerNotice, "服务暂未开通，你的问题已保留。")
            XCTAssertFalse(AssistantFixtureProtocol.requests.contains { $0.httpMethod == "POST" })

            // A completed read can establish the tombstone before a pending DELETE
            // gets its uncertain response; that later response cannot reverse it.
            var held: AssistantFixtureProtocol?
            AssistantFixtureProtocol.handler = {
                if $0.request.httpMethod == "DELETE" { held = $0 }
                else { $0.reply(AssistantFixture.list([AssistantFixture.tombstone(AssistantFixture.second, revision: "3")], revision: "3")) }
            }
            model.deleteConversation(AssistantFixture.second)
            try AssistantFixture.until { held != nil }
            model.loadConversations()
            try AssistantFixture.until { model.deletions[AssistantFixture.second] == .confirmed }
            var oldConsumed = false
            fixture.afterNextMainGate = { oldConsumed = true }
            held?.fail()
            try AssistantFixture.until { oldConsumed }
            XCTAssertEqual(model.deletions[AssistantFixture.second], .confirmed)
        }
    }
}
