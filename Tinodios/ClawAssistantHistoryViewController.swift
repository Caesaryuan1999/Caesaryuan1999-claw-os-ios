// Copyright (c) 2026 CLAW OS contributors.
import UIKit

final class ClawAssistantHistoryViewController: ClawAssistantPage, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private let statusTitle = ClawAssistantUI.label(size: 20, weight: .medium)
    private let status = ClawAssistantUI.label(size: 15)
    private let refresh = ClawAssistantUI.button("重新加载")
    private let back = ClawAssistantUI.button("返回助手")
    private let header = UIView()
    private var rows: [ClawAssistantConversation] = []
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "历史对话"
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = ClawTheme.background; table.separatorColor = ClawTheme.border
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 76
        table.dataSource = self; table.delegate = self
        table.register(ClawAssistantHistoryCell.self, forCellReuseIdentifier: "assistant-history")
        table.accessibilityIdentifier = "claw.ai.history.list"
        view.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let stack = UIStackView(arrangedSubviews: [ClawAssistantUI.label("当前账号", size: 13),
                                                 statusTitle, status, refresh, back, accountButton])
        stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -16)
        ])
        table.tableHeaderView = header
        refresh.addTarget(self, action: #selector(reloadHistory), for: .touchUpInside)
        back.addTarget(self, action: #selector(backToAssistant), for: .touchUpInside)
        render()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if current, model?.listLoading == false { model?.loadConversations() }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = table.bounds.width
        guard width > 0 else { return }
        let height = header.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        if abs(header.frame.height - height) > 0.5 || header.frame.width != width {
            header.frame = CGRect(x: 0, y: 0, width: width, height: height)
            table.tableHeaderView = header
        }
    }
    override func render() {
        guard isViewLoaded else { return }
        super.render()
        rows = current ? model?.conversations ?? [] : []
        let empty = model?.hasListSnapshot == true && rows.isEmpty && model?.listError == nil
        if !current {
            statusTitle.text = "登录状态已失效"; status.text = "请前往账号设置重新登录。"
        } else if model?.listLoading == true {
            statusTitle.text = "正在同步历史"
            status.text = rows.isEmpty ? "正在读取当前账号的历史对话。" : "正在核对最新历史，当前显示上次完整内容。"
        } else if let error = model?.listError {
            statusTitle.text = "暂时无法读取历史"; status.text = error.message
        } else if empty {
            statusTitle.text = "还没有历史对话"; status.text = "已保存的对话会显示在这里。"
        } else {
            statusTitle.text = ""; status.text = "仅显示当前账号的助手对话。"
        }
        statusTitle.isHidden = statusTitle.text?.isEmpty == true
        refresh.isHidden = !current || model?.listLoading == true || empty
        back.isHidden = !current || !empty || model?.listLoading == true
        refresh.isEnabled = current && model?.listLoading == false
        table.reloadData(); view.setNeedsLayout()
    }
    @objc private func reloadHistory() { if current { model?.loadConversations() } }
    @objc private func backToAssistant() { navigationController?.popToRootViewController(animated: true) }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "assistant-history", for: indexPath)
            as? ClawAssistantHistoryCell, indexPath.row < rows.count else { return UITableViewCell() }
        let row = rows[indexPath.row]
        cell.configure(row, deletion: model?.deletions[row.conversation_id])
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard current, let session = session, indexPath.row < rows.count else { return }
        navigationController?.pushViewController(ClawAssistantConversationViewController(
            session: session, conversation: rows[indexPath.row]), animated: true)
    }
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
        -> UISwipeActionsConfiguration? {
        guard current, indexPath.row < rows.count else { return nil }
        let id = rows[indexPath.row].conversation_id
        guard model?.deletions[id] != .pending else { return nil }
        let action = UIContextualAction(style: .destructive, title: "删除对话") { [weak self] _, _, done in
            self?.confirmDeletion(id); done(false)
        }
        let configuration = UISwipeActionsConfiguration(actions: [action])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }
}

private final class ClawAssistantHistoryCell: UITableViewCell {
    private let name = ClawAssistantUI.label(size: 17, weight: .medium)
    private let updated = ClawAssistantUI.label(size: 13)
    private let state = ClawAssistantUI.label(size: 13)
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = ClawTheme.surface
        let icon = UILabel()
        icon.text = "AI"; icon.font = .systemFont(ofSize: 17, weight: .medium)
        icon.textAlignment = .center; icon.textColor = ClawTheme.primary; icon.backgroundColor = ClawTheme.brandSoft
        icon.layer.cornerRadius = 12; icon.clipsToBounds = true; icon.isAccessibilityElement = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        let metadata = UIStackView(arrangedSubviews: [name, updated, state])
        metadata.axis = .vertical; metadata.spacing = 3; metadata.translatesAutoresizingMaskIntoConstraints = false
        updated.textColor = ClawTheme.muted; state.textColor = ClawTheme.warning
        contentView.addSubview(icon); contentView.addSubview(metadata)
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            icon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            icon.widthAnchor.constraint(equalToConstant: 40), icon.heightAnchor.constraint(equalToConstant: 40),
            icon.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),
            metadata.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            metadata.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            metadata.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            metadata.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
        name.accessibilityIdentifier = "claw.ai.history.title"
        updated.accessibilityIdentifier = "claw.ai.history.updated"
    }
    required init?(coder: NSCoder) { fatalError("Use programmatic history cell") }
    func configure(_ row: ClawAssistantConversation, deletion: ClawAssistantHistory.Deletion?) {
        name.text = row.displayTitle
        if let raw = row.updated_at, let date = ClawAssistantWire.date(raw) {
            let format = DateFormatter(); format.dateStyle = .medium; format.timeStyle = .short
            updated.text = format.string(from: date)
        } else { updated.text = nil }
        state.text = deletion == .pending ? "正在删除…" : (deletion == .unknown ? "删除结果暂未确认" : nil)
        state.isHidden = state.text == nil
        accessibilityLabel = [name.text, updated.text, state.text].compactMap { $0 }.joined(separator: "，")
    }
}
