//
//  TopicSecurityViewController.swift
//
//  Copyright © 2022-2025 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

class TopicSecurityViewController: UITableViewController {
    private static let kSectionActions = 0
    private static let kSectionActionsDelMessages = 0
    private static let kSectionActionsLeaveGroup = 1
    private static let kSectionActionsLeaveConversation = 2
    private static let kSectionActionsDelTopic = 3
    private static let kSectionActionsDelSavedMessages = 4
    private static let kSectionActionsBlock = 5
    private static let kSectionActionsReport = 6
    private static let kSectionActionsReportGroup = 7

    private static let kSectionPermissions = 1
    private static let kSectionPermissionsMine = 0
    private static let kSectionPermissionsPeer = 1

    private static let kSectionDefaultPermissions = 2
    private static let kSectionDefaultPermissionsAuth = 0
    private static let kSectionDefaultPermissionsAnon = 1

    @IBOutlet weak var actionMyPermissions: UITableViewCell!
    @IBOutlet weak var myPermissionsLabel: UILabel!
    @IBOutlet weak var actionPeerPermissions: UITableViewCell!
    @IBOutlet weak var peerNameLabel: UILabel!
    @IBOutlet weak var peerPermissionsLabel: UILabel!

    @IBOutlet weak var authUsersPermissionsLabel: UILabel!
    @IBOutlet weak var anonUsersPermissionsLabel: UILabel!
    @IBOutlet weak var actionAuthPermissions: UITableViewCell!
    @IBOutlet weak var actionAnonPermissions: UITableViewCell!

    @IBOutlet weak var actionDeleteMessages: UITableViewCell!
    @IBOutlet weak var actionDeleteGroup: UITableViewCell!
    @IBOutlet weak var actionDeleteAll: UITableViewCell!
    @IBOutlet weak var actionLeaveGroup: UITableViewCell!
    @IBOutlet weak var actionLeaveConversation: UITableViewCell!
    @IBOutlet weak var actionBlockContact: UITableViewCell!
    @IBOutlet weak var actionReportContact: UITableViewCell!
    @IBOutlet weak var actionReportGroup: UITableViewCell!

    var topicName = ""
    private var topic: DefaultComTopic!
    private var tinode: Tinode!
    private var isDeletingMessages = false

    // Show row with Peer's permissions (p2p topic)
    private var showPeerPermissions: Bool = false
    // Show section with default topic permissions (manager of a grp topic)
    private var showDefaultPermissions: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "claw.settings.topic.security.screen"
        tableView.accessibilityIdentifier = "claw.settings.topic.security.list"
        actionDeleteMessages.accessibilityIdentifier = "claw.settings.topic.security.delete-messages"
        actionDeleteGroup.accessibilityIdentifier = "claw.settings.topic.security.delete-group"
        actionLeaveGroup.accessibilityIdentifier = "claw.settings.topic.security.leave-group"
        actionLeaveConversation.accessibilityIdentifier = "claw.settings.topic.security.leave-conversation"
        ClawTheme.styleList(tableView, rowHeight: 62)
        tableView.tableHeaderView = ClawTheme.makeStatusHeader(
            title: NSLocalizedString("会话安全设置", comment: "Topic security status title"),
            detail: NSLocalizedString("管理消息、成员权限以及会话的安全操作。", comment: "Topic security status detail"),
            symbolName: "checkmark.shield")
        tableView.contentInset.bottom = 24

        actionMyPermissions.textLabel?.text = NSLocalizedString("我的权限", comment: "My permissions")
        actionPeerPermissions.textLabel?.text = NSLocalizedString("对方权限", comment: "Peer permissions")
        actionAuthPermissions.textLabel?.text = NSLocalizedString("已登录用户", comment: "Authenticated users")
        actionAnonPermissions.textLabel?.text = NSLocalizedString("访客用户", comment: "Anonymous users")
        actionDeleteMessages.textLabel?.text = NSLocalizedString("删除所有消息", comment: "Delete all messages")
        actionDeleteGroup.textLabel?.text = NSLocalizedString("删除群组", comment: "Delete group")
        actionDeleteAll.textLabel?.text = NSLocalizedString("删除已保存消息", comment: "Delete saved messages")
        actionLeaveGroup.textLabel?.text = NSLocalizedString("退出群组", comment: "Leave group")
        actionLeaveConversation.textLabel?.text = NSLocalizedString("离开会话", comment: "Leave conversation")
        actionBlockContact.textLabel?.text = NSLocalizedString("屏蔽联系人", comment: "Block contact")
        actionReportContact.textLabel?.text = NSLocalizedString("举报联系人", comment: "Report contact")
        actionReportGroup.textLabel?.text = NSLocalizedString("举报群组", comment: "Report group")

