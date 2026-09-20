// Copyright (c) 2026 CLAW OS contributors.
// Actual formatter, cell, layout and owned image consumers. Synthetic messages
// and an isolated SDK/SQLite slot are not login or a live chat journey.
import XCTest
import UIKit
import Network
import TinodeSDK
@testable import TinodiosDB
@testable import Tinodios

final class ImageMessageLayoutTests: XCTestCase {
    private enum Failure: Error { case initialState, deadline, drawing }
    private var window: UIWindow?
    private var previousWindow: UIWindow?
    private var root: UIViewController?
    private var imageStageSnapshot: (() -> [String: Any])?

    private func main<T>(_ body: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try body() }
        return try DispatchQueue.main.sync(execute: body)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try main {
            guard Bundle.main.bundleIdentifier == "app.veilping.clawoschat",
                  Bundle.main.object(forInfoDictionaryKey: "HOST_NAME") as? String == "127.0.0.1:9",
                  Bundle.main.object(forInfoDictionaryKey: "USE_TLS") as? String == "NO",
                  SharedUtils.getAuthToken() == nil, Cache.tinode.myUid == nil,
                  Cache.tinode.store?.myUid == nil, !Cache.tinode.isConnectionAuthenticated else {
                throw Failure.initialState
            }
            previousWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
            let host = UIViewController()
            host.view.backgroundColor = ClawTheme.background
            let value: UIWindow
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) {
                value = UIWindow(windowScene: scene)
            } else { throw Failure.initialState }
            value.frame = UIScreen.main.bounds; value.rootViewController = host
            root = host; window = value; value.makeKeyAndVisible()
        }
    }

    override func tearDownWithError() throws {
        main {
            imageStageSnapshot = nil
            window?.isHidden = true; window = nil; root = nil
            previousWindow?.makeKey(); previousWindow = nil
        }
    }

    func testFullFormatterPreservesOrdinaryGeometryAndUsesDecodedBeforeUnknown() throws {
        try main {
            let decoded = pattern(width: 80, height: 40)
            let bytes = try XCTUnwrap(decoded.pngData())
            let decodedBytes = try XCTUnwrap(UIImage(data: bytes))
            let formatter = FullFormatter(defaultAttributes: [.font: UIFont.systemFont(ofSize: 16)])
            let maximum = CGSize(width: 400, height: 500)
            for (w, h) in [(800, 400), (32, 64), (0, 0)] {
                let draft = try self.draft(width: w, height: h, bits: bytes)
                let actual = try attachment(formatter.toAttributed(draft, fitIn: maximum))
                let original = w > 0 ? CGSize(width: w, height: h) : decodedBytes.size
                XCTAssertNil(actual.imageCanvas)
                XCTAssertEqual(actual.bounds.size, UiUtils.sizeUnder(original: original, fitUnder: maximum, scale: 1, clip: false).dst)
            }
            let metadataWins = try attachment(formatter.toAttributed(try draft(width: 100, height: 400, bits: bytes), fitIn: maximum))
            XCTAssertEqual(metadataWins.imageCanvas?.mode, .longTop)
            XCTAssertEqual(metadataWins.bounds.size, CGSize(width: 240, height: 320))
            let decodedLong = try attachment(formatter.toAttributed(try draft(width: 0, height: 0,
                bits: XCTUnwrap(pattern(width: 40, height: 160).pngData())), fitIn: maximum))
            XCTAssertEqual(decodedLong.imageCanvas?.mode, .longTop)
            let unknown = try attachment(formatter.toAttributed(try draft(width: 0, height: 0, bits: Data([1])), fitIn: maximum))
            XCTAssertEqual(unknown.imageCanvas?.mode, .unknownFit)
            XCTAssertEqual(unknown.bounds.size, CGSize(width: 240, height: 160))
            for width in [CGFloat.zero, -1, .infinity, .nan] {
                XCTAssertEqual(formatter.toAttributed(try draft(width: 100, height: 400, bits: bytes),
                    fitIn: CGSize(width: width, height: 400)).length, 0)
            }
            let narrow = try attachment(formatter.toAttributed(try draft(width: 100, height: 400, bits: bytes),
                fitIn: CGSize(width: 120, height: 400)))
            XCTAssertEqual(narrow.bounds.size, CGSize(width: 120, height: 160))
            let quote = QuoteFormatter(defaultAttributes: [.font: UIFont.systemFont(ofSize: 16)], defaultFont: .systemFont(ofSize: 16))
            let quoted = try attachment(quote.toAttributed(try draft(width: 100, height: 400, bits: bytes), fitIn: maximum))
            XCTAssertNil(quoted.imageCanvas)
            var video = Attachment(content: .video)
            video.width = 80; video.height = 40; video.preview = bytes
            let node = FormatNode(); node.attachment(video)
            let videoAttachment = try attachment(node.toAttributed(withAttributes: [.font: UIFont.systemFont(ofSize: 16)], fontTraits: nil, fitIn: maximum))
            XCTAssertNil(videoAttachment.imageCanvas)
        }
    }

    func testLongTopAndUnknownFitRenderActualPixelsWithoutChangingCanvas() throws {
        try main {
            let source = pattern(width: 100, height: 400)
            let long = try XCTUnwrap(ClawImageCanvas(width: 100, height: 400, decoded: source, maximum: CGSize(width: 240, height: 400)))
            let top = long.rendered(source)
            XCTAssertEqual(top.size, CGSize(width: 240, height: 320))
            XCTAssertGreaterThan(try pixel(top, x: 0.5, y: 0.15)[0], 200)
            XCTAssertLessThan(try pixel(top, x: 0.5, y: 0.15)[2], 30)
            let unknown = try XCTUnwrap(ClawImageCanvas(width: nil, height: nil, decoded: nil, maximum: CGSize(width: 240, height: 400)))
            let fit = unknown.rendered(source)
            XCTAssertEqual(fit.size, CGSize(width: 240, height: 160))
            XCTAssertEqual(try pixel(fit, x: 0.1, y: 0.5)[3], 0)
            XCTAssertGreaterThan(try pixel(fit, x: 0.5, y: 0.85)[2], 200)
            XCTAssertEqual(unknown.size, CGSize(width: 240, height: 160))
            for (name, image) in [("long-top-pixels", top), ("unknown-fit-pixels", fit)] {
                let item = XCTAttachment(image: image); item.name = "image-v1-" + name; item.lifetime = .keepAlways; add(item)
            }
        }
    }

    func testActualMessageCellLongImageInBothDirectionsAndAccessibilityAppearances() throws {
        try main {
            let bytes = try XCTUnwrap(pattern(width: 100, height: 400).pngData())
            for dark in [false, true] {
                for outgoing in [false, true] {
                    for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
                        let controller = try mount(width: 320, context: nil, category: category, dark: dark)
                        defer { unmount(controller) }
                        let message = try self.message(width: 100, height: 400, bits: bytes, outgoing: outgoing)
                        let cell = try show(message, on: controller)
                        let image = try attachment(cell.content.attributedText)
                        let overlay = try XCTUnwrap(descendants(cell).compactMap { $0 as? ClawImageStateView }.first)
                        XCTAssertEqual(image.imageCanvas?.mode, .longTop)
                        XCTAssertLessThanOrEqual(image.bounds.width, 240)
                        XCTAssertEqual(image.bounds.height / image.bounds.width, 4.0 / 3.0, accuracy: 0.001)
                        XCTAssertEqual(overlay.bounds.width, image.bounds.width, accuracy: 1e-9)
                        XCTAssertEqual(overlay.bounds.height, image.bounds.height, accuracy: 1e-9)
                        XCTAssertEqual(overlay.badge.text, "长图"); XCTAssertFalse(overlay.badge.isHidden)
                        XCTAssertTrue(overlay.retryButton.isHidden)
                        XCTAssertNil(overlay.hitTest(CGPoint(x: 20, y: 20), with: nil))
                        XCTAssertTrue(cell.contentView.bounds.insetBy(dx: -1, dy: -1).contains(overlay.frame))
                        XCTAssertTrue(controller.collectionView.collectionViewLayout is MessageViewLayout)
                        try capture("long-\(outgoing ? "out" : "in")-\(dark ? "dark" : "light")-\(category == .large ? "standard" : "ax")", controller: controller, attachment: image, overlay: overlay)
                    }
                }
            }
        }
    }

    func testOwnedAttachmentRetryKeepsCanvasAndRejectsCancelledAndRetiredCallbacks() throws {
        let owner = try ImageOwner(origin: URL(string: "http://127.0.0.1:9/")!)
        defer { owner.retire() }
        var completions = [ClawOwnedImageLoader.Completion]()
        var delivered = 0
        let loader = ClawOwnedImageLoader { _, _, callback in
            completions.append { result in delivered += 1; callback(result) }
            return nil
        }
        let value = try main { try asyncAttachment(owner: owner, loader: loader) }
        let context = try owner.context()
        main {
            imageStageSnapshot = {
                self.imageFields(value, context: context).merging([
                    "transport_requests": completions.count, "controlled_callbacks": delivered
                ]) { _, right in right }
            }
        }
        let consumer = UUID()
        main {
            value.bindImageConsumer(consumer, isCurrent: { true }, changed: {})
            value.startDownload(onError: value.imageCanvas!.rendered(nil))
            XCTAssertEqual(completions.count, 1)
            completions[0](.failure(Failure.drawing))
        }
        try until("first failure") { value.imageState == .failed }
        main { XCTAssertTrue(value.retryImage()); XCTAssertEqual(completions.count, 2) }
        let fixed = main { value.bounds }
        main { completions[1](.success(self.pattern(width: 60, height: 180))) }
        try until("fixed fit success") { value.imageState == .ready }
        main { XCTAssertEqual(value.bounds, fixed); XCTAssertEqual(value.image?.size, fixed.size) }
        main {
            value.startDownload(onError: value.imageCanvas!.rendered(nil))
            XCTAssertEqual(completions.count, 3)
            value.unbindImageConsumer(consumer)
            completions[2](.success(self.pattern(width: 10, height: 10)))
        }
        try drainMain()
        main { XCTAssertEqual(value.imageState, .failed); XCTAssertFalse(value.retryImage()) }
        main {
            value.bindImageConsumer(UUID(), isCurrent: { true }, changed: {})
            XCTAssertTrue(value.retryImage()); XCTAssertEqual(completions.count, 4)
            completions[3](.success(self.pattern(width: 10, height: 10)))
        }
        try until("explicit rebind retry") { value.imageState == .ready }
        owner.retire()
        main {
            value.bindImageConsumer(UUID(), isCurrent: { true }, changed: {})
            XCTAssertFalse(value.retryImage()); XCTAssertEqual(completions.count, 4)
        }
    }

    func testActualRetryConsumerRechecksEntityPageBulkSelectionAndReuse() throws {
        let owner = try ImageOwner(origin: URL(string: "http://127.0.0.1:9/")!)
        defer { owner.retire() }
        var callbacks = [ClawOwnedImageLoader.Completion]()
        var delivered = 0
        let loader = ClawOwnedImageLoader { _, _, callback in
            callbacks.append { result in delivered += 1; callback(result) }
            return nil
        }
        let controller = try main { try mount(width: 320, context: owner.context()) }
        defer { main { unmount(controller) } }
        let value = try main { try asyncAttachment(owner: owner, loader: loader) }
        let context = try XCTUnwrap(controller.context)
        main {
            imageStageSnapshot = {
                self.imageFields(value, context: context).merging([
                    "transport_requests": callbacks.count, "controlled_callbacks": delivered,
                    "page_current": controller.voiceScopeIsCurrent()
                ]) { _, right in right }
            }
        }
        let model = try main { try message(width: 0, height: 0, bits: Data([1]), ref: value.url) }
        let cell = try main { () -> MessageCell in
            model.cachedContent = NSAttributedString(attachment: value)
            let cell = try show(model, on: controller)
            value.startDownload(onError: value.imageCanvas!.rendered(nil))
            callbacks[0](.failure(Failure.drawing))
            return cell
        }
        try until("retry available") { value.imageState == .failed }
        try main {
            let action = try XCTUnwrap(value.imageActionURL)
            controller.voicePageActive = false
            controller.didTapContent(in: cell, url: action); XCTAssertEqual(callbacks.count, 1)
            controller.voicePageActive = true
            model.content?.entities?.first?.data?["width"] = .int(12)
            controller.didTapContent(in: cell, url: action); XCTAssertEqual(callbacks.count, 1)
            model.content?.entities?.first?.data?["width"] = .int(0)
            controller.bulkSelectionMode = true
            controller.didTapContent(in: cell, url: action); XCTAssertEqual(callbacks.count, 1)
            controller.bulkSelectionMode = false
            XCTAssertTrue(controller.isImageCurrent(in: cell, attachment: value))
            // The same production URL consumer also guards the new ready path.
            value.displayImageState(.ready)
            let preview = try XCTUnwrap(value.imageActionURL)
            controller.didTapContent(in: cell, url: preview)
            XCTAssertEqual(controller.previews.count, 1)
            if case .rawdata(let bits, let ref) = controller.previews[0].imgContent {
                XCTAssertEqual(bits, Data([1])); XCTAssertEqual(ref, value.url.absoluteString)
            } else { XCTFail("Original image source changed") }
            controller.voicePageActive = false
            controller.didTapContent(in: cell, url: preview); XCTAssertEqual(controller.previews.count, 1)
            controller.voicePageActive = true
            model.content?.entities?.first?.data?["width"] = .int(12)
            controller.didTapContent(in: cell, url: preview); XCTAssertEqual(controller.previews.count, 1)
            model.content?.entities?.first?.data?["width"] = .int(0)
            controller.didTapContent(in: cell, url: URL(string: "tinode:///image/preview?key=0&binding=invalid"))
            XCTAssertEqual(controller.previews.count, 1)
            value.displayImageState(.failed)
            controller.didTapContent(in: cell, url: action); XCTAssertEqual(callbacks.count, 2)
            // A real window detach cancels this in-flight binding. Reattach and
            // layout alone must never restart it; only the explicit action can.
            controller.view.removeFromSuperview()
            XCTAssertEqual(value.imageState, .failed)
            root?.view.addSubview(controller.view)
            cell.setNeedsLayout(); cell.layoutIfNeeded()
            cell.setNeedsLayout(); cell.layoutIfNeeded()
            XCTAssertEqual(callbacks.count, 2)
            controller.didTapContent(in: cell, url: action); XCTAssertEqual(callbacks.count, 3)
            cell.prepareForReuse()
            callbacks[1](.success(pattern(width: 20, height: 20)))
            callbacks[2](.success(pattern(width: 20, height: 20)))
            controller.didTapContent(in: cell, url: action); XCTAssertEqual(callbacks.count, 3)
            controller.didTapContent(in: cell, url: preview); XCTAssertEqual(controller.previews.count, 1)
        }
        try drainMain()
        main { XCTAssertNotEqual(value.imageState, .ready) }
    }

    func testRealHTTPFailureRetryUsesOriginalOwnerAndShowsClearTextAction() throws {
        let server = try ImageHTTP(bytes: main { pattern(width: 40, height: 120).pngData()! })
        defer { server.stop() }
        let owner = try ImageOwner(origin: server.origin)
        defer { owner.retire() }
        let controller = try main { try mount(width: 320, context: owner.context(), category: .accessibilityExtraExtraExtraLarge, dark: true) }
        defer { main { unmount(controller) } }
        let value = try main { try asyncAttachment(owner: owner, loader: .shared) }
        let context = try XCTUnwrap(controller.context)
        main {
            imageStageSnapshot = {
                self.imageFields(value, context: context).merging([
                    "http_requests": server.requestCount,
                    "page_current": controller.voiceScopeIsCurrent()
                ]) { _, right in right }
            }
        }
        let cell = try main { () -> MessageCell in
            let item = try message(width: 0, height: 0, bits: Data([1]), ref: value.url)
            item.cachedContent = NSAttributedString(attachment: value)
            let cell = try show(item, on: controller)
            value.startDownload(onError: value.imageCanvas!.rendered(nil))
            return cell
        }
        try until("real HTTP 403") { value.imageState == .failed }
        let before = main { value.bounds }
        try main {
            cell.setNeedsLayout(); cell.layoutIfNeeded()
            let overlay = try XCTUnwrap(descendants(cell).compactMap { $0 as? ClawImageStateView }.first)
            overlay.layoutIfNeeded()
            XCTAssertFalse(overlay.retryButton.isHidden)
            XCTAssertGreaterThanOrEqual(overlay.retryButton.bounds.height, 48)
            XCTAssertEqual(overlay.retryButton.backgroundColor, .clear)
            XCTAssertEqual(overlay.retryButton.accessibilityLabel, "重新加载")
            let rect = overlay.retryButton.convert(overlay.retryButton.bounds, to: overlay)
            XCTAssertTrue(overlay.bounds.insetBy(dx: -1, dy: -1).contains(rect))
            let hit = cell.contentView.hitTest(overlay.retryButton.convert(CGPoint(x: overlay.retryButton.bounds.midX, y: overlay.retryButton.bounds.midY), to: cell.contentView), with: nil)
            XCTAssertTrue(hit === overlay.retryButton || hit?.isDescendant(of: overlay.retryButton) == true)
            try capture("unknown-failed-ax-dark", controller: controller, attachment: value, overlay: overlay)
            overlay.retryButton.sendActions(for: .touchUpInside)
        }
        try until("real HTTP retry image") { value.imageState == .ready }
        try main {
            XCTAssertEqual(value.bounds, before)
            XCTAssertEqual(server.requestCount, 2); XCTAssertTrue(server.allRequestsAuthenticated)
            let overlay = try XCTUnwrap(descendants(cell).compactMap { $0 as? ClawImageStateView }.first)
            try capture("unknown-ready-fit-ax-dark", controller: controller, attachment: value, overlay: overlay)
        }
    }

    private func until(_ stage: String, _ condition: @escaping () -> Bool) throws {
        let started = ProcessInfo.processInfo.systemUptime
        var evaluations = 0
        var lastPredicate: Bool?
        var mainQueueTailSeen = false
        DispatchQueue.main.async { mainQueueTailSeen = true }
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.main {
            evaluations += 1
            let result = condition()
            lastPredicate = result
            return result
        } }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 3)
        try main {
            var fields = imageStageSnapshot?() ?? [:]
            fields["stage"] = stage
            fields["elapsed"] = ProcessInfo.processInfo.systemUptime - started
            fields["predicate_evaluations"] = evaluations
            if let lastPredicate = lastPredicate { fields["predicate_last"] = lastPredicate }
            else { fields["predicate_last"] = NSNull() }
            fields["post_wait_start_main_queue_tail_seen"] = mainQueueTailSeen
            fields["wait_result"] = String(describing: result)
            fields["snapshot_main_thread"] = Thread.isMainThread
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
                                           uniformTypeIdentifier: "public.json")
            attachment.name = "image-v1-stage-" + stage.replacingOccurrences(of: " ", with: "-")
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        guard result == .completed else {
            XCTFail("Bounded image stage: " + stage); throw Failure.deadline
        }
    }
    private func imageFields(_ value: AsyncImageTextAttachment, context: ClawOwnedImageContext) -> [String: Any] {
        precondition(Thread.isMainThread)
        // Each owner gate finishes before any subsequent UIKit/consumer read.
        let ownerCurrent = context.isCurrent
        let sourceMatches: Bool
        if let reference = value.imageSourceEntity?.data?["ref"]?.asString() {
            sourceMatches = context.resourceURL(from: reference) == value.url
        } else { sourceMatches = false }
        return ["state": String(describing: value.imageState), "owner_current": ownerCurrent,
                "source_matches": sourceMatches, "consumer_current": value.imageConsumerIsCurrent,
                "can_retry": value.canRetryImage]
    }
    private func drainMain() throws {
        let done = expectation(description: "owned completion FIFO")
        DispatchQueue.main.async { DispatchQueue.main.async { done.fulfill() } }
        XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 3), .completed)
    }
    private func draft(width: Int, height: Int, bits: Data?, ref: URL? = nil) throws -> Drafty {
        try Drafty(plainText: " ").insertImage(at: 0, mime: "image/png", bits: bits, width: width, height: height, fname: nil, refurl: ref, size: bits?.count ?? 0)
    }
    private func message(width: Int, height: Int, bits: Data?, outgoing: Bool = false, ref: URL? = nil) throws -> StoredMessage {
        let item = StoredMessage(); item.msgId = 1; item.seq = 1; item.topic = "grpImageFixture"
        item.from = outgoing ? "fixture-local" : "fixture-peer"; item.dbStatus = .synced
        item.ts = Date(timeIntervalSince1970: 1_700_000_000)
        item.content = try draft(width: width, height: height, bits: bits, ref: ref)
        return item
    }
    private func attachment(_ text: NSAttributedString) throws -> EntityTextAttachment {
        var result: EntityTextAttachment?
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if let image = value as? EntityTextAttachment { result = image; stop.pointee = true }
        }
        return try XCTUnwrap(result)
    }
    private func asyncAttachment(owner: ImageOwner, loader: ClawOwnedImageLoader) throws -> AsyncImageTextAttachment {
        let url = owner.origin.appendingPathComponent(UUID().uuidString + ".png")
        let canvas = try XCTUnwrap(ClawImageCanvas(width: nil, height: nil, decoded: nil, maximum: CGSize(width: 200, height: 400)))
        let value = AsyncImageTextAttachment(url: url, afterDownloaded: { canvas.rendered($0) }, context: try owner.context(), loader: loader)
        value.type = "image"; value.draftyEntityKey = 0; value.imageCanvas = canvas
        value.imageSourceEntity = try draft(width: 0, height: 0, bits: Data([1]), ref: url).entities?.first
        value.bounds = CGRect(origin: .zero, size: canvas.size); value.image = canvas.rendered(nil)
        return value
    }
    private func mount(width: CGFloat, context: ClawOwnedImageContext?, category: UIContentSizeCategory = .large, dark: Bool = false) throws -> ImageController {
        let parent = try XCTUnwrap(root)
        let controller = ImageController(context: context); controller.interactor = nil
        controller.topicName = "grpImageFixture"; controller.myUID = "fixture-local"
        parent.addChild(controller)
        parent.setOverrideTraitCollection(UITraitCollection(traitsFrom: [UITraitCollection(preferredContentSizeCategory: category), UITraitCollection(userInterfaceStyle: dark ? .dark : .light)]), forChild: controller)
        controller.loadViewIfNeeded(); controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 640)
        parent.view.addSubview(controller.view); controller.didMove(toParent: parent)
        controller.voicePageActive = true; controller.view.layoutIfNeeded()
        return controller
    }
    private func unmount(_ controller: ImageController) {
        controller.voicePageActive = false; controller.collectionView.dataSource = nil
        controller.willMove(toParent: nil); controller.view.removeFromSuperview(); controller.removeFromParent()
    }
    private func show(_ message: StoredMessage, on controller: ImageController) throws -> MessageCell {
        controller.messages = [message]; controller.messageSeqIdIndex = [message.seqId: 0]
        controller.collectionView.collectionViewLayout.invalidateLayout(); controller.collectionView.reloadData()
        controller.view.layoutIfNeeded(); controller.collectionView.layoutIfNeeded()
        let cell = try XCTUnwrap(controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? MessageCell)
        cell.setNeedsLayout(); cell.layoutIfNeeded(); cell.content.layoutIfNeeded()
        return cell
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { descendants($0) } }
    private func pattern(width: CGFloat, height: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        }
    }
    private func pixel(_ image: UIImage, x: CGFloat, y: CGFloat) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(cg.cropping(to: CGRect(x: CGFloat(cg.width) * x, y: CGFloat(cg.height) * y, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { ptr in
            let ctx = try XCTUnwrap(CGContext(data: ptr.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
    }
    private func capture(_ name: String, controller: ImageController, attachment: EntityTextAttachment, overlay: ClawImageStateView) throws {
        controller.view.layoutIfNeeded(); overlay.layoutIfNeeded()
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
            drawn = controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        guard drawn else { throw Failure.drawing }
        let png = XCTAttachment(image: image); png.name = "image-v1-" + name; png.lifetime = .keepAlways; add(png)
        let fields: [String: Any] = ["scope": "actual formatter/cell/layout with synthetic message, not authenticated chat",
            "width": attachment.bounds.width, "height": attachment.bounds.height,
            "overlayWidth": overlay.bounds.width, "overlayHeight": overlay.bounds.height,
            "retryVisible": !overlay.retryButton.isHidden, "retryWidth": overlay.retryButton.bounds.width,
            "retryHeight": overlay.retryButton.bounds.height, "font": overlay.retryButton.titleLabel?.font.pointSize ?? 0,
            "badgeVisible": !overlay.badge.isHidden,
            "sourceWidth": attachment.imageSourceEntity?.data?["width"]?.asInt() ?? -1,
            "sourceHeight": attachment.imageSourceEntity?.data?["height"]?.asInt() ?? -1]
        let item = XCTAttachment(data: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        item.name = "image-v1-" + name + "-geometry"; item.lifetime = .keepAlways; add(item)
    }
}

private final class ImageController: MessageViewController {
    let context: ClawOwnedImageContext?
    var previews = [ImagePreviewContent]()
    init(context: ClawOwnedImageContext?) { self.context = context; super.init() }
    required init?(coder: NSCoder) { fatalError("Programmatic fixture") }
    override func viewDidLoad() {
        (collectionView.collectionViewLayout as? MessageViewLayout)?.delegate = self
        collectionView.dataSource = self
    }
    override func viewDidAppear(_ animated: Bool) {}
    override var inputAccessoryView: UIView? { nil }
    override func performSegue(withIdentifier identifier: String, sender: Any?) {
        XCTAssertEqual(identifier, "ShowImagePreview")
        if let value = sender as? ImagePreviewContent { previews.append(value) }
        else { XCTFail("Missing original preview payload") }
    }
    // Only the existing current-slot boundary is controlled. The production
    // retry handler and entity/page/cell checks above it execute unchanged.
    override func voiceScopeIsCurrent() -> Bool { voicePageActive && context?.isCurrent == true }
}

private final class ImageOwner {
    let origin: URL
    let base: BaseDb
    let store: SqlStore
    let owner: Tinode
    private let lock = NSRecursiveLock()
    private var active = true
    init(origin: URL) throws {
        self.origin = origin
        base = BaseDb(databasePath: FileManager.default.temporaryDirectory.appendingPathComponent("image-v1-" + UUID().uuidString + ".sqlite").path)
        store = try XCTUnwrap(base.sqlStore); XCTAssertTrue(base.isStoreAvailable)
        store.myUid = "usrImageFixture"
        owner = Tinode(for: "image-fixture", authenticateWith: "synthetic-key", persistDataIn: store)
        owner.authToken = "synthetic-token"
    }
    func context() throws -> ClawOwnedImageContext {
        try XCTUnwrap(ClawOwnedImageContext(owner: owner, serviceURL: origin, generation: 1,
            currentGeneration: { 1 }, inCurrentSlot: { body in
                self.lock.lock(); defer { self.lock.unlock() }
                guard self.active else { return false }; body(); return true
            }))
    }
    func retire() { owner.logout(); lock.lock(); active = false; lock.unlock() }
}

private final class ImageHTTP {
    private let queue = DispatchQueue(label: "image-v1-loopback")
    private let lock = NSLock()
    private let listener: NWListener
    private var connections = [NWConnection]()
    private var auth = [Bool]()
    private var ready = false
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return auth.count }
    var allRequestsAuthenticated: Bool { lock.lock(); defer { lock.unlock() }; return !auth.isEmpty && auth.allSatisfy { $0 } }
    var origin: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/")! }
    init(bytes: Data) throws {
        let config = NWParameters.tcp; config.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: config)
        let gate = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.lock.lock(); self?.ready = true; self?.lock.unlock(); gate.signal()
            case .failed: gate.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { connection.cancel(); return }
            self.lock.lock(); self.connections.append(connection); self.lock.unlock()
            connection.start(queue: self.queue); self.receive(connection, prefix: Data(), bytes: bytes)
        }
        listener.start(queue: queue)
        guard gate.wait(timeout: .now() + 3) == .success else { listener.cancel(); throw NSError(domain: "fixture", code: 1) }
        lock.lock(); let valid = ready; lock.unlock()
        guard valid else { throw NSError(domain: "fixture", code: 2) }
    }
    private func receive(_ connection: NWConnection, prefix: Data, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { [weak self] data, _, ended, error in
            guard let self = self else { return }
            let total = prefix + (data ?? Data())
            guard total.count <= 32768 else { connection.cancel(); return }
            guard total.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if !ended && error == nil { self.receive(connection, prefix: total, bytes: bytes) }
                return
            }
            let text = String(decoding: total, as: UTF8.self).lowercased()
            self.lock.lock(); self.auth.append(text.contains("x-tinode-auth:")); let ordinal = self.auth.count; self.lock.unlock()
            let body = ordinal == 1 ? Data() : bytes
            let header = "HTTP/1.1 \(ordinal == 1 ? 403 : 200) Fixture\r\nContent-Type: image/png\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + body, contentContext: .finalMessage, isComplete: true,
                completion: .contentProcessed { error in if error != nil { connection.cancel() } })
        }
    }
    func stop() { listener.cancel(); lock.lock(); let pending = connections; connections = []; lock.unlock(); pending.forEach { $0.cancel() } }
}
