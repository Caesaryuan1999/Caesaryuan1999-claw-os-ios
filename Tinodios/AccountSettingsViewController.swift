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
    private let premiumUid = UILabel()
    private let premiumAccountName = UILabel()
    private let premiumInviteCode = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "claw.settings.account.screen"
        tableView.accessibilityIdentifier = "claw.settings.account.list"
        setup()
        navigationItem.title = NSLocalizedString("Account settings", comment: "Account settings title")
        ClawTheme.styleList(tableView, rowHeight: 72)
        tableView.backgroundColor = ClawTheme.surfaceMuted
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

        reloadData()
    }

    private func setup() {
        self.tinode = Cache.tinode
        self.me = self.tinode.getMeTopic()
    }

    private func installPremiumHeader() {
        let width = max(tableView.bounds.width, UIScreen.main.bounds.width)
        let header = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 760))
        header.backgroundColor = ClawTheme.surfaceMuted

        premiumAvatar.translatesAutoresizingMaskIntoConstraints = false
        premiumAvatar.contentMode = .scaleAspectFill
        premiumAvatar.clipsToBounds = true
        premiumAvatar.layer.borderWidth = 2
        premiumAvatar.layer.borderColor = ClawTheme.brandSoft.cgColor

        premiumDisplayName.translatesAutoresizingMaskIntoConstraints = false
        premiumDisplayName.font = .systemFont(ofSize: 22, weight: .bold)
        premiumDisplayName.textColor = ClawTheme.ink
        premiumDisplayName.textAlignment = .center
        premiumDisplayName.numberOfLines = 0
        premiumDisplayName.adjustsFontForContentSizeCategory = true

        premiumIdentityCaption.translatesAutoresizingMaskIntoConstraints = false
        premiumIdentityCaption.text = NSLocalizedString("ID 和账号名用于查找和添加", comment: "Account identity explanation")
        premiumIdentityCaption.font = .systemFont(ofSize: 13, weight: .medium)
        premiumIdentityCaption.textColor = ClawTheme.muted
        premiumIdentityCaption.textAlignment = .center

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        ClawTheme.styleCard(card)

        let idRow = makeIdentityRow(
            title: "ID",
            valueLabel: premiumUid,
            copyTag: 0)
        let accountRow = makeIdentityRow(
            title: NSLocalizedString("账号名（不可修改）", comment: "Immutable account name"),
            valueLabel: premiumAccountName,
            copyTag: 1)
        let inviteRow = makeIdentityRow(
            title: NSLocalizedString("注册邀请码", comment: "Registration invite code"),
            valueLabel: premiumInviteCode,
            copyTag: 2)

        let rows = UIStackView(arrangedSubviews: [idRow, accountRow, inviteRow])
        rows.translatesAutoresizingMaskIntoConstraints = false
        rows.axis = .vertical
        rows.distribution = .fillEqually
        rows.spacing = 0

        let settingsCard = UIView()
        settingsCard.translatesAutoresizingMaskIntoConstraints = false
        ClawTheme.styleCard(settingsCard)

        let generalRow = makeSettingsMenuRow(
            title: NSLocalizedString("通用设置", comment: "General settings"),
            symbolName: "slider.horizontal.3",
            action: #selector(openGeneralSettings))
        let notificationsRow = makeSettingsMenuRow(
            title: NSLocalizedString("通知", comment: "Notification settings"),
            symbolName: "bell",
            action: #selector(openNotifications))
        let securityRow = makeSettingsMenuRow(
            title: NSLocalizedString("安全", comment: "Security settings"),
            symbolName: "shield",
            action: #selector(openSecurity))
        let settingsRows = UIStackView(arrangedSubviews: [generalRow, notificationsRow, securityRow])
        settingsRows.translatesAutoresizingMaskIntoConstraints = false
        settingsRows.axis = .vertical
        settingsRows.distribution = .fillEqually

        let logoutButton = UIButton(type: .system)
        logoutButton.translatesAutoresizingMaskIntoConstraints = false
        logoutButton.setTitle(NSLocalizedString("登出", comment: "Log out"), for: .normal)
        logoutButton.setTitleColor(ClawTheme.danger, for: .normal)
        logoutButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        logoutButton.setImage(
            ClawTheme.symbol("rectangle.portrait.and.arrow.right", pointSize: ClawTheme.iconStandard,
                             weight: .medium),
            for: .normal)
        logoutButton.tintColor = ClawTheme.danger
        logoutButton.contentHorizontalAlignment = .center
        logoutButton.titleLabel?.adjustsFontForContentSizeCategory = true
        logoutButton.backgroundColor = ClawTheme.surface
        logoutButton.layer.cornerRadius = ClawTheme.buttonRadius
        logoutButton.layer.cornerCurve = .continuous
        logoutButton.layer.borderWidth = 1
        logoutButton.layer.borderColor = ClawTheme.danger.withAlphaComponent(0.22).cgColor
        logoutButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -5, bottom: 0, right: 5)
        logoutButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: -5)
        logoutButton.addTarget(self, action: #selector(confirmLogout), for: .touchUpInside)

        header.addSubview(premiumAvatar)
        header.addSubview(premiumDisplayName)
        header.addSubview(premiumIdentityCaption)
        header.addSubview(card)
        header.addSubview(settingsCard)
        header.addSubview(logoutButton)
        card.addSubview(rows)
        settingsCard.addSubview(settingsRows)

        NSLayoutConstraint.activate([
            premiumAvatar.topAnchor.constraint(equalTo: header.topAnchor, constant: 24),
            premiumAvatar.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            premiumAvatar.widthAnchor.constraint(equalToConstant: 112),
            premiumAvatar.heightAnchor.constraint(equalToConstant: 112),

            premiumDisplayName.topAnchor.constraint(equalTo: premiumAvatar.bottomAnchor, constant: 18),
            premiumDisplayName.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            premiumDisplayName.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),

            premiumIdentityCaption.topAnchor.constraint(equalTo: premiumDisplayName.bottomAnchor, constant: 8),
            premiumIdentityCaption.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            premiumIdentityCaption.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),

            card.topAnchor.constraint(equalTo: premiumIdentityCaption.bottomAnchor, constant: 30),
            card.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            card.heightAnchor.constraint(equalToConstant: 218),

            rows.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            rows.topAnchor.constraint(equalTo: card.topAnchor),
            rows.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            settingsCard.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 18),
            settingsCard.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            settingsCard.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            settingsCard.heightAnchor.constraint(equalToConstant: 186),
            settingsRows.leadingAnchor.constraint(equalTo: settingsCard.leadingAnchor),
            settingsRows.trailingAnchor.constraint(equalTo: settingsCard.trailingAnchor),
            settingsRows.topAnchor.constraint(equalTo: settingsCard.topAnchor),
            settingsRows.bottomAnchor.constraint(equalTo: settingsCard.bottomAnchor),

            logoutButton.topAnchor.constraint(equalTo: settingsCard.bottomAnchor, constant: 14),
            logoutButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            logoutButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            logoutButton.heightAnchor.constraint(equalToConstant: 54),
            logoutButton.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -24)
        ])
        tableView.tableHeaderView = header
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        premiumAvatar.layer.cornerRadius = premiumAvatar.bounds.width / 2
        guard let header = tableView.tableHeaderView else { return }
        tableView.contentInset.bottom = max(24, view.safeAreaInsets.bottom + 24)
        header.frame.size.width = tableView.bounds.width
        header.setNeedsLayout()
        header.layoutIfNeeded()
        let fittingHeight = header.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        let targetHeight = max(760, fittingHeight + 1)
        if abs(header.frame.height - targetHeight) > 0.5 {
            header.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: targetHeight)
            tableView.tableHeaderView = header
        }
        ClawTheme.normalizeIconButtons(in: header)
    }

    private func makeIdentityRow(title: String, valueLabel: UILabel, copyTag: Int) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = ClawTheme.primaryPressed

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        valueLabel.textColor = ClawTheme.ink
        valueLabel.numberOfLines = 1
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.72

        let copyButton = UIButton(type: .system)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.tag = copyTag
        copyButton.setImage(ClawTheme.symbol("doc.on.doc", pointSize: ClawTheme.iconCompact, weight: .regular), for: .normal)
        copyButton.tintColor = ClawTheme.muted
        copyButton.accessibilityLabel = NSLocalizedString("复制", comment: "Copy value")
        copyButton.addTarget(self, action: #selector(copyPremiumValue(_:)), for: .touchUpInside)

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = ClawTheme.border

        row.addSubview(titleLabel)
        row.addSubview(valueLabel)
        row.addSubview(copyButton)
        row.addSubview(divider)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -12),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            valueLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -12),
            copyButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 48),
            copyButton.heightAnchor.constraint(equalToConstant: 48),
            divider.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            divider.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            divider.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
        return row
    }

    @objc private func copyPremiumValue(_ sender: UIButton) {
        copyTopicValue(sender)
    }

    private func makeSettingsMenuRow(title: String, symbolName: String, action: Selector) -> UIControl {
        let row = UIControl()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addTarget(self, action: action, for: .touchUpInside)

        let icon = UIImageView(image: ClawTheme.symbol(
            symbolName, pointSize: ClawTheme.iconStandard, weight: .medium))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = ClawTheme.primary
        icon.contentMode = .center

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.textColor = ClawTheme.ink
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true

        let chevron = UIImageView(image: ClawTheme.symbol(
            "chevron.right", pointSize: ClawTheme.iconCompact, weight: .semibold))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = ClawTheme.muted
        chevron.contentMode = .center

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = ClawTheme.border

        row.addSubview(icon)
        row.addSubview(label)
        row.addSubview(chevron)
        row.addSubview(divider)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 20),
            divider.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
            divider.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
        return row
    }

    @objc private func openGeneralSettings() {
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

    @objc private func confirmLogout() {
        let alert = UIAlertController(
            title: NSLocalizedString("登出", comment: "Log out"),
            message: NSLocalizedString("确定要登出？", comment: "Warning in logout alert"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("确定", comment: "Confirm"),
            style: .destructive,
            handler: { _ in self.logout() }))
        present(alert, animated: true)
    }

    private func logout() {
        guard Cache.tinode != nil else {
            UiUtils.showToast(message: NSLocalizedString("登出失败，请重试", comment: "Logout failure"))
            return
        }
        UiUtils.logoutAndRouteToLoginVC()
        UiUtils.showToast(message: NSLocalizedString("已成功登出", comment: "Logout success"), level: .info)
    }

    private func reloadData() {
        guard let me = self.me ?? self.tinode.getMeTopic() else {
            userNameLabel.text = NSLocalizedString("正在同步账号", comment: "Account data loading state")
            myUIDLabel.text = self.tinode.myUid ?? "-"
            aliasLabel.text = NSLocalizedString("未设置", comment: "Placeholder for missing account name")
            descriptionLabel.text = NSLocalizedString("邀请码不可用", comment: "Placeholder for missing invite code")
            avatarImageView.set(pub: nil, id: self.tinode.myUid, deleted: false)
            premiumDisplayName.text = NSLocalizedString("正在同步账号", comment: "Account data loading state")
            premiumUid.text = self.tinode.myUid ?? "-"
            premiumAccountName.text = NSLocalizedString("未设置", comment: "Placeholder for missing account name")
            premiumInviteCode.text = NSLocalizedString("邀请码不可用", comment: "Placeholder for missing invite code")
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
        premiumDisplayName.text = self.userNameLabel.text

        // Avatar.
        self.avatarImageView.set(pub: me.pub, id: self.tinode.myUid, deleted: false)
        premiumAvatar.set(pub: me.pub, id: self.tinode.myUid, deleted: false)
        self.avatarImageView.letterTileFont = self.avatarImageView.letterTileFont.withSize(CGFloat(50))

        self.descriptionLabel.text = me.creds?.first(where: { $0.meth == ClawAuthInput.inviteCredentialMethod })?.val ??
            NSLocalizedString("邀请码不可用", comment: "Placeholder for missing invite code")
        premiumInviteCode.text = descriptionLabel.text

        // Private ID: only shown on the owner's account settings page.
        self.myUIDLabel.text = self.tinode.myUid
        premiumUid.text = self.tinode.myUid
        self.myUIDLabel.sizeToFit()

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
        let value: String?
        let message: String
        switch sender.tag {
        case 0:
            value = self.tinode.myUid
            message = NSLocalizedString("ID 已复制", comment: "Toast notification")
        case 1:
            value = accountName
            message = NSLocalizedString("账号名已复制", comment: "Toast notification")
        default:
            value = self.descriptionLabel.text
            message = NSLocalizedString("邀请码已复制", comment: "Toast notification")
        }
        guard let value = value, !value.isEmpty else { return }
        UIPasteboard.general.string = value
        UiUtils.showToast(message: message, level: .info)
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
