//
//  AccountGeneralSettingsViewController.swift
//
//  Copyright © 2020-2025 Tinode LLC. All rights reserved.
//

import PhoneNumberKit
import TinodeSDK
import UIKit

class AccountGeneralSettingsViewController: UITableViewController {
    // Container for passing credentials to CredentialsChangeViewController.
    private struct CredentialContainer {
        let currentCred: Credential
        let newCred: Credential?
    }

    private static let kSectionPersonal = 0
    // Avatar = 0
    private static let kPersonalName = 1
    // Keep the legacy editing outlet hidden. Public CLAW号 is a separate read-only row.
    private static let kPersonalAlias = 2
    private static let kPersonalDescription = 3

    private static let kSectionContacts = 1

    private static let kDescriptionPlaceholder = NSLocalizedString("说明（可选）", comment: "Placeholder for missing user self-description")
    
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var aliasTextField: UITextField!
    @IBOutlet weak var descriptionTextView: UITextView!
    @IBOutlet weak var avatarImage: RoundImageView!
    @IBOutlet weak var loadAvatarButton: UIButton!

    private let publicIdentifier = UILabel()
    private let phoneIdentity = UILabel()
    private let emailIdentity = UILabel()
    private let saveProfileButton = UIButton(type: .system)

    weak var tinode: Tinode!
    weak var me: DefaultMeTopic!
    private var imagePicker: ImagePicker!

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        reloadData()
    }

    private func setup() {
        title = NSLocalizedString("个人资料", comment: "Account general settings title")
        view.backgroundColor = ClawTheme.background
        ClawTheme.styleList(tableView, rowHeight: UITableView.automaticDimension)
        self.tinode = Cache.tinode
        self.me = self.tinode.getMeTopic()!

        ClawTheme.styleTextField(nameTextField)
        nameTextField.delegate = self
        nameTextField.tag = AccountGeneralSettingsViewController.kPersonalName

        ClawTheme.styleTextField(aliasTextField)
        aliasTextField.delegate = self
        aliasTextField.tag = AccountGeneralSettingsViewController.kPersonalAlias
        aliasTextField.isEnabled = false
        aliasTextField.isHidden = true

        ClawTheme.styleTextView(descriptionTextView)
        descriptionTextView.delegate = self
        descriptionTextView.tag = AccountGeneralSettingsViewController.kPersonalDescription

        avatarImage.layer.borderWidth = 2
        avatarImage.layer.borderColor = ClawTheme.border.cgColor
        ClawTheme.styleRoundedIconButton(loadAvatarButton, symbolName: "camera.fill")

        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)
        installProfileForm()
    }

    private func installProfileForm() {
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = nil
        tableView.separatorStyle = .none
        view.accessibilityIdentifier = "claw.profile.screen"
        let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 650))
        header.backgroundColor = ClawTheme.background
        // Retain the real storyboard inputs and their delegates while moving them into the adaptive form.
        let nameInput: UITextField = nameTextField
        let noteInput: UITextView = descriptionTextView
        let avatar: RoundImageView = avatarImage
        let avatarButton: UIButton = loadAvatarButton
        for control in [nameInput, noteInput, avatar, avatarButton] as [UIView] {
            control.removeFromSuperview()
            NSLayoutConstraint.deactivate(control.constraints.filter {
                $0.firstAttribute == .height || $0.firstAttribute == .width
            })
            control.translatesAutoresizingMaskIntoConstraints = false
        }
        nameInput.font = ClawTheme.font(16)
        nameInput.adjustsFontForContentSizeCategory = true
        nameInput.accessibilityLabel = "昵称"
        nameInput.accessibilityIdentifier = "claw.profile.nickname"
        nameInput.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        noteInput.font = ClawTheme.font(16)
        noteInput.adjustsFontForContentSizeCategory = true
        noteInput.accessibilityLabel = "个人简介"
        noteInput.isScrollEnabled = false
        noteInput.heightAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        avatar.widthAnchor.constraint(equalToConstant: 48).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 48).isActive = true
        avatarButton.setImage(nil, for: .normal)
        avatarButton.setTitle("更换头像", for: .normal)
        avatarButton.backgroundColor = .clear
        avatarButton.titleLabel?.font = ClawTheme.font(13)
        avatarButton.titleLabel?.adjustsFontForContentSizeCategory = true
        avatarButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        avatarButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        avatarButton.accessibilityLabel = "更换头像"
        let avatarRow = UIStackView(arrangedSubviews: [
            ClawProfileLayout.label("头像", size: 16, color: ClawTheme.ink), UIView(), avatar, avatarButton
        ])
        avatarRow.alignment = .center
        avatarRow.spacing = 8
        avatarRow.backgroundColor = ClawTheme.surface
        avatarRow.layer.cornerRadius = 12
        avatarRow.isLayoutMarginsRelativeArrangement = true
        avatarRow.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 12)

        let publicRow = ClawProfileLayout.valueRow(title: "CLAW号", value: publicIdentifier)
        publicRow.isUserInteractionEnabled = true
        publicRow.isAccessibilityElement = true
        publicRow.accessibilityTraits = .button
        publicRow.accessibilityLabel = "CLAW号，点按复制"
        publicRow.accessibilityIdentifier = "claw.profile.public-id"
        publicRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(copyPublicIdentifier)))
        let phoneRow = ClawProfileLayout.valueRow(title: "手机号", value: phoneIdentity)
        let emailRow = ClawProfileLayout.valueRow(title: "邮箱", value: emailIdentity)
        for row in [phoneRow, emailRow] {
            row.accessibilityHint = "更换手机号或邮箱暂未开放"
        }
        ClawTheme.stylePrimaryButton(saveProfileButton)
        saveProfileButton.setTitle("保存资料", for: .normal)
        saveProfileButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        saveProfileButton.accessibilityIdentifier = "claw.profile.save"
        saveProfileButton.addTarget(self, action: #selector(doneEditingClicked(_:)), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [
            avatarRow, ClawProfileLayout.label("昵称", size: 16, color: ClawTheme.ink), nameInput,
            ClawProfileLayout.label("让联系人更容易认出你", size: 12), publicRow, phoneRow, emailRow,
            ClawProfileLayout.label("手机号与邮箱用于登录，不会在公开资料中显示。更换手机号或邮箱暂未开放。", size: 14),
            ClawProfileLayout.label("个人简介", size: 16, color: ClawTheme.ink), noteInput, saveProfileButton
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -24)
        ])
        tableView.tableHeaderView = header
        ClawProfileLayout.fitHeader(in: tableView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ClawProfileLayout.fitHeader(in: tableView)
    }

    @objc private func copyPublicIdentifier() {
        guard let value = AccountNames.fromTags(me.tags) else {
            UiUtils.showToast(message: "暂未设置 CLAW号"); return
        }
        UIPasteboard.general.string = value
        UiUtils.showToast(message: "CLAW号已复制", level: .info)
    }

    private func identitySummary(method: String) -> String {
        guard let credentials = me.creds else { return "暂未获取" }
        guard let credential = credentials.first(where: { $0.meth == method && $0.isDone }) ??
                credentials.first(where: { $0.meth == method }),
              let value = credential.val, !value.isEmpty else { return "未绑定" }
        return value + (credential.isDone ? " · 已验证" : " · 未验证")
    }

    private func reloadData() {
        // Title.
        self.nameTextField.text = me.pub?.fn

        aliasTextField.text = nil
        publicIdentifier.text = AccountNames.fromTags(me.tags) ?? "暂未设置"
        publicIdentifier.superview?.accessibilityValue = publicIdentifier.text
        phoneIdentity.text = identitySummary(method: "tel")
        emailIdentity.text = identitySummary(method: "email")

        // Description (note)
        if let note = me.pub?.note {
            self.descriptionTextView.text = note
            self.descriptionTextView.textColor = UIColor.secondaryLabel
        } else {
            self.descriptionTextView.text = AccountGeneralSettingsViewController.kDescriptionPlaceholder
            self.descriptionTextView.textColor = UIColor.placeholderText
        }

        // Avatar.
        self.avatarImage.set(pub: me.pub, id: self.tinode.myUid, deleted: false)
        self.avatarImage.letterTileFont = self.avatarImage.letterTileFont.withSize(CGFloat(20))

        // Note: tableView.reloadSections() would be better but
        // it makes the [Add another] contact button disappear.
        // Likely due to this: https://stackoverflow.com/questions/3132135/initally-visible-cells-gets-invisible-after-calling-reloadsectionswithrowanimat
        self.tableView.reloadData()
    }

    @IBAction func loadAvatarClicked(_ sender: Any) {
        imagePicker.present(from: self.view)
    }


    @IBAction func doneEditingClicked(_ sender: Any) {
        guard saveProfileButton.isEnabled else { return }
        view.endEditing(true)
        var pub: TheCard? = nil
        if let name = nameTextField.text, name != me.pub?.fn {
            pub = TheCard(fn: name)
        }

        let desc = descriptionTextView.text
        if desc != me.pub?.note {
            pub = pub ?? TheCard()
            if (desc ?? "").isEmpty || desc == AccountGeneralSettingsViewController.kDescriptionPlaceholder {
                pub!.note = Tinode.kNullValue
            } else {
                pub!.note = desc
            }
        }
        if pub == nil {
            // Unchanged
            _ = self.navigationController?.popViewController(animated: true)
            return
        }

        saveProfileButton.isEnabled = false
        saveProfileButton.setTitle("正在保存…", for: .normal)
        self.me.setMeta(meta: MsgSetMeta(desc: pub != nil ? MetaSetDesc(pub: pub, priv: nil) : nil, tags: nil))
            .then(onSuccess: { _ in
                DispatchQueue.main.async {
                    _ = self.navigationController?.popViewController(animated: true)
                }
                return nil
            }, onFailure: { [weak self] error in
                DispatchQueue.main.async {
                    self?.saveProfileButton.isEnabled = true
                    self?.saveProfileButton.setTitle("保存资料", for: .normal)
                    UiUtils.showToast(message: "资料未能保存，请检查连接后重试。")
                }
                return nil
            })
    }
}

