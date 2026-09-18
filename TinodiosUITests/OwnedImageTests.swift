import XCTest
import UIKit
import Kingfisher
import TinodeSDK
@testable import TinodiosDB

// Only unrelated avatar rendering dependencies are adapted for this test target.
// Security context, requests, loader and both consumers compile from production files.
enum UiUtils {
    static func letterTileColor(for id: String, dark: Bool) -> UIColor { .gray }
}
extension UIImage {
    var noir: UIImage { self } // These tests never request deleted-avatar rendering.
}

private final class OwnedImageFixture {
    let base: BaseDb
    let store: SqlStore
    var owner: Tinode
    var slot: Tinode?
    var generation: UInt64 = 1
    private let slotLock = NSRecursiveLock()
    let origin = URL(string: "https://owned-fixture.invalid/")!

    init() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("owned-image-" + UUID().uuidString + ".sqlite")
        base = BaseDb(databasePath: file.path)
        store = try XCTUnwrap(base.sqlStore)
        XCTAssertTrue(base.isStoreAvailable)
        store.myUid = "usrOwnedA"
        owner = Tinode(for: "owned-image-fixture", authenticateWith: "fixture-api-key", persistDataIn: store)
        owner.authToken = "synthetic-token-A"
        slot = owner
        // Do not unlink a database with live BaseDb/accessor connections.
    }

    func context() throws -> ClawOwnedImageContext {
        let captured = owner
        return try XCTUnwrap(ClawOwnedImageContext(owner: captured, serviceURL: origin, generation: generation,
            currentGeneration: { self.generation },
            inCurrentSlot: { body in
                self.slotLock.lock(); defer { self.slotLock.unlock() }
                guard self.slot === captured else { return false }
                body()
                return true
            }))
    }

    func logout() {
        owner.logout()
        slotLock.lock(); defer { slotLock.unlock() }
        slot = nil
        generation += 1
    }

    func switchToB() {
        logout()
        store.myUid = "usrOwnedB"
        owner = Tinode(for: "owned-image-fixture", authenticateWith: "fixture-api-key", persistDataIn: store)
        owner.authToken = "synthetic-token-B"
        slot = owner
    }
}

private final class ControlledImageTransport {
    struct Pending {
        let resource: Kingfisher.ImageResource
        let options: KingfisherOptionsInfo
        let completion: ClawOwnedImageLoader.Completion

        func request() -> URLRequest? {
            var request: URLRequest? = URLRequest(url: resource.downloadURL)
            for option in options {
                if case .requestModifier(let modifier) = option, let current = request {
                    request = modifier.modified(for: current)
                }
            }
            return request
        }
    }
    var pending = [Pending]()
    lazy var loader = ClawOwnedImageLoader { resource, options, completion in
        self.pending.append(Pending(resource: resource, options: options, completion: completion))
        return nil
    }
}

private final class CountingImageLayoutManager: NSLayoutManager {
    var redraws = 0
    override func invalidateDisplay(forCharacterRange charRange: NSRange) {
        redraws += 1
        super.invalidateDisplay(forCharacterRange: charRange)
    }
}

