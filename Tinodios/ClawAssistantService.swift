// Copyright (c) 2026 CLAW OS contributors.
import Foundation

protocol ClawAssistantCancellation: AnyObject { func cancel() }

/// A operations remain unchanged. B entry points require explicit protocol negotiation.
final class ClawAssistantService {
    static let responseLimit = 24 * 1024 * 1024 // covers 100 * 32000 * 6 + metadata
    private let origin: URL
    private let apiKey: String
    private let token: String
    private let configuration: URLSessionConfiguration
    private let isCurrent: () -> Bool
    private let lock = NSLock()
    private var ended = false
    private var requests: [UUID: ClawAssistantCancellation] = [:]

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

    @discardableResult
    func createConversation(_ id: String, capabilities: ClawAssistantCapabilities,
        retrySubmission: Bool = false,
        completion: @escaping (Result<ClawAssistantConversationPageValue, ClawAssistantError>) -> Void)
        -> ClawAssistantCancellation? {
        guard (try? capabilities.validateRuns()) != nil, capabilities.generation.available || retrySubmission,
              ClawAssistantWire.uuid(id) else { completion(.failure(.unavailable)); return nil }
        let body = Data(("{\"conversation_id\":\"" + id + "\"}").utf8)
        return request("conversations", method: "POST", body: body, successCodes: [200, 201], completion: completion)
    }

    @discardableResult
    func submitRun(_ id: String, input: ClawAssistantRunInput, capabilities: ClawAssistantCapabilities,
        retrySubmission: Bool = false,
        completion: @escaping (Result<ClawAssistantRunReceipt, ClawAssistantError>) -> Void)
        -> ClawAssistantCancellation? {
        guard (try? capabilities.validateRuns()) != nil,
              capabilities.generation.available || retrySubmission, ClawAssistantWire.uuid(id) else {
            completion(.failure(.unavailable)); return nil
        }
        do {
            return request("conversations/\(id)/runs", method: "POST", body: try input.body(),
                           successCodes: [200, 202], completion: completion)
        } catch let error as ClawAssistantError { completion(.failure(error)); return nil }
          catch { completion(.failure(.invalidResponse)); return nil }
    }

    @discardableResult
    func run(_ id: String, runID: String, capabilities: ClawAssistantCapabilities, stop: Bool = false,
        completion: @escaping (Result<ClawAssistantRunSnapshot, ClawAssistantError>) -> Void)
        -> ClawAssistantCancellation? {
        guard (try? capabilities.validateRuns()) != nil, ClawAssistantWire.uuid(id), ClawAssistantWire.uuid(runID) else {
            completion(.failure(.incompatible)); return nil
        }
        return request("conversations/\(id)/runs/\(runID)" + (stop ? "/stop" : ""),
                       method: stop ? "POST" : "GET", completion: completion)
    }

    @discardableResult
    func events(_ id: String, runID: String, after: String, capabilities: ClawAssistantCapabilities,
        completion: @escaping (Result<ClawAssistantRunEvents, ClawAssistantError>) -> Void)
        -> ClawAssistantCancellation? {
        guard (try? capabilities.validateRuns()) != nil, ClawAssistantWire.uuid(id), ClawAssistantWire.uuid(runID),
              ClawAssistantWire.decimal(after) else { completion(.failure(.invalidResponse)); return nil }
        return request("conversations/\(id)/runs/\(runID)/events",
                       query: [URLQueryItem(name: "after_event", value: after), URLQueryItem(name: "limit", value: "100")],
                       completion: { (result: Result<ClawAssistantRunEvents, ClawAssistantError>) in
            completion(result.flatMap { value in
                guard value.conversation_id == id, value.run_id == runID,
                      value.items.first.map({ ClawAssistantRunWire.next(after) == $0.id }) ?? true else {
                    return .failure(.invalidResponse)
                }
                return .success(value)
            })
        })
    }

