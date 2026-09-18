import XCTest
import UIKit
import AVFoundation
import Network
import CryptoKit
import MobileVLCKit
import TinodeSDK
@testable import TinodiosDB

// Dependency measurements, not a replacement VideoPreviewController or a safe-player implementation.
// No URLProtocol, external destination, real credential, or downloaded media is used.
private enum VLCProbeFailure: Error { case fixture, listener, response, generation, evidence, playback, snapshot }

private func vlcMain<T>(_ body: () -> T) -> T {
    Thread.isMainThread ? body() : DispatchQueue.main.sync(execute: body)
}

private final class VLCProbeServer {
    private static let registryLock = NSLock()
    private static var registeredPorts = Set<UInt16>()
    enum Reply {
        case video(Data, cacheable: Bool, cookie: Bool)
        case redirect(URL, Int)
        case forbidden
    }
    private struct Route { let label: String; let reply: Reply; let gated: Bool }
    private let queue = DispatchQueue(label: "claw.vlc.loopback")
    private let listener: NWListener
    private var routes = [String: Route]()
    private var peers = [ObjectIdentifier: NWConnection]()
    private var pending = [() -> Void]()
    private var bodyReleased = false
    private var events = [[String: Any]]()
    private var active = true
    private(set) var port: UInt16 = 0
    var origin: URL { URL(string: "http://127.0.0.1:\(port)/")! }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any)
        let ready = DispatchSemaphore(value: 0)
        var signalled = false
        var becameReady = false
        listener.stateUpdateHandler = { state in
            if !signalled {
                switch state {
                case .ready: becameReady = true; signalled = true; ready.signal()
                case .failed: signalled = true; ready.signal()
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self, self.active, self.events.count < 32, self.peers.count < 32 else {
                connection.cancel(); return
            }
            self.peers[ObjectIdentifier(connection)] = connection
            connection.start(queue: self.queue)
            self.receive(connection, bytes: Data())
            self.queue.asyncAfter(deadline: .now() + 12) { [weak self] in self?.close(connection) }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success,
              queue.sync(execute: { becameReady }),
              let bound = listener.port, bound.rawValue != 0 else {
            listener.cancel(); throw VLCProbeFailure.listener
        }
        port = bound.rawValue
        Self.registryLock.lock(); Self.registeredPorts.insert(port); Self.registryLock.unlock()
    }

    func add(_ label: String, reply: Reply, gated: Bool = false) -> URL {
        let path = "/" + UUID().uuidString.lowercased() + ".mp4"
        queue.sync { routes[path] = Route(label: label, reply: reply, gated: gated) }
        return URL(string: path, relativeTo: origin)!.absoluteURL
    }

    func replace(_ url: URL, reply: Reply) {
        queue.sync {
            guard let prior = routes[url.path] else { return }
            routes[url.path] = Route(label: prior.label, reply: reply, gated: false)
        }
    }

    func releaseBody() {
        queue.sync {
            bodyReleased = true
            let callbacks = pending; pending.removeAll(); callbacks.forEach { $0() }
        }
    }

    func observations() -> [[String: Any]] { queue.sync { events } }

    func stop() {
        queue.sync {
            active = false
            listener.cancel()
            pending.removeAll()
            for peer in peers.values { peer.cancel() }
            peers.removeAll()
        }
        Self.registryLock.lock(); Self.registeredPorts.remove(port); Self.registryLock.unlock()
    }

    private func close(_ peer: NWConnection) {
        peer.cancel()
        peers.removeValue(forKey: ObjectIdentifier(peer))
    }

    private func receive(_ peer: NWConnection, bytes: Data) {
        peer.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self = self, self.active, error == nil, let data = data, !data.isEmpty else {
                self?.close(peer); return
            }
            let all = bytes + data
            guard all.count <= 16384 else { self.close(peer); return }
            if let end = all.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(peer, header: all[..<end.lowerBound])
            } else if !complete {
                self.receive(peer, bytes: all)
            } else { self.close(peer) }
        }
    }

    private func respond(_ peer: NWConnection, header: Data) {
        guard let text = String(data: header, encoding: .utf8) else { close(peer); return }
        let lines = text.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3, ["GET", "HEAD"].contains(String(first[0])), first[1].hasPrefix("/"),
              let parts = URLComponents(string: "http://127.0.0.1" + String(first[1])),
              let route = routes[parts.path], events.count < 32 else { close(peer); return }
        var headers = [String: String]()
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
        }
        let query = parts.queryItems ?? []
        let index = events.count
        events.append([
            "route": route.label, "head": first[0] == "HEAD", "bytesSent": 0,
            "queryHasSecret": query.contains { $0.name == "secret" },
            "queryMatchesA": query.contains { $0.name == "secret" && $0.value == "vlc-synthetic-A" },
            "queryMatchesB": query.contains { $0.name == "secret" && $0.value == "vlc-synthetic-B" },
            "queryHasAPIKey": query.contains { $0.name == "apikey" },
            "hasAuthHeader": headers["authorization"] != nil || headers["x-tinode-auth"] != nil,
            "hasCookie": headers["cookie"] != nil,
            "cookieMatchesFixture": headers["cookie"]?.contains("claw_vlc_probe=synthetic") == true,
            "refererHasSecret": headers["referer"]?.contains("secret=") == true,
            "rangeRequest": headers["range"] != nil,
            "conditionalRequest": headers["if-none-match"] != nil || headers["if-modified-since"] != nil
        ])
        var status = 200
        var body = Data()
        var extra = [String]()
        switch route.reply {
        case let .video(data, cacheable, cookie):
            guard data.count <= 2 * 1024 * 1024 else { close(peer); return }
            body = data
            extra += ["Content-Type: video/mp4", "Accept-Ranges: bytes",
                      "Cache-Control: " + (cacheable ? "public, max-age=3600" : "no-store")]
            if cookie { extra.append("Set-Cookie: claw_vlc_probe=synthetic; Path=/") }
            if let range = headers["range"], range.hasPrefix("bytes=") {
                let values = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
                guard values.count == 2, let start = Int(values[0]), start >= 0, start < data.count else {
                    close(peer); return
                }
                let end = min(Int(values[1]) ?? (data.count - 1), data.count - 1)
                guard end >= start else { close(peer); return }
                status = 206
                body = data.subdata(in: start..<(end + 1))
                extra.append("Content-Range: bytes \(start)-\(end)/\(data.count)")
            }
        case let .redirect(destination, code):
            // Only locally constructed targets are accepted. No server-supplied/public destination exists.
            Self.registryLock.lock()
            let registered = destination.port.flatMap { UInt16(exactly: $0) }.map { Self.registeredPorts.contains($0) } ?? false
            Self.registryLock.unlock()
            guard destination.scheme == "http", destination.host == "127.0.0.1",
                  registered, destination.user == nil, destination.password == nil else {
                close(peer); return
            }
            status = code
            extra.append("Location: " + destination.absoluteString)
        case .forbidden: status = 403
        }
        let response = Data((["HTTP/1.1 \(status) Fixture", "Connection: close",
                              "Content-Length: \(body.count)"] + extra).joined(separator: "\r\n").utf8)
            + Data("\r\n\r\n".utf8)
        let content = first[0] == "HEAD" ? Data() : body
        peer.send(content: response, completion: .contentProcessed { [weak self] error in
            guard let self = self, self.active, error == nil else { self?.close(peer); return }
            let write = { [weak self] in self?.sendBody(content, peer: peer, event: index) }
            if route.gated && !self.bodyReleased { self.pending.append { write() } } else { write() }
        })
    }

    private func sendBody(_ data: Data, peer: NWConnection, event: Int) {
        guard active, peers[ObjectIdentifier(peer)] != nil else { return }
        peer.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if error == nil { self.events[event]["bytesSent"] = data.count }
            self.close(peer)
        })
    }
}