final class OwnedImageTests: XCTestCase {
    private func image(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 3, height: 3)).image { context in
            color.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 3, height: 3))
        }
    }

    private func onMain(_ operation: () -> Void) {
        if Thread.isMainThread { operation() } else { DispatchQueue.main.sync(execute: operation) }
    }

    private func drainMain() {
        let done = expectation(description: "queued media consumption completes")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 3)
    }

    func testProductionModifierUsesCapturedHeadersOnlyForSameOrigin() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let transport = ControlledImageTransport()
        let local = fixture.origin.appendingPathComponent("media/avatar")
        let external = try XCTUnwrap(URL(string: "https://signed-fixture.invalid/photo?signature=synthetic"))
        transport.loader.load(from: local, context: context) { _ in }
        transport.loader.load(from: external, context: context) { _ in }
        XCTAssertEqual(transport.pending.count, 2)
        let localRequest = try XCTUnwrap(transport.pending[0].request())
        XCTAssertEqual(localRequest.value(forHTTPHeaderField: "X-Tinode-Auth"), "Token synthetic-token-A")
        let remoteRequest = try XCTUnwrap(transport.pending[1].request())
        XCTAssertNil(remoteRequest.value(forHTTPHeaderField: "X-Tinode-Auth"))
        XCTAssertNil(remoteRequest.value(forHTTPHeaderField: "X-Tinode-APIKey"))
        var contaminated = URLRequest(url: external)
        contaminated.setValue("synthetic-old", forHTTPHeaderField: "Authorization")
        contaminated.setValue("synthetic-old", forHTTPHeaderField: "Cookie")
        XCTAssertNil(context.request(contaminated)?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(context.request(contaminated)?.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(context.redirectedRequest(localRequest))
        XCTAssertTrue(transport.pending[0].options.contains { if case .redirectHandler = $0 { return true }; return false })
        let one = transport.pending[0].options.compactMap { option -> ImageDownloader? in
            if case .downloader(let downloader) = option { return downloader }; return nil
        }.first
        let two = transport.pending[1].options.compactMap { option -> ImageDownloader? in
            if case .downloader(let downloader) = option { return downloader }; return nil
        }.first
        XCTAssertNotNil(one)
        XCTAssertFalse(one === two)
    }

    func testNilResourceFailsActualUtilsPromiseWithoutStartingTransport() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let transport = ControlledImageTransport()
        let failed = expectation(description: "nil URL rejects")
        Utils.fetchTinodeResource(from: nil, context: context, loader: transport.loader).then(
            onSuccess: { _ in XCTFail("nil URL cannot resolve"); failed.fulfill(); return nil },
            onFailure: { error in
                guard case ClawOwnedImageError.invalidURL = error else { XCTFail("Expected typed invalid URL"); failed.fulfill(); return nil }
                failed.fulfill(); return nil
            })
        wait(for: [failed], timeout: 3)
        XCTAssertTrue(transport.pending.isEmpty)
    }

    func testOriginalOwnerGateRejectsRetirementAndStoreOrSlotChange() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let url = fixture.origin.appendingPathComponent("media/file")
        XCTAssertFalse(fixture.owner.isConnectionAuthenticated)
        XCTAssertNotNil(context.request(URLRequest(url: url)), "Offline retained account remains eligible")
        fixture.store.myUid = "usrOwnedB"
        XCTAssertNil(context.request(URLRequest(url: url)))
        fixture.store.myUid = "usrOwnedA"
        fixture.generation += 1
        XCTAssertFalse(context.isCurrent)
        fixture.generation -= 1
        fixture.slot = nil
        XCTAssertFalse(context.isCurrent)
        fixture.slot = fixture.owner
        fixture.owner.logout()
        XCTAssertNil(context.request(URLRequest(url: url)))
    }

    func testRealKingfisherCacheLoadsOfflineAAndCannotServeB() throws {
        let fixture = try OwnedImageFixture()
        let contextA = try fixture.context()
        let url = fixture.origin.appendingPathComponent("media/same-url")
        let resourceA = try XCTUnwrap(contextA.resource(for: url))
        let cache = ImageCache(name: "owned-native-" + UUID().uuidString)
        defer { cache.clearMemoryCache() }
        cache.store(image(.red), forKey: resourceA.cacheKey, toDisk: false)
        let loader = ClawOwnedImageLoader { resource, options, completion in
            KingfisherManager.shared.retrieveImage(with: resource,
                options: options + [.targetCache(cache), .onlyFromCache]) { result in
                    switch result {
                    case .success(let value): completion(.success(value.image))
                    case .failure(let error): completion(.failure(error))
                    }
                }
        }
        let loadedA = expectation(description: "offline A cache hit")
        loader.load(from: url, context: contextA) { result in
            if case .failure = result { XCTFail("A cache should load offline") }
            loadedA.fulfill()
        }
        wait(for: [loadedA], timeout: 3)
        fixture.switchToB()
        let contextB = try fixture.context()
        XCTAssertNotEqual(contextB.resource(for: url)?.cacheKey, resourceA.cacheKey)
        let rejectedB = expectation(description: "B cache miss")
        loader.load(from: url, context: contextB) { result in
            if case .success = result { XCTFail("B must not reuse A image") }
            rejectedB.fulfill()
        }
        wait(for: [rejectedB], timeout: 3)
    }

    func testActualRoundViewKeepsBImageWhenACompletesLate() throws {
        let fixture = try OwnedImageFixture()
        let contextA = try fixture.context()
        let transport = ControlledImageTransport()
        let red = image(.red)
        let blue = image(.blue)
        var avatar: RoundImageView!
        onMain {
            avatar = RoundImageView(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
            avatar.ownedImageLoader = transport.loader
            avatar.ownedImageContextProvider = { contextA }
            avatar.set(pub: TheCard(fn: nil, avatar: Photo(ref: "/media/a")), id: "usrA", deleted: false)
        }
        XCTAssertEqual(transport.pending.count, 1)
        fixture.switchToB()
        let contextB = try fixture.context()
        onMain {
            avatar.ownedImageContextProvider = { contextB }
            avatar.set(pub: TheCard(fn: nil, avatar: Photo(image: blue)), id: "usrB", deleted: false)
        }
        transport.pending[0].completion(.success(red))
        drainMain()
        onMain { XCTAssertTrue(avatar.image === blue) }
    }

    func testActualRoundViewDefaultAndBrandResetsInvalidatePendingImage() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let transport = ControlledImageTransport()
        let red = image(.red)
        for action in 0..<3 {
            var avatar: RoundImageView!
            var expected: UIImage?
            onMain {
                avatar = RoundImageView(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
                avatar.ownedImageLoader = transport.loader
                avatar.ownedImageContextProvider = { context }
                avatar.set(pub: TheCard(fn: nil, avatar: Photo(ref: "/media/a")), id: "usrA", deleted: false)
                if action == 0 { avatar.setIconType(.grp) }
                else if action == 1 { avatar.setBrandingIcon() }
                else { avatar.set(pub: nil, id: "usrNoPhoto", deleted: false) }
                expected = avatar.image
            }
            transport.pending[action].completion(.success(red))
            drainMain()
            onMain { XCTAssertTrue(avatar.image === expected) }
        }
    }

    func testActualAttachmentSuccessPostprocessesAndRedraws() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let transport = ControlledImageTransport()
        let blue = image(.blue)
        let red = image(.red)
        var processed = 0
        var attachment: AsyncImageTextAttachment!
        let manager = CountingImageLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 120, height: 80))
        let text = NSTextStorage(string: "fixture")
        var before = 0
        onMain {
            text.addLayoutManager(manager)
            manager.addTextContainer(container)
            attachment = AsyncImageTextAttachment(url: fixture.origin.appendingPathComponent("media/a"),
                afterDownloaded: { _ in processed += 1; return blue }, context: context, loader: transport.loader)
            _ = attachment.image(forBounds: .zero, textContainer: container, characterIndex: 0)
            before = manager.redraws
            attachment.startDownload(onError: red)
        }
        transport.pending[0].completion(.success(red))
        drainMain()
        onMain {
            XCTAssertEqual(processed, 1)
            XCTAssertTrue(attachment.image === blue)
            XCTAssertGreaterThan(manager.redraws, before)
        }
    }

    func testActualAttachmentLogoutRejectsImageAndRedraw() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let transport = ControlledImageTransport()
        let placeholder = image(.gray)
        var attachment: AsyncImageTextAttachment!
        let manager = CountingImageLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 120, height: 80))
        let text = NSTextStorage(string: "fixture")
        var before = 0
        onMain {
            text.addLayoutManager(manager)
            manager.addTextContainer(container)
            attachment = AsyncImageTextAttachment(url: fixture.origin.appendingPathComponent("media/a"),
                context: context, loader: transport.loader)
            attachment.image = placeholder
            _ = attachment.image(forBounds: .zero, textContainer: container, characterIndex: 0)
            before = manager.redraws
            attachment.startDownload(onError: image(.red))
        }
        fixture.logout()
        transport.pending[0].completion(.success(image(.blue)))
        drainMain()
        onMain {
            XCTAssertTrue(attachment.image === placeholder)
            XCTAssertEqual(manager.redraws, before)
        }
    }

    func testActualAttachmentURLReplacementRejectsOldRequest() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let transport = ControlledImageTransport()
        let old = image(.red)
        let current = image(.blue)
        var attachment: AsyncImageTextAttachment!
        onMain {
            attachment = AsyncImageTextAttachment(url: fixture.origin.appendingPathComponent("media/a"),
                context: context, loader: transport.loader)
            attachment.startDownload(onError: old)
            attachment.url = fixture.origin.appendingPathComponent("media/b")
            attachment.startDownload(onError: old)
        }
        transport.pending[0].completion(.success(old))
        transport.pending[1].completion(.success(current))
        drainMain()
        onMain { XCTAssertTrue(attachment.image === current) }
    }

    func testActualUtilsPromiseSettlesAfterOwnerRetiresWithoutSuccess() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let transport = ControlledImageTransport()
        let completed = expectation(description: "retired media promise rejects")
        Utils.fetchTinodeResource(from: fixture.origin.appendingPathComponent("media/a"),
            context: context, loader: transport.loader).then(
                onSuccess: { _ in XCTFail("retired owner cannot resolve an image"); completed.fulfill(); return nil },
                onFailure: { error in
                    guard case ClawOwnedImageError.sessionExpired = error else {
                        XCTFail("Expected session expiry"); completed.fulfill(); return nil
                    }
                    completed.fulfill(); return nil
                })
        fixture.logout()
        transport.pending[0].completion(.success(image(.blue)))
        wait(for: [completed], timeout: 3)
    }
}


