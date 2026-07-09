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
        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == SignupViewController.kSectionGeneral {
            return CGFloat.leastNonzeroMagnitude
        }
        if indexPath.section == SignupViewController.kSectionContacts {
            if indexPath.row == SignupViewController.kContactsTel {
                return CGFloat.leastNonzeroMagnitude
            }
        }

        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 1:
            return NSLocalizedString("安全", comment: "Signup security section")
        case SignupViewController.kSectionContacts:
            return NSLocalizedString("邀请码", comment: "Signup invite section")
        case SignupViewController.kSectionGeneral:
            return nil
        default:
            return super.tableView(tableView, titleForHeaderInSection: section)
        }
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

        guard ClawAuthInput.isAccountNameValid(login) else {
            loginTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("账号名只能包含数字和字母", comment: "Invalid account name"))
            return
        }
        guard ClawAuthInput.isPasswordValid(pwd) else {
            passwordTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("密码至少需要 6 位", comment: "Invalid password"))
            return
        }
        guard !inviteCode.isEmpty else {
            emailTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("请输入邀请码", comment: "Missing invite code"))
            return
        }

        let creds = [Credential(meth: ClawAuthInput.inviteCredentialMethod, val: inviteCode)]
        let tags = [AccountNames.exactLookupQuery(login), "\(Tinode.kTagAlias)\(login)"]

        func doSignUp(withPublicCard pub: TheCard, withCredentials creds: [Credential]) {
            let desc = MetaSetDesc<TheCard, String>(pub: pub, priv: nil)
            desc.attachments = pub.photoRefs

            UiUtils.toggleProgressOverlay(in: self, visible: true, title: NSLocalizedString("Registering...", comment: "Progress overlay"))

            do {
                try Cache.tinode.connectDefault(inBackground: false)?
                    .thenApply { _ in
                        return Cache.tinode.createAccountBasic(uname: login, pwd: pwd, login: true, tags: tags, desc: desc, creds: creds)
                    }
                    .thenApply { [weak self] msg in
                        let tinode = Cache.tinode
                        SharedUtils.saveAuthToken(for: login, token: tinode.authToken, expires: tinode.authTokenExpires)
                        if let ctrl = msg?.ctrl, ctrl.code >= 300, ctrl.text.contains("validate credentials") {
                            DispatchQueue.main.async {
                                UiUtils.routeToCredentialsVC(in: self!.navigationController, verifying: ctrl.getStringArray(for: "cred")?.first)
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
                        guard let signupVC = self else { return }
                        DispatchQueue.main.async {
                            signupVC.signUpButton.isUserInteractionEnabled = true
                            UiUtils.toggleProgressOverlay(in: signupVC, visible: false)
                        }
                    }
            } catch {
                Cache.tinode.disconnect()
                DispatchQueue.main.async {
                    UiUtils.showToast(message: String(format: NSLocalizedString("Failed to create account: %@", comment: "Error message"), error.localizedDescription))
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
                    UiUtils.ToastFailureHandler(err: error)
                })
                return
            }
        }

        doSignUp(withPublicCard: TheCard(fn: login, avatar: avatar, note: nil), withCredentials: creds)
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
        return String(format: NSLocalizedString("Failed to create account: %@", comment: "Error message"), err.localizedDescription)
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
