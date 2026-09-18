// Copyright (c) 2026 CLAW OS contributors.
// Original nib cells and real Find/account view consumers in the existing App host.
// Synthetic in-memory data only; no login, permission prompt, query, publish or server ACK.
import XCTest
import UIKit
import CoreText
import Contacts
import TinodeSDK
import TinodiosDB
@testable import Tinodios

final class CoreListLayoutTests: XCTestCase {
    private enum Failure: Error { case initialState, layout }
    private var window: UIWindow!
    private var previousWindow: UIWindow?
    private var priorContactStatus: CNAuthorizationStatus!
    private var priorPermissionsCallback: ((CNAuthorizationStatus) -> Void)?
    private var owner: Tinode!
    private var capturedView: UIView?

    private func main<T>(_ work: () throws -> T) rethrows -> T {
        if Thread.isMainThread { return try work() }
        return try DispatchQueue.main.sync(execute: work)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try main {
            guard Bundle.main.bundleIdentifier == "app.veilping.clawoschat",
                  Bundle.main.object(forInfoDictionaryKey: "HOST_NAME") as? String == "127.0.0.1:9",
                  SharedUtils.getAuthToken() == nil,
                  Cache.tinode.myUid == nil, Cache.tinode.store?.myUid == nil,
                  !Cache.tinode.isConnectionAuthenticated, Cache.tinode.getMeTopic() == nil,
                  ContactsSynchronizer.default.authStatus != .authorized else {
                XCTFail("Unexpected host/account state"); throw Failure.initialState
            }
            owner = Cache.tinode
            previousWindow = UIApplication.shared.windows.first(where: { $0.isKeyWindow })
            priorContactStatus = ContactsSynchronizer.default.authStatus
            priorPermissionsCallback = ContactsSynchronizer.default.permissionsChangedCallback
            // Real Find setup retains its system synchronizer. Deny this test dependency
            // before loading; no OS permission or contacts enumeration is requested.
            ContactsSynchronizer.default.authStatus = .denied
            window = UIWindow(frame: UIScreen.main.bounds)
            if let scene = previousWindow?.windowScene { window.windowScene = scene }
        }
    }

    override func tearDownWithError() throws {
        try main {
            defer {
                window?.endEditing(true)
                window?.isHidden = true
                window?.rootViewController = nil
                capturedView = nil; window = nil
                owner?.stopTrackingTopic(topicName: Tinode.kTopicMe)
                // Cancels the anonymous fixture's periodic contacts timer. Never clears
                // an unexpected replacement owner or a signed-in account.
                if let owner = owner, owner.myUid == nil { _ = Cache.invalidate(ifCurrent: owner) }
                owner = nil
                if let status = priorContactStatus { ContactsSynchronizer.default.authStatus = status }
                ContactsSynchronizer.default.permissionsChangedCallback = priorPermissionsCallback
                previousWindow?.makeKey(); previousWindow = nil
            }
            if let view = capturedView, view.window != nil { try evidence("final", view: view) }
        }
    }

