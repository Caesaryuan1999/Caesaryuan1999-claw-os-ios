// Copyright (c) 2026 CLAW OS contributors.
// Original App class + original bundled XIB. Component presentation only:
// no chat route, credentials, microphone, recording, upload, or synthetic login.
import XCTest
import UIKit
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
            for name in [UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidHideNotification] {
                keyboardTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] note in
                    guard let self = self else { return }
                    if note.name == UIResponder.keyboardDidShowNotification {
                        self.keyboardShows += 1
                        self.keyboardFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                    } else {
                        self.keyboardHides += 1
                        self.keyboardFrame = .zero
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
            if let value = fixture { try capture("teardown-current-before-reset", value) }
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

    func testOriginalNibLoadsAndResetsWithoutRecording() throws {
        try main {
            let f = try current(), bar = f.bar
            XCTAssertEqual(Bundle(for: SendMessageBar.self).bundleURL, Bundle.main.bundleURL)
            XCTAssertNotNil(Bundle.main.url(forResource: "SendMessageBar", withExtension: "nib"))
            XCTAssertTrue(bar.inputField is PlaceholderTextView)
            XCTAssertTrue(bar.previewView is RichTextView)
            XCTAssertTrue(bar.wavePreviewImageView is WaveImageView)
            let gestures = descendants(bar).flatMap { $0.gestureRecognizers ?? [] }.compactMap { $0 as? UILongPressGestureRecognizer }
            XCTAssertEqual(gestures.count, 1)
            XCTAssertEqual(try XCTUnwrap(gestures.first).minimumPressDuration, 0.5)
            let original = CGPoint(x: bar.sendButtonHorizontal.constant, y: bar.sendButtonVertical.constant)
            bar.resetRecordingState(); bar.resetRecordingState(); f.settle()
            XCTAssertEqual(bar.sendButtonHorizontal.constant, original.x)
            XCTAssertEqual(bar.sendButtonVertical.constant, original.y)
            XCTAssertTrue(bar.audioView.isHidden)
            XCTAssertFalse(bar.inputField.isHidden)
            XCTAssertTrue(f.spy.actions.isEmpty)
            try capture("initial-and-repeat-reset", f)
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
            XCTAssertTrue(bar.inputField.becomeFirstResponder())
            try awaitMain("software keyboard shown", seconds: 3) {
                self.keyboardShows > 0 && self.keyboardFrame.height > 0 && bar.inputField.isFirstResponder
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
            XCTAssertTrue(bar.inputField.resignFirstResponder())
            XCTAssertTrue(f.controller.becomeFirstResponder())
            try awaitMain("software keyboard hidden", seconds: 3) {
                self.keyboardHides > 0 && !bar.inputField.isFirstResponder && self.keyboardFrame == .zero
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
            let rectangle = button.convert(button.bounds, to: f.bar.voiceScrollView)
            XCTAssertTrue(f.bar.voiceScrollView.bounds.insetBy(dx: -1, dy: -1).contains(rectangle))
            let actualWindow = try XCTUnwrap(button.window)
            let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: actualWindow)
            let hit = actualWindow.hitTest(center, with: nil)
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

    private func capture(_ name: String, _ f: AccessoryFixture) throws {
        f.settle()
        let bar = f.bar
        // Draw the loaded UIKit view, not a reconstructed image or fake chat screenshot.
        var drawn = false
        let png = UIGraphicsImageRenderer(bounds: bar.bounds).image { _ in
            drawn = bar.drawHierarchy(in: bar.bounds, afterScreenUpdates: true)
        }.pngData()
        guard drawn, let data = png, !data.isEmpty else { throw Failure.renderingFailed }
        let image = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        image.name = "voice-component-" + name; image.lifetime = .keepAlways; add(image)
        func rect(_ value: CGRect) -> [CGFloat] { [value.minX, value.minY, value.width, value.height] }
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
    override var state: UIGestureRecognizer.State { phase }
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
