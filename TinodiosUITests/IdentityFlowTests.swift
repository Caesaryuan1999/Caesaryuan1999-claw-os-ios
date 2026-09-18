import XCTest
import Foundation

// Actual production Foundation service + flow are compiled into this test target.
// Only transport, time and the UIKit/SDK bridge are controlled; no real OTP/provider is contacted.
private final class IdentityProtocol: URLProtocol {
    struct Reply { let status: Int; let body: Data }
    static let lock = NSLock()
    static var handler: ((URLRequest) throws -> Reply)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            guard let handler = handler else { throw URLError(.badServerResponse) }
            let reply = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    static func respond(_ handler: @escaping (URLRequest) throws -> Reply) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler
    }
}

final class IdentityFlowTests: XCTestCase {
    private var service: ClawIdentityService!
    private var flow: ClawIdentityFlow!
    private var time = Date(timeIntervalSince1970: 1_800_000_000)
    private var current = true
    private var retired = 0
    private var committed: [ClawIdentitySessionResult] = []
    private var bridge: ClawIdentityFlow.LoginBridge!
    private var allowCommit = true

    private let capabilities = """
    {"version":"claw-auth-v1","enabled":true,"methods":{"email":true,"tel":true},"flow":"verify_then_password","code_length":6,"challenge_ttl":300,"proof_ttl":300,"resend_after":60,"password":{"min_length":12,"max_length":64,"alphabet":"ascii_printable_no_space"},"legacy_basic":true,"test_mode":true}
    """
    private let accepted = #"{"challenge_id":"synthetic-challenge","expires_in":300,"retry_after":60,"delivery":"accepted"}"#
    private let proof = #"{"proof":"synthetic-test-proof","expires_in":300,"purpose":"register"}"#
    private let login = #"{"user":"usrSyntheticA","token":"dGVzdC10b2tlbg==","expires":"2099-01-01T00:00:00Z"}"#

