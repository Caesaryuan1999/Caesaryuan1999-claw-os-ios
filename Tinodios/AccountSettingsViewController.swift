//
//  AccountSettingsViewController.swift
//
//  Copyright © 2019-2025 Tinode LLC. All rights reserved.
//

import TinodeSDK
import UIKit

class AccountSettingsViewController: UITableViewController {
    private static let kSectionBasic = 0
    // Avatar = 0
    // Name = 1
    private static let kSectionPersonal = 1
    // MyUID = 0
    private static let kPersonalAlias = 1
    private static let kPersonalVerified = 2
    private static let kPersonalStaff = 3
    private static let kPersonalDanger = 4
    private static let kPersonalDescription = 5

    @IBOutlet weak var avatarImageView: RoundImageView!
    @IBOutlet weak var userNameLabel: UILabel!
    @IBOutlet weak var myUIDLabel: UILabel!
    @IBOutlet weak var aliasLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    
    private var tinode: Tinode!
    private var me: DefaultMeTopic?
    private var accountSyncAttempt = 0
    private let premiumAvatar = RoundImageView()
    private let premiumDisplayName = UILabel()
    private let premiumIdentityCaption = UILabel()
    private let premiumAccountName = UILabel()
    private var publicIdentityStack: UIStackView?
    private var appearanceRow: UIStackView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "claw.settings.account.screen"
        tableView.accessibilityIdentifier = "claw.settings.account.list"
        setup()
        navigationItem.title = NSLocalizedString("我", comment: "Account settings title")
        ClawTheme.styleList(tableView, rowHeight: 72)
        tableView.backgroundColor = ClawTheme.background
        tableView.separatorStyle = .none
        tableView.sectionHeaderHeight = 0
        tableView.sectionFooterHeight = 12
        avatarImageView.layer.borderWidth = 2
        avatarImageView.layer.borderColor = ClawTheme.brandSoft.cgColor
        userNameLabel.textColor = ClawTheme.ink
        myUIDLabel.textColor = ClawTheme.ink
        aliasLabel.textColor = ClawTheme.ink
        descriptionLabel.textColor = ClawTheme.ink
        installPremiumHeader()
        tableView.tableFooterView = UIView(frame: .zero)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = false
        reloadData()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.prefersLargeTitles = false
    }

    private func setup() {
        self.tinode = Cache.tinode
        self.me = self.tinode.getMeTopic()
    }

    private func installPremiumHeader() {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 650))
        header.backgroundColor = ClawTheme.background
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never

        premiumAvatar.translatesAutoresizingMaskIntoConstraints = false
        premiumAvatar.contentMode = .scaleAspectFill
        premiumAvatar.clipsToBounds = true
        premiumAvatar.widthAnchor.constraint(equalToConstant: 56).isActive = true
        premiumAvatar.heightAnchor.constraint(equalToConstant: 56).isActive = true
        premiumDisplayName.font = ClawTheme.font(20, weight: .semibold, style: .title2)
        premiumDisplayName.textColor = ClawTheme.ink
        premiumDisplayName.textAlignment = .natural
        premiumDisplayName.numberOfLines = 0
        premiumDisplayName.adjustsFontForContentSizeCategory = true

        let edit = UIButton(type: .system)
        edit.setTitleColor(ClawTheme.primary, for: .normal)
        edit.contentHorizontalAlignment = .leading
        edit.titleLabel?.numberOfLines = 0
        edit.titleLabel?.adjustsFontForContentSizeCategory = true
        edit.setTitle("编辑个人资料", for: .normal)
        edit.titleLabel?.font = ClawTheme.font(13)
        edit.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        edit.addTarget(self, action: #selector(openGeneralSettings), for: .touchUpInside)
        edit.accessibilityIdentifier = "claw.settings.account.profile"
        let identityText = UIStackView(arrangedSubviews: [premiumDisplayName, edit])
        identityText.axis = .vertical
        identityText.spacing = 0
        let identity = UIStackView(arrangedSubviews: [premiumAvatar, identityText])
        identity.alignment = .center
        identity.spacing = 16
        let publicRow = makeIdentityRow(title: "CLAW号", valueLabel: premiumAccountName, copyTag: 1)
        let profile = UIStackView(arrangedSubviews: [identity, publicRow])
        profile.accessibilityIdentifier = "claw.settings.account.profile-card"
        profile.axis = .vertical
        profile.spacing = 12
        profile.isLayoutMarginsRelativeArrangement = true
        profile.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)
        profile.backgroundColor = ClawTheme.surface
        profile.layer.cornerRadius = 20

        let notificationsRow = makeSettingsMenuRow(title: "消息通知", symbolName: "bell", action: #selector(openNotifications))
        let securityRow = makeSettingsMenuRow(title: "账号安全", symbolName: "shield", action: #selector(openSecurity))
        let helpRow = makeSettingsMenuRow(title: "关于 CLAW OS", symbolName: "questionmark.circle", action: #selector(openHelp))
        let appearance = UILabel()
        appearance.text = "跟随系统"
        let appearanceRow = ClawProfileLayout.valueRow(title: "外观", value: appearance)
        self.appearanceRow = appearanceRow
        appearanceRow.accessibilityIdentifier = "claw.settings.account.appearance-readonly"
        appearanceRow.accessibilityHint = "当前跟随系统外观，可在系统设置中更改"
        let logoutButton = UIButton(type: .system)
        logoutButton.setTitle("退出登录", for: .normal)
        logoutButton.setTitleColor(ClawTheme.danger, for: .normal)
        logoutButton.titleLabel?.font = ClawTheme.font(15, weight: .medium)
        logoutButton.titleLabel?.adjustsFontForContentSizeCategory = true
        logoutButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        logoutButton.addTarget(self, action: #selector(confirmLogout), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            profile, ClawProfileLayout.label("偏好设置", size: 12), notificationsRow, appearanceRow,
            ClawProfileLayout.label("账号与帮助", size: 12), securityRow, helpRow, logoutButton
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(16, after: profile)
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -24)
        ])
        tableView.tableHeaderView = header
        ClawProfileLayout.fitHeader(in: tableView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        premiumAvatar.layer.cornerRadius = 20
        let accessible = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        publicIdentityStack?.axis = accessible ? .vertical : .horizontal
        publicIdentityStack?.alignment = accessible ? .leading : .center
        appearanceRow?.axis = accessible ? .vertical : .horizontal
        appearanceRow?.alignment = accessible ? .leading : .center
        guard let header = tableView.tableHeaderView else { return }
        tableView.contentInset.bottom = max(24, view.safeAreaInsets.bottom + 24)
        header.frame.size.width = tableView.bounds.width
        header.setNeedsLayout()
        let fittingHeight = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        let targetHeight = ceil(fittingHeight)
        if abs(header.frame.height - targetHeight) > 0.5 {
            header.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: targetHeight)
            tableView.tableHeaderView = header
        }
        ClawTheme.normalizeIconButtons(in: header)
    }

    private func makeIdentityRow(title: String, valueLabel: UILabel, copyTag: Int) -> UIView {
        let caption = ClawProfileLayout.label(title, size: 16, color: ClawTheme.ink)
        caption.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.font = ClawTheme.font(13)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = ClawTheme.muted
        valueLabel.numberOfLines = 0
        valueLabel.accessibilityIdentifier = "claw.settings.account.public-id"
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let copy = UIButton(type: .system)
        copy.tag = copyTag
        copy.setTitle("复制", for: .normal)
        copy.setTitleColor(ClawTheme.primary, for: .normal)
        copy.titleLabel?.font = ClawTheme.font(13)
        copy.titleLabel?.adjustsFontForContentSizeCategory = true
        copy.titleLabel?.numberOfLines = 0
        copy.accessibilityLabel = NSLocalizedString("复制 CLAW 号", comment: "Copy public identifier")
        copy.accessibilityIdentifier = "claw.settings.account.copy-public-id"
        copy.addTarget(self, action: #selector(copyPremiumValue(_:)), for: .touchUpInside)
        copy.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        copy.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        let row = UIStackView(arrangedSubviews: [caption, valueLabel, copy])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        publicIdentityStack = row
        return row
    }

    @objc private func copyPremiumValue(_ sender: UIButton) {
        copyTopicValue(sender)
    }

    private func makeSettingsMenuRow(title: String, symbolName: String, action: Selector) -> UIControl {
        let row = UIControl()
        row.backgroundColor = ClawTheme.surface
        row.layer.cornerRadius = 12
        row.addTarget(self, action: action, for: .touchUpInside)
        row.isAccessibilityElement = true
        row.accessibilityLabel = title
        row.accessibilityTraits = .button
        let label = ClawProfileLayout.label(title, size: 16, color: ClawTheme.ink)
        let chevron = UIImageView(image: ClawTheme.symbol("chevron.right", pointSize: 16, weight: .regular))
        chevron.tintColor = ClawTheme.muted
        chevron.contentMode = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        row.addSubview(chevron)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 20),
            chevron.heightAnchor.constraint(equalToConstant: 20)
        ])
        return row
    }

    @objc private func openGeneralSettings() {
        guard self.tinode.getMeTopic() != nil else {
            UiUtils.showToast(message: NSLocalizedString("正在加载个人资料，请稍后重试", comment: "Profile not yet available"))
            return
        }
        performSegue(withIdentifier: "AccountSettings2General", sender: self)
    }

    @objc private func openNotifications() {
        let notifications = SettingsNotificationsViewController(style: .insetGrouped)
        if let navigationController = navigationController {
            navigationController.pushViewController(notifications, animated: true)
        } else {
            present(UINavigationController(rootViewController: notifications), animated: true)
        }
    }

    @objc private func openSecurity() {
        performSegue(withIdentifier: "AccountSettings2Security", sender: self)
    }

    @objc private func openHelp() {
        performSegue(withIdentifier: "AccountSettings2Help", sender: self)
    }

    @objc private func confirmLogout() {
        guard let owner = tinode, Cache.isCurrent(owner) else { return }
        let uid = owner.myUid
        let generation = Cache.sessionGeneration
        let alert = UIAlertController(
            title: NSLocalizedString("退出登录", comment: "Log out"),
            message: NSLocalizedString("退出后需重新登录。本机待发送和发送结果待确认的消息将保留。", comment: "Warning in logout alert"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("退出登录", comment: "Confirm logout"),
            style: .destructive,
            handler: { [weak self] _ in self?.logout(owner: owner, uid: uid, generation: generation) }))
        present(alert, animated: true)
    }

    private func logout(owner: Tinode, uid: String?, generation: UInt64) {
        guard Cache.sessionGeneration == generation, owner.myUid == uid, Cache.isCurrent(owner) else { return }
        UiUtils.logoutAndRouteToLoginVC(ifCurrent: owner)
        if Cache.isLoggedOut(generation: generation &+ 1) {
            UiUtils.showToast(message: NSLocalizedString("已退出登录", comment: "Logout success"), level: .info)
        }
    }

    private func reloadData() {
        guard let me = self.me ?? self.tinode.getMeTopic() else {
            userNameLabel.text = NSLocalizedString("正在同步账号", comment: "Account data loading state")
            myUIDLabel.text = self.tinode.myUid ?? "-"
            aliasLabel.text = NSLocalizedString("未设置", comment: "Placeholder for missing account name")
            descriptionLabel.text = NSLocalizedString("邀请码不可用", comment: "Placeholder for missing invite code")
            avatarImageView.set(pub: nil, id: self.tinode.myUid, deleted: false)
            premiumDisplayName.text = NSLocalizedString("正在同步账号", comment: "Account data loading state")
            premiumAccountName.text = NSLocalizedString("未设置", comment: "Placeholder for missing account name")
            premiumAvatar.set(pub: nil, id: self.tinode.myUid, deleted: false)
            scheduleAccountSyncRetry()
            return
        }
        self.me = me
        accountSyncAttempt = 0
        let accountName = AccountNames.fromTags(me.tags)
        // Title.
        self.userNameLabel.text = AccountNames.contactDisplayName(displayName: me.pub?.fn,
                                                                  accountName: accountName,
                                                                  userId: self.tinode.myUid)
        premiumDisplayName.text = AccountNames.contactDisplayName(displayName: me.pub?.fn, accountName: accountName, userId: self.tinode.myUid, genericDefaultName: "未设置昵称")

        // Avatar.
        self.avatarImageView.set(pub: me.pub, id: self.tinode.myUid, deleted: false)
        premiumAvatar.set(pub: me.pub, id: self.tinode.myUid, deleted: false)
        self.avatarImageView.letterTileFont = self.avatarImageView.letterTileFont.withSize(CGFloat(50))

        // Retain storyboard connections without exposing internal UID or obsolete invite credentials.
        self.descriptionLabel.text = nil
        self.myUIDLabel.text = nil
        self.descriptionLabel.accessibilityElementsHidden = true
        self.myUIDLabel.accessibilityElementsHidden = true

        self.aliasLabel.text = accountName ?? NSLocalizedString("未设置", comment: "Placeholder for missing account name")
        premiumAccountName.text = aliasLabel.text
        self.aliasLabel.sizeToFit()
    }

    private func scheduleAccountSyncRetry() {
        guard accountSyncAttempt < 5 else { return }
        accountSyncAttempt += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, self.viewIfLoaded?.window != nil else { return }
            self.me = self.tinode.getMeTopic()
            self.reloadData()
        }
    }

    @IBAction func copyTopicValue(_ sender: UIButton) {
        let accountName = (self.me ?? self.tinode.getMeTopic()).flatMap {
            AccountNames.fromTags($0.tags)
        }
        guard sender.tag == 1, let value = accountName, !value.isEmpty else { return }
        UIPasteboard.general.string = value
        UiUtils.showToast(message: NSLocalizedString("CLAW 号已复制", comment: "Public identifier copied"), level: .info)
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return CGFloat.leastNonzeroMagnitude
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return CGFloat.leastNonzeroMagnitude
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return CGFloat.leastNonzeroMagnitude
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        cell.accessibilityElementsHidden = true
        if indexPath.section == AccountSettingsViewController.kSectionBasic {
            // Hide separator lines in the top sections.
            cell.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: UIScreen.main.bounds.width)
        }
        if indexPath.section == 2 {
            cell.backgroundColor = ClawTheme.surface
            cell.textLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            cell.textLabel?.textColor = ClawTheme.ink
            cell.imageView?.tintColor = ClawTheme.primaryPressed
            cell.imageView?.contentMode = .scaleAspectFit
            cell.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 18)
        }
        return cell
    }
}
