//
// AUTH-A1 state. No UIKit, SDK or persistent credentials; shared with native tests.
//
import Foundation

struct ClawIdentitySessionResult {
    let user: String
    let token: String
    let expires: Date?
}

final class ClawIdentityFlow {
    enum PasswordOutcome { case registered(String); case reset }
    typealias LoginBridge = (ClawIdentityLogin, @escaping (Result<ClawIdentitySessionResult, ClawIdentityError>) -> Void) -> Void

    let purpose: ClawIdentityPurpose
    let service: ClawIdentityService
    private let now: () -> Date
    private let snapshotIsCurrent: () -> Bool
    private let loginBridge: LoginBridge
    private let retireSession: () -> Void
    private let commitSession: (ClawIdentitySessionResult) -> Bool

    private(set) var active = true
    private(set) var busy = false
    private(set) var capabilities: ClawIdentityCapabilities?
    private(set) var method: ClawIdentityMethod?
    private(set) var value: String?
    private(set) var challenge: ClawIdentityChallenge?
    private(set) var challengeDeadline: Date?
    private(set) var cooldownDeadline: Date?
    private var loginCooldownDeadline: Date?
    private var mutationCooldownDeadline: Date?
    private(set) var proof: ClawIdentityProof?
    private(set) var proofDeadline: Date?
    private(set) var pendingChallenge: ClawIdentityChallengeRequest?
    private(set) var pendingPassword: ClawIdentityPasswordRequest?
    private(set) var registeredUser: String?
    private(set) var sessionCommitted = false
    private var websocketStarted = false
    private var generation = UUID()

    init(purpose: ClawIdentityPurpose, service: ClawIdentityService,
         now: @escaping () -> Date = Date.init,
         snapshotIsCurrent: @escaping () -> Bool,
         loginBridge: @escaping LoginBridge,
         retireSession: @escaping () -> Void,
         commitSession: @escaping (ClawIdentitySessionResult) -> Bool) {
        self.purpose = purpose
        self.service = service
        self.now = now
        self.snapshotIsCurrent = snapshotIsCurrent
        self.loginBridge = loginBridge
        self.retireSession = retireSession
        self.commitSession = commitSession
    }

    deinit {
        service.cancel()
        if active && websocketStarted && !sessionCommitted { retireSession() }
    }

    var isCurrent: Bool { active && snapshotIsCurrent() }
    private func seconds(until deadline: Date?) -> Int { max(0, Int(ceil((deadline ?? now()).timeIntervalSince(now())))) }
    var retrySeconds: Int { seconds(until: cooldownDeadline) }
    var loginRetrySeconds: Int { seconds(until: loginCooldownDeadline) }
    var mutationRetrySeconds: Int { seconds(until: mutationCooldownDeadline) }
    var canVerify: Bool {
        challenge != nil && (challengeDeadline ?? .distantPast) > now() && pendingChallenge == nil
    }
    var canSetPassword: Bool { proof != nil && (proofDeadline ?? .distantPast) > now() }

    func invalidate() {
        guard active else { return }
        active = false
        generation = UUID()
        service.cancel()
        pendingChallenge = nil
        pendingPassword = nil
        challenge = nil
        proof = nil
        value = nil
        if websocketStarted && !sessionCommitted { retireSession() }
    }