// Actual URLSession download tasks use this URLProtocol. No real account or external server is contacted.
private final class OwnedFileProtocol: URLProtocol {
    enum Reply { case body(Int, Data), unknownLength(Data), declaredLength(Data, Int), failure, redirect(URL) }
    static let handlerLock = NSLock()
    static var handler: ((URLRequest, @escaping (Reply) -> Void) -> Void)?
    private let stateLock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.handlerLock.lock()
        let handler = Self.handler
        Self.handlerLock.unlock()
        guard let handler = handler else { emit(.failure); return }
        handler(request) { [weak self] in self?.emit($0) }
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
    private func emit(_ reply: Reply) {
        stateLock.lock(); let wasStopped = stopped; stateLock.unlock()
        guard !wasStopped else { return }
        switch reply {
        case let .body(status, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": String(body.count), "Content-Type": "application/octet-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .unknownLength(body):
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/octet-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .declaredLength(body, length):
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": String(length)])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        case let .redirect(target):
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        }
    }
    static func respond(_ handler: @escaping (URLRequest, @escaping (Reply) -> Void) -> Void) {
        handlerLock.lock(); defer { handlerLock.unlock() }
        self.handler = handler
    }
}

extension OwnedImageTests {
    private func downloaded(context: ClawOwnedImageContext, url: URL,
                            root: URL = FileManager.default.temporaryDirectory,
                            budget: ClawVideoDownloadBudget? = nil) throws -> Swift.Result<URL, Error> {
        let done = expectation(description: "owned download completes exactly once")
        var captured: Swift.Result<URL, Error>?
        let operation = ClawOwnedFileDownload(context: context, suggestedName: "../same.mp4", root: root,
                                             protocolClasses: [OwnedFileProtocol.self], budget: budget) { result in
            XCTAssertTrue(Thread.isMainThread)
            captured = result
            done.fulfill()
        }
        operation.start(from: url)
        wait(for: [done], timeout: 5)
        withExtendedLifetime(operation) {}
        return try XCTUnwrap(captured)
    }

