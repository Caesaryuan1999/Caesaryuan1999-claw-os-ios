//
//  NewGroupViewController.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

protocol NewGroupDisplayLogic: AnyObject {
    func presentChat(with topicName: String)
}

class NewGroupViewController: UITableViewController {
    @IBOutlet weak var saveButtonItem: UIBarButtonItem!
    @IBOutlet weak var groupNameTextField: UITextField!
    @IBOutlet weak var privateTextField: UITextField!
    @IBOutlet weak var tagsTextField: TagsEditView!
    @IBOutlet weak var avatarView: RoundImageView!
    @IBOutlet weak var channelSwitch: UISwitch!

    private var selectedContacts: [ContactHolder] = []
    private var selectedUids = Set<String>()
    var selectedMembers: [String] { return selectedUids.map { $0 } }

    private var avatarReceived: Bool = false
    private var isCreatingGroup = false
    private var hasPresentedMemberSelection = false
    private var premiumDetailsBuilt = false
    private let detailsTitleLabel = UILabel()
    private let detailsSubtitleLabel = UILabel()
    private let membersSummaryLabel = UILabel()
    private let premiumCreateButton = UIButton(type: .system)
    private let premiumAvatarEditButton = UIButton(type: .system)

    private lazy var createButtonItem = UIBarButtonItem(
        title: NSLocalizedString("创建群聊", comment: "Button title"),
        style: .done,
        target: self,
        action: #selector(saveButtonClicked(_:)))
    private lazy var fallbackCreateButtonItem = UIBarButtonItem(
        title: NSLocalizedString("创建群聊", comment: "Button title"),
        style: .done,
        target: self,
        action: #selector(saveButtonClicked(_:)))

    private var imagePicker: ImagePicker!

    private func setup() {
        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)
        self.tagsTextField.onVerifyTag = { (_, tag) in
            return Utils.isValidTag(tag: tag)
        }
        if !Cache.isContactSynchronizerActive() {
            Cache.synchronizeContactsPeriodically()
        }

        // Add me to selectedUids and selectedContacts.
        if let myUid = Cache.tinode.myUid {
            selectedContacts = ContactsManager.default.fetchContacts(withUids: [myUid]) ?? []
            if !selectedContacts.isEmpty {
                selectedUids.insert(myUid)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")
        navigationItem.title = NSLocalizedString("创建群聊", comment: "Screen title")
        view.accessibilityIdentifier = "claw.group.create.screen"
        tableView.accessibilityIdentifier = "claw.group.create.form"
        groupNameTextField.accessibilityIdentifier = "claw.group.create.name"
        privateTextField.accessibilityIdentifier = "claw.group.create.private"
        tagsTextField.accessibilityIdentifier = "claw.group.create.tags"
        avatarView.accessibilityIdentifier = "claw.group.create.avatar"
        channelSwitch.accessibilityIdentifier = "claw.group.create.channel"
        createButtonItem.accessibilityIdentifier = "claw.group.create.submit"
        fallbackCreateButtonItem.accessibilityIdentifier = "claw.group.create.submit"
        saveButtonItem.accessibilityIdentifier = "claw.group.create.submit"
        ClawTheme.styleList(tableView, rowHeight: 70)
        tableView.backgroundColor = ClawTheme.background
        tableView.separatorColor = ClawTheme.border
        tableView.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        groupNameTextField.placeholder = NSLocalizedString("Group name", comment: "Group name placeholder")
        ClawTheme.styleTextField(groupNameTextField)
        ClawTheme.styleTextField(privateTextField)
        tagsTextField.backgroundColor = ClawTheme.surface
        tagsTextField.layer.cornerRadius = ClawTheme.inputRadius
        tagsTextField.layer.cornerCurve = .continuous
        tagsTextField.layer.borderWidth = 1
        tagsTextField.layer.borderColor = ClawTheme.border.cgColor
        tagsTextField.clipsToBounds = true
        avatarView.layer.borderWidth = 2
        avatarView.layer.borderColor = ClawTheme.brandSoft.cgColor
        channelSwitch.onTintColor = ClawTheme.primary
        createButtonItem.tintColor = ClawTheme.primary
        fallbackCreateButtonItem.tintColor = ClawTheme.primary
        saveButtonItem.tintColor = ClawTheme.primary
        self.groupNameTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        self.privateTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        UiUtils.dismissKeyboardForTaps(onView: self.view)
        setup()
        rebuildPremiumGroupDetails()
        updateCreateButtons()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView,
           abs(header.frame.width - tableView.bounds.width) > 0.5 {
            header.frame.size.width = tableView.bounds.width
            tableView.tableHeaderView = header
        }
        avatarView.layer.cornerRadius = min(avatarView.bounds.width, avatarView.bounds.height) / 2
        avatarView.clipsToBounds = true
        ClawTheme.normalizeIconButtons(in: view)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.navigationItem.rightBarButtonItem = nil
        self.tabBarController?.navigationItem.rightBarButtonItem = nil
        updateMemberSummary()
        updateCreateButtons()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentMemberSelectionIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if self.tabBarController?.navigationItem.rightBarButtonItem === createButtonItem {
            self.tabBarController?.navigationItem.rightBarButtonItem = nil
        }
        if self.navigationItem.rightBarButtonItem === fallbackCreateButtonItem {
            self.navigationItem.rightBarButtonItem = nil
        }
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return premiumDetailsBuilt ? 0 : 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Section 0: use default.
        // Section 1: always show [+ Add members] then the list of members.
        return section == 0 ? super.tableView(tableView, numberOfRowsInSection: 0) : selectedContacts.count + 1
    }

    // Group members.
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard indexPath.section == 1 && indexPath.row > 0 else { return super.tableView(tableView, cellForRowAt: indexPath) }

        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell

        // Configure the cell...
        let contact = selectedContacts[indexPath.row - 1]

        cell.avatar.set(pub: contact.pub, id: contact.uniqueId, deleted: false)
        cell.title.text = contact.pub?.fn ?? contact.accountName ?? NSLocalizedString("Unnamed member", comment: "Fallback member title")
        cell.title.sizeToFit()
        cell.subtitle.text = contact.subtitle ?? contact.accountName ?? ""
        cell.subtitle.sizeToFit()
        ClawTheme.styleTableCell(cell)

        return cell
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        super.tableView(tableView, willDisplay: cell, forRowAt: indexPath)

        let rowCount = self.tableView(tableView, numberOfRowsInSection: indexPath.section)
        let visibleRows: [Int]
        if indexPath.section == 0 {
            visibleRows = Array(0..<rowCount)
        } else {
            visibleRows = Array(0..<rowCount)
        }
        let position = ClawTheme.groupedPosition(for: indexPath.row, visibleRows: visibleRows)
        ClawTheme.styleGroupedCell(cell, position: position)
        ClawTheme.normalizeIconButtons(in: cell.contentView)
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Hide empty header in the first section.
        return section == 0 ? CGFloat.leastNormalMagnitude : super.tableView(tableView, heightForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Otherwise crash
        return indexPath.section == 0 || indexPath.row == 0 ? super.tableView(tableView, heightForRowAt: indexPath) : 70
    }
    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        // Otherwise crash
        return indexPath.section == 0 || indexPath.row == 0 ? super.tableView(tableView, indentationLevelForRowAt: indexPath) : 0
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "NewGroupToEditMembers" {
            let navigator = segue.destination as! UINavigationController
            let destination = navigator.viewControllers.first as! EditMembersViewController
            destination.delegate = self
        }
    }

    // MARK: - UI event handlers.
    @IBAction func loadAvatarClicked(_ sender: Any) {
        // Get avatar image
        self.imagePicker.present(from: self.view)
    }

    private func presentMemberSelectionIfNeeded() {
        guard !hasPresentedMemberSelection else { return }
        let members = selectedMembers.filter { !Cache.tinode.isMe(uid: $0) }
        guard members.isEmpty else { return }
        hasPresentedMemberSelection = true
        DispatchQueue.main.async { [weak self] in
            self?.performSegue(withIdentifier: "NewGroupToEditMembers", sender: nil)
        }
    }

    private func rebuildPremiumGroupDetails() {
        guard !premiumDetailsBuilt else { return }
        premiumDetailsBuilt = true

        navigationItem.title = NSLocalizedString("设置群资料", comment: "Group profile step title")
        tableView.backgroundColor = ClawTheme.surface
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false

        let width = tableView.bounds.width > 0 ? tableView.bounds.width : UIScreen.main.bounds.width
        let content = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 650))
        content.autoresizingMask = [.flexibleWidth]
        content.backgroundColor = ClawTheme.surface

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: ClawTheme.symbol("chevron.left", pointSize: 18, weight: .semibold),
            style: .plain,
            target: self,
            action: #selector(editMembersButtonTapped))
        navigationItem.leftBarButtonItem?.accessibilityLabel = NSLocalizedString(
            "返回选择成员", comment: "Return to group member selection")

        detailsTitleLabel.text = NSLocalizedString("设置群资料", comment: "Group profile title")
        detailsTitleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        detailsTitleLabel.textColor = ClawTheme.ink
        detailsSubtitleLabel.text = NSLocalizedString("添加群名称和说明，创建后仍可修改", comment: "Group profile subtitle")
        detailsSubtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        detailsSubtitleLabel.textColor = ClawTheme.muted

        avatarView.removeFromSuperview()
        avatarView.layer.borderWidth = 0
        avatarView.backgroundColor = ClawTheme.brandSoft
        if !avatarReceived {
            avatarView.image = ClawTheme.symbol("person.3.fill", pointSize: 34, weight: .medium)
            avatarView.tintColor = ClawTheme.primary
            avatarView.contentMode = .center
        }
        avatarView.isUserInteractionEnabled = true
        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(premiumAvatarTapped))
        avatarView.addGestureRecognizer(avatarTap)

