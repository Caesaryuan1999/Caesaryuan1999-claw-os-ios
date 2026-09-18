import Foundation
import UserNotifications
import UIKit
import CryptoKit
import TinodeSDK
import Kingfisher

/// The same decision is used by the settings screen and native tests.
struct ClawNotificationAuthorization {
    enum Action: Equatable { case request, settings, none }
    let status: UNAuthorizationStatus
    let alertsEnabled: Bool
    let notificationCenterEnabled: Bool

    var isUsable: Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return alertsEnabled && notificationCenterEnabled
        default:
            return false
        }
    }

    func action(forStatusButton: Bool) -> Action {
        if status == .notDetermined { return .request }
        return forStatusButton || !isUsable ? .settings : .none
    }

    var title: String {
        if status == .notDetermined { return "开启新消息通知" }
        if status == .denied { return "系统通知已关闭" }
        return "已授权，可在系统设置调整提醒方式"
    }

    var summary: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return isUsable ? "系统允许显示提醒。具体投递仍受网络和系统设置影响。"
                : "部分提醒方式未开启，可在系统设置中调整。你仍可打开 CLAW OS 查看并同步消息。"
        default:
            return "可能无法及时收到新消息提醒。你仍可打开 CLAW OS 查看并同步消息。"
        }
    }

    var buttonTitle: String {
        status == .notDetermined ? "开启系统通知" : "前往系统设置"
    }
}

/// A request generation protects retries; it is independent of the account cache namespace.
final class ClawMediaPreviewState {
    enum Phase: Equatable { case idle, loading, ready, failed, forbidden }
    private let lock = NSLock()
    private var attempt = UUID()
    private var currentPhase: Phase = .idle
    private var image: UIImage?
    private var bytes: Data?

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    var phase: Phase { locked { currentPhase } }
    var shareData: Data? { locked { currentPhase == .ready ? bytes : nil } }

    @discardableResult
    func begin() -> UUID {
        locked {
            attempt = UUID()
            currentPhase = .loading
            image = nil
            bytes = nil
            return attempt
        }
    }

    func isCurrent(_ request: UUID) -> Bool { locked { attempt == request } }

    @discardableResult
    func complete(_ request: UUID, image: UIImage) -> Bool {
        guard let data = image.pngData() else { fail(request); return false }
        return locked {
            guard attempt == request else { return false }
            self.image = image
            bytes = data
            currentPhase = .ready
            return true
        }
    }

    @discardableResult
    func loadInline(_ bits: Data?) -> UIImage? {
        let request = begin()
        guard let bits = bits, let image = UIImage(data: bits) else {
            fail(request)
            return nil
        }
        return complete(request, image: image) && phase == .ready ? image : nil
    }

    @discardableResult
    func fail(_ request: UUID, forbidden: Bool = false) -> Bool {
        locked {
            guard attempt == request else { return false }
            currentPhase = forbidden ? .forbidden : .failed
            image = nil
            bytes = nil
            return true
        }
    }
}

struct ClawMediaSession {
    let owner: ObjectIdentifier
    let uid: String
    let generation: UInt64

    func accepts(owner candidate: AnyObject, uid: String?, storedUID: String?, generation: UInt64) -> Bool {
        owner == ObjectIdentifier(candidate) && self.uid == uid && self.uid == storedUID
            && self.generation == generation
    }
}

enum ClawMediaFiles {
    static let readRecovery = "无法读取此文件，请重新选择，或先下载到本机后重试。"