    func testFileDownloadConfigurationAndFrozenHeadersAreAccountScoped() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let operation = ClawOwnedFileDownload(context: context, suggestedName: nil) { _ in }
        fixture.owner.authToken = "synthetic-rotated-token"
        let request = try XCTUnwrap(operation.request(from: fixture.origin.appendingPathComponent("media/a")))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Tinode-Auth"), "Token synthetic-token-A")
        let external = try XCTUnwrap(context.resourceURL(from: "//external-fixture.invalid/a"))
        XCTAssertNil(operation.request(from: external)?.value(forHTTPHeaderField: "X-Tinode-Auth"))
        XCTAssertNil(operation.request(from: external)?.value(forHTTPHeaderField: "X-Tinode-APIKey"))
        for text in ["http://external-fixture.invalid/a", "file:///tmp/a", "ftp://external-fixture.invalid/a",
                     "https://user:password@owned-fixture.invalid/a"] {
            XCTAssertNil(operation.request(from: URL(string: text)!))
        }
        let config = ClawOwnedFileDownload.configuration()
        XCTAssertNil(config.identifier)
        XCTAssertNil(config.urlCache)
        XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage)
        XCTAssertFalse(config.httpShouldSetCookies)
        XCTAssertEqual(config.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testActualFileDownloadRequestsKeepExternalAnonymousAndPreserveBytes() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let bytes = Data([0, 1, 2, 3, 255])
        for url in [fixture.origin.appendingPathComponent("media/a"), URL(string: "https://external-fixture.invalid/a")!] {
            OwnedFileProtocol.respond { request, reply in
                if request.url?.host == fixture.origin.host {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Tinode-Auth"), "Token synthetic-token-A")
                } else {
                    XCTAssertNil(request.value(forHTTPHeaderField: "X-Tinode-Auth"))
                    XCTAssertNil(request.value(forHTTPHeaderField: "X-Tinode-APIKey"))
                }
                XCTAssertFalse(request.httpShouldHandleCookies)
                XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
                reply(.body(200, bytes))
            }
            let file = try downloaded(context: context, url: url).get()
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            XCTAssertEqual(file.lastPathComponent, "same.mp4")
            ClawMediaFiles.removeExport(file)
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testActualFileDownloadRejectsRedirectBeforeTargetRequest() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        for target in [fixture.origin.appendingPathComponent("target"), URL(string: "https://redirect-target.invalid/a")!] {
            var targets = 0
            OwnedFileProtocol.respond { request, reply in
                if request.url == target { targets += 1; reply(.body(200, Data([1]))) }
                else { reply(.redirect(target)) }
            }
            let result = try downloaded(context: context, url: fixture.origin.appendingPathComponent("redirect"))
            guard case let .failure(error) = result, case ClawFileTransferError.redirect = error else {
                return XCTFail("Expected redirect rejection")
            }
            XCTAssertEqual(targets, 0)
        }
    }

    func testActualFileDownloadRejectsHTTPErrorPartialAndEmptyBodies() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        for (status, bytes) in [(403, Data("forbidden".utf8)), (206, Data([1])), (204, Data()), (200, Data())] {
            OwnedFileProtocol.respond { _, reply in reply(.body(status, bytes)) }
            let result = try downloaded(context: context, url: fixture.origin.appendingPathComponent("failure"))
            guard case .failure = result else { return XCTFail("Invalid response must not produce a share file") }
        }
    }

