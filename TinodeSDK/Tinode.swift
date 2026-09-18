//
//  Tinode.swift
//
//  Copyright © 2019-2025 Tinode LLC. All rights reserved.
//

import Foundation

public enum TinodeJsonError: Error {
    case encode
    case decode
}

public enum TinodeError: LocalizedError, CustomStringConvertible {
    case invalidReply(String)
    case invalidState(String)
    case invalidArgument(String)
    case notConnected(String)
    case requestNotSent(String)
    // The request may have reached the server. It must not be replayed automatically.
    case requestOutcomeUnknown(String)
    case serverResponseError(Int, String, String?)
    case notSubscribed(String)
    case notSynchronized

    public var description: String {
        get {
            switch self {
            case .invalidReply(let message):
                return "Invalid reply: \(message)"
            case .invalidState(let message):
                return "Invalid state: \(message)"
            case .invalidArgument(let message):
                return "Invalid argument: \(message)"
            case .notConnected(let message):
                return "Not connected: \(message)"
            case .requestNotSent(let message):
                return "Request not sent: \(message)"
            case .requestOutcomeUnknown(let message):
                return "Request outcome unconfirmed: \(message)"
            case .serverResponseError(let code, let text, _):
                return "\(text) (\(code))"
            case .notSubscribed(let message):
                return "Not subscribed: \(message)"
            case .notSynchronized:
                return "Not synchronized"
            }
        }
    }

    public var errorDescription: String? {
        return description
    }
}

public enum PublishFailureDisposition: Equatable {
    case queued, failed, unconfirmed

    public static func forError(_ error: Error) -> PublishFailureDisposition {
        if let error = error as? TinodeError {
            switch error {
            case .notConnected, .requestNotSent:
                // Only emitted before handing this request to transport.
                return .queued
            case .invalidArgument:
                return .failed
            case .serverResponseError(let code, _, _):
                // A timeout or a server/gateway failure does not prove rejection.
                return (400..<500).contains(code) && code != 408 ? .failed : .unconfirmed
            default:
                return .unconfirmed
            }
        }
        if error is EncodingError {
            return .failed
        }
        if let jsonError = error as? TinodeJsonError, case .encode = jsonError {
            return .failed
        }
        return .unconfirmed
    }
}

enum PublishConfirmation {
    static func sequence(from ctrl: MsgServerCtrl?) throws -> Int {
        guard let ctrl = ctrl, (200..<300).contains(ctrl.code),
              let seq = ctrl.getIntParam(for: "seq"), seq > 0 else {
            throw TinodeError.requestOutcomeUnknown("Missing valid publish confirmation or sequence")
        }
        return seq
    }
}

/// C3 identity is assigned once when a new outbound row is created, never on retry.
public enum C3PublishPolicy {
    public static let capability = "claw-msg-v1"
    public static let upgradeRequired = "服务端需要升级，消息尚未发送。"

    public static func clientMessageId(in head: [String: JSONValue]?) -> String? {
        guard let value = head?["clientmsgid"]?.asString(),
              value.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil else { return nil }
        return value
    }

    public static func newHeaders(_ head: [String: JSONValue]?, content: Drafty) -> [String: JSONValue] {
        var headers = head ?? [:]
        headers["clientmsgid"] = .string(UUID().uuidString.lowercased())
        if content.isPlain { headers.removeValue(forKey: "mime") }
        else { headers["mime"] = .string(Drafty.kMimeType) }
        return headers
    }

    static func rejectionText(_ ctrl: MsgServerCtrl) -> String {
        return ctrl.code == 409 && ctrl.getStringParam(for: "reason") == "clientmsgid_conflict" ?
            "重试消息的内容已变化，请查看原消息后重新创建消息。" : ctrl.text
    }
}

// Callback interface called by Connection
// when it receives events from the websocket.
public protocol TinodeEventListener: AnyObject {
    // Connection established successfully, handshakes exchanged.
    // The connection is ready for login.
    // Params:
    //   code   should be always 201.
    //   reason should be always "Created".
    //   params server parameters, such as protocol version.
    func onConnect(code: Int, reason: String, params: [String: JSONValue]?)

    // Connection was dropped.
    // Params:
    //   byServer: true if connection was closed by server.
    //   code: numeric code of the error which caused connection to drop.
    //   reason: error message.
    func onDisconnect(byServer: Bool, code: URLSessionWebSocketTask.CloseCode, reason: String)

    // Result of successful or unsuccessful {@link #login} attempt.
    // Params:
    //   code: a numeric value between 200 and 299 on success, 400 or higher on failure.
    //   text: "OK" on success or error message.
    func onLogin(code: Int, text: String)

    // Handle generic server message.
    // Params:
    //   msg: message to be processed.
    func onMessage(msg: ServerMessage?)

    // Handle unparsed message. Default handler calls {@code #dispatchPacket(...)} on a
    // websocket thread.
    // A subclassed listener may wish to call {@code dispatchPacket()} on a UI thread
    // Params:
    //   msg: message to be processed.
    func onRawMessage(msg: String)

    // Handle control message
    // Params:
    //   ctrl: control message to process.
    func onCtrlMessage(ctrl: MsgServerCtrl?)

    // Handle data message
    // Params:
    //   data: control message to process.
    func onDataMessage(data: MsgServerData?)

    // Handle info message
    // Params:
    //   info: info message to process.
    func onInfoMessage(info: MsgServerInfo?)

    // Handle meta message
    // Params:
    //   meta: meta message to process.
    func onMetaMessage(meta: MsgServerMeta?)

    // Handle presence message
    // Params:
    //   pres: control message to process.
    func onPresMessage(pres: MsgServerPres?)
}

public extension TinodeEventListener {
    func onConnect(code: Int, reason: String, params: [String: JSONValue]?) {}
    func onDisconnect(byServer: Bool, code: URLSessionWebSocketTask.CloseCode, reason: String) {}
    func onLogin(code: Int, text: String) {}
    func onMessage(msg: ServerMessage?) {}
    func onRawMessage(msg: String) {}
    func onCtrlMessage(ctrl: MsgServerCtrl?) {}
    func onDataMessage(data: MsgServerData?) {}
    func onInfoMessage(info: MsgServerInfo?) {}
    func onMetaMessage(meta: MsgServerMeta?) {}
    func onPresMessage(pres: MsgServerPres?) {}
}

public class Tinode {
    public static let kTopicNew = "new"
    public static let kUserNew = "new"
    public static let kChannelNew = "nch"
    public static let kTopicMe = "me"
    public static let kTopicFnd = "fnd"
    public static let kTopicSys = "sys"
    public static let kTopicSlf = "slf"

    public static let kTopicGrpPrefix = "grp"
    public static let kTopicUsrPrefix = "usr"
    public static let kTopicChnPrefix = "chn"

    // Keys for server-provided limits.
    public static let kMaxMessageSize = "maxMessageSize"
    public static let kMaxSubscriberCount = "maxSubscriberCount"
    public static let kMaxTagLength = "maxTagLength"
    public static let kMinTagLength = "minTagLength"
    public static let kMaxTagCount = "maxTagCount"
    public static let kMaxFileUploadSize = "maxFileUploadSize"
    public static let kCredValidatorsRequired = "reqCred"
    public static let kMessageDeleteAge = "msgDelAge"

    public static let kNoteKp = "kp"
    public static let kNoteKpA = "kpa"
    public static let kNoteKpV = "kpv"
    public static let kNoteRead = "read"
    public static let kNoteRecv = "recv"
    public static let kNoteCall = "call"
    public static let kNullValue = "\u{2421}"

    internal static let log = Log(subsystem: "co.tinode.tinodesdk")

    public static let kMaxPinnedCount = 5

    public static let kTagEmail = "email:"
    public static let kTagPhone = "tel:"
    public static let kTagAlias = "alias:"

    private static let kAliasRegex = "^[a-z0-9][a-z0-9_\\-]{3,23}$"

    let kProtocolVersion = "0"
    let kVersion = "0.23"
    let kLibVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String

