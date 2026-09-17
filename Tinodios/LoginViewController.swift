//
//  LoginViewController.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit
import os
import SwiftKeychainWrapper
import TinodeSDK
import TinodiosDB

class LoginViewController: UIViewController {
    private let submissionGate = ClawSubmissionGate()
    private var premiumLoginInstalled = false

    @IBOutlet weak var userNameTextEdit: UITextField!
    @IBOutlet weak var passwordTextEdit: UITextField!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var logoView: UIImageView!
    @IBOutlet weak var serviceNameLabel: UILabel!
    @IBOutlet weak var poweredByStack: UIStackView!
    @IBOutlet weak var configureConnectionButton: UIButton!
    @IBOutlet weak var loginButton: UIButton!

    override func loadView() {
        super.loadView()
        // This is needed in order to adjust the height of the scroll view when the keyboard appears.
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIControl.keyboardWillShowNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIControl.keyboardWillHideNotification, object: self)
        // Make sure LoginVC gets notified when app logo icon becomes available.
        NotificationCenter.default.addObserver(self, selector: #selector(logoAvailable(_:)), name: Notification.Name(SharedUtils.kNotificationBrandingSmallIconAvailable), object: nil)
        // Get notified with the branding service name becomes available.
        NotificationCenter.default.addObserver(self, selector: #selector(brandingConfigAvailable(_:)), name: Notification.Name(SharedUtils.kNotificationBrandingConfigAvailable), object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        installPremiumLoginLayout()

        // Listen to text change events
        userNameTextEdit.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        passwordTextEdit.addTarget(self, action: #selector(textFieldDidChange(_:)), for: UIControl.Event.editingChanged)
        userNameTextEdit.placeholder = NSLocalizedString("账号名", comment: "Login account name placeholder")
        userNameTextEdit.autocapitalizationType = .none
        userNameTextEdit.autocorrectionType = .no
        userNameTextEdit.textContentType = .username
        passwordTextEdit.placeholder = NSLocalizedString("密码", comment: "Login password placeholder")
        passwordTextEdit.showSecureEntrySwitch()
        ClawTheme.styleTextField(userNameTextEdit)
        ClawTheme.styleTextField(passwordTextEdit)
        ClawTheme.stylePrimaryButton(loginButton)
        ClawTheme.styleSecondaryButton(configureConnectionButton)
        logoView.contentMode = .scaleAspectFit
        logoView.image = UIImage(named: "logo-ios")
        logoView.layer.cornerRadius = 18
        logoView.layer.cornerCurve = .continuous
        logoView.layer.borderWidth = 1
        logoView.layer.borderColor = ClawTheme.border.cgColor
        logoView.clipsToBounds = true
        serviceNameLabel.text = NSLocalizedString("CLAW OS", comment: "Product name")
        serviceNameLabel.textColor = ClawTheme.ink
        serviceNameLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        serviceNameLabel.textAlignment = .center
        serviceNameLabel.isHidden = false
        loginButton.accessibilityIdentifier = "claw.login.primary"
        configureConnectionButton.accessibilityIdentifier = "claw.login.connection"

        UiUtils.dismissKeyboardForTaps(onView: self.view)

        self.poweredByStack.isHidden = false
        self.configureConnectionButton.isHidden = false
        self.logoView.image = UIImage(named: "logo-ios")
        self.serviceNameLabel.text = NSLocalizedString("CLAW OS", comment: "Product name")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidShowNotification, object: self)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: self)
        NotificationCenter.default.removeObserver(self, name: Notification.Name(SharedUtils.kNotificationBrandingSmallIconAvailable), object: self)
        NotificationCenter.default.removeObserver(self, name: Notification.Name(SharedUtils.kNotificationBrandingConfigAvailable), object: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.navigationBar.isHidden = true
        self.setInterfaceColors()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.navigationBar.isHidden = false
    }

    override var prefersStatusBarHidden: Bool {
        return false
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
    }

    private func setInterfaceColors() {
        self.view.backgroundColor = ClawTheme.surface
        self.scrollView.backgroundColor = ClawTheme.surface
        ClawTheme.styleTextField(userNameTextEdit)
        ClawTheme.styleTextField(passwordTextEdit)
        ClawTheme.stylePrimaryButton(loginButton)
        ClawTheme.styleSecondaryButton(configureConnectionButton)
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        guard let keyboardValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        let keyboardScreenEndFrame = keyboardValue.cgRectValue

        let keyboardViewEndFrame = view.convert(keyboardScreenEndFrame, from: view.window)

        let bottomInset = keyboardViewEndFrame.height - view.safeAreaInsets.bottom

        scrollView.contentInset.bottom = bottomInset
        scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
    }

    @objc func textFieldDidChange(_ textField: UITextField) {
        textField.clearErrorSign()
    }

    // Logo image has just been downloaded. Use it.
    @objc func logoAvailable(_ notification: Notification) {
        DispatchQueue.main.async {
            self.logoView.image = UIImage(named: "logo-ios")
        }
    }

    // Service name has just become available. Use it.
    @objc func brandingConfigAvailable(_ notification: Notification) {
        DispatchQueue.main.async {
            self.configureConnectionButton.isHidden = false
            self.poweredByStack.isHidden = false
            self.serviceNameLabel.text = NSLocalizedString("CLAW OS", comment: "Product name")
        }
    }

    private func installPremiumLoginLayout() {
        guard !premiumLoginInstalled else { return }
        premiumLoginInstalled = true

        view.subviews.forEach { $0.isHidden = true }

        let premiumScroll = UIScrollView()
        premiumScroll.translatesAutoresizingMaskIntoConstraints = false
        premiumScroll.backgroundColor = ClawTheme.surface
        premiumScroll.alwaysBounceVertical = true
        premiumScroll.keyboardDismissMode = .interactive
        view.addSubview(premiumScroll)

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.backgroundColor = ClawTheme.surface
        premiumScroll.addSubview(content)

        let logo = UIImageView(image: UIImage(named: "logo-ios"))
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.contentMode = .scaleAspectFit
        logo.layer.cornerRadius = 18
        logo.layer.cornerCurve = .continuous
        logo.layer.borderWidth = 1
        logo.layer.borderColor = ClawTheme.border.cgColor
        logo.clipsToBounds = true

        let service = makeLabel(
            text: NSLocalizedString("CLAW OS", comment: "Product name"),
            size: 23,
            weight: .bold,
            color: ClawTheme.ink,
            alignment: .center)
        let heading = makeLabel(
            text: NSLocalizedString("欢迎回来", comment: "Login welcome heading"),
            size: 30,
            weight: .bold,
            color: ClawTheme.ink)
        let subtitle = makeLabel(
            text: NSLocalizedString("使用账号名登录 CLAW OS", comment: "Login welcome subtitle"),
            size: 14,
            weight: .regular,
            color: ClawTheme.muted)

        let usernameLabel = makeLabel(
            text: NSLocalizedString("账号名", comment: "Login account name label"),
            size: 12,
            weight: .medium,
            color: ClawTheme.muted)
        let username = UITextField()
        username.translatesAutoresizingMaskIntoConstraints = false
        username.font = .systemFont(ofSize: 16, weight: .medium)
        username.accessibilityIdentifier = "claw.login.accountName"

        let passwordLabel = makeLabel(
            text: NSLocalizedString("密码", comment: "Login password label"),
            size: 12,
            weight: .medium,
            color: ClawTheme.muted)
        let password = UITextField()
        password.translatesAutoresizingMaskIntoConstraints = false
        password.font = .systemFont(ofSize: 16, weight: .medium)
        password.isSecureTextEntry = true
        password.accessibilityIdentifier = "claw.login.password"

        let forgot = makeTextButton(
            title: NSLocalizedString("忘记密码", comment: "Forgot password button"),
            size: 13,
            weight: .medium)
        forgot.contentHorizontalAlignment = .right
        forgot.addTarget(self, action: #selector(openResetPassword), for: .touchUpInside)

        let login = UIButton(type: .system)
        login.translatesAutoresizingMaskIntoConstraints = false
        login.setTitle(NSLocalizedString("登录", comment: "Login button"), for: .normal)
        login.accessibilityIdentifier = "claw.login.primary"
        login.addTarget(self, action: #selector(loginClicked(_:)), for: .touchUpInside)

        let accountPrompt = makeLabel(
            text: NSLocalizedString("还没有账号？", comment: "No account prompt"),
            size: 13,
            weight: .regular,
            color: ClawTheme.muted,
            alignment: .right)
        let createAccount = makeTextButton(
            title: NSLocalizedString("创建账号", comment: "Create account button"),
            size: 13,
            weight: .semibold)
        createAccount.contentHorizontalAlignment = .left
        createAccount.addTarget(self, action: #selector(openSignup), for: .touchUpInside)
        let accountRow = UIStackView(arrangedSubviews: [accountPrompt, createAccount])
        accountRow.translatesAutoresizingMaskIntoConstraints = false
        accountRow.axis = .horizontal
        accountRow.spacing = 6
        accountRow.alignment = .center
        accountRow.distribution = .fillEqually

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = ClawTheme.border

        let serverIcon = UIImageView(image: ClawTheme.symbol("server.rack", pointSize: 16, weight: .medium))
        serverIcon.translatesAutoresizingMaskIntoConstraints = false
        serverIcon.tintColor = ClawTheme.muted
        serverIcon.contentMode = .scaleAspectFit
        let (configuredHostName, _) = Tinode.getConnectionParams()
        let serverName = makeLabel(text: configuredHostName, size: 12, weight: .regular, color: ClawTheme.muted)
        let tlsState = makeLabel(text: NSLocalizedString("TLS 已启用", comment: "TLS enabled status"), size: 12, weight: .regular, color: ClawTheme.muted)
        let separator = makeLabel(text: "·", size: 12, weight: .regular, color: ClawTheme.muted, alignment: .center)
        let connection = makeTextButton(
            title: NSLocalizedString("连接设置", comment: "Connection settings button"),
            size: 12,
            weight: .medium)
        connection.accessibilityIdentifier = "claw.login.connection"
        connection.addTarget(self, action: #selector(openConnectionSettings), for: .touchUpInside)

        let serverStack = UIStackView(arrangedSubviews: [serverIcon, serverName, separator, tlsState, UIView(), connection])
        serverStack.translatesAutoresizingMaskIntoConstraints = false
        serverStack.axis = .horizontal
        serverStack.spacing = 7
        serverStack.alignment = .center

        [logo, service, heading, subtitle, usernameLabel, username, passwordLabel, password,
         forgot, login, accountRow, divider, serverStack].forEach { content.addSubview($0) }

        NSLayoutConstraint.activate([
            premiumScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            premiumScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            premiumScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            premiumScroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: premiumScroll.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: premiumScroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: premiumScroll.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: premiumScroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: premiumScroll.frameLayoutGuide.widthAnchor),
            content.heightAnchor.constraint(greaterThanOrEqualTo: premiumScroll.frameLayoutGuide.heightAnchor),

            logo.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            logo.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            logo.widthAnchor.constraint(equalToConstant: 78),
            logo.heightAnchor.constraint(equalToConstant: 78),
            service.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 14),
            service.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            heading.topAnchor.constraint(equalTo: service.bottomAnchor, constant: 92),
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            heading.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            subtitle.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: heading.trailingAnchor),

            usernameLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 30),
            usernameLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            usernameLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            username.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 8),
            username.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            username.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            username.heightAnchor.constraint(equalToConstant: 58),

            passwordLabel.topAnchor.constraint(equalTo: username.bottomAnchor, constant: 16),
            passwordLabel.leadingAnchor.constraint(equalTo: usernameLabel.leadingAnchor),
            passwordLabel.trailingAnchor.constraint(equalTo: usernameLabel.trailingAnchor),
            password.topAnchor.constraint(equalTo: passwordLabel.bottomAnchor, constant: 8),
            password.leadingAnchor.constraint(equalTo: username.leadingAnchor),
            password.trailingAnchor.constraint(equalTo: username.trailingAnchor),
            password.heightAnchor.constraint(equalToConstant: 58),

            forgot.topAnchor.constraint(equalTo: password.bottomAnchor, constant: 2),
            forgot.trailingAnchor.constraint(equalTo: password.trailingAnchor),
            forgot.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
            forgot.heightAnchor.constraint(equalToConstant: 44),

            login.topAnchor.constraint(equalTo: forgot.bottomAnchor, constant: 2),
            login.leadingAnchor.constraint(equalTo: username.leadingAnchor),
            login.trailingAnchor.constraint(equalTo: username.trailingAnchor),
            login.heightAnchor.constraint(equalToConstant: 54),

            accountRow.topAnchor.constraint(equalTo: login.bottomAnchor, constant: 14),
            accountRow.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            accountRow.widthAnchor.constraint(equalToConstant: 190),
            accountRow.heightAnchor.constraint(equalToConstant: 44),

            divider.topAnchor.constraint(equalTo: accountRow.bottomAnchor, constant: 8),
            divider.leadingAnchor.constraint(equalTo: username.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: username.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            serverStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            serverStack.leadingAnchor.constraint(equalTo: username.leadingAnchor),
            serverStack.trailingAnchor.constraint(equalTo: username.trailingAnchor),
            serverStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            serverStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            serverIcon.widthAnchor.constraint(equalToConstant: 18),
            serverIcon.heightAnchor.constraint(equalToConstant: 18),
            connection.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
            connection.heightAnchor.constraint(equalToConstant: 44)
        ])

        self.scrollView = premiumScroll
        self.logoView = logo
        self.serviceNameLabel = service
        self.poweredByStack = serverStack
        self.configureConnectionButton = connection
        self.userNameTextEdit = username
        self.passwordTextEdit = password
        self.loginButton = login
    }

    private func makeLabel(text: String, size: CGFloat, weight: UIFont.Weight,
                           color: UIColor, alignment: NSTextAlignment = .left) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.textAlignment = alignment
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    private func makeTextButton(title: String, size: CGFloat, weight: UIFont.Weight) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(ClawTheme.primaryPressed, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: size, weight: weight)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        return button
    }