    func testActualFileDownloadNetworkFailureCompletesAndCanRetry() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let url = fixture.origin.appendingPathComponent("retry")
        OwnedFileProtocol.respond { _, reply in reply(.failure) }
        guard case let .failure(error) = try downloaded(context: context, url: url),
              case ClawFileTransferError.network = error else {
            return XCTFail("Expected network failure")
        }
        OwnedFileProtocol.respond { _, reply in reply(.body(200, Data([7, 8]))) }
        let file = try downloaded(context: context, url: url).get()
        XCTAssertEqual(try Data(contentsOf: file), Data([7, 8]))
        ClawMediaFiles.removeExport(file)
    }

    func testActualFileDownloadLateResponseRejectsAccountAndSameUIDGenerationChange() throws {
        for swapAccount in [false, true] {
            let fixture = try OwnedImageFixture()
            let context = try fixture.context()
            let started = expectation(description: "original request observed")
            let completed = expectation(description: "stale owner completes with failure")
            var release: ((OwnedFileProtocol.Reply) -> Void)?
            OwnedFileProtocol.respond { request, reply in
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Tinode-Auth"), "Token synthetic-token-A")
                release = reply
                started.fulfill()
            }
            let operation = ClawOwnedFileDownload(context: context, suggestedName: nil,
                                                  protocolClasses: [OwnedFileProtocol.self]) { result in
                guard case .failure = result else { XCTFail("Old media must not become a share file"); completed.fulfill(); return }
                completed.fulfill()
            }
            operation.start(from: fixture.origin.appendingPathComponent("late"))
            wait(for: [started], timeout: 5)
            if swapAccount { fixture.switchToB() } else { fixture.generation += 1 }
            try XCTUnwrap(release)(.body(200, Data([1, 2])))
            wait(for: [completed], timeout: 5)
            XCTAssertNil(operation.request(from: fixture.origin))
        }
    }

    func testActualFileDownloadCancellationCompletesOnceAndNeverContactsAfterEarlyCancel() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        var requests = 0
        OwnedFileProtocol.respond { _, _ in requests += 1 }
        let complete = expectation(description: "cancel once")
        var completions = 0
        let operation = ClawOwnedFileDownload(context: context, suggestedName: nil,
                                              protocolClasses: [OwnedFileProtocol.self]) { result in
            completions += 1
            guard case let .failure(error) = result, case ClawFileTransferError.cancelled = error else {
                XCTFail("Expected cancel"); complete.fulfill(); return
            }
            complete.fulfill()
        }
        operation.cancel()
        operation.cancel()
        operation.start(from: fixture.origin)
        wait(for: [complete], timeout: 5)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(requests, 0)
    }

    func testActualFileDownloadWriteFailureDoesNotOverwriteSuppliedRoot() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let rootFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sentinel = Data("keep-root".utf8)
        try sentinel.write(to: rootFile)
        defer { try? FileManager.default.removeItem(at: rootFile) }
        OwnedFileProtocol.respond { _, reply in reply(.body(200, Data([1]))) }
        guard case let .failure(error) = try downloaded(context: context,
            url: fixture.origin.appendingPathComponent("write-failure"), root: rootFile),
              case ClawFileTransferError.write = error else {
            return XCTFail("Expected write failure")
        }
        XCTAssertEqual(try Data(contentsOf: rootFile), sentinel)
    }

    func testActualFilePresentationGateRejectsOldAttemptOwnerAndOffMainConsumption() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let slot = ClawOwnedImageSlot()
        let attempt = slot.invalidate()
        let presentation = ClawOwnedFilePresentation(context: context, attemptIsCurrent: { slot.accepts(attempt) })
        var presented = 0
        onMain { XCTAssertTrue(presentation.consume { presented += 1 }) }
        slot.invalidate()
        onMain { XCTAssertFalse(presentation.consume { presented += 1 }) }
        let current = ClawOwnedFilePresentation(context: context, attemptIsCurrent: { true })
        fixture.switchToB()
        onMain { XCTAssertFalse(current.consume { presented += 1 }) }
        XCTAssertEqual(presented, 1)
        let background = expectation(description: "presentation rejects background queue")
        DispatchQueue.global().async {
            XCTAssertFalse(presentation.consume { XCTFail("UIKit callback cannot run on worker queue") })
            background.fulfill()
        }
        wait(for: [background], timeout: 5)
    }
}


