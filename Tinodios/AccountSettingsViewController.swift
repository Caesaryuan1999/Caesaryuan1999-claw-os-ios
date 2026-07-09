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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadData()
    }

    private func setup() {
        self.tinode = Cache.tinode
        self.me = self.tinode.getMeTopic()!
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