    public var OsVersion: String = ""

    private class ConcurrentFuturesMap {
        static let kFutureExpiryInterval = 3.0
        static let kFutureExpiryTimerTolerance = 0.2
        static let kFutureTimeout = 5.0
        private var futuresDict = [String: PromisedReply<ServerMessage>]()
        private let futuresQueue = DispatchQueue(label: "co.tinode.futuresmap")
        private var timer: Timer?
        init() {
            timer = Timer(
                timeInterval: ConcurrentFuturesMap.kFutureExpiryInterval,
                target: self,
                selector: #selector(expireFutures),
                userInfo: nil,
                repeats: true)
            timer!.tolerance = ConcurrentFuturesMap.kFutureExpiryTimerTolerance
            // Run on the background thread.
            DispatchQueue.global(qos: .background).async {
                let runLoop = RunLoop.current
                runLoop.add(self.timer!, forMode: .common)
                runLoop.run()
            }
        }
        deinit {
            timer!.invalidate()
        }
        @objc private func expireFutures() {
            let expired = futuresQueue.sync { () -> [PromisedReply<ServerMessage>] in
                let threshold = Date().addingTimeInterval(TimeInterval(-ConcurrentFuturesMap.kFutureTimeout))
                let keys = futuresDict.filter { $0.value.creationTimestamp < threshold }.map { $0.key }
                return keys.compactMap { futuresDict.removeValue(forKey: $0) }
            }
            let error = TinodeError.requestOutcomeUnknown("Timed out waiting for the server reply")
            for future in expired { try? future.reject(error: error) }
        }
        subscript(key: String) -> PromisedReply<ServerMessage>? {
            get { return futuresQueue.sync { return futuresDict[key] } }
            set { futuresQueue.sync { futuresDict[key] = newValue } }
        }
        func removeValue(forKey key: String) -> PromisedReply<ServerMessage>? {
            return futuresQueue.sync { return futuresDict.removeValue(forKey: key) }
        }
        func rejectAndPurgeAll(withError e: Error) {
            let pending = futuresQueue.sync { () -> [PromisedReply<ServerMessage>] in
                let pending = Array(futuresDict.values)
                futuresDict.removeAll()
                return pending
            }
            for f in pending { try? f.reject(error: e) }
        }
    }

    // A simple thread-safe wrapper around Dictionary<String, T>.
    private class ConcurrentMap<T> {
        private var internalMap = [String: T]()
        private let opsQueue = DispatchQueue(label: "co.tinode.map-ops")

        var values: Dictionary<String, T>.Values {
            opsQueue.sync { return internalMap.values }
        }
        var count: Int {
            opsQueue.sync { return internalMap.count }
        }

        subscript(key: String) -> T? {
            get { return opsQueue.sync { return internalMap[key] } }
            set { opsQueue.sync { internalMap[key] = newValue } }
        }
        func removeValue(forKey key: String) -> T? {
            return opsQueue.sync { return internalMap.removeValue(forKey: key) }
        }
    }

    // Forwards events to all subscribed listeners.
    private class ListenerNotifier: TinodeEventListener {
        private var listeners: [TinodeEventListener] = []
        private var queue = DispatchQueue(label: "co.tinode.listener")

        public func addListener(_ l: TinodeEventListener) {
            queue.sync {
                guard listeners.firstIndex(where: { $0 === l }) == nil else { return }
                listeners.append(l)
            }
        }

        public func removeListener(_ l: TinodeEventListener) {
            queue.sync {
                if let idx = listeners.firstIndex(where: { $0 === l }) {
                    listeners.remove(at: idx)
                }
            }
        }

        public func removeAll() {
            queue.sync { listeners.removeAll() }
        }

        public var listenersThreadSafe: [TinodeEventListener] {
            queue.sync { return self.listeners }
        }

        func onConnect(code: Int, reason: String, params: [String: JSONValue]?) {
            listenersThreadSafe.forEach { $0.onConnect(code: code, reason: reason, params: params) }
        }

        func onDisconnect(byServer: Bool, code: URLSessionWebSocketTask.CloseCode, reason: String) {
            listenersThreadSafe.forEach { $0.onDisconnect(byServer: byServer, code: code, reason: reason) }
        }

        func onLogin(code: Int, text: String) {
            listenersThreadSafe.forEach { $0.onLogin(code: code, text: text) }
        }

        func onMessage(msg: ServerMessage?) {
            listenersThreadSafe.forEach { $0.onMessage(msg: msg) }
        }

        func onRawMessage(msg: String) {
            listenersThreadSafe.forEach { $0.onRawMessage(msg: msg) }
        }

        func onCtrlMessage(ctrl: MsgServerCtrl?) {
            listenersThreadSafe.forEach { $0.onCtrlMessage(ctrl: ctrl) }
        }

        func onDataMessage(data: MsgServerData?) {
            listenersThreadSafe.forEach { $0.onDataMessage(data: data) }
        }

        func onInfoMessage(info: MsgServerInfo?) {
            listenersThreadSafe.forEach { $0.onInfoMessage(info: info) }
        }

        func onMetaMessage(meta: MsgServerMeta?) {
            listenersThreadSafe.forEach { $0.onMetaMessage(meta: meta) }
        }

        func onPresMessage(pres: MsgServerPres?) {
            listenersThreadSafe.forEach { $0.onPresMessage(pres: pres) }
        }
    }
    public var appName: String
    public var apiKey: String
    public var useTLS: Bool
    public var hostName: String
    public var connection: Connection?
    public var nextMsgId = 1
    private var futures = ConcurrentFuturesMap()
    private let publishReceiptLock = NSLock()
    private var publishReceipts: [String: (Date, (MsgServerCtrl) -> Void)] = [:]
    private let requestIdLock = NSLock()
    public var serverVersion: String?
    public var serverBuild: String?
    private var serverParams: [String: JSONValue]?
    public var supportsDurablePublish: Bool {
        return isConnected && serverParams?["idempotency"]?.asString() == C3PublishPolicy.capability
    }
    private var connectionListener: TinodeConnectionListener?
    public var timeAdjustment: TimeInterval = 0
    public var isConnectionAuthenticated = false
    public var myUid: String?
    public var deviceToken: String?
    public var authToken: String?
    public var authTokenExpires: Date?
    public var nameCounter = 0
    public var store: Storage?
    private var listenerNotifier = ListenerNotifier()
    public var topicsLoaded = false
    private(set) public var topicsUpdated: Date?

    struct LoginCredentials {
        let scheme: String
        let secret: String
        init(using scheme: String, authenticateWith secret: String) {
            self.scheme = scheme
            self.secret = secret
        }
    }
    private var loginCredentials: LoginCredentials?
    private var autoLogin: Bool = false
    private var loginInProgress: Bool = false
    // Queue to execute state-mutating operations on.
    // One SDK instance represents one local session and is permanently retired on logout.
    // Recursive because Promise callbacks can execute synchronously on the caller thread.
    private let sessionLock = NSRecursiveLock()
    private var sessionClosed = false

    // Cleanup may run after retirement; normal operations use withActiveSession.
    public func withSessionLock<T>(_ body: () throws -> T) rethrows -> T {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return try body()
    }

    public var isSessionActive: Bool { withSessionLock { !sessionClosed } }

    // App credential/media callbacks use the same boundary as local logout.
    @discardableResult
    public func withActiveSession<T>(_ body: () throws -> T) rethrows -> T? {
        return try withSessionLock {
            guard !sessionClosed else { return nil }
            return try body()
        }
    }

