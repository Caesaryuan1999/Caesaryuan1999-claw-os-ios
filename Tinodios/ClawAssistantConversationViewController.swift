// Copyright (c) 2026 CLAW OS contributors.
import UIKit

final class ClawAssistantConversationViewController: ClawAssistantPage, UITextViewDelegate {
    private let conversation: ClawAssistantConversation?
    private let status = ClawAssistantUI.label()
    private let messages = UIStackView()
    private let input = UITextView()
    private let draftNotice = ClawAssistantUI.label(size: 13)
    private let send = ClawAssistantUI.button("发送", primary: true)
    private let reload = ClawAssistantUI.button("重新加载")
    private let reconcile = ClawAssistantUI.button("重新核对")
    private let delete = ClawAssistantUI.button("删除对话")
    private var scroll: UIScrollView?
    private var keyboard: NSObjectProtocol?
    private var shownMessages: [ClawAssistantMessage] = []
    init(session: ClawAssistantSession, conversation: ClawAssistantConversation? = nil) {
        self.conversation = conversation
        super.init(session: session)
    }
    required init?(coder: NSCoder) { conversation = nil; super.init(coder: coder) }
    deinit { if let keyboard = keyboard { NotificationCenter.default.removeObserver(keyboard) } }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = conversation?.displayTitle ?? "开始提问"
        messages.axis = .vertical; messages.spacing = 20
        ClawTheme.styleTextView(input)
        input.font = ClawTheme.font(16); input.adjustsFontForContentSizeCategory = true
        input.delegate = self; input.isScrollEnabled = true
        input.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        input.accessibilityLabel = "你的问题"; input.accessibilityIdentifier = "claw.ai.draft"
        send.accessibilityIdentifier = "claw.ai.send"; send.isEnabled = false
        status.accessibilityIdentifier = "claw.ai.conversation.status"
        delete.setTitleColor(ClawTheme.danger, for: .normal)
        let stack = UIStackView(arrangedSubviews: [status, messages, reload, reconcile, delete,
                                                  ClawAssistantUI.label("你的问题"), input, draftNotice, send, accountButton])
        scroll = mountStack(stack)
        reload.addTarget(self, action: #selector(reloadMessages), for: .touchUpInside)
        reconcile.addTarget(self, action: #selector(reconcileResult), for: .touchUpInside)
        delete.addTarget(self, action: #selector(deleteConversation), for: .touchUpInside)
        keyboard = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let self = self, self.view.window != nil,
                      let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let local = self.view.convert(frame, from: nil)
                let overlap = max(0, self.view.bounds.maxY - local.minY - self.view.safeAreaInsets.bottom)
                self.scroll?.contentInset.bottom = overlap
                self.scroll?.verticalScrollIndicatorInsets.bottom = overlap
            }
        render()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let id = conversation?.conversation_id, current { model?.loadMessages(id) }
    }
    override func render() {
        guard isViewLoaded else { return }
        super.render()
        let id = conversation?.conversation_id
        let deletion = id.flatMap { model?.deletions[$0] }
        let active = current && deletion != .confirmed
        title = active ? conversation?.displayTitle ?? "开始提问" : "助手对话"
        input.isEditable = active
        let draft = current ? model?.draft ?? "" : ""
        if input.text != draft { input.text = draft }
        draftNotice.text = active ? model?.providerNotice : "助手内容已隐藏。"
        send.isEnabled = false // A never advertises or submits B, regardless of capability flags.
        send.alpha = 0.55
        delete.isHidden = id == nil || !current || deletion == .confirmed
        delete.isEnabled = deletion != .pending
        delete.setTitle(deletion == .unknown ? "再次删除同一对话" : "删除对话", for: .normal)
        reconcile.isHidden = deletion != .unknown || !current
        reconcile.isEnabled = model?.listLoading == false
        reload.isHidden = id == nil || !active || deletion == .pending || deletion == .unknown
        reload.isEnabled = id.map { model?.detailLoading.contains($0) == false } ?? false
        if !current {
            status.text = "请重新登录后查看助手历史。"
            input.resignFirstResponder()
        } else if deletion == .pending {
            status.text = "正在删除…"
        } else if deletion == .unknown {
            status.text = "删除结果暂未确认。重新核对只查询原对话状态，不会重新生成回答。"
        } else if deletion == .confirmed {
            status.text = "这段对话已删除。"
        } else if case .rejected(let error)? = deletion {
            status.text = error.message
        } else if let id = id, let error = model?.detailErrors[id] {
            status.text = error.message
        } else if let id = id, model?.detailLoading.contains(id) == true {
            status.text = "正在加载历史…"
        } else {
            status.text = id == nil ? "这里只保留本账号的草稿，尚未发送。" : "当前账号的历史对话"
        }
        let values = active ? id.flatMap { model?.details[$0] } ?? [] : []
        if shownMessages != values {
            shownMessages = values
            messages.arrangedSubviews.forEach { messages.removeArrangedSubview($0); $0.removeFromSuperview() }
            for message in values {
                let heading = ClawAssistantUI.label(message.role == "user" ? "你" : "助手", size: 13, weight: .medium)
                let body = ClawAssistantUI.label(message.text)
                body.accessibilityIdentifier = "claw.ai.history.body"
                let block = UIStackView(arrangedSubviews: [heading, body])
                block.axis = .vertical; block.spacing = 8
                if let state = message.stateText {
                    let label = ClawAssistantUI.label(state, size: 13)
                    label.textColor = ClawTheme.muted; block.addArrangedSubview(label)
                }
                messages.addArrangedSubview(block)
            }
        }
    }
    func textViewDidChange(_ textView: UITextView) {
        guard current else { render(); return }
        model?.setDraft(textView.text)
        if textView.text.utf8.count > 32000 {
            draftNotice.text = "问题超过32000字节，尚未发送。请缩短内容；当前草稿仍保留。"
        }
    }
    @objc private func reloadMessages() { if let id = conversation?.conversation_id, current { model?.loadMessages(id) } }
    @objc private func reconcileResult() { if let id = conversation?.conversation_id, current { model?.reconcileDeletion(id) } }
    @objc private func deleteConversation() { if let id = conversation?.conversation_id { confirmDeletion(id) } }
}
