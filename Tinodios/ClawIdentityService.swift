//
// AUTH-A1 transport. Credentials exist only in request bodies and ephemeral memory.
//
import Foundation

enum ClawIdentityMethod: String, Codable { case tel, email }
enum ClawIdentityPurpose: String, Codable { case register, reset }

struct ClawIdentityCapabilities: Decodable {
    struct Methods: Decodable { let email: Bool; let tel: Bool }
    struct Password: Decodable {
        let min_length: Int; let max_length: Int; let alphabet: String
    }
    let version: String
    let enabled: Bool
    let methods: Methods
    let flow: String
    let code_length: Int
    let challenge_ttl: Int
    let proof_ttl: Int
    let resend_after: Int
    let password: Password
    let legacy_basic: Bool
    let test_mode: Bool

    var supported: Bool {
        enabled && version == "claw-auth-v1" && flow == "verify_then_password"
            && code_length == 6 && challenge_ttl > 0 && proof_ttl > 0 && resend_after > 0
            && challenge_ttl <= 86400 && proof_ttl <= 86400 && resend_after <= 86400
            && password.min_length == 12 && password.max_length == 64
            && password.alphabet == "ascii_printable_no_space"
    }
    func canDeliver(_ method: ClawIdentityMethod) -> Bool {
        method == .tel ? methods.tel : methods.email
    }
}

struct ClawIdentityChallenge: Decodable {
    let challenge_id: String; let expires_in: Int; let retry_after: Int; let delivery: String
}
struct ClawIdentityProof: Decodable {
    let proof: String; let expires_in: Int; let purpose: ClawIdentityPurpose
}
struct ClawIdentityRegistration: Decodable {
    let user: String; let registered: Bool; let login_required: Bool; let replayed: Bool
}
struct ClawIdentityReset: Decodable {
    let reset: Bool; let reauth_required: Bool; let replayed: Bool
}
struct ClawIdentityLogin: Decodable {
    let user: String; let token: String; let expires: String
}
struct ClawIdentityChallengeRequest: Encodable, Equatable {
    let request_id: String; let purpose: ClawIdentityPurpose; let method: ClawIdentityMethod; let value: String
}
struct ClawIdentityVerifyRequest: Encodable {
    let request_id: String; let challenge_id: String; let code: String
}
struct ClawIdentityPasswordRequest: Encodable {
    let request_id: String; let proof: String; let password: String
}
struct ClawIdentityLoginRequest: Encodable {
    let method: ClawIdentityMethod; let value: String; let password: String
}

enum ClawIdentityError: Error {
    case unavailable
    case invalidIdentifier
    case invalidPassword
    case invalidCode
    case invalidResponse
    case transport
    case capabilitiesConnection
    case server(code: String, retryAfter: Int?)
    case ended
    case legacyRecovery

    var code: String? {
        if case let .server(code, _) = self { return code }
        return nil
    }
    var retryAfter: Int? {
        if case let .server(_, delay) = self { return delay }
        return nil
    }
    var message: String {
        switch self {
        case .unavailable: return "身份服务暂不可用"
        case .invalidIdentifier: return "请检查手机号国家码或邮箱格式"
        case .invalidPassword: return "请设置 12–64 位密码，仅使用英文字母、数字或符号，不含空格"
        case .invalidCode: return "请输入 6 位数字验证码"
        case .invalidResponse: return "身份服务响应无效，请稍后重试"
        case .transport: return "网络请求结果未确认，请检查连接后按页面提示操作"
        case .capabilitiesConnection: return "暂时无法连接身份服务，请检查网络和连接设置后重试。"
        case .ended: return "操作已结束，请重新开始"
        case .legacyRecovery: return "此原账号需要完成旧凭据验证。该验证方式暂不可用，请联系管理员恢复账号。"
        case let .server(code, _):
            switch code {
            case "auth_invalid": return "手机号、邮箱或密码不正确"
            case "invalid_identifier": return "请检查手机号国家码或邮箱格式"
            case "password_policy": return ClawIdentityError.invalidPassword.message
            case "challenge_invalid": return "验证码不正确，请重新输入"
            case "challenge_expired": return "验证码已过期，请重新获取"
            case "challenge_used": return "验证码已使用，请重新获取"
            case "challenge_attempts_exceeded": return "验证码尝试次数已用尽，请重新获取"
            case "proof_expired", "proof_invalid", "proof_used": return "身份验证已失效，请重新获取验证码"
            case "identity_in_use": return "此手机号或邮箱已有账号，请登录或找回密码"
            case "request_conflict": return "请求内容已变化，请重新开始"
            case "rate_limited": return "操作过于频繁，请等待页面倒计时结束"
            case "delivery_unavailable": return "此验证方式暂不可用"
            case "delivery_failed": return "验证码未能提交，请稍后重试"
            case "delivery_uncertain": return "验证码提交结果未确认，请等待后重新获取"
            default: return "身份服务暂不可用"
            }
        }
    }
}