    // Every response is consumed on the main queue against its original screen/host/session.
    private func consume<T>(_ result: Result<T, ClawIdentityError>, generation: UUID,
                            _ completion: @escaping (Result<T, ClawIdentityError>) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.generation == generation, self.active else { return }
            guard self.snapshotIsCurrent() else { self.invalidate(); return }
            self.busy = false
            completion(result)
        }
    }

    func prepare(_ completion: @escaping (Result<ClawIdentityCapabilities, ClawIdentityError>) -> Void) {
        guard isCurrent, !busy else { completion(.failure(.ended)); return }
        if let capabilities = capabilities { completion(.success(capabilities)); return }
        busy = true
        let generation = generation
        service.capabilities { [weak self] result in
            self?.consume(result, generation: generation) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case let .success(capabilities):
                    guard capabilities.supported else { completion(.failure(.unavailable)); return }
                    self.capabilities = capabilities
                    completion(.success(capabilities))
                case let .failure(error): completion(.failure(error))
                }
            }
        }
    }

    func requestCode(method: ClawIdentityMethod, input: String, countryCode: String = "+86",
                     legalResourcesAvailable: Bool, termsAccepted: Bool,
                     completion: @escaping (Result<ClawIdentityChallenge, ClawIdentityError>) -> Void) {
        guard isCurrent, !busy else { completion(.failure(.ended)); return }
        guard let capabilities = capabilities, capabilities.supported, capabilities.canDeliver(method),
              purpose != .register || (legalResourcesAvailable && termsAccepted) else {
            completion(.failure(.unavailable)); return
        }
        let normalized: String
        do { normalized = try ClawIdentityInput.normalize(input, method: method, countryCode: countryCode) }
        catch { completion(.failure(.invalidIdentifier)); return }
        let request: ClawIdentityChallengeRequest
        if let pending = pendingChallenge {
            // An uncertain submission is retried only by an explicit user action with identical bytes.
            guard pending.method == method, pending.value == normalized else {
                completion(.failure(.server(code: "request_conflict", retryAfter: nil))); return
            }
            request = pending
        } else {
            guard retrySeconds == 0 else {
                completion(.failure(.server(code: "rate_limited", retryAfter: retrySeconds))); return
            }
            request = ClawIdentityChallengeRequest(request_id: UUID().uuidString.lowercased(),
                purpose: purpose, method: method, value: normalized)
        }
        self.method = method
        value = normalized
        pendingChallenge = request
        challenge = nil
        proof = nil
        proofDeadline = nil
        busy = true
        let generation = generation
        service.challenge(request) { [weak self] result in
            self?.consume(result, generation: generation) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case let .success(response):
                    guard !response.challenge_id.isEmpty, response.delivery == "accepted",
                          (1...capabilities.challenge_ttl).contains(response.expires_in),
                          (0...86400).contains(response.retry_after) else {
                        completion(.failure(.invalidResponse)); return
                    }
                    self.pendingChallenge = nil
                    self.challenge = response
                    self.challengeDeadline = self.now().addingTimeInterval(TimeInterval(response.expires_in))
                    self.cooldownDeadline = self.now().addingTimeInterval(TimeInterval(response.retry_after))
                    completion(.success(response))
                case let .failure(error):
                    switch error {
                    case .transport, .invalidResponse:
                        // Keep the exact request for explicit confirmation retry; never auto-send a new request.
                        break
                    default:
                        self.pendingChallenge = nil
                        let delay = error.retryAfter ?? capabilities.resend_after
                        self.cooldownDeadline = self.now().addingTimeInterval(TimeInterval(delay))
                    }
                    completion(.failure(error))
                }
            }
        }
    }

    func verify(code: String, completion: @escaping (Result<ClawIdentityProof, ClawIdentityError>) -> Void) {
        guard isCurrent, !busy else { completion(.failure(.ended)); return }
        guard canVerify, let challenge = challenge else {
            completion(.failure(.server(code: "challenge_expired", retryAfter: nil))); return
        }
        guard ClawIdentityInput.codeIsValid(code) else { completion(.failure(.invalidCode)); return }
        let request = ClawIdentityVerifyRequest(request_id: UUID().uuidString.lowercased(),
                                                challenge_id: challenge.challenge_id, code: code)
        busy = true
        let generation = generation
        service.verify(request) { [weak self] result in
            self?.consume(result, generation: generation) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case let .success(response):
                    guard response.purpose == self.purpose, !response.proof.isEmpty,
                          response.expires_in > 0, response.expires_in <= (self.capabilities?.proof_ttl ?? 0) else {
                        self.challenge = nil
                        completion(.failure(.invalidResponse)); return
                    }
                    self.challenge = nil
                    self.proof = response
                    self.proofDeadline = self.now().addingTimeInterval(TimeInterval(response.expires_in))
                    completion(.success(response))
                case let .failure(error):
                    if error.code != "challenge_invalid" && error.code != "rate_limited" {
                        // A lost verify response cannot recover the original proof: require a new challenge.
                        self.challenge = nil
                    }
                    if let delay = error.retryAfter {
                        self.cooldownDeadline = self.now().addingTimeInterval(TimeInterval(delay))
                    }
                    completion(.failure(error))
                }
            }
        }
    }

    func setPassword(_ password: String,
                     completion: @escaping (Result<PasswordOutcome, ClawIdentityError>) -> Void) {
        guard isCurrent, !busy else { completion(.failure(.ended)); return }
        guard mutationRetrySeconds == 0 else {
            completion(.failure(.server(code: "rate_limited", retryAfter: mutationRetrySeconds))); return
        }
        let request: ClawIdentityPasswordRequest
        if let pending = pendingPassword {
            guard password == pending.password else {
                completion(.failure(.server(code: "request_conflict", retryAfter: nil))); return
            }
            // A committed operation can be replayed after proof expiry; only this exact pending payload qualifies.
            request = pending
        } else {
            guard canSetPassword, let proof = proof else {
                completion(.failure(.server(code: "proof_expired", retryAfter: nil))); return
            }
            guard ClawIdentityInput.newPasswordIsValid(password) else {
                completion(.failure(.invalidPassword)); return
            }
            request = ClawIdentityPasswordRequest(request_id: UUID().uuidString.lowercased(),
                                                  proof: proof.proof, password: password)
            pendingPassword = request
        }
        busy = true
        let generation = generation
        let completed: (Result<PasswordOutcome, ClawIdentityError>) -> Void = { [weak self] result in
            self?.consume(result, generation: generation) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.pendingPassword = nil
                    self.proof = nil
                    self.proofDeadline = nil
                    if case let .success(.registered(uid)) = result { self.registeredUser = uid }
                case let .failure(error):
                    if let delay = error.retryAfter {
                        self.mutationCooldownDeadline = self.now().addingTimeInterval(TimeInterval(delay))
                    }
                    if let code = error.code, !["auth_unavailable", "delivery_uncertain"].contains(code) {
                        self.pendingPassword = nil
                        if ["proof_invalid", "proof_expired", "proof_used", "request_conflict"].contains(code) {
                            self.proof = nil
                        }
                    }
                }
                completion(result)
            }
        }
        if purpose == .register {
            service.register(request) { result in
                completed(result.flatMap { value in
                    guard value.registered, value.login_required, !value.user.isEmpty else { return .failure(.invalidResponse) }
                    return .success(.registered(value.user))
                })
            }
        } else {
            service.reset(request) { result in
                completed(result.flatMap { value in
                    guard value.reset, value.reauth_required else { return .failure(.invalidResponse) }
                    return .success(.reset)
                })
            }
        }
    }

    func login(method: ClawIdentityMethod, input: String, countryCode: String = "+86", password: String,
               completion: @escaping (Result<ClawIdentitySessionResult, ClawIdentityError>) -> Void) {
        guard isCurrent, !busy else { completion(.failure(.ended)); return }
        guard capabilities?.supported == true else { completion(.failure(.unavailable)); return }
        guard loginRetrySeconds == 0 else {
            completion(.failure(.server(code: "rate_limited", retryAfter: loginRetrySeconds))); return
        }
        guard !password.isEmpty else { completion(.failure(.server(code: "auth_invalid", retryAfter: nil))); return }
        let normalized: String
        do { normalized = try ClawIdentityInput.normalize(input, method: method, countryCode: countryCode) }
        catch { completion(.failure(.invalidIdentifier)); return }
        // Existing password bytes are intentionally neither trimmed nor checked against new-password policy.
        let request = ClawIdentityLoginRequest(method: method, value: normalized, password: password)
        busy = true
        let generation = generation
        service.login(request) { [weak self] result in
            self?.consume(result, generation: generation) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case let .failure(error):
                    if let delay = error.retryAfter {
                        self.loginCooldownDeadline = self.now().addingTimeInterval(TimeInterval(delay))
                    }
                    completion(.failure(error))
                case let .success(http):
                    let formatter = ISO8601DateFormatter()
                    let expiration = formatter.date(from: http.expires) ?? {
                        formatter.formatOptions.insert(.withFractionalSeconds)
                        return formatter.date(from: http.expires)
                    }()
                    guard !http.user.isEmpty, !http.token.isEmpty, Data(base64Encoded: http.token) != nil,
                          let expiration = expiration, expiration > self.now(),
                          self.registeredUser == nil || self.registeredUser == http.user else {
                        completion(.failure(.invalidResponse)); return
                    }
                    self.busy = true
                    self.websocketStarted = true
                    self.loginBridge(http) { [weak self] response in
                        self?.consume(response, generation: generation) { [weak self] response in
                            guard let self = self else { return }
                            switch response {
                            case let .success(session):
                                guard session.user == http.user, !session.token.isEmpty,
                                      Data(base64Encoded: session.token) != nil else {
                                    self.retireSession()
                                    completion(.failure(.invalidResponse)); return
                                }
                                let confirmed = ClawIdentitySessionResult(user: session.user, token: session.token,
                                    expires: session.expires ?? expiration)
                                guard self.commitSession(confirmed) else {
                                    self.retireSession()
                                    completion(.failure(.ended)); return
                                }
                                self.sessionCommitted = true
                                completion(.success(confirmed))
                            case let .failure(error):
                                self.retireSession()
                                completion(.failure(error))
                            }
                        }
                    }
                }
            }
        }
    }
    // Compatibility is only for existing basic accounts; no legacy registration or stock OTP.
    func loginLegacy(username: String, password: String,
                     bridge: @escaping (String, String, @escaping (Result<ClawIdentitySessionResult, ClawIdentityError>) -> Void) -> Void,
                     completion: @escaping (Result<ClawIdentitySessionResult, ClawIdentityError>) -> Void) {
        guard isCurrent, !busy else { completion(.failure(.ended)); return }
        guard capabilities?.supported == true, capabilities?.legacy_basic == true else {
            completion(.failure(.unavailable)); return
        }
        guard !username.isEmpty, !password.isEmpty else { completion(.failure(.invalidIdentifier)); return }
        busy = true
        websocketStarted = true
        let generation = generation
        bridge(username, password) { [weak self] response in
            self?.consume(response, generation: generation) { [weak self] response in
                guard let self = self else { return }
                switch response {
                case let .success(session):
                    guard !session.user.isEmpty, !session.token.isEmpty,
                          Data(base64Encoded: session.token) != nil,
                          self.commitSession(session) else {
                        self.retireSession()
                        completion(.failure(.ended)); return
                    }
                    self.sessionCommitted = true
                    completion(.success(session))
                case let .failure(error):
                    self.retireSession()
                    completion(.failure(error))
                }
            }
        }
    }

}