        premiumAvatarEditButton.backgroundColor = ClawTheme.primary
        premiumAvatarEditButton.tintColor = .white
        premiumAvatarEditButton.setImage(
            ClawTheme.symbol("camera.fill", pointSize: 15, weight: .semibold), for: .normal)
        premiumAvatarEditButton.layer.cornerRadius = 20
        premiumAvatarEditButton.layer.cornerCurve = .continuous
        premiumAvatarEditButton.accessibilityLabel = NSLocalizedString("更换群头像", comment: "Change group avatar")
        premiumAvatarEditButton.addTarget(self, action: #selector(premiumAvatarTapped), for: .touchUpInside)

        groupNameTextField.removeFromSuperview()
        groupNameTextField.placeholder = NSLocalizedString("群聊名称", comment: "Group name placeholder")
        privateTextField.removeFromSuperview()
        privateTextField.placeholder = NSLocalizedString("群聊说明（可选）", comment: "Group description placeholder")
        [groupNameTextField, privateTextField].forEach { field in
            field.translatesAutoresizingMaskIntoConstraints = false
            ClawTheme.styleTextField(field)
            field.font = .systemFont(ofSize: 15, weight: .medium)
            field.heightAnchor.constraint(equalToConstant: 56).isActive = true
        }

        membersSummaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
        membersSummaryLabel.textColor = ClawTheme.muted
        membersSummaryLabel.numberOfLines = 2

        ClawTheme.stylePrimaryButton(premiumCreateButton)
        premiumCreateButton.layer.cornerRadius = 8
        premiumCreateButton.setTitle(NSLocalizedString("创建群聊", comment: "Create group button"), for: .normal)
        premiumCreateButton.addTarget(self, action: #selector(saveButtonClicked(_:)), for: .touchUpInside)
        premiumCreateButton.accessibilityIdentifier = "claw.group.create.submit"

        let form = UIStackView(arrangedSubviews: [groupNameTextField, privateTextField, membersSummaryLabel])
        form.axis = .vertical
        form.spacing = 12

        [detailsTitleLabel, detailsSubtitleLabel, avatarView, premiumAvatarEditButton, form, premiumCreateButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }
        NSLayoutConstraint.activate([
            detailsTitleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            detailsTitleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            detailsTitleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            detailsSubtitleLabel.leadingAnchor.constraint(equalTo: detailsTitleLabel.leadingAnchor),
            detailsSubtitleLabel.trailingAnchor.constraint(equalTo: detailsTitleLabel.trailingAnchor),
            detailsSubtitleLabel.topAnchor.constraint(equalTo: detailsTitleLabel.bottomAnchor, constant: 6),

            avatarView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            avatarView.topAnchor.constraint(equalTo: detailsSubtitleLabel.bottomAnchor, constant: 30),
            avatarView.widthAnchor.constraint(equalToConstant: 96),
            avatarView.heightAnchor.constraint(equalToConstant: 96),
            premiumAvatarEditButton.widthAnchor.constraint(equalToConstant: 40),
            premiumAvatarEditButton.heightAnchor.constraint(equalToConstant: 40),
            premiumAvatarEditButton.trailingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 4),
            premiumAvatarEditButton.bottomAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 4),

            form.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            form.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            form.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 34),

            premiumCreateButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            premiumCreateButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            premiumCreateButton.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 28),
            premiumCreateButton.heightAnchor.constraint(equalToConstant: 52)
        ])

        tableView.tableHeaderView = content
        tableView.reloadData()
        updateMemberSummary()
    }

    @objc private func premiumAvatarTapped() {
        loadAvatarClicked(avatarView as Any)
    }

    @objc private func editMembersButtonTapped() {
        performSegue(withIdentifier: "NewGroupToEditMembers", sender: nil)
    }

    private func updateMemberSummary() {
        let count = selectedMembers.filter { !Cache.tinode.isMe(uid: $0) }.count
        membersSummaryLabel.text = String(
            format: NSLocalizedString("已选择 %d 位成员，可返回上一步继续调整", comment: "Selected members summary"), count)
    }

    @IBAction func saveButtonClicked(_ sender: Any) {
        guard !isCreatingGroup else { return }
        let groupName = UiUtils.ensureDataInTextField(groupNameTextField, maxLength: UiUtils.kMaxTitleLength)
        let tinode = Cache.tinode
        let members = selectedMembers.filter {
            ContactsManager.isDirectContactId($0) && !tinode.isMe(uid: $0)
        }
        if members.isEmpty {
            UiUtils.showToast(message: NSLocalizedString("请选择至少一位群成员", comment: "Error message"))
            return
        }
        // Optional
        let privateInfo = String((privateTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(UiUtils.kMaxTitleLength))
        guard !groupName.isEmpty else { return }
        let avatar = avatarReceived ? avatarView.image?.resize(width: CGFloat(UiUtils.kMaxAvatarSize), height: CGFloat(UiUtils.kMaxAvatarSize), clip: true) : nil
        setCreatingGroup(true)
        createGroupTopic(titled: groupName, subtitled: privateInfo, with: tagsTextField.tags, consistingOf: members, withAvatar: avatar, asChannel: channelSwitch.isOn)
    }

    private func setCreatingGroup(_ creating: Bool) {
        isCreatingGroup = creating
        updateCreateButtons()
    }

    private func updateCreateButtons() {
        let count = selectedMembers.filter {
            ContactsManager.isDirectContactId($0) && !Cache.tinode.isMe(uid: $0)
        }.count
        let title = count > 0
            ? String(format: NSLocalizedString("创建群聊 (%d)", comment: "Button title with selected member count"), count)
            : NSLocalizedString("创建群聊", comment: "Button title")
        let buttons: [UIBarButtonItem?] = [createButtonItem, fallbackCreateButtonItem, saveButtonItem]
        buttons.compactMap { $0 }.forEach { button in
            button.title = title
            button.isEnabled = !isCreatingGroup
        }
        premiumCreateButton.isEnabled = !isCreatingGroup && count > 0
        premiumCreateButton.alpha = premiumCreateButton.isEnabled ? 1 : 0.45
        updateMemberSummary()
    }

    private func creationFailed(_ error: Error) {
        DispatchQueue.main.async {
            self.setCreatingGroup(false)
            UiUtils.ToastFailureHandler(err: error)
        }
    }

    /// Show message that no members are selected.
    private func toggleNoSelectedMembersNote(on show: Bool) {
        if show {
            let messageLabel = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: tableView.bounds.height))
            messageLabel.text = NSLocalizedString("没有选择群成员", comment: "Placeholder when no members are selected")
            messageLabel.textColor = .gray
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.font = .preferredFont(forTextStyle: .body)
            messageLabel.sizeToFit()

            tableView.backgroundView = messageLabel
        } else {
            tableView.backgroundView = nil
        }
    }

    private func createGroupTopic(titled name: String, subtitled subtitle: String, with tags: [String]?, consistingOf members: [String], withAvatar avatar: UIImage?, asChannel isChannel: Bool) {
        let topic = DefaultComTopic(in: Cache.tinode, forwardingEventsTo: nil, isChannel: isChannel)

        func finishCreation(memberInviteFailed: Bool) {
            _ = topic.leave()
            DispatchQueue.main.async {
                self.setCreatingGroup(false)
                if memberInviteFailed {
                    UiUtils.showToast(message: NSLocalizedString(
                        "群聊已创建，部分成员添加失败，请在群设置中重试",
                        comment: "Partial group creation warning"))
                }
                self.presentChat(with: topic.name)
            }
        }

        func inviteMember(at index: Int, hadFailure: Bool = false) {
            guard index < members.count else {
                finishCreation(memberInviteFailed: hadFailure)
                return
            }

            topic.invite(user: members[index], in: nil).then(
                onSuccess: { _ in
                    inviteMember(at: index + 1, hadFailure: hadFailure)
                    return nil
                },
                onFailure: { error in
                    Cache.log.error("NewGroupVC - failed to invite a selected member: %@", error.localizedDescription)
                    // Continue with the remaining members. The group is already created,
                    // so retrying the whole form would create a duplicate group.
                    inviteMember(at: index + 1, hadFailure: true)
                    return nil
                })
        }

        func doCreate(pub: TheCard) {
            topic.pub = pub
            topic.priv = ["comment": .string(subtitle)] // No need to use Tinode.kNullValue here
            topic.tags = tags
            topic.subscribe().then(
                onSuccess: { _ in
                    inviteMember(at: 0)
                    return nil
                },
                onFailure: { error in
                    self.creationFailed(error)
                    return nil
                })
        }

        guard let avatar = avatar?.resize(width: UiUtils.kMaxAvatarSize, height: UiUtils.kMaxAvatarSize, clip: true), avatar.size.width >= UiUtils.kMinAvatarSize && avatar.size.height >= UiUtils.kMinAvatarSize else {
            doCreate(pub: TheCard(fn: name))
            return
        }

        if let imageBits = avatar.pixelData(forMimeType: Photo.kDefaultType) {
            if imageBits.count > UiUtils.kMaxInbandAvatarBytes {
                // Sending image out of band.
                Cache.getLargeFileHelper().startAvatarUpload(mimetype: Photo.kDefaultType, data: imageBits, topicId: topic.name, completionCallback: {(srvmsg, error) in
                    guard let error = error else {
                        let thumbnail = avatar.resize(width: UiUtils.kAvatarPreviewDimensions, height: UiUtils.kAvatarPreviewDimensions, clip: true)
                        let photo = Photo(data: thumbnail?.pixelData(forMimeType: Photo.kDefaultType), ref: srvmsg?.ctrl?.getStringParam(for: "url"), width: Int(avatar.size.width), height: Int(avatar.size.height))
                        doCreate(pub: TheCard(fn: name, avatar: photo))
                        return
                    }
                    self.creationFailed(error)
                })
            } else {
                doCreate(pub: TheCard(fn: name, avatar: avatar))
            }
        } else {
            creationFailed(ImageProcessingError.invalidImage)
        }
    }
}

