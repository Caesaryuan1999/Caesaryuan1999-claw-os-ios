// Copyright (c) 2026 CLAW OS contributors.
// Original UIKit Assistant controllers/App tab bar with synthetic Service responses.
// No live provider, login, ordinary-message send, or customer-service submission.
import XCTest
import UIKit
import Contacts
import TinodeSDK
@testable import Tinodios

final class AssistantLayoutTests: XCTestCase {
    private var fixture: AssistantFixture!
    private var window: UIWindow!
    private var previousWindow: UIWindow?
    private var currentView: UIView?
    private var priorContactStatus: CNAuthorizationStatus?
    private var priorPermissionsCallback: ((CNAuthorizationStatus) -> Void)?
    private var anonymousOwner: Tinode?
    override func setUpWithError() throws {
        continueAfterFailure = false
        try AssistantFixture.main {
            guard Bundle.main.bundleIdentifier == "app.veilping.clawoschat",
                  Bundle.main.object(forInfoDictionaryKey: "HOST_NAME") as? String == "127.0.0.1:9",
                  SharedUtils.getAuthToken() == nil, Cache.tinode.myUid == nil,
                  Cache.tinode.store?.myUid == nil, !Cache.tinode.isConnectionAuthenticated,
                  ContactsSynchronizer.default.authStatus != .authorized else {
                throw AssistantFixture.Failure.fixture
            }
            fixture = try AssistantFixture()
            anonymousOwner = Cache.tinode
            priorContactStatus = ContactsSynchronizer.default.authStatus
            priorPermissionsCallback = ContactsSynchronizer.default.permissionsChangedCallback
            ContactsSynchronizer.default.authStatus = .denied
            AssistantFixtureProtocol.requests = []
            try fixture.prepare()
            previousWindow = UIApplication.shared.windows.first { $0.isKeyWindow }
            window = UIWindow(frame: UIScreen.main.bounds)
            window.windowScene = previousWindow?.windowScene
        }
    }
    override func tearDownWithError() throws {
        try AssistantFixture.main {
            defer {
                fixture?.retire(); fixture = nil
                AssistantFixtureProtocol.handler = nil
                window?.endEditing(true); window?.isHidden = true; window?.rootViewController = nil
                currentView = nil; window = nil; previousWindow?.makeKey(); previousWindow = nil
                if let owner = anonymousOwner, owner.myUid == nil { _ = Cache.invalidate(ifCurrent: owner) }
                anonymousOwner = nil
                if let status = priorContactStatus { ContactsSynchronizer.default.authStatus = status }
                ContactsSynchronizer.default.permissionsChangedCallback = priorPermissionsCallback
            }
            if let view = currentView, view.window != nil { try evidence("final", view) }
        }
    }
    private func host(_ controller: UIViewController, accessibility: Bool = false) throws {
        let container = UIViewController()
        container.addChild(controller)
        container.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory:
            accessibility ? .accessibilityExtraExtraExtraLarge : .large), forChild: controller)
        container.view.addSubview(controller.view)
        controller.view.frame = CGRect(x: 16, y: 60, width: 320, height: max(600, window.bounds.height - 140))
        controller.didMove(toParent: container)
        window.overrideUserInterfaceStyle = accessibility ? .dark : .light
        window.rootViewController = container; window.makeKeyAndVisible()
        container.view.layoutIfNeeded(); controller.view.layoutIfNeeded()
        currentView = controller.view
        try AssistantFixture.until { controller.view.window === self.window && controller.transitionCoordinator == nil }
    }
    private func all(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(all) }
    private func button(_ title: String, in view: UIView) throws -> UIButton {
        try XCTUnwrap(all(view).compactMap { $0 as? UIButton }.first { $0.currentTitle == title })
    }
    private func evidence(_ name: String, _ view: UIView) throws {
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let png = XCTAttachment(image: image)
        png.name = "assistant-a-" + name; png.lifetime = .keepAlways; add(png)
        let geometry: [[String: Any]] = all(view).filter { $0 is UILabel || $0 is UIButton || $0 is UITextView }.map {
            let bounds = $0.convert($0.bounds, to: view)
            return ["type": String(describing: type(of: $0)), "id": $0.accessibilityIdentifier ?? "",
                    "x": bounds.minX, "y": bounds.minY, "width": bounds.width, "height": bounds.height,
                    "hidden": $0.isHidden, "alpha": $0.alpha]
        }
        let json = XCTAttachment(data: try JSONSerialization.data(withJSONObject:
            ["scope": "real UIKit assistant A; synthetic HTTP/history only", "geometry": geometry], options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        json.name = "assistant-a-" + name + "-geometry"; json.lifetime = .keepAlways; add(json)
    }

    func testActualFourTabsKeepMessageContactRoutesAndAssistantSelection() throws {
        try AssistantFixture.main {
            let tabs = ClawMainTabBarController.make(storyboard: UIStoryboard(name: "Main", bundle: nil))
            XCTAssertEqual(tabs.viewControllers?.map { $0.tabBarItem.title ?? "" }, ["消息", "通讯录", "助手", "我"])
            let assistantNavigation = try XCTUnwrap(tabs.viewControllers?[2] as? UINavigationController)
            let assistant = try XCTUnwrap(assistantNavigation.viewControllers.first as? ClawAssistantViewController)
            assistant.bind(fixture.scope)
            tabs.selectedIndex = 2
            try host(tabs)
            XCTAssertTrue(tabs.selectedViewController === assistantNavigation)
            XCTAssertTrue(tabs.viewControllers?.first === tabs.messagesNavigationController)
            XCTAssertTrue((tabs.viewControllers?[1] as? UINavigationController)?.viewControllers.first is FindViewController)
            XCTAssertTrue((tabs.viewControllers?.last as? UINavigationController)?.viewControllers.first is AccountSettingsViewController)
            tabs.selectAccount(); XCTAssertEqual(tabs.selectedIndex, 3)
            tabs.selectMessages(); XCTAssertEqual(tabs.selectedIndex, 0)
            tabs.selectedIndex = 2
            try evidence("four-tabs", tabs.view)
            XCTAssertFalse(AssistantFixtureProtocol.requests.contains { $0.httpMethod == "POST" })
        }
    }

    func testFutureCapabilityFieldsNeverEnableGenerationAndDraftReturnsWithinAccount() throws {
        try AssistantFixture.main {
            var capability = AssistantFixture.capabilities
            capability["generation"] = ["available": true]
            capability["stream"] = ["available": true]
            capability["run_protocol"] = "future"
            capability["message_states"] = ["completed"]
            AssistantFixtureProtocol.handler = { $0.reply(capability) }
            fixture.scope.history.loadCapabilities()
            try AssistantFixture.until { !self.fixture.scope.history.capabilityLoading }
            let home = ClawAssistantViewController(session: fixture.scope)
            let navigation = UINavigationController(rootViewController: home)
            try host(navigation)
            try button("开始提问", in: home.view).sendActions(for: .touchUpInside)
            try AssistantFixture.until { navigation.topViewController is ClawAssistantConversationViewController &&
                navigation.transitionCoordinator == nil }
            let detail = try XCTUnwrap(navigation.topViewController as? ClawAssistantConversationViewController)
            let input = try XCTUnwrap(all(detail.view).compactMap { $0 as? UITextView }.first)
            XCTAssertTrue(input.becomeFirstResponder())
            input.text = "未发送的本账号问题"
            detail.textViewDidChange(input)
            XCTAssertEqual(fixture.scope.draft, "未发送的本账号问题")
            XCTAssertFalse(try button("发送", in: detail.view).isEnabled)
            XCTAssertTrue(all(detail.view).contains { ($0 as? UILabel)?.text == "你的问题已保留。请更新应用后再发送。" })
            detail.view.endEditing(true)
            try evidence("draft-unavailable", detail.view)
            navigation.popViewController(animated: false)
            try AssistantFixture.until { navigation.topViewController === home && detail.parent == nil }
            try button("开始提问", in: home.view).sendActions(for: .touchUpInside)
            try AssistantFixture.until { navigation.topViewController is ClawAssistantConversationViewController &&
                navigation.transitionCoordinator == nil }
            let resumed = try XCTUnwrap(navigation.topViewController)
            XCTAssertEqual(all(resumed.view).compactMap { $0 as? UITextView }.first?.text, "未发送的本账号问题")
            XCTAssertFalse(AssistantFixtureProtocol.requests.contains { $0.httpMethod == "POST" })
        }
    }

    func testRealTitleTimeRowsAndPartialHistoryGrowAt320AccessibilityWithoutFakePreview() throws {
        try AssistantFixture.main {
            AssistantFixtureProtocol.handler = {
                if $0.request.url?.path.hasSuffix("/messages") == true {
                    $0.reply(AssistantFixture.messages([AssistantFixture.message(state: "interrupted",
                        text: "这是一段受控的合成历史正文，并非模型实时回答。")]))
                } else {
                    $0.reply(AssistantFixture.list([AssistantFixture.conversation(
                        title: "这是一段用于检验大字号自然换行的合成标题")]))
                }
            }
            let history = ClawAssistantHistoryViewController(session: fixture.scope)
            let navigation = UINavigationController(rootViewController: history)
            try host(navigation, accessibility: true)
            try AssistantFixture.until { self.fixture.scope.history.hasListSnapshot && !self.fixture.scope.history.listLoading }
            let table = try XCTUnwrap(all(history.view).compactMap { $0 as? UITableView }.first)
            table.layoutIfNeeded()
            let index = IndexPath(row: 0, section: 0)
            table.scrollToRow(at: index, at: .middle, animated: false); table.layoutIfNeeded()
            let cell = try XCTUnwrap(table.cellForRow(at: index))
            XCTAssertGreaterThan(cell.bounds.height, 76)
            for label in all(cell).compactMap({ $0 as? UILabel }) where label.accessibilityIdentifier?.hasPrefix("claw.ai.history.") == true {
                XCTAssertGreaterThan(label.bounds.width, 0)
                let required = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertLessThanOrEqual(required.height, label.bounds.height + 1)
            }
            XCTAssertEqual(all(cell).compactMap { $0 as? UILabel }.filter { !($0.text ?? "").isEmpty }.count, 3)
            try evidence("history-ax", history.view)
            history.tableView(table, didSelectRowAt: index)
            try AssistantFixture.until { navigation.topViewController is ClawAssistantConversationViewController &&
                navigation.transitionCoordinator == nil && self.fixture.scope.history.details[AssistantFixture.first] != nil }
            let detail = try XCTUnwrap(navigation.topViewController)
            XCTAssertTrue(all(detail.view).contains { ($0 as? UILabel)?.text == "回答已中断" })
            XCTAssertFalse(all(detail.view).contains { ($0 as? UILabel)?.text == "正在回答" })
            try evidence("history-detail-ax", detail.view)
        }
    }

    func testConfirmationCancellationAndUnknownDeleteUseActualConsumersWithoutAutoRetry() throws {
        try AssistantFixture.main {
            let data = try JSONSerialization.data(withJSONObject: AssistantFixture.conversation())
            let conversation = try JSONDecoder().decode(ClawAssistantConversation.self, from: data)
            AssistantFixtureProtocol.handler = {
                if $0.request.httpMethod == "DELETE" { $0.fail() }
                else if $0.request.url?.path.hasSuffix("/messages") == true { $0.reply(AssistantFixture.messages([])) }
                else { $0.reply(AssistantFixture.list([AssistantFixture.conversation()])) }
            }
            let detail = ClawAssistantConversationViewController(session: fixture.scope, conversation: conversation)
            let navigation = UINavigationController(rootViewController: detail)
            try host(navigation)
            try button("删除对话", in: detail.view).sendActions(for: .touchUpInside)
            try AssistantFixture.until { detail.presentedViewController is UIAlertController }
            let alert = try XCTUnwrap(detail.presentedViewController as? UIAlertController)
            XCTAssertEqual(alert.title, "删除这段对话？")
            XCTAssertEqual(alert.preferredAction?.style, .cancel)
            XCTAssertEqual(alert.actions.map { $0.style }, [.cancel, .destructive])
            XCTAssertFalse(AssistantFixtureProtocol.requests.contains { $0.httpMethod == "DELETE" })
            alert.dismiss(animated: false)
            try AssistantFixture.until { detail.presentedViewController == nil }
            // State-machine submit is tested directly; invoking private UIAlertAction
            // handlers through KVC would not be an actual user confirmation test.
            fixture.scope.history.deleteConversation(AssistantFixture.first)
            try AssistantFixture.until { self.fixture.scope.history.deletions[AssistantFixture.first] == .unknown }
            XCTAssertTrue(all(detail.view).contains { ($0 as? UILabel)?.text?.hasPrefix("删除结果暂未确认") == true })
            try button("重新核对", in: detail.view).sendActions(for: .touchUpInside)
            try AssistantFixture.until { !self.fixture.scope.history.listLoading }
            XCTAssertEqual(fixture.scope.history.deletions[AssistantFixture.first], .unknown)
            XCTAssertEqual(AssistantFixtureProtocol.requests.filter { $0.httpMethod == "DELETE" }.count, 1)
            try evidence("delete-unknown", detail.view)
        }
    }

    func testRetiringVisibleScopeImmediatelyHidesDraftAndDoesNotLogoutSDKFor401() throws {
        try AssistantFixture.main {
            fixture.scope.history.setDraft("仅原账号可见的合成草稿")
            let detail = ClawAssistantConversationViewController(session: fixture.scope)
            let navigation = UINavigationController(rootViewController: detail)
            try host(navigation)
            XCTAssertEqual(all(detail.view).compactMap { $0 as? UITextView }.first?.text, "仅原账号可见的合成草稿")
            AssistantFixtureProtocol.handler = { $0.reply(AssistantFixture.error("authentication_required"), status: 401) }
            fixture.scope.history.loadCapabilities()
            try AssistantFixture.until { self.fixture.scope.isBlocked }
            XCTAssertEqual(all(detail.view).compactMap { $0 as? UITextView }.first?.text, "")
            XCTAssertFalse(try button("前往账号设置", in: detail.view).isHidden)
            XCTAssertEqual(fixture.owner.store?.myUid, "usrSyntheticAssistantA")
            XCTAssertTrue(fixture.owner.isSessionActive)
            try evidence("authorization-hidden", detail.view)
            fixture.scope.markRetired(clearAccount: true); fixture.scope.finishRetirement()
            XCTAssertEqual(fixture.scope.account.draft, "")
        }
    }

    func testRealHistoryRowShowsExplicitDeletionRejectionWithoutRemovingConversation() throws {
        try AssistantFixture.main {
            var status = 403
            AssistantFixtureProtocol.handler = {
                if $0.request.httpMethod == "DELETE" {
                    $0.reply(AssistantFixture.error(status == 403 ? "permission_denied" : "not_found"), status: status)
                } else { $0.reply(AssistantFixture.list([AssistantFixture.conversation()])) }
            }
            let history = ClawAssistantHistoryViewController(session: fixture.scope)
            let navigation = UINavigationController(rootViewController: history)
            try host(navigation, accessibility: true)
            let model = fixture.scope.history
            try AssistantFixture.until { model.hasListSnapshot && !model.listLoading }
            let table = try XCTUnwrap(all(history.view).compactMap { $0 as? UITableView }.first)
            let index = IndexPath(row: 0, section: 0)
            for code in [403, 404] {
                status = code
                // Actual transport -> History -> observing original UIKit row. The
                // separate confirmation test covers alert presentation/cancel semantics.
                model.deleteConversation(AssistantFixture.first)
                try AssistantFixture.until { model.deletions[AssistantFixture.first] != .pending }
                let error = ClawAssistantError.server(code, code == 403 ? "permission_denied" : "not_found")
                XCTAssertEqual(model.deletions[AssistantFixture.first], .rejected(error))
                XCTAssertEqual(model.conversations.map { $0.conversation_id }, [AssistantFixture.first])
                table.layoutIfNeeded(); table.scrollToRow(at: index, at: .middle, animated: false)
                table.layoutIfNeeded()
                let cell = try XCTUnwrap(table.cellForRow(at: index))
                let message = try XCTUnwrap(all(cell).compactMap { $0 as? UILabel }.first {
                    $0.text == "删除未完成。" + error.message
                })
                XCTAssertFalse(message.isHidden)
                XCTAssertNotNil(message.window)
                let required = message.sizeThatFits(CGSize(width: message.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertGreaterThan(message.bounds.width, 0)
                XCTAssertLessThanOrEqual(required.height, message.bounds.height + 1)
                XCTAssertTrue(cell.accessibilityLabel?.contains(error.message) == true)
                XCTAssertFalse(cell.accessibilityLabel?.contains("已删除") == true)
                try evidence("history-delete-rejected-" + String(code), history.view)
            }
            XCTAssertEqual(AssistantFixtureProtocol.requests.filter { $0.httpMethod == "DELETE" }.count, 2)
            XCTAssertFalse(AssistantFixtureProtocol.requests.contains { $0.httpMethod == "POST" })
        }
    }
}
