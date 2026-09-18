import UIKit
import TinodeSDK

class LoginViewController: UIViewController {
    // Preserve existing storyboard outlets and segue routes.
    @IBOutlet weak var userNameTextEdit: UITextField!
    @IBOutlet weak var passwordTextEdit: UITextField!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var logoView: UIImageView!
    @IBOutlet weak var serviceNameLabel: UILabel!
    @IBOutlet weak var poweredByStack: UIStackView!
    @IBOutlet weak var configureConnectionButton: UIButton!
    @IBOutlet weak var loginButton: UIButton!

    private var coordinator: ClawIdentityCoordinator?
    private var form: ClawIdentityForm!
    private let methodPicker = UISegmentedControl(items: ["手机号", "邮箱"])
    private var country: UITextField!
    private var legacyButton: UIButton!
    private var legacyMode = false
    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ClawTheme.background
        form = ClawIdentityForm(title: "登录 CLAW OS", detail: "使用已验证的手机号或邮箱与密码登录。")
        let logo = UIImageView(image: UIImage(named: "logo-ios"))
        logo.contentMode = .scaleAspectFit
        logo.heightAnchor.constraint(equalToConstant: 56).isActive = true
        logo.accessibilityLabel = "CLAW OS"
        form.stack.insertArrangedSubview(logo, at: 0)
        logoView = logo
        methodPicker.selectedSegmentIndex = 0
        methodPicker.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        methodPicker.addTarget(self, action: #selector(methodChanged), for: .valueChanged)
        form.stack.addArrangedSubview(methodPicker)
        country = form.field("国家码")
        country.text = "+86"
        country.keyboardType = .phonePad
        userNameTextEdit = form.field("手机号")
        passwordTextEdit = form.field("密码", secure: true)
        passwordTextEdit.textContentType = .password
        loginButton = form.button("登录", target: self, action: #selector(loginClicked(_:)))
        loginButton.accessibilityIdentifier = "claw.login.primary"
        let signup = form.button("注册账号", target: self, action: #selector(openSignup), primary: false)
        let reset = form.button("找回密码", target: self, action: #selector(openResetPassword), primary: false)
        for button in [signup, reset] {
            form.stack.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        let secondaryActions = UIStackView(arrangedSubviews: [signup, reset])
        secondaryActions.axis = .horizontal
        secondaryActions.distribution = .fillEqually
        secondaryActions.spacing = 16
        form.stack.addArrangedSubview(secondaryActions)
        legacyButton = form.button("使用原账号登录", target: self, action: #selector(toggleLegacy), primary: false)
        configureConnectionButton = form.button("连接设置", target: self, action: #selector(openConnectionSettings), primary: false)
        configureConnectionButton.accessibilityIdentifier = "claw.login.connection"
        _ = form.button("重新检查身份服务", target: self, action: #selector(recheckService), primary: false)
        form.finish()
        form.install(in: self)
        UiUtils.dismissKeyboardForTaps(onView: view)
        methodChanged()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        if coordinator?.flow.isCurrent != true { prepareIdentity() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Navigation ends this login attempt. A committed session is retained by the flow.
        timer?.invalidate()
        coordinator?.flow.invalidate()
        passwordTextEdit.text = nil
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    deinit { timer?.invalidate() }

    private var selectedMethod: ClawIdentityMethod { methodPicker.selectedSegmentIndex == 0 ? .tel : .email }

    private func prepareIdentity(status: String? = nil) {
        coordinator?.flow.invalidate()
        coordinator = nil
        form.status.text = status ?? "正在检查身份服务…"
        do {
            let current = try ClawIdentityCoordinator(purpose: .register)
            coordinator = current
            current.flow.prepare { [weak self, weak current] result in
                guard let self = self, let current = current, self.coordinator === current else { return }
                switch result {
                case let .success(capabilities):
                    self.form.status.text = status ?? (capabilities.test_mode
                        ? "测试环境：短信或邮件投递尚未代表正式服务。" : "使用密码登录；验证码仅用于注册和找回密码。")
                    if !capabilities.legacy_basic { self.legacyMode = false; self.methodChanged() }
                case let .failure(error):
                    self.form.status.text = status ?? (current.flow.legacyLoginAvailable
                        ? "手机号和邮箱登录暂不可用；已有原账号可选择“使用原账号登录”。"
                        : "\(error.message)。请检查连接设置。")
                }
                self.refresh()
            }
        } catch {
            form.status.text = "身份服务暂不可用。请检查连接设置；公网身份服务须使用 HTTPS。"
        }
        refresh()
    }
    private func refresh() {
        let flow = coordinator?.flow
        let ready = flow?.isCurrent == true && flow?.busy == false && flow?.capabilities?.supported == true
        loginButton.isEnabled = (legacyMode ? flow?.legacyLoginAvailable == true && flow?.busy == false : ready)
            && (flow?.loginRetrySeconds ?? 0) == 0
        loginButton.setTitle(flow?.busy == true ? "正在登录…" : (flow?.loginRetrySeconds ?? 0) > 0 ? "\(flow!.loginRetrySeconds) 秒后重试" : "登录", for: .normal)
        userNameTextEdit.isEnabled = flow?.busy != true
        passwordTextEdit.isEnabled = flow?.busy != true
        country.isEnabled = flow?.busy != true
        methodPicker.isEnabled = flow?.busy != true
        legacyButton.isEnabled = flow?.legacyLoginAvailable == true && flow?.busy == false
    }
    @objc private func methodChanged() {
        let phone = !legacyMode && selectedMethod == .tel
        methodPicker.isHidden = legacyMode
        form.setField(country, visible: phone)
        let label = legacyMode ? "原账号名" : phone ? "手机号" : "邮箱"
        userNameTextEdit.placeholder = label
        userNameTextEdit.accessibilityLabel = label
        userNameTextEdit.keyboardType = legacyMode ? .asciiCapable : phone ? .phonePad : .emailAddress
        userNameTextEdit.textContentType = legacyMode ? .username : phone ? .telephoneNumber : .emailAddress
        if let index = form.stack.arrangedSubviews.firstIndex(of: userNameTextEdit), index > 0 {
            (form.stack.arrangedSubviews[index - 1] as? UILabel)?.text = label
        }
        legacyButton?.setTitle(legacyMode ? "使用手机号或邮箱登录" : "使用原账号登录", for: .normal)
        refresh()
    }
    @objc private func toggleLegacy() {
        legacyMode.toggle()
        userNameTextEdit.text = nil
        passwordTextEdit.text = nil
        methodChanged()
        form.status.text = legacyMode ? "仅供已有原账号使用。新账号请通过手机号或邮箱注册。" : nil
    }
    @objc private func recheckService() { prepareIdentity() }
    @objc private func openSignup() { performSegue(withIdentifier: "Login2Signup", sender: nil) }
    @objc private func openResetPassword() { performSegue(withIdentifier: "Login2ResetPassword", sender: nil) }
    @objc private func openConnectionSettings() {
        if let owner = coordinator?.owner { Cache.invalidate(ifCurrent: owner) }
        coordinator?.flow.invalidate()
        performSegue(withIdentifier: "Login2Branding", sender: nil)
    }

    @IBAction func loginClicked(_ sender: Any) {
        guard let current = coordinator, current.flow.isCurrent else { prepareIdentity(); return }
        let password = ClawAuthInput.passwordForSubmit(passwordTextEdit.text)
        let completion: (Result<ClawIdentitySessionResult, ClawIdentityError>) -> Void = { [weak self, weak current] result in
            guard let self = self, let current = current, self.coordinator === current else { return }
            switch result {
            case .success:
                self.passwordTextEdit.text = nil
                UiUtils.routeToChatListVC(for: current.owner)
            case let .failure(error):
                let message = self.legacyMode && error.code == "auth_invalid" ? "原账号名或密码不正确" : error.message
                self.form.status.text = message
                if !current.flow.isCurrent { self.prepareIdentity(status: message) }
            }
            self.refresh()
        }
        if legacyMode {
            let username = ClawAuthInput.accountNameForSubmit(userNameTextEdit.text)
            guard ClawAuthFormValidation.validateLogin(accountName: username, password: password) == .ok else {
                form.status.text = "请输入原账号名和密码"; return
            }
            current.loginLegacy(username: username, password: password, completion: completion)
        } else {
            current.flow.login(method: selectedMethod, input: userNameTextEdit.text ?? "",
                countryCode: country.text ?? "+86", password: password, completion: completion)
        }
        refresh()
    }
}
