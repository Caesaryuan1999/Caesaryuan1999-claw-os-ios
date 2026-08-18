//
//  NewChatTabController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

final class ClawMainTabBarController: UITabBarController, UITabBarControllerDelegate {
    private(set) var messagesNavigationController: UINavigationController!

    static func make(storyboard: UIStoryboard) -> ClawMainTabBarController {
        let controller = ClawMainTabBarController()
        controller.messagesNavigationController = storyboard.instantiateViewController(
            withIdentifier: "ChatsNavigator") as! UINavigationController

        let contacts = storyboard.instantiateViewController(withIdentifier: "Find")
        let contactsNavigation = UINavigationController(rootViewController: contacts)

        let callsNavigation = UINavigationController(rootViewController: ClawCallsHistoryViewController())

        let account = storyboard.instantiateViewController(withIdentifier: "Account Settings")
        let accountNavigation = UINavigationController(rootViewController: account)

        controller.viewControllers = [
            controller.messagesNavigationController,
            contactsNavigation,
            callsNavigation,
            accountNavigation
        ]
        controller.configureAppearance()
        controller.refreshMessageBadge()
        return controller
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshMessageBadge()
    }

    private func configureAppearance() {
        delegate = self
        let items: [(String, String, String)] = [
            ("消息", "message", "message.fill"),
            ("通讯录", "person.2", "person.2.fill"),
            ("通话", "phone", "phone.fill"),
            ("我的", "person.crop.circle", "person.crop.circle.fill")
        ]
        for (index, item) in items.enumerated() where index < (viewControllers?.count ?? 0) {
            viewControllers?[index].tabBarItem = UITabBarItem(
                title: NSLocalizedString(item.0, comment: "Main navigation item"),
                image: ClawTheme.symbol(item.1, pointSize: 21, weight: .medium),
                selectedImage: ClawTheme.symbol(item.2, pointSize: 21, weight: .semibold))
            viewControllers?[index].tabBarItem.accessibilityIdentifier = "claw.main.tab.\(index)"
        }

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ClawTheme.surface
        appearance.shadowColor = ClawTheme.border
        appearance.stackedLayoutAppearance.normal.iconColor = ClawTheme.muted
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: ClawTheme.muted,
            .font: UIFont.systemFont(ofSize: 11, weight: .medium)
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = ClawTheme.primary
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: ClawTheme.primary,
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold)
        ]
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.tintColor = ClawTheme.primary
        tabBar.unselectedItemTintColor = ClawTheme.muted
        tabBar.accessibilityIdentifier = "claw.main.tabbar"
    }

    func selectMessages() {
        selectedIndex = 0
    }

    func refreshMessageBadge() {
        guard let messagesItem = viewControllers?.first?.tabBarItem else { return }
        let unread = Cache.totalUnreadCount()
        messagesItem.badgeValue = unread > 0 ? (unread > 99 ? "99+" : String(unread)) : nil
        messagesItem.badgeColor = ClawTheme.danger
        messagesItem.setBadgeTextAttributes([
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 10, weight: .bold)
        ], for: .normal)
    }
}

private final class ClawCallHistoryCell: UITableViewCell {
    static let reuseIdentifier = "ClawCallHistoryCell"

    private let avatar = RoundImageView()
    private let nameLabel = UILabel()
    private let directionImage = UIImageView()
    private let resultLabel = UILabel()
    private let timeLabel = UILabel()
    private let callButton = UIButton(type: .system)
    var onCall: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = ClawTheme.surface
        selectionStyle = .none

