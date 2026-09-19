//
//  MessageViewController+VLCMediaPlayerDelegate.swift
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//
// Ordinary AU playback uses complete owned bytes, never a VLC URL/stream.
// Video and the user's unsubmitted recording preview retain their own players.
import AVFAudio
import Foundation
import TinodeSDK
import UIKit

enum ClawAudioFailure: Error {
    case unavailable, unsupported, tooLarge, space, network, forbidden, expired
    var message: String {
        switch self {
        case .unsupported: return "当前设备暂时无法播放这段语音，请联系发送者重新发送。"
        case .tooLarge: return "语音文件过大，暂时无法在本机播放。"
        case .space: return "本机可用空间不足或暂时无法确认，请释放空间后重试。"
        case .forbidden: return "当前账号无权播放这段语音。"
        case .expired: return "操作已结束，请重新打开此消息。"
        case .unavailable: return "语音数据暂不可用，请返回聊天检查此消息。"
        case .network: return "语音未加载完成，请检查网络后重试。"
        }
    }
    var allowsOriginalDownload: Bool {
        switch self { case .unsupported, .tooLarge: return true; default: return false }
    }
    static func from(_ error: Error) -> ClawAudioFailure {
        if let failure = error as? ClawAudioFailure { return failure }
        guard let transfer = error as? ClawFileTransferError else { return .unavailable }
        switch transfer {
        case .tooLarge: return .tooLarge
        case .insufficientSpace, .spaceUnavailable: return .space
        case .sessionExpired, .cancelled: return .expired
        case .http(403): return .forbidden
        case .invalidURL, .invalidData: return .unavailable
        default: return .network
        }
    }
}

/// One immutable source/owner/attempt. Engine operations occur on main after
/// SDK/Cache gates return. No AV/network/UI call runs inside those locks.
final class ClawAudioPlayback: NSObject, AVAudioPlayerDelegate {
    enum State { case idle, preparing, playing, paused, ended, failed, retired }
    static let memoryLimit: Int64 = 8 * 1024 * 1024
    let attempt = UUID()
    let context: ClawOwnedImageContext
    let entityKey: Int
    let reference: String?
    let suggestedName: String?
    private var inlineBytes: Data?
    private let scopeIsCurrent: () -> Bool
    private let maximumBytes: Int64
    private var download: ClawOwnedFileDownload?
    private var originalDownload: ClawOwnedFileDownload?
    private var exporting = false
    private var exportGeneration = UUID()
    private var cleanupURLs = Set<URL>()
    private var timer: Timer?
    private var pendingSeek: Double?
    private var playWhenPrepared = true
    private(set) var player: AVAudioPlayer?
    private(set) var state: State = .idle
    private(set) var failure: ClawAudioFailure?
    var changed: ((ClawAudioPlayback) -> Void)?

    init?(context: ClawOwnedImageContext, key: Int, reference: String?, bytes: Data?, name: String?,
          scopeIsCurrent: @escaping () -> Bool) {
        guard let limit = context.withCurrent({
            context.owner.getServerLimit(for: Tinode.kMaxFileUploadSize, withDefault: Self.memoryLimit)
        }), limit > 0 else { return nil }
        self.context = context
        entityKey = key
        self.reference = reference
        inlineBytes = bytes
        suggestedName = name
        maximumBytes = min(limit, Self.memoryLimit)
        self.scopeIsCurrent = scopeIsCurrent
        super.init()
    }

    var isCurrent: Bool {
        Thread.isMainThread && state != .retired && context.isCurrent && scopeIsCurrent()
    }
    var position: Double {
        guard let player = player, player.duration.isFinite, player.duration > 0,
              player.currentTime.isFinite else { return 0 }
        return min(1, max(0, player.currentTime / player.duration))
    }

    func toggle() {
        precondition(Thread.isMainThread)
        guard isCurrent else { retire(); return }
        switch state {
        case .idle: prepare()
        case .preparing: break // Repeated tap cannot create another download.
        case .playing:
            player?.pause()
            state = .paused
            notify()
        case .paused, .ended: play()
        case .failed, .retired: break // Retry requires a new explicit UI attempt.
        }
    }

    func seek(to fraction: Double) {
        precondition(Thread.isMainThread)
        guard isCurrent else { retire(); return }
        guard fraction.isFinite else { return }
        let fraction = min(1, max(0, fraction))
        if state == .idle {
            pendingSeek = fraction
            playWhenPrepared = false
            prepare()
        } else if state == .preparing {
            pendingSeek = fraction
        } else if let player = player, player.duration.isFinite, player.duration > 0 {
            if state == .ended { state = .paused }
            player.currentTime = fraction * player.duration
            notify()
        }
    }

    private func prepare() {
        state = .preparing
        startObserving()
        notify()
        guard isCurrent else { retire(); return }
        if let reference = reference {
            guard !reference.isEmpty, let url = context.resourceURL(from: reference) else { fail(.unavailable); return }
            let task = ClawOwnedFileDownload(context: context, suggestedName: suggestedName,
                budget: ClawVideoDownloadBudget(maximumBytes: maximumBytes)) { [weak self] result in
                guard let self = self else {
                    if case let .success(url) = result { ClawMediaFiles.removeExport(url) }
                    return
                }
                self.download = nil
                guard self.isCurrent, self.state == .preparing else {
                    if case let .success(url) = result { self.releaseFile(url) }
                    self.retire(); return
                }
                switch result {
                case let .success(url):
                    self.cleanupURLs.insert(url)
                    do {
                        try ClawVideoDownloadBudget(maximumBytes: self.maximumBytes).checkFile(url)
                        let bytes = try Data(contentsOf: url)
                        self.releaseFile(url)
                        self.install(bytes)
                    } catch { self.releaseFile(url); self.fail(.from(error)) }
                case let .failure(error): self.fail(.from(error))
                }
            }
            download = task
            guard isCurrent else { retire(); return }
            task.start(from: url)
        } else if let bytes = inlineBytes {
            install(bytes)
        } else { fail(.unavailable) }
    }

