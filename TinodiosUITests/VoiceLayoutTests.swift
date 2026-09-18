// Copyright (c) 2026 CLAW OS contributors.
// Original App class + original bundled XIB. Component presentation only:
// no chat route, credentials, microphone, recording, upload, or synthetic login.
import XCTest
import UIKit
import UIKit.UIGestureRecognizerSubclass
import TinodiosDB
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
            bar.inputField.text = "组件布局测试" // synthetic, never submitted
            bar.textViewDidChange(bar.inputField); f.settle(); try awaitPresentation(f)
            XCTAssertNil(bar.sendButton.currentImage)
            XCTAssertNil(bar.sendButton.imageView?.image)
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
                           "titleLines": bar.sendButton.titleLabel?.numberOfLines ?? -1,
                           "frame": rect(bar.sendButton.bounds)],
            "inputFirstResponder": bar.inputField.isFirstResponder,
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