extension NewGroupViewController: NewGroupDisplayLogic {
    func presentChat(with topicName: String) {
        self.presentChatReplacingCurrentVC(with: topicName)
    }
}

extension NewGroupViewController: EditMembersDelegate {
    func editMembersInitialSelection(_: UIView) -> [ContactHolder] {
        return selectedContacts
    }

    func editMembersDidEndEditing(_: UIView, added: [String], removed: [String], completion: @escaping (Error?) -> Void) {
        let validAdded = added.filter {
            ContactsManager.isDirectContactId($0) && !Cache.tinode.isMe(uid: $0)
        }
        let validRemoved = removed.filter { ContactsManager.isDirectContactId($0) }
        guard validAdded.count == added.count, validRemoved.count == removed.count else {
            completion(NSError(
                domain: "app.veilping.clawoschat.group-members",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(
                    "群成员只能选择联系人账号",
                    comment: "Group member type validation error")]))
            return
        }

        let removedIds = Set(validRemoved)
        let proposedIds = Set(selectedUids.filter {
            ContactsManager.isDirectContactId($0) && !Cache.tinode.isMe(uid: $0)
        }).union(validAdded).subtracting(removedIds)
        let addedContacts = ContactsManager.default.fetchContacts(withUids: validAdded) ?? []
        let addedById = Dictionary(uniqueKeysWithValues: addedContacts.compactMap { contact in
            contact.uniqueId.map { ($0, contact) }
        })
        let orderedAdditions = validAdded.compactMap { addedById[$0] }
        let retainedContacts = selectedContacts.filter { contact in
            guard let uid = contact.uniqueId else { return false }
            return !removedIds.contains(uid)
        }
        let newSelection = retainedContacts + orderedAdditions
        let resolvedIds = Set(newSelection.compactMap { $0.uniqueId })