extension OwnedImageTests {
    func testActualFileDownloadCancelInFlightCompletesOnlyOnce() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let started = expectation(description: "download started")
        let completed = expectation(description: "in-flight cancellation completes")
        var release: ((OwnedFileProtocol.Reply) -> Void)?
        OwnedFileProtocol.respond { _, reply in release = reply; started.fulfill() }
        var count = 0
        let operation = ClawOwnedFileDownload(context: context, suggestedName: nil,
                                              protocolClasses: [OwnedFileProtocol.self]) { result in
            count += 1
            guard case let .failure(error) = result, case ClawFileTransferError.cancelled = error else {
                XCTFail("Expected cancelled result"); completed.fulfill(); return
            }
            completed.fulfill()
        }
        operation.start(from: fixture.origin)
        wait(for: [started], timeout: 5)
        operation.cancel()
        operation.cancel()
        release?(.body(200, Data([1, 2])))
        wait(for: [completed], timeout: 5)
        drainMain()
        XCTAssertEqual(count, 1)
    }

    func testActualFileTerminalConsumerRestoresCurrentButtonForFailureAndSuccess() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let slot = ClawOwnedImageSlot()
        for fail in [true, false] {
            let ticket = slot.invalidate()
            let presentation = ClawOwnedFilePresentation(context: context, attemptIsCurrent: { slot.accepts(ticket) })
            var button: UIBarButtonItem!
            onMain {
                button = UIBarButtonItem(title: "分享视频", style: .plain, target: nil, action: nil)
                button.isEnabled = false
            }
            let done = expectation(description: "actual main consumer restores current button")
            var successes = 0
            var failures = 0
            OwnedFileProtocol.respond { _, reply in reply(fail ? .failure : .body(200, Data([1, 2]))) }
            let operation = ClawOwnedFileDownload(context: context, suggestedName: nil,
                                                  protocolClasses: [OwnedFileProtocol.self]) { result in
                presentation.complete(result, restore: { button.isEnabled = true },
                    success: { file in successes += 1; ClawMediaFiles.removeExport(file) },
                    failure: { _ in failures += 1 })
                XCTAssertTrue(button.isEnabled)
                done.fulfill()
            }
            operation.start(from: fixture.origin)
            wait(for: [done], timeout: 5)
            XCTAssertEqual(successes, fail ? 0 : 1)
            XCTAssertEqual(failures, fail ? 1 : 0)
        }
    }
}


