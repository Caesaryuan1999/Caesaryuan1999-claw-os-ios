// Copyright (c) 2026 CLAW OS contributors.
import Foundation

protocol ClawAssistantCancellation: AnyObject { func cancel() }

/// Only A read/delete operations exist here. No POST, run, stream or implicit create.
final class ClawAssistantService {
    static let responseLimit = 24 * 1024 * 1024 // covers 100 * 32000 * 6 + metadata
    private let origin: URL
    private let apiKey: String
    private let token: String
    private let configuration: URLSessionConfiguration
    private let isCurrent: () -> Bool
    private let lock = NSLock()
    private var ended = false
    private var requests: [UUID: ClawAssistantHTTPTask] = [:]

    static func origin(_ url: URL) throws -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = c.scheme?.lowercased(), let host = c.host?.lowercased(),
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/",
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "::1", "[::1]"].contains(host)) else {
            throw ClawAssistantError.insecureOrigin
        }
        c.scheme = scheme; c.path = "/"
        guard let normalized = c.url else { throw ClawAssistantError.insecureOrigin }
        return normalized
    }

    init(origin: URL, apiKey: String, token: String,
         configuration: URLSessionConfiguration = .ephemeral,
         isCurrent: @escaping () -> Bool) throws {
        self.origin = try Self.origin(origin)
        guard !apiKey.isEmpty, !token.isEmpty,
              !apiKey.contains("\r"), !apiKey.contains("\n"),
              !token.contains("\r"), !token.contains("\n"),
              Data(base64Encoded: token) != nil else { throw ClawAssistantError.signInRequired }
        self.apiKey = apiKey; self.token = token; self.isCurrent = isCurrent
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.configuration.urlCache = nil
        self.configuration.httpCookieStorage = nil
        self.configuration.httpShouldSetCookies = false
        self.configuration.urlCredentialStorage = nil
        self.configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.configuration.timeoutIntervalForRequest = 20
        self.configuration.timeoutIntervalForResource = 30
        self.configuration.httpAdditionalHeaders = nil
    }

    func cancelAll() {
        lock.lock(); ended = true
        let pending = Array(requests.values); requests.removeAll()
        lock.unlock()
        pending.forEach { $0.cancel() }
    }

    @discardableResult
    func capabilities(_ completion: @escaping (Result<ClawAssistantCapabilities, ClawAssistantError>) -> Void)
        -> ClawAssistantCancellation? {
        request("capabilities", completion: completion)
    }

    @discardableResult
    func conversations(cursor: String? = nil, revision: String? = nil,
                       completion: @escaping (Result<ClawAssistantConversationPage, ClawAssistantError>) -> Void)
        -> ClawAssistantCancellation? {
        var query = [URLQueryItem(name: "limit", value: "20")]
        if let cursor = cursor, let revision = revision, ClawAssistantWire.uuid(cursor),
           ClawAssistantWire.decimal(revision) {
            query += [URLQueryItem(name: "cursor", value: cursor), URLQueryItem(name: "snapshot_revision", value: revision)]
        } else if cursor != nil || revision != nil {
            completion(.failure(.invalidResponse)); return nil
        }
        return request("conversations", query: query, completion: completion)
    }

    @discardableResult
    func messages(_ id: String, after: String = "0", revision: String? = nil,
                  completion: @escaping (Result<ClawAssistantMessagePage, ClawAssistantError>) -> Void)
        -> ClawAssistantCancellation? {
        guard ClawAssistantWire.uuid(id), ClawAssistantWire.decimal(after),
              revision.map(ClawAssistantWire.decimal) ?? (after == "0") else {
            completion(.failure(.invalidResponse)); return nil
        }
        var query = [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "after_seq", value: after)]
        if let revision = revision { query.append(URLQueryItem(name: "snapshot_revision", value: revision)) }
        return request("conversations/\(id)/messages", query: query, completion: completion)
    }

    @discardableResult
    func delete(_ id: String, completion: @escaping (Result<ClawAssistantDeleteReceipt, ClawAssistantError>) -> Void)
        -> ClawAssistantCancellation? {
        guard ClawAssistantWire.uuid(id) else { completion(.failure(.invalidResponse)); return nil }
        return request("conversations/\(id)", method: "DELETE", completion: completion)
    }

    private func request<T: ClawAssistantValidated>(_ path: String, method: String = "GET",
        query: [URLQueryItem] = [], completion: @escaping (Result<T, ClawAssistantError>) -> Void)
        -> ClawAssistantCancellation? {
        guard isCurrent() else { completion(.failure(.retired)); return nil }
        guard var parts = URLComponents(url: origin.appendingPathComponent("v0/ai/" + path), resolvingAgainstBaseURL: false) else {
            completion(.failure(.invalidResponse)); return nil
        }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { completion(.failure(.invalidResponse)); return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("token " + token, forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "X-Tinode-APIKey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let id = UUID()
        let task = ClawAssistantHTTPTask(request: request, configuration: configuration) { [weak self] result in
            guard let self = self else { return }
            self.lock.lock(); self.requests.removeValue(forKey: id); let ended = self.ended; self.lock.unlock()
            guard !ended, self.isCurrent() else { completion(.failure(.retired)); return }
            completion(result.flatMap { response in
                do {
                    let value = try JSONDecoder().decode(T.self, from: response)
                    try value.validate()
                    return .success(value)
                } catch let error as ClawAssistantError { return .failure(error) }
                  catch { return .failure(.invalidResponse) }
            })
        }
        lock.lock()
        guard !ended else { lock.unlock(); completion(.failure(.retired)); return nil }
        requests[id] = task
        lock.unlock()
        // HTTPTask synchronizes start/cancel. A retirement before start cannot resurrect it.
        task.start()
        return task
    }
}

/// Each bounded request owns an ephemeral session; redirect and cache decisions are real delegates.
final class ClawAssistantHTTPTask: NSObject, URLSessionDataDelegate, ClawAssistantCancellation {
    private let lock = NSRecursiveLock()
    private let request: URLRequest
    private let configuration: URLSessionConfiguration
    private var completion: ((Result<Data, ClawAssistantError>) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var data = Data()
    private var response: HTTPURLResponse?
    private var finished = false

    init(request: URLRequest, configuration: URLSessionConfiguration,
         completion: @escaping (Result<Data, ClawAssistantError>) -> Void) {
        self.request = request; self.configuration = configuration; self.completion = completion
    }
    func start() {
        lock.lock(); defer { lock.unlock() }
        guard !finished, session == nil else { return }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task; task.resume()
    }
    func cancel() { finish(.failure(.transport)) }

    private func finish(_ result: Result<Data, ClawAssistantError>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let completion = self.completion; self.completion = nil
        let session = self.session; self.session = nil
        self.task = nil; data.removeAll(keepingCapacity: false)
        lock.unlock()
        session?.invalidateAndCancel()
        completion?(result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(.invalidResponse))
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.url == request.url else {
            completionHandler(.cancel); finish(.failure(.invalidResponse)); return
        }
        // Authentication failure is authoritative even when a gateway supplies no
        // JSON envelope. Hide this scope before reading an untrusted error body.
        if http.statusCode == 401 {
            completionHandler(.cancel); finish(.failure(.server(401, "authentication_required"))); return
        }
        guard http.mimeType?.lowercased() == "application/json" else {
            completionHandler(.cancel); finish(.failure(.invalidResponse)); return
        }
        guard http.expectedContentLength <= Int64(ClawAssistantService.responseLimit) else {
            completionHandler(.cancel); finish(.failure(.responseTooLarge)); return
        }
        lock.lock(); self.response = http; let ended = finished; lock.unlock()
        completionHandler(ended ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count <= ClawAssistantService.responseLimit - self.data.count else {
            lock.unlock(); finish(.failure(.responseTooLarge)); return
        }
        self.data.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let response = self.response; let body = data; let ended = finished; lock.unlock()
        guard !ended else { return }
        guard error == nil else { finish(.failure(.transport)); return }
        guard let response = response else { finish(.failure(.invalidResponse)); return }
        guard response.statusCode == 200 else {
            struct Envelope: Decodable { struct Detail: Decodable { let code: String }; let error: Detail }
            let code = (try? JSONDecoder().decode(Envelope.self, from: body))?.error.code ?? ""
            // Do not pass arbitrary server text into logs or UI.
            let allowed = ["invalid_request", "authentication_required", "permission_denied", "not_found",
                           "conversation_deleted", "snapshot_changed", "request_conflict", "body_too_large",
                           "unsupported_media_type", "history_unavailable", "provider_not_configured", "internal_error"]
            if response.statusCode == 401 { finish(.failure(.server(401, "authentication_required"))) }
            else if response.statusCode == 409 && code == "snapshot_changed" { finish(.failure(.historyChanged)) }
            else if allowed.contains(code) { finish(.failure(.server(response.statusCode, code))) }
            else { finish(.failure(.invalidResponse)) }
            return
        }
        finish(.success(body))
    }
}