private final class VLCProbeAccount {
    let base: BaseDb
    let store: SqlStore
    let owner: Tinode
    private var current = true
    private var generation: UInt64 = 1
    let origin: URL

    init(origin: URL, account: String = "A") throws {
        self.origin = origin
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("vlc-probe-" + UUID().uuidString + ".sqlite")
        base = BaseDb(databasePath: file.path)
        store = try XCTUnwrap(base.sqlStore)
        store.myUid = "usrVLCProbe" + account
        owner = Tinode(for: "vlc-probe", authenticateWith: "vlc-synthetic-api", persistDataIn: store)
        owner.hostName = "127.0.0.1:\(try XCTUnwrap(origin.port))"
        owner.useTLS = false
        owner.authToken = "vlc-synthetic-" + account
        // BaseDb retains SQLite handles: never unlink an open synthetic database.
    }

    func context() throws -> ClawOwnedImageContext {
        try XCTUnwrap(ClawOwnedImageContext(owner: owner, serviceURL: origin, generation: generation,
            currentGeneration: { self.generation }, inCurrentSlot: { body in
                guard self.current else { return false }; body(); return true
            }))
    }

    func retire() { owner.logout(); current = false; generation += 1 }
}

private final class VLCProbePlayer {
    let player: VLCMediaPlayer
    private let window: UIWindow
    // Avoid releasing a still-stopping VLC player after a failed bounded cleanup assertion.
    static var retainedAfterFailedStop = [VLCProbePlayer]()