enum ClawIdentityInput {
    private static let asciiWhitespace = CharacterSet(charactersIn: " \t\r\n\u{000B}\u{000C}")
    static func normalize(_ input: String, method: ClawIdentityMethod, countryCode: String = "+86") throws -> String {
        let value = input.trimmingCharacters(in: asciiWhitespace)
        if method == .tel {
            let full = value.hasPrefix("+") ? value : countryCode + value
            guard full.range(of: "^\\+[1-9][0-9]{6,14}$", options: .regularExpression) != nil else {
                throw ClawIdentityError.invalidIdentifier
            }
            return full
        }
        // Reject Unicode before lowercasing (e.g. Kelvin sign must not become ASCII k).
        guard value.utf8.count <= 128,
              value.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw ClawIdentityError.invalidIdentifier
        }
        let normalized = value.lowercased()
        guard normalized.utf8.count <= 128 else {
            throw ClawIdentityError.invalidIdentifier
        }
        let parts = normalized.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw ClawIdentityError.invalidIdentifier }
        let local = String(parts[0])
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard !local.isEmpty, local.utf8.count <= 64,
              local.range(of: "^[A-Za-z0-9.!#$%&'*+/=?^_\u{0060}{|}~-]+$", options: .regularExpression) != nil,
              !local.hasPrefix("."), !local.hasSuffix("."), !local.contains(".."), labels.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                      && String(label).range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil
              }) else { throw ClawIdentityError.invalidIdentifier }
        return normalized
    }
    static func newPasswordIsValid(_ value: String) -> Bool {
        (12...64).contains(value.utf8.count) && value.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
    }
    static func codeIsValid(_ value: String) -> Bool {
        value.utf8.count == 6 && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}

final class ClawIdentityService: NSObject, URLSessionTaskDelegate {
    struct FailureEnvelope: Decodable {
        struct Detail: Decodable { let code: String; let retry_after: Int? }
        let error: Detail
    }
    let baseURL: URL
    private let apiKey: String
    private let configuration: URLSessionConfiguration
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

    init(origin: URL, apiKey: String, configuration: URLSessionConfiguration = .ephemeral) throws {
        guard let components = URLComponents(url: origin, resolvingAgainstBaseURL: true),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.scheme == "https" || (components.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else {
            throw ClawIdentityError.unavailable
        }
        baseURL = origin.appendingPathComponent("v0/auth", isDirectory: true)
        self.apiKey = apiKey
        self.configuration = configuration
        super.init()
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
    }

    func cancel() { session.invalidateAndCancel() }

    // Auth redirects must never forward credentials or the API key to another URL.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func capabilities(completion: @escaping (Result<ClawIdentityCapabilities, ClawIdentityError>) -> Void) {
        request("capabilities", data: nil, expected: [200]) {
            (result: Result<ClawIdentityCapabilities, ClawIdentityError>) in
            // This read-only check cannot leave a submitted identity mutation uncertain.
            if case .failure(.transport) = result {
                completion(.failure(.capabilitiesConnection))
            } else {
                completion(result)
            }
        }
    }
    func challenge(_ value: ClawIdentityChallengeRequest, completion: @escaping (Result<ClawIdentityChallenge, ClawIdentityError>) -> Void) {
        encode("challenge", value: value, expected: [202], completion: completion)
    }
    func verify(_ value: ClawIdentityVerifyRequest, completion: @escaping (Result<ClawIdentityProof, ClawIdentityError>) -> Void) {
        encode("verify", value: value, expected: [200], completion: completion)
    }
    func register(_ value: ClawIdentityPasswordRequest, completion: @escaping (Result<ClawIdentityRegistration, ClawIdentityError>) -> Void) {
        encode("register", value: value, expected: [200, 201], completion: completion)
    }
    func reset(_ value: ClawIdentityPasswordRequest, completion: @escaping (Result<ClawIdentityReset, ClawIdentityError>) -> Void) {
        encode("reset-password", value: value, expected: [200], completion: completion)
    }
    func login(_ value: ClawIdentityLoginRequest, completion: @escaping (Result<ClawIdentityLogin, ClawIdentityError>) -> Void) {
        encode("password-login", value: value, expected: [200], completion: completion)
    }
    private func encode<Request: Encodable, Response: Decodable>(_ endpoint: String, value: Request, expected: Set<Int>,
            completion: @escaping (Result<Response, ClawIdentityError>) -> Void) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(value), data.count <= 8192 else {
            completion(.failure(.invalidResponse)); return
        }
        request(endpoint, data: data, expected: expected, completion: completion)
    }
    private func request<Response: Decodable>(_ endpoint: String, data: Data?, expected: Set<Int>,
            completion: @escaping (Result<Response, ClawIdentityError>) -> Void) {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = data == nil ? "GET" : "POST"
        request.httpBody = data
        request.setValue(apiKey, forHTTPHeaderField: "X-Tinode-APIKey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if data != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        session.dataTask(with: request) { data, response, error in
            guard error == nil else { completion(.failure(.transport)); return }
            guard let response = response as? HTTPURLResponse, response.url == url,
                  let data = data, data.count <= 65536 else {
                completion(.failure(.invalidResponse)); return
            }
            guard expected.contains(response.statusCode) else {
                if let failure = try? JSONDecoder().decode(FailureEnvelope.self, from: data) {
                    let delay = failure.error.retry_after.flatMap { (0...86400).contains($0) ? $0 : nil }
                    completion(.failure(.server(code: failure.error.code, retryAfter: delay)))
                } else {
                    completion(.failure(.invalidResponse))
                }
                return
            }
            guard let value = try? JSONDecoder().decode(Response.self, from: data) else {
                completion(.failure(.invalidResponse)); return
            }
            completion(.success(value))
        }.resume()
    }
}
