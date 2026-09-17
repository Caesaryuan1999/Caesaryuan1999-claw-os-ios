import Foundation
import UserNotifications
import UIKit
import CryptoKit

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

    /// Caller controls root. Each export gets a new directory; remote names never become paths.
    static func exportPNG(_ bytes: Data, suggestedName: String?, root: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let leaf = ((suggestedName ?? "图片").replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        let stem = (leaf as NSString).deletingPathExtension
        let cleaned = String(stem.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet(charactersIn: "/\\:").contains($0)
        }.map { String($0) }.joined().prefix(100))
        let name = cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "图片" : cleaned
        let directory = root.appendingPathComponent("ClawImageExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name + ".png", isDirectory: false)
        try bytes.write(to: destination, options: .withoutOverwriting)
        return destination
    }
}