        guard orderedAdditions.count == validAdded.count, resolvedIds == proposedIds else {
            let error = NSError(
                domain: "app.veilping.clawoschat.group-members",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(
                    "成员选择无效，请重试",
                    comment: "Group member selection error")])
            completion(error)
            return
        }

        let previousSelection = selectedContacts
        selectedUids = proposedIds
        selectedContacts = newSelection
        if premiumDetailsBuilt {
            updateCreateButtons()
            updateMemberSummary()
            completion(nil)
            return
        }

        var removedPaths: [IndexPath] = []
        for (index, contact) in previousSelection.enumerated() {
            guard let uid = contact.uniqueId, removedIds.contains(uid) else { continue }
            removedPaths.append(IndexPath(row: index + 1, section: 1))
        }
        let addedPaths = orderedAdditions.indices.map {
            IndexPath(row: retainedContacts.count + $0 + 1, section: 1)
        }

        tableView.beginUpdates()
        self.tableView.deleteRows(at: removedPaths, with: .automatic)
        self.tableView.insertRows(at: addedPaths, with: .automatic)
        tableView.endUpdates()
        updateCreateButtons()
        updateMemberSummary()
        completion(nil)
    }

    func editMembersWillChangeState(_: UIView, uid: String, added: Bool, initiallySelected: Bool) -> Bool {
        return ContactsManager.isDirectContactId(uid) && !Cache.tinode.isMe(uid: uid)
    }
}

extension NewGroupViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard case .image(let image, _, _) = media,
            let image = image?.resize(width: CGFloat(UiUtils.kMaxAvatarSize), height: CGFloat(UiUtils.kMaxAvatarSize), clip: true) else { return }

        self.avatarView.image = image
        self.avatarView.tintColor = nil
        self.avatarView.contentMode = .scaleAspectFill
        avatarReceived = true
    }
}