    override func setUpWithError() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdentityProtocol.self]
        service = try ClawIdentityService(origin: URL(string: "https://identity.invalid/")!,
            apiKey: "synthetic-api-key", configuration: configuration)
        current = true; retired = 0; committed = []; allowCommit = true
        time = Date(timeIntervalSince1970: 1_800_000_000)
        bridge = { http, reply in
            reply(.success(ClawIdentitySessionResult(user: http.user, token: http.token, expires: nil)))
        }
        flow = ClawIdentityFlow(purpose: .register, service: service, now: { [unowned self] in self.time },
            snapshotIsCurrent: { [unowned self] in self.current },
            loginBridge: { [unowned self] http, reply in self.bridge(http, reply) },
            retireSession: { [unowned self] in self.retired += 1 },
            commitSession: { [unowned self] session in
                guard self.allowCommit else { return false }
                self.committed.append(session); return true
            })
    }
    override func tearDown() {
        flow.invalidate()
        flow = nil
        service.cancel()
        service = nil
        IdentityProtocol.respond { _ in throw URLError(.cancelled) }
        super.tearDown()
    }
    private func reply(_ json: String, _ status: Int = 200) -> IdentityProtocol.Reply {
        IdentityProtocol.Reply(status: status, body: Data(json.utf8))
    }
    private func awaitResult<T>(_ action: (@escaping (Result<T, ClawIdentityError>) -> Void) -> Void) -> Result<T, ClawIdentityError> {
        let done = expectation(description: "production callback")
        var captured: Result<T, ClawIdentityError>?
        action { result in captured = result; done.fulfill() }
        wait(for: [done], timeout: 3)
        return captured ?? .failure(.ended)
    }
    private func prepare() throws {
        IdentityProtocol.respond { [self] _ in reply(capabilities) }
        _ = try awaitResult { flow.prepare($0) }.get()
    }
    private func challenge() throws {
        IdentityProtocol.respond { [self] _ in reply(accepted, 202) }
        _ = try awaitResult { flow.requestCode(method: .email, input: "Test+tag@Example.com",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }.get()
    }
    private func verified() throws {
        try prepare(); try challenge()
        IdentityProtocol.respond { [self] _ in reply(proof) }
        _ = try awaitResult { flow.verify(code: "123456", completion: $0) }.get()
    }
    private func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }

    func testNonTLSLegacyOriginKeepsSDKLoginWithoutCreatingHTTPTransport() throws {
        let origin = URL(string: "http://192.168.50.20:6060/")!
        XCTAssertThrowsError(try ClawIdentityService(origin: origin, apiKey: "synthetic"))
        let disabled = ClawIdentityFlow.makeHTTPService(origin: origin, apiKey: "synthetic")
        XCTAssertNil(disabled)
        let legacy = ClawIdentityFlow(purpose: .register, service: disabled,
            snapshotIsCurrent: { true }, loginBridge: { _, _ in XCTFail("No new HTTP token bridge") },
            retireSession: {}, commitSession: { $0.user == "usrLegacy" })
        defer { legacy.invalidate() }
        XCTAssertThrowsError(try awaitResult { legacy.prepare($0) }.get())
        XCTAssertTrue(legacy.legacyLoginAvailable)
        let originalPassword = " \told-password\n"
        var calls = 0
        let result = try awaitResult {
            legacy.loginLegacy(username: "original42", password: originalPassword, bridge: { name, password, reply in
                calls += 1
                XCTAssertEqual(name, "original42")
                XCTAssertEqual(password, originalPassword)
                reply(.success(ClawIdentitySessionResult(user: "usrLegacy", token: "b2xk", expires: nil)))
            }, completion: $0)
        }.get()
        XCTAssertEqual(result.user, "usrLegacy")
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(legacy.sessionCommitted)
    }

    func testAbsentHTTPTransportCannotSendAnyNewIdentityRequest() throws {
        let disabled = ClawIdentityFlow.makeHTTPService(origin: URL(string: "http://identity.example.test/")!,
                                                       apiKey: "synthetic")
        XCTAssertNil(disabled)
        let blocked = ClawIdentityFlow(purpose: .register, service: disabled,
            snapshotIsCurrent: { true }, loginBridge: { _, _ in XCTFail("New login must stay blocked") },
            retireSession: {}, commitSession: { _ in XCTFail("No session to commit"); return false })
        defer { blocked.invalidate() }
        XCTAssertThrowsError(try awaitResult { blocked.prepare($0) }.get())
        XCTAssertThrowsError(try awaitResult { blocked.login(method: .email, input: "a@example.test",
                                                             password: "Original bytes", completion: $0) }.get())
        XCTAssertThrowsError(try awaitResult { blocked.requestCode(method: .email, input: "a@example.test",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }.get())
        XCTAssertThrowsError(try awaitResult { blocked.verify(code: "123456", completion: $0) }.get())
        XCTAssertThrowsError(try awaitResult { blocked.setPassword("Abcdef123456!", completion: $0) }.get())
        XCTAssertFalse(blocked.busy)
        XCTAssertNil(blocked.pendingChallenge)
        XCTAssertNil(blocked.pendingPassword)
    }

    func testIdentifierNormalizationKeepsPlusAndDotsAndRejectsUnicode() throws {
        XCTAssertEqual(try ClawIdentityInput.normalize(" \tUser.Name+Tag@XN--EXAMPLE.COM\r\n", method: .email), "user.name+tag@xn--example.com")
        XCTAssertEqual(try ClawIdentityInput.normalize("13800138000", method: .tel), "+8613800138000")
        XCTAssertThrowsError(try ClawIdentityInput.normalize("a@例子.com", method: .email))
        XCTAssertThrowsError(try ClawIdentityInput.normalize("K@example.com", method: .email))
        XCTAssertThrowsError(try ClawIdentityInput.normalize("\u{00a0}a@b.com", method: .email))
        XCTAssertThrowsError(try ClawIdentityInput.normalize(String(repeating: "a", count: 65) + "@b.com", method: .email))
        XCTAssertThrowsError(try ClawIdentityInput.normalize("a@" + String(repeating: "b", count: 64) + ".com", method: .email))
        XCTAssertThrowsError(try ClawIdentityInput.normalize("a@localhost", method: .email))
    }
    func testNewPasswordPolicyDoesNotTrimOrAcceptNonASCII() {
        XCTAssertTrue(ClawIdentityInput.newPasswordIsValid("Correct-12345"))
        XCTAssertFalse(ClawIdentityInput.newPasswordIsValid(" Correct-12345"))
        XCTAssertFalse(ClawIdentityInput.newPasswordIsValid("密码Password123"))
        XCTAssertFalse(ClawIdentityInput.newPasswordIsValid("short"))
        XCTAssertFalse(ClawIdentityInput.newPasswordIsValid(String(repeating: "x", count: 65)))
    }
    func testOriginRequiresHTTPSExceptExactLoopback() throws {
        for value in ["http://example.com/", "https://user:secret@example.com/", "https://example.com/?token=x",
                      "https://example.com/#fragment", "http://localhost.example.com/"] {
            XCTAssertThrowsError(try ClawIdentityService(origin: URL(string: value)!, apiKey: "fixture"))
        }
        for value in ["https://example.com/", "http://127.0.0.1:6091/", "http://localhost:6091/"] {
            let candidate = try ClawIdentityService(origin: URL(string: value)!, apiKey: "fixture")
            candidate.cancel()
        }
    }
    func testRedirectDelegateRejectsEvenSameOrigin() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://identity.invalid/other")!)
        let task = session.dataTask(with: request)
        let response = HTTPURLResponse(url: service.baseURL, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var invoked = false
        service.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { redirected in
            invoked = true; XCTAssertNil(redirected)
        }
        XCTAssertTrue(invoked)
    }
    func testDisabledCapabilitiesAndLegalGateDoNotSubmitChallenge() throws {
        IdentityProtocol.respond { [self] _ in reply(capabilities.replacingOccurrences(of: #""enabled":true"#, with: #""enabled":false"#)) }
        XCTAssertThrowsError(try awaitResult { flow.prepare($0) }.get())
        XCTAssertEqual(flow.capabilities?.enabled, false)
        var sent = 0
        IdentityProtocol.respond { [self] _ in sent += 1; return reply(capabilities) }
        // A decoded refusal remains authoritative for this flow. Replacing a
        // transport fixture must not silently enable a cached disabled service.
        XCTAssertThrowsError(try awaitResult { flow.prepare($0) }.get())
        XCTAssertThrowsError(try awaitResult { flow.requestCode(method: .email, input: "a@b.com",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }.get())
        XCTAssertThrowsError(try awaitResult { flow.requestCode(method: .email, input: "a@b.com",
            legalResourcesAvailable: false, termsAccepted: true, completion: $0) }.get())
        XCTAssertEqual(sent, 0)
    }
    func testSupportedCapabilitiesStillRequireAvailableLegalResources() throws {
        try prepare()
        XCTAssertEqual(flow.capabilities?.supported, true)
        var sent = 0
        IdentityProtocol.respond { [self] _ in sent += 1; return reply(accepted, 202) }
        XCTAssertThrowsError(try awaitResult { flow.requestCode(method: .email, input: "a@b.com",
            legalResourcesAvailable: false, termsAccepted: true, completion: $0) }.get())
        XCTAssertEqual(sent, 0)
    }
    func testUnavailableMethodCannotSendOTP() throws {
        IdentityProtocol.respond { [self] _ in reply(capabilities.replacingOccurrences(of: #""email":true"#, with: #""email":false"#)) }
        _ = try awaitResult { flow.prepare($0) }.get()
        var sent = 0
        IdentityProtocol.respond { [self] _ in sent += 1; return reply(accepted, 202) }
        XCTAssertThrowsError(try awaitResult { flow.requestCode(method: .email, input: "a@b.com",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }.get())
        XCTAssertEqual(sent, 0)
    }
    func testCapabilitiesConnectionFailureIsReadOnlyAndCanBeCheckedAgain() throws {
        var requests = 0
        IdentityProtocol.respond { request in
            requests += 1
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.lastPathComponent, "capabilities")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.httpBodyStream)
            throw URLError(.cannotConnectToHost)
        }
        let failed = awaitResult { flow.prepare($0) }
        guard case let .failure(error) = failed else { return XCTFail("Expected failed capabilities check") }
        guard case .capabilitiesConnection = error else { return XCTFail("Expected read-only connection error") }
        XCTAssertEqual(error.message, "暂时无法连接身份服务，请检查网络和连接设置后重试。")
        XCTAssertTrue(flow.capabilitiesChecked)
        XCTAssertNil(flow.capabilities)
        XCTAssertNil(flow.pendingChallenge)
        XCTAssertNil(flow.pendingPassword)
        XCTAssertTrue(flow.legacyLoginAvailable)
        XCTAssertEqual(requests, 1)

        IdentityProtocol.respond { [self] request in
            requests += 1
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.lastPathComponent, "capabilities")
            return reply(capabilities)
        }
        XCTAssertTrue(try awaitResult { flow.prepare($0) }.get().supported)
        XCTAssertEqual(requests, 2)
        XCTAssertNil(flow.pendingChallenge)
        XCTAssertNil(flow.pendingPassword)
    }

    func testUncertainChallengeExplicitRetryFreezesRequestBytesAndIdentifier() throws {
        try prepare()
        var requests: [Data] = []
        IdentityProtocol.respond { [self] request in
            requests.append(try body(request))
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Tinode-APIKey"), "synthetic-api-key")
            throw URLError(.networkConnectionLost)
        }
        let failed = awaitResult { flow.requestCode(method: .email, input: "Test+tag@Example.com",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }
        guard case let .failure(error) = failed else { return XCTFail("Expected uncertain challenge") }
        guard case .transport = error else { return XCTFail("POST must retain its uncertain result") }
        XCTAssertEqual(error.message, "网络请求结果未确认，请检查连接后按页面提示操作")
        XCTAssertNotNil(flow.pendingChallenge)
        XCTAssertThrowsError(try awaitResult { flow.requestCode(method: .email, input: "changed@example.com",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }.get())
        XCTAssertEqual(requests.count, 1)
        IdentityProtocol.respond { [self] request in requests.append(try body(request)); return reply(accepted, 202) }
        _ = try awaitResult { flow.requestCode(method: .email, input: "Test+tag@Example.com",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }.get()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0], requests[1])
        XCTAssertNil(flow.pendingChallenge)
    }
    func testChallengeCooldownAndExpiryUseClockWithoutResending() throws {
        try prepare(); try challenge()
        XCTAssertEqual(flow.retrySeconds, 60)
        XCTAssertTrue(flow.canVerify)
        XCTAssertThrowsError(try awaitResult { flow.requestCode(method: .email, input: "a@b.com",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }.get())
        time = time.addingTimeInterval(301)
        XCTAssertFalse(flow.canVerify)
        XCTAssertEqual(flow.retrySeconds, 0)
        XCTAssertThrowsError(try awaitResult { flow.verify(code: "123456", completion: $0) }.get())
    }
    func testVerifyLostResponseDiscardsChallengeInsteadOfReusingMissingProof() throws {
        try prepare(); try challenge()
        IdentityProtocol.respond { _ in throw URLError(.networkConnectionLost) }
        XCTAssertThrowsError(try awaitResult { flow.verify(code: "123456", completion: $0) }.get())
        XCTAssertNil(flow.challenge)
        XCTAssertNil(flow.proof)
        XCTAssertFalse(flow.canVerify)
    }
    func testProofExpiryDoesNotSendNewMutation() throws {
        try verified()
        time = time.addingTimeInterval(301)
        var sent = 0
        IdentityProtocol.respond { [self] _ in sent += 1; return reply("{}") }
        XCTAssertThrowsError(try awaitResult { flow.setPassword("Correct-12345", completion: $0) }.get())
        XCTAssertEqual(sent, 0)
    }
    func testPendingRegistrationRetrySurvivesProofExpiryWithIdenticalBytes() throws {
        try verified()
        var requests: [Data] = []
        IdentityProtocol.respond { [self] request in requests.append(try body(request)); throw URLError(.networkConnectionLost) }
        _ = awaitResult { flow.setPassword("Correct-12345", completion: $0) }
        XCTAssertNotNil(flow.pendingPassword)
        time = time.addingTimeInterval(301)
        XCTAssertThrowsError(try awaitResult { flow.setPassword("Changed-12345", completion: $0) }.get())
        XCTAssertEqual(requests.count, 1)
        IdentityProtocol.respond { [self] request in
            requests.append(try body(request))
            return reply(#"{"user":"usrSyntheticA","registered":true,"login_required":true,"replayed":true}"#)
        }
        _ = try awaitResult { flow.setPassword("Correct-12345", completion: $0) }.get()
        XCTAssertEqual(requests[0], requests[1])
        XCTAssertEqual(flow.registeredUser, "usrSyntheticA")
        XCTAssertTrue(committed.isEmpty, "HTTP registration must not establish a chat session")
    }
    func testProofInvalidClearsProofAndPermitsNewVerification() throws {
        try verified()
        IdentityProtocol.respond { [self] _ in reply(#"{"error":{"code":"proof_invalid"}}"#, 400) }
        _ = awaitResult { flow.setPassword("Correct-12345", completion: $0) }
        XCTAssertNil(flow.proof)
        XCTAssertNil(flow.pendingPassword)
        time = time.addingTimeInterval(61)
        try challenge()
        XCTAssertTrue(flow.canVerify)
    }
    func testLoginPreservesOldPasswordBytesAndCommitsOnlyAfterWS() throws {
        try prepare()
        let oldPassword = " xé \n"
        IdentityProtocol.respond { [self] request in
            let json = try JSONSerialization.jsonObject(with: body(request)) as! [String: Any]
            XCTAssertEqual(json["password"] as? String, oldPassword)
            XCTAssertEqual(json["value"] as? String, "a@b.com")
            return reply(login)
        }
        bridge = { [unowned self] http, reply in
            XCTAssertTrue(self.committed.isEmpty)
            reply(.success(ClawIdentitySessionResult(user: http.user, token: http.token, expires: nil)))
        }
        _ = try awaitResult { flow.login(method: .email, input: "A@B.COM", password: oldPassword, completion: $0) }.get()
        XCTAssertEqual(committed.count, 1)
        XCTAssertTrue(flow.sessionCommitted)
    }
    func testHTTPAndWSUIDMismatchRetiresWithoutPersistingToken() throws {
        try prepare()
        IdentityProtocol.respond { [self] _ in reply(login) }
        bridge = { http, reply in
            reply(.success(ClawIdentitySessionResult(user: "usrOther", token: http.token, expires: nil)))
        }
        XCTAssertThrowsError(try awaitResult { flow.login(method: .email, input: "a@b.com", password: "old", completion: $0) }.get())
        XCTAssertTrue(committed.isEmpty)
        XCTAssertEqual(retired, 1)
    }
    func testCommitGateRejectsSessionRetiredAtPersistenceBoundary() throws {
        try prepare()
        allowCommit = false
        IdentityProtocol.respond { [self] _ in reply(login) }
        XCTAssertThrowsError(try awaitResult { flow.login(method: .email, input: "a@b.com", password: "old", completion: $0) }.get())
        XCTAssertTrue(committed.isEmpty)
        XCTAssertEqual(retired, 1)
    }
    func testHostGenerationChangeDiscardsLateWebSocketResult() throws {
        try prepare()
        IdentityProtocol.respond { [self] _ in reply(login) }
        let started = expectation(description: "WS started")
        var callback: ((Result<ClawIdentitySessionResult, ClawIdentityError>) -> Void)?
        bridge = { _, reply in callback = reply; started.fulfill() }
        let rejected = expectation(description: "late result not consumed")
        rejected.isInverted = true
        flow.login(method: .email, input: "a@b.com", password: "old") { _ in rejected.fulfill() }
        wait(for: [started], timeout: 3)
        current = false
        callback?(.success(ClawIdentitySessionResult(user: "usrSyntheticA", token: "dGVzdA==", expires: nil)))
        wait(for: [rejected], timeout: 0.1)
        XCTAssertFalse(flow.active)
        XCTAssertTrue(committed.isEmpty)
        XCTAssertEqual(retired, 1)
    }
    func testLeavingFlowRetiresStartedSessionAndDiscardsLateResult() throws {
        try prepare()
        IdentityProtocol.respond { [self] _ in reply(login) }
        let started = expectation(description: "WS started")
        var callback: ((Result<ClawIdentitySessionResult, ClawIdentityError>) -> Void)?
        bridge = { _, reply in callback = reply; started.fulfill() }
        flow.login(method: .email, input: "a@b.com", password: "old") { _ in XCTFail("Left flow consumed callback") }
        wait(for: [started], timeout: 3)
        flow.invalidate()
        callback?(.success(ClawIdentitySessionResult(user: "usrSyntheticA", token: "dGVzdA==", expires: nil)))
        XCTAssertEqual(retired, 1)
        XCTAssertNil(flow.pendingPassword)
        XCTAssertTrue(committed.isEmpty)
    }
    func testLegacyBasicKeepsPasswordBytesAndRejectsUnavailableVerification() throws {
        try prepare()
        let value = " old 密码 "
        let result = awaitResult { done in
            flow.loginLegacy(username: "oldname", password: value, bridge: { username, password, reply in
                XCTAssertEqual(username, "oldname")
                XCTAssertEqual(password, value)
                reply(.failure(.legacyRecovery))
            }, completion: done)
        }
        XCTAssertThrowsError(try result.get())
        XCTAssertEqual(retired, 1)
        XCTAssertTrue(committed.isEmpty)
    }
    func testDeliveryUncertainStartsFreshChallengeOnlyAfterCooldown() throws {
        try prepare()
        var ids: [String] = []
        IdentityProtocol.respond { [self] request in
            let json = try JSONSerialization.jsonObject(with: body(request)) as! [String: Any]
            ids.append(json["request_id"] as! String)
            return reply(#"{"error":{"code":"delivery_uncertain","retry_after":60}}"#, 503)
        }
        _ = awaitResult { flow.requestCode(method: .email, input: "a@b.com",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }
        XCTAssertNil(flow.pendingChallenge)
        XCTAssertEqual(flow.retrySeconds, 60)
        XCTAssertThrowsError(try awaitResult { flow.requestCode(method: .email, input: "a@b.com",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }.get())
        XCTAssertEqual(ids.count, 1)
        time = time.addingTimeInterval(61)
        _ = awaitResult { flow.requestCode(method: .email, input: "a@b.com",
            legalResourcesAvailable: true, termsAccepted: true, completion: $0) }
        XCTAssertEqual(ids.count, 2)
        XCTAssertNotEqual(ids[0], ids[1])
    }
    func testLoginRetryAfterBlocksHTTPUntilDeadline() throws {
        try prepare()
        var sent = 0
        IdentityProtocol.respond { [self] _ in
            sent += 1
            return reply(#"{"error":{"code":"rate_limited","retry_after":30}}"#, 429)
        }
        _ = awaitResult { flow.login(method: .email, input: "a@b.com", password: "old", completion: $0) }
        XCTAssertEqual(flow.loginRetrySeconds, 30)
        _ = awaitResult { flow.login(method: .email, input: "a@b.com", password: "old", completion: $0) }
        XCTAssertEqual(sent, 1)
        time = time.addingTimeInterval(31)
        _ = awaitResult { flow.login(method: .email, input: "a@b.com", password: "old", completion: $0) }
        XCTAssertEqual(sent, 2)
    }
    func testExpiredHTTPTokenDoesNotStartWebSocket() throws {
        try prepare()
        IdentityProtocol.respond { [self] _ in reply(login.replacingOccurrences(of: "2099", with: "2000")) }
        bridge = { _, _ in XCTFail("Expired HTTP token reached WS") }
        XCTAssertThrowsError(try awaitResult { flow.login(method: .email, input: "a@b.com", password: "old", completion: $0) }.get())
        XCTAssertTrue(committed.isEmpty)
        XCTAssertEqual(retired, 0)
    }
    func testRegisteredUIDMismatchDoesNotStartWebSocket() throws {
        try verified()
        IdentityProtocol.respond { [self] _ in reply(#"{"user":"usrRegistered","registered":true,"login_required":true,"replayed":false}"#, 201) }
        _ = try awaitResult { flow.setPassword("Correct-12345", completion: $0) }.get()
        IdentityProtocol.respond { [self] _ in reply(login) }
        bridge = { _, _ in XCTFail("Different UID reached WS") }
        XCTAssertThrowsError(try awaitResult { flow.login(method: .email, input: "a@b.com", password: "Correct-12345", completion: $0) }.get())
        XCTAssertTrue(committed.isEmpty)
    }
    func testResetMutationUsesResetEndpointAndRequiresReauthentication() throws {
        flow.invalidate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdentityProtocol.self]
        service = try ClawIdentityService(origin: URL(string: "https://identity.invalid/")!,
            apiKey: "synthetic-api-key", configuration: configuration)
        flow = ClawIdentityFlow(purpose: .reset, service: service, now: { [unowned self] in self.time },
            snapshotIsCurrent: { true }, loginBridge: { _, _ in XCTFail("Reset must not auto-login") },
            retireSession: {}, commitSession: { _ in XCTFail("Reset must not persist token"); return false })
        try prepare()
        IdentityProtocol.respond { [self] _ in reply(accepted, 202) }
        _ = try awaitResult { flow.requestCode(method: .email, input: "a@b.com",
            legalResourcesAvailable: false, termsAccepted: false, completion: $0) }.get()
        IdentityProtocol.respond { [self] _ in reply(proof.replacingOccurrences(of: "register", with: "reset")) }
        _ = try awaitResult { flow.verify(code: "123456", completion: $0) }.get()
        IdentityProtocol.respond { [self] request in
            XCTAssertEqual(request.url?.path, "/v0/auth/reset-password")
            return reply(#"{"reset":true,"reauth_required":true,"replayed":false}"#)
        }
        let result = try awaitResult { flow.setPassword("Correct-12345", completion: $0) }.get()
        guard case .reset = result else { XCTFail("Expected reset result"); return }
        XCTAssertNil(flow.proof)
        XCTAssertNil(flow.pendingPassword)
        XCTAssertFalse(flow.sessionCommitted)
    }

    func testMissingAUTH404StillAllowsOriginalBasicLogin() throws {
        IdentityProtocol.respond { [self] _ in reply(#"{"error":{"code":"not_found"}}"#, 404) }
        XCTAssertThrowsError(try awaitResult { flow.prepare($0) }.get())
        XCTAssertTrue(flow.legacyLoginAvailable)
        var calls = 0
        _ = try awaitResult { done in
            flow.loginLegacy(username: "oldname", password: " old ", bridge: { name, password, reply in
                calls += 1
                XCTAssertEqual(name, "oldname")
                XCTAssertEqual(password, " old ")
                reply(.success(ClawIdentitySessionResult(user: "usrOld", token: "dGVzdA==", expires: nil)))
            }, completion: done)
        }.get()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(committed.first?.user, "usrOld")
        XCTAssertTrue(flow.sessionCommitted)
    }
    func testExplicitLegacyFalseSurvivesDisabledAUTHCapabilities() throws {
        IdentityProtocol.respond { [self] _ in
            reply(capabilities.replacingOccurrences(of: #""enabled":true"#, with: #""enabled":false"#)
                .replacingOccurrences(of: #""legacy_basic":true"#, with: #""legacy_basic":false"#))
        }
        XCTAssertThrowsError(try awaitResult { flow.prepare($0) }.get())
        XCTAssertFalse(flow.legacyLoginAvailable)
        XCTAssertEqual(flow.capabilities?.legacy_basic, false)
        XCTAssertThrowsError(try awaitResult { done in
            flow.loginLegacy(username: "oldname", password: " old ", bridge: { _, _, _ in
                XCTFail("Explicit legacy refusal dispatched basic login")
            }, completion: done)
        }.get())
        XCTAssertTrue(committed.isEmpty)
    }
    func testFailedAUTHTransportAllowsOriginalBasicButNotNewIdentityLogin() throws {
        IdentityProtocol.respond { _ in throw URLError(.cannotConnectToHost) }
        XCTAssertThrowsError(try awaitResult { flow.prepare($0) }.get())
        XCTAssertTrue(flow.legacyLoginAvailable)
        XCTAssertThrowsError(try awaitResult { flow.login(method: .email, input: "a@b.com", password: "old", completion: $0) }.get())
        XCTAssertTrue(committed.isEmpty)
    }

}
