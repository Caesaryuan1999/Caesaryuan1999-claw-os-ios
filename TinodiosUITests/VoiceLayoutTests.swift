// Copyright (c) 2026 CLAW OS contributors.
// Original App class + original bundled XIB. Component presentation only:
// no chat route, credentials, microphone, recording, upload, or synthetic login.
import XCTest
import AVFoundation
import UIKit
import UIKit.UIGestureRecognizerSubclass
import TinodiosDB
import TinodeSDK
@testable import Tinodios

final class VoiceLayoutTests: XCTestCase {
    private enum Failure: Error { case preconditionFailed, deadline, renderingFailed }
    private var fixture: AccessoryFixture?
    private var previousWindow: UIWindow?
    private var keyboardTokens: [NSObjectProtocol] = []
    private var keyboardFrame = CGRect.zero
    private var keyboardShows = 0
    private var keyboardHides = 0
    private var keyboardSequence = 0
    private var keyboardSamples = [[String: Any]]()
    private var lastHitEvidence = [String: Any]()
    private var inputBeginEvents = 0

    private func main<T>(_ body: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try body() }
        return try DispatchQueue.main.sync(execute: body)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try main {
            // Reject an unexpected host/account; do not erase data to make a fixture pass.
            guard Bundle.main.bundleIdentifier == "app.veilping.clawoschat",
                  Bundle.main.object(forInfoDictionaryKey: "HOST_NAME") as? String == "127.0.0.1:9",
                  Bundle.main.object(forInfoDictionaryKey: "USE_TLS") as? String == "NO",
                  SharedUtils.getAuthToken() == nil,
                  Cache.tinode.myUid == nil, Cache.tinode.store?.myUid == nil,
                  !Cache.tinode.isConnectionAuthenticated else {
                XCTFail("Unexpected host or authenticated initial state")
                throw Failure.preconditionFailed
            }
            try awaitMain("foreground App", seconds: 3) { UIApplication.shared.applicationState == .active }
            previousWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
            keyboardFrame = .zero; keyboardShows = 0; keyboardHides = 0
            keyboardSequence = 0; keyboardSamples = []; lastHitEvidence = [:]
            inputBeginEvents = 0
            for name in [UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidHideNotification,
                         UIResponder.keyboardDidChangeFrameNotification] {
                keyboardTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] note in
                    guard let self = self else { return }
                    precondition(Thread.isMainThread)
                    self.keyboardSequence += 1
                    self.keyboardFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .null
                    let category: String
                    if note.name == UIResponder.keyboardDidShowNotification {
                        self.keyboardShows += 1; category = "didShow"
                    } else if note.name == UIResponder.keyboardDidHideNotification {
                        self.keyboardHides += 1; category = "didHide"
                    } else {
                        category = "didChangeFrame"
                    }
                    if self.keyboardSamples.count < 64 {
                        let frame = self.keyboardFrame
                        self.keyboardSamples.append(["sequence": self.keyboardSequence, "event": category,
                            "hasFrame": !frame.isNull,
                            "visibleHeight": frame.isNull ? -1 : frame.intersection(UIScreen.main.bounds).height,
                            "inputFirstResponder": self.fixture?.bar.inputField.isFirstResponder == true])
                    }
                })
            }
            let value = AccessoryFixture()
            fixture = value
            keyboardTokens.append(NotificationCenter.default.addObserver(
                forName: UITextView.textDidBeginEditingNotification, object: value.bar.inputField, queue: .main) {
                [weak self] _ in
                precondition(Thread.isMainThread)
                self?.inputBeginEvents += 1
            })
            value.window.makeKeyAndVisible()
            XCTAssertTrue(value.controller.becomeFirstResponder())
            try awaitMain("original accessory visible", seconds: 3) {
                value.bar.window != nil && value.bar.bounds.width > 0 && value.bar.bounds.height > 0
            }
            value.settle()
        }
    }

    override func tearDownWithError() throws {
        try main {
            defer {
                fixture?.bar.inputField.resignFirstResponder()
                fixture?.controller.resignFirstResponder()
                fixture?.bar.resetRecordingState()
                fixture?.bar.delegate = nil
                fixture?.window.isHidden = true
                fixture = nil
                previousWindow?.makeKey(); previousWindow = nil
                keyboardTokens.forEach { NotificationCenter.default.removeObserver($0) }
                keyboardTokens.removeAll()
            }
            // Preserve the actual current component even when an earlier assertion failed.
            if let value = fixture { try capture("teardown-current-before-reset", value, waitForStability: false) }
        }
    }

    // Pumps UIKit on the main thread; a finite unmet condition fails instead of silently skipping.
    private func awaitMain(_ category: String, seconds: TimeInterval, _ condition: () -> Bool) throws {
        precondition(Thread.isMainThread)
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !condition() && ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        guard condition() else { XCTFail("Component condition failed: " + category); throw Failure.deadline }
    }

    private func current() throws -> AccessoryFixture { try XCTUnwrap(fixture) }

    // Sample real UIKit state on main until it remains stable; never suppress animations.
    private func awaitStable(_ category: String, until deadline: TimeInterval? = nil, _ geometry: () -> [CGFloat]?) throws {
        var previous: [CGFloat]?
        var stableSince = ProcessInfo.processInfo.systemUptime
        let remaining = max(0, (deadline ?? (stableSince + 3)) - stableSince)
        try awaitMain(category, seconds: remaining) {
            guard let values = geometry() else { previous = nil; return false }
            let now = ProcessInfo.processInfo.systemUptime
            if let old = previous, old.count == values.count,
               zip(old, values).allSatisfy({ abs($0.0 - $0.1) <= 0.5 }) {
                return now - stableSince >= 0.1
            }
            previous = values; stableSince = now
            return false
        }
    }

    private func presentationViews(_ f: AccessoryFixture) -> [UIView] {
        // Finite layout/fade transitions only: do not wait for text-view caret or waveform animation.
        let bar = f.bar
        let buttons = [bar.sendButton!, bar.stopAudioRecordingButton!, bar.voiceSendButton!,
                       bar.playAudioButton!, bar.pauseAudioButton!, bar.deleteAudioButton!]
        var views: [UIView] = [bar, bar.audioView, bar.voiceStackView, bar.voiceScrollView]
        for button in buttons { views.append(button) }
        var ancestor = f.bar.superview
        while let value = ancestor { views.append(value); ancestor = value.superview }
        return views
    }

    private func awaitPresentation(_ f: AccessoryFixture, until deadline: TimeInterval? = nil) throws {
        try awaitStable("component animations and geometry settled", until: deadline) {
            f.bar.layoutIfNeeded(); f.bar.window?.layoutIfNeeded()
            let views = self.presentationViews(f)
            guard views.allSatisfy({ $0.layer.animationKeys()?.isEmpty ?? true }) else { return nil }
            return views.filter { !$0.isHidden }.flatMap {
                let frame = $0.convert($0.bounds, to: nil)
                return [frame.minX, frame.minY, frame.width, frame.height, $0.alpha]
            }
        }
    }

    private func viewAndAncestors(_ view: UIView) -> [UIView] {
        precondition(Thread.isMainThread)
        var result: [UIView] = [], current: UIView? = view
        while let value = current { result.append(value); current = value.superview }
        return result
    }

    private func sendImageVisibility(_ button: UIButton) -> (notVisible: Bool, evidence: [String: Any]) {
        precondition(Thread.isMainThread)
        guard let imageView = button.imageView else {
            return (true, ["reason": "no_image_view", "nodes": []])
        }
        let chain = viewAndAncestors(imageView)
        let reason: String
        if imageView.image == nil { reason = "no_image" }
        else if imageView.window == nil { reason = "detached_from_window" }
        else if chain.contains(where: { $0.isHidden }) { reason = "hidden_in_hierarchy" }
        else if chain.contains(where: { $0.alpha == 0 }) { reason = "zero_alpha_in_hierarchy" }
        else { reason = "no_absence_evidence" }
        let nodes: [[String: Any]] = chain.map { view in
            let frame = view.window.map { view.convert(view.bounds, to: $0) }
            let windowFrame: [CGFloat] = frame.map { [$0.minX, $0.minY, $0.width, $0.height] } ?? []
            return ["class": NSStringFromClass(type(of: view)), "hidden": view.isHidden,
                    "alpha": view.alpha, "windowPresent": view.window != nil,
                    "bounds": [view.bounds.minX, view.bounds.minY, view.bounds.width, view.bounds.height],
                    "windowFrame": windowFrame, "clipsToBounds": view.clipsToBounds,
                    "animationKeys": view.layer.animationKeys() ?? []]
        }
        let settled = chain.allSatisfy { $0.layer.animationKeys()?.isEmpty ?? true }
        // A zero size or clipping rectangle alone is not proof that the retained image cannot draw.
        return (reason != "no_absence_evidence" && settled,
                ["reason": reason, "settled": settled, "hasImage": imageView.image != nil, "nodes": nodes])
    }

    func testOriginalNibLoadsAndResetsWithoutRecording() throws {
        try main {
            let f = try current(), bar = f.bar
            XCTAssertEqual(Bundle(for: SendMessageBar.self).bundleURL, Bundle.main.bundleURL)
            XCTAssertNotNil(Bundle.main.url(forResource: "SendMessageBar", withExtension: "nib"))
            XCTAssertTrue(bar.inputField is PlaceholderTextView)
            XCTAssertTrue(bar.previewView is RichTextView)
            XCTAssertTrue(bar.wavePreviewImageView is WaveImageView)
            // UITextView has system selection gestures; only the original send button owns this action.
            let gestures = (bar.sendButton.gestureRecognizers ?? []).compactMap { $0 as? UILongPressGestureRecognizer }
            XCTAssertEqual(gestures.count, 1)
            XCTAssertEqual(try XCTUnwrap(gestures.first).minimumPressDuration, 0.5)
            XCTAssertTrue(try XCTUnwrap(gestures.first).view === bar.sendButton)
            let original = CGPoint(x: bar.sendButtonHorizontal.constant, y: bar.sendButtonVertical.constant)
            bar.resetRecordingState(); bar.resetRecordingState(); f.settle()
            XCTAssertEqual(bar.sendButtonHorizontal.constant, original.x)
            XCTAssertEqual(bar.sendButtonVertical.constant, original.y)
            XCTAssertTrue(bar.audioView.isHidden)
            XCTAssertFalse(bar.inputField.isHidden)
            XCTAssertTrue(f.spy.actions.isEmpty)
            try capture("initial-and-repeat-reset", f)
            // Exercise the actual XIB button across both existing appearance paths.
            let originalImage = try XCTUnwrap(bar.sendButton.currentImage)
            if #available(iOS 15.0, *) { XCTAssertNil(bar.sendButton.configuration) }
            XCTAssertNil(bar.sendButton.currentTitle)
            let beforeBegin = inputBeginEvents
            XCTAssertFalse(bar.inputField.isFirstResponder)
            XCTAssertTrue(bar.inputField.becomeFirstResponder())
            try awaitMain("this input began editing", seconds: 3) {
                self.inputBeginEvents > beforeBegin && bar.inputField.isFirstResponder
            }
            let syntheticInput = "组件布局测试" // never submitted
            bar.inputField.text = syntheticInput
            XCTAssertEqual(bar.inputField.actualText, syntheticInput)
            bar.textViewDidChange(bar.inputField); f.settle(); try awaitPresentation(f)
            XCTAssertNil(bar.sendButton.currentImage)
            let buttonWindow = try XCTUnwrap(bar.sendButton.window)
            XCTAssertTrue(viewAndAncestors(bar.sendButton).allSatisfy { !$0.isHidden && $0.alpha > 0 })
            let buttonFrame = bar.sendButton.convert(bar.sendButton.bounds, to: buttonWindow)
            let visibleFrame = buttonFrame.intersection(buttonWindow.bounds)
            XCTAssertGreaterThanOrEqual(visibleFrame.width, buttonFrame.width - 0.5)
            XCTAssertGreaterThanOrEqual(visibleFrame.height, buttonFrame.height - 0.5)
            XCTAssertTrue(sendImageVisibility(bar.sendButton).notVisible, "Image absence requires actual visibility evidence")
            if #available(iOS 15.0, *) { XCTAssertNil(bar.sendButton.configuration) }
            XCTAssertEqual(bar.sendButton.currentTitle, "发送")
            let label = try XCTUnwrap(bar.sendButton.titleLabel)
            XCTAssertEqual(label.numberOfLines, 1)
            let size = ("发送" as NSString).size(withAttributes: [.font: try XCTUnwrap(label.font)])
            XCTAssertGreaterThanOrEqual(label.bounds.width + 1, ceil(size.width))
            XCTAssertLessThanOrEqual(label.bounds.height, ceil(label.font.lineHeight) + 1)
            XCTAssertGreaterThanOrEqual(bar.sendButton.bounds.width, max(64, ceil(size.width) + 20))
            XCTAssertGreaterThanOrEqual(bar.sendButton.bounds.height, 48)
            try capture("send-button-text-single-line", f)
            bar.inputField.text = ""; bar.textViewDidChange(bar.inputField); f.settle(); try awaitPresentation(f)
            XCTAssertTrue(bar.inputField.actualText.isEmpty)
            XCTAssertNil(bar.sendButton.currentTitle)
            XCTAssertTrue(try XCTUnwrap(bar.sendButton.currentImage).isEqual(originalImage))
            if #available(iOS 15.0, *) { XCTAssertNil(bar.sendButton.configuration) }
            XCTAssertEqual(bar.sendButton.bounds.width, 48, accuracy: 0.5)
            XCTAssertEqual(bar.sendButton.bounds.height, 48, accuracy: 0.5)
            XCTAssertEqual(bar.sendButton.accessibilityLabel, "录音")
            XCTAssertTrue(f.spy.actions.isEmpty); XCTAssertTrue(f.spy.sentTexts.isEmpty)
            try capture("send-button-empty-recording-restored", f)
        }
    }

    func testContinuousAudioWidthsReachRealFormatterAndMessageCells() throws {
        try main {
            try withAudioRenderer(width: 390) { controller in
                let samples: [(Int, CGFloat)] = [(1000, 128), (1500, 128.813559), (4000, 132.881356),
                    (10000, 142.644068), (20000, 158.915254), (30000, 175.186441),
                    (45000, 199.593220), (59000, 222.372881), (60000, 224)]
                var measured: [[String: Any]] = []
                for outgoing in [false, true] {
                    for (duration, expected) in samples {
                        let message = try audioMessage(duration: duration, outgoing: outgoing)
                        let cell = try showAudio(message, on: controller)
                        let play = try audioAttachment(in: cell)
                        XCTAssertEqual(play.0.audioDurationMilliseconds, duration)
                        XCTAssertEqual(play.0.bounds.width, 24)
                        XCTAssertEqual(cell.containerView.frame.width, expected, accuracy: 0.51)
                        XCTAssertEqual(cell.containerView.frame.width - cell.content.frame.width, 28, accuracy: 0.01)
                        let attributes = try XCTUnwrap(controller.collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) as? MessageViewLayoutAttributes)
                        XCTAssertEqual(attributes.containerFrame.width, cell.containerView.frame.width, accuracy: 0.01)
                        XCTAssertEqual(attributes.contentFrame.width, cell.content.frame.width, accuracy: 0.01)
                        measured.append(["durationMs": duration, "outgoing": outgoing,
                            "body": cell.containerView.frame.width, "content": cell.content.frame.width])
                    }
                }
                try captureAudioRenderer("continuous-width", controller, measured)
            }
        }
    }

    func testAudioAddressAndPlaybackFramesNeverChangeWidthOrExpandHitTarget() throws {
        try main {
            try withAudioRenderer(width: 390) { controller in
                var width: CGFloat?
                var measured: [[String: Any]] = []
                for source in [nil, URL(string: "mid:uploading/synthetic.m4a"), URL(string: "/v0/file/synthetic.m4a")] {
                    let message = try audioMessage(duration: 20_000, ref: source)
                    let cell = try showAudio(message, on: controller)
                    let (play, range) = try audioAttachment(in: cell)
                    if let previous = width { XCTAssertEqual(cell.containerView.frame.width, previous, accuracy: 0.01) }
                    width = cell.containerView.frame.width
                    cell.content.layoutManager.ensureLayout(for: cell.content.textContainer)
                    let glyphs = cell.content.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    let rect = cell.content.layoutManager.boundingRect(forGlyphRange: glyphs, in: cell.content.textContainer)
                    let hit = cell.content.getURLForTap(CGPoint(x: rect.midX, y: rect.midY))
                    XCTAssertEqual(hit?.path, "/audio/toggle-play")
                    let blank = cell.content.getURLForTap(CGPoint(x: cell.content.bounds.maxX - 1, y: rect.midY))
                    XCTAssertNotEqual(blank?.path, "/audio/toggle-play", "Width must not enlarge the playback hit")
                    for action in ["play", "pause", "reset"] {
                        play.delegate?.action(action, payload: nil) // Attachment frame only, no VLC/network.
                        let size = controller.calcContainerSize(for: message, avatarsVisible: false, progressVisible: false)
                        XCTAssertEqual(size.width, try XCTUnwrap(width), accuracy: 0.01)
                        XCTAssertEqual(play.bounds.width, 24)
                        XCTAssertEqual(play.audioDurationMilliseconds, 20_000)
                    }
                    measured.append(["body": cell.containerView.frame.width, "audioGlyphWidth": play.bounds.width,
                                     "sourceKind": source == nil ? "inline" : source!.scheme == "mid" ? "pending" : "server"])
                }
                try captureAudioRenderer("stable-width-and-hit", controller, measured)
            }
        }
    }

    func testAudioUnknownLegacySmallViewportAndMixedContentPreserveRealLayout() throws {
        try main {
            // Policy's invalid-budget guard only: the pre-existing generic
            // maxContentWidth fallback at a nonpositive viewport is not changed.
            let invalidBudgets: [CGFloat] = [0, -1, .infinity, .nan]
            for budget in invalidBudgets {
                XCTAssertEqual(MessageBubbleLayoutPolicy.voiceWidth(durationMs: Int.max, maxWidth: budget), 0)
            }
            try withAudioRenderer(width: 320) { controller in
                var measured: [[String: Any]] = []
                for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
                    for style in [UIUserInterfaceStyle.light, .dark] {
                        let traits = UITraitCollection(traitsFrom: [
                            UITraitCollection(preferredContentSizeCategory: category),
                            UITraitCollection(userInterfaceStyle: style)])
                        controller.parent?.setOverrideTraitCollection(traits, forChild: controller)
                        controller.overrideUserInterfaceStyle = style
                        try withCurrentTraits(traits) {
                            let durations: [Int?] = [nil, 0, -1000, 1000, 60_000, 120_000, Int.max, Int.min]
                            for duration in durations {
                                let message = try audioMessage(duration: duration)
                                let cell = try showAudio(message, on: controller)
                                let limit = controller.calcMaxContentWidth(for: message, avatarsVisible: false) + 28
                                let play = try audioAttachment(in: cell)
                                XCTAssertEqual(play.0.audioDurationMilliseconds, duration)
                                XCTAssertGreaterThanOrEqual(cell.containerView.frame.width + 0.51, min(128, limit))
                                XCTAssertLessThanOrEqual(cell.containerView.frame.width, limit + 0.51)
                                XCTAssertGreaterThan(cell.containerView.frame.height, 0)
                                if duration == nil || duration! <= 0 {
                                    XCTAssertTrue(cell.content.attributedText.string.contains("-:--"))
                                    XCTAssertFalse(cell.content.attributedText.string.contains("0:01"))
                                    if category == .large {
                                        XCTAssertEqual(cell.containerView.frame.width, min(128, limit), accuracy: 0.51)
                                    }
                                }
                                if duration == 120_000 {
                                    XCTAssertTrue(cell.content.attributedText.string.contains("2:00"))
                                }
                                if category == .large, duration == 60_000 || duration == 120_000 {
                                    XCTAssertEqual(cell.containerView.frame.width, min(224, limit), accuracy: 0.51)
                                }
                                measured.append(["durationKind": duration == nil ? "unknown" : String(duration!),
                                    "category": category.rawValue, "dark": style == .dark,
                                    "body": cell.containerView.frame.width, "height": cell.containerView.frame.height,
                                    "maximum": limit])
                            }
                            let first = try audioMessage(duration: 4000)
                            let second = try audioMessage(duration: 45_000)
                            first.content = Drafty(content: "真实混合正文保持并自然换行。").append(try XCTUnwrap(first.content))
                                .append(Drafty(content: " 两段之间的正文 ")).append(try XCTUnwrap(second.content))
                            let cell = try showAudio(first, on: controller)
                            XCTAssertTrue(cell.content.attributedText.string.contains("真实混合正文"))
                            XCTAssertTrue(cell.content.attributedText.string.contains("两段之间的正文"))
                            var audioCount = 0
                            cell.content.attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: cell.content.attributedText.length)) { value, _, _ in
                                if (value as? MultiImageTextAttachment)?.type == "audio/toggle-play" { audioCount += 1 }
                            }
                            XCTAssertEqual(audioCount, 2)
                            let contentLimit = controller.calcMaxContentWidth(for: first, avatarsVisible: false)
                            let natural = controller.textSizeHelper.computeSize(for: cell.content.attributedText,
                                within: contentLimit)
                            XCTAssertGreaterThanOrEqual(cell.containerView.frame.width + 0.51, min(natural.width, contentLimit) + 28)
                            XCTAssertLessThanOrEqual(cell.containerView.frame.width,
                                controller.calcMaxContentWidth(for: first, avatarsVisible: false) + 28.51)
                            let quote = Drafty.quote(quoteHeader: "合成引用", authorUid: "fixture-peer",
                                                    quoteContent: Drafty(content: "引用文字保持"))
                            let replied = try audioMessage(duration: 20_000)
                            replied.content = quote.append(try XCTUnwrap(replied.content))
                            let replyCell = try showAudio(replied, on: controller)
                            var renderedQuote: QuotedAttachment?
                            replyCell.content.attributedText.enumerateAttribute(.attachment,
                                in: NSRange(location: 0, length: replyCell.content.attributedText.length)) { value, _, _ in
                                if let quoted = value as? QuotedAttachment { renderedQuote = quoted }
                            }
                            XCTAssertTrue(try XCTUnwrap(renderedQuote).attributedString.string.contains("引用文字保持"))
                            XCTAssertNotNil(try XCTUnwrap(renderedQuote).image)
                            _ = try audioAttachment(in: replyCell)
                            try captureAudioRenderer("small-\(category.rawValue)-\(style.rawValue)", controller, measured)
                            let plain = StoredMessage()
                            plain.msgId = 2; plain.seq = 2; plain.from = "fixture-peer"
                            plain.content = Drafty(content: "字")
                            let plainCell = try showAudio(plain, on: controller)
                            if category == .large { XCTAssertLessThan(plainCell.containerView.frame.width, 128) }
                            XCTAssertEqual(plainCell.content.attributedText.string, "字")
                        }
                    }
                }
            }
        }
    }

    private func withCurrentTraits(_ traits: UITraitCollection, _ body: () throws -> Void) throws {
        var result: Result<Void, Error>?
        traits.performAsCurrent { result = Result { try body() } }
        try XCTUnwrap(result).get()
    }

    private func withAudioRenderer(width: CGFloat, _ body: (AudioWidthController) throws -> Void) throws {
        let f = try current()
        f.controller.resignFirstResponder()
        let controller = AudioWidthController()
        controller.interactor = nil
        controller.myUID = "fixture-local" // Local direction input only; SDK remains anonymous.
        f.root.addChild(controller)
        f.root.setOverrideTraitCollection(UITraitCollection(traitsFrom: [
            UITraitCollection(preferredContentSizeCategory: .large),
            UITraitCollection(userInterfaceStyle: .light)]), forChild: controller)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 640)
        f.root.view.addSubview(controller.view)
        controller.didMove(toParent: f.root)
        defer {
            controller.collectionView.dataSource = nil
            controller.willMove(toParent: nil); controller.view.removeFromSuperview()
            controller.removeFromParent()
        }
        controller.view.layoutIfNeeded()
        XCTAssertTrue(controller.collectionView.collectionViewLayout is MessageViewLayout)
        try body(controller)
    }

    private func audioMessage(duration: Int?, outgoing: Bool = false, ref: URL? = nil) throws -> StoredMessage {
        let message = StoredMessage()
        message.msgId = 1; message.seq = 1; message.from = outgoing ? "fixture-local" : "fixture-peer"
        message.ts = Date(timeIntervalSince1970: 1_700_000_000)
        message.content = try Drafty(plainText: " ").insertAudio(at: 0, mime: "audio/m4a",
            bits: ref == nil ? Data([1, 2, 3, 4]) : nil, preview: Data([12, 25, 50, 25]),
            duration: duration ?? 0, fname: nil, refurl: ref, size: 4)
        if duration == nil { message.content?.entities?.first?.data?.removeValue(forKey: "duration") }
        return message
    }

    private func showAudio(_ message: StoredMessage, on controller: AudioWidthController) throws -> MessageCell {
        controller.messages = [message]
        controller.messageSeqIdIndex = [message.seqId: 0]
        controller.collectionView.collectionViewLayout.invalidateLayout()
        controller.collectionView.reloadData()
        controller.view.layoutIfNeeded(); controller.collectionView.layoutIfNeeded()
        let cell = try XCTUnwrap(controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? MessageCell)
        cell.layoutIfNeeded(); cell.content.layoutIfNeeded()
        XCTAssertNotNil(cell.window)
        XCTAssertNotNil(message.cachedContent)
        return cell
    }

    private func audioAttachment(in cell: MessageCell) throws -> (MultiImageTextAttachment, NSRange) {
        let content = try XCTUnwrap(cell.content.attributedText)
        var found: (MultiImageTextAttachment, NSRange)?
        content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.length)) { value, range, _ in
            if let play = value as? MultiImageTextAttachment, play.type == "audio/toggle-play", found == nil {
                found = (play, range)
            }
        }
        return try XCTUnwrap(found)
    }

    private func captureAudioRenderer(_ name: String, _ controller: AudioWidthController, _ values: [[String: Any]]) throws {
        let view = controller.view!
        var drawn = false
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            drawn = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        guard drawn else { throw Failure.renderingFailed }
        let png = XCTAttachment(image: image); png.name = "audio-width-" + name; png.lifetime = .keepAlways; add(png)
        let data = try JSONSerialization.data(withJSONObject: ["scope": "actual formatter, MessageCell and MessageViewLayout; no playback", "measurements": values], options: [.sortedKeys])
        let json = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        json.name = "audio-width-" + name + "-geometry"; json.lifetime = .keepAlways; add(json)
    }

    func testLimitFinishAndReleaseOrderingUseOriginalNibAndSubmissionDispatch() throws {
        try main {
            let f = try current(), bar = f.bar
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-limit-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir); bar.delegate = f.spy }
            for finishFirst in [true, false] {
                for locked in [false, true] {
                    bar.resetRecordingState()
                    let controller = LimitSubmissionController(bar: bar)
                    let bridge = LimitRecordingUIBridge(bar: bar)
                    var engine: LimitRecordingEngine!
                    let recorder = MediaRecorder(session: LimitRecordingSession(), factory: { url, _ in
                        engine = LimitRecordingEngine(url: url); return engine
                    }, directory: dir, schedulesTimer: false)
                    defer { recorder.retire(); controller.voiceRecorder = nil }
                    recorder.delegate = bridge
                    controller.voiceRecorder = recorder
                    bar.delegate = controller
                    let gesture = ControlledLongPress()
                    gesture.phase = .began; gesture.point = CGPoint(x: 210, y: 650)
                    // Real handler; the anonymous controller cannot acquire a real
                    // account recorder. Start only the injected AV-boundary recorder.
                    bar.longPressed(sender: gesture)
                    recorder.start()
                    XCTAssertEqual(engine.requestedDurations, [60])
                    if locked {
                        gesture.phase = .changed; gesture.point.y -= 61
                        bar.longPressed(sender: gesture)
                    }
                    engine.currentTime = 59.875
                    recorder.recordUpdate()
                    engine.isRecording = false; engine.currentTime = 0
                    if finishFirst { recorder.recordingFinished(engine, successfully: true) }
                    gesture.phase = .ended
                    bar.longPressed(sender: gesture)
                    XCTAssertEqual(controller.acceptedDurations, [], "The old release must never submit")
                    if !finishFirst {
                        XCTAssertEqual(recorder.state, .recording)
                        XCTAssertEqual(bridge.finishes, 0)
                        recorder.recordingFinished(engine, successfully: true)
                    }
                    XCTAssertEqual(recorder.state, .preview)
                    XCTAssertEqual(bridge.finishes, 1)
                    XCTAssertFalse(recorder.reachedDurationLimit)
                    // A repeated old release is still blocked by the real Bar flag.
                    bar.longPressed(sender: gesture)
                    XCTAssertTrue(controller.acceptedDurations.isEmpty)
                    recorder.recordingFinished(engine, successfully: true)
                    XCTAssertEqual(bridge.finishes, 1)
                    bar.sendRecording(bar.voiceSendButton as Any)
                    XCTAssertEqual(controller.acceptedDurations, [59_875])
                    XCTAssertEqual(controller.acceptedBytes, [Data([1, 2, 3, 4])])
                    XCTAssertEqual(recorder.state, .transferred)
                    XCTAssertNil(recorder.recordFileURL)
                }
            }
        }
    }

    func testNormalReleaseAndLockedLimitKeepExplicitSendDistinct() throws {
        try main {
            let f = try current(), bar = f.bar
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-limit-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir); bar.delegate = f.spy }
            for lockedLimit in [false, true] {
                bar.resetRecordingState()
                let controller = LimitSubmissionController(bar: bar)
                let bridge = LimitRecordingUIBridge(bar: bar)
                var engine: LimitRecordingEngine!
                let recorder = MediaRecorder(session: LimitRecordingSession(), factory: { url, _ in
                    engine = LimitRecordingEngine(url: url); return engine
                }, directory: dir, schedulesTimer: false)
                defer { recorder.retire(); controller.voiceRecorder = nil }
                controller.voiceRecorder = recorder
                recorder.delegate = bridge; bar.delegate = controller
                let gesture = ControlledLongPress()
                gesture.phase = .began; gesture.point = CGPoint(x: 210, y: 650)
                bar.longPressed(sender: gesture); recorder.start()
                if lockedLimit {
                    gesture.phase = .changed; gesture.point.y -= 61
                    bar.longPressed(sender: gesture)
                    engine.currentTime = 60
                    recorder.recordUpdate()
                    engine.isRecording = false; engine.currentTime = 0
                    recorder.recordingFinished(engine, successfully: true)
                    XCTAssertTrue(recorder.reachedDurationLimit)
                    XCTAssertEqual(recorder.state, .preview)
                } else {
                    engine.currentTime = 59
                }
                gesture.phase = .ended; bar.longPressed(sender: gesture)
                if lockedLimit {
                    XCTAssertTrue(controller.acceptedDurations.isEmpty)
                    XCTAssertEqual(bridge.finishes, 1)
                    bar.sendRecording(bar.voiceSendButton as Any)
                    XCTAssertEqual(controller.acceptedDurations, [60_000])
                } else {
                    XCTAssertEqual(controller.acceptedDurations, [59_000])
                    XCTAssertEqual(bridge.finishes, 1)
                }
                XCTAssertEqual(engine.stops, 1)
                XCTAssertEqual(recorder.state, .transferred)
            }
        }
    }

    func testRecordingStatesAndOriginalButtonsForwardActions() throws {
        try main {
            let f = try current(), bar = f.bar
            bar.recordingDidStart(); bar.audioUpdateAmplitude(amplitude: 0.2, atTime: 4)
            f.settle()
            XCTAssertTrue(bar.audioDurationLabel.text?.contains("正在录音") == true)
            XCTAssertTrue(bar.voiceSendButton.isHidden)
            try capture("holding-controlled-presentation", f)
            bar.audioBarState(.lock); f.settle()
            try assertButtons([bar.stopAudioRecordingButton, bar.voiceSendButton, bar.deleteAudioButton], in: f)
            try click(bar.stopAudioRecordingButton, selector: "stopRecording:", in: f)
            XCTAssertEqual(f.spy.actions.last, "stopRecording")
            bar.recordingDidStop()
            bar.audioPlaybackPreview(Data([12, 36, 90, 160, 255, 120, 32, 0]), duration: 4)
            f.settle()
            XCTAssertTrue(bar.audioDurationLabel.text?.contains("录音已完成") == true)
            try click(bar.playAudioButton, selector: "playRecording:", in: f)
            XCTAssertEqual(f.spy.actions.last, "playbackStart")
            bar.audioPlaybackAction(.playbackStart); bar.showAudioBar(.longPlayback)
            bar.audioPlaybackTime(2); f.settle()
            XCTAssertTrue(bar.audioDurationLabel.text?.contains("正在试听") == true)
            try capture("listening-controlled-presentation", f)
            try click(bar.pauseAudioButton, selector: "pausePlayback:", in: f)
            XCTAssertEqual(f.spy.actions.last, "playbackPause")
            bar.audioPlaybackAction(.playbackPause); bar.showAudioBar(.longPaused); f.settle()
            XCTAssertEqual(bar.playAudioButton.title(for: .normal), "继续试听")
            try click(bar.voiceSendButton, selector: "sendRecording:", in: f)
            XCTAssertEqual(f.spy.actions.last, "stopAndSend")
            try click(bar.deleteAudioButton, selector: "deleteRecording:", in: f)
            XCTAssertEqual(f.spy.actions.last, "stopAndDelete")
            bar.showInterruptedRecordingPreview(); f.settle()
            XCTAssertTrue(bar.voiceDescriptionLabel.text?.contains("不会自动继续录音") == true)
            XCTAssertEqual(f.spy.actions, ["stopRecording", "playbackStart", "playbackPause", "stopAndSend", "stopAndDelete"])
            try capture("paused-interrupted-preview", f)
        }
    }

    func testDynamicTypeDarkLightAndScrollableMinimumTargets() throws {
        try main {
            let f = try current(), bar = f.bar
            bar.recordingDidStart(); bar.audioBarState(.lock); bar.recordingDidStop()
            bar.audioPlaybackPreview(Data([0, 32, 128, 255, 64]), duration: 4)
            f.applyTraits(category: .large, style: .light)
            let normalSize = try XCTUnwrap(bar.audioDurationLabel.font).pointSize
            let lightColor = try XCTUnwrap(bar.audioView.backgroundColor).resolvedColor(with: bar.traitCollection)
            try capture("light-default-type", f)
            f.applyTraits(category: .accessibilityExtraExtraExtraLarge, style: .dark)
            XCTAssertEqual(bar.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
            XCTAssertGreaterThan(try XCTUnwrap(bar.audioDurationLabel.font).pointSize, normalSize)
            XCTAssertNotEqual(try XCTUnwrap(bar.audioView.backgroundColor).resolvedColor(with: bar.traitCollection), lightColor)
            // Deliberately small component viewport, not a fabricated device or chat page.
            bar.voicePanelMaximumHeight = 260; f.settle()
            XCTAssertTrue(bar.voiceScrollView.isScrollEnabled)
            XCTAssertGreaterThan(bar.voiceScrollView.contentSize.height, bar.voiceScrollView.bounds.height)
            try assertButtons([bar.playAudioButton, bar.voiceSendButton, bar.deleteAudioButton], in: f)
            try capture("dark-largest-type-scroll", f)
        }
    }

    func testInputAccessoryKeyboardAppearsAndDismisses() throws {
        try main {
            let f = try current(), bar = f.bar
            let beforeShow = keyboardSequence
            XCTAssertTrue(bar.inputField.becomeFirstResponder())
            try awaitStable("software keyboard shown with complete geometry") {
                let frame = self.keyboardFrame.intersection(UIScreen.main.bounds)
                guard self.keyboardSequence > beforeShow, !self.keyboardFrame.isNull,
                      frame.height > 100, bar.inputField.isFirstResponder, bar.window != nil else { return nil }
                let accessory = bar.convert(bar.bounds, to: nil)
                // The initial 98pt notification described only the accessory, not a software keyboard.
                guard frame.height - accessory.intersection(frame).height - f.window.safeAreaInsets.bottom > 100 else { return nil }
                return [frame.minY, frame.height, accessory.minY, accessory.height]
            }
            bar.inputField.text = "组件布局测试" // synthetic, never submitted
            bar.textViewDidChange(bar.inputField); f.settle()
            let barScreen = bar.convert(bar.bounds, to: nil)
            XCTAssertGreaterThan(barScreen.height, 0)
            XCTAssertGreaterThan(keyboardFrame.intersection(UIScreen.main.bounds).height, 100)
            XCTAssertGreaterThanOrEqual(barScreen.intersection(UIScreen.main.bounds).height, barScreen.height - 1)
            XCTAssertFalse(bar.inputField.isHidden)
            XCTAssertTrue(f.spy.sentTexts.isEmpty)
            try capture("keyboard-shown", f)
            let beforeHide = keyboardSequence
            XCTAssertTrue(bar.inputField.resignFirstResponder())
            XCTAssertTrue(f.controller.becomeFirstResponder())
            try awaitStable("software keyboard hidden with accessory retained") {
                guard self.keyboardSequence > beforeHide, !self.keyboardFrame.isNull,
                      !bar.inputField.isFirstResponder, f.controller.isFirstResponder, bar.window != nil else { return nil }
                let frame = self.keyboardFrame.intersection(UIScreen.main.bounds)
                let accessory = bar.convert(bar.bounds, to: nil)
                // This controller intentionally retains its inputAccessoryView. Its frame need not be zero.
                guard frame.height > 0, accessory.intersection(frame).height >= accessory.height - 1,
                      frame.height - accessory.height <= f.window.safeAreaInsets.bottom + 1 else { return nil }
                return [frame.minY, frame.height, accessory.minY, accessory.height]
            }
            f.settle(); try capture("keyboard-dismissed", f)
        }
    }

    func testResetAfterGestureDoesNotReusePreviousLayout() throws {
        try main {
            let f = try current(), bar = f.bar, gesture = ControlledLongPress()
            gesture.point = CGPoint(x: 200, y: 600); gesture.phase = .began
            bar.longPressed(sender: gesture); bar.recordingDidStart()
            let baseline = bar.sendButtonHorizontal.constant
            gesture.phase = .changed; gesture.point.x -= 20
            bar.longPressed(sender: gesture)
            XCTAssertEqual(bar.sendButtonHorizontal.constant, baseline - 20)
            bar.resetRecordingState(); f.settle()
            bar.inputField.text = "测试"; bar.textViewDidChange(bar.inputField); f.settle()
            let textLayout = CGPoint(x: bar.sendButtonHorizontal.constant, y: bar.sendButtonVertical.constant)
            bar.resetRecordingState(); bar.resetRecordingState(); f.settle()
            XCTAssertEqual(bar.sendButtonHorizontal.constant, textLayout.x)
            XCTAssertEqual(bar.sendButtonVertical.constant, textLayout.y)
            bar.inputField.text = ""; bar.textViewDidChange(bar.inputField)
            bar.sendButtonHorizontal.constant = -41; bar.sendButtonVertical.constant = -31
            gesture.phase = .began; gesture.point = CGPoint(x: 180, y: 620)
            bar.longPressed(sender: gesture); bar.recordingDidStart()
            gesture.phase = .changed; gesture.point.y -= 20
            bar.longPressed(sender: gesture)
            XCTAssertEqual(bar.sendButtonHorizontal.constant, -41)
            XCTAssertEqual(bar.sendButtonVertical.constant, -51)
            bar.resetRecordingState(); f.settle()
            XCTAssertTrue(bar.audioView.isHidden)
            try capture("reset-new-layout", f)
        }
    }

    func testControlledGestureHandlerUsesSameWindowAndThresholds() throws {
        try main {
            let f = try current(), bar = f.bar, gesture = ControlledLongPress()
            gesture.phase = .began; gesture.point = CGPoint(x: 210, y: 650)
            bar.longPressed(sender: gesture); bar.recordingDidStart(); f.settle()
            XCTAssertEqual(f.spy.actions, ["start"])
            let originalWindow = try XCTUnwrap(bar.window)
            gesture.phase = .changed; gesture.point.y -= 61
            bar.longPressed(sender: gesture); f.settle()
            XCTAssertTrue(gesture.lastCoordinateView === originalWindow)
            XCTAssertFalse(bar.stopAudioRecordingButton.isHidden)
            XCTAssertTrue(bar.voiceDescriptionLabel.text?.contains("已锁定录音") == true)
            gesture.phase = .ended; bar.longPressed(sender: gesture)
            XCTAssertEqual(f.spy.actions, ["start"], "Locking must not submit on release")
            try capture("controlled-up-lock", f)
            bar.resetRecordingState(); f.settle()
            gesture.phase = .began; gesture.point = CGPoint(x: 210, y: 650)
            bar.longPressed(sender: gesture); bar.recordingDidStart(); f.settle()
            gesture.phase = .changed; gesture.point.x -= 61
            bar.longPressed(sender: gesture)
            XCTAssertEqual(f.spy.actions.last, "stopAndDelete")
            bar.resetRecordingState(); f.settle()
            gesture.phase = .began; bar.longPressed(sender: gesture); bar.recordingDidStart()
            gesture.phase = .ended; bar.longPressed(sender: gesture)
            XCTAssertEqual(f.spy.actions.last, "stopAndSend")
            XCTAssertEqual(f.spy.actions, ["start", "start", "stopAndDelete", "start", "stopAndSend"])
            try capture("controlled-handler-actions", f)
        }
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }

    private func assertButtons(_ buttons: [UIButton?], in f: AccessoryFixture) throws {
        for optional in buttons {
            let button = try XCTUnwrap(optional)
            XCTAssertFalse(button.isHidden)
            XCTAssertTrue(button.isEnabled)
            XCTAssertGreaterThanOrEqual(button.bounds.height, 52)
            XCTAssertGreaterThan(button.bounds.width, 0)
            f.bar.voiceScrollView.scrollRectToVisible(button.convert(button.bounds, to: f.bar.voiceScrollView), animated: false)
            f.settle()
            let readinessDeadline = ProcessInfo.processInfo.systemUptime + 3
            try awaitPresentation(f, until: readinessDeadline)
            let rectangle = button.convert(button.bounds, to: f.bar.voiceScrollView)
            XCTAssertTrue(f.bar.voiceScrollView.bounds.insetBy(dx: -1, dy: -1).contains(rectangle))
            let actualWindow = try XCTUnwrap(button.window)
            func hitAtCenter() -> UIView? {
                let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: actualWindow)
                let hit = actualWindow.hitTest(center, with: nil)
                lastHitEvidence = ["button": button.accessibilityIdentifier ?? "", "hitClass": hit.map { NSStringFromClass(type(of: $0)) } ?? "none",
                                   "matches": hit === button || hit?.isDescendant(of: button) == true,
                                   "buttonInteractive": button.isUserInteractionEnabled,
                                   "targetWindowPresent": button.window === actualWindow,
                                   "transitionLayers": presentationViews(f).map { ["class": NSStringFromClass(type(of: $0)),
                                       "keys": $0.layer.animationKeys() ?? []] as [String: Any] }]
                return hit
            }
            try awaitStable("button center hit after transition", until: readinessDeadline) {
                let hit = hitAtCenter()
                guard button.window === actualWindow, hit === button || hit?.isDescendant(of: button) == true else { return nil }
                let frame = button.convert(button.bounds, to: actualWindow)
                return [frame.minX, frame.minY, frame.width, frame.height]
            }
            let hit = hitAtCenter()
            XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true)
            let needed = try XCTUnwrap(button.titleLabel).sizeThatFits(CGSize(width: button.bounds.width - button.contentEdgeInsets.left - button.contentEdgeInsets.right,
                                                                            height: .greatestFiniteMagnitude))
            XCTAssertLessThanOrEqual(needed.height + button.contentEdgeInsets.top + button.contentEdgeInsets.bottom, button.bounds.height + 1)
            XCTAssertFalse(button.accessibilityIdentifier?.isEmpty ?? true)
        }
    }

    private func click(_ button: UIButton, selector: String, in f: AccessoryFixture) throws {
        try assertButtons([button], in: f)
        XCTAssertTrue(button.actions(forTarget: f.bar, forControlEvent: .touchUpInside)?.contains(selector) == true)
        button.sendActions(for: .touchUpInside) // Actual XIB target/action, not a finger event.
    }

    private func capture(_ name: String, _ f: AccessoryFixture, waitForStability: Bool = true) throws {
        f.settle()
        if waitForStability { try awaitPresentation(f) }
        let bar = f.bar
        // Draw the loaded UIKit view, not a reconstructed image or fake chat screenshot.
        var drawn = false
        let png = UIGraphicsImageRenderer(bounds: bar.bounds).image { _ in
            drawn = bar.drawHierarchy(in: bar.bounds, afterScreenUpdates: true)
        }.pngData()
        guard drawn, let data = png, !data.isEmpty else { throw Failure.renderingFailed }
        let image = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        image.name = "voice-component-" + name; image.lifetime = .keepAlways; add(image)
        func rect(_ value: CGRect) -> [CGFloat] { value.isNull ? [] : [value.minX, value.minY, value.width, value.height] }
        let buttons = [bar.stopAudioRecordingButton!, bar.voiceSendButton!, bar.playAudioButton!, bar.pauseAudioButton!, bar.deleteAudioButton!]
        let evidence: [String: Any] = [
            "scope": "Original SendMessageBar and App XIB in neutral accessory container; not a chat/recording/send test",
            "snapshotSource": "UIKit drawHierarchy of loaded component; not XCUIScreen or keyboard pixels",
            "case": name, "hostActive": UIApplication.shared.applicationState == .active,
            "sourceClass": NSStringFromClass(SendMessageBar.self), "bundleIsApp": Bundle(for: SendMessageBar.self) == Bundle.main,
            "windowPresent": bar.window != nil, "bar": rect(bar.bounds), "safeInsets": [bar.safeAreaInsets.top, bar.safeAreaInsets.bottom],
            "category": bar.traitCollection.preferredContentSizeCategory.rawValue,
            "dark": bar.traitCollection.userInterfaceStyle == .dark,
            "headingFontPoints": bar.audioDurationLabel.font.pointSize,
            "scrollEnabled": bar.voiceScrollView.isScrollEnabled, "scrollViewport": rect(bar.voiceScrollView.bounds),
            "contentHeight": bar.voiceScrollView.contentSize.height,
            "keyboardShows": keyboardShows, "keyboardHides": keyboardHides, "keyboardFrame": rect(keyboardFrame),
            "keyboardSequence": keyboardSequence, "keyboardSamples": keyboardSamples,
            "lastHit": lastHitEvidence, "waitedForStablePresentation": waitForStability,
            "transitionLayers": presentationViews(f).map { ["class": NSStringFromClass(type(of: $0)),
                "keys": $0.layer.animationKeys() ?? []] as [String: Any] },
            "sendButton": ["hasImage": bar.sendButton.currentImage != nil, "title": bar.sendButton.currentTitle ?? "",
                           "imageViewHasImage": bar.sendButton.imageView?.image != nil,
                           "imageVisibility": sendImageVisibility(bar.sendButton).evidence,
                           "titleLines": bar.sendButton.titleLabel?.numberOfLines ?? -1,
                           "frame": rect(bar.sendButton.bounds)],
            "inputFirstResponder": bar.inputField.isFirstResponder,
            "inputBeginEvents": inputBeginEvents, "actualInputLength": bar.inputField.actualText.count,
            "buttons": buttons.map { ["id": $0.accessibilityIdentifier ?? "", "hidden": $0.isHidden,
                                       "frame": rect($0.convert($0.bounds, to: bar)), "height": $0.bounds.height] as [String: Any] },
            "delegateActions": f.spy.actions, "componentDelegateHasNetworkImplementation": false
        ]
        let json = XCTAttachment(data: try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]),
                                 uniformTypeIdentifier: "public.json")
        json.name = "voice-component-" + name; json.lifetime = .keepAlways; add(json)
    }
}

