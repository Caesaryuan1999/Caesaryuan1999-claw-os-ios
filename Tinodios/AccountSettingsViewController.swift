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
    
    weak var tinode: Tinode!
    weak var me: DefaultMeTopic!

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        tableView.tableFooterView = makeDeviceInfoFooter()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadData()
    }

    private func setup() {
        self.tinode = Cache.tinode
        self.me = self.tinode.getMeTopic()!
    }

    private func makeDeviceInfoFooter() -> UIView {
        let footer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 104))
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.backgroundColor = .secondarySystemGroupedBackground
        control.layer.cornerRadius = 8
        control.accessibilityLabel = NSLocalizedString("device_info", comment: "Phone information")
        control.accessibilityHint = NSLocalizedString("device_info_explained", comment: "Phone information explanation")
        control.accessibilityIdentifier = "account_device_info"
        control.addTarget(self, action: #selector(showDeviceInfo), for: .touchUpInside)

        let iconView = UIImageView(image: UIImage(systemName: "iphone"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = view.tintColor
        iconView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("device_info", comment: "Phone information")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label

        let subtitleLabel = UILabel()
        subtitleLabel.text = NSLocalizedString("device_info_explained", comment: "Phone information explanation")
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 3

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit

        footer.addSubview(control)
        control.addSubview(iconView)
        control.addSubview(labels)
        control.addSubview(chevron)

        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            control.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
            control.topAnchor.constraint(equalTo: footer.topAnchor, constant: 12),
            control.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -12),
            iconView.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 34),
            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 16),
            labels.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),
            chevron.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -18),
            chevron.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10)
        ])
        return footer
    }

    @objc private func showDeviceInfo() {
        let deviceModel = UIDevice.current.model
        let operatingSystem = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let appVersion = build == "-" ? version : "\(version) (\(build))"
        let languageIdentifier = Locale.preferredLanguages.first ?? Locale.current.identifier
        let currentLanguage = Locale.current.localizedString(forIdentifier: languageIdentifier) ?? languageIdentifier

        let lines = [
            "\(NSLocalizedString("device_model", comment: "Device model")): \(deviceModel)",
            "\(NSLocalizedString("operating_system", comment: "Operating system")): \(operatingSystem)",
            "\(NSLocalizedString("app_version", comment: "App version")): \(appVersion)",
            "\(NSLocalizedString("current_language", comment: "Current language")): \(currentLanguage)"
        ]
        let copyValue = lines.joined(separator: "\n")
        let message = copyValue + "\n\n" + NSLocalizedString("privacy_device_info", comment: "Device information privacy note")
        let alert = UIAlertController(
            title: NSLocalizedString("device_info", comment: "Phone information"),
            message: message,
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
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("close", comment: "Close"),
            style: .cancel))
        present(alert, animated: true)
    }

    private func reloadData() {
        let accountName = AccountNames.fromTags(me.tags)
        // Title.
        self.userNameLabel.text = AccountNames.contactDisplayName(displayName: me.pub?.fn,
                                                                  accountName: accountName,
                                                                  userId: self.tinode.myUid)

        // Avatar.
        self.avatarImageView.set(pub: me.pub, id: self.tinode.myUid, deleted: false)
        self.avatarImageView.letterTileFont = self.avatarImageView.letterTileFont.withSize(CGFloat(50))

        self.descriptionLabel.text = me.creds?.first(where: { $0.meth == ClawAuthInput.inviteCredentialMethod })?.val ??
            NSLocalizedString("邀请码不可用", comment: "Placeholder for missing invite code")

        // Private ID: only shown on the owner's account settings page.
        self.myUIDLabel.text = self.tinode.myUid
        self.myUIDLabel.sizeToFit()

        self.aliasLabel.text = accountName ?? NSLocalizedString("未设置", comment: "Placeholder for missing account name")
        self.aliasLabel.sizeToFit()
    }

    @IBAction func copyTopicValue(_ sender: UIButton) {
        let accountName = AccountNames.fromTags(me.tags)
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
        if indexPath.section == AccountSettingsViewController.kSectionPersonal {
            if (indexPath.row == AccountSettingsViewController.kPersonalVerified && !me.isVerified) ||
                (indexPath.row == AccountSettingsViewController.kPersonalStaff && !me.isStaffManaged) ||
                (indexPath.row == AccountSettingsViewController.kPersonalDanger && !me.isDangerous) {
                return CGFloat.leastNonzeroMagnitude
            }
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        if indexPath.section == AccountSettingsViewController.kSectionBasic {
            // Hide separator lines in the top sections.
            cell.separatorInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: UIScreen.main.bounds.width)
        }
        return cell
    }
}