    init(url: URL) {
        let pair = vlcMain { () -> (VLCMediaPlayer, UIWindow) in
            let window: UIWindow
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
            } else { window = UIWindow(frame: CGRect(x: 0, y: 0, width: 160, height: 160)) }
            let controller = UIViewController()
            controller.view.frame = window.bounds
            controller.view.backgroundColor = .black
            window.rootViewController = controller
            window.isHidden = false
            let player = VLCMediaPlayer()
            player.drawable = controller.view
            player.media = VLCMedia(url: url)
            player.play()
            return (player, window)
        }
        player = pair.0
        window = pair.1
    }

    func metrics() -> [String: Any] {
        vlcMain {
            let stats = player.media?.statistics
            return ["state": Int(player.state.rawValue), "timeMs": player.time.value?.intValue ?? 0,
                    "decoded": Int(stats?.decodedVideo ?? 0), "displayed": Int(stats?.displayedPictures ?? 0),
                    "readBytes": Int(stats?.readBytes ?? 0), "hasVideoOut": player.hasVideoOut,
                    "width": Int(player.videoSize.width), "height": Int(player.videoSize.height)]
        }
    }

    func stop() { vlcMain { player.stop() } }
    func stopped() -> Bool { vlcMain { player.state == .stopped } }
    func terminal() -> Bool { vlcMain { player.state == .ended || player.state == .error } }
    func hide() { vlcMain { player.drawable = nil; window.isHidden = true } }
}

final class VLCPlaybackProbeTests: XCTestCase {
    private var root: URL!
    private var deadline = Date()
    private var reported = false
    private var progress: [String: Any] = [:]
    private var dependencyEvidence: [String: Any] = [:]

    override func setUpWithError() throws {
        executionTimeAllowance = 120
        deadline = Date().addingTimeInterval(120)
        reported = false
        progress = ["stage": "starting", "safety": "NOT_MEASURED"]
        dependencyEvidence = [:]
        root = FileManager.default.temporaryDirectory.appendingPathComponent("claw-vlc-probe-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if !reported {
            try attach("vlc-incomplete-measurement", ["fixture": "INCOMPLETE_OR_FAILED",
                "lastProgress": progress, "safety": "NO_SAFETY_CONCLUSION"])
        }
        // Only this test's generated clips/snapshots. Never erase any app cache or account data.
        if let root = root, VLCProbePlayer.retainedAfterFailedStop.isEmpty {
            try FileManager.default.removeItem(at: root)
        }
    }