private final class AccessoryFixture {
    let window = UIWindow(frame: UIScreen.main.bounds)
    let root = UIViewController()
    let controller = AccessoryController()
    let spy = VoiceDelegateSpy()
    var bar: SendMessageBar { controller.bar }

    init() {
        window.windowLevel = .normal + 1
        root.view.backgroundColor = .systemBackground
        window.rootViewController = root
        root.addChild(controller)
        controller.view.frame = root.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(controller.view); controller.didMove(toParent: root)
        bar.delegate = spy
    }
    func settle() {
        for _ in 0..<3 {
            root.view.layoutIfNeeded(); bar.setNeedsLayout(); bar.layoutIfNeeded(); bar.window?.layoutIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
    func applyTraits(category: UIContentSizeCategory, style: UIUserInterfaceStyle) {
        let traits = UITraitCollection(traitsFrom: [UITraitCollection(preferredContentSizeCategory: category),
                                                   UITraitCollection(userInterfaceStyle: style)])
        traits.performAsCurrent {
            root.setOverrideTraitCollection(traits, forChild: controller)
            window.overrideUserInterfaceStyle = style
            // The accessory belongs to UIKit's input window, not the child view
            // hierarchy. Override its real traits rather than a mock font/getter.
            if #available(iOS 17.0, *) {
                bar.traitOverrides.preferredContentSizeCategory = category
                bar.traitOverrides.userInterfaceStyle = style
            }
            settle()
        }
    }
}

private final class AccessoryController: UIViewController {
    let bar = SendMessageBar()
    override var canBecomeFirstResponder: Bool { true }
    override var inputAccessoryView: UIView? { bar }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        bar.autoresizingMask = .flexibleHeight
    }
}

