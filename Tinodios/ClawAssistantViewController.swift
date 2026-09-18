// Copyright (c) 2026 CLAW OS contributors.
import UIKit

enum ClawAssistantUI {
    static func label(_ text: String = "", size: CGFloat = 16, weight: UIFont.Weight = .regular) -> UILabel {
        let label = UILabel()
        label.text = text; label.numberOfLines = 0
        label.font = ClawTheme.font(size, weight: weight)
        label.adjustsFontForContentSizeCategory = true; label.textColor = ClawTheme.ink
        return label
    }
    static func button(_ title: String, primary: Bool = false) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        if primary { ClawTheme.stylePrimaryButton(button) } else { ClawTheme.styleSecondaryButton(button) }
        button.titleLabel?.numberOfLines = 0; button.titleLabel?.textAlignment = .center
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        return button
    }
}

/// Shared only by A pages. Scope ownership is independent of visible controllers.
class ClawAssistantPage: UIViewController {
    private(set) var session: ClawAssistantSession?
    private var observation: UUID?
    private var lifecycle: [NSObjectProtocol] = []
    var model: ClawAssistantHistory? { session?.history }
    var current: Bool { session?.isCurrent ?? false }
    let accountButton = ClawAssistantUI.button("前往账号设置")

    init(session: ClawAssistantSession? = nil) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ClawTheme.background
        accountButton.accessibilityIdentifier = "claw.ai.account"
        accountButton.addTarget(self, action: #selector(openAccount), for: .touchUpInside)
        bind(session)
        lifecycle = [
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                object: nil, queue: .main) { [weak self] _ in self?.view.isHidden = true },
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: .main) { [weak self] _ in
                    self?.view.isHidden = false
                    self?.refreshVisibleScope()
                }
        ]
    }
    deinit {
        if let observation = observation { model?.removeObserver(observation) }
        lifecycle.forEach { NotificationCenter.default.removeObserver($0) }
    }
    func bind(_ session: ClawAssistantSession?) {
        if let observation = observation { model?.removeObserver(observation) }
        self.session = session
        observation = session?.history.observe { [weak self] in self?.render() }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.isHidden = false; refreshVisibleScope()
    }
    func refreshVisibleScope() { render() }
    func render() { accountButton.isHidden = current }
    @objc private func openAccount() {
        view.endEditing(true)
        (tabBarController as? ClawMainTabBarController)?.selectAccount()
    }
    func mountStack(_ stack: UIStackView) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        return scroll
    }
    func confirmDeletion(_ id: String) {
        guard let original = session, original.isCurrent, model?.deletions[id] != .pending else { return }
        let alert = UIAlertController(title: "删除这段对话？",
            message: "将删除此账号内的整段助手对话，并在其他设备恢复同步后更新。此操作无法撤销。",
            preferredStyle: .alert)
        let cancel = UIAlertAction(title: "取消", style: .cancel)
        alert.addAction(cancel); alert.preferredAction = cancel
        alert.addAction(UIAlertAction(title: "删除对话", style: .destructive) { [weak self, weak original] _ in
            guard let self = self, let original = original, self.session === original, original.isCurrent else { return }
            original.history.deleteConversation(id)
        })
        present(alert, animated: true)
    }
}

final class ClawAssistantViewController: ClawAssistantPage {
    private let welcome = ClawAssistantUI.label("有什么想聊的？", size: 32, weight: .bold)
    private let notice = ClawAssistantUI.label()
    private let start = ClawAssistantUI.button("开始提问", primary: true)
    private let historyButton = ClawAssistantUI.button("历史对话")
    private let refresh = ClawAssistantUI.button("重新检查")
    private var startupError: ClawAssistantError?
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "助手"
        welcome.accessibilityIdentifier = "claw.ai.welcome"
        notice.accessibilityIdentifier = "claw.ai.status"
        start.accessibilityIdentifier = "claw.ai.start"
        historyButton.accessibilityIdentifier = "claw.ai.history"
        let stack = UIStackView(arrangedSubviews: [
            ClawAssistantUI.label("AI · 通用文字助手", size: 12),
            welcome, ClawAssistantUI.label("提问、梳理思路，或一起理解一个新概念。"),
            notice, start, historyButton, refresh, accountButton
        ])
        _ = mountStack(stack)
        start.addTarget(self, action: #selector(openDraft), for: .touchUpInside)
        historyButton.addTarget(self, action: #selector(openHistory), for: .touchUpInside)
        refresh.addTarget(self, action: #selector(reloadCapabilities), for: .touchUpInside)
        render()
    }
    override func refreshVisibleScope() {
        if !current {
            do {
                let candidate = try Cache.assistantSession()
                if let prior = session {
                    guard prior.owner === candidate.owner, prior.uid == candidate.uid,
                          prior.generation == candidate.generation, prior.origin == candidate.origin else {
                        startupError = .retired; render(); return
                    }
                }
                bind(candidate); startupError = nil
            }
            catch let error as ClawAssistantError { startupError = error }
            catch { startupError = .signInRequired }
        }
        render()
        if current, model?.capabilities == nil, model?.capabilityLoading == false { model?.loadCapabilities() }
    }
    override func render() {
        guard isViewLoaded else { return }
        super.render()
        start.isEnabled = current && model?.capabilities != nil && model?.capabilityError == nil
        historyButton.isEnabled = current && model?.capabilities?.history.available == true && model?.capabilityError == nil
        if !current {
            notice.text = startupError?.message ?? "请重新登录后查看助手历史。"
        } else if model?.capabilityLoading == true {
            notice.text = "正在检查助手服务…"
        } else if let error = model?.capabilityError {
            notice.text = error.message
        } else if model?.capabilities?.history.available == false {
            notice.text = "助手历史暂不可用。服务暂未开通。"
        } else {
            notice.text = model?.providerNotice ?? "服务暂未开通。"
        }
    }
    @objc private func reloadCapabilities() {
        refreshVisibleScope()
        if current, model?.capabilityLoading == false { model?.loadCapabilities() }
    }
    @objc private func openDraft() {
        guard let session = session, current, start.isEnabled else { return }
        navigationController?.pushViewController(ClawAssistantConversationViewController(session: session), animated: true)
    }
    @objc private func openHistory() {
        guard let session = session, current, historyButton.isEnabled else { return }
        navigationController?.pushViewController(ClawAssistantHistoryViewController(session: session), animated: true)
    }
}
