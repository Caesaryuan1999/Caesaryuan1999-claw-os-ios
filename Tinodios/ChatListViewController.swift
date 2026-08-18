//
//  ChatListViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

protocol ChatListDisplayLogic: AnyObject {
    func displayChats(_ topics: [DefaultComTopic], archivedTopics: [DefaultComTopic]?)
    func displayLoginView()
    func updateChat(_ name: String)
    func deleteChat(_ name: String)
}

class ChatListViewController: UITableViewController, ChatListDisplayLogic {

    private struct ActiveContactItem {
        let topicName: String
        let pub: TheCard?
        let displayName: String
        let accountName: String?
        let touched: Date?
        let inCall: Bool
        let online: Bool
        let deleted: Bool
    }

    private static let kFooterHeight: CGFloat = 30

    @IBOutlet var chatListTableView: UITableView!

    var interactor: ChatListBusinessLogic?
    var topics: [DefaultComTopic] = []
    private var allTopics: [DefaultComTopic] = []
    var archivedTopics: [DefaultComTopic]?
    var numArchivedTopics: Int { return archivedTopics?.count ?? 0 }

    // Index of contacts: name => position in topics
    var rowIndex: [String: Int] = [:]
    var router: ChatListRoutingLogic?
    // Archived chats footer
    var archivedChatsFooter: UIView?
    private weak var searchField: UITextField?
    private var headerWidth: CGFloat = 0
    private var activeContactItems: [ActiveContactItem] = []

    private func setup() {
        let viewController = self
        let interactor = ChatListInteractor()
        let presenter = ChatListPresenter()
        let router = ChatListRouter()

        viewController.interactor = interactor
        viewController.router = router
        interactor.presenter = presenter
        interactor.router = router
        presenter.viewController = viewController
        router.viewController = viewController

        self.chatListTableView.register(UINib(nibName: "ChatListViewCell", bundle: nil), forCellReuseIdentifier: "ChatListViewCell")
        self.chatListTableView.backgroundColor = ClawTheme.surface
        self.chatListTableView.separatorColor = ClawTheme.border
        self.chatListTableView.separatorInset = UIEdgeInsets(top: 0, left: 92, bottom: 0, right: 18)
        self.chatListTableView.rowHeight = 76
        self.chatListTableView.estimatedRowHeight = 76
        self.navigationItem.largeTitleDisplayMode = .never
        setupBrandTitle()

        // Footer for Archived Chats link.
        archivedChatsFooter = UIView(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: ChatListViewController.kFooterHeight))
        archivedChatsFooter!.backgroundColor = tableView.backgroundColor
        let button = UIButton(frame: CGRect(x: 0, y: 0, width: tableView.frame.width, height: ChatListViewController.kFooterHeight))
        button.setTitle(NSLocalizedString("Archived Chats", comment: "View title"), for: .normal)
        button.setTitleColor(UIColor.darkGray, for: .normal)
        button.titleLabel?.font = button.titleLabel?.font.withSize(15)
        button.addTarget(self, action: #selector(navigateToArchive), for: .touchUpInside)
        archivedChatsFooter!.addSubview(button)
        tableView.tableFooterView = archivedChatsFooter
        rebuildHeader()
    }