        [avatar, nameLabel, directionImage, resultLabel, timeLabel, callButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = ClawTheme.ink
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        directionImage.contentMode = .scaleAspectFit
        resultLabel.font = .systemFont(ofSize: 13)
        resultLabel.textColor = ClawTheme.muted
        timeLabel.font = .systemFont(ofSize: 12)
        timeLabel.textColor = ClawTheme.muted
        timeLabel.textAlignment = .right
        ClawTheme.styleIconButton(callButton, symbolName: "phone.fill", pointSize: 18)
        callButton.accessibilityLabel = NSLocalizedString("回拨", comment: "Redial accessibility label")
        callButton.addTarget(self, action: #selector(callTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 54),
            avatar.heightAnchor.constraint(equalToConstant: 54),
            nameLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),
            directionImage.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            directionImage.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 7),
            directionImage.widthAnchor.constraint(equalToConstant: 14),
            directionImage.heightAnchor.constraint(equalToConstant: 14),
            resultLabel.leadingAnchor.constraint(equalTo: directionImage.trailingAnchor, constant: 5),
            resultLabel.centerYAnchor.constraint(equalTo: directionImage.centerYAnchor),
            resultLabel.trailingAnchor.constraint(lessThanOrEqualTo: callButton.leadingAnchor, constant: -8),
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            timeLabel.trailingAnchor.constraint(equalTo: callButton.leadingAnchor, constant: -6),
            callButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            callButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            callButton.widthAnchor.constraint(equalToConstant: ClawTheme.touchTarget),
            callButton.heightAnchor.constraint(equalToConstant: ClawTheme.touchTarget)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(record: ClawCallHistoryRecord) {
        let topic = Cache.tinode.getTopic(topicName: record.topic) as? DefaultComTopic
        nameLabel.text = topic?.pub?.fn ?? NSLocalizedString("未知联系人", comment: "Unknown contact")
        avatar.set(pub: topic?.pub, id: record.topic, deleted: false)
        timeLabel.text = RelativeDateFormatter.shared.shortDate(from: record.startedAt)
        let directionSymbol = record.outgoing ? "arrow.up.right" : "arrow.down.left"
        directionImage.image = ClawTheme.symbol(directionSymbol, pointSize: 12, weight: .semibold)
        let statusColor = record.missed ? ClawTheme.danger : ClawTheme.primary
        directionImage.tintColor = statusColor
        resultLabel.textColor = record.missed ? ClawTheme.danger : ClawTheme.muted
        if record.connected {
            resultLabel.text = String(format: NSLocalizedString("已接通 · %@", comment: "Connected call duration"), Self.duration(record.duration))
        } else {
            resultLabel.text = record.outgoing
                ? NSLocalizedString("未接通", comment: "Outgoing call not answered")
                : NSLocalizedString("未接来电", comment: "Missed incoming call")
        }
        ClawTheme.styleIconButton(
            callButton,
            symbolName: record.audioOnly ? "phone.fill" : "video.fill",
            pointSize: 18,
            tintColor: ClawTheme.primary)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onCall = nil
    }

    @objc private func callTapped() {
        onCall?()
    }

