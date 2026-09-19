// Copyright (c) 2026 CLAW OS contributors.
// Actual app UIKit pages, Session/History/Run, isolated SDK/SQLite and URLProtocol transport.
// No real provider, new question/run POST, login, ordinary chat or customer-service submission.
import XCTest
import UIKit
import Contacts
import TinodeSDK
import TinodiosDB
@testable import Tinodios

final class AssistantKnownRunLayoutTests: XCTestCase {
    private var fixture: AssistantFixture!
    private var window: UIWindow!
    private var previousWindow: UIWindow?
    private var container: UIViewController!
    private var navigation: UINavigationController!
    private var currentView: UIView?
    private var anonymousOwner: Tinode?
    private var priorContactStatus: CNAuthorizationStatus?
    private var priorPermissionsCallback: ((CNAuthorizationStatus) -> Void)?
    private var rows: [[String: Any]] = []
    private var snapshot = AssistantBFixture.snapshot()
    private var stream: AssistantFixtureProtocol?
    private var stopRequest: AssistantFixtureProtocol?
    private var runGets = 0
    private var keyboardEndFrame: CGRect = .null
    private var keyboardFrameChanges = 0
    private let cid = AssistantBFixture.cid
    private let otherCID = "00000000-0000-4000-8000-000000000020"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try AssistantFixture.main {
            guard Bundle.main.bundleIdentifier == "app.veilping.clawoschat",
                  Bundle.main.object(forInfoDictionaryKey: "HOST_NAME") as? String == "127.0.0.1:9",
                  SharedUtils.getAuthToken() == nil, Cache.tinode.myUid == nil, Cache.tinode.store?.myUid == nil,
                  !Cache.tinode.isConnectionAuthenticated, ContactsSynchronizer.default.authStatus != .authorized else {
                throw AssistantFixture.Failure.fixture
            }
            fixture = try AssistantFixture(); anonymousOwner = Cache.tinode
            priorContactStatus = ContactsSynchronizer.default.authStatus
            priorPermissionsCallback = ContactsSynchronizer.default.permissionsChangedCallback
            ContactsSynchronizer.default.authStatus = .denied
            AssistantFixtureProtocol.requests = []
            rows = [row(1, role: "user", text: "仅供原生界面验证的合成问题", id: AssistantFixture.second),
                    row(2, role: "assistant", text: "完整历史正文", id: AssistantBFixture.answerID)]
            installTransport()
            fixture.scope.history.loadCapabilities()
            try AssistantFixture.until { !self.fixture.scope.history.capabilityLoading }
            previousWindow = UIApplication.shared.windows.first { $0.isKeyWindow }
            window = UIWindow(frame: UIScreen.main.bounds); window.windowScene = previousWindow?.windowScene
        }
    }
    override func tearDownWithError() throws {
        try AssistantFixture.main {
            defer {
                fixture?.retire(); fixture = nil; AssistantFixtureProtocol.handler = nil
                window?.endEditing(true); window?.isHidden = true; window?.rootViewController = nil
                currentView = nil; navigation = nil; container = nil; window = nil
                previousWindow?.makeKey(); previousWindow = nil
                if let owner = anonymousOwner, owner.myUid == nil { _ = Cache.invalidate(ifCurrent: owner) }
                if let value = priorContactStatus { ContactsSynchronizer.default.authStatus = value }
                ContactsSynchronizer.default.permissionsChangedCallback = priorPermissionsCallback
            }
            if let view = currentView, view.window != nil { try evidence("final", view) }
        }
    }
    private func row(_ seq: Int, role: String, text: String, id: String) -> [String: Any] {
        ["message_id": id, "conversation_id": cid, "run_id": AssistantBFixture.rid, "seq": String(seq),
         "role": role, "text": text, "state": role == "user" ? "completed" : "partial",
         "created_at": AssistantFixture.date, "updated_at": AssistantFixture.date]
    }
    private func installTransport() {
        AssistantFixtureProtocol.handler = { [weak self] transport in
            guard let self = self else { return }
            let path = transport.request.url!.path
            if path.hasSuffix("/capabilities") { transport.reply(AssistantBFixture.capabilitiesValue()) }
            else if path.hasSuffix("/messages") { transport.reply(AssistantFixture.messages(self.rows, revision: "2")) }
            else if path.hasSuffix("/stream") { self.stream = transport; AssistantBFixture.open(transport) }
            else if path.hasSuffix("/stop") { self.stopRequest = transport }
            else if path.contains("/runs/") { self.runGets += 1; transport.reply(self.snapshot) }
            else { transport.reply(AssistantFixture.list([AssistantFixture.conversation(), AssistantFixture.conversation(self.otherCID)])) }
        }
    }
    private func hostHistory(accessibility: Bool = false) throws -> ClawAssistantHistoryViewController {
        let history = ClawAssistantHistoryViewController(session: fixture.scope)
        navigation = UINavigationController(rootViewController: history)
        container = UIViewController(); container.addChild(navigation)
        container.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory:
            accessibility ? .accessibilityExtraExtraExtraLarge : .large), forChild: navigation)
        container.view.addSubview(navigation.view)
        navigation.view.frame = CGRect(x: 16, y: 60, width: 320, height: max(600, window.bounds.height - 140))
        navigation.didMove(toParent: container)
        window.overrideUserInterfaceStyle = accessibility ? .dark : .light
        window.rootViewController = container; window.makeKeyAndVisible()
        container.view.layoutIfNeeded(); navigation.view.layoutIfNeeded()
        currentView = navigation.view
        try AssistantFixture.until { UIApplication.shared.applicationState == .active &&
            history.view.window === self.window && self.fixture.scope.history.hasListSnapshot }
        return history
    }
    private func openDetail(accessibility: Bool = false) throws -> ClawAssistantConversationViewController {
        let history = try hostHistory(accessibility: accessibility)
        let table = try XCTUnwrap(all(history.view).compactMap { $0 as? UITableView }.first)
        history.tableView(table, didSelectRowAt: IndexPath(row: 0, section: 0))
        try AssistantFixture.until { self.navigation.topViewController is ClawAssistantConversationViewController &&
            self.navigation.transitionCoordinator == nil && self.fixture.scope.knownRun?.projection != nil }
        return try XCTUnwrap(navigation.topViewController as? ClawAssistantConversationViewController)
    }
    private func all(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(all) }
    private func control(_ id: String, in view: UIView) throws -> UIButton {
        try XCTUnwrap(all(view).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == id })
    }
    private func label(_ id: String, in view: UIView) throws -> UILabel {
        try XCTUnwrap(all(view).compactMap { $0 as? UILabel }.first { $0.accessibilityIdentifier == id })
    }
    private func isVisible(_ view: UIView) -> Bool {
        guard view.window != nil else { return false }
        var current: UIView? = view
        while let item = current { if item.isHidden || item.alpha == 0 { return false }; current = item.superview }
        return true
    }
    private func revealAndCheckHit(_ button: UIButton, in detail: UIViewController) throws {
        let scroll = try XCTUnwrap(all(detail.view).compactMap { $0 as? UIScrollView }.first {
            $0.accessibilityIdentifier == "claw.ai.conversation.scroll"
        })
        scroll.scrollRectToVisible(button.convert(button.bounds, to: scroll).insetBy(dx: 0, dy: -12), animated: false)
        detail.view.layoutIfNeeded()
        let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: detail.view)
        XCTAssertTrue(detail.view.bounds.contains(point))
        let hit = detail.view.hitTest(point, with: nil)
        XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true)
    }
    private func evidence(_ name: String, _ view: UIView) throws {
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let png = XCTAttachment(image: image); png.name = "assistant-known-" + name; png.lifetime = .keepAlways; add(png)
        let geometry: [[String: Any]] = all(view).filter { $0 is UILabel || $0 is UIButton || $0 is UIScrollView }.map {
            let frame = $0.convert($0.bounds, to: view)
            return ["type": String(describing: type(of: $0)), "id": $0.accessibilityIdentifier ?? "",
                    "x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height,
                    "visible": isVisible($0), "offsetY": ($0 as? UIScrollView)?.contentOffset.y ?? 0]
        }
        let data = try JSONSerialization.data(withJSONObject: ["scope": "actual UIKit; synthetic HTTP and saved text only",
            "geometry": geometry, "run_gets": runGets, "post_count": AssistantFixtureProtocol.requests.filter {
                $0.httpMethod == "POST"
            }.count, "keyboard_frame_changes": keyboardFrameChanges,
            "keyboard_frame": keyboardEndFrame.isNull ? [] : [keyboardEndFrame.minX, keyboardEndFrame.minY,
                keyboardEndFrame.width, keyboardEndFrame.height]], options: [.sortedKeys])
        let json = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        json.name = "assistant-known-" + name + "-geometry"; json.lifetime = .keepAlways; add(json)
    }

    func testActualKnownAnswerAt320AccessibilityUsesClearControlsAndNeverEnablesGeneration() throws {
        try AssistantFixture.main {
            let detail = try openDetail(accessibility: true)
            try AssistantFixture.until { self.stream != nil }
            detail.view.layoutIfNeeded()
            XCTAssertEqual(try label("claw.ai.run.state", in: detail.view).text, "正在回答")
            let stop = try control("claw.ai.run.stop", in: detail.view)
            let recover = try control("claw.ai.run.recover", in: detail.view)
            XCTAssertEqual(stop.currentTitle, "停止回答"); XCTAssertTrue(stop.isEnabled)
            XCTAssertEqual(recover.currentTitle, "恢复原回答")
            for button in [stop, recover] {
                XCTAssertGreaterThanOrEqual(button.bounds.height, 52)
                let title = try XCTUnwrap(button.titleLabel)
                XCTAssertLessThanOrEqual(title.sizeThatFits(CGSize(width: title.bounds.width, height: .greatestFiniteMagnitude)).height,
                                         title.bounds.height + 1)
                XCTAssertGreaterThan(button.bounds.width, 0); XCTAssertLessThanOrEqual(button.bounds.width, 320)
                try revealAndCheckHit(button, in: detail)
            }
            XCTAssertFalse(try control("claw.ai.send", in: detail.view).isEnabled)
            try control("claw.ai.send", in: detail.view).sendActions(for: .touchUpInside)
            XCTAssertFalse(AssistantFixtureProtocol.requests.contains { $0.httpMethod == "POST" })
            try evidence("active-ax-dark", detail.view)
            window.overrideUserInterfaceStyle = .light; detail.view.layoutIfNeeded()
            try evidence("active-ax-light", detail.view)
        }
    }

    func testStopUnknownPersistsAcrossRealNavigationAndOtherConversationRequiresOriginalContext() throws {
        try AssistantFixture.main {
            let detail = try openDetail()
            try control("claw.ai.run.stop", in: detail.view).sendActions(for: .touchUpInside)
            try AssistantFixture.until { self.stopRequest != nil }
            XCTAssertEqual(try label("claw.ai.run.state", in: detail.view).text, "正在停止回答")
            let history = try XCTUnwrap(navigation.viewControllers.first as? ClawAssistantHistoryViewController)
            navigation.popViewController(animated: false)
            try AssistantFixture.until { self.navigation.topViewController === history && detail.parent == nil }
            stopRequest!.fail()
            try AssistantFixture.until { self.fixture.scope.knownRun?.stopping == .unknown }
            let table = try XCTUnwrap(all(history.view).compactMap { $0 as? UITableView }.first)
            history.tableView(table, didSelectRowAt: IndexPath(row: 1, section: 0))
            let alert = try XCTUnwrap(history.presentedViewController as? UIAlertController)
            XCTAssertEqual(alert.message, "上一段对话的停止结果尚未确认。请先查看原回答状态。")
            XCTAssertEqual(alert.actions.map { $0.title ?? "" }, ["取消", "查看原回答"])
            XCTAssertEqual(fixture.scope.selectedConversationID, cid)
            // Alert presentation/copy is real; actions are not invoked through private UIKit handlers.
            alert.dismiss(animated: false)
            try AssistantFixture.until { history.presentedViewController == nil }
            history.tableView(table, didSelectRowAt: IndexPath(row: 0, section: 0))
            try AssistantFixture.until { self.navigation.topViewController is ClawAssistantConversationViewController &&
                self.navigation.transitionCoordinator == nil }
            let resumed = try XCTUnwrap(navigation.topViewController as? ClawAssistantConversationViewController)
            XCTAssertEqual(try control("claw.ai.run.recover", in: resumed.view).currentTitle, "查看原回答状态")
            XCTAssertEqual(try control("claw.ai.run.stop", in: resumed.view).currentTitle, "再次停止回答")
            let before = runGets
            try control("claw.ai.run.recover", in: resumed.view).sendActions(for: .touchUpInside)
            try AssistantFixture.until { self.runGets > before }
            XCTAssertEqual(fixture.scope.knownRun?.stopping, .unknown)
            XCTAssertEqual(AssistantFixtureProtocol.requests.filter { $0.httpMethod == "POST" }.count, 1)
            stopRequest = nil
            try control("claw.ai.run.stop", in: resumed.view).sendActions(for: .touchUpInside)
            try AssistantFixture.until { self.stopRequest != nil }
            snapshot = AssistantBFixture.snapshot(text: "已完成的合成回答", cursor: "3", revision: "3", state: "completed")
            stopRequest!.reply(snapshot)
            try AssistantFixture.until { self.fixture.scope.knownRun?.stopping == .confirmed }
            XCTAssertEqual(try label("claw.ai.run.state", in: resumed.view).text, "回答已完成")
            XCTAssertFalse(isVisible(try control("claw.ai.run.stop", in: resumed.view)))
            XCTAssertEqual(AssistantFixtureProtocol.requests.filter { $0.httpMethod == "POST" }.count, 2)
            try evidence("stop-confirmed-completed", resumed.view)
        }
    }

    func testRealRowsKeepIdentityAndReadingAnchorAcrossDeltaFontAndKeyboard() throws {
        try AssistantFixture.main {
            let text = String(repeating: "这是用于检查阅读位置的合成已存正文。\n", count: 80)
            rows[1]["text"] = text; snapshot = AssistantBFixture.snapshot(text: text)
            let detail = try openDetail()
            try AssistantFixture.until { self.stream != nil }
            let scroll = try XCTUnwrap(all(detail.view).compactMap { $0 as? UIScrollView }.first {
                $0.accessibilityIdentifier == "claw.ai.conversation.scroll"
            })
            detail.view.layoutIfNeeded()
            let answer = try XCTUnwrap(all(detail.view).first { $0.accessibilityIdentifier == "claw.ai.message." + AssistantBFixture.answerID })
            scroll.setContentOffset(CGPoint(x: 0, y: answer.convert(answer.bounds, to: scroll).minY + 40), animated: false)
            let pixel = answer.convert(answer.bounds, to: scroll).minY - scroll.contentOffset.y - scroll.adjustedContentInset.top
            stream!.client?.urlProtocol(stream!, didLoad: try AssistantBFixture.frame(AssistantBFixture.event("3", text: "追加合成正文")))
            try AssistantFixture.until { self.fixture.scope.knownRun?.projection?.lastEvent == "3" }
            detail.view.layoutIfNeeded()
            XCTAssertTrue(all(detail.view).first { $0.accessibilityIdentifier == answer.accessibilityIdentifier } === answer)
            XCTAssertEqual(answer.convert(answer.bounds, to: scroll).minY - scroll.contentOffset.y - scroll.adjustedContentInset.top,
                           pixel, accuracy: 1)
            container.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge),
                                                 forChild: navigation)
            detail.view.layoutIfNeeded()
            XCTAssertEqual(answer.convert(answer.bounds, to: scroll).minY - scroll.contentOffset.y - scroll.adjustedContentInset.top,
                           pixel, accuracy: 1)
            let latest = try control("claw.ai.latest", in: detail.view)
            XCTAssertTrue(isVisible(latest)); XCTAssertGreaterThanOrEqual(latest.bounds.height, 52)
            try evidence("reading-anchor-ax", detail.view)
            latest.sendActions(for: .touchUpInside)
            XCTAssertTrue(latest.isHidden)
            let input = try XCTUnwrap(all(detail.view).compactMap { $0 as? UITextView }.first)
            let keyboardObservation = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
                    guard let self = self,
                          let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                    self.keyboardEndFrame = frame; self.keyboardFrameChanges += 1
                }
            defer { NotificationCenter.default.removeObserver(keyboardObservation) }
            let keyboardIntersection = { () -> CGFloat in
                guard !self.keyboardEndFrame.isNull else { return 0 }
                return detail.view.bounds.intersection(detail.view.convert(self.keyboardEndFrame, from: nil)).height
            }
            XCTAssertTrue(input.becomeFirstResponder())
            try AssistantFixture.until { input.isFirstResponder && self.keyboardFrameChanges > 0 &&
                keyboardIntersection() > 100 && scroll.contentInset.bottom > keyboardIntersection() }
            XCTAssertFalse(try control("claw.ai.send", in: detail.view).isEnabled)
            try evidence("keyboard", detail.view)
            let beforeHide = keyboardFrameChanges
            detail.view.endEditing(true)
            try AssistantFixture.until { !input.isFirstResponder && self.keyboardFrameChanges > beforeHide &&
                keyboardIntersection() == 0 }
            XCTAssertFalse(AssistantFixtureProtocol.requests.contains { $0.httpMethod == "POST" })
        }
    }

    func testLegacyAndCompletedHistoryNeverExposeStopOrRetryGeneration() throws {
        try AssistantFixture.main {
            snapshot = AssistantBFixture.snapshot(text: "不覆盖更新历史", state: "completed")
            let detail = try openDetail()
            XCTAssertEqual(try label("claw.ai.run.state", in: detail.view).text, "回答已完成")
            XCTAssertFalse(isVisible(try control("claw.ai.run.stop", in: detail.view)))
            XCTAssertFalse(isVisible(try control("claw.ai.run.recover", in: detail.view)))
            XCTAssertFalse(all(detail.view).contains { ($0 as? UIButton)?.currentTitle == "重试回答" })
            try evidence("completed", detail.view)
            fixture.scope.markRetired(clearAccount: true); fixture.scope.finishRetirement()
            fixture.scope = try fixture.newScope(generation: 2)
            snapshot = AssistantBFixture.snapshot(state: "interrupted")
            snapshot["legacy"] = true; snapshot["question_message_id"] = ""; snapshot["answer_message_id"] = ""
            fixture.scope.history.loadCapabilities()
            try AssistantFixture.until { !self.fixture.scope.history.capabilityLoading }
            let legacy = try openDetail()
            XCTAssertFalse(isVisible(try control("claw.ai.run.stop", in: legacy.view)))
            XCTAssertFalse(isVisible(try control("claw.ai.run.recover", in: legacy.view)))
            XCTAssertTrue(all(legacy.view).contains { ($0 as? UILabel)?.text == "完整历史正文" })
            XCTAssertFalse(AssistantFixtureProtocol.requests.contains { $0.httpMethod == "POST" })
            try evidence("legacy", legacy.view)
        }
    }

    func test401HidesRealPageAndOldPageLeaseCannotReleaseNewScopeReader() throws {
        try AssistantFixture.main {
            let old = try openDetail()
            AssistantFixtureProtocol.handler = { $0.replyUnauthorized(contentType: "text/html") }
            try control("claw.ai.run.recover", in: old.view).sendActions(for: .touchUpInside)
            try AssistantFixture.until { self.fixture.scope.isBlocked }
            XCTAssertFalse(all(old.view).contains { ($0 as? UILabel)?.text == "前缀" })
            XCTAssertTrue(isVisible(try control("claw.ai.account", in: old.view)))
            XCTAssertTrue(fixture.owner.isSessionActive)
            fixture.scope = try fixture.newScope(generation: 2)
            stream = nil; installTransport()
            fixture.scope.history.loadCapabilities()
            try AssistantFixture.until { !self.fixture.scope.history.capabilityLoading }
            let current = try openDetail()
            try AssistantFixture.until { self.stream != nil }
            // Controlled old lifecycle callback, distinct from the real navigation transitions above.
            old.beginAppearanceTransition(false, animated: false); old.endAppearanceTransition()
            let before = runGets
            try control("claw.ai.run.recover", in: current.view).sendActions(for: .touchUpInside)
            try AssistantFixture.until { self.runGets > before }
            XCTAssertTrue(fixture.scope.isCurrent); XCTAssertNotNil(fixture.scope.knownRun?.projection)
            XCTAssertFalse(AssistantFixtureProtocol.requests.contains { $0.httpMethod == "POST" })
            try evidence("new-scope", current.view)
        }
    }
}