extension AccountGeneralSettingsViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard case .image(let image, _, _) = media else { return }
        UiUtils.updateAvatar(forTopic: self.me, image: image)
            .thenApply { _ in
                DispatchQueue.main.async {
                    UiUtils.showToast(message: NSLocalizedString("头像已更新", comment: "Avatar update success"), level: .info)
                    self.reloadData()
                }
                return nil
            }
    }
}

// The storyboard still owns the inputs; the D1 header is now their visible container.
extension AccountGeneralSettingsViewController {
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        CGFloat.leastNonzeroMagnitude
    }
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        CGFloat.leastNonzeroMagnitude
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { false }
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        // No legacy credential deletion, including stale swipe callbacks.
    }
}

extension AccountGeneralSettingsViewController: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        // Profile input is never written to the debug log.
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let newLength = (textField.text ?? "").count + (string.count - range.length)
        if textField.tag == AccountGeneralSettingsViewController.kPersonalAlias {
            // Alias length.
            return newLength <= UiUtils.kMaxAliasLength
        }
        // Limit max length of the non-alias input.
        return newLength <= UiUtils.kMaxTitleLength
    }
}

extension AccountGeneralSettingsViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == .placeholderText {
            textView.text = nil
            textView.textColor = .secondaryLabel
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            textView.text = AccountGeneralSettingsViewController.kDescriptionPlaceholder
            textView.textColor = .placeholderText
        }
    }

    // Limit max length of the input.
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return textView.text.count + (text.count - range.length) <= UiUtils.kMaxTopicDescriptionLength
    }
}