    @discardableResult
    func stream(_ id: String, runID: String, after: String, capabilities: ClawAssistantCapabilities,
        event: @escaping (ClawAssistantRunEvent) -> Void,
        completion: @escaping (ClawAssistantStreamEnd) -> Void) -> ClawAssistantCancellation? {
        guard (try? capabilities.validateRuns()) != nil, ClawAssistantWire.uuid(id), ClawAssistantWire.uuid(runID),
              ClawAssistantWire.decimal(after) else { completion(.failure(.invalidResponse)); return nil }
        guard capabilities.stream.available else {
            completion(.failure(.server(503, "history_unavailable"))); return nil
        }
        guard isCurrent() else { completion(.failure(.retired)); return nil }
        let requestID = UUID()
        var outgoing = authorizedRequest(origin.appendingPathComponent("v0/ai/conversations/\(id)/runs/\(runID)/stream"),
                                         method: "GET", body: nil)
        outgoing.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        outgoing.setValue(after, forHTTPHeaderField: "Last-Event-ID")
        let task = ClawAssistantStream(request: outgoing, configuration: configuration, isCurrent: isCurrent,
            event: event, completion: { [weak self] result in
                guard let self = self else { return }
                self.lock.lock(); self.requests.removeValue(forKey: requestID); self.lock.unlock()
                completion(result)
            })
        lock.lock()
        guard !ended else { lock.unlock(); completion(.failure(.retired)); return nil }
        requests[requestID] = task; lock.unlock()
        task.start(); return task
    }

    private func authorizedRequest(_ url: URL, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.setValue("token " + token, forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "X-Tinode-APIKey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private func request<T: ClawAssistantValidated>(_ path: String, method: String = "GET",
        query: [URLQueryItem] = [], body: Data? = nil, successCodes: Set<Int> = [200],
        completion: @escaping (Result<T, ClawAssistantError>) -> Void)
        -> ClawAssistantCancellation? {
        guard isCurrent() else { completion(.failure(.retired)); return nil }
        guard var parts = URLComponents(url: origin.appendingPathComponent("v0/ai/" + path), resolvingAgainstBaseURL: false) else {
            completion(.failure(.invalidResponse)); return nil
        }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { completion(.failure(.invalidResponse)); return nil }
        let request = authorizedRequest(url, method: method, body: body)
        let id = UUID()
        let task = ClawAssistantHTTPTask(request: request, configuration: configuration, successCodes: successCodes) { [weak self] result in
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
    private let successCodes: Set<Int>
    private var completion: ((Result<Data, ClawAssistantError>) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var data = Data()
    private var response: HTTPURLResponse?
    private var finished = false

    init(request: URLRequest, configuration: URLSessionConfiguration, successCodes: Set<Int> = [200],
         completion: @escaping (Result<Data, ClawAssistantError>) -> Void) {
        self.request = request; self.configuration = configuration; self.completion = completion
        self.successCodes = successCodes
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
        guard successCodes.contains(response.statusCode) else {
            struct Envelope: Decodable { struct Detail: Decodable { let code: String }; let error: Detail }
            let code = (try? JSONDecoder().decode(Envelope.self, from: body))?.error.code ?? ""
            // Do not pass arbitrary server text into logs or UI.
            let allowed = ["invalid_request", "authentication_required", "permission_denied", "not_found",
                           "conversation_deleted", "snapshot_changed", "request_conflict", "body_too_large",
                           "unsupported_media_type", "history_unavailable", "provider_not_configured", "internal_error",
                           "execution_unavailable", "run_in_progress", "retry_not_allowed", "context_too_large", "cursor_ahead"]
            if response.statusCode == 401 { finish(.failure(.server(401, "authentication_required"))) }
            else if response.statusCode == 409 && code == "snapshot_changed" { finish(.failure(.historyChanged)) }
            else if allowed.contains(code) { finish(.failure(.server(response.statusCode, code))) }
            else { finish(.failure(.invalidResponse)) }
            return
        }
        finish(.success(body))
    }
}
