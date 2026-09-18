// Copyright (c) 2026 CLAW OS contributors.
// App-hosted real MessageVC display consumers + MessageView/UICollectionView.
// Neutral cells and synthetic StoredMessage only: no login, publish, read receipt,
// microphone, thumbnail generation, or complete authenticated chat journey.
import XCTest
import UIKit
import TinodeSDK
import TinodiosDB
@testable import Tinodios

final class ChatScrollTests: XCTestCase {
    private enum Failure: Error { case initialState, deadline }
    private var controller: NeutralChatController!
    private var cells: NeutralCells!
    private var window: UIWindow!
    private var previousWindow: UIWindow?
    private var layout: UICollectionViewFlowLayout!

    private func main<T>(_ work: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try work() }
        return try DispatchQueue.main.sync(execute: work)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try main {
            guard Bundle.main.bundleIdentifier == "app.veilping.clawoschat",
                  Bundle.main.object(forInfoDictionaryKey: "HOST_NAME") as? String == "127.0.0.1:9",
                  SharedUtils.getAuthToken() == nil, Cache.tinode.myUid == nil,
                  Cache.tinode.store?.myUid == nil, !Cache.tinode.isConnectionAuthenticated else {
                XCTFail("Unexpected authenticated or network host state"); throw Failure.initialState
            }
            previousWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
            controller = NeutralChatController()
            controller.interactor = nil // No business route is installed in this neutral fixture.
            controller.topic = try XCTUnwrap(Tinode.newTopic(withTinode: nil, forTopic: "grp-scroll-fixture") as? DefaultComTopic)
            controller.loadViewIfNeeded() // Actual production loadView, including the latest button.
            layout = UICollectionViewFlowLayout()
            layout.itemSize = CGSize(width: 240, height: 56)
            layout.minimumLineSpacing = 4
            controller.collectionView.setCollectionViewLayout(layout, animated: false)
            controller.collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "neutral")
            cells = NeutralCells(controller)
            controller.collectionView.dataSource = cells
            window = UIWindow(frame: UIScreen.main.bounds)
            if let scene = previousWindow?.windowScene { window.windowScene = scene }
            window.rootViewController = UINavigationController(rootViewController: controller)
            window.makeKeyAndVisible()
            window.layoutIfNeeded(); controller.view.layoutIfNeeded()
            XCTAssertNotNil(controller.collectionView.window)
        }
    }

    override func tearDownWithError() throws {
        try main {
            defer {
                window?.isHidden = true
                controller?.collectionView.dataSource = nil
                window?.rootViewController = nil
                controller = nil; cells = nil; window = nil
                previousWindow?.makeKey(); previousWindow = nil
            }
            if controller != nil { try evidence("final-viewport") }
        }
    }

    private func rows(_ range: ClosedRange<Int>) -> [StoredMessage] {
        range.map { index in
            let message = StoredMessage()
            message.msgId = Int64(index); message.seq = index
            message.content = Drafty(content: "合成消息 \(index)")
            message.ts = Date(timeIntervalSince1970: Double(index))
            return message
        }
    }

    private func present(_ messages: [StoredMessage], _ intent: ChatDisplayIntent = .passive) throws {
        controller.displayChatMessages(messages: messages, source: try XCTUnwrap(controller.chatDisplaySource), intent: intent)
        try settled()
    }

    private func settled() throws {
        let end = ProcessInfo.processInfo.systemUptime + 3
        while controller.chatPresentationRunning || !controller.chatPresentationQueue.isEmpty {
            guard ProcessInfo.processInfo.systemUptime < end else { XCTFail("UI batch deadline"); throw Failure.deadline }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        controller.collectionView.layoutIfNeeded()
    }

    private func readHistory() {
        controller.scrollViewWillBeginDragging(controller.collectionView)
        controller.collectionView.setContentOffset(CGPoint(x: 0, y: 430), animated: false)
        controller.collectionView.layoutIfNeeded()
    }

    private func assertAnchor(_ before: ChatViewportSnapshot, file: StaticString = #filePath, line: UInt = #line) throws {
        let anchor = try XCTUnwrap(before.anchors.first, file: file, line: line)
        let now = controller.captureChatViewport()
        XCTAssertEqual(now.anchors.first?.dbID, anchor.dbID, file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(now.anchors.first?.offset), anchor.offset, accuracy: 1, file: file, line: line)
    }

    func testLargePassiveBatchPreservesHistoryAndBottomFollows() throws {
        try main {
            try present(rows(1...40)); readHistory()
            let anchor = controller.captureChatViewport()
            try present(rows(1...50)) // >5: actual full-reload branch.
            try assertAnchor(anchor)
            controller.goToLastMessage()
            try present(rows(1...60))
            XCTAssertEqual(controller.collectionView.contentOffset.y, controller.chatMaximumOffset, accuracy: 1)
            controller.lastMessageReceived = .distantPast
            try present(rows(1...61)) // Actual animated insert + neighbor-refresh path at the bottom.
            XCTAssertEqual(controller.collectionView.contentOffset.y, controller.chatMaximumOffset, accuracy: 1)
        }
    }

    func testPrependHeightChangeAndDeletedAnchorUseRealAttributes() throws {
        try main {
            try present(rows(20...60)); readHistory()
            let before = controller.captureChatViewport()
            controller.lastMessageReceived = .distantPast
            try present(rows(1...60), .preserve)
            try assertAnchor(before)
            let heightAnchor = controller.captureChatViewport()
            controller.reloadChatLayoutPreservingViewport { self.layout.itemSize.height = 82 }
            try settled(); try assertAnchor(heightAnchor)
            let candidates = controller.captureChatViewport()
            let removed = try XCTUnwrap(candidates.anchors.first).dbID
            let survivor = try XCTUnwrap(candidates.anchors.dropFirst().first)
            controller.lastMessageReceived = .distantPast
            try present(rows(1...60).filter { $0.msgId != removed }, .preserve)
            let actual = try XCTUnwrap(controller.captureChatViewport().anchors.first(where: { $0.dbID == survivor.dbID }))
            XCTAssertEqual(actual.offset, survivor.offset, accuracy: 1)
        }
    }

    func testOverlappingRealTwoPhaseBatchesDoNotReplaceActiveArray() throws {
        try main {
            try present(rows(1...40)); readHistory()
            let before = controller.captureChatViewport()
            let source = try XCTUnwrap(controller.chatDisplaySource)
            controller.lastMessageReceived = .distantPast
            controller.displayChatMessages(messages: rows(1...41), source: source, intent: .passive)
            XCTAssertTrue(controller.chatPresentationRunning, "Must overlap an actual unfinished UICollectionView batch")
            controller.displayChatMessages(messages: rows(1...42), source: source, intent: .passive)
            XCTAssertEqual(controller.messages.count, 41, "Queued snapshot must not replace active batch data")
            XCTAssertEqual(controller.chatPresentationQueue.count, 1)
            try settled()
            XCTAssertEqual(controller.messages.count, 42)
            XCTAssertEqual(controller.collectionView.numberOfItems(inSection: 0), 42)
            try assertAnchor(before)
        }
    }

    func testUserMovementBetweenBatchPhasesInvalidatesSubmission() throws {
        try main {
            try present(rows(1...40)); readHistory()
            let ticket = controller.captureChatSubmissionIntent()
            controller.lastMessageReceived = .distantPast
            controller.displayChatMessages(messages: rows(1...41), source: try XCTUnwrap(controller.chatDisplaySource), intent: ticket)
            XCTAssertTrue(controller.chatPresentationRunning)
            controller.scrollViewWillBeginDragging(controller.collectionView)
            controller.collectionView.setContentOffset(CGPoint(x: 0, y: 190), animated: false)
            try settled()
            XCTAssertEqual(controller.collectionView.contentOffset.y, 190, accuracy: 1)
            XCTAssertNil(controller.chatConsumedSubmission)
        }
    }

    func testNewSubmissionConsumedOnceThenAckAndUnknownScrollPreserve() throws {
        try main {
            try present(rows(1...40)); readHistory()
            let consumer = CaptureOnlyInteractor()
            controller.interactor = consumer
            let cases: [PendingMessage?] = [nil,
                .replyTo(message: Drafty(content: "合成回复"), seqId: 2),
                .forwarded(message: Drafty(content: "合成转发"), from: "fixture", preview: Drafty(content: "合成预览"))]
            for pending in cases {
                consumer.pendingMessage = pending
                controller.sendMessageBar(sendText: "合成提交")
                guard case .submission(let value)? = consumer.captured else { return XCTFail("Actual text consumer omitted capture") }
                XCTAssertFalse(value.editing)
                XCTAssertEqual(value.submission, controller.chatSubmissionRevision)
            }
            let ticket = controller.captureChatSubmissionIntent()
            try present(rows(1...41), ticket)
            XCTAssertEqual(controller.collectionView.contentOffset.y, controller.chatMaximumOffset, accuracy: 1)
            readHistory(); let anchor = controller.captureChatViewport()
            try present(rows(1...41), .passive) // ACK/ready status refresh is not a new action.
            try present(rows(1...42), ticket) // Delayed duplicate ticket.
            try assertAnchor(anchor)
            let late = controller.captureChatSubmissionIntent()
            // No pan callback: the real scroll delegate must also reject unknown movement.
            controller.collectionView.setContentOffset(CGPoint(x: 0, y: 310), animated: false)
            let current = controller.captureChatViewport()
            try present(rows(1...43), late)
            try assertAnchor(current)
        }
    }

    func testEditCaptureAndPinnedLocalReloadKeepHistory() throws {
        try main {
            try present(rows(1...40)); readHistory()
            let interactor = MessageInteractor()
            interactor.pendingMessage = .edit(message: Drafty(content: "合成编辑"), markdown: "合成编辑", seqId: 8)
            controller.interactor = interactor
            let captured = controller.captureChatSubmissionIntent()
            XCTAssertTrue(captured.preservesReadingPosition)
            interactor.dismissPendingMessage() // Delayed UI must not infer intent from the new pending state.
            let anchor = controller.captureChatViewport()
            try present(rows(1...40), captured)
            let source = try XCTUnwrap(controller.chatDisplaySource)
            controller.displayPinnedMessages(pins: [8], selected: 0, source: source)
            controller.reloadPinned(forSeq: 8, source: source)
            controller.reloadMessages(fromSeqId: 8, toSeqId: 8, source: source)
            controller.deviceRotated()
            try settled(); try assertAnchor(anchor)
            XCTAssertNil(controller.chatConsumedSubmission)
        }
    }

    func testQuoteNoOpAndOriginalPageSourceRejectLatePresentation() throws {
        try main {
            try present(rows(1...40)); readHistory()
            let ticket = controller.captureChatSubmissionIntent()
            let revision = controller.chatInteractionRevision
            controller.scrollToAndAnimate(seqId: Int.max) // Actual common quote/pin entry, no movement.
            XCTAssertGreaterThan(controller.chatInteractionRevision, revision)
            let before = controller.captureChatViewport()
            try present(rows(1...41), ticket); try assertAnchor(before)
            let oldSource = try XCTUnwrap(controller.chatDisplaySource)
            let presenter = MessagePresenter(pageID: controller.chatPageID)
            presenter.viewController = controller
            presenter.presentMessages(messages: rows(100...140), source: oldSource, intent: .passive)
            controller.topic = try XCTUnwrap(Tinode.newTopic(withTinode: nil, forTopic: "grp-scroll-fixture") as? DefaultComTopic)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            XCTAssertEqual(controller.messages.first?.msgId, 1)
            controller.displayChatMessages(messages: rows(200...240), source: ChatDisplaySource(page: UUID(), topic: controller.topic!), intent: .passive)
            XCTAssertEqual(controller.messages.first?.msgId, 1)
        }
    }

    func testPreviewButtonCapturesBeforeHandoffAndLateWorkCannotMintTicket() throws {
        try main {
            try present(rows(1...40)); readHistory()
            let preview = NeutralFilePreview()
            let navigation = try XCTUnwrap(controller.navigationController)
            navigation.pushViewController(preview, animated: false)
            // Real original page is offscreen; capture is still allowed for its own top preview.
            let capture = controller.chatPreviewIntentCapture(for: preview)
            preview.captureDisplayIntent = capture
            preview.previewContent = FilePreviewContent(data: Data([1, 2, 3]), refUrl: nil,
                fileName: "fixture.txt", contentType: "text/plain", size: 3, pendingMessagePreview: nil)
            let sendButton = UIButton(type: .system)
            preview.view.addSubview(sendButton); preview.sendButton = sendButton
            var received: ChatDisplayIntent?
            let token = NotificationCenter.default.addObserver(forName: Notification.Name(MessageViewController.kNotificationSendAttachment),
                object: nil, queue: .main) { note in
                    received = note.userInfo?[ChatDisplayIntent.notificationKey] as? ChatDisplayIntent
                }
            defer { NotificationCenter.default.removeObserver(token) }
            preview.sendFileAttachment(sendButton) // Actual button method captures before notification and pop.
            let intent = try XCTUnwrap(received)
            guard case .submission(let ticket) = intent else { return XCTFail("Legitimate offscreen preview lost its ticket") }
            let serial = controller.chatSubmissionRevision
            controller.invalidateChatDisplayIntent() // User interaction while thumbnail/data work is pending.
            let end = ProcessInfo.processInfo.systemUptime + 3
            while navigation.transitionCoordinator != nil || controller.view.window == nil {
                guard ProcessInfo.processInfo.systemUptime < end else { throw Failure.deadline }
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            }
            readHistory(); let before = controller.captureChatViewport()
            try present(rows(1...41), intent)
            XCTAssertEqual(controller.chatSubmissionRevision, serial)
            XCTAssertNotEqual(ticket.interaction, controller.chatInteractionRevision)
            try assertAnchor(before)
            XCTAssertTrue(capture().preservesReadingPosition, "Popped preview cannot capture another active ticket")
        }
    }

    func testFirstNonemptyOnlyOnceAndZeroSequenceDraftsKeepIdentity() throws {
        try main {
            try present([]); try present(rows(1...40))
            XCTAssertTrue(controller.chatPresentedNonempty)
            XCTAssertEqual(controller.collectionView.contentOffset.y, controller.chatMaximumOffset, accuracy: 1)
            readHistory(); try present([], .preserve)
            try present(rows(1...40))
            XCTAssertLessThan(controller.collectionView.contentOffset.y, controller.chatMaximumOffset - 40)
            let drafts = rows(1...40)
            drafts.forEach { $0.seq = 0 }
            try present(drafts, .preserve); readHistory()
            let anchor = controller.captureChatViewport()
            controller.reloadChatLayoutPreservingViewport { self.layout.itemSize.height = 70 }
            try settled(); try assertAnchor(anchor)
        }
    }

    func testLatestButtonIsRealVisibleAdaptiveAndInvalidatesOldRestore() throws {
        try main {
            try present(rows(1...40)); readHistory()
            let button = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UIButton }
                .first(where: { $0.currentTitle == "回到最新消息" }))
            XCTAssertFalse(button.isHidden)
            XCTAssertEqual(button.accessibilityLabel, "回到最新消息")
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
            XCTAssertGreaterThan(button.bounds.width, 44)
            let ticket = controller.captureChatSubmissionIntent()
            button.sendActions(for: .touchUpInside)
            XCTAssertTrue(button.isHidden)
            XCTAssertEqual(controller.collectionView.contentOffset.y, controller.chatMaximumOffset, accuracy: 1)
            readHistory(); let anchor = controller.captureChatViewport()
            try present(rows(1...41), ticket); try assertAnchor(anchor)
            let container = try XCTUnwrap(controller.parent)
            container.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: controller)
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            XCTAssertEqual(controller.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
            let frame = button.convert(button.bounds, to: controller.view)
            XCTAssertGreaterThanOrEqual(frame.height, 44)
            XCTAssertGreaterThanOrEqual(frame.minX, controller.view.safeAreaInsets.left)
            XCTAssertLessThanOrEqual(frame.maxX, controller.view.bounds.width - controller.view.safeAreaInsets.right)
            // Geometry is additionally captured; a complete keyboard/chat journey is not claimed.
            try evidence("latest-button-history")
        }
    }

    private func evidence(_ name: String) throws {
        let view = controller.view!
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true) }
        let png = XCTAttachment(image: image); png.name = "chat-scroll-\(name)"; png.lifetime = .keepAlways; add(png)
        let viewport = controller.captureChatViewport()
        let data: [String: Any] = ["scope": "neutral cells, production MessageVC consumer and real UICollectionView",
            "count": controller.messages.count, "offsetY": viewport.offset.y,
            "anchorIDs": viewport.anchors.map { $0.dbID }, "anchorOffsets": viewport.anchors.map { $0.offset },
            "atBottom": viewport.atBottom, "interaction": controller.chatInteractionRevision,
            "queueCount": controller.chatPresentationQueue.count, "rendering": controller.chatPresentationRunning]
        let json = XCTAttachment(data: try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]), uniformTypeIdentifier: "public.json")
        json.name = "chat-scroll-\(name)-geometry"; json.lifetime = .keepAlways; add(json)
    }
}

private final class NeutralChatController: MessageViewController {
    // Suppress business lifecycle only; inherited loadView and display consumers are actual production methods.
    override func viewDidLoad() {}
    override func viewDidAppear(_ animated: Bool) {}
    override var inputAccessoryView: UIView? { nil }
}

private final class NeutralFilePreview: FilePreviewController {
    override func viewDidLoad() {} // Only the actual confirm handler is exercised, not storyboard layout.
}

private final class CaptureOnlyInteractor: MessageInteractor {
    var captured: ChatDisplayIntent?
    override func sendMessage(content: Drafty, displayIntent: ChatDisplayIntent) {
        captured = displayIntent // Consumer port only; no publish or synthetic ACK.
    }
}

private final class NeutralCells: NSObject, UICollectionViewDataSource {
    unowned let controller: MessageViewController
    init(_ controller: MessageViewController) { self.controller = controller }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { controller.messages.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "neutral", for: indexPath)
        cell.backgroundColor = indexPath.item.isMultiple(of: 2) ? .systemGray4 : .systemGray5
        return cell
    }
}
