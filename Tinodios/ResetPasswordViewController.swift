//
//  ResetPasswordViewController.swift
//  Tinodios
//
//  Copyright © 2019-2025 Tinode. All rights reserved.
//

import PhoneNumberKit
import TinodeSDK
import UIKit

class ResetPasswordViewController: UITableViewController {
    // UI element positions of UI in the table layout.
    private static let kSectionCredentials = 0
    private static let kSectionNewPassword = 1
    private static let kMethodEmail = 1
    private static let kMethodTel = 2
    private static let kRequestCodeButton = 3
    private static let kIHaveCodeButton = 4

    @IBOutlet weak var promptLabel: UILabel!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var telTextField: PhoneNumberTextField!
    @IBOutlet weak var confirmationCodeTextField: UITextField!
    @IBOutlet weak var newPasswordTextField: UITextField!

    private var passwordVisible = false
    private var passwordChangeSectionVisible = true

    override func viewDidLoad() {
        super.viewDidLoad()

        // Listen to text change events to clear the possible error from earlier attempt.
        emailTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        telTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        confirmationCodeTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        newPasswordTextField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)

        promptLabel.text = NSLocalizedString("输入账号名和账户设置页中的 ID，设置新密码。ID 仅本人可见。", comment: "ID reset password prompt")
        emailTextField.placeholder = NSLocalizedString("账号名", comment: "Password reset account name placeholder")
        emailTextField.autocapitalizationType = .none
        emailTextField.autocorrectionType = .no
        emailTextField.textContentType = .username
        telTextField.placeholder = NSLocalizedString("ID", comment: "Password reset private user id placeholder")
        telTextField.keyboardType = .asciiCapable
        telTextField.autocapitalizationType = .none
        telTextField.autocorrectionType = .no
        telTextField.withFlag = false
        telTextField.withPrefix = false
        telTextField.withExamplePlaceholder = false
        telTextField.withDefaultPickerUI = false
        confirmationCodeTextField.placeholder = NSLocalizedString("再次输入新密码", comment: "Confirm new password placeholder")
        confirmationCodeTextField.isSecureTextEntry = true
        confirmationCodeTextField.keyboardType = .default
        confirmationCodeTextField.textContentType = .newPassword
        newPasswordTextField.placeholder = NSLocalizedString("新密码", comment: "New password placeholder")
        newPasswordTextField.textContentType = .newPassword

        newPasswordTextField.showSecureEntrySwitch()

        UiUtils.dismissKeyboardForTaps(onView: self.view)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if self.isMovingFromParent {
            // If the user's logged in and is voluntarily leaving the ResetPassword VC
            // by hitting the Back button.
            let tinode = Cache.tinode
            if tinode.isConnectionAuthenticated || tinode.myUid != nil {
                tinode.logout()
            }
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == ResetPasswordViewController.kSectionNewPassword && !self.passwordChangeSectionVisible {
            return CGFloat.leastNonzeroMagnitude
        }
        return super.tableView(tableView, heightForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == ResetPasswordViewController.kSectionNewPassword && !self.passwordChangeSectionVisible {
            return nil
        }
        return super.tableView(tableView, titleForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Show only required credential fields.
        switch indexPath.section {
        case ResetPasswordViewController.kSectionCredentials:
            if indexPath.row == ResetPasswordViewController.kRequestCodeButton ||
                indexPath.row == ResetPasswordViewController.kIHaveCodeButton {
                return CGFloat.leastNonzeroMagnitude
            }
        case ResetPasswordViewController.kSectionNewPassword:
            if !self.passwordChangeSectionVisible {
                return CGFloat.leastNonzeroMagnitude
            }
        default:
            break
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }

    private func configurePageHeader() {
        DispatchQueue.main.async {
            self.promptLabel.text = NSLocalizedString("输入账号名和账户设置页中的 ID，设置新密码。ID 仅本人可见。", comment: "ID reset password prompt")
        }
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    @IBAction func haveCodeClicked(_ sender: Any) {
        self.tableView.reloadData()
    }

    private func validateCredential(forMethod method: String) -> String? {
        return nil
    }

    @IBAction func requestCodeClicked(_ sender: Any) {
        confirmCodeClicked(sender)
    }

    @IBAction func confirmCodeClicked(_ sender: Any) {
        let accountName = ClawAuthInput.accountNameForSubmit(emailTextField.text)
        let userId = (telTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let pwd = ClawAuthInput.passwordForSubmit(newPasswordTextField.text)
        let confirmPwd = ClawAuthInput.passwordForSubmit(confirmationCodeTextField.text)

        guard ClawAuthInput.isAccountNameValid(accountName) else {
            emailTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("账号名只能包含数字和字母", comment: "Invalid account name"))
            return
        }
        guard AccountNames.isUserIdLike(userId) else {
            telTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("请输入账户设置页中的 ID", comment: "Invalid user id"))
            return
        }
        guard ClawAuthInput.isPasswordValid(pwd) else {
            newPasswordTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("密码至少需要 6 位", comment: "Invalid password"))
            return
        }
        guard pwd == confirmPwd else {
            confirmationCodeTextField.markAsError()
            UiUtils.showToast(message: NSLocalizedString("两次输入的新密码不一致", comment: "Password mismatch"))
            return
        }

        guard let auth = try? AuthScheme.idResetInstance(accountName: accountName, userId: userId) else {
            UiUtils.showToast(message: NSLocalizedString("账号名或 ID 不正确", comment: "Invalid password reset params"))
            return
        }

        UiUtils.toggleProgressOverlay(in: self, visible: true, title: NSLocalizedString("正在更新密码...", comment: "Progress overlay"))
        do {
            try Cache.tinode.connectDefault(inBackground: false)?
                .thenApply { _ in
                    return Cache.tinode.updateAccountBasic(usingAuthScheme: auth, username: nil, password: pwd)
                }
                .then(onSuccess: { msg in
                    if let ctrl = msg?.ctrl, 200 <= ctrl.code && ctrl.code < 300 {
                        DispatchQueue.main.async {
                            UiUtils.showToast(message: NSLocalizedString("密码已更新", comment: "Password reset success"), level: .info)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                            self.navigationController?.popViewController(animated: true)
                        }
                    } else {
                        DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("账号名或 ID 不正确", comment: "Password reset failed")) }
                    }
                    return nil
                }, onFailure: { err in
                    DispatchQueue.main.async { UiUtils.showToast(message: NSLocalizedString("账号名或 ID 不正确", comment: "Password reset failed")) }
                    return nil
                }).thenFinally {
                    DispatchQueue.main.async {
                        UiUtils.toggleProgressOverlay(in: self, visible: false)
                    }
                }
        } catch {
            UiUtils.toggleProgressOverlay(in: self, visible: false)
            UiUtils.showToast(message: error.localizedDescription)
        }
    }
}
