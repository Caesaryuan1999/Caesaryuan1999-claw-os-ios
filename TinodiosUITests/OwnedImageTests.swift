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