// These methods execute the production budget/download/lease with actual SDK and SQLite owners.
// The stop notification here is a controlled callback boundary; the VLC host separately runs the real player.
extension OwnedImageTests {
    func testVideoBudgetChecksTwoCopiesReserveOverflowAndRealFilesystem() throws {
        let root = FileManager.default.temporaryDirectory
        let limit: Int64 = 1024
        var required: Int64 = 0
        let exact = ClawVideoDownloadBudget(maximumBytes: limit) { _ in
            required = 2 * limit + ClawVideoDownloadBudget.reserveBytes
            return required
        }
        XCTAssertNoThrow(try exact.preflight(at: root))
        XCTAssertEqual(required, 16 * 1024 * 1024 + 2048)
        XCTAssertThrowsError(try ClawVideoDownloadBudget(maximumBytes: limit,
            availableBytes: { _ in required - 1 }).preflight(at: root)) {
                guard case ClawFileTransferError.insufficientSpace = $0 else { return XCTFail("wrong space category") }
            }
        for invalid in [Int64(0), -1, Int64.max, Int64.max / 2] {
            XCTAssertThrowsError(try ClawVideoDownloadBudget(maximumBytes: invalid,
                availableBytes: { _ in XCTFail("overflow must fail before space query"); return Int64.max }).preflight(at: root))
        }
        // Use the actual filesystem accessor, without assuming the runner has a particular free capacity.
        let actual = ClawVideoDownloadBudget(maximumBytes: 1)
        do { try actual.preflight(at: root) }
        catch { guard case ClawFileTransferError.insufficientSpace = error else { throw error } }
        let fixture = try OwnedImageFixture()
        XCTAssertEqual(try ClawVideoDownloadBudget.captured(from: fixture.context()).maximumBytes, 8 * 1024 * 1024)
    }

