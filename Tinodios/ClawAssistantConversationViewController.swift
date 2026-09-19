// Copyright (c) 2026 CLAW OS contributors.
import UIKit

final class ClawAssistantConversationViewController: ClawAssistantPage, UITextViewDelegate, UIScrollViewDelegate {
    private let conversation: ClawAssistantConversation?
    private let knownReturnAddress: ClawAssistantSession.KnownAddress?
    override var readerConversationID: String? { conversation?.conversation_id ?? knownReturnAddress?.conversationID }
    private let status = ClawAssistantUI.label()
    private let messages = UIStackView()
    private let input = UITextView()
    private let draftNotice = ClawAssistantUI.label(size: 13)
    private let send = ClawAssistantUI.button("发送", primary: true)
    private let reload = ClawAssistantUI.button("重新加载")
    private let reconcile = ClawAssistantUI.button("重新核对")
    private let delete = ClawAssistantUI.button("删除对话")
    private let runTitle = ClawAssistantUI.label(size: 16, weight: .medium)
    private let runDetail = ClawAssistantUI.label(size: 14)
    private let stop = ClawAssistantUI.button("停止回答")
    private let recover = ClawAssistantUI.button("恢复原回答")
    private let runPanel = UIStackView()
    private let latest = ClawAssistantUI.button("回到最新")
    private var scroll: UIScrollView?
    private var keyboard: NSObjectProtocol?
    private var shownMessages: [ClawAssistantMessageViewValue] = []
    private var rowViews: [String: ClawAssistantMessageRow] = [:]
    private struct Viewport {
        let followsBottom: Bool
        let candidates: [(id: String, distance: CGFloat)]
        let offset: CGPoint
    }
    private var storedViewport: Viewport?
    private var pendingViewport: Viewport?
    private var adjustingViewport = false
    private var lastWidth: CGFloat = 0
    private var keyboardOverlap: CGFloat = 0
    private var latestBottom: NSLayoutConstraint?
    init(session: ClawAssistantSession, conversation: ClawAssistantConversation? = nil) {
        self.conversation = conversation; knownReturnAddress = nil
        super.init(session: session)
    }
    init(session: ClawAssistantSession, knownAddress: ClawAssistantSession.KnownAddress) {
        knownReturnAddress = knownAddress
        conversation = session.history.conversations.first { $0.conversation_id == knownAddress.conversationID }
        super.init(session: session)
    }
    required init?(coder: NSCoder) { conversation = nil; knownReturnAddress = nil; super.init(coder: coder) }
    deinit { if let keyboard = keyboard { NotificationCenter.default.removeObserver(keyboard) } }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = conversation?.displayTitle ?? (knownReturnAddress == nil ? "开始提问" : "原回答")
        messages.axis = .vertical; messages.spacing = 20
        ClawTheme.styleTextView(input)
        input.font = ClawTheme.font(16); input.adjustsFontForContentSizeCategory = true
        input.delegate = self; input.isScrollEnabled = true
        input.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        input.accessibilityLabel = "你的问题"; input.accessibilityIdentifier = "claw.ai.draft"
        send.accessibilityIdentifier = "claw.ai.send"; send.isEnabled = false
        status.accessibilityIdentifier = "claw.ai.conversation.status"
        runTitle.accessibilityIdentifier = "claw.ai.run.state"
        runDetail.accessibilityIdentifier = "claw.ai.run.explanation"
        stop.accessibilityIdentifier = "claw.ai.run.stop"
        recover.accessibilityIdentifier = "claw.ai.run.recover"
        latest.accessibilityIdentifier = "claw.ai.latest"
        latest.accessibilityLabel = "回到最新"
        latest.isHidden = true
        delete.setTitleColor(ClawTheme.danger, for: .normal)
        runPanel.axis = .vertical; runPanel.spacing = 10
        runPanel.backgroundColor = ClawTheme.brandSoft; runPanel.layer.cornerRadius = 12
        runPanel.isLayoutMarginsRelativeArrangement = true
        runPanel.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        [runTitle, runDetail, recover, stop].forEach { runPanel.addArrangedSubview($0) }
        let stack = UIStackView(arrangedSubviews: [status, messages, runPanel, reload, reconcile, delete,
                                                  ClawAssistantUI.label("你的问题"), input, draftNotice, send, accountButton])
        scroll = mountStack(stack)
        scroll?.delegate = self; scroll?.accessibilityIdentifier = "claw.ai.conversation.scroll"
        latest.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(latest)
        latestBottom = latest.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        NSLayoutConstraint.activate([
            latest.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            latest.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            latest.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            latestBottom!
        ])
        reload.addTarget(self, action: #selector(reloadMessages), for: .touchUpInside)
        reconcile.addTarget(self, action: #selector(reconcileResult), for: .touchUpInside)
        delete.addTarget(self, action: #selector(deleteConversation), for: .touchUpInside)
        recover.addTarget(self, action: #selector(recoverAnswer), for: .touchUpInside)
        stop.addTarget(self, action: #selector(stopAnswer), for: .touchUpInside)
        latest.addTarget(self, action: #selector(goToLatest), for: .touchUpInside)
        keyboard = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let self = self, self.view.window != nil,
                      let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let anchor = self.captureViewport()
                let local = self.view.convert(frame, from: nil)
                self.keyboardOverlap = max(0, self.view.bounds.maxY - local.minY - self.view.safeAreaInsets.bottom)
                self.updateInsets()
                self.view.layoutIfNeeded(); self.restoreViewport(anchor)
            }
        render()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let id = readerConversationID, current { model?.loadMessages(id) }
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            pendingViewport = storedViewport
        }
        super.traitCollectionDidChange(previousTraitCollection)
        if isViewLoaded { render() }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !adjustingViewport, let scroll = scroll else { return }
        if abs(lastWidth - scroll.bounds.width) > 0.5, lastWidth > 0 {
            restoreViewport(storedViewport)
        }
        lastWidth = scroll.bounds.width
        updateInsets()
        storedViewport = captureViewport()
    }
    override func render() {
        guard isViewLoaded else { return }
        if pendingViewport == nil { view.layoutIfNeeded() }
        let anchor = pendingViewport ?? captureViewport()
        pendingViewport = nil
        adjustingViewport = true
        super.render()
        let id = readerConversationID
        let deletion = id.flatMap { model?.deletions[$0] }
        let active = current && deletion != .confirmed
        title = active ? conversation?.displayTitle ?? (id == nil ? "开始提问" : "原回答") : "助手对话"
        input.isEditable = active
        let draft = current ? model?.draft ?? "" : ""
        if input.text != draft { input.text = draft }
        draftNotice.text = active ? model?.providerNotice : "助手内容已隐藏。"
        send.isEnabled = false // B02 only reads/stops known runs; no generation action is wired.
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
        renderRun(id: id, active: active, deletion: deletion)
        let values = active ? id.map { session?.messageRows($0) ?? [] } ?? [] : []
        if shownMessages != values {
            shownMessages = values
            let ids = Set(values.map { $0.id })
            for (key, row) in rowViews where !ids.contains(key) {
                messages.removeArrangedSubview(row); row.removeFromSuperview(); rowViews[key] = nil
            }
            for (index, value) in values.enumerated() {
                let row = rowViews[value.id] ?? ClawAssistantMessageRow()
                rowViews[value.id] = row; row.configure(value)
                if !messages.arrangedSubviews.contains(row) {
                    messages.insertArrangedSubview(row, at: index)
                } else if messages.arrangedSubviews.firstIndex(of: row) != index {
                    messages.removeArrangedSubview(row); messages.insertArrangedSubview(row, at: index)
                }
            }
        }
        view.layoutIfNeeded()
        updateInsets(); view.layoutIfNeeded()
        adjustingViewport = false
        restoreViewport(anchor)
        if shownMessages.isEmpty { latest.isHidden = true }
    }
    func textViewDidChange(_ textView: UITextView) {
        guard current else { render(); return }
        model?.setDraft(textView.text)
        if textView.text.utf8.count > 32000 {
            draftNotice.text = "问题太长，尚未发送。请缩短内容；当前草稿仍保留。"
        }
    }
    private func renderRun(id: String?, active: Bool, deletion: ClawAssistantHistory.Deletion?) {
        guard active, let id = id, session?.knownAddress?.conversationID == id,
              let run = session?.knownRun, deletion != .pending, deletion != .unknown else {
            runPanel.isHidden = true; return
        }
        let projection = run.projection
        let terminal = projection?.terminal == true
        let legacy = projection?.receipt.isLegacy == true
        runPanel.isHidden = legacy
        stop.isHidden = terminal || projection == nil || legacy
        recover.isHidden = terminal || legacy || run.stopping == .pending
        recover.isEnabled = current
        let supportsRuns: Bool
        if let capabilities = model?.capabilities {
            supportsRuns = capabilities.history.available && (try? capabilities.validateRuns()) != nil
        } else { supportsRuns = false }
        stop.isEnabled = current && run.stopping != .pending && model?.capabilityError == nil && supportsRuns
        stop.setTitle(run.stopping == .unknown ? "再次停止回答" : "停止回答", for: .normal)
        recover.setTitle(run.stopping == .unknown ? "查看原回答状态" : "恢复原回答", for: .normal)
        if run.stopping == .pending {
            runTitle.text = "正在停止回答"; runDetail.text = "停止请求已发出，正在确认结果。"
        } else if run.stopping == .unknown {
            runTitle.text = "停止结果暂未确认"
            runDetail.text = "查看原回答状态不会重新生成。需要停止时，请选择“再次停止回答”。"
        } else if let error = run.lastError {
            runTitle.text = "暂时无法读取原回答"; runDetail.text = error.message
        } else if let projection = projection {
            runTitle.text = ClawAssistantMessageViewValue.caption(projection.state)
            if ["failed", "interrupted"].contains(projection.state) {
                runDetail.text = projection.text.isEmpty ? "暂时无法完成这次回答。" : "已有内容已保留。暂时无法继续这次回答。"
            } else {
                runDetail.text = terminal ? "已保存的内容仍可查看。" : "离开页面不会自动停止回答。"
            }
        } else {
            runTitle.text = "正在读取原回答"; runDetail.text = "只查看已保存的回答，不会重新生成。"
        }
    }
    private var maximumOffset: CGFloat {
        guard let scroll = scroll else { return 0 }
        return max(-scroll.adjustedContentInset.top,
                   scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
    }
    private func captureViewport() -> Viewport? {
        guard let scroll = scroll, scroll.bounds.height > 0 else { return nil }
        let top = scroll.contentOffset.y + scroll.adjustedContentInset.top
        let bottom = scroll.contentOffset.y + scroll.bounds.height - scroll.adjustedContentInset.bottom
        let candidates = shownMessages.compactMap { value -> (id: String, distance: CGFloat)? in
            guard let row = rowViews[value.id], !row.isHidden else { return nil }
            let frame = row.convert(row.bounds, to: scroll)
            return frame.maxY > top && frame.minY < bottom ? (value.id, frame.minY - top) : nil
        }
        return Viewport(followsBottom: maximumOffset - scroll.contentOffset.y < 24,
                        candidates: candidates, offset: scroll.contentOffset)
    }
    private func restoreViewport(_ anchor: Viewport?) {
        guard let scroll = scroll, let anchor = anchor else { return }
        adjustingViewport = true
        var target = anchor.offset.y
        if anchor.followsBottom { target = maximumOffset }
        else if let candidate = anchor.candidates.first(where: { rowViews[$0.id] != nil }),
                let row = rowViews[candidate.id] {
            target = row.convert(row.bounds, to: scroll).minY - candidate.distance - scroll.adjustedContentInset.top
        }
        scroll.setContentOffset(CGPoint(x: 0, y: min(maximumOffset, max(-scroll.adjustedContentInset.top, target))), animated: false)
        adjustingViewport = false
        latest.isHidden = shownMessages.isEmpty || maximumOffset - scroll.contentOffset.y < 24
        storedViewport = captureViewport()
    }
    private func updateInsets() {
        guard let scroll = scroll else { return }
        let reserve = shownMessages.isEmpty ? CGFloat(0) : max(52, latest.bounds.height) + 24
        scroll.contentInset.bottom = keyboardOverlap + reserve
        scroll.verticalScrollIndicatorInsets.bottom = keyboardOverlap
        latestBottom?.constant = -12 - keyboardOverlap
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !adjustingViewport else { return }
        latest.isHidden = shownMessages.isEmpty || maximumOffset - scrollView.contentOffset.y < 24
        storedViewport = captureViewport()
    }
    @objc private func goToLatest() {
        guard let scroll = scroll else { return }
        view.layoutIfNeeded()
        scroll.setContentOffset(CGPoint(x: 0, y: maximumOffset), animated: false)
    }
    @objc private func recoverAnswer() { _ = recoverPageRun() }
    @objc private func stopAnswer() { _ = stopPageRun() }
    @objc private func reloadMessages() { if let id = readerConversationID, current { model?.loadMessages(id) } }
    @objc private func reconcileResult() { if let id = readerConversationID, current { model?.reconcileDeletion(id) } }
    @objc private func deleteConversation() { if let id = readerConversationID { confirmDeletion(id) } }
}

private final class ClawAssistantMessageRow: UIStackView {
    private let heading = ClawAssistantUI.label(size: 13, weight: .medium)
    private let body = ClawAssistantUI.label()
    private let state = ClawAssistantUI.label(size: 13)
    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical; spacing = 8
        body.accessibilityIdentifier = "claw.ai.history.body"
        [heading, body, state].forEach { addArrangedSubview($0) }
        layer.cornerRadius = 14; isLayoutMarginsRelativeArrangement = true
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
    }
    required init(coder: NSCoder) { super.init(coder: coder) }
    func configure(_ value: ClawAssistantMessageViewValue) {
        accessibilityIdentifier = "claw.ai.message." + value.id
        heading.text = value.role == "user" ? "你" : "助手"
        body.text = value.text; state.text = value.state; state.isHidden = value.state == nil
        let user = value.role == "user"
        backgroundColor = user ? ClawTheme.primary : .clear
        heading.textColor = user ? ClawTheme.onBrand : ClawTheme.primary
        body.textColor = user ? ClawTheme.onBrand : ClawTheme.ink
        state.textColor = ClawTheme.muted
    }
}