        ClawTheme.styleTableCell(actionMyPermissions, symbolName: "person.crop.circle")
        ClawTheme.styleTableCell(actionPeerPermissions, symbolName: "person.2")
        ClawTheme.styleTableCell(actionAuthPermissions, symbolName: "person.crop.circle")
        ClawTheme.styleTableCell(actionAnonPermissions, symbolName: "eye.slash")
        ClawTheme.styleTableCell(actionDeleteMessages, symbolName: "trash", destructive: true)
        ClawTheme.styleTableCell(actionDeleteGroup, symbolName: "trash.slash", destructive: true)
        ClawTheme.styleTableCell(actionDeleteAll, symbolName: "trash.slash", destructive: true)
        ClawTheme.styleTableCell(actionLeaveGroup, symbolName: "rectangle.portrait.and.arrow.right", destructive: true)
        ClawTheme.styleTableCell(actionLeaveConversation, symbolName: "rectangle.portrait.and.arrow.right", destructive: true)
        ClawTheme.styleTableCell(actionBlockContact, symbolName: "hand.raised", destructive: true)
        ClawTheme.styleTableCell(actionReportContact, symbolName: "exclamationmark.bubble", destructive: true)
        ClawTheme.styleTableCell(actionReportGroup, symbolName: "exclamationmark.bubble", destructive: true)
        setup()
        reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView else { return }
        if header.frame.width != tableView.bounds.width || header.frame.height != 124 {
            header.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 124)
            tableView.tableHeaderView = header
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        reloadData()
    }

    private func setup() {
        self.tinode = Cache.tinode
        self.topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        guard self.topic != nil else {
            return
        }

        if self.topic.isGrpType {
            showDefaultPermissions = topic.isManager
            showPeerPermissions = false
        } else if self.topic.isSlfType {
            showDefaultPermissions = false
            showPeerPermissions = false
        } else {
            showDefaultPermissions = false
            showPeerPermissions = true
        }

        UiUtils.setupTapRecognizer(
            forView: actionDeleteMessages,
            action: #selector(TopicSecurityViewController.deleteMessagesClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionDeleteGroup,
            action: #selector(TopicSecurityViewController.deleteGroupClicked),
            actionTarget: self, name: "deleteGroup")
        UiUtils.setupTapRecognizer(
            forView: actionDeleteAll,
            action: #selector(TopicSecurityViewController.deleteGroupClicked),
            actionTarget: self, name: "deleteSavedMessages")
        UiUtils.setupTapRecognizer(
            forView: actionLeaveGroup,
            action: #selector(TopicSecurityViewController.leaveGroupClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionLeaveConversation,
            action: #selector(TopicSecurityViewController.leaveConversationClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionBlockContact,
            action: #selector(TopicSecurityViewController.blockContactClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionReportContact,
            action: #selector(TopicSecurityViewController.reportContactClicked),
            actionTarget: self)
        UiUtils.setupTapRecognizer(
            forView: actionReportGroup,
            action: #selector(TopicSecurityViewController.reportGroupClicked),
            actionTarget: self)

        UiUtils.setupTapRecognizer(
            forView: actionMyPermissions,
            action: #selector(TopicSecurityViewController.permissionsTapped),
            actionTarget: self)

        if showPeerPermissions {
            UiUtils.setupTapRecognizer(
                forView: actionPeerPermissions,
                action: #selector(TopicSecurityViewController.permissionsTapped),
                actionTarget: self)
        }

        if showDefaultPermissions {
            UiUtils.setupTapRecognizer(
                forView: actionAuthPermissions,
                action: #selector(TopicSecurityViewController.permissionsTapped),
                actionTarget: self)
            UiUtils.setupTapRecognizer(
                forView: actionAnonPermissions,
                action: #selector(TopicSecurityViewController.permissionsTapped),
                actionTarget: self)
        }
    }

    private func reloadData() {
        let acs = topic.accessMode

        if self.topic.isGrpType {
            authUsersPermissionsLabel?.text = topic.defacs?.getAuth()
            anonUsersPermissionsLabel?.text = topic.defacs?.getAnon()
            myPermissionsLabel?.text = acs?.modeString
            // FIXME: reload just the members section.
            tableView.reloadData()
        } else {
            peerNameLabel?.text = topic.pub?.fn ?? NSLocalizedString("Unknown", comment: "Placeholder for missing user name")
            myPermissionsLabel?.text = acs?.wantString
            let sub = topic.getSubscription(for: self.topic.name)
            peerPermissionsLabel?.text = sub?.acs?.givenString
        }
    }

    @objc func permissionsTapped(sender: UITapGestureRecognizer) {
        switch sender.view { // apparently there is no need for === operator.
        case actionMyPermissions:
            if let acs = topic.accessMode {
                var disabled: String = ""
                if acs.isOwner {
                    // The owner should be able to change any permission except unsetting the 'O'
                    disabled = "O"
                } else {
                    // Allow accepting any of A S D O permissions but don't allow asking for them.
                    let controlled = AcsHelper(str: "ASDO")
                    if let notGiven = AcsHelper.diff(a1: controlled, a2: AcsHelper.and(a1: acs.given, a2: controlled)) {
                        disabled = notGiven.description
                    } else {
                        disabled = "ASDO"
                    }
                }
                UiUtils.showPermissionsEditDialog(over: self, acs: acs.want, callback: { perm in UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: nil, changeType: .updateSelfSub, newPermissions: perm)?.then(onSuccess: self.promiseSuccessHandler) }, disabledPermissions: disabled)
            } else {
                Cache.log.error("Access mode is nil")
            }
        case actionPeerPermissions:
            UiUtils.showPermissionsEditDialog(over: self, acs: topic.getSubscription(for: self.topic.name)?.acs?.given, callback: { perm in UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: self.topic.name, changeType: .updateSub, newPermissions: perm)?.then(onSuccess: self.promiseSuccessHandler) }, disabledPermissions: "ASDO")
        case actionAuthPermissions:
            UiUtils.showPermissionsEditDialog(over: self, acs: topic.defacs?.auth, callback: { perm in UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: nil, changeType: .updateAuth, newPermissions: perm)?.then(onSuccess: self.promiseSuccessHandler) }, disabledPermissions: "O")
        case actionAnonPermissions:
            UiUtils.showPermissionsEditDialog(over: self, acs: topic.defacs?.anon, callback: { perm in UiUtils.handlePermissionsChange(onTopic: self.topic, forUid: nil, changeType: .updateAnon, newPermissions: perm)?.then(onSuccess: self.promiseSuccessHandler) }, disabledPermissions: "O")
        default:
            return
        }
    }

    private func deleteTopic() {
        topic.delete(hard: true).then(
            onSuccess: { _ in
                DispatchQueue.main.async {
                    self.performSegue(withIdentifier: "TopicSecurity2Chats", sender: nil)
                }
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
    }

    private func blockContact() {
        topic.updateMode(uid: nil, update: "-JP").then(
            onSuccess: { _ in
                DispatchQueue.main.async {
                    self.performSegue(withIdentifier: "TopicSecurity2Chats", sender: nil)
                }
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler)
    }

    private func reportTopic(reason: String) {
        blockContact()
        // Create and send spam report.
        let msg = Drafty().attachJSON([
            "action": JSONValue.string("report"),
            "target": JSONValue.string(self.topic.name)
            ])
        _ = Cache.tinode.publish(topic: Tinode.kTopicSys, head: ["mime": .string(Drafty.kJSONMimeType)], content: msg, attachments: nil)
    }

    @objc func deleteGroupClicked(sender: UITapGestureRecognizer) {
        guard topic.isOwner else {
            UiUtils.showToast(message: NSLocalizedString("只有群主可以删除群组", comment: "Toast notification"))
            return
        }
        let isDeleteGroup = (sender.name ?? "") == "deleteGroup"
        let title = isDeleteGroup ? NSLocalizedString("删除群组？", comment: "Alert title") : NSLocalizedString("删除已保存消息？", comment: "Alert title")
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("删除", comment: "Alert action"), style: .destructive,
            handler: { _ in self.deleteTopic() }))
        present(alert, animated: true)
    }

    @objc func deleteMessagesClicked(sender: UITapGestureRecognizer) {
        let handler: (Bool) -> Void = { (hard: Bool) -> Void in
            guard !self.isDeletingMessages else {
                UiUtils.showToast(message: NSLocalizedString("正在删除，请稍候", comment: "Message delete in progress"), level: .info)
                return
            }
            self.isDeletingMessages = true
            self.actionDeleteMessages.isUserInteractionEnabled = false
            self.topic?.delMessages(hard: hard).then(onSuccess: { _ in
                DispatchQueue.main.async {
                    self.isDeletingMessages = false
                    self.actionDeleteMessages.isUserInteractionEnabled = true
                    UiUtils.showToast(message: NSLocalizedString("消息已删除", comment: "Toast notification"), level: .info)
                }
                return nil
            }, onFailure: { err in
                DispatchQueue.main.async {
                    self.isDeletingMessages = false
                    self.actionDeleteMessages.isUserInteractionEnabled = true
                    UiUtils.showToast(message: String(format: NSLocalizedString("删除失败：%@", comment: "Toast notification"), err.localizedDescription))
                }
                return nil
            })
        }

        let alert = UIAlertController(title: NSLocalizedString("删除所有消息？", comment: "Alert title"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Alert action"), style: .cancel, handler: nil))
        if topic.isDeleter {
            alert.addAction(UIAlertAction(
                title: NSLocalizedString("从双方删除", comment: "Alert action qualifier as in 'Delete for all'"), style: .destructive,
                handler: { _ in handler(true) }))
        }
        alert.addAction(UIAlertAction(
            title: topic.isDeleter ? NSLocalizedString("仅从我这里删除", comment: "Alert action 'Delete for me'") : NSLocalizedString("确定", comment: "Alert action"), style: .destructive,
            handler: { _ in handler(false) }))
        present(alert, animated: true)
    }

    @objc func leaveConversationClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("离开会话？", comment: "Alert title"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("离开", comment: "Alert action"), style: .destructive,
            handler: { _ in self.deleteTopic() }))
        present(alert, animated: true)
    }

    @objc func leaveGroupClicked(sender: UITapGestureRecognizer) {
        guard !topic.isOwner else {
            UiUtils.showToast(message: NSLocalizedString("群主不能离开群组", comment: "Toast notification"))
            return
        }

        let alert = UIAlertController(title: NSLocalizedString("离开群组？", comment: "Alert title"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("离开", comment: "Alert action"), style: .destructive,
            handler: { _ in self.deleteTopic() }))
        present(alert, animated: true)
    }

    @objc func blockContactClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("屏蔽联系人？", comment: "Alert action"), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("屏蔽", comment: "Alert action"), style: .destructive,
            handler: { _ in self.blockContact() }))
        present(alert, animated: true)
    }

    @objc func reportContactClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("举报联系人？", comment: "Alert title"), message: NSLocalizedString("同时屏蔽并删除所有消息", comment: "Alert explanation"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("举报", comment: "Alert action"), style: .destructive,
            handler: { _ in self.reportTopic(reason: "TODO") }))
        present(alert, animated: true)
    }

    @objc func reportGroupClicked(sender: UITapGestureRecognizer) {
        let alert = UIAlertController(title: NSLocalizedString("举报群组？", comment: "Alert title"), message: NSLocalizedString("同时屏蔽并删除所有消息", comment: "Alert explanation"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Alert action"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("举报", comment: "Alert action"), style: .destructive,
            handler: { _ in self.reportTopic(reason: "TODO") }))
        present(alert, animated: true)
    }

    private func promiseSuccessHandler(msg: ServerMessage?) throws -> PromisedReply<ServerMessage>? {
        Cache.log.debug("promiseSuccessHandler - update succeseeded")
        DispatchQueue.main.async { self.reloadData() }
        return nil
    }
}