    @objc private func openSignup() {
        performSegue(withIdentifier: "Login2Signup", sender: nil)
    }

    @objc private func openResetPassword() {
        performSegue(withIdentifier: "Login2ResetPassword", sender: nil)
    }

    @objc private func openConnectionSettings() {
        performSegue(withIdentifier: "Login2Branding", sender: nil)
    }

    @IBAction func loginClicked(_ sender: Any) {
        let userName = ClawAuthInput.accountNameForSubmit(userNameTextEdit.text)
        let password = ClawAuthInput.passwordForSubmit(passwordTextEdit.text)

        switch ClawAuthFormValidation.validateLogin(accountName: userName, password: password) {
        case .ok:
            break
        case .accountRequired:
            userNameTextEdit.markAsError()
            UiUtils.showToast(message: NSLocalizedString("请输入账号名", comment: "Missing account name"))
            return
        case .accountInvalid:
            userNameTextEdit.markAsError()
            UiUtils.showToast(message: NSLocalizedString("账号名只能包含数字和字母", comment: "Invalid account name"))
            return
        case .passwordRequired:
            passwordTextEdit.markAsError()
            return
        default:
            return
        }
        guard submissionGate.begin() else { return }

        let tinode = Cache.tinode
        UiUtils.toggleProgressOverlay(in: self, visible: true, title: NSLocalizedString("正在登录...", comment: "Login progress text"))
        do {
            guard let connection = try tinode.connectDefault(inBackground: false) else {
                submissionGate.finish()
                UiUtils.toggleProgressOverlay(in: self, visible: false)
                UiUtils.showToast(message: NSLocalizedString("无法建立服务器连接，请重试", comment: "Missing connection promise"))
                return
            }
            connection
                .thenApply({ _ in
                        guard Cache.isCurrent(tinode) else { throw TinodeError.invalidState("Session ended") }
                        return tinode.loginBasic(uname: userName, password: password)
                    })
                .then(
                    onSuccess: { [weak self] pkt in
                        return Cache.ifCurrent(tinode) { () -> PromisedReply<ServerMessage>? in
                        guard let uid = tinode.myUid, !uid.isEmpty else {
                            Cache.log.error("LoginVC - login response did not include a user ID")
                            DispatchQueue.main.async {
                                UiUtils.showToast(message: NSLocalizedString("登录响应缺少账户 ID，请重试", comment: "Missing account ID after login"))
                            }
                            Cache.invalidate(ifCurrent: tinode)
                            return nil
                        }
                        Cache.log.info("LoginVC - login successful for %@", uid)
                        SharedUtils.saveAuthToken(for: userName, token: tinode.authToken, expires: tinode.authTokenExpires)
                        if let token = tinode.authToken {
                            tinode.setAutoLoginWithToken(token: token)
                        }
                        if let ctrl = pkt?.ctrl, ctrl.code >= 300, ctrl.text.contains("validate credentials") {
                            DispatchQueue.main.async {
                                UiUtils.routeToCredentialsVC(in: self?.navigationController,
                                                             verifying: ctrl.getStringArray(for: "cred")?.first, for: tinode)
                            }
                            return nil
                        }
                        UiUtils.routeToChatListVC(for: tinode)
                        return nil

                        } ?? nil
                    }, onFailure: { err in
                        return Cache.ifCurrent(tinode) { () -> PromisedReply<ServerMessage>? in
                            Cache.log.error("LoginVC - login failed: %@", err.localizedDescription)
                            Cache.invalidate(ifCurrent: tinode)
                            let generation = Cache.sessionGeneration
                            DispatchQueue.main.async {
                                guard Cache.isLoggedOut(generation: generation) else { return }
                                UiUtils.showToast(message: ClawAuthErrorMessages.loginMessage(for: err))
                            }
                            return nil
                        } ?? nil
                    }).thenFinally { [weak self] in
                        self?.submissionGate.finish()
                        guard let loginVC = self else { return }
                        DispatchQueue.main.async {
                            UiUtils.toggleProgressOverlay(in: loginVC, visible: false)
                        }
                    }
            } catch {
                submissionGate.finish()
                UiUtils.toggleProgressOverlay(in: self, visible: false)
                Cache.log.error("LoginVC - Failed to connect/login to Tinode: %@", error.localizedDescription)
                UiUtils.showToast(message: ClawAuthErrorMessages.loginMessage(for: error))
                Cache.invalidate(ifCurrent: tinode)
            }
    }
}
