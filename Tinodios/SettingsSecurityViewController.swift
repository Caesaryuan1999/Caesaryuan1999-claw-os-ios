//
//  SettingsSecurityViewController.swift
//
//  Copyright © 2020-2022 Tinode LLC. All rights reserved.
//

import TinodeSDK
import TinodiosDB
import UIKit

class SettingsSecurityViewController: UITableViewController {
    private let submissionGate = ClawSubmissionGate()
    @IBOutlet weak var authUsersPermissions: UITableViewCell!
    @IBOutlet weak var anonUsersPermissions: UITableViewCell!
    @IBOutlet weak var authPermissionsLabel: UILabel!
    @IBOutlet weak var anonPermissionsLabel: UILabel!

    @IBOutlet weak var actionChangePassword: UITableViewCell!
    @IBOutlet weak var actionLogOut: UITableViewCell!
    @IBOutlet weak var actionDeleteAccount: UITableViewCell!

    @IBOutlet weak var actionBlockedContacts: UITableViewCell!

    weak var tinode: Tinode!
    weak var me: DefaultMeTopic!

    private let securityRowLeadingInset: CGFloat = 30
    private let securityRowTrailingInset: CGFloat = 18
    private let securityRowIconColumnWidth: CGFloat = 40
    private let securityRowIconSize = CGSize(width: 28, height: 28)

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        reloadData()
    }

    private func setup() {
        title = NSLocalizedString("安全", comment: "Security settings title")
        view.backgroundColor = ClawTheme.background
        ClawTheme.styleList(tableView, rowHeight: 62)
        tableView.tableHeaderView = ClawTheme.makeStatusHeader(
            title: NSLocalizedString("账号已受保护", comment: "Security status title"),
            detail: NSLocalizedString("密码、访问权限和屏蔽名单均由账号安全中心管理。", comment: "Security status detail"),
            symbolName: "checkmark.shield")
        tableView.tableFooterView = makeDeviceInfoFooter()
        tableView.contentInset.bottom = 24

        authUsersPermissions.textLabel?.text = NSLocalizedString("已登录用户", comment: "Authenticated users")
        anonUsersPermissions.textLabel?.text = NSLocalizedString("访客用户", comment: "Anonymous users")
        actionChangePassword.textLabel?.text = NSLocalizedString("修改密码", comment: "Change password")
        actionBlockedContacts.textLabel?.text = NSLocalizedString("已屏蔽联系人", comment: "Blocked contacts")
        actionDeleteAccount.textLabel?.text = NSLocalizedString("删除账号", comment: "Delete account")

        configureSecurityCell(authUsersPermissions, title: "已登录用户", symbolName: "person.crop.circle",
                              detail: authPermissionsLabel.text)
        configureSecurityCell(anonUsersPermissions, title: "访客用户", symbolName: "eye.slash",
                              detail: anonPermissionsLabel.text)
        configureSecurityCell(actionChangePassword, title: "修改密码", symbolName: "key")
        configureSecurityCell(actionBlockedContacts, title: "已屏蔽联系人", symbolName: "hand.raised")
        configureSecurityCell(actionDeleteAccount, title: "删除账号", symbolName: "trash", destructive: true)

        // Logout is presented on the account overview screen. Keep the old static
        // cell connected for backwards-compatible storyboards, but remove it here.
        actionLogOut.isHidden = true
        actionLogOut.isUserInteractionEnabled = false
        authPermissionsLabel.textColor = ClawTheme.muted
        anonPermissionsLabel.textColor = ClawTheme.muted

        self.tinode = Cache.tinode
        self.me = self.tinode.getMeTopic()!

        UiUtils.setupTapRecognizer(
            forView: authUsersPermissions,
            action: #selector(SettingsSecurityViewController.permissionsTapped),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: anonUsersPermissions,
            action: #selector(SettingsSecurityViewController.permissionsTapped),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionChangePassword,
            action: #selector(SettingsSecurityViewController.changePasswordClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionLogOut,
            action: #selector(SettingsSecurityViewController.logoutClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionDeleteAccount,
            action: #selector(SettingsSecurityViewController.deleteAccountClicked),
            actionTarget: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView,
           header.frame.width != tableView.bounds.width || header.frame.height != 124 {
            header.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 124)
            tableView.tableHeaderView = header
        }
        if let footer = tableView.tableFooterView,
           footer.frame.width != tableView.bounds.width || footer.frame.height != 104 {
            footer.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 104)
            tableView.tableFooterView = footer
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 && indexPath.row == 1 {
            return .leastNonzeroMagnitude
        }
        return 62
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return NSLocalizedString("账号操作", comment: "Account actions section")
        case 1:
            return NSLocalizedString("访问控制", comment: "Access controls section")
        case 2:
            return NSLocalizedString("隐私保护", comment: "Privacy protection section")
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell,
                            forRowAt indexPath: IndexPath) {
        let visibleRows = (0..<tableView.numberOfRows(inSection: indexPath.section)).filter {
            self.tableView(tableView, heightForRowAt: IndexPath(row: $0, section: indexPath.section)) > 1
        }
        ClawTheme.styleGroupedCell(
            cell,
            position: ClawTheme.groupedPosition(for: indexPath.row, visibleRows: visibleRows),
            destructive: cell === actionDeleteAccount)
        cell.contentView.backgroundColor = .clear
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        ClawTheme.normalizeIconButtons(in: cell.contentView)
    }

    private func configureSecurityCell(_ cell: UITableViewCell, title: String, symbolName: String,
                                       detail: String? = nil, destructive: Bool = false,
                                       enabled: Bool = true) {
        var configuration = UIListContentConfiguration.valueCell()
        configuration.text = NSLocalizedString(title, comment: "Security settings row title")
        configuration.secondaryText = detail
        configuration.image = ClawTheme.symbol(symbolName, pointSize: 24, weight: .medium)
        configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: securityRowLeadingInset,
            bottom: 0,
            trailing: securityRowTrailingInset)
        configuration.imageProperties.reservedLayoutSize = CGSize(
            width: securityRowIconColumnWidth,
            height: securityRowIconSize.height)
        configuration.imageProperties.maximumSize = securityRowIconSize
        configuration.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 24,
            weight: .medium,
            scale: .medium)
        configuration.imageProperties.tintColor = enabled
            ? (destructive ? ClawTheme.danger : ClawTheme.primary)
            : ClawTheme.muted
        configuration.textProperties.font = .systemFont(ofSize: 16, weight: .medium)
        configuration.textProperties.color = enabled
            ? (destructive ? ClawTheme.danger : ClawTheme.ink)
            : ClawTheme.muted
        configuration.textProperties.adjustsFontForContentSizeCategory = true
        configuration.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        configuration.secondaryTextProperties.color = ClawTheme.muted
        configuration.secondaryTextProperties.adjustsFontForContentSizeCategory = true

        // The storyboard imageView/textLabel use UIKit's legacy layout, whose
        // icon frame is not aware of the grouped card's 18pt inset. Hide those
        // legacy subviews and let the iOS 14 content configuration own the row.
        cell.imageView?.isHidden = true
        cell.textLabel?.isHidden = true
        cell.detailTextLabel?.isHidden = true
        cell.contentConfiguration = configuration
        cell.isUserInteractionEnabled = enabled
        cell.accessibilityLabel = NSLocalizedString(title, comment: "Security settings row title")
        cell.accessibilityValue = detail
    }

    private func reloadData() {
        // Permissions.
        let authPermissions = me.defacs?.getAuth() ?? ""
        let anonPermissions = me.defacs?.getAnon() ?? ""
        self.authPermissionsLabel.text = authPermissions
        self.anonPermissionsLabel.text = anonPermissions
        configureSecurityCell(authUsersPermissions, title: "已登录用户", symbolName: "person.crop.circle",
                              detail: authPermissions)
        configureSecurityCell(anonUsersPermissions, title: "访客用户", symbolName: "eye.slash",
                              detail: anonPermissions)

        if self.tinode.countFilteredTopics(filter: { topic in return topic.topicType.matches(TopicType.user) && !topic.isJoiner }) == 0 {
            // No blocked contacts, disable cell.
            configureSecurityCell(actionBlockedContacts, title: "已屏蔽联系人", symbolName: "hand.raised", enabled: false)
            self.actionBlockedContacts.accessoryType = .none
        } else {
            // Some blocked contacts, enable cell.
            configureSecurityCell(actionBlockedContacts, title: "已屏蔽联系人", symbolName: "hand.raised")
            self.actionBlockedContacts.accessoryType = .disclosureIndicator
        }
    }

    private func getAcsAndPermissionsChangeType(for sender: UIView) -> (AcsHelper?, UiUtils.PermissionsChangeType?) {
        if sender === authUsersPermissions {
            return (me.defacs?.auth, .updateAuth)
        }
        if sender === anonUsersPermissions {
            return (me.defacs?.anon, .updateAnon)
        }
        return (nil, nil)
    }

    @objc
    func permissionsTapped(sender: UITapGestureRecognizer) {
        guard let v = sender.view else {
            Cache.log.debug("SettingsSecurityVC - permissions tap from no sender view... quitting")
            return
        }
        let (acs, changeTypeOptional) = getAcsAndPermissionsChangeType(for: v)
        guard let acsUnwrapped = acs, let changeType = changeTypeOptional else {
            Cache.log.debug("SettingsSecurityVC - permissionsTapped: could not get acs")
            return
        }
        UiUtils.showPermissionsEditDialog(over: self, acs: acsUnwrapped, callback: { permissions in
            UiUtils.handlePermissionsChange(onTopic: self.me, forUid: nil, changeType: changeType, newPermissions: permissions)?.then(
                onSuccess: { _ in
                    DispatchQueue.main.async { self.reloadData() }
                        return nil
                }
            )
        }, disabledPermissions: "ODS")
    }

    @objc func changePasswordClicked(sender: UITapGestureRecognizer) {
        presentPasswordChangeAlert()
    }

    private func presentPasswordChangeAlert(initialPassword: String = "", initialConfirmation: String = "") {
        let alert = UIAlertController(title: NSLocalizedString("修改密码", comment: "Alert title"),
                                      message: NSLocalizedString("请输入两遍新密码（12–64 位英文字母、数字或符号，不含空格）。修改成功后需要重新登录。", comment: "Alert prompt"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: ""), style: .cancel, handler: nil))
        alert.addTextField(configurationHandler: { textField in
            textField.placeholder = NSLocalizedString("新密码", comment: "Alert prompt")
            textField.textContentType = .newPassword
            textField.text = initialPassword
            textField.showSecureEntrySwitch()
        })
        alert.addTextField(configurationHandler: { textField in
            textField.placeholder = NSLocalizedString("再次输入新密码", comment: "Alert prompt")
            textField.textContentType = .newPassword
            textField.text = initialConfirmation
            textField.showSecureEntrySwitch()
        })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("确定", comment: ""), style: .default,
            handler: { _ in
                let newPassword = alert.textFields?.first?.text ?? ""
                let repeatedPassword = alert.textFields?.dropFirst().first?.text ?? ""
                self.updatePassword(with: newPassword, repeatedPassword: repeatedPassword,
                                    retryOnFailure: true)
            }))
        self.present(alert, animated: true)
    }

    private func makeDeviceInfoFooter() -> UIView {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 104))
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        ClawTheme.styleCard(control)
        control.accessibilityLabel = NSLocalizedString("device_info", comment: "Phone information")
        control.accessibilityHint = NSLocalizedString("device_info_explained", comment: "Phone information explanation")
        control.accessibilityIdentifier = "security_device_info"
        control.addTarget(self, action: #selector(showDeviceInfo), for: .touchUpInside)

        let iconBox = UIView()
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        iconBox.backgroundColor = ClawTheme.brandSoft
        iconBox.layer.cornerRadius = 12
        iconBox.layer.cornerCurve = .continuous

        let icon = UIImageView(image: ClawTheme.symbol("iphone", pointSize: ClawTheme.iconStandard, weight: .medium))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = ClawTheme.primary
        icon.contentMode = .center
        iconBox.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("device_info", comment: "Phone information")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = ClawTheme.ink

        let subtitleLabel = UILabel()
        subtitleLabel.text = NSLocalizedString("device_info_explained", comment: "Phone information explanation")
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = ClawTheme.muted
        subtitleLabel.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 3

        let chevron = UIImageView(image: ClawTheme.symbol("chevron.right", pointSize: ClawTheme.iconCompact,
                                                          weight: .semibold))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = ClawTheme.muted
        chevron.contentMode = .center

        footer.addSubview(control)
        control.addSubview(iconBox)
        control.addSubview(labels)
        control.addSubview(chevron)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 18),
            control.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -18),
            control.topAnchor.constraint(equalTo: footer.topAnchor, constant: 12),
            control.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -12),
            iconBox.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 14),
            iconBox.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: 42),
            iconBox.heightAnchor.constraint(equalToConstant: 42),
            icon.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 14),
            labels.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            chevron.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 16),
            chevron.heightAnchor.constraint(equalToConstant: 20)
        ])
        return footer
    }

    @objc private func showDeviceInfo() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let appVersion = build == "-" ? version : "\(version) (\(build))"
        let languageIdentifier = Locale.preferredLanguages.first ?? Locale.current.identifier
        let currentLanguage = Locale.current.localizedString(forIdentifier: languageIdentifier) ?? languageIdentifier
        let lines = [
            "\(NSLocalizedString("device_model", comment: "Device model")): \(UIDevice.current.model)",
            "\(NSLocalizedString("operating_system", comment: "Operating system")): \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "\(NSLocalizedString("app_version", comment: "App version")): \(appVersion)",
            "\(NSLocalizedString("current_language", comment: "Current language")): \(currentLanguage)"
        ]
        let copyValue = lines.joined(separator: "\n")
        let alert = UIAlertController(
            title: NSLocalizedString("device_info", comment: "Phone information"),
            message: copyValue + "\n\n" + NSLocalizedString("privacy_device_info", comment: "Privacy note"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("copy_info", comment: "Copy phone information"),
            style: .default,
            handler: { _ in
                UIPasteboard.general.string = copyValue
                UiUtils.showToast(
                    message: NSLocalizedString("device_info_copied", comment: "Device information copied"),
                    level: .info)
            }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("close", comment: "Close"), style: .cancel))
        present(alert, animated: true)
    }

    @objc func logoutClicked(sender: UITapGestureRecognizer) {
        guard let owner = tinode, Cache.isCurrent(owner) else { return }
        let uid = owner.myUid
        let generation = Cache.sessionGeneration
        let alert = UIAlertController(title: "退出登录",
            message: "退出后需重新登录。本机待发送和发送结果待确认的消息将保留。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出登录", style: .destructive, handler: { [weak self] _ in
            self?.logout(owner: owner, uid: uid, generation: generation)
        }))
        present(alert, animated: true)
    }

    @objc func deleteAccountClicked(sender: UITapGestureRecognizer) {
        guard let owner = tinode, Cache.isCurrent(owner) else { return }
        let uid = owner.myUid
        let generation = Cache.sessionGeneration
        let alert = UIAlertController(title: nil, message: NSLocalizedString("确定要删除账号？此操作无法撤销。", comment: "Warning in delete account alert"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: ""), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("删除", comment: "Alert action"), style: .default,
            handler: { [weak self] _ in
                self?.deleteAccount(owner: owner, uid: uid, generation: generation)
            }))
        present(alert, animated: true)
    }

    private func updatePassword(with newPassword: String, repeatedPassword: String,
                                retryOnFailure: Bool) {
        guard let owner = tinode, Cache.isCurrent(owner), owner.isConnectionAuthenticated else { return }
        guard ClawIdentityInput.newPasswordIsValid(newPassword) else {
            UiUtils.showToast(message: ClawIdentityError.invalidPassword.message)
            presentPasswordChangeAlert()
            return
        }
        switch ClawAuthFormValidation.validatePasswordChange(password: newPassword, confirmation: repeatedPassword) {
        case .ok:
            break
        case .passwordRequired, .passwordPolicy:
            DispatchQueue.main.async {
                UiUtils.showToast(message: NSLocalizedString("密码太短", comment: "Error message"))
                self.presentPasswordChangeAlert(initialPassword: newPassword,
                                                initialConfirmation: repeatedPassword)
            }
            return
        case .passwordMismatch:
            DispatchQueue.main.async {
                UiUtils.showToast(message: NSLocalizedString("两次输入的密码不一致", comment: "Error message"))
                self.presentPasswordChangeAlert(initialPassword: newPassword,
                                                initialConfirmation: repeatedPassword)
            }
            return
        default:
            return
        }
        guard submissionGate.begin() else { return }
        actionChangePassword.isUserInteractionEnabled = false
        owner.updateAccountBasic(uid: nil, username: nil, password: newPassword)
            .then(onSuccess: { [weak self] msg in
                self?.finishPasswordSubmission()
                DispatchQueue.main.async {
                    guard Cache.isCurrent(owner) else { return }
                    if let ctrl = msg?.ctrl, (200..<300).contains(ctrl.code) {
                        // AUTH server has advanced the credential epoch; old token/SID is no longer usable.
                        UiUtils.logoutAndRouteToLoginVC(ifCurrent: owner)
                        UiUtils.showToast(message: "密码已更新，请重新登录", level: .info)
                    } else {
                        // A malformed/missing ACK cannot prove the password was not changed.
                        UiUtils.logoutAndRouteToLoginVC(ifCurrent: owner)
                        UiUtils.showToast(message: "密码修改结果未确认，请返回登录页尝试新密码；若无法登录，可找回密码。")
                    }
                }
                return nil
            }, onFailure: { [weak self] error in
                self?.finishPasswordSubmission()
                DispatchQueue.main.async {
                    guard Cache.isCurrent(owner) else { return }
                    var definitelyRejected = false
                    if let failure = error as? TinodeError {
                        switch failure {
                        case .requestNotSent, .notConnected:
                            definitelyRejected = true
                        case let .serverResponseError(code, _, _):
                            definitelyRejected = (400..<500).contains(code) && code != 408 && code != 401
                        default: break
                        }
                    }
                    if definitelyRejected {
                        UiUtils.showToast(message: ClawAuthErrorMessages.passwordChangeMessage(for: error))
                        if retryOnFailure { self?.presentPasswordChangeAlert() }
                    } else {
                        // No automatic repeat: the server may have committed before the connection closed.
                        UiUtils.logoutAndRouteToLoginVC(ifCurrent: owner)
                        UiUtils.showToast(message: "密码修改结果未确认，请返回登录页尝试新密码；若无法登录，可找回密码。")
                    }
                }
                return nil
            })
    }

    private func finishPasswordSubmission() {
        submissionGate.finish()
        DispatchQueue.main.async {
            self.actionChangePassword.isUserInteractionEnabled = true
        }
    }

    private func logout(owner: Tinode, uid: String?, generation: UInt64) {
        guard Cache.sessionGeneration == generation, owner.myUid == uid, Cache.isCurrent(owner) else { return }
        Cache.log.info("SettingsSecurityVC - logging out")
        UiUtils.logoutAndRouteToLoginVC(ifCurrent: owner)
    }

    private func deleteAccount(owner: Tinode, uid: String?, generation: UInt64) {
        guard Cache.sessionGeneration == generation, owner.myUid == uid, Cache.isCurrent(owner) else { return }
        Cache.log.info("SettingsSecurityVC - deleting account")
        owner.delCurrentUser(hard: true)
            .thenApply { _ in
                DispatchQueue.main.async {
                    // The SDK already retires owner on successful deletion.
                    // Slot identity, not active state or a new Cache.tinode, controls cleanup.
                    UiUtils.logoutAndRouteToLoginVC(ifCurrent: owner)
                }
                return nil
            }
            .thenCatch { error in
                DispatchQueue.main.async {
                    guard Cache.sessionGeneration == generation, owner.myUid == uid, Cache.isCurrent(owner) else { return }
                    UiUtils.ToastFailureHandler(err: error)
                }
                return nil
            }
    }
}