extension TopicSecurityViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

        if section == TopicSecurityViewController.kSectionDefaultPermissions && !showDefaultPermissions {
            return 0
        }
        if section == TopicSecurityViewController.kSectionPermissions && !showPeerPermissions {
            return 1
        }
        return super.tableView(tableView, numberOfRowsInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let tt = self.topic else {
            return super.tableView(tableView, heightForRowAt: indexPath)
        }

        if indexPath.section == TopicSecurityViewController.kSectionActions {
            if indexPath.row == TopicSecurityViewController.kSectionActionsDelMessages && tt.isChannel {
                // Channel readers cannot delete messages
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsLeaveGroup && !tt.isGrpType && !tt.isSlfType {
                // P2P topic, hide [Leave Group]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsLeaveConversation && (tt.isGrpType || tt.isSlfType) {
                // Group topic, hide [Leave Conversation]
                return CGFloat.leastNonzeroMagnitude
            }
            // Hide either [Leave] or [Delete Topic] actions.
            if indexPath.row == TopicSecurityViewController.kSectionActionsLeaveGroup && tt.isOwner {
                // Owner, hide [Leave]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsDelTopic && (!tt.isOwner || tt.isSlfType) {
                // Not an owner or SLF, hide [Delete Group]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsDelSavedMessages && !tt.isSlfType {
                // SLF-specific delete topic.
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsBlock && (tt.isGrpType || tt.isSlfType) {
                // Group topic, hide [Block Contact]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsReport && (tt.isGrpType || tt.isSlfType) {
                // Group topic, hide [Report Contact]
                return CGFloat.leastNonzeroMagnitude
            }
            if indexPath.row == TopicSecurityViewController.kSectionActionsReportGroup && (!tt.isGrpType || tt.isOwner) {
                // P2P topic or the owner, hide [Report Group]
                return CGFloat.leastNonzeroMagnitude
            }
        } else if indexPath.section == TopicSecurityViewController.kSectionPermissions && tt.isSlfType {
            return CGFloat.leastNormalMagnitude
        } else if indexPath.section == TopicSecurityViewController.kSectionDefaultPermissions && tt.isSlfType {
            return CGFloat.leastNormalMagnitude
        }

        return 62
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == TopicSecurityViewController.kSectionDefaultPermissions && !showDefaultPermissions {
            return nil
        } else if section == TopicSecurityViewController.kSectionPermissions && !showPeerPermissions {
            return nil
        }

        switch section {
        case TopicSecurityViewController.kSectionActions:
            return NSLocalizedString("会话操作", comment: "Conversation actions section")
        case TopicSecurityViewController.kSectionPermissions:
            return NSLocalizedString("成员权限", comment: "Member permissions section")
        case TopicSecurityViewController.kSectionDefaultPermissions:
            return NSLocalizedString("默认权限", comment: "Default permissions section")
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == TopicSecurityViewController.kSectionDefaultPermissions && !showDefaultPermissions {
            return CGFloat.leastNormalMagnitude
        } else if section == TopicSecurityViewController.kSectionPermissions && !showPeerPermissions {
            return CGFloat.leastNormalMagnitude
        }

        return 38
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell,
                            forRowAt indexPath: IndexPath) {
        let visibleRows = (0..<tableView.numberOfRows(inSection: indexPath.section)).filter {
            self.tableView(tableView, heightForRowAt: IndexPath(row: $0, section: indexPath.section)) > 1
        }
        let isDanger = indexPath.section == TopicSecurityViewController.kSectionActions
        ClawTheme.styleGroupedCell(
            cell,
            position: ClawTheme.groupedPosition(for: indexPath.row, visibleRows: visibleRows),
            destructive: isDanger)
        cell.contentView.backgroundColor = .clear
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        ClawTheme.normalizeIconButtons(in: cell.contentView)
    }

    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        return 0
    }

    struct AccessModeLabel {
        public static let kColorGrayBorder = UIColor(fromHexCode: 0xff9e9e9e)
        public static let kColorGreenBorder = UIColor(fromHexCode: 0xff4caf50)
        public static let kColorRedBorder = UIColor(fromHexCode: 0xffe57373)
        public static let kColorYellowBorder = UIColor(fromHexCode: 0xffffca28)
        let color: UIColor
        let text: String
    }

    static func getAccessModeLabels(acs: Acs?, status: BaseDb.Status?) -> [AccessModeLabel]? {
        var result = [AccessModeLabel]()
        if let acs = acs {
            if acs.isModeDefined {
                if !acs.isNone {
                    if !acs.isJoiner || (!acs.isWriter && !acs.isReader) {
                        result.append(AccessModeLabel(color: AccessModeLabel.kColorRedBorder, text: "blocked"))
                    } else if acs.isOwner {
                        result.append(AccessModeLabel(color: AccessModeLabel.kColorGreenBorder, text: "owner"))
                    } else if acs.isAdmin {
                        result.append(AccessModeLabel(color: AccessModeLabel.kColorGreenBorder, text: "admin"))
                    } else if !acs.isWriter {
                        result.append(AccessModeLabel(color: AccessModeLabel.kColorYellowBorder, text: "read-only"))
                    } else if !acs.isReader {
                        result.append(AccessModeLabel(color: AccessModeLabel.kColorYellowBorder, text: "write-only"))
                    }
                } else {
                    // The acs.mode is 'N' (none)
                    if !acs.isNoneGiven || acs.isNoneWant {
                        result.append(AccessModeLabel(color: AccessModeLabel.kColorGrayBorder, text: "invited"))
                    } else if acs.isNoneGiven && !acs.isNoneWant {
                        result.append(AccessModeLabel(color: AccessModeLabel.kColorGrayBorder, text: "requested"))
                    }
                }
            }
        }
        if let status = status, status == .queued {
            result.append(AccessModeLabel(color: AccessModeLabel.kColorGrayBorder, text: "pending"))
        }
        return !result.isEmpty ? result : nil
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