    private func install(_ bytes: Data) {
        guard isCurrent, state == .preparing else { retire(); return }
        guard !bytes.isEmpty else { fail(.unavailable); return }
        guard Int64(bytes.count) <= maximumBytes else { fail(.tooLarge); return }
        do {
            // The decoder receives no URL/base URL/path/resolver/credentials,
            // including when untrusted bytes are a mislabeled playlist.
            let candidate = try AVAudioPlayer(data: bytes)
            guard candidate.duration.isFinite, candidate.duration > 0,
                  candidate.prepareToPlay() else { fail(.unsupported); return }
            guard isCurrent else { candidate.stop(); retire(); return }
            player = candidate
            candidate.delegate = self
            if let seek = pendingSeek { candidate.currentTime = seek * candidate.duration }
            pendingSeek = nil
            state = .paused
            if playWhenPrepared { play() } else { notify() }
        } catch { fail(.unsupported) }
    }

    private func play() {
        guard isCurrent, let player = player else { retire(); return }
        if state == .ended { player.currentTime = 0 }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            guard isCurrent else { retire(); return }
            guard player.play(), player.isPlaying else { fail(.unsupported); return }
            state = .playing
            notify()
        } catch { fail(.unavailable) }
    }

    private func startObserving() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.observe() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func observe() {
        precondition(Thread.isMainThread)
        guard isCurrent else { retire(); return }
        retryCleanup()
        if state == .playing, let player = player {
            if !player.isPlaying { state = .paused }
            notify() // Read real currentTime; never increment a synthetic clock.
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self, weak player] in
            guard let self = self, let player = player, self.player === player, self.isCurrent else { return }
            if flag { self.state = .ended; self.notify() } else { self.fail(.unsupported) }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self, weak player] in
            guard let self = self, let player = player, self.player === player, self.isCurrent else { return }
            self.fail(.unsupported)
        }
    }

    private func notify() { changed?(self) }

    private func fail(_ error: ClawAudioFailure) {
        guard isCurrent else { retire(); return }
        player?.delegate = nil
        player?.stop()
        player = nil
        failure = error
        state = .failed
        notify()
    }

    /// Explicit user action only; uses the original file budget, not the 8MiB
    /// playback input limit. Completion belongs to this same source/attempt.
    func downloadOriginal(completion: @escaping (Swift.Result<URL, Error>) -> Void) {
        precondition(Thread.isMainThread)
        guard isCurrent, failure?.allowsOriginalDownload == true, !exporting else { return }
        let budget: ClawVideoDownloadBudget
        do { budget = try .captured(from: context) }
        catch { completion(.failure(error)); return }
        exporting = true
        let generation = UUID()
        exportGeneration = generation
        let complete: (Swift.Result<URL, Error>) -> Void = { [weak self] result in
            guard let self = self else {
                if case let .success(url) = result { ClawMediaFiles.removeExport(url) }; return
            }
            guard self.isCurrent, self.exportGeneration == generation else {
                if case let .success(url) = result { self.releaseFile(url) }; return
            }
            self.originalDownload = nil
            self.exporting = false
            completion(result)
        }
        if let reference = reference {
            guard !reference.isEmpty, let url = context.resourceURL(from: reference) else {
                complete(.failure(ClawFileTransferError.invalidURL)); return
            }
            let task = ClawOwnedFileDownload(context: context, suggestedName: suggestedName,
                                             budget: budget, completion: complete)
            originalDownload = task
            guard isCurrent else { retire(); return }
            task.start(from: url)
        } else if let bytes = inlineBytes {
            do {
                try budget.checkProgress(written: Int64(bytes.count), expected: Int64(bytes.count))
                try budget.preflight(at: FileManager.default.temporaryDirectory)
                guard !bytes.isEmpty, isCurrent else { throw ClawFileTransferError.invalidData }
                complete(.success(try ClawMediaFiles.exportData(bytes, suggestedName: suggestedName)))
            } catch { complete(.failure(error)) }
        } else { complete(.failure(ClawFileTransferError.invalidData)) }
    }

    private func releaseFile(_ url: URL) {
        cleanupURLs.insert(url)
        if ClawMediaFiles.removeExport(url) { cleanupURLs.remove(url) }
    }
    private func retryCleanup() {
        for url in Array(cleanupURLs) { releaseFile(url) }
    }

    func retire() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.retire() }; return }
        guard state != .retired else { retryCleanup(); return }
        state = .retired
        exportGeneration = UUID()
        timer?.invalidate(); timer = nil
        download?.cancel(); download = nil
        originalDownload?.cancel(); originalDownload = nil
        player?.delegate = nil
        player?.stop(); player = nil
        inlineBytes = nil
        retryCleanup()
        notify()
        changed = nil
        // Never deactivate a shared audio session now owned by a newer take.
    }

    deinit {
        let player = player, timer = timer, urls = Array(cleanupURLs)
        download?.cancel(); originalDownload?.cancel()
        let cleanup = {
            timer?.invalidate()
            player?.delegate = nil; player?.stop()
            urls.forEach { ClawMediaFiles.removeExport($0) }
        }
        if Thread.isMainThread { cleanup() } else { DispatchQueue.main.async(execute: cleanup) }
    }
}

extension MessageCell {
    func stopAudio() {
        audioPlayback?.retire()
        audioPlayback = nil
        mediaEntityKey = nil
    }
}