    func testVideoDownloadRejectsKnownAndUnknownLengthOversize() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let budget = ClawVideoDownloadBudget(maximumBytes: 4, availableBytes: { _ in Int64.max })
        for unknown in [false, true] {
            OwnedFileProtocol.respond { _, reply in
                reply(unknown ? .unknownLength(Data(repeating: 8, count: 32)) : .body(200, Data(repeating: 8, count: 32)))
            }
            let result = try downloaded(context: context, url: fixture.origin, budget: budget)
            guard case let .failure(error) = result, case ClawFileTransferError.tooLarge = error else {
                return XCTFail("An oversized body must never become a playback file")
            }
        }
        XCTAssertThrowsError(try budget.checkProgress(written: 1, expected: 5))
        XCTAssertThrowsError(try budget.checkProgress(written: 5, expected: -1))
        XCTAssertNoThrow(try budget.checkProgress(written: 4, expected: -1))
    }

    func testVideoBudgetRechecksActualFileAndPreservesBoundedDownload() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let budget = ClawVideoDownloadBudget(maximumBytes: 4, availableBytes: { _ in Int64.max })
        let file = try ClawMediaFiles.exportData(Data([1, 2, 3, 4]), suggestedName: "check.mp4")
        defer { ClawMediaFiles.removeExport(file) }
        XCTAssertNoThrow(try budget.checkFile(file))
        try Data([1, 2, 3, 4, 5]).write(to: file)
        XCTAssertThrowsError(try budget.checkFile(file)) {
            guard case ClawFileTransferError.tooLarge = $0 else { return XCTFail("wrong final-file category") }
        }
        OwnedFileProtocol.respond { _, reply in reply(.unknownLength(Data([9, 8, 7, 6]))) }
        let downloadedFile = try downloaded(context: context, url: fixture.origin, budget: budget).get()
        XCTAssertEqual(try Data(contentsOf: downloadedFile), Data([9, 8, 7, 6]))
        XCTAssertTrue(ClawMediaFiles.removeExport(downloadedFile))
        OwnedFileProtocol.respond { _, reply in reply(.declaredLength(Data([1, 2]), 4)) }
        guard case .failure = try downloaded(context: context, url: fixture.origin, budget: budget) else {
            return XCTFail("A truncated 200 body must not become a playback file")
        }
    }

    func testVideoDownloadSpaceFailuresNeverStartTransport() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        var requests = 0
        OwnedFileProtocol.respond { _, reply in requests += 1; reply(.body(200, Data([1]))) }
        for unavailable in [false, true] {
            let budget = ClawVideoDownloadBudget(maximumBytes: 100) { _ in
                if unavailable { throw CocoaError(.fileReadUnknown) }
                return 1
            }
            let result = try downloaded(context: context, url: fixture.origin, budget: budget)
            guard case let .failure(error) = result else { return XCTFail("space gate must reject") }
            if unavailable {
                guard case ClawFileTransferError.spaceUnavailable = error else { return XCTFail("wrong query category") }
            } else {
                guard case ClawFileTransferError.insufficientSpace = error else { return XCTFail("wrong low-space category") }
            }
        }
        XCTAssertEqual(requests, 0)
    }

    func testPlaybackLeaseRejectsRetiredOwnerAtQueuedMainConsumption() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let oldFile = try ClawMediaFiles.exportData(Data([1]), suggestedName: "a.mp4")
        fixture.switchToB()
        let newFile = try ClawMediaFiles.exportData(Data([2]), suggestedName: "b.mp4")
        defer { ClawMediaFiles.removeExport(newFile) }
        let delivered = expectation(description: "queued old owner cannot play")
        DispatchQueue.main.async {
            let player = NSObject()
            let lease = ClawOwnedPlaybackLease(context: context, ownedFile: oldFile, player: player,
                stop: {}, isStopped: { true }, detach: {}, releaseMedia: {})
            XCTAssertFalse(lease.play { XCTFail("retired A must not start") })
            XCTAssertTrue(lease.cleaned)
            XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path))
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 3)
        XCTAssertEqual(fixture.store.myUid, "usrOwnedB")
    }

    func testPlaybackLeaseRequiresStoppedEventAndRetainsFileAfterTimeout() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let file = try ClawMediaFiles.exportData(Data([1]), suggestedName: "owned.mp4")
        let player = NSObject()
        var stopped = false
        var stops = 0
        var lease: ClawOwnedPlaybackLease!
        onMain {
            lease = ClawOwnedPlaybackLease(context: context, ownedFile: file, player: player,
                stop: { stops += 1 }, isStopped: { stopped }, detach: {}, releaseMedia: {})
            XCTAssertTrue(lease.play {})
            lease.retire(); lease.retire()
            stopped = true // Cached state alone is deliberately insufficient.
        }
        let elapsed = expectation(description: "fixed stop deadline retains responsibility")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.1) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: 6)
        onMain {
            XCTAssertTrue(lease.cleanupPending)
            XCTAssertFalse(lease.cleaned)
            XCTAssertEqual(stops, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
            NotificationCenter.default.post(name: Notification.Name("VLCMediaPlayerStateChanged"), object: player)
            XCTAssertTrue(lease.cleaned)
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testPlaybackLeaseOfflineOwnerAndLocalSourceArePreservedUntilRetirement() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data([1, 2]).write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }
        var lease: ClawOwnedPlaybackLease!
        onMain {
            lease = ClawOwnedPlaybackLease(context: context, ownedFile: nil, player: NSObject(),
                stop: {}, isStopped: { true }, detach: {}, releaseMedia: {})
            XCTAssertFalse(fixture.owner.isConnectionAuthenticated)
            XCTAssertTrue(lease.checkOwner())
        }
        fixture.logout()
        onMain {
            XCTAssertFalse(lease.checkOwner())
            XCTAssertTrue(lease.cleaned)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.path))
        XCTAssertFalse(ClawMediaFiles.removeExport(local))
    }

    func testPlaybackRetirementCannotStopNewAttemptOrDeleteShareFile() throws {
        let fixture = try OwnedImageFixture()
        let context = try fixture.context()
        let old = try ClawMediaFiles.exportData(Data([1]), suggestedName: "play.mp4")
        let share = try ClawMediaFiles.exportData(Data([1]), suggestedName: "share.mp4")
        let next = try ClawMediaFiles.exportData(Data([2]), suggestedName: "next.mp4")
        defer { ClawMediaFiles.removeExport(share) }
        let a = NSObject(), b = NSObject()
        var stoppedA = false, stoppedB = false, stopsA = 0, stopsB = 0
        onMain {
            let first = ClawOwnedPlaybackLease(context: context, ownedFile: old, player: a,
                stop: { stopsA += 1 }, isStopped: { stoppedA }, detach: {}, releaseMedia: {})
            let second = ClawOwnedPlaybackLease(context: context, ownedFile: next, player: b,
                stop: { stopsB += 1 }, isStopped: { stoppedB }, detach: {}, releaseMedia: {})
            XCTAssertTrue(first.play {}); XCTAssertTrue(second.play {})
            first.retire()
            stoppedA = true
            NotificationCenter.default.post(name: Notification.Name("VLCMediaPlayerStateChanged"), object: a)
            XCTAssertTrue(first.cleaned)
            XCTAssertFalse(second.retired)
            XCTAssertEqual(stopsA, 1); XCTAssertEqual(stopsB, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: next.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: share.path))
            second.retire(); stoppedB = true
            NotificationCenter.default.post(name: Notification.Name("VLCMediaPlayerStateChanged"), object: b)
            XCTAssertTrue(second.cleaned)
        }
    }
}