    // Never invoke a consumer while holding the session gate. Consumer callbacks
    // may synchronously use their UI queue or start another SDK operation.
    public func dispatchIfActive(on queue: DispatchQueue = .main, _ callback: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self = self, self.isSessionActive else { return }
            callback()
        }
    }

    public func hostURL(useWebsocketProtocol: Bool) -> URL? {
        guard !hostName.isEmpty else { return nil }
        let protocolString = useTLS ? (useWebsocketProtocol ? "wss://" : "https://") : (useWebsocketProtocol ? "ws://" : "http://")
        let urlString = "\(protocolString)\(hostName)/"
        return URL(string: urlString)
    }
    public func baseURL(useWebsocketProtocol: Bool) -> URL? {
        return hostURL(useWebsocketProtocol: useWebsocketProtocol)?.appendingPathComponent("v\(kProtocolVersion)")
    }
    public func channelsURL(useWebsocketProtocol: Bool) -> URL? {
        return baseURL(useWebsocketProtocol: useWebsocketProtocol)?.appendingPathComponent("/channels")
    }
    public var isConnected: Bool {
        if let c = connection, c.isConnected {
            return true
        }
        return false
    }

    private var topics = ConcurrentMap<TopicProto>()
    private var users = ConcurrentMap<UserProto>()

    public static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        encoder.dateEncodingStrategy = .customRFC3339
        encoder.outputFormatting = .withoutEscapingSlashes
        return encoder
    }()
    public static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        decoder.dateDecodingStrategy = .customRFC3339
        return decoder
    }()

    public init(for appname: String, authenticateWith apiKey: String,
         persistDataIn store: Storage? = nil,
         fowardEventsTo l: TinodeEventListener? = nil) {
        self.appName = appname
        self.apiKey = apiKey
        self.store = store
        if let listener = l {
            self.listenerNotifier.addListener(listener)
        }
        self.myUid = self.store?.myUid
        self.deviceToken = self.store?.deviceToken
        self.useTLS = false
        self.hostName = ""
        // self.osVersoin

        // osVersion
        // eventListener
        // typeOfMetaPacket
        // futures
        // store
        // myUID
        // deviceToken
        loadTopics()
    }

    public func addListener(_ l: TinodeEventListener) {
        listenerNotifier.addListener(l)
    }
    public func removeListener(_ l: TinodeEventListener) {
        listenerNotifier.removeListener(l)
    }
    public func remoteAllListeners() {
        listenerNotifier.removeAll()
    }

    @discardableResult
    private func loadTopics() -> Bool {
        guard !topicsLoaded else { return true }
        if let s = store, s.isReady, let allTopics = s.topicGetAll(from: self) {
            for t in allTopics {
                t.store = s
                topics[t.name] = t
                if let updated = t.updated, topicsUpdated ?? Date.distantPast < updated {
                    topicsUpdated = updated
                }
            }
            if let messages = s.getLatestMessagePreviews() {
                for m in messages {
                    if let topic = m.topic, let tt = topics[topic] {
                        tt.latestMessage = m
                        topics[topic] = tt
                    }
                }
            }
            topicsLoaded = true
        }
        return topicsLoaded
    }
    public func isMe(uid: String?) -> Bool {
        return self.myUid == uid
    }
    public func updateUser<DP: Codable, DR: Codable>(uid: String, desc: Description<DP, DR>) {
        var userPtr: UserProto?
        if let user = users[uid] {
            _ = (user as? User<DP>)?.merge(from: desc)
            userPtr = user
        } else {
            let user = User<DP>(uid: uid, desc: desc)
            users[uid] = user
            userPtr = user
        }
        store?.userUpdate(user: userPtr!)
    }
    public func updateUser<DP: Codable, DR: Codable>(sub: Subscription<DP, DR>) {
        var userPtr: UserProto?
        let uid = sub.user!
        if let user = users[uid] {
            _ = (user as? User<DP>)?.merge(from: sub)
            userPtr = user
        } else {
            let user = try! User<DP>(sub: sub)
            users[uid] = user
            userPtr = user
        }
        store?.userUpdate(user: userPtr!)
    }
    public func getUser<SP: Codable>(with uid: String) -> User<SP>? {
        if let user = users[uid] {
            return user as? User<SP>
        }
        if let user = store?.userGet(uid: uid) {
            users[uid] = user
            return user as? User<SP>
        }
        return nil
    }

    public func nextUniqueString() -> String {
        nameCounter += 1
        let millisecSince1970 = Int64(Date().timeIntervalSince1970 as Double * 1000)
        let q = ((millisecSince1970 - 1414213562373) << 16).advanced(by: nameCounter & 0xffff)
        return String(q, radix: 32)
    }

    public var userAgent: String {
        return "\(appName) (iOS \(OsVersion); \(Locale.current.identifier)); tinode-swift/\(kLibVersion)"
    }

    public func getServerLimit(for key: String, withDefault defVal: Int64) -> Int64 {
        return self.serverParams?[key]?.asInt64() ?? defVal
    }

    public func getServerParam(for key: String) -> JSONValue? {
        return self.serverParams?[key]
    }

    public func toAbsoluteURL(origUrl: String) -> URL? {
        return URL(string: origUrl, relativeTo: baseURL(useWebsocketProtocol: false)) ?? URL(string: origUrl)
    }

    public func isTrustedURL(_ url: URL) -> Bool {
        let base = baseURL(useWebsocketProtocol: false)!
        return url.scheme == base.scheme && url.host == base.host && url.port == base.port
    }

    public func addAuthQueryParams(_ url: URL) -> URL {
        if isTrustedURL(url) {
            let items = [
                URLQueryItem(name: "apikey", value: apiKey),
                URLQueryItem(name: "auth", value: "token"),
                // Convert standard encoded token to URL encoding to be safely included into an URL.
                URLQueryItem(name: "secret", value: authToken?
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")),
            ]
            var components = URLComponents(string: url.absoluteString)
            var query = components?.queryItems ?? []
            query.append(contentsOf: items)
            components?.queryItems = query
            return components?.url ?? url
        }
        return url
    }

    public func getRequestHeaders() -> [String:String] {
        var headers: [String:String] = [:]
        headers["X-Tinode-APIKey"] = apiKey
        if authToken != nil {
            headers["X-Tinode-Auth"] = "Token " + authToken!
        }
        headers["User-Agent"] = userAgent
        return headers
    }

    private func getNextMsgId() -> String {
        requestIdLock.lock(); defer { requestIdLock.unlock() }
        nextMsgId += 1
        return String(nextMsgId)
    }
    private func resolveWithPacket(id: String?, pkt: ServerMessage) throws {
        if let idUnwrapped = id {
            let p = futures.removeValue(forKey: idUnwrapped)
            if let r = p, !r.isDone {
                try r.resolve(result: pkt)
            }
        }
    }
    private func dispatch(_ msg: String) throws {
        sessionLock.lock(); defer { sessionLock.unlock() }
        guard !sessionClosed else { return }
        guard !msg.isEmpty else {
            return
        }

        listenerNotifier.onRawMessage(msg: msg)
        guard let data = msg.data(using: .utf8) else {
            throw TinodeJsonError.decode
        }
        let serverMsg = try Tinode.jsonDecoder.decode(ServerMessage.self, from: data)

        listenerNotifier.onMessage(msg: serverMsg)

        if let ctrl = serverMsg.ctrl {
            listenerNotifier.onCtrlMessage(ctrl: ctrl)
            if let id = ctrl.id {
                publishReceiptLock.lock()
                let receipt = publishReceipts.removeValue(forKey: id)?.1
                publishReceiptLock.unlock()
                if let r = futures.removeValue(forKey: id) {
                    if ServerMessage.kStatusOk <= ctrl.code && ctrl.code < ServerMessage.kStatusBadRequest {
                        try r.resolve(result: serverMsg)
                    } else {
                        try r.reject(error: TinodeError.serverResponseError(ctrl.code, C3PublishPolicy.rejectionText(ctrl), ctrl.getStringParam(for: "what")))
                    }
                } else if (200..<300).contains(ctrl.code) {
                    // A timeout may already have rejected its Promise. Preserve the
                    // late confirmation independently; never turn that Promise green.
                    receipt?(ctrl)
                }
            }
            if ctrl.code == ServerMessage.kStatusResetContent && ctrl.text == "evicted" {
                if let topicName = ctrl.topic, let topic = getTopic(topicName: topicName) {
                    topic.topicLeft(unsub: ctrl.getBoolParam(for: "unsub") ?? false, code: ctrl.code, reason: ctrl.text)
                }
            } else if let what = ctrl.getStringParam(for: "what"), let topicName = ctrl.topic, let topic = getTopic(topicName: topicName) {
                switch what {
                case "data":
                    topic.allMessagesReceived(count: ctrl.getIntParam(for: "count"))
                case "sub":
                    topic.allSubsReceived()
                default:
                    break
                }
            }
        } else if let meta = serverMsg.meta {
            if let t = getTopic(topicName: meta.topic!) ?? maybeCreateTopic(meta: meta) {
                t.routeMeta(meta: meta)

                if let updated = t.updated, t.topicType != .fnd, t.topicType != .me {
                    if topicsUpdated ?? Date.distantPast < updated {
                        topicsUpdated = updated
                    }
                }
            }

            listenerNotifier.onMetaMessage(meta: meta)
            try resolveWithPacket(id: meta.id, pkt: serverMsg)
        } else if let data = serverMsg.data {
            if let t = getTopic(topicName: data.topic!) {
                t.routeData(data: data)
            }
            listenerNotifier.onDataMessage(data: data)
            try resolveWithPacket(id: data.id, pkt: serverMsg)
        } else if let pres = serverMsg.pres {
            if let topicName = pres.topic {
                if let t = getTopic(topicName: topicName) {
                    t.routePres(pres: pres)
                    // For P2P topics presence is addressed to 'me' only. Forward it to the actual topic, if it's found.
                    if topicName == Tinode.kTopicMe, case .p2p = Tinode.topicTypeByName(name: pres.src) {
                        if let forwardTo = getTopic(topicName: pres.src!) {
                            forwardTo.routePres(pres: pres)
                        }
                    }
                }
            }
            listenerNotifier.onPresMessage(pres: pres)
        } else if let info = serverMsg.info {
            if let topicName = info.topic {
                if let t = getTopic(topicName: topicName) {
                    t.routeInfo(info: info)
                }
                listenerNotifier.onInfoMessage(info: info)
            }
        }
    }

    public func oobNotification(payload: [AnyHashable : Any], token: String) {

    }

    private func note(topic: String, what: String, seq: Int) {
        let msg = ClientMessage<Int, Int>(
            note: MsgClientNote(topic: topic, what: what, seq: seq))
        try? send(payload: msg)
    }

    public func noteRecv(topic: String, seq: Int) {
        note(topic: topic, what: Tinode.kNoteRecv, seq: seq)
    }

    public func noteRead(topic: String, seq: Int) {
        note(topic: topic, what: Tinode.kNoteRead, seq: seq)
    }

    public func noteKeyPress(topic: String) {
        note(topic: topic, what: Tinode.kNoteKp, seq: 0)
    }

    public func videoCall(topic: String, seq: Int, event: String, payload: JSONValue? = nil) {
        let msg = ClientMessage<Int, Int>(
            note: MsgClientNote(topic: topic, what: "call", seq: seq, event: event, payload: payload))
        try? send(payload: msg)
    }

    private func send<DP: Codable, DR: Codable>(payload msg: ClientMessage<DP, DR>) throws {
        sessionLock.lock(); defer { sessionLock.unlock() }
        guard !sessionClosed else { throw TinodeError.requestNotSent("本机账号已退出，请重新登录。") }
        if let reason = store?.initializationError { throw TinodeError.requestNotSent(reason) }
        guard let conn = connection, conn.isConnected else {
            throw TinodeError.notConnected("Attempted to send msg to a closed connection.")
        }
        let jsonData = try Tinode.jsonEncoder.encode(msg)
        // Login credentials and message content must not enter Debug logs either.
        Tinode.log.debug("packet_out")
        conn.send(payload: jsonData)
    }

    private func sendWithPromise<DP: Codable, DR: Codable>(payload msg: ClientMessage<DP, DR>, with id: String) -> PromisedReply<ServerMessage> {
        let future = PromisedReply<ServerMessage>()
        // Register before send: a fast reply must not be lost between these operations.
        futures[id] = future
        do {
            try send(payload: msg)
        } catch {
            _ = futures.removeValue(forKey: id)
            do {
                try future.reject(error: error)
            } catch {
                Tinode.log.error("Error rejecting promise: %@", error.localizedDescription)
            }
        }
        return future
    }

    private func hello(inBackground bkg: Bool) -> PromisedReply<ServerMessage> {
        serverParams = nil
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(hi: MsgClientHi(id: msgId, ver: kVersion, ua: userAgent, dev: deviceToken, lang: Locale.current.identifier, background: bkg))
        return sendWithPromise(payload: msg, with: msgId)
            .thenApply({ [weak self] pkt in
                guard let ctrl = pkt?.ctrl else {
                    throw TinodeError.invalidReply("Unexpected type of reply packet to hello")
                }
                guard let tn = self else { return nil }
                tn.sessionLock.lock(); defer { tn.sessionLock.unlock() }
                guard !tn.sessionClosed else { throw TinodeError.invalidState("Session ended") }
                tn.serverParams = ctrl.params
                if !(ctrl.params?.isEmpty ?? true) {
                    tn.serverVersion = ctrl.getStringParam(for: "ver")
                    tn.serverBuild = ctrl.getStringParam(for: "build")
                    tn.serverParams = ctrl.params
                    for k in [Tinode.kMaxMessageSize, Tinode.kMaxSubscriberCount, Tinode.kMaxTagCount, Tinode.kMaxFileUploadSize] {
                        if ctrl.getInt64Param(for: k) == nil {
                            Tinode.log.error("Server limit missing for key %@", k)
                        }
                    }
                }
                return nil
        })
    }

    /**
     * Start tracking topic: add it to in-memory cache.
     */
    public func startTrackingTopic(topic: TopicProto) {
        topic.store = store
        topics[topic.name] = topic
    }

    /**
     * Stop tracking the topic: remove it from in-memory cache.
     */
    public func stopTrackingTopic(topicName: String) {
        _ = topics.removeValue(forKey: topicName)
    }

    /**
     * Check if topic is being tracked.
     */
    public func isTopicTracked(topicName: String) -> Bool {
        return topics[topicName] != nil
    }

    public func newTopic<SP: Codable & Mergeable, SR: Codable>(sub: Subscription<SP, SR>) -> TopicProto {
        if sub.topic == Tinode.kTopicMe {
            let t = MeTopic<SP>(tinode: self, l: nil)
            return t
        } else if sub.topic == Tinode.kTopicFnd {
            let r = FndTopic<SP>(tinode: self)
            return r
        }
        return ComTopic(tinode: self, sub: sub as! Subscription<TheCard, PrivateType>)
    }
    public static func newTopic(withTinode tinode: Tinode?, forTopic name: String) -> TopicProto {
        if name == Tinode.kTopicMe {
            return DefaultMeTopic(tinode: tinode)
        }
        if name == Tinode.kTopicFnd {
            return DefaultFndTopic(tinode: tinode)
        }
        return DefaultComTopic(tinode: tinode, name: name, l: nil)
    }
    public func newTopic(for name: String) -> TopicProto {
        return Tinode.newTopic(withTinode: self, forTopic: name)
    }
    public func maybeCreateTopic(meta: MsgServerMeta) -> TopicProto? {
        if meta.desc == nil {
            return nil
        }

        var topic: TopicProto?
        if meta.topic == Tinode.kTopicMe {
            topic = DefaultMeTopic(tinode: self, desc: meta.desc! as! DefaultDescription)
        } else if meta.topic == Tinode.kTopicFnd {
            topic = DefaultFndTopic(tinode: self)
        } else {
            topic = DefaultComTopic(tinode: self, name: meta.topic!, desc: (meta.desc! as! DefaultDescription))
        }

        return topic
    }
    public func changeTopicName(topic: TopicProto, oldName: String) -> Bool {
        let result = topics.removeValue(forKey: oldName) != nil
        topics[topic.name] = topic
        store!.topicUpdate(topic: topic)
        return result
    }
    public func getMeTopic() -> DefaultMeTopic? {
        return getTopic(topicName: Tinode.kTopicMe) as? DefaultMeTopic
    }
    public func getOrCreateFndTopic() -> DefaultFndTopic {
        if let fnd = getTopic(topicName: Tinode.kTopicFnd) as? DefaultFndTopic {
            return fnd
        }
        return DefaultFndTopic(tinode: self)
    }
    public func getTopic(topicName: String) -> TopicProto? {
        if topicName.isEmpty {
            return nil
        }
        return topics[topicName]
    }

    public static func topicTypeByName(name: String?) -> TopicType {
        var r: TopicType = .unknown
        if let name = name, !name.isEmpty {
            switch name {
            case kTopicMe:
                r = .me
            case kTopicFnd:
                r = .fnd
            case kTopicSys:
                r = .sys
            case kTopicSlf:
                r = .slf
            default:
                if name.starts(with: kTopicGrpPrefix) || name.starts(with: kTopicNew) || name.starts(with: kTopicChnPrefix) || name.starts(with: kChannelNew) {
                    r = .grp
                } else if name.starts(with: kTopicUsrPrefix) {
                    r = .p2p
                }
            }
        }
        return r
    }

    public static func isChannel(name: String?) -> Bool {
        if let name = name, !name.isEmpty {
            return name.starts(with: kTopicChnPrefix) || name.starts(with: kChannelNew)
        }
        return false
    }

    /// Create account using a single basic authentication scheme. A connection must be established
    /// prior to calling this method.
    ///
    /// - Parameters:
    ///   - uname: user name
    ///   - pwd: password
    ///   - login: use the new account for authentication
    ///   - tags: discovery tags
    ///   - desc: account parameters, such as full name etc.
    ///   - creds:  account credential, such as email or phone
    /// - Returns: PromisedReply of the reply ctrl message
    public func createAccountBasic<Pu: Codable, Pr: Codable>(uname: String, pwd: String, login: Bool, tags: [String]?, desc: MetaSetDesc<Pu, Pr>, creds: [Credential]?) -> PromisedReply<ServerMessage> {
        let encodedSecret: String
        do {
            encodedSecret = try AuthScheme.encodeBasicToken(uname: uname, password: pwd)
        } catch {
            return PromisedReply(error: TinodeError.invalidArgument(error.localizedDescription))
        }
        return account(uid: Tinode.kUserNew, scheme: AuthScheme.kLoginBasic, secret: encodedSecret, loginNow: login, tags: tags, desc: desc, creds: creds)
    }

    private func handleAuthenticationError(error: Error) {
        sessionLock.lock(); defer { sessionLock.unlock() }
        guard !sessionClosed else { return }
        if let e = error as? TinodeError {
            if case TinodeError.serverResponseError(let code, let text, _) = e {
                if ServerMessage.kStatusBadRequest <= code && code < ServerMessage.kStatusInternalServerError {
                    // clear auth data.
                    self.loginCredentials = nil
                    self.authToken = nil
                    self.authTokenExpires = nil
                }
                self.isConnectionAuthenticated = false
                self.listenerNotifier.onLogin(code: code, text: text)
            }
        }
    }

    /// Create new account. Connection must be established prior to calling this method.
    ///
    /// - Parameters:
    ///   - uid: uid of the user to affect
    ///   - scheme: authentication scheme to use
    ///   - secret: authentication secret for the chosen scheme
    ///   - loginNow: use new account to login immediately
    ///   - tags: tags
    ///   - desc: default access parameters for this account
    ///   - creds: creds
    /// - Returns: PromisedReply of the reply ctrl message
    public func account<Pu: Codable, Pr: Codable>(uid: String?, tmpscheme: String? = nil, tmpsecret: String? = nil, scheme: String, secret: String, loginNow: Bool, tags: [String]?, desc: MetaSetDesc<Pu, Pr>?, creds: [Credential]?) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msga = MsgClientAcc(id: msgId, uid: uid, tmpscheme: tmpscheme, tmpsecret: tmpsecret, scheme: scheme, secret: secret, doLogin: loginNow, desc: desc)

        if let creds = creds, creds.count > 0 {
            for c in creds {
                msga.addCred(cred: c)
            }
        }

        if let tags = tags, tags.count > 0 {
            for t in tags {
                msga.addTag(tag: t)
            }
        }

        let msg = ClientMessage<Pu, Pr>(acc: msga)
        if let attachments = desc?.attachments, !attachments.isEmpty {
            msg.extra = MsgClientExtra(attachments: attachments)
        }

        let future = sendWithPromise(payload: msg, with: msgId)

        if !loginNow {
            return future
        }
        return future.then(
            onSuccess: { [weak self] pkt in
                try self?.loginSuccessful(ctrl: pkt?.ctrl)
                return nil
            },
            onFailure: { [weak self] err in
                self?.handleAuthenticationError(error: err)
                return PromisedReply<ServerMessage>(error: err)
            })
    }

    private func setAutoLogin(using scheme: String?,
                              authenticateWith secret: String?) {
        guard let scheme = scheme, let secret = secret else {
            autoLogin = false
            loginCredentials = nil
            return
        }
        autoLogin = true
        loginCredentials = LoginCredentials(using: scheme, authenticateWith: secret)
    }

    public func setAutoLoginWithToken(token: String) {
        sessionLock.lock(); defer { sessionLock.unlock() }
        guard !sessionClosed else { return }
        setAutoLogin(using: AuthScheme.kLoginToken, authenticateWith: token)
    }

    public func loginBasic(uname: String, password: String) -> PromisedReply<ServerMessage> {
        var encodedToken: String
        do {
            encodedToken = try AuthScheme.encodeBasicToken(uname: uname, password: password)
        } catch {
            Tinode.log.error("Won't login - failed encoding token: %@", error.localizedDescription)
            return PromisedReply(error: error)
        }
        return login(scheme: AuthScheme.kLoginBasic, secret: encodedToken, creds: nil)
    }

    public func loginToken(token: String, creds: [Credential]?) -> PromisedReply<ServerMessage> {
        return login(scheme: AuthScheme.kLoginToken, secret: token, creds: creds)
    }

    public func login(scheme: String, secret: String, creds: [Credential]?) -> PromisedReply<ServerMessage> {
        sessionLock.lock(); defer { sessionLock.unlock() }
        guard !sessionClosed else { return PromisedReply(error: TinodeError.invalidState("Session ended")) }
        if autoLogin {
            loginCredentials = LoginCredentials(using: scheme, authenticateWith: secret)
        }
        guard !isConnectionAuthenticated else {
            // Already logged in.
            return PromisedReply<ServerMessage>(value: ServerMessage())
        }
        guard !loginInProgress else {
            return PromisedReply<ServerMessage>(error: TinodeError.invalidState("Login in progress"))
        }
        loginInProgress = true
        let msgId = getNextMsgId()
        let msgl = MsgClientLogin(id: msgId, scheme: scheme, secret: secret, credentials: nil)
        if let creds = creds, creds.count > 0 {
            for c in creds {
                msgl.addCred(c: c)
            }
        }
        let msg = ClientMessage<Int, Int>(login: msgl)
        return sendWithPromise(payload: msg, with: msgId).then(
            onSuccess: { [weak self] pkt in
                self?.withActiveSession { self?.loginInProgress = false }
                try self?.loginSuccessful(ctrl: pkt?.ctrl)
                return nil
            },
            onFailure: { [weak self] err in
                self?.withActiveSession { self?.loginInProgress = false }
                self?.handleAuthenticationError(error: err)
                return PromisedReply<ServerMessage>(error: err)
            })
    }

    private func loginSuccessful(ctrl: MsgServerCtrl?) throws {
        sessionLock.lock(); defer { sessionLock.unlock() }
        guard !sessionClosed else { throw TinodeError.invalidState("Session ended") }
        guard let ctrl = ctrl else {
            throw TinodeError.invalidReply("Unexpected type of server response")
        }
        let newUid = ctrl.getStringParam(for: "user")
        if let curUid = myUid, curUid != newUid {
            logout()
            listenerNotifier.onLogin(code: ServerMessage.kStatusBadRequest, text: "UID mismatch")
            throw TinodeError.invalidState(
                "UID mismatch: received '\(newUid ?? "")', expected '\(curUid)'")
        }
        myUid = newUid

        authToken = ctrl.getStringParam(for: "token")
        authTokenExpires = authToken != nil ?
            Formatter.rfc3339.date(from: ctrl.getStringParam(for: "expires") ?? "") : nil

        // auth expires
        if ctrl.code < ServerMessage.kStatusMultipleChoices {
            guard authToken != nil else {
                throw TinodeError.invalidState("Server did not return auth token")
            }
            isConnectionAuthenticated = true
            store?.myUid = newUid
            setAutoLoginWithToken(token: authToken!)
            // Load topics if not yet loaded.
            loadTopics()
            listenerNotifier.onLogin(code: ctrl.code, text: ctrl.text)
        } else {
            isConnectionAuthenticated = false
            if let meth = ctrl.getStringArray(for: "cred") {
                store?.setMyUid(uid: newUid!, credMethods: meth)
            }
        }
    }
    private func updateAccountSecret(uid: String?,
                                     tmpscheme: String? = nil, tmpsecret: String? = nil,
                                     scheme: String, secret: String) -> PromisedReply<ServerMessage> {
        return account(uid: uid, tmpscheme: tmpscheme, tmpsecret: tmpsecret, scheme: scheme, secret: secret, loginNow: false, tags: nil, desc: nil as MetaSetDesc<Int, Int>?, creds: nil)
    }
    @discardableResult
    public func updateAccountBasic(uid: String?, username: String?, password: String) -> PromisedReply<ServerMessage> {
        do {
            return try updateAccountSecret(uid: uid, scheme: AuthScheme.kLoginBasic,
                secret: AuthScheme.encodeBasicToken(uname: username ?? "", password: password))
        } catch {
            return PromisedReply(error: error)
        }
    }

    @discardableResult
    public func updateAccountBasic(usingAuthScheme auth: AuthScheme, username: String?, password: String) -> PromisedReply<ServerMessage> {
        do {
            return try updateAccountSecret(uid: nil, tmpscheme: auth.scheme, tmpsecret: auth.secret, scheme: AuthScheme.kLoginBasic,
                secret: AuthScheme.encodeBasicToken(uname: username ?? "", password: password))
        } catch {
            return PromisedReply(error: error)
        }
    }

    public func requestResetPassword(method: String, newValue: String) -> PromisedReply<ServerMessage> {
        do {
            return try login(scheme: AuthScheme.kLoginReset, secret: AuthScheme.encodeResetToken(scheme: AuthScheme.kLoginBasic, method: method, value: newValue), creds: nil)
        } catch {
            return PromisedReply(error: error)
        }
    }
    public func disconnect() {
        withSessionLock {
            // Remove auto-login data.
            setAutoLogin(using: nil, authenticateWith: nil)
            connection?.disconnect()
        }
    }
    public func logout() {
        withSessionLock {
            guard !sessionClosed else { return }
            // Best effort only: local logout never waits for device-unregister ACK.
            if isConnectionAuthenticated && isConnected {
                let msg = ClientMessage<Int, Int>(hi: MsgClientHi(id: getNextMsgId(), dev: Tinode.kNullValue))
                try? send(payload: msg)
            }
            sessionClosed = true
            let previousUid = myUid
            let previousStore = store
            setAutoLogin(using: nil, authenticateWith: nil)
            loginInProgress = false
            isConnectionAuthenticated = false
            authToken = nil
            authTokenExpires = nil
            myUid = nil
            deviceToken = nil
            serverParams = nil
            for topic in topics.values { topic.store = nil }
            topics = ConcurrentMap<TopicProto>()
            users = ConcurrentMap<UserProto>()
            topicsLoaded = false
            topicsUpdated = nil
            store = nil
            if previousStore?.myUid == previousUid { previousStore?.logout() }
            connection?.disconnect()
            connection = nil
            publishReceiptLock.lock()
            publishReceipts.removeAll()
            publishReceiptLock.unlock()
        }
        let error = TinodeError.requestOutcomeUnknown("Session ended before the server reply")
        // Purge outside state/map locks: callbacks may re-enter the SDK or app cache.
        DispatchQueue.global(qos: .utility).async { [self] in
            futures.rejectAndPurgeAll(withError: error)
            try? connectionListener?.rejectAllPromises(err: error)
        }
    }
    private func handleDisconnect(isServerOriginated: Bool, code: URLSessionWebSocketTask.CloseCode, reason: String) {
        sessionLock.lock(); defer { sessionLock.unlock() }
        guard !sessionClosed else { return }
        serverParams = nil
        publishReceiptLock.lock()
        publishReceipts.removeAll()
        publishReceiptLock.unlock()
        let e = TinodeError.requestOutcomeUnknown("Connection closed before the server reply")
        futures.rejectAndPurgeAll(withError: e)
        serverBuild = nil
        serverVersion = nil
        serverParams = nil
        isConnectionAuthenticated = false
        for t in topics.values {
            t.topicLeft(unsub: false, code: ServerMessage.kStatusServiceUnavailable, reason: "disconnected")
        }
        listenerNotifier.onDisconnect(byServer: isServerOriginated, code: code, reason: reason)
    }
    public class TinodeConnectionListener: ConnectionListener {
        var tinode: Tinode
        var completionPromises: [PromisedReply<ServerMessage>] = []
        var promiseQueue = DispatchQueue(label: "co.tinode.completion-promises")

        init(tinode: Tinode) {
            self.tinode = tinode
        }
        func onConnect(reconnecting: Bool, param: Any?) {
            guard tinode.isSessionActive else { return }
            let m = reconnecting ? "YES" : "NO"
            Tinode.log.info("Tinode connected: after reconnect - %@", m.description)
            let doLogin = tinode.autoLogin && tinode.loginCredentials != nil
            var future = tinode.hello(inBackground: param as? Bool ?? false).thenApply({ [weak self] pkt in
                guard let self = self else {
                    throw TinodeError.invalidState("Missing Tinode instance in connection handler")
                }
                let tinode = self.tinode
                guard tinode.isSessionActive else { throw TinodeError.invalidState("Session ended") }

                if let ctrl = pkt?.ctrl {
                    tinode.timeAdjustment = Date().timeIntervalSince(ctrl.ts)
                    // tinode store
                    tinode.store?.setTimeAdjustment(adjustment: tinode.timeAdjustment)
                    // listener
                    tinode.listenerNotifier.onConnect(code: ctrl.code, reason: ctrl.text, params: ctrl.params)
                }
                if !doLogin {
                    try self.resolveAllPromises(msg: pkt)
                }
                return nil
            })
            if doLogin {
                future = future.thenApply({ [weak self] msg in
                    if let t = self?.tinode, let cred = t.loginCredentials, !t.loginInProgress {
                        return t.login(
                            scheme: cred.scheme, secret: cred.secret, creds: nil).then(
                                onSuccess: { msg in
                                    try self?.resolveAllPromises(msg: msg)
                                    return nil
                                },
                                onFailure: { err in
                                    Tinode.log.error("Login error: %@", err.localizedDescription)
                                    return PromisedReply<ServerMessage>(error: err)
                                })
                    }
                    return nil
                })
            }
            future.thenCatch({ err in
                Tinode.log.error("Connection error: %@", err.localizedDescription)
                return PromisedReply<ServerMessage>(error: err)
            })
        }
        func onMessage(with message: String) {
            Log.default.debug("packet_in")
            do {
                try tinode.dispatch(message)
            } catch {
                Log.default.error("packet_in_failed")
            }
        }
        func onDisconnect(isServerOriginated: Bool, code: URLSessionWebSocketTask.CloseCode, reason: String) {
            let serverOriginatedString = isServerOriginated ? "YES" : "NO"
            Log.default.info("Tinode disconnected: server originated [%@]; code [%d]; reason [%@]",
                             serverOriginatedString, code.rawValue, reason)
            tinode.handleDisconnect(isServerOriginated: isServerOriginated, code: code, reason: reason)
        }
        func onError(error: Error) {
            tinode.handleDisconnect(isServerOriginated: true, code: .invalid, reason: error.localizedDescription)
            Log.default.error("Tinode network error: %@", error.localizedDescription)
            try? rejectAllPromises(err: error)
        }
        public func addPromise(promise: PromisedReply<ServerMessage>) {
            promiseQueue.sync {
                completionPromises.append(promise)
            }
        }
        private func completeAllPromises(msg: ServerMessage?, err: Error?) throws {
            let promises: [PromisedReply<ServerMessage>] = promiseQueue.sync {
                let promises = completionPromises.map { $0 }
                completionPromises.removeAll()
                return promises
            }
            if let e = err {
                try promises.forEach { try $0.reject(error: e) }
                return
            }
            if let msg = msg {
                try promises.forEach { try $0.resolve(result: msg) }
            }
        }
        private func resolveAllPromises(msg: ServerMessage?) throws {
            try completeAllPromises(msg: msg, err: nil)
        }
        fileprivate func rejectAllPromises(err: Error?) throws {
            try completeAllPromises(msg: nil, err: err)
        }
    }

    private func resetMsgId() {
        requestIdLock.lock(); defer { requestIdLock.unlock() }
        nextMsgId = 0xffff + Int((Float(arc4random()) / Float(UInt32.max)) * 0xffff)
    }

    @discardableResult
    public func connect(to hostName: String, useTLS: Bool, inBackground bkg: Bool) throws -> PromisedReply<ServerMessage>? {
        try withSessionLock {
            return try connectThreadUnsafe(to: hostName, useTLS: useTLS, inBackground: bkg)
        }
    }

    private func connectThreadUnsafe(to hostName: String, useTLS: Bool, inBackground bkg: Bool) throws -> PromisedReply<ServerMessage>? {
        guard !sessionClosed else { throw TinodeError.invalidState("Session ended") }
        if let reason = store?.initializationError { throw TinodeError.requestNotSent(reason) }
        if isConnected {
            Tinode.log.debug("Tinode is already connected")
            return PromisedReply<ServerMessage>(value: ServerMessage())
        }
        self.useTLS = useTLS
        self.hostName = hostName
        guard let endpointURL = self.channelsURL(useWebsocketProtocol: true) else {
            throw TinodeError.invalidState("Could not form server url.")
        }
        resetMsgId()
        if connection == nil {
            connectionListener = TinodeConnectionListener(tinode: self)
            connection = Connection(open: endpointURL,
                                    with: apiKey,
                                    notify: connectionListener)
        }
        let connectedPromise = PromisedReply<ServerMessage>()
        connectionListener!.addPromise(promise: connectedPromise)
        try connection!.connect(withParam: bkg)
        return connectedPromise
    }

    // Connect with saved connection params (host name and tls settings).
    @discardableResult
    private func connect(inBackground bkg: Bool) throws -> PromisedReply<ServerMessage>? {
        return try connectThreadUnsafe(to: self.hostName, useTLS: self.useTLS, inBackground: bkg)
    }

    // Make sure connection is either already established or being established:
    //  - If connection is already established do nothing
    //  - If connection does not exist, create
    //  - If not connected and waiting for backoff timer, wake it up.
    //
    // |interactively| is true if user directly requested a reconnect.
    // If |reset| is true, drop connection and reconnect. Happens when cluster is reconfigured.
    @discardableResult
    public func reconnectNow(interactively: Bool, reset: Bool) -> Bool {
        guard store?.initializationError == nil else { return false }
        return withSessionLock {
            guard !sessionClosed else { return false }
            var reconnectInteractive = interactively
            if connection == nil {
                do {
                    try connect(inBackground: false)
                    return true
                } catch {
                    Tinode.log.error("Couldn't connect to server: %@", error.localizedDescription)
                    return false
                }
            }
            if connection!.isConnected {
                // We are done unless we need to reset the connection.
                if !reset {
                    return true
                }
                connection!.disconnect()
                reconnectInteractive = true
            }

            // Connection exists but not connected.
            // Try to connect immediately only if requested or if
            // autoreconnect is not enabled.
            if reconnectInteractive || !connection!.isWaitingToConnect {
                do {
                    try connection!.connect(reconnectAutomatically: true, withParam: nil)
                    return true
                } catch {
                    return false
                }
            }
            return false
        }
    }

    /**
     * Set device token for push notifications.
     *
     * @param token device token
     */
    @discardableResult
    public func setDeviceToken(token: String) -> PromisedReply<ServerMessage> {
        withSessionLock {
            guard !sessionClosed else { return PromisedReply(error: TinodeError.invalidState("Session ended")) }
            let accountUid = myUid
            guard token != deviceToken else {
                return PromisedReply<ServerMessage>(value: ServerMessage())
            }
            // Cache token here assuming the call to server does not fail. If it fails clear the cached token.
            // This prevents multiple unnecessary calls to the server with the same token.
            deviceToken = Tinode.isNull(obj: token) ? nil : token
            let msgId = getNextMsgId()
            let msg = ClientMessage<Int, Int>(hi: MsgClientHi(id: msgId, dev: token))
            return sendWithPromise(payload: msg, with: msgId)
                .thenCatch { [weak self] _ in
                    // Clear cached value on failure to allow for retries.
                    self?.withActiveSession {
                        guard self?.myUid == accountUid, self?.store?.myUid == accountUid,
                              self?.deviceToken == token else { return }
                        self?.deviceToken = nil
                        self?.store?.deviceToken = nil
                    }
                    return nil
                }
        }
    }

    public func subscribe<Pu: Codable, Pr: Codable>(to topicName: String, set: MsgSetMeta<Pu, Pr>?, get: MsgGetMeta?) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Pu, Pr>(
            sub: MsgClientSub(
                id: msgId,
                topic: topicName,
                set: set,
                get: get))
        if let attachments = set?.desc?.attachments, !attachments.isEmpty {
            msg.extra = MsgClientExtra(attachments: attachments)
        }
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func getMeta(topic: String, query: MsgGetMeta) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(  // generic params don't matter
            get: MsgClientGet(
                id: msgId,
                topic: topic,
                query: query))
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func setMeta<Pu: Codable, Pr: Codable>(for topic: String, meta: MsgSetMeta<Pu, Pr>?) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage(
            set: MsgClientSet(id: msgId, topic: topic, meta: meta)
        )
        if let attachments = meta?.desc?.attachments, !attachments.isEmpty {
            msg.extra = MsgClientExtra(attachments: attachments)
        }
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func leave(topic: String, unsub: Bool?) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(
            leave: MsgClientLeave(id: msgId, topic: topic, unsub: unsub))
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func publish(topic: String, head: [String: JSONValue]?, content: Drafty, attachments: [String]?, onLateAcknowledgement: ((MsgServerCtrl) -> Void)? = nil) -> PromisedReply<ServerMessage> {
        if let reason = store?.initializationError {
            return PromisedReply(error: TinodeError.requestNotSent(reason))
        }
        guard isConnected else {
            return PromisedReply(error: TinodeError.notConnected("Connection is not open"))
        }
        // Repeat the gate at dispatch: the connection may have changed after DB claim.
        guard supportsDurablePublish else {
            return PromisedReply(error: TinodeError.requestNotSent(C3PublishPolicy.upgradeRequired))
        }
        let msgId = getNextMsgId()
        if let receipt = onLateAcknowledgement {
            publishReceiptLock.lock()
            let cutoff = Date().addingTimeInterval(-300)
            publishReceipts = publishReceipts.filter { $0.value.0 > cutoff }
            // Bound memory while keeping the durable row eligible for same-key retry.
            if publishReceipts.count >= 1024, let oldest = publishReceipts.min(by: { $0.value.0 < $1.value.0 })?.key {
                publishReceipts.removeValue(forKey: oldest)
            }
            publishReceipts[msgId] = (Date(), receipt)
            publishReceiptLock.unlock()
        }
        let msg = ClientMessage<Int, Int>(pub: MsgClientPub(id: msgId, topic: topic, noecho: true, head: head, content: content))
        if let attachments = attachments, !attachments.isEmpty {
            msg.extra = MsgClientExtra(attachments: attachments)
        }
        return sendWithPromise(payload: msg, with: msgId)
    }

    public func getTopics() -> [TopicProto]? {
        return Array(topics.values)
    }
    public func getFilteredTopics(filter: ((TopicProto) -> Bool)?) -> [TopicProto]? {
        guard let filter = filter else {
            return topics.values.compactMap { $0 }
        }

        var result = topics.values.filter { (topic) -> Bool in
            return filter(topic)
        }
        result.sort(by: { ($0.touched ?? Date.distantPast) > ($1.touched ?? Date.distantPast) })
        return result
    }

    public func countFilteredTopics(filter: ((TopicProto) -> Bool)?) -> Int {
        guard let filter = filter else { return topics.count }

        var count = 0
        topics.values.forEach { topic in
            if filter(topic) {
                count += 1
            }
        }
        return count
    }

    private func sendDeleteMessage(msg: ClientMessage<Int, Int>) -> PromisedReply<ServerMessage> {
        return sendWithPromise(payload: msg, with: msg.del!.id!)
    }

    func delMessage(topicName: String, fromId: Int, toId: Int?, hard: Bool) -> PromisedReply<ServerMessage> {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(),
                                  topic: topicName,
                                  from: fromId, to: toId, hard: hard)))
    }
    func delMessage(topicName: String, ranges: [MsgRange]?, hard: Bool) -> PromisedReply<ServerMessage> {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(), topic: topicName, ranges: ranges, hard: hard)))
    }
    func delMessage(topicName: String, msgId: Int, hard: Bool) -> PromisedReply<ServerMessage> {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(), topic: topicName, msgId: msgId, hard: hard)))
    }
    func delSubscription(topicName: String, user: String?) -> PromisedReply<ServerMessage> {
        return sendDeleteMessage(
            msg: ClientMessage<Int, Int>(
                del: MsgClientDel(id: getNextMsgId(), topic: topicName, user: user)))
    }

    /// Low-level request to delete a credential. Use {@link MeTopic#delCredential(String, String)} ()} instead.
    ///
    /// - Parameters
    ///  - cred  credential to delete.
    /// - Returns: PromisedReply of the reply ctrl message
    func delCredential(cred: Credential) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(del: MsgClientDel(id: msgId, cred: cred))
        return sendWithPromise(payload: msg, with: msgId)
    }

    /// Request to delete account of the current user.
    /// - Parameters:
    ///   - hard: hard-delete user
    /// - Returns: PromisedReply of the reply ctrl message
    public func delCurrentUser(hard: Bool) -> PromisedReply<ServerMessage> {
        guard let ownerUid = myUid else { return PromisedReply(error: TinodeError.invalidState("No authenticated account")) }
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(del: MsgClientDel(id: msgId, hard: hard))
        return sendWithPromise(payload: msg, with: msgId).thenApply { [weak self] packet in
            guard let this = self else { return nil }
            return this.finishAccountDeletion(packet: packet, requestId: msgId, ownerUid: ownerUid)
        }
    }

    // Shared by the real request callback and native tests. A generic resolved
    // Promise may contain 205, 3xx or metadata; none confirms account deletion.
    func finishAccountDeletion(packet: ServerMessage?, requestId: String,
                               ownerUid: String) -> PromisedReply<ServerMessage>? {
        guard let ctrl = packet?.ctrl,
              ctrl.id == requestId, ctrl.code == ServerMessage.kStatusOk else {
            return PromisedReply(error: TinodeError.requestOutcomeUnknown("账号注销结果未确认，请重新登录核实。"))
        }
        return withActiveSession { () -> PromisedReply<ServerMessage>? in
            guard self.myUid == ownerUid, self.store?.myUid == ownerUid else {
                return PromisedReply(error: TinodeError.invalidState("Session changed"))
            }
            self.store?.deleteAccount(ownerUid)
            self.logout()
            return nil
        } ?? PromisedReply(error: TinodeError.invalidState("Session ended"))
    }

    /// Low-level request to delete topic. Use {@link Topic#delete()} instead.
    ///
    /// - Parameters:
    ///   - topicName: name of the topic to delete
    ///   - hard: hard-delete topic
    /// - Returns: PromisedReply of the reply ctrl message
    func delTopic(topicName: String, hard: Bool) -> PromisedReply<ServerMessage> {
        let msgId = getNextMsgId()
        let msg = ClientMessage<Int, Int>(del: MsgClientDel(id: msgId, topic: topicName, hard: hard))
        return sendWithPromise(payload: msg, with: msgId)
    }

    public static func serializeObject<T: Encodable>(_ t: T) -> String? {
        guard let jsonData = try? Tinode.jsonEncoder.encode(t) else {
            return nil
        }
        let typeName = String(describing: T.self)
        let json = String(decoding: jsonData, as: UTF8.self)
        return [typeName, json].joined(separator: ";")
    }
    public static func deserializeObject<T: Decodable>(from data: String?) -> T? {
        guard let parts = data?.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true), parts.count == 2 else {
            return nil
        }
        guard parts[0] == String(describing: T.self), let d = String(parts[1]).data(using: .utf8) else {
            return nil
        }
        return try? Tinode.jsonDecoder.decode(T.self, from: d)
    }

    public static func isNull(obj: Any?) -> Bool {
        guard let str = obj as? String else { return false }
        return str == Tinode.kNullValue
    }

    /// Split fully-qualified tag into prefix and value.
    ///
    /// - Parameters:
    ///    - tag: tag to split
    /// - Returns: tuple with the prefix (namespace) and value.
    public static func tagSplit(_ tag: String?) -> (String, String)? {
        guard let tag = tag?.trimmingCharacters(in: .whitespaces) else { return nil }

        guard let splitAt = tag.firstIndex(of: ":") else { return nil }

        let value = tag.suffix(from: tag.index(after: splitAt))
        if value.isEmpty {
            return nil
        }
        return (String(tag.prefix(upTo: splitAt)), String(value))
    }

    /// Set a unique namespace tag. If the tag with this namespace is already present then it's replaced with the new tag.
    ///
    /// - Parameters:
    ///    - uniqueTag: tag to add, must be fully-qualified; if nil or empty, no action is taken.
    /// - Returns: array of tags with the given namespace tag replaced.
    public static func setUniqueTag(tags: [String]?, uniqueTag: String) -> [String]? {
        guard let parts = Tinode.tagSplit(uniqueTag) else { return nil }

        guard let tags = tags, !tags.isEmpty else {
            // No tags, just add the new one.
            return [uniqueTag]
        }

        // Remove the old tag with the same prefix.
        var tt = tags.filter { !$0.starts(with: parts.0) }
        // Add the new tag and convert to array.
        tt.append(uniqueTag)
        return tt
    }

    /// Remove tags with the given prefix.
    ///
    /// - Parameters:
    ///   - prefix: prefix to remove
    /// - Returns: array of tags with the tags of the given prefix removed.
    public static func clearTagPrefix(tags: [String]?, prefix: String) -> [String]? {
        return tags?.filter { !$0.starts(with: prefix) }
    }

    /// Check if the given tag value is syntactically valid.
    ///
    /// - Parameters:
    ///   - tag: value to check.
    /// - Returns: true if the tag value is valid, false otherwise.
    public static func isValidTagValueFormat(tag: String?) -> Bool {
        guard let tag = tag, !tag.isEmpty else {
            return true
        }

        return tag.range(of: kAliasRegex, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Find the first tag with the given prefix.
    ///
    /// - Parameters:
    ///   - prefix: prefix to search for.
    /// - Returns: tag if found or nil
    public static func tagByPrefix(tags: [String]?, prefix: String) -> String? {
        return tags?.first(where: { $0.starts(with: prefix) })
    }
}