    private static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

final class ClawCallsHistoryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let allButton = UIButton(type: .system)
    private let missedButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyState = UIStackView()
    private var records: [ClawCallHistoryRecord] = []
    private var missedOnly = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("通话", comment: "Calls tab title")
        view.backgroundColor = ClawTheme.surface
        navigationItem.largeTitleDisplayMode = .never
        view.accessibilityIdentifier = "claw.calls.history.screen"
        configureNavigation()
        configureFilters()
        configureTable()
        configureEmptyState()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reloadRecords), name: .clawCallHistoryDidChange, object: nil)
        reloadRecords()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadRecords()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureNavigation() {
        let add = UIButton(type: .system)
        add.frame = CGRect(x: 0, y: 0, width: ClawTheme.touchTarget, height: ClawTheme.touchTarget)
        ClawTheme.styleIconButton(add, symbolName: "person.badge.plus", pointSize: 20)
        add.accessibilityLabel = NSLocalizedString("选择联系人", comment: "Choose a contact")
        add.addTarget(self, action: #selector(openContacts), for: .touchUpInside)
        clearButton.frame = CGRect(x: 0, y: 0, width: ClawTheme.touchTarget, height: ClawTheme.touchTarget)
        ClawTheme.styleIconButton(clearButton, symbolName: "trash", pointSize: 19)
        clearButton.tintColor = ClawTheme.danger
        clearButton.accessibilityLabel = NSLocalizedString("清空通话记录", comment: "Clear call history")
        clearButton.accessibilityIdentifier = "claw.calls.history.clear"
        clearButton.addTarget(self, action: #selector(confirmClearHistory), for: .touchUpInside)
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: add),
            UIBarButtonItem(customView: clearButton)
        ]
    }

    private func configureFilters() {
        allButton.setTitle(NSLocalizedString("全部", comment: "All calls filter"), for: .normal)
        missedButton.setTitle(NSLocalizedString("未接", comment: "Missed calls filter"), for: .normal)
        allButton.accessibilityIdentifier = "claw.calls.filter.all"
        missedButton.accessibilityIdentifier = "claw.calls.filter.missed"
        allButton.addTarget(self, action: #selector(showAll), for: .touchUpInside)
        missedButton.addTarget(self, action: #selector(showMissed), for: .touchUpInside)
        [allButton, missedButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            $0.contentHorizontalAlignment = .center
            $0.contentVerticalAlignment = .center
            $0.layer.cornerRadius = 19
            $0.layer.cornerCurve = .continuous
            NSLayoutConstraint.activate([
                $0.widthAnchor.constraint(equalToConstant: 82),
                $0.heightAnchor.constraint(equalToConstant: 38)
            ])
        }
        let filters = UIStackView(arrangedSubviews: [allButton, missedButton])
        filters.translatesAutoresizingMaskIntoConstraints = false
        filters.axis = .horizontal
        filters.spacing = 8
        view.addSubview(filters)
        NSLayoutConstraint.activate([
            filters.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            filters.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: filters.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        updateFilterAppearance()
    }

    private func configureTable() {
        tableView.backgroundColor = ClawTheme.surface
        tableView.separatorColor = ClawTheme.border
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 82, bottom: 0, right: 16)
        tableView.rowHeight = 76
        tableView.keyboardDismissMode = .onDrag
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ClawCallHistoryCell.self, forCellReuseIdentifier: ClawCallHistoryCell.reuseIdentifier)
    }

    private func configureEmptyState() {
        let image = UIImageView(image: ClawTheme.symbol("phone.arrow.up.right", pointSize: 30, weight: .medium))
        image.tintColor = ClawTheme.primary
        image.contentMode = .center
        image.heightAnchor.constraint(equalToConstant: 56).isActive = true
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("暂无通话记录", comment: "Empty call history title")
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = ClawTheme.ink
        titleLabel.textAlignment = .center
        let detailLabel = UILabel()
        detailLabel.text = NSLocalizedString("从联系人主页发起安全的语音或视频通话。", comment: "Empty call history message")
        detailLabel.font = .systemFont(ofSize: 14)
        detailLabel.textColor = ClawTheme.muted
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.axis = .vertical
        emptyState.spacing = 10
        [image, titleLabel, detailLabel].forEach { emptyState.addArrangedSubview($0) }
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            emptyState.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            emptyState.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -24)
        ])
    }

    @objc private func reloadRecords() {
        let allRecords = ClawCallHistoryStore.records()
        records = ClawCallHistoryStore.filtered(allRecords, missedOnly: missedOnly)
        clearButton.isEnabled = !allRecords.isEmpty
        clearButton.alpha = clearButton.isEnabled ? 1 : 0.35
        emptyState.isHidden = !records.isEmpty
        tableView.isHidden = records.isEmpty
        tableView.reloadData()
    }

    @objc private func showAll() {
        missedOnly = false
        updateFilterAppearance()
        reloadRecords()
    }

    @objc private func showMissed() {
        missedOnly = true
        updateFilterAppearance()
        reloadRecords()
    }

    private func updateFilterAppearance() {
        styleFilter(allButton, selected: !missedOnly)
        styleFilter(missedButton, selected: missedOnly)
    }

    private func styleFilter(_ button: UIButton, selected: Bool) {
        button.backgroundColor = selected ? ClawTheme.primary : ClawTheme.surfaceMuted
        button.setTitleColor(selected ? .white : ClawTheme.muted, for: .normal)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return records.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ClawCallHistoryCell.reuseIdentifier, for: indexPath) as! ClawCallHistoryCell
        let record = records[indexPath.row]
        cell.configure(record: record)
        cell.onCall = { [weak self] in self?.startCall(record) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        UiUtils.routeToMessageVC(forTopic: records[indexPath.row].topic)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let record = records[indexPath.row]
        let delete = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("删除", comment: "Delete call history item")) { _, _, completion in
                let deleted = ClawCallHistoryStore.delete(id: record.id)
                if !deleted {
                    UiUtils.showToast(message: NSLocalizedString(
                        "通话记录删除失败，请重试", comment: "Call history delete failed"))
                }
                completion(deleted)
            }
        delete.image = ClawTheme.symbol("trash", pointSize: 18, weight: .semibold)
        let configuration = UISwipeActionsConfiguration(actions: [delete])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    @objc private func confirmClearHistory() {
        let alert = UIAlertController(
            title: NSLocalizedString("清空通话记录", comment: "Clear call history title"),
            message: NSLocalizedString("确定删除此设备上的全部通话记录吗？此操作无法撤销。", comment: "Clear call history message"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("全部删除", comment: "Delete all call history"),
            style: .destructive) { _ in
                if !ClawCallHistoryStore.clear() {
                    UiUtils.showToast(message: NSLocalizedString(
                        "通话记录删除失败，请重试", comment: "Call history delete failed"))
                }
            })
        present(alert, animated: true)
    }

    private func startCall(_ record: ClawCallHistoryRecord) {
        UiUtils.routeToMessageVC(forTopic: record.topic) { messageVC in
            guard let messageVC = messageVC else { return }
            let callType = record.audioOnly
                ? MessageViewController.Constants.kAudioOnlyCall
                : MessageViewController.Constants.kVideoCall
            messageVC.performSegue(withIdentifier: "Messages2Call", sender: callType)
        }
    }

    @objc private func openContacts() {
        if let controllers = tabBarController?.viewControllers,
           controllers.count > 1,
           let navigation = controllers[1] as? UINavigationController,
           let contacts = navigation.viewControllers.first as? FindViewController {
            contacts.isSelectingContactForCall = true
        }
        tabBarController?.selectedIndex = 1
    }
}

class NewChatTabController: UITabBarController, UITabBarControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        self.delegate = self
    }

    func tabBarController(_ tabBarController: UITabBarController,
                          shouldSelect viewController: UIViewController) -> Bool {
        guard let viewControllers = self.viewControllers else { return false }
        guard viewControllers[selectedIndex] !== viewController else { return false }
        for controller in viewControllers.compactMap({ $0 as? FindViewController }) {
            controller.cancelPendingSearchRequest(deactivateSearch: true)
        }
        return true
    }
}