    private func host(_ controller: UIViewController, category: UIContentSizeCategory = .large,
                      style: UIUserInterfaceStyle = .light) throws {
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: controller)
        root.addChild(navigation)
        root.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: category), forChild: navigation)
        root.view.addSubview(navigation.view)
        navigation.view.frame = CGRect(x: 16, y: 60, width: 320,
                                       height: max(600, window.bounds.height - 140))
        navigation.didMove(toParent: root)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        navigation.view.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        capturedView = navigation.view
        try until {
            navigation.view.layoutIfNeeded()
            return controller.view.window === self.window &&
                navigation.topViewController === controller &&
                navigation.transitionCoordinator == nil &&
                navigation.navigationBar.bounds.height > 0
        }
    }

    private func until(_ condition: () -> Bool) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !condition() {
            if ProcessInfo.processInfo.systemUptime >= deadline {
                XCTFail("Native layout did not settle within 3 seconds"); throw Failure.layout
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    private func navigationAction(_ controller: UIViewController, title: String, name: String) throws {
        let bar = try XCTUnwrap(controller.navigationController?.navigationBar)
        try until { bar.layoutIfNeeded(); return controller.navigationItem.rightBarButtonItem?.customView?.window != nil }
        let action = try XCTUnwrap(controller.navigationItem.rightBarButtonItem?.customView as? UIButton)
        let label = try XCTUnwrap(action.titleLabel)
        XCTAssertEqual(bar.bounds.height, 44, accuracy: 1)
        XCTAssertEqual(action.bounds.height, 44, accuracy: 1)
        XCTAssertGreaterThanOrEqual(action.bounds.width, 44)
        XCTAssertEqual(action.currentTitle, title)
        XCTAssertEqual(label.numberOfLines, 1)
        XCTAssertFalse(action.isHidden)
        XCTAssertTrue(action.isEnabled)
        contained(action, in: bar); contained(label, in: action); readable(label)
        let textWidth = (title as NSString).size(withAttributes: [.font: label.font!]).width
        XCTAssertGreaterThanOrEqual(label.bounds.width + 1, textWidth)
        XCTAssertNotNil(action.window)
        try evidence(name, view: try XCTUnwrap(controller.navigationController?.view))
    }

    private func nib<T: UITableViewCell>(_ name: String, as type: T.Type) throws -> T {
        try XCTUnwrap(UINib(nibName: name, bundle: Bundle.main).instantiate(withOwner: nil, options: nil)
            .compactMap { $0 as? T }.first)
    }

    private func fit(_ cell: UITableViewCell, y: CGFloat = 0, in view: UIView) {
        view.addSubview(cell)
        cell.frame = CGRect(x: 0, y: y, width: 320, height: 94)
        cell.contentView.bounds.size.width = 320
        cell.setNeedsLayout(); cell.layoutIfNeeded()
        let measured = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        cell.frame.size.height = ceil(max(84, measured))
        cell.setNeedsLayout(); cell.layoutIfNeeded()
    }

    private func contained(_ child: UIView, in parent: UIView, file: StaticString = #filePath, line: UInt = #line) {
        let rect = child.convert(child.bounds, to: parent)
        XCTAssertGreaterThanOrEqual(rect.minX, -1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minY, -1, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxX, parent.bounds.width + 1, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxY, parent.bounds.height + 1, file: file, line: line)
    }

    private func readable(_ label: UILabel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(label.bounds.width, 0, file: file, line: line)
        let required = label.sizeThatFits(CGSize(width: label.bounds.width, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThanOrEqual(label.bounds.height + 1, required, file: file, line: line)
    }

    private func unreadBadgeFits(_ cell: ChatListViewCell, text: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let label = cell.unreadCount!
        XCTAssertEqual(label.text, text, file: file, line: line)
        XCTAssertFalse(label.isHidden, file: file, line: line)
        XCTAssertTrue(label.adjustsFontForContentSizeCategory, file: file, line: line)
        XCTAssertFalse(label.adjustsFontSizeToFitWidth, file: file, line: line)
        XCTAssertEqual(label.numberOfLines, 1, file: file, line: line)
        let shaped = CTLineCreateWithAttributedString(NSAttributedString(string: text,
            attributes: [.font: label.font!]) as CFAttributedString)
        let glyphWidth = CGFloat(CTLineGetTypographicBounds(shaped, nil, nil, nil))
        XCTAssertGreaterThan(glyphWidth, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(label.bounds.width + 1, ceil(glyphWidth) + 12, file: file, line: line)
        XCTAssertGreaterThanOrEqual(label.bounds.width + 1, label.bounds.height, file: file, line: line)
        XCTAssertEqual(cell.unreadCountWidth.constant, label.bounds.width, accuracy: 1, file: file, line: line)
        readable(label, file: file, line: line)
        contained(label, in: cell, file: file, line: line)
    }

    private func allViews(_ root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap { allViews($0) }
    }

    private func topic() throws -> DefaultComTopic {
        let topic = try XCTUnwrap(Tinode.newTopic(withTinode: nil, forTopic: "grp-core-fixture") as? DefaultComTopic)
        topic.pub = TheCard(fn: "合成会话名称")
        topic.seq = 12; topic.read = 2
        let message = StoredMessage()
        message.seq = 12; message.from = "usr-synthetic-other"
        message.ts = Date(timeIntervalSince1970: 1_700_000_000)
        message.content = Drafty(content: "合成的真实 Drafty 预览")
        topic.latestMessage = message
        return topic
    }

    func testConversationNibOptInKeepsDataAndRestoresLegacyReuse() throws {
        try main {
            let controller = UIViewController(); try host(controller)
            let cell = try nib("ChatListViewCell", as: ChatListViewCell.self)
            cell.fillFromTopic(topic: try topic())
            fit(cell, in: controller.view)
            XCTAssertFalse(cell.usesContinuousLayout)
            XCTAssertEqual(cell.icon.convert(cell.icon.bounds, to: cell).minX, 32, accuracy: 1)
            cell.usesContinuousLayout = true
            fit(cell, in: controller.view)
            XCTAssertEqual(cell.icon.convert(cell.icon.bounds, to: cell).minX, 16, accuracy: 1)
            XCTAssertEqual(cell.title.text, "合成会话名称")
            XCTAssertTrue((cell.subtitle.attributedText?.string ?? "").contains("真实 Drafty"))
            XCTAssertEqual(cell.unreadCount.text, "9+")
            XCTAssertFalse(cell.unreadCount.isHidden)
            unreadBadgeFits(cell, text: "9+")
            XCTAssertFalse(try XCTUnwrap(allViews(cell).first { $0.accessibilityIdentifier == "claw.conversation.divider" }).isHidden)
            contained(cell.title, in: cell); contained(cell.unreadCount, in: cell)
            try evidence("conversation-continuous", view: controller.view)
            cell.prepareForReuse()
            XCTAssertFalse(cell.usesContinuousLayout)
            fit(cell, in: controller.view)
            XCTAssertEqual(cell.icon.convert(cell.icon.bounds, to: cell).minX, 32, accuracy: 1)
            XCTAssertTrue(cell.unreadCount.isHidden)
            XCTAssertNil(cell.title.text)
            for category: UIContentSizeCategory in [.large, .accessibilityExtraExtraExtraLarge] {
                let chats = try XCTUnwrap(UIStoryboard(name: "Main", bundle: nil)
                    .instantiateViewController(withIdentifier: "ChatListViewController") as? ChatListViewController)
                chats.loadViewIfNeeded()
                chats.interactor = nil // Original visual consumers, no subscribe/login side effects.
                try host(chats, category: category)
                chats.displayChats([try topic()], archivedTopics: nil)
                let search = try XCTUnwrap(allViews(chats.tableView.tableHeaderView!).first {
                    $0.accessibilityIdentifier == "claw.chats.search"
                } as? UITextField)
                XCTAssertEqual(search.placeholder, "搜索会话")
                XCTAssertFalse(allViews(chats.tableView.tableHeaderView!).contains {
                    ($0 as? UILabel)?.text == "活跃联系人"
                })
                search.text = "合成"; search.sendActions(for: .editingChanged)
                XCTAssertEqual(chats.topics.count, 1)
                search.text = "无匹配"; search.sendActions(for: .editingChanged)
                XCTAssertTrue(chats.topics.isEmpty)
                try navigationAction(chats, title: "发起聊天",
                                     name: category.isAccessibilityCategory ? "messages-nav-ax" : "messages-nav")
            }
        }
    }

    func testContactNibOptInSelectionAndDefaultConsumerRemainDistinct() throws {
        try main {
            let controller = UIViewController(); try host(controller)
            let cell = try nib("ContactViewCell", as: ContactViewCell.self)
            let spy = ContactSelectionSpy()
            cell.title.text = "合成联系人"; cell.subtitle.text = "CLAW号：claw_fixture"
            fit(cell, in: controller.view)
            XCTAssertEqual(cell.avatar.frame.minX, 32, accuracy: 1)
            cell.usesContinuousLayout = true; cell.delegate = spy
            fit(cell, in: controller.view)
            XCTAssertEqual(cell.avatar.frame.minX, 16, accuracy: 1)
            XCTAssertEqual(cell.backgroundView?.frame, cell.bounds)
            cell.setSelected(true, animated: false)
            XCTAssertTrue(spy.selectedCell === cell)
            contained(cell.title, in: cell); readable(cell.subtitle)
            try evidence("contact-continuous", view: controller.view)
            cell.prepareForReuse()
            fit(cell, in: controller.view)
            XCTAssertFalse(cell.usesContinuousLayout)
            XCTAssertEqual(cell.avatar.frame.minX, 32, accuracy: 1)
            XCTAssertEqual(cell.backgroundView?.frame.minX, 20)
        }
    }

    func testOriginalNibsAt320GrowForAccessibilityInBothAppearances() throws {
        try main {
            for style: UIUserInterfaceStyle in [.light, .dark] {
                let controller = UIViewController()
                try host(controller, category: .accessibilityExtraExtraExtraLarge, style: style)
                let traits = controller.traitCollection
                var result: Result<(ChatListViewCell, ContactViewCell), Error>!
                traits.performAsCurrent {
                    result = Result {
                        (try nib("ChatListViewCell", as: ChatListViewCell.self),
                         try nib("ContactViewCell", as: ContactViewCell.self))
                    }
                }
                let (chat, contact) = try result.get()
                chat.usesContinuousLayout = true
                chat.fillFromTopic(topic: try topic())
                chat.title.text = "合成大字号会话名称"
                contact.usesContinuousLayout = true
                contact.title.text = "合成大字号联系人"
                contact.subtitle.text = "CLAW号：claw_accessibility"
                fit(chat, in: controller.view)
                fit(contact, y: chat.frame.maxY + 8, in: controller.view)
                XCTAssertGreaterThan(chat.bounds.height, 84)
                XCTAssertGreaterThan(contact.bounds.height, 84)
                XCTAssertGreaterThan(chat.title.font.pointSize, 16)
                XCTAssertGreaterThan(contact.title.font.pointSize, 16)
                for label in [chat.title!, chat.subtitle!, contact.title!, contact.subtitle!] {
                    readable(label)
                }
                contained(chat.title, in: chat); contained(chat.unreadCount, in: chat)
                contained(contact.title, in: contact); contained(contact.subtitle, in: contact)
                XCTAssertGreaterThan(chat.unreadCount.font.pointSize, 12)
                unreadBadgeFits(chat, text: "9+")
                XCTAssertEqual(chat.traitCollection.userInterfaceStyle, style)
                XCTAssertEqual(contact.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
                try evidence(style == .dark ? "rows-ax-dark" : "rows-ax-light", view: controller.view)
                let unreadTopic = try topic()
                unreadTopic.read = 7 // Single digit at the same current AX font.
                chat.fillFromTopic(topic: unreadTopic)
                fit(chat, in: controller.view)
                unreadBadgeFits(chat, text: "5")
                try evidence(style == .dark ? "badge-single-ax-dark" : "badge-single-ax-light", view: controller.view)
                unreadTopic.read = unreadTopic.seq
                chat.fillFromTopic(topic: unreadTopic)
                fit(chat, in: controller.view)
                XCTAssertTrue(chat.unreadCount.isHidden)
                // Topic.read is monotonic; reuse the cell with a fresh unread topic.
                let restoredTopic = try topic()
                XCTAssertEqual(restoredTopic.read, 2)
                XCTAssertEqual(unreadTopic.read, unreadTopic.seq)
                chat.fillFromTopic(topic: restoredTopic)
                let enlargedFontSize = chat.unreadCount.font.pointSize
                let standard = UIViewController(); try host(standard, style: style)
                fit(chat, in: standard.view)
                try until {
                    chat.setNeedsLayout(); chat.layoutIfNeeded()
                    return chat.traitCollection.preferredContentSizeCategory == .large &&
                        chat.unreadCount.font.pointSize < enlargedFontSize
                }
                unreadBadgeFits(chat, text: "9+")
                let enlarged = UIViewController()
                try host(enlarged, category: .accessibilityExtraExtraExtraLarge, style: style)
                fit(chat, in: enlarged.view)
                try until {
                    chat.setNeedsLayout(); chat.layoutIfNeeded()
                    return chat.unreadCount.font.pointSize > 12
                }
                unreadBadgeFits(chat, text: "9+")
                try evidence(style == .dark ? "badge-regrown-ax-dark" : "badge-regrown-ax-light", view: enlarged.view)
            }
        }
    }

    func testRealFindConsumesContactsAndEmptyStateWithoutDirectoryCalls() throws {
        try main {
            for category: UIContentSizeCategory in [.large, .accessibilityExtraExtraExtraLarge] {
                let controller = try XCTUnwrap(UIStoryboard(name: "Main", bundle: nil)
                    .instantiateViewController(withIdentifier: "Find") as? FindViewController)
                controller.loadViewIfNeeded()
                let port = NoNetworkFindPort()
                controller.interactor = port
                try host(controller, category: category)
                let contacts = [
                    ContactHolder(pub: TheCard(fn: "合成联系人"), uniqueId: "usrfixture1", accountName: "claw_fixture"),
                    ContactHolder(pub: nil, uniqueId: "usrfixture2", accountName: nil)
                ]
                controller.displayLocalContacts(contacts: contacts)
                controller.tableView.layoutIfNeeded()
                let index = IndexPath(row: 0, section: FindViewController.kLocalContactsSection)
                let cell = try XCTUnwrap(controller.tableView(controller.tableView, cellForRowAt: index) as? ContactViewCell)
                XCTAssertTrue(cell.usesContinuousLayout)
                XCTAssertEqual(cell.title.text, "合成联系人")
                XCTAssertEqual(cell.subtitle.text, "CLAW号：claw_fixture")
                let missing = try XCTUnwrap(controller.tableView(controller.tableView,
                    cellForRowAt: IndexPath(row: 1, section: FindViewController.kLocalContactsSection)) as? ContactViewCell)
                XCTAssertFalse((missing.title.text ?? "").contains("usrfixture"))
                XCTAssertEqual(missing.subtitle.text, "暂未设置 CLAW号")
                XCTAssertEqual(controller.navigationItem.title, "通讯录")
                let add = try XCTUnwrap(controller.navigationItem.rightBarButtonItem?.customView as? UIButton)
                XCTAssertEqual(add.currentTitle, "添加联系人")
                XCTAssertTrue(add.allTargets.count > 0)
                try navigationAction(controller, title: "添加联系人",
                                     name: category.isAccessibilityCategory ? "contacts-nav-ax" : "contacts-nav")
                XCTAssertTrue(allViews(controller.tableView.tableHeaderView!).contains {
                    ($0 as? UIButton)?.currentTitle == "发起群聊"
                })
                XCTAssertEqual(port.saveCalls, 0)
                try evidence("contacts-data", view: controller.view)
                controller.displayLocalContacts(contacts: [])
                controller.tableView.layoutIfNeeded()
                let empty = controller.tableView(controller.tableView, cellForRowAt: index)
                XCTAssertFalse(empty is ContactViewCell)
                try evidence("contacts-empty", view: controller.view)
            }
        }
    }

    func testRealAccountMissingThenPublicAliasUsesOriginalDataConsumer() throws {
        try main {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let missing = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "Account Settings")
                as? AccountSettingsViewController)
            try host(missing)
            XCTAssertTrue(allViews(missing.view).contains { ($0 as? UILabel)?.text == "正在同步账号" })
            try evidence("account-unavailable", view: missing.view)
            let me = DefaultMeTopic(tinode: owner)
            me.pub = TheCard(fn: "合成个人昵称")
            me.tags = ["alias:claw_fixture", "basic:legacyfixture"]
            let loaded = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "Account Settings")
                as? AccountSettingsViewController)
            try host(loaded)
            let value = try XCTUnwrap(allViews(loaded.view).first {
                $0.accessibilityIdentifier == "claw.settings.account.public-id"
            } as? UILabel)
            XCTAssertEqual(value.text, "claw_fixture")
            XCTAssertTrue(allViews(loaded.view).contains { ($0 as? UILabel)?.text == "合成个人昵称" })
            let appearance = try XCTUnwrap(allViews(loaded.view).first {
                $0.accessibilityIdentifier == "claw.settings.account.appearance-readonly"
            })
            XCTAssertFalse(appearance is UIControl)
            XCTAssertTrue(allViews(appearance).contains { ($0 as? UILabel)?.text == "跟随系统" })
            XCTAssertFalse(allViews(loaded.view).contains { ($0 as? UILabel)?.text == "帮助与客服" })
            try evidence("account-public-alias", view: loaded.view)
        }
    }

    func testRealAccountAt320AccessibilityGrowsWithoutClippingOrInventedEntries() throws {
        try main {
            let me = DefaultMeTopic(tinode: owner)
            me.pub = TheCard(fn: "合成很长的个人昵称")
            me.tags = ["alias:claw_fixture_long"]
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let standard = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "Account Settings")
                as? AccountSettingsViewController)
            try host(standard, style: .dark)
            let standardHeight = try XCTUnwrap(standard.tableView.tableHeaderView).bounds.height
            XCTAssertGreaterThan(standardHeight, 0)
            try evidence("account-standard-dark", view: standard.view)
            let controller = try XCTUnwrap(storyboard.instantiateViewController(withIdentifier: "Account Settings")
                as? AccountSettingsViewController)
            try host(controller, category: .accessibilityExtraExtraExtraLarge, style: .dark)
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            let header = try XCTUnwrap(controller.tableView.tableHeaderView)
            let card = try XCTUnwrap(allViews(header).first { $0.accessibilityIdentifier == "claw.settings.account.profile-card" })
            contained(card, in: header)
            for label in allViews(card).compactMap({ $0 as? UILabel }) where !(label.text ?? "").isEmpty {
                readable(label); contained(label, in: card)
            }
            let copy = try XCTUnwrap(allViews(card).first {
                $0.accessibilityIdentifier == "claw.settings.account.copy-public-id"
            } as? UIButton)
            XCTAssertGreaterThanOrEqual(copy.bounds.height, 48)
            XCTAssertGreaterThanOrEqual(copy.bounds.width, 48)
            let profile = try XCTUnwrap(allViews(card).first {
                $0.accessibilityIdentifier == "claw.settings.account.profile"
            } as? UIButton)
            XCTAssertGreaterThanOrEqual(profile.bounds.height, 44)
            XCTAssertEqual(controller.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
            XCTAssertGreaterThan(header.bounds.height, standardHeight)
            XCTAssertTrue(controller.tableView.isScrollEnabled)
            let table = try XCTUnwrap(controller.tableView)
            XCTAssertGreaterThanOrEqual(table.contentSize.height + 1, header.frame.maxY)
            try evidence("account-ax-dark", view: controller.view)
            let lastAction = try XCTUnwrap(allViews(header).compactMap { $0 as? UIButton }
                .first { $0.currentTitle == "退出登录" })
            let topOffset = -table.adjustedContentInset.top
            let bottomOffset = max(topOffset, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
            if bottomOffset > topOffset {
                table.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
                try until { table.layoutIfNeeded(); return abs(table.contentOffset.y - bottomOffset) <= 1 }
            }
            let viewport = table.bounds.inset(by: table.adjustedContentInset)
            let lastFrame = lastAction.convert(lastAction.bounds, to: table)
            XCTAssertGreaterThanOrEqual(lastFrame.minY, viewport.minY - 1)
            XCTAssertLessThanOrEqual(lastFrame.maxY, viewport.maxY + 1)
            XCTAssertGreaterThanOrEqual(lastFrame.minX, viewport.minX - 1)
            XCTAssertLessThanOrEqual(lastFrame.maxX, viewport.maxX + 1)
            XCTAssertFalse(lastAction.isHidden)
            XCTAssertGreaterThan(lastAction.alpha, 0)
            XCTAssertNotNil(lastAction.window)
            readable(try XCTUnwrap(lastAction.titleLabel))
            try evidence("account-ax-end-reachable", view: controller.view)
        }
    }

    private func evidence(_ name: String, view: UIView) throws {
        view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image {
            _ in view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let png = XCTAttachment(image: image); png.name = "core-list-\(name)"
        png.lifetime = .keepAlways; add(png)
        let rows: [[String: Any]] = allViews(view).filter {
            $0 is UILabel || $0 is UIButton || $0 is UITableViewCell
        }.map {
            let r = $0.convert($0.bounds, to: view)
            let badge = $0.accessibilityIdentifier == "unreadCount" ? $0 as? UILabel : nil
            let badgeGlyphWidth = badge.map { label in
                CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(
                    string: label.text ?? "", attributes: [.font: label.font!]) as CFAttributedString), nil, nil, nil)
            } ?? 0
            return ["kind": String(describing: type(of: $0)), "identifier": $0.accessibilityIdentifier ?? "",
                    "x": r.minX, "y": r.minY, "width": r.width, "height": r.height,
                    "hidden": $0.isHidden, "alpha": $0.alpha,
                    "font": ($0 as? UILabel)?.font.pointSize ?? 0,
                    "unreadGlyphWidth": badgeGlyphWidth]
        }
        let data: [String: Any] = ["scope": "original UIKit/nibs with synthetic in-memory data; no authenticated journey",
            "width": view.bounds.width, "height": view.bounds.height,
            "appearance": view.traitCollection.userInterfaceStyle.rawValue,
            "contentSize": view.traitCollection.preferredContentSizeCategory.rawValue, "views": rows]
        let json = XCTAttachment(data: try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]),
                                 uniformTypeIdentifier: "public.json")
        json.name = "core-list-\(name)-geometry"; json.lifetime = .keepAlways; add(json)
    }
}

private final class ContactSelectionSpy: ContactViewCellDelegate {
    weak var selectedCell: UITableViewCell?
    func selected(from cell: UITableViewCell) { selectedCell = cell }
}

private final class NoNetworkFindPort: FindBusinessLogic {
    var presenter: FindPresentationLogic?
    var fndTopic: DefaultFndTopic? { nil }
    private(set) var saveCalls = 0
    func loadAndPresentContacts(searchQuery: String?) {}
    func invalidateDirectorySearch(input: String?) {}
    func canUse(_ remoteContact: RemoteContactHolder, input: String?) -> Bool { false }
    func updateAndPresentRemoteContacts() {}
    func saveRemoteTopic(from remoteContact: RemoteContactHolder, completion: @escaping (Error?) -> Void) {
        saveCalls += 1
        XCTFail("Layout fixture must not save a directory result")
    }
    func setup() {}
    func cleanup() {}
    func attachToFndTopic() {}
}