    static func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func origin(_ url: URL) -> String? {
        guard let components = URLComponents(url: url.absoluteURL, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host?.lowercased(), components.user == nil, components.password == nil else { return nil }
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }

    static func isAllowedMediaURL(_ url: URL, service: URL) -> Bool {
        guard let remote = origin(url), let local = origin(service) else { return false }
        return remote == local || url.scheme?.lowercased() == "https"
    }

    static func cacheKey(origin service: URL, uid: String, url: URL) -> String? {
        guard !uid.isEmpty, let serviceOrigin = origin(service), isAllowedMediaURL(url, service: service),
              let data = try? JSONEncoder().encode([serviceOrigin, uid, url.absoluteURL.absoluteString]) else { return nil }
        return "claw-media-v1-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let exportLock = NSLock()
    private static var ownedExports = Set<URL>()

    private static func leafName(_ suggested: String?, fallback: String) -> String {
        let leaf = ((suggested ?? fallback).replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        var cleaned = ""
        for scalar in leaf.unicodeScalars {
            guard !CharacterSet.controlCharacters.contains(scalar),
                  !CharacterSet(charactersIn: "/\\:").contains(scalar) else { continue }
            let candidate = cleaned + String(scalar)
            if candidate.utf8.count > 180 { break }
            cleaned = candidate
        }
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? fallback : cleaned
    }

    /// Each operation owns one UUID directory. The supplied root is never removed.
    private static func export(root: URL, namespace: String, name: String,
                               write: (URL) throws -> Void) throws -> URL {
        let fm = FileManager.default
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let base = root.appendingPathComponent(namespace, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        guard base.resolvingSymlinksInPath().path == base.path else { throw ClawFileTransferError.write }
        let directory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard !fm.fileExists(atPath: directory.path) else { throw ClawFileTransferError.write }
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let target = directory.appendingPathComponent(name, isDirectory: false)
            guard directory.resolvingSymlinksInPath().path == directory.path,
                  target.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent() == directory,
                  !fm.fileExists(atPath: target.path) else { throw ClawFileTransferError.write }
            try write(target)
            exportLock.lock()
            ownedExports.insert(target)
            exportLock.unlock()
            return target
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    static func exportData(_ bytes: Data, suggestedName: String?,
                           root: URL = FileManager.default.temporaryDirectory) throws -> URL {
        try export(root: root, namespace: "ClawMediaExports",
                   name: leafName(suggestedName, fallback: "附件")) {
            try bytes.write(to: $0, options: .withoutOverwriting)
        }
    }

    /// Called synchronously before URLSession removes its temporary download.
    static func preserveDownload(_ source: URL, suggestedName: String?,
                                 root: URL = FileManager.default.temporaryDirectory) throws -> URL {
        try export(root: root, namespace: "ClawMediaExports",
                   name: leafName(suggestedName, fallback: "附件")) {
            try FileManager.default.moveItem(at: source, to: $0)
        }
    }

    /// Only paths created and registered by this process can be cleaned up.
    @discardableResult static func removeExport(_ url: URL) -> Bool {
        exportLock.lock(); defer { exportLock.unlock() }
        guard ownedExports.contains(url) else { return false }
        do {
            if FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) {
                try FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
            ownedExports.remove(url)
            return true
        } catch { return false } // Keep ownership when the filesystem refuses cleanup.
    }

    static func exportPNG(_ bytes: Data, suggestedName: String?, root: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let leaf = leafName(suggestedName, fallback: "图片")
        let stem = (leaf as NSString).deletingPathExtension
        let name = stem.isEmpty || stem == "." || stem == ".." ? "图片" : stem
        return try export(root: root, namespace: "ClawImageExports", name: name + ".png") {
            try bytes.write(to: $0, options: .withoutOverwriting)
        }
    }
}

enum ClawOwnedImageError: Error { case invalidURL, sessionExpired, cancelled }

/// No global account lookup. Production callers supply their captured Cache slot gate.
final class ClawOwnedImageContext {
    let owner: Tinode
    let serviceURL: URL
    let session: ClawMediaSession
    private let currentGeneration: () -> UInt64
    private let inCurrentSlot: (_ body: () -> Void) -> Bool

    init?(owner: Tinode, serviceURL: URL, generation: UInt64,
          currentGeneration: @escaping () -> UInt64,
          inCurrentSlot: @escaping (_ body: () -> Void) -> Bool) {
        guard ClawMediaFiles.origin(serviceURL) != nil,
              let uid = owner.withActiveSession({ () -> String? in
                  guard let uid = owner.myUid, owner.store?.myUid == uid else { return nil }
                  return uid
              }) ?? nil else { return nil }
        self.owner = owner
        self.serviceURL = serviceURL
        self.session = ClawMediaSession(owner: ObjectIdentifier(owner), uid: uid, generation: generation)
        self.currentGeneration = currentGeneration
        self.inCurrentSlot = inCurrentSlot
    }

    @discardableResult
    func withCurrent<Value>(_ operation: () -> Value) -> Value? {
        owner.withActiveSession {
            var result: Value?
            let entered = inCurrentSlot {
                guard session.accepts(owner: owner, uid: owner.myUid, storedUID: owner.store?.myUid,
                                      generation: currentGeneration()) else { return }
                result = operation()
            }
            return entered ? result : nil
        } ?? nil
    }

    var isCurrent: Bool { withCurrent { true } ?? false }

    func resourceURL(from ref: String) -> URL? {
        withCurrent {
            guard let url = URL(string: ref, relativeTo: serviceURL)?.absoluteURL,
                  ClawMediaFiles.isAllowedMediaURL(url, service: serviceURL) else { return nil }
            return url
        } ?? nil
    }

    func resource(for url: URL?) -> Kingfisher.ImageResource? {
        withCurrent {
            guard let url = url?.absoluteURL,
                  let key = ClawMediaFiles.cacheKey(origin: serviceURL, uid: session.uid, url: url) else { return nil }
            return Kingfisher.ImageResource(downloadURL: url, cacheKey: key)
        } ?? nil
    }

    /// Used by the real Kingfisher modifier and native URLRequest tests.
    func request(_ original: URLRequest) -> URLRequest? {
        withCurrent {
            guard let url = original.url, ClawMediaFiles.isAllowedMediaURL(url, service: serviceURL) else { return nil }
            var request = original
            for header in ["X-Tinode-APIKey", "X-Tinode-Auth", "Authorization", "Cookie"] {
                request.setValue(nil, forHTTPHeaderField: header)
            }
            if ClawMediaFiles.origin(url) == ClawMediaFiles.origin(serviceURL) {
                owner.getRequestHeaders().forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            }
            return request
        } ?? nil
    }

    func redirectedRequest(_ request: URLRequest) -> URLRequest? { nil }
}

final class ClawOwnedImageSlot {
    private let lock = NSLock()
    private var generation = UUID()
    @discardableResult func invalidate() -> UUID {
        lock.lock(); defer { lock.unlock() }
        generation = UUID()
        return generation
    }
    func accepts(_ ticket: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ticket == generation
    }
}

final class ClawOwnedImageLoad {
    private let lock = NSLock()
    private var task: DownloadTask?
    private var transport: ImageDownloader?
    private var stopped = false
    private var cancelled = false

    init(transport: ImageDownloader) { self.transport = transport }

    func bind(_ task: DownloadTask?) {
        lock.lock()
        if stopped { lock.unlock(); task?.cancel(); return }
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        stopped = true
        let oldTask = task
        let oldTransport = transport
        task = nil
        transport = nil
        lock.unlock()
        oldTask?.cancel()
        oldTransport?.cancelAll()
    }

    func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let valid = !cancelled
        stopped = true
        task = nil
        transport = nil
        return valid
    }
}

final class ClawOwnedImageLoader {
    typealias Completion = (Swift.Result<UIImage, Error>) -> Void
    typealias Transport = (Kingfisher.ImageResource, KingfisherOptionsInfo, @escaping Completion) -> DownloadTask?
    static let shared = ClawOwnedImageLoader()
    private let retrieve: Transport

    init(retrieve: @escaping Transport = { resource, options, completion in
        KingfisherManager.shared.retrieveImage(with: resource, options: options) { result in
            switch result {
            case .success(let value): completion(.success(value.image))
            case .failure(let error): completion(.failure(error))
            }
        }
    }) {
        self.retrieve = retrieve
    }

    @discardableResult
    func load(from url: URL?, context: ClawOwnedImageContext?, completion: @escaping Completion) -> ClawOwnedImageLoad? {
        guard let context = context, context.isCurrent else {
            DispatchQueue.main.async { completion(.failure(ClawOwnedImageError.sessionExpired)) }
            return nil
        }
        guard let resource = context.resource(for: url) else {
            DispatchQueue.main.async { completion(.failure(ClawOwnedImageError.invalidURL)) }
            return nil
        }
        let downloader = ImageDownloader(name: "claw-owned-" + UUID().uuidString)
        downloader.sessionConfiguration = .ephemeral
        let load = ClawOwnedImageLoad(transport: downloader)
        let modifier = AnyModifier { context.request($0) }
        let redirect = AnyRedirectHandler { _, _, request, done in done(context.redirectedRequest(request)) }
        let options: KingfisherOptionsInfo = [.requestModifier(modifier), .redirectHandler(redirect), .downloader(downloader)]
        let task = retrieve(resource, options) { result in
            // Consumers recheck their context and request generation immediately
            // around mutation. Never resolve a Promise while holding SDK/Cache locks.
            DispatchQueue.main.async {
                guard load.finish() else { completion(.failure(ClawOwnedImageError.cancelled)); return }
                guard context.isCurrent else { completion(.failure(ClawOwnedImageError.sessionExpired)); return }
                completion(result)
            }
        }
        load.bind(task)
        return load
    }
}


// Foreground-process download only. Uploads retain their independent background session.
enum ClawFileTransferError: Error {
    case invalidURL, sessionExpired, cancelled, redirect, network, write, invalidData
    case tooLarge, insufficientSpace, spaceUnavailable
    case http(Int)

    var message: String {
        switch self {
        case .sessionExpired, .cancelled: return "操作已结束，请重新打开此消息。"
        case .http(403): return "当前账号无权访问此附件。"
        case .write: return "无法准备分享文件，请稍后重试。"
        case .tooLarge: return "视频超过本机预览大小限制，请返回聊天。"
        case .insufficientSpace: return "本机可用空间不足，请释放空间后重新打开视频。"
        case .spaceUnavailable: return "暂时无法确认本机可用空间，请稍后重新打开视频。"
        default: return "附件暂时无法下载，请重试，或返回聊天检查此消息是否仍可访问。"
        }
    }
}

/// UIKit callers execute this gate on main immediately before presentation, with no SDK lock held.
final class ClawOwnedFilePresentation {
    let context: ClawOwnedImageContext
    private let attemptIsCurrent: () -> Bool
    init(context: ClawOwnedImageContext, attemptIsCurrent: @escaping () -> Bool) {
        self.context = context
        self.attemptIsCurrent = attemptIsCurrent
    }
    @discardableResult func consume(_ operation: () -> Void) -> Bool {
        guard Thread.isMainThread, context.isCurrent, attemptIsCurrent() else { return false }
        operation()
        return true
    }

    /// Actual Video and legacy download terminal consumers share this UI boundary.
    func complete(_ result: Swift.Result<URL, Error>, restore: () -> Void,
                  success: (URL) -> Void, failure: (Error) -> Void) {
        let consumed = consume {
            restore()
            switch result {
            case let .success(url): success(url)
            case let .failure(error): failure(error)
            }
        }
        if !consumed, case let .success(url) = result { ClawMediaFiles.removeExport(url) }
    }
}

/// A per-operation preview limit, not a server policy or a disk reservation.
struct ClawVideoDownloadBudget {
    static let reserveBytes: Int64 = 16 * 1024 * 1024
    let maximumBytes: Int64
    private let availableBytes: (URL) throws -> Int64

    init(maximumBytes: Int64, availableBytes: @escaping (URL) throws -> Int64 = { root in
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: root.path)
        guard let bytes = attributes[.systemFreeSize] as? NSNumber else { throw ClawFileTransferError.spaceUnavailable }
        return bytes.int64Value
    }) {
        self.maximumBytes = maximumBytes
        self.availableBytes = availableBytes
    }

    static func captured(from context: ClawOwnedImageContext) throws -> ClawVideoDownloadBudget {
        guard let maximum = context.withCurrent({
            context.owner.getServerLimit(for: Tinode.kMaxFileUploadSize, withDefault: 8 * 1024 * 1024)
        }) else { throw ClawFileTransferError.sessionExpired }
        return ClawVideoDownloadBudget(maximumBytes: maximum)
    }

    func preflight(at root: URL) throws {
        let doubled = maximumBytes.multipliedReportingOverflow(by: 2)
        let required = doubled.partialValue.addingReportingOverflow(Self.reserveBytes)
        guard maximumBytes > 0, !doubled.overflow, !required.overflow else { throw ClawFileTransferError.tooLarge }
        let available: Int64
        do { available = try availableBytes(root) }
        catch { throw ClawFileTransferError.spaceUnavailable }
        guard available >= required.partialValue else { throw ClawFileTransferError.insufficientSpace }
    }

    func checkProgress(written: Int64, expected: Int64) throws {
        guard maximumBytes > 0, written >= 0, written <= maximumBytes,
              expected < 0 || expected <= maximumBytes else { throw ClawFileTransferError.tooLarge }
    }

    func checkFile(_ file: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let length = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        try checkProgress(written: length, expected: length)
        guard length > 0 else { throw ClawFileTransferError.invalidData }
    }
}

/// Main-thread responsibility for one actual player and its optional owned file.
/// The generic callbacks capture that player, never the controller's later player.
final class ClawOwnedPlaybackLease {
    private static var pending = [UUID: ClawOwnedPlaybackLease]()
    private let identity = UUID()
    private let context: ClawOwnedImageContext
    private let ownedFile: URL?
    private let stop: () -> Void
    private let isStopped: () -> Bool
    private let detach: () -> Void
    private let releaseMedia: () -> Void
    private var observer: NSObjectProtocol?
    private var stopTimer: Timer?
    private var requestedPlay = false
    private var observedStopped = false
    private(set) var retired = false
    private(set) var cleanupPending = false
    private(set) var cleaned = false

    init(context: ClawOwnedImageContext, ownedFile: URL?, player: AnyObject,
         stop: @escaping () -> Void, isStopped: @escaping () -> Bool,
         detach: @escaping () -> Void, releaseMedia: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        self.context = context
        self.ownedFile = ownedFile
        self.stop = stop
        self.isStopped = isStopped
        self.detach = detach
        self.releaseMedia = releaseMedia
        // The fixed VLCKit notification is posted after its cached state is updated.
        observer = NotificationCenter.default.addObserver(forName: Notification.Name("VLCMediaPlayerStateChanged"),
            object: player, queue: .main) { [weak self] _ in
                guard let self = self, self.retired, self.isStopped() else { return }
                self.observedStopped = true
                self.completeIfStopped()
            }
    }

    @discardableResult func play(_ operation: () -> Void) -> Bool {
        precondition(Thread.isMainThread)
        guard !retired, context.isCurrent else { retire(); return false }
        requestedPlay = true
        observedStopped = false
        operation() // SDK/Cache gates have returned: never call VLC while holding them.
        return true
    }

    @discardableResult func checkOwner() -> Bool {
        precondition(Thread.isMainThread)
        guard !retired, context.isCurrent else { retire(); return false }
        return true
    }

    func retire() {
        precondition(Thread.isMainThread)
        guard !retired else { return }
        retired = true
        Self.pending[identity] = self
        stop()
        detach()
        // No polling of an initially cached `.stopped` as proof that async stop completed.
        // Once play was requested, require this player's actual stop notification and state.
        completeIfStopped()
        guard !cleaned else { return }
        let timer = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.stopTimer = nil
            self.completeIfStopped()
            self.cleanupPending = !self.cleaned
            // No timeout unlink or repeated stop. Retain this attempt and its observer;
            // a later real stop notification may still discharge its file responsibility.
        }
        stopTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func completeIfStopped() {
        guard retired, !cleaned, (!requestedPlay || observedStopped), isStopped() else { return }
        releaseMedia()
        if let ownedFile = ownedFile, !ClawMediaFiles.removeExport(ownedFile) {
            cleanupPending = true
            return
        }
        cleaned = true
        cleanupPending = false
        stopTimer?.invalidate()
        stopTimer = nil
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        Self.pending.removeValue(forKey: identity)
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        stopTimer?.invalidate()
    }
}

final class ClawOwnedFileDownload: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    typealias Completion = (Swift.Result<URL, Error>) -> Void
    private let context: ClawOwnedImageContext
    private let headers: [String: String]
    private let suggestedName: String?
    private let root: URL
    private let protocolClasses: [AnyClass]?
    private let budget: ClawVideoDownloadBudget?
    private let completion: Completion
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var requestedURL: URL?
    private var finished = false
    private var cancelled = false

    init(context: ClawOwnedImageContext, suggestedName: String?, root: URL = FileManager.default.temporaryDirectory,
         protocolClasses: [AnyClass]? = nil, budget: ClawVideoDownloadBudget? = nil, completion: @escaping Completion) {
        self.context = context
        self.headers = context.withCurrent { context.owner.getRequestHeaders() } ?? [:]
        self.suggestedName = suggestedName
        self.root = root
        self.protocolClasses = protocolClasses
        self.budget = budget
        self.completion = completion
        super.init()
    }

    static func configuration(protocolClasses: [AnyClass]? = nil) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.protocolClasses = protocolClasses
        return config
    }

    /// The actual task uses this frozen-header request, never a later Cache/SDK.
    func request(from url: URL) -> URLRequest? {
        guard context.isCurrent, ClawMediaFiles.isAllowedMediaURL(url, service: context.serviceURL) else { return nil }
        var request = URLRequest(url: url.absoluteURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpShouldHandleCookies = false
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if ClawMediaFiles.origin(url) == ClawMediaFiles.origin(context.serviceURL) {
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        }
        return request
    }

    func start(from url: URL) {
        guard let request = request(from: url) else {
            finish(.failure(context.isCurrent ? ClawFileTransferError.invalidURL : .sessionExpired))
            return
        }
        do { try budget?.preflight(at: root) }
        catch { finish(.failure(error)); return }
        let session = URLSession(configuration: Self.configuration(protocolClasses: protocolClasses),
                                 delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        lock.lock()
        guard !finished, self.session == nil else { lock.unlock(); session.invalidateAndCancel(); return }
        self.session = session
        self.task = task
        requestedURL = request.url
        lock.unlock()
        guard context.isCurrent else { finish(.failure(ClawFileTransferError.sessionExpired)); return }
        task.resume()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        finish(.failure(ClawFileTransferError.cancelled))
    }

    private func finish(_ result: Swift.Result<URL, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            if case let .success(url) = result { ClawMediaFiles.removeExport(url) }
            return
        }
        finished = true
        let transport = session
        session = nil
        task = nil
        lock.unlock()
        transport?.invalidateAndCancel()
        DispatchQueue.main.async {
            self.lock.lock()
            let cancelled = self.cancelled
            self.lock.unlock()
            if cancelled || !self.context.isCurrent {
                if case let .success(url) = result { ClawMediaFiles.removeExport(url) }
                self.completion(.failure(cancelled ? ClawFileTransferError.cancelled : .sessionExpired))
            } else {
                self.completion(result)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(.failure(ClawFileTransferError.redirect))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard context.isCurrent else { finish(.failure(ClawFileTransferError.sessionExpired)); return }
        do { try budget?.checkProgress(written: totalBytesWritten, expected: totalBytesExpectedToWrite) }
        catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard context.isCurrent else { finish(.failure(ClawFileTransferError.sessionExpired)); return }
        lock.lock()
        let stopped = finished || cancelled
        let requested = requestedURL
        lock.unlock()
        guard !stopped else { return }
        guard let response = downloadTask.response as? HTTPURLResponse,
              response.url == requested else { finish(.failure(ClawFileTransferError.invalidData)); return }
        guard response.statusCode == 200 else { finish(.failure(ClawFileTransferError.http(response.statusCode))); return }
        do {
            try budget?.checkFile(location)
            let attrs = try FileManager.default.attributesOfItem(atPath: location.path)
            let length = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            try budget?.checkProgress(written: length, expected: response.expectedContentLength)
            guard length > 0, response.expectedContentLength < 0 || response.expectedContentLength == length else {
                finish(.failure(ClawFileTransferError.invalidData)); return
            }
            guard context.isCurrent else { finish(.failure(ClawFileTransferError.sessionExpired)); return }
            let export = try ClawMediaFiles.preserveDownload(location, suggestedName: suggestedName, root: root)
            do { try budget?.checkFile(export) }
            catch { ClawMediaFiles.removeExport(export); throw error }
            guard context.isCurrent else {
                ClawMediaFiles.removeExport(export)
                finish(.failure(ClawFileTransferError.sessionExpired)); return
            }
            finish(.success(export))
        } catch { finish(.failure((error as? ClawFileTransferError) ?? .write)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // A valid download already completed through didFinishDownloadingTo.
        // The exactly-once gate ignores that subsequent completion.
        finish(.failure(error == nil ? ClawFileTransferError.invalidData : .network))
    }
}