    @discardableResult private func until(_ seconds: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        guard Date() < deadline else { XCTFail("VLC probe exceeded its 120-second method budget"); return false }
        let limit = min(seconds, deadline.timeIntervalSinceNow)
        let predicate = NSPredicate { _, _ in condition() }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: limit) == .completed
    }

    @discardableResult private func cleanup(_ playback: VLCProbePlayer) -> Bool {
        playback.stop()
        if until(5, { playback.stopped() }) { playback.hide(); return true }
        else {
            XCTFail("VLC did not stop within the fixed cleanup budget")
            VLCProbePlayer.retainedAfterFailedStop.append(playback)
            return false
        }
    }

    private func attach(_ name: String, _ report: [String: Any]) throws {
        var final = report
        final["dependencyEvidence"] = dependencyEvidence
        let bytes = try JSONSerialization.data(withJSONObject: final, options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        reported = true
        // Fixed labels, booleans, counters and library metadata only; never a URL or credential value.
        print("VLC_PROBE_OBSERVATION " + String(data: bytes, encoding: .utf8)!)
    }

    private func libraryEvidence(_ player: VLCProbePlayer) throws -> [String: Any] {
        guard let value = ProcessInfo.processInfo.environment["CLAW_VLC_POD_EVIDENCE"],
              let bytes = value.data(using: .utf8),
              let evidence = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              evidence["podVersion"] as? String == "3.6.0",
              let headers = evidence["headers"] as? [[String: Any]], headers.count == 3 else {
            throw VLCProbeFailure.evidence
        }
        let runtime = vlcMain { player.player.libraryInstance }
        guard !runtime.version.isEmpty, !runtime.changeset.isEmpty else { throw VLCProbeFailure.evidence }
        let result: [String: Any] = ["pod": evidence, "runtimeVersion": String(runtime.version.prefix(100)),
                "runtimeChangeset": String(runtime.changeset.prefix(100)),
                "scope": "Real MobileVLCKit dependency; VideoPreviewController is not instantiated"]
        dependencyEvidence = result
        return result
    }

    private func clip(blue: Bool) throws -> Data {
        let url = root.appendingPathComponent(UUID().uuidString + ".mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 60000, AVVideoMaxKeyFrameIntervalKey: 15]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                         kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        guard writer.canAdd(input) else { throw VLCProbeFailure.generation }
        writer.add(input)
        guard writer.startWriting() else { throw VLCProbeFailure.generation }
        writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &pixel) == kCVReturnSuccess,
              let buffer = pixel else { writer.cancelWriting(); throw VLCProbeFailure.generation }
        CVPixelBufferLockBaseAddress(buffer, [])
        let pointer = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<64 { for x in 0..<64 {
            let index = y * stride + x * 4
            pointer[index] = 255; pointer[index + 1] = blue ? 20 : 220
            pointer[index + 2] = 20; pointer[index + 3] = blue ? 220 : 20
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let generationDeadline = Date().addingTimeInterval(10)
        for frame in 0..<90 {
            while !input.isReadyForMoreMediaData && Date() < generationDeadline { Thread.sleep(forTimeInterval: 0.005) }
            guard Date() < generationDeadline,
                  adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                writer.cancelWriting(); throw VLCProbeFailure.generation
            }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        guard done.wait(timeout: .now() + 10) == .success, writer.status == .completed else {
            progress = ["stage": "asset-writer-finish", "status": writer.status.rawValue,
                        "errorCode": (writer.error as NSError?)?.code ?? 0]
            writer.cancelWriting(); throw VLCProbeFailure.generation
        }
        let bytes = try Data(contentsOf: url)
        guard !bytes.isEmpty, bytes.count <= 2 * 1024 * 1024 else { throw VLCProbeFailure.generation }
        return bytes
    }

    private func decoded(_ playback: VLCProbePlayer) -> Bool {
        let m = playback.metrics()
        return (m["decoded"] as? Int ?? 0) > 0 && (m["displayed"] as? Int ?? 0) > 0 &&
            (m["timeMs"] as? Int ?? 0) >= 150 && m["hasVideoOut"] as? Bool == true &&
            m["width"] as? Int == 64 && m["height"] as? Int == 64
    }

    private func validateBaseline(_ bytes: Data, label: String) throws {
        let server = try VLCProbeServer(); defer { server.stop() }
        let url = server.add("fixture-control", reply: .video(bytes, cacheable: false, cookie: false))
        let playback = VLCProbePlayer(url: url); defer { cleanup(playback) }
        _ = try libraryEvidence(playback)
        let ready = until(8, { self.decoded(playback) })
        progress = ["stage": "fixture-control", "metrics": playback.metrics(), "requests": server.observations()]
        guard ready,
              try snapshot(playback, label: label) == "A_red" else { throw VLCProbeFailure.playback }
    }

    private func sampledFrame(_ url: URL, label: String) throws -> String {
        let playback = VLCProbePlayer(url: url); defer { cleanup(playback) }
        _ = try libraryEvidence(playback)
        let ready = until(8, { self.decoded(playback) })
        progress = ["stage": label, "metrics": playback.metrics()]
        guard ready else { throw VLCProbeFailure.playback }
        return try snapshot(playback, label: label)
    }

    private func snapshot(_ playback: VLCProbePlayer, label: String) throws -> String {
        let file = root.appendingPathComponent(UUID().uuidString + ".png")
        vlcMain {
            playback.player.pause()
            playback.player.saveVideoSnapshot(at: file.path, withWidth: 64, andHeight: 64)
        }
        guard until(3, { UIImage(contentsOfFile: file.path)?.cgImage != nil }),
              let image = UIImage(contentsOfFile: file.path)?.cgImage else { throw VLCProbeFailure.snapshot }
        let attachment = XCTAttachment(data: try Data(contentsOf: file), uniformTypeIdentifier: "public.png")
        attachment.name = label; attachment.lifetime = .keepAlways; add(attachment)
        var pixel = [UInt8](repeating: 0, count: 4)
        let rendered = pixel.withUnsafeMutableBytes { memory -> Bool in
            guard let ctx = CGContext(data: memory.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return true
        }
        guard rendered else { throw VLCProbeFailure.snapshot }
        if Int(pixel[0]) > Int(pixel[2]) + 80 && Int(pixel[0]) > Int(pixel[1]) + 80 { return "A_red" }
        if Int(pixel[2]) > Int(pixel[0]) + 80 && Int(pixel[2]) > Int(pixel[1]) + 80 { return "B_blue" }
        return "unknown"
    }

    func testRealVLCFramesTimeDecodeAndCapturedCredentialURL() throws {
        let server = try VLCProbeServer(); defer { server.stop() }
        let bytes = try clip(blue: false)
        let raw = server.add("baseline", reply: .video(bytes, cacheable: false, cookie: false))
        let account = try VLCProbeAccount(origin: server.origin)
        let context = try account.context()
        let url = try XCTUnwrap(context.withCurrent { account.owner.addAuthQueryParams(raw) })
        let playback = VLCProbePlayer(url: url); defer { cleanup(playback) }
        let evidence = try libraryEvidence(playback)
        let ready = until(8, { self.decoded(playback) })
        progress = ["stage": "baseline", "metrics": playback.metrics(), "requests": server.observations()]
        guard ready else { throw VLCProbeFailure.playback }
        let color = try snapshot(playback, label: "vlc-baseline-real-frame")
        XCTAssertEqual(color, "A_red")
        XCTAssertTrue(server.observations().contains { $0["queryMatchesA"] as? Bool == true })
        try attach("vlc-baseline", ["fixture": "MEASUREMENT_VALID", "library": evidence,
            "frame": color, "metrics": playback.metrics(), "requests": server.observations(),
            "fixtureSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "safety": "NOT_ASSESSED_BY_BASELINE"])
    }

    func testRealVLCRedirectBehaviorRecordsOriginAndCredentialObservations() throws {
        let bytes = try clip(blue: false)
        try validateBaseline(bytes, label: "vlc-redirect-fixture-control")
        var results = [[String: Any]]()
        for (code, otherOrigin, explicitQuery) in [(302, false, false), (302, true, false), (307, true, false), (302, true, true)] {
            let source = try VLCProbeServer(); defer { source.stop() }
            let target = try VLCProbeServer(); defer { target.stop() }
            let destinationServer = otherOrigin ? target : source
            var destination = destinationServer.add("target", reply: .video(bytes, cacheable: false, cookie: false))
            let account = try VLCProbeAccount(origin: source.origin)
            if explicitQuery { destination = account.owner.addAuthQueryParams(source.origin).replacingProbeOrigin(destination) }
            let raw = source.add("redirect", reply: .redirect(destination, code))
            let playback = VLCProbePlayer(url: account.owner.addAuthQueryParams(raw))
            defer { cleanup(playback) }
            guard until(5, { !source.observations().isEmpty }) else { throw VLCProbeFailure.response }
            let observed = until(5, {
                self.decoded(playback) || playback.terminal() || destinationServer.observations().contains {
                    $0["route"] as? String == "target"
                }
            })
            let targets = destinationServer.observations().filter { $0["route"] as? String == "target" }
            guard observed else {
                progress = ["stage": "redirect-timeout", "completedCases": results, "metrics": playback.metrics()]
                throw VLCProbeFailure.response
            }
            results.append(["code": code, "otherOrigin": otherOrigin, "queryExplicitInLocation": explicitQuery,
                "targetReached": !targets.isEmpty, "metrics": playback.metrics(), "targets": targets,
                "safety": targets.isEmpty ? "NOT_OBSERVED_THIS_FIXTURE" : "CONFIRMED_GAP_REDIRECT_FOLLOWED",
                "credentialFindingRequiresDistinguishingExplicitLocationQuery": true])
            progress = ["stage": "redirect-matrix", "completedCases": results]
        }
        try attach("vlc-redirect-matrix", ["fixture": "MEASUREMENT_COMPLETED", "cases": results,
            "scope": "Actual VLC network; no claim that a successful measurement means playback is safe"])
    }

    func testRealVLCOwnerRetirementBeforeBodyReleaseRecordsContinuedReadAndDecode() throws {
        let server = try VLCProbeServer(); defer { server.stop() }
        let bytes = try clip(blue: false)
        try validateBaseline(bytes, label: "vlc-retirement-fixture-control")
        let raw = server.add("retire-gated", reply: .video(bytes, cacheable: false, cookie: false), gated: true)
        let account = try VLCProbeAccount(origin: server.origin)
        let context = try account.context()
        let playback = VLCProbePlayer(url: account.owner.addAuthQueryParams(raw)); defer { cleanup(playback) }
        guard until(5, { !server.observations().isEmpty }) else { throw VLCProbeFailure.response }
        let before = playback.metrics()
        account.retire()
        XCTAssertFalse(context.isCurrent)
        server.releaseBody()
        let observed = until(8, { self.decoded(playback) || playback.terminal() })
        let after = playback.metrics()
        progress = ["stage": "retired-body-released", "before": before, "after": after,
                    "requests": server.observations()]
        guard observed else { throw VLCProbeFailure.response }
        let continuedRead = (after["readBytes"] as? Int ?? 0) > (before["readBytes"] as? Int ?? 0)
        let continuedDecode = (after["decoded"] as? Int ?? 0) > (before["decoded"] as? Int ?? 0)
        let explicitlyStopped = cleanup(playback)
        try attach("vlc-owner-retirement", ["fixture": "MEASUREMENT_COMPLETED", "contextRetired": !context.isCurrent,
            "before": before, "after": after, "continuedRead": continuedRead, "continuedDecode": continuedDecode,
            "requests": server.observations(), "explicitStopCompleted": explicitlyStopped,
            "safety": continuedRead || continuedDecode ? "CONFIRMED_GAP_PLAYER_NOT_BOUND_TO_OWNER" : "NOT_OBSERVED_THIS_FIXTURE",
            "scope": "Actual Tinode retirement and VLC dependency; actual VideoPreviewController route NOT_RUN"])
    }

    func testRealVLCReopenChangedContentAnd403RecordsCacheAndCookieBehavior() throws {
        let red = try clip(blue: false); let blue = try clip(blue: true)
        var results = [[String: Any]]()
        for cacheable in [false, true] {
            let server = try VLCProbeServer(); defer { server.stop() }
            let raw = server.add("reopen", reply: .video(red, cacheable: cacheable, cookie: true))
            let account = try VLCProbeAccount(origin: server.origin)
            let url = account.owner.addAuthQueryParams(raw)
            let firstColor = try sampledFrame(url, label: "vlc-cache-first")
            XCTAssertEqual(firstColor, "A_red")
            let firstCount = server.observations().count
            server.replace(raw, reply: .video(blue, cacheable: cacheable, cookie: false))
            let secondColor = try sampledFrame(url, label: "vlc-cache-second")
            guard ["A_red", "B_blue"].contains(secondColor) else { throw VLCProbeFailure.snapshot }
            let secondCount = server.observations().count
            server.replace(raw, reply: .forbidden)
            let third = VLCProbePlayer(url: url)
            let observed = until(5, { self.decoded(third) || third.terminal() })
            let thirdMetrics = third.metrics()
            let decodedDespite403 = (thirdMetrics["decoded"] as? Int ?? 0) > 0 || (thirdMetrics["displayed"] as? Int ?? 0) > 0
            cleanup(third)
            guard observed else {
                progress = ["stage": "reopen-403-timeout", "metrics": thirdMetrics, "completedCases": results]
                throw VLCProbeFailure.response
            }
            results.append(["cacheable": cacheable, "firstFrame": firstColor, "secondFrame": secondColor,
                "secondMadeRequest": secondCount > firstCount,
                "thirdMadeRequest": server.observations().count > secondCount,
                "decodedAfterServerChangedTo403": decodedDespite403, "thirdMetrics": thirdMetrics,
                "requests": server.observations(),
                "safety": secondColor == "A_red" || decodedDespite403 ? "CONFIRMED_GAP_OLD_CONTENT_REUSED" : "NOT_OBSERVED_THIS_FIXTURE",
                "scope": "Same complete synthetic URL; not proof of a persistent disk cache or cross-account exploit"])
            progress = ["stage": "reopen-matrix", "completedCases": results]
        }
        try attach("vlc-reopen-cache-cookie", ["fixture": "MEASUREMENT_COMPLETED", "cases": results])
    }
}

private extension URL {
    // Retain only the synthetic query constructed by the real SDK; destination itself stays local.
    func replacingProbeOrigin(_ destination: URL) -> URL {
        var result = URLComponents(url: destination, resolvingAgainstBaseURL: false)!
        result.queryItems = URLComponents(url: self, resolvingAgainstBaseURL: false)!.queryItems
        return result.url!
    }
}
