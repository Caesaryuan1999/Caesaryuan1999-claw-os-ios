//
//  SignupViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import PhoneNumberKit
import TinodeSDK
import UIKit
import TinodiosDB

class SignupViewController: UITableViewController {
    private let submissionGate = ClawSubmissionGate()
    private var premiumSignupInstalled = false
    private var termsAccepted = true
    private weak var premiumHeaderView: UIView?
    private weak var termsButton: UIButton?
    private static let kSectionGeneral = 2
    // UI positions of the Contacts fields.
    private static let kSectionContacts = 3
    private static let kContactsEmail = 0
    private static let kContactsTel = 1

    @IBOutlet weak var avatarImageView: RoundImageView!
    @IBOutlet weak var loginTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var descriptionTextField: UITextField!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var telTextField: PhoneNumberTextField!
    @IBOutlet weak var signUpButton: UIButton!

    var imagePicker: ImagePicker!
    var avatarReceived: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: true)
        installPremiumSignupLayout()

        // Listen to text change events to clear the possible error from earlier attempt.
        loginTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        passwordTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        emailTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        loginTextField.placeholder = NSLocalizedString("账号名", comment: "Signup account name placeholder")
        loginTextField.autocapitalizationType = .none
        loginTextField.autocorrectionType = .no
        loginTextField.textContentType = .username
        passwordTextField.placeholder = NSLocalizedString("密码", comment: "Signup password placeholder")
        emailTextField.placeholder = NSLocalizedString("邀请码", comment: "Signup invite code placeholder")
        emailTextField.autocapitalizationType = .allCharacters
        emailTextField.autocorrectionType = .no
        signUpButton.isEnabled = true
        passwordTextField.showSecureEntrySwitch()
        tableView.backgroundColor = ClawTheme.background
        ClawTheme.styleTextField(loginTextField)
        ClawTheme.styleTextField(passwordTextField)
        ClawTheme.styleTextField(emailTextField)
        ClawTheme.stylePrimaryButton(signUpButton)
        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = premiumHeaderView,
              abs(header.frame.width - tableView.bounds.width) > 0.5 else { return }
        header.frame.size.width = tableView.bounds.width
        tableView.tableHeaderView = header
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return CGFloat.leastNonzeroMagnitude
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return nil
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return CGFloat.leastNonzeroMagnitude
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return CGFloat.leastNonzeroMagnitude
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    @IBAction func addAvatarClicked(_ sender: Any) {
        // Get avatar image
        self.imagePicker.present(from: self.view)
    }

    @IBAction func signUpClicked(_ sender: Any) {
        let login = ClawAuthInput.accountNameForSubmit(loginTextField.text)
        let pwd = ClawAuthInput.passwordForSubmit(passwordTextField.text)
        let inviteCode = ClawAuthInput.inviteCodeForSubmit(emailTextField.text)

        switch ClawAuthFormValidation.validateSignUp(accountName: login, password: pwd, inviteCode: inviteCode) {
        case .ok:
            break
        case .accountRequired:
            loginTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("请输入账号名", comment: "Missing account name"))
            return
        case .accountInvalid:
            loginTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("账号名只能包含数字和字母", comment: "Invalid account name"))
            return
        case .passwordRequired, .passwordPolicy:
            passwordTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("密码至少需要 6 位", comment: "Invalid password"))
            return
        case .inviteRequired:
            emailTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("请输入邀请码", comment: "Missing invite code"))
            return
        default:
            return
        }
        guard termsAccepted else {
            UiUtils.showToast(message: NSLocalizedString("请先同意服务条款与隐私政策", comment: "Signup terms required"))
            return
        }
        guard submissionGate.begin() else { return }

        let creds = [Credential(meth: ClawAuthInput.inviteCredentialMethod, val: inviteCode)]

        func doSignUp(withPublicCard pub: TheCard, withCredentials creds: [Credential]) {
            let desc = MetaSetDesc<TheCard, String>(pub: pub, priv: nil)
            desc.attachments = pub.photoRefs

            UiUtils.toggleProgressOverlay(in: self, visible: true, title: NSLocalizedString("正在注册...", comment: "Progress overlay"))

            do {
                guard let connection = try Cache.tinode.connectDefault(inBackground: false) else {
                    submissionGate.finish()
                    signUpButton.isUserInteractionEnabled = true
                    UiUtils.toggleProgressOverlay(in: self, visible: false)
                    UiUtils.showToast(message: NSLocalizedString("无法建立服务器连接，请重试", comment: "Missing connection promise"))
                    return
                }
                connection
                    .thenApply { _ in
                        return Cache.tinode.createAccountBasic(uname: login, pwd: pwd, login: true, tags: nil, desc: desc, creds: creds)
                    }
                    .thenApply { [weak self] msg in
                        guard let signupVC = self else { return nil }
                        let tinode = Cache.tinode
                        SharedUtils.saveAuthToken(for: login, token: tinode.authToken, expires: tinode.authTokenExpires)
                        if let ctrl = msg?.ctrl, ctrl.code >= 300, ctrl.text.contains("validate credentials") {
                            DispatchQueue.main.async {
                                UiUtils.routeToCredentialsVC(in: signupVC.navigationController, verifying: ctrl.getStringArray(for: "cred")?.first)
                            }
                        } else {
                            if let token = Cache.tinode.authToken {
                                Cache.tinode.setAutoLoginWithToken(token: token)
                            }
                            UiUtils.routeToChatListVC()
                        }
                        return nil
                    }
                    .thenCatch { err in
                        Cache.log.error("Failed to create account: %@", err.localizedDescription)
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: self.signUpErrorMessage(for: err))
                        }
                        Cache.tinode.disconnect()
                        return nil
                    }
                    .thenFinally { [weak self] in
                        self?.submissionGate.finish()
                        guard let signupVC = self else { return }
                        DispatchQueue.main.async {
                            signupVC.signUpButton.isUserInteractionEnabled = true
                            UiUtils.toggleProgressOverlay(in: signupVC, visible: false)
                        }
                    }
            } catch {
                submissionGate.finish()
                Cache.tinode.disconnect()
                DispatchQueue.main.async {
                    UiUtils.showToast(message: ClawAuthErrorMessages.signUpMessage(for: error))
                    self.signUpButton.isUserInteractionEnabled = true
                    UiUtils.toggleProgressOverlay(in: self, visible: false)
                }
            }
        }

        signUpButton.isUserInteractionEnabled = false

        var avatar = avatarReceived ? avatarImageView?.image?.resize(width: UiUtils.kMaxAvatarSize, height: UiUtils.kMaxAvatarSize, clip: true) : nil
        if avatar != nil && (avatar!.size.width < UiUtils.kMinAvatarSize || avatar!.size.height < UiUtils.kMinAvatarSize) {
            avatar = nil
        }

        if let imageBits = avatar?.pixelData(forMimeType: Photo.kDefaultType) {
            if imageBits.count > UiUtils.kMaxInbandAvatarBytes {
                // Sending image out of band.
                Cache.getLargeFileHelper().startAvatarUpload(mimetype: Photo.kDefaultType, data: imageBits, topicId: "newacc", completionCallback: {(srvmsg, error) in
                    guard let error = error else {
                        let thumbnail = avatar!.resize(width: UiUtils.kAvatarPreviewDimensions, height: UiUtils.kAvatarPreviewDimensions, clip: true)
                        let photo = Photo(data: thumbnail?.pixelData(forMimeType: Photo.kDefaultType), ref: srvmsg?.ctrl?.getStringParam(for: "url"), width: Int(avatar!.size.width), height: Int(avatar!.size.height))
                        doSignUp(withPublicCard: TheCard(fn: login, avatar: photo, note: nil), withCredentials: creds)
                        return
                    }
                    self.submissionGate.finish()
                    DispatchQueue.main.async {
                        self.signUpButton.isUserInteractionEnabled = true
                    }
                    UiUtils.ToastFailureHandler(err: error)
                })
                return
            }
        }

        doSignUp(withPublicCard: TheCard(fn: login, avatar: avatar, note: nil), withCredentials: creds)
    }

    private func installPremiumSignupLayout() {
        guard !premiumSignupInstalled else { return }
        premiumSignupInstalled = true

        title = NSLocalizedString("创建账号", comment: "Signup screen title")
        tableView.backgroundColor = ClawTheme.surface
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.contentInsetAdjustmentBehavior = .automatic

        let header = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 748))
        header.backgroundColor = ClawTheme.surface

        let logo = UIImageView(image: UIImage(named: "logo-ios"))
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.contentMode = .scaleAspectFit
        logo.layer.cornerRadius = 18
        logo.layer.cornerCurve = .continuous
        logo.layer.borderWidth = 1
        logo.layer.borderColor = ClawTheme.border.cgColor
        logo.clipsToBounds = true

        let heading = makeSignupLabel(
            text: NSLocalizedString("加入 CLAW OS", comment: "Signup heading"),
            size: 30,
            weight: .bold,
            color: ClawTheme.ink)
        let subtitle = makeSignupLabel(
            text: NSLocalizedString("账号名创建后不可修改，仅支持数字和字母。", comment: "Signup account explanation"),
            size: 13,
            weight: .regular,
            color: ClawTheme.muted)
        subtitle.numberOfLines = 2

        let accountLabel = makeSignupLabel(
            text: NSLocalizedString("账号名", comment: "Signup account label"),
            size: 12,
            weight: .medium,
            color: ClawTheme.muted)
        let account = makeSignupTextField(identifier: "claw.signup.accountName")

        let passwordLabel = makeSignupLabel(
            text: NSLocalizedString("密码", comment: "Signup password label"),
            size: 12,
            weight: .medium,
            color: ClawTheme.muted)
        let password = makeSignupTextField(identifier: "claw.signup.password")
        password.isSecureTextEntry = true

        let inviteLabel = makeSignupLabel(
            text: NSLocalizedString("邀请码", comment: "Signup invite label"),
            size: 12,
            weight: .medium,
            color: ClawTheme.muted)
        let invite = makeSignupTextField(identifier: "claw.signup.inviteCode")
        let paste = UIButton(type: .system)
        paste.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        paste.setImage(ClawTheme.symbol("doc.on.clipboard", pointSize: 18, weight: .medium), for: .normal)
        paste.tintColor = ClawTheme.muted
        paste.accessibilityLabel = NSLocalizedString("粘贴邀请码", comment: "Paste invite code")
        paste.addTarget(self, action: #selector(pasteInviteCode), for: .touchUpInside)
        invite.rightView = paste
        invite.rightViewMode = .always

        let consentButton = UIButton(type: .system)
        consentButton.translatesAutoresizingMaskIntoConstraints = false
        consentButton.tintColor = ClawTheme.primary
        consentButton.accessibilityLabel = NSLocalizedString("同意服务条款与隐私政策", comment: "Accept terms")
        consentButton.addTarget(self, action: #selector(toggleTerms), for: .touchUpInside)
        let consentLabel = makeSignupLabel(
            text: NSLocalizedString("我已阅读并同意服务条款与隐私政策", comment: "Signup consent"),
            size: 12,
            weight: .regular,
            color: ClawTheme.muted)
        consentLabel.numberOfLines = 2
        let consentRow = UIStackView(arrangedSubviews: [consentButton, consentLabel])
        consentRow.translatesAutoresizingMaskIntoConstraints = false
        consentRow.axis = .horizontal
        consentRow.alignment = .center
        consentRow.spacing = 8

        let submit = UIButton(type: .system)
        submit.translatesAutoresizingMaskIntoConstraints = false
        submit.setTitle(NSLocalizedString("创建账号", comment: "Signup primary action"), for: .normal)
        submit.accessibilityIdentifier = "claw.signup.primary"
        submit.addTarget(self, action: #selector(signUpClicked(_:)), for: .touchUpInside)

        let privacyIcon = UIImageView(image: ClawTheme.symbol("shield", pointSize: 16, weight: .medium))
        privacyIcon.translatesAutoresizingMaskIntoConstraints = false
        privacyIcon.tintColor = ClawTheme.primary
        privacyIcon.contentMode = .scaleAspectFit
        let privacyText = makeSignupLabel(
            text: NSLocalizedString("邀请码由服务端校验，客户端不会生成安全凭证。", comment: "Server validated invite note"),
            size: 11,
            weight: .regular,
            color: ClawTheme.muted)
        privacyText.numberOfLines = 2
        let privacyRow = UIStackView(arrangedSubviews: [privacyIcon, privacyText])
        privacyRow.translatesAutoresizingMaskIntoConstraints = false
        privacyRow.axis = .horizontal
        privacyRow.alignment = .top
        privacyRow.spacing = 8

        let existingAccount = UIButton(type: .system)
        existingAccount.translatesAutoresizingMaskIntoConstraints = false
        existingAccount.setTitle(NSLocalizedString("已有账号", comment: "Existing account button"), for: .normal)
        existingAccount.setTitleColor(ClawTheme.primaryPressed, for: .normal)
        existingAccount.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        existingAccount.addTarget(self, action: #selector(openLogin), for: .touchUpInside)

        [logo, heading, subtitle, accountLabel, account, passwordLabel, password,
         inviteLabel, invite, consentRow, submit, privacyRow, existingAccount].forEach { header.addSubview($0) }

        NSLayoutConstraint.activate([
            logo.topAnchor.constraint(equalTo: header.topAnchor, constant: 24),
            logo.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            logo.widthAnchor.constraint(equalToConstant: 78),
            logo.heightAnchor.constraint(equalToConstant: 78),

            heading.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 30),
            heading.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            heading.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            subtitle.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: heading.trailingAnchor),

            accountLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 24),
            accountLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 28),
            accountLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -28),
            account.topAnchor.constraint(equalTo: accountLabel.bottomAnchor, constant: 8),
            account.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            account.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24),
            account.heightAnchor.constraint(equalToConstant: 58),

            passwordLabel.topAnchor.constraint(equalTo: account.bottomAnchor, constant: 16),
            passwordLabel.leadingAnchor.constraint(equalTo: accountLabel.leadingAnchor),
            passwordLabel.trailingAnchor.constraint(equalTo: accountLabel.trailingAnchor),
            password.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 8),
            password.leadingAnchor.constraint(equalTo: account.leadingAnchor),
            password.trailingAnchor.constraint(equalTo: account.trailingAnchor),
            password.heightAnchor.constraint(equalToConstant: 58),

            inviteLabel.topAnchor.constraint(equalTo: password.bottomAnchor, constant: 16),
            inviteLabel.leadingAnchor.constraint(equalTo: accountLabel.leadingAnchor),
            inviteLabel.trailingAnchor.constraint(equalTo: accountLabel.trailingAnchor),
            invite.topAnchor.constraint(equalTo: inviteLabel.bottomAnchor, constant: 8),
            invite.leadingAnchor.constraint(equalTo: account.leadingAnchor),
            invite.trailingAnchor.constraint(equalTo: account.trailingAnchor),
            invite.heightAnchor.constraint(equalToConstant: 58),

            consentRow.topAnchor.constraint(equalTo: invite.bottomAnchor, constant: 10),
            consentRow.leadingAnchor.constraint(equalTo: account.leadingAnchor),
            consentRow.trailingAnchor.constraint(equalTo: account.trailingAnchor),
            consentButton.widthAnchor.constraint(equalToConstant: 24),
            consentButton.heightAnchor.constraint(equalToConstant: 44),

            submit.topAnchor.constraint(equalTo: consentRow.bottomAnchor, constant: 8),
            submit.leadingAnchor.constraint(equalTo: account.leadingAnchor),
            submit.trailingAnchor.constraint(equalTo: account.trailingAnchor),
            submit.heightAnchor.constraint(equalToConstant: 54),

            privacyRow.topAnchor.constraint(equalTo: submit.bottomAnchor, constant: 12),
            privacyRow.leadingAnchor.constraint(equalTo: account.leadingAnchor),
            privacyRow.trailingAnchor.constraint(equalTo: account.trailingAnchor),
            privacyIcon.widthAnchor.constraint(equalToConstant: 18),
            privacyIcon.heightAnchor.constraint(equalToConstant: 18),

            existingAccount.topAnchor.constraint(equalTo: privacyRow.bottomAnchor, constant: 12),
            existingAccount.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            existingAccount.heightAnchor.constraint(equalToConstant: 44),
            existingAccount.bottomAnchor.constraint(lessThanOrEqualTo: header.bottomAnchor, constant: -8)
        ])

        tableView.tableHeaderView = header
        premiumHeaderView = header
        termsButton = consentButton
        updateTermsButton()

        loginTextField = account
        passwordTextField = password
        emailTextField = invite
        signUpButton = submit
    }

    private func makeSignupLabel(text: String, size: CGFloat, weight: UIFont.Weight,
                                 color: UIColor) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    private func makeSignupTextField(identifier: String) -> UITextField {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 16, weight: .medium)
        field.accessibilityIdentifier = identifier
        return field
    }

    @objc private func toggleTerms() {
        termsAccepted.toggle()
        updateTermsButton()
    }

    private func updateTermsButton() {
        let symbolName = termsAccepted ? "checkmark.square.fill" : "square"
        termsButton?.setImage(ClawTheme.symbol(symbolName, pointSize: 20, weight: .medium), for: .normal)
    }

    @objc private func pasteInviteCode() {
        emailTextField.text = UIPasteboard.general.string
        emailTextField.clearErrorSign()
    }

    @objc private func openLogin() {
        navigationController?.popViewController(animated: true)
    }

    private func signUpErrorMessage(for err: Error) -> String {
        if case TinodeError.serverResponseError(let code, let text, let reason) = err {
            let combined = "\(text) \(reason ?? "")".lowercased()
            if code == 409 || combined.contains("duplicate") || combined.contains("conflict") {
                return NSLocalizedString("已存在相同账号名", comment: "Duplicate account name")
            }
            if combined.contains("invite") {
                return NSLocalizedString("邀请码无效", comment: "Invalid invite code")
            }
        }
        return ClawAuthErrorMessages.signUpMessage(for: err)
    }
}

extension SignupViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard case .image(let image, _, _) = media,
            let image = image?.resize(width: CGFloat(UiUtils.kMaxAvatarSize), height: CGFloat(UiUtils.kMaxAvatarSize), clip: true) else { return }

        self.avatarImageView.image = image
        avatarReceived = true
    }
}