    private func setupBrandTitle() {
        let logo = UIImageView(image: UIImage(named: "logo-ios"))
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.contentMode = .scaleAspectFit
        logo.layer.cornerRadius = 7

        let title = UILabel()
        title.text = "CLAW OS"
        title.textColor = ClawTheme.ink
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.adjustsFontForContentSizeCategory = true

        let brand = UIStackView(arrangedSubviews: [logo, title])
        brand.axis = .horizontal
        brand.alignment = .center
        brand.spacing = 8
        brand.accessibilityLabel = "CLAW OS"
        brand.frame = CGRect(x: 0, y: 0, width: 142, height: 36)
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 32),
            logo.heightAnchor.constraint(equalToConstant: 32)
        ])
        // The storyboard provides a legacy navigation-item title. Clear it so the
        // custom logo-and-name view is the only brand shown in this header.
        navigationItem.title = nil
        navigationItem.titleView = nil
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: brand)
    }

    private func rebuildHeader() {
        let measuredWidth = tableView.bounds.width
        let width = measuredWidth > 0 ? measuredWidth : UIScreen.main.bounds.width
        let query = searchField?.text ?? ""
        activeContactItems = buildActiveContactItems()
        let hasActiveContacts = !activeContactItems.isEmpty
        let activeStripHeight = ActiveContactsLayoutMetrics.stripHeight
        let headerHeight: CGFloat = hasActiveContacts ? 104 + activeStripHeight + 38 : 104
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: headerHeight))
        header.backgroundColor = ClawTheme.surface

        let search = UITextField(frame: CGRect(x: 18, y: 12, width: width - 36, height: 48))
        search.text = query
        search.placeholder = NSLocalizedString("搜索消息或联系人", comment: "Chat list search placeholder")
        search.font = .systemFont(ofSize: 15)
        search.returnKeyType = .search
        search.clearButtonMode = .whileEditing
        search.autocorrectionType = .no
        ClawTheme.styleTextField(search)
        search.backgroundColor = ClawTheme.surfaceMuted
        search.layer.borderWidth = 0
        let searchIconContainer = UIView(frame: CGRect(x: 0, y: 0, width: 42, height: 48))
        let searchIcon = UIImageView(frame: CGRect(x: 14, y: 14, width: 20, height: 20))
        searchIcon.image = ClawTheme.symbol("magnifyingglass", pointSize: 18, weight: .medium)
        searchIcon.tintColor = ClawTheme.muted
        searchIcon.contentMode = .scaleAspectFit
        searchIconContainer.addSubview(searchIcon)
        search.leftView = searchIconContainer
        search.leftViewMode = .always
        search.addTarget(self, action: #selector(searchChanged(_:)), for: .editingChanged)
        header.addSubview(search)
        searchField = search

        var recentTitleY: CGFloat = 76
        if hasActiveContacts {
            let activeTitle = UILabel(frame: CGRect(x: 20, y: 76, width: width - 120, height: 22))
            activeTitle.text = NSLocalizedString("活跃联系人", comment: "Online contacts section title")
            activeTitle.textColor = ClawTheme.ink
            activeTitle.font = .systemFont(ofSize: 14, weight: .semibold)
            header.addSubview(activeTitle)

            let viewAll = UIButton(type: .system)
            viewAll.frame = CGRect(x: width - 96, y: 65, width: 76, height: 44)
            viewAll.setTitle(NSLocalizedString("查看全部", comment: "View all contacts"), for: .normal)
            viewAll.setTitleColor(ClawTheme.primary, for: .normal)
            viewAll.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
            viewAll.addTarget(self, action: #selector(showAllContacts), for: .touchUpInside)
            header.addSubview(viewAll)

            let horizontalInset: CGFloat = 20
            let spacing = ActiveContactsLayoutMetrics.spacing
            let visibleCount = ActiveContactsLayoutMetrics.visibleCount(
                viewportWidth: width,
                horizontalInset: horizontalInset,
                spacing: spacing)
            let itemWidth = ActiveContactsLayoutMetrics.itemWidth(
                viewportWidth: width,
                horizontalInset: horizontalInset,
                spacing: spacing)
            let activeScroll = UIScrollView(frame: CGRect(
                x: 0, y: 104, width: width, height: ActiveContactsLayoutMetrics.stripHeight))
            activeScroll.showsHorizontalScrollIndicator = false
            activeScroll.alwaysBounceHorizontal = activeContactItems.count > visibleCount
            for (index, contact) in activeContactItems.enumerated() {
                let item = UIButton(type: .custom)
                item.frame = CGRect(
                    x: horizontalInset + CGFloat(index) * (itemWidth + spacing),
                    y: 0,
                    width: itemWidth,
                    height: ActiveContactsLayoutMetrics.stripHeight)
                item.tag = index
                item.accessibilityLabel = contact.displayName
                item.addTarget(self, action: #selector(activeContactTapped(_:)), for: .touchUpInside)

                let avatarSize: CGFloat = 54
                let avatar = AvatarWithOnlineIndicator(frame: CGRect(
                    x: floor((itemWidth - avatarSize) * 0.5),
                    y: 0,
                    width: avatarSize,
                    height: avatarSize))
                avatar.isUserInteractionEnabled = false
                avatar.set(
                    pub: contact.pub,
                    id: contact.topicName,
                    online: contact.inCall ? false : contact.online,
                    deleted: contact.deleted)
                item.addSubview(avatar)

                if contact.inCall {
                    let callBadge = UIView(frame: CGRect(
                        x: floor((itemWidth - 36) * 0.5),
                        y: 42,
                        width: 36,
                        height: 18))
                    callBadge.backgroundColor = ClawTheme.accent
                    callBadge.layer.cornerRadius = 9
                    callBadge.layer.cornerCurve = .continuous
                    callBadge.isUserInteractionEnabled = false

                    let callIcon = UIImageView(frame: CGRect(x: 11, y: 3, width: 14, height: 12))
                    callIcon.image = ClawTheme.symbol("phone.fill", pointSize: 11, weight: .semibold)
                    callIcon.tintColor = .white
                    callIcon.contentMode = .scaleAspectFit
                    callBadge.addSubview(callIcon)
                    item.addSubview(callBadge)
                }

                let name = UILabel(frame: CGRect(x: 2, y: 60, width: itemWidth - 4, height: 58))
                name.text = contact.displayName
                name.textColor = ClawTheme.ink
                name.font = .systemFont(ofSize: 12, weight: .semibold)
                name.textAlignment = .center
                name.numberOfLines = 2
                name.adjustsFontForContentSizeCategory = true
                name.lineBreakMode = .byTruncatingTail
                item.addSubview(name)

                let status = UILabel(frame: CGRect(x: 2, y: 122, width: itemWidth - 4, height: 24))
                status.text = contact.inCall
                    ? NSLocalizedString("通话中", comment: "Contact is currently in a call")
                    : contact.online
                        ? NSLocalizedString("在线", comment: "Online contact status")
                        : NSLocalizedString("最近活跃", comment: "Recently active contact status")
                status.textColor = (contact.inCall || contact.online) ? ClawTheme.primary : ClawTheme.muted
                status.font = .systemFont(ofSize: 10, weight: .regular)
                status.adjustsFontForContentSizeCategory = true
                status.textAlignment = .center
                status.lineBreakMode = .byTruncatingTail
                item.addSubview(status)
                activeScroll.addSubview(item)
            }
            activeScroll.contentSize = CGSize(
                width: ActiveContactsLayoutMetrics.contentWidth(
                    itemCount: activeContactItems.count,
                    itemWidth: itemWidth,
                    horizontalInset: horizontalInset,
                    spacing: spacing),
                height: ActiveContactsLayoutMetrics.stripHeight)
            header.addSubview(activeScroll)
            recentTitleY = 104 + activeStripHeight + 8
        }

        let recentTitle = UILabel(frame: CGRect(x: 18, y: recentTitleY, width: width - 36, height: 22))
        recentTitle.text = NSLocalizedString("最近消息", comment: "Recent chats section title")
        recentTitle.textColor = ClawTheme.muted
        recentTitle.font = .systemFont(ofSize: 14, weight: .medium)
        header.addSubview(recentTitle)

        tableView.tableHeaderView = header
        headerWidth = width
    }

    private func applySearchFilter() {
        let query = searchField?.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        topics = query.isEmpty ? allTopics : allTopics.filter { topic in
            let title = AccountNames.contactDisplayName(
                displayName: topic.pub?.fn,
                accountName: topic.alias,
                userId: topic.name,
                genericDefaultName: NSLocalizedString("联系人", comment: "Generic contact name"))
                .lowercased()
            let accountName = AccountNames.contactListSecondary(accountName: topic.alias)?.lowercased() ?? ""
            return title.contains(query) || accountName.contains(query)
        }
        rowIndex = Dictionary(uniqueKeysWithValues: topics.enumerated().map { ($0.element.name, $0.offset) })
    }

    @objc private func searchChanged(_ sender: UITextField) {
        applySearchFilter()
        tableView.reloadData()
    }

    @objc private func activeContactTapped(_ sender: UIButton) {
        guard activeContactItems.indices.contains(sender.tag) else { return }
        performSegue(withIdentifier: "Chats2Messages", sender: activeContactItems[sender.tag].topicName)
    }

    private func buildActiveContactItems() -> [ActiveContactItem] {
        let genericName = NSLocalizedString("联系人", comment: "Generic contact name")
        let activeCallTopic = Cache.callManager.callInProgress?.topic

        let topics = Cache.tinode.getFilteredTopics { topic in
            topic.topicType == .p2p && topic.isJoiner && !topic.isArchived && !topic.deleted
        } ?? []

        return topics.compactMap { source -> ActiveContactItem? in
            guard let topic = source as? DefaultComTopic,
                  !topic.name.isEmpty,
                  !Cache.tinode.isMe(uid: topic.name) else { return nil }
            return ActiveContactItem(
                topicName: topic.name,
                pub: topic.pub,
                displayName: AccountNames.contactDisplayName(
                    displayName: topic.pub?.fn,
                    accountName: topic.alias,
                    userId: topic.name,
                    genericDefaultName: genericName),
                accountName: AccountNames.contactListSecondary(accountName: topic.alias),
                touched: topic.touched,
                inCall: activeCallTopic == topic.name,
                online: topic.online,
                deleted: topic.deleted)
        }
            .filter { !$0.deleted }
            .sorted { lhs, rhs in
                if lhs.inCall != rhs.inCall {
                    return lhs.inCall && !rhs.inCall
                }
                if lhs.online != rhs.online {
                    return lhs.online && !rhs.online
                }
                if lhs.touched != rhs.touched {
                    return (lhs.touched ?? Date.distantPast) > (rhs.touched ?? Date.distantPast)
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    @objc private func showAllContacts() {
        tabBarController?.selectedIndex = 1
    }

    private func toggleFooter(visible: Bool) {
        let count = numArchivedTopics > 9 ? "9+" : String(numArchivedTopics)
        let button = tableView.tableFooterView!.subviews[0] as! UIButton
        button.setTitle(String(format: NSLocalizedString("Archived Chats (%@)", comment: "Button to open chat archive"), count), for: .normal)
        archivedChatsFooter!.isHidden = !visible
        tableView.tableFooterView = archivedChatsFooter
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        setup()

        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appGoingInactive),
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }
    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
    }
    @objc
    func appBecameActive() {
        self.interactor?.setup()
        self.interactor?.attachToMeTopic()
        // Reload topics after the app became active.
        self.interactor?.loadAndPresentTopics()
    }
    @objc
    func appGoingInactive() {
        self.interactor?.cleanup()
        self.interactor?.leaveMeTopic()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.interactor?.setup()
        self.interactor?.attachToMeTopic()
        self.interactor?.loadAndPresentTopics()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        if abs(width - headerWidth) > 1, searchField?.isFirstResponder != true {
            rebuildHeader()
        }
    }

    // Continue listening on meTopic even when the VC isn't visible.
    // TODO: remote this.
    // override func viewDidDisappear(_ animated: Bool) {
    //     self.interactor?.cleanup()
    // }

    func displayLoginView() {
        UiUtils.logoutAndRouteToLoginVC()
    }

    func displayChats(_ topics: [DefaultComTopic], archivedTopics: [DefaultComTopic]?) {
        assert(Thread.isMainThread)
        self.allTopics = topics
        self.archivedTopics = archivedTopics
        applySearchFilter()
        rebuildHeader()
        self.tableView!.reloadData()
        self.toggleFooter(visible: self.numArchivedTopics > 0)
        (tabBarController as? ClawMainTabBarController)?.refreshMessageBadge()
    }

    func updateChat(_ name: String) {
        assert(Thread.isMainThread)
        rebuildHeader()
        if let position = rowIndex[name] {
            self.tableView!.reloadRows(at: [IndexPath(item: position, section: 0)], with: .none)
        }
        self.toggleFooter(visible: self.numArchivedTopics > 0)
        (tabBarController as? ClawMainTabBarController)?.refreshMessageBadge()
    }

    func deleteChat(_ name: String) {
        assert(Thread.isMainThread)
        allTopics.removeAll { $0.name == name }
        applySearchFilter()
        rebuildHeader()
        self.tableView!.reloadData()
        self.toggleFooter(visible: self.numArchivedTopics > 0)
        (tabBarController as? ClawMainTabBarController)?.refreshMessageBadge()
    }

    @objc private func navigateToArchive() {
        self.performSegue(withIdentifier: "Chats2Archive", sender: nil)
    }
}

// UITableViewController
extension ChatListViewController {
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "Chats2Messages", let topicName = sender as? String {
            router?.routeToChat(withName: topicName, for: segue)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        toggleNoChatsNote(on: topics.isEmpty)
        return topics.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatListViewCell") as! ChatListViewCell
        let topic = self.topics[indexPath.row]
        cell.fillFromTopic(topic: topic)
        return cell
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Delete item at indexPath
        let delete = UIContextualAction(style: .destructive, title: NSLocalizedString("Delete", comment: "Swipe action"), handler: { _,_,_ in
            let topic = self.topics[indexPath.row]
            self.interactor?.deleteTopic(topic.name)
        })
        let archive = UIContextualAction(style: .normal, title: NSLocalizedString("Archive", comment: "Swipe action"), handler: { _,_,_ in
            let topic = self.topics[indexPath.row]
            self.interactor?.changeArchivedStatus(
                forTopic: topic.name, archived: !topic.isArchived)
        })

        return UISwipeActionsConfiguration(actions: [delete, archive])
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.performSegue(withIdentifier: "Chats2Messages", sender: self.topics[indexPath.row].name)
    }
}

extension ChatListViewController {

    /// Show notification that the chat list is empty
    public func toggleNoChatsNote(on show: Bool) {
        if show {
            let rect = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height)
            let messageLabel = UILabel(frame: rect)
            messageLabel.text = NSLocalizedString("暂无消息", comment: "Placeholder when no chats found")
            messageLabel.textColor = ClawTheme.muted
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.font = UIFont.preferredFont(forTextStyle: .body)
            messageLabel.sizeToFit()

            tableView.backgroundView = messageLabel
        } else {
            tableView.backgroundView = nil
        }
    }
}