// Controlled inputs exercise the original handler, not UIKit touch recognition.
private final class ControlledLongPress: UILongPressGestureRecognizer {
    var phase: UIGestureRecognizer.State = .possible
    var point = CGPoint.zero
    weak var lastCoordinateView: UIView?
    override var state: UIGestureRecognizer.State {
        get { phase }
        set { phase = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { lastCoordinateView = view; return point }
}

private final class VoiceDelegateSpy: SendMessageBarDelegate, PendingMessagePreviewDelegate {
    var actions: [String] = []
    var sentTexts: [String] = []
    func sendMessageBar(sendText: String) { sentTexts.append(sendText) }
    func sendMessageBar(attachment: MessageAttachmentAction) {}
    func sendMessageBar(textChangedTo text: String) {}
    func sendMessageBar(enablePeersMessaging: Bool) {}
    func sendMessageBar(recordAudio: AudioBarAction) {
        switch recordAudio {
        case .start: actions.append("start")
        case .stopAndSend: actions.append("stopAndSend")
        case .stopAndDelete: actions.append("stopAndDelete")
        case .lock: actions.append("lock")
        case .stopRecording: actions.append("stopRecording")
        case .pauseRecording: actions.append("pauseRecording")
        case .playbackStart: actions.append("playbackStart")
        case .playbackPause: actions.append("playbackPause")
        case .playbackReset: actions.append("playbackReset")
        }
    }
    func pendingPreviewMessageSize(forMessage msg: NSAttributedString) -> CGSize { .zero }
    func dismissPendingMessagePreview() {}
}

private final class AudioWidthController: MessageViewController {
    // Original loadView/cell configuration/layout consumers; business lifecycle
    // alone is disabled. No neutral cells or alternate flow layout.
    override func viewDidLoad() {
        (collectionView.collectionViewLayout as? MessageViewLayout)?.delegate = self
        collectionView.dataSource = self
    }
    override func viewDidAppear(_ animated: Bool) {}
    override var inputAccessoryView: UIView? { nil }
}

// Actual MessageViewController.sendMessageBar(recordAudio:) is inherited. Only
// its existing handoff boundary is spied; no auth, SDK publish or upload occurs.
private final class LimitSubmissionController: MessageViewController {
    let testedBar: SendMessageBar
    var acceptedDurations: [Int] = []
    var acceptedBytes: [Data] = []
    init(bar: SendMessageBar) { testedBar = bar; super.init() }
    required init?(coder: NSCoder) { fatalError("Test fixture is programmatic") }
    override func sendAudioAttachment(recorder: MediaRecorder) {
        do {
            let (take, data) = try recorder.prepareSubmission(minimumDuration: 3000)
            acceptedDurations.append(take.duration); acceptedBytes.append(data)
            recorder.didSubmit(take)
            testedBar.resetRecordingState()
        } catch { XCTFail("Controlled local Data handoff failed") }
    }
}

// The real recorder callback drives the real bundled Bar; the page's owner gate
// and microphone are outside this component test, not replaced by fake login.
private final class LimitRecordingUIBridge: MediaRecorderDelegate {
    let bar: SendMessageBar
    var finishes = 0
    init(bar: SendMessageBar) { self.bar = bar }
    func didStartRecording(recorder: MediaRecorder) { bar.recordingDidStart() }
    func didFinishRecording(recorder: MediaRecorder, url: URL?, duration: TimeInterval) {
        finishes += 1
        bar.recordingDidStop()
        bar.audioPlaybackPreview(recorder.preview, duration: duration)
    }
    func didUpdateRecording(recorder: MediaRecorder, amplitude: Float, atTime: TimeInterval) {
        bar.audioUpdateAmplitude(amplitude: amplitude, atTime: atTime)
    }
    func didFailRecording(recorder: MediaRecorder, _ error: Error) { bar.resetRecordingState() }
    func didUpdateRecordingPermission(recorder: MediaRecorder, event: MediaRecorderPermissionEvent) {}
}

private final class LimitRecordingSession: MediaRecordingSession {
    var recordPermission: AVAudioSession.RecordPermission { .granted }
    func requestRecordPermission(_ callback: @escaping (Bool) -> Void) { XCTFail("Unexpected permission request") }
    func activate() throws {}
    func deactivate() throws {}
}

private final class LimitRecordingEngine: MediaRecordingEngine {
    weak var delegate: AVAudioRecorderDelegate?
    var isRecording = false
    var currentTime: TimeInterval = 0
    var isMeteringEnabled = false
    var requestedDurations: [TimeInterval] = []
    var stops = 0
    let url: URL
    init(url: URL) { self.url = url }
    func prepareToRecord() -> Bool { (try? Data([1, 2, 3, 4]).write(to: url)) != nil }
    func record() -> Bool { isRecording = true; return true }
    func record(forDuration duration: TimeInterval) -> Bool { requestedDurations.append(duration); return record() }
    func stop() { stops += 1; isRecording = false; currentTime = 0 }
    func pause() { isRecording = false }
    func updateMeters() {}
    func averagePower(forChannel channelNumber: Int) -> Float { -12 }
}
