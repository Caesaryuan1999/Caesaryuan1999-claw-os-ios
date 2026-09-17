//
//  MessageViewController+MessageCellDelegate.swift
//  Tinodios
//
//  Copyright © 2022-2025 Tinode LLC. All rights reserved.
//

import MobileVLCKit
import UIKit
import TinodeSDK
import TinodiosDB

private struct ClawMessageAction {
    let title: String
    let symbolName: String
    let destructive: Bool
    let handler: () -> Void
}

private final class ClawMessageActionControl: UIControl {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let handler: () -> Void

    init(action: ClawMessageAction) {
        self.handler = action.handler
        super.init(frame: .zero)

        accessibilityLabel = action.title
        accessibilityTraits = .button
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 62).isActive = true

        iconView.image = ClawTheme.symbol(action.symbolName, pointSize: 22, weight: .medium)
        iconView.tintColor = action.destructive ? ClawTheme.danger : ClawTheme.ink
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = action.title
        titleLabel.textColor = action.destructive ? ClawTheme.danger : ClawTheme.ink
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        titleLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 7
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: ClawTheme.iconStandard),
            iconView.heightAnchor.constraint(equalToConstant: ClawTheme.iconStandard),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        addTarget(self, action: #selector(runAction), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        handler()
    }
}

private final class ClawMessageActionsViewController: UIViewController, UIGestureRecognizerDelegate {
    private let actions: [ClawMessageAction]
    private let panel = UIView()

    init(actions: [ClawMessageAction]) {
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        view.accessibilityIdentifier = "claw.message.actions.overlay"

        panel.backgroundColor = ClawTheme.surface
        panel.layer.cornerRadius = 18
        panel.layer.cornerCurve = .continuous
        panel.layer.borderWidth = 1
        panel.layer.borderColor = ClawTheme.border.cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.accessibilityIdentifier = "claw.message.actions.panel"
        view.addSubview(panel)

        let title = UILabel()
        title.text = NSLocalizedString("消息操作", comment: "Message actions title")
        title.textColor = ClawTheme.muted
        title.font = .systemFont(ofSize: 13, weight: .medium)

        let regularActions = actions.filter { !$0.destructive }
        let destructiveActions = actions.filter { $0.destructive }
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(title)

        for start in stride(from: 0, to: regularActions.count, by: 5) {
            let end = min(start + 5, regularActions.count)
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            row.distribution = .fillEqually
            row.spacing = 4
            for index in start..<end {
                row.addArrangedSubview(makeControl(for: regularActions[index]))
            }
            for _ in end..<(start + 5) {
                let spacer = UIView()
                spacer.isAccessibilityElement = false
                row.addArrangedSubview(spacer)
            }
            content.addArrangedSubview(row)
        }

        if !destructiveActions.isEmpty {
            let divider = UIView()
            divider.backgroundColor = ClawTheme.border
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
            content.addArrangedSubview(divider)

            let dangerRow = UIStackView()
            dangerRow.axis = .horizontal
            dangerRow.alignment = .fill
            dangerRow.distribution = .fillEqually
            dangerRow.spacing = 10
            destructiveActions.forEach { action in
                let control = makeDangerControl(for: action)
                dangerRow.addArrangedSubview(control)
            }
            content.addArrangedSubview(dangerRow)
        }

        panel.addSubview(content)
        let bottom = panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        bottom.priority = .required
        let preferredWidth = panel.widthAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.widthAnchor,
            constant: -32)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            preferredWidth,
            bottom,
            content.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -16)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    private func makeControl(for action: ClawMessageAction) -> UIControl {
        ClawMessageActionControl(action: wrapped(action))
    }

    private func makeDangerControl(for action: ClawMessageAction) -> UIControl {
        let control = ClawMessageActionControl(action: wrapped(action))
        control.backgroundColor = ClawTheme.danger.withAlphaComponent(0.09)
        control.layer.cornerRadius = 12
        control.layer.cornerCurve = .continuous
        return control
    }

    private func wrapped(_ action: ClawMessageAction) -> ClawMessageAction {
        ClawMessageAction(title: action.title, symbolName: action.symbolName,
                          destructive: action.destructive) { [weak self] in
            self?.dismiss(animated: true, completion: action.handler)
        }
    }

    @objc private func backgroundTapped(_ sender: UITapGestureRecognizer) {
        if !panel.frame.contains(sender.location(in: view)) {
            dismiss(animated: true)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !panel.bounds.contains(touch.location(in: panel))
    }
}

// Methods for handling taps in messages.

extension MessageViewController: MessageCellDelegate {
    func didLongTap(in cell: MessageCell) {
        if bulkSelectionMode {
            toggleBulkMessageSelection(seqId: cell.seqId)
            return
        }
        createPopupMenu(in: cell)
    }

    func didTapContent(in cell: MessageCell, url: URL?) {
        guard let url = url else { return }

        if url.scheme == "tinode" {
            switch url.path {
            case "/post":
                handleButtonPost(in: cell, using: url)
            case "/attachment/small":
                handleSmallAttachment(in: cell, using: url)
            case "/attachment/large":
                handleLargeAttachment(in: cell, using: url)
            case "/image/preview":
                showImagePreview(in: cell, draftyEntityKey: Int(url.extractQueryParam(named: "key") ?? ""))
            case "/quote":
                handleQuoteClick(in: cell)
            case "/audio/seek":
                handleAudioSeek(in: cell, using: url)
                break
            case "/audio/toggle-play":
                handleToggleAudioPlay(in: cell, draftyEntityKey: Int(url.extractQueryParam(named: "key") ?? ""))
            case "/video":
                showVideoPreview(in: cell, draftyEntityKey: Int(url.extractQueryParam(named: "key") ?? ""))
            default:
                Cache.log.error("MessageVC - unknown tinode:// action: %@", url.description)
            }
            return
        }

        UIApplication.shared.open(url)
    }

    // TODO: remove as unused
    func didTapMessage(in cell: MessageCell) {
        if bulkSelectionMode {
            toggleBulkMessageSelection(seqId: cell.seqId)
        }
    }

    // TODO: remove as unused or go to user's profile (p2p topic?)
    func didTapAvatar(in cell: MessageCell) {}

    func didTapOutsideContent(in cell: MessageCell) {
        _ = self.sendMessageBar.inputField.resignFirstResponder()
    }

    func didTapCancelUpload(in cell: MessageCell) {
        guard let topicId = self.topicName,
            let msgIdx = self.messageSeqIdIndex[cell.seqId] else { return }
        _ = Cache.getLargeFileHelper().cancelUpload(topicId: topicId, msgId: self.messages[msgIdx].msgId)
    }

    func didEndMediaPlayback(in cell: MessageCell, audioPlayer: VLCMediaPlayer) {
        if self.currentAudioPlayer == audioPlayer {
            self.currentAudioPlayer = nil
        }
        attachmentDelegate(from: cell, action: "reset", payload: nil)
    }

    func didActivateMedia(in cell: MessageCell, audioPlayer: VLCMediaPlayer) {
        if let player = self.currentAudioPlayer, player != audioPlayer {
            player.stop()
        }
        self.currentAudioPlayer = audioPlayer
        attachmentDelegate(from: cell, action: "play", payload: nil)
    }

    func didPauseMedia(in cell: MessageCell, audioPlayer: VLCMediaPlayer) {
        if let player = self.currentAudioPlayer, player != audioPlayer {
            player.stop()
        }
        self.currentAudioPlayer = audioPlayer
        attachmentDelegate(from: cell, action: "pause", payload: nil)
    }

    func didSeekMedia(in cell: MessageCell, audioPlayer: VLCMediaPlayer, pos: Float) {
        if let player = self.currentAudioPlayer, player != audioPlayer {
            player.stop()
        }
        self.currentAudioPlayer = audioPlayer
        attachmentDelegate(from: cell, action: "seek", payload: pos)
    }

    func createPopupMenu(in cell: MessageCell) {
        guard !cell.isDeleted else { return }
        guard let topic = topic else { return }
        let messageSeqId = cell.seqId
        let storedMessage = messageSeqIdIndex[messageSeqId].map { messages[$0] }

        var actions = [ClawMessageAction]()
        actions.append(ClawMessageAction(title: NSLocalizedString("复制", comment: "Menu item"),
                                         symbolName: "doc.on.doc", destructive: false) { [weak self] in
            self?.copyMessageContent(seqId: cell.seqId)
        })
        actions.append(ClawMessageAction(title: NSLocalizedString("多选", comment: "Menu item"),
                                         symbolName: "checklist", destructive: false) { [weak self] in
            self?.beginBulkMessageSelection(starting: messageSeqId)
        })
        if let message = storedMessage, !message.isSynced {
            if !message.isUnconfirmed && message.status != BaseDb.Status.sending.rawValue && message.status != BaseDb.Status.sendingC3.rawValue {
                actions.append(ClawMessageAction(title: "删除本机记录", symbolName: "trash", destructive: true) { [weak self] in
                    self?.deleteMessage(seqId: messageSeqId, hard: false)
                })
            }
        } else if topic.isSlfType {
            // Self-type: always hard-delete.
            actions.append(ClawMessageAction(title: NSLocalizedString("删除该消息", comment: "Menu item"),
                                             symbolName: "trash", destructive: true) { [weak self] in
                                             self?.deleteMessage(seqId: messageSeqId, hard: true)
            })
        } else if !topic.isChannel {
            // Channel users cannot delete messages at all.
            // Non-channel can delete at least for self.
            actions.append(ClawMessageAction(title: NSLocalizedString("删除该消息", comment: "Menu item"),
                                             symbolName: "trash", destructive: true) { [weak self] in
                                             self?.deleteMessage(seqId: messageSeqId, hard: false)
            })

            if topic.isDeleter {
                let maxDelAge = Cache.tinode.getServerLimit(for: Tinode.kMessageDeleteAge, withDefault: 0)
                let canDelete = topic.isOwner || maxDelAge == 0 || (maxDelAge > 0 && (cell.timeStamp?.timeIntervalSince1970 ?? -1) > (Date().timeIntervalSince1970 - Double(maxDelAge)))
                if canDelete {
                    actions.append(ClawMessageAction(title: NSLocalizedString("为所有人删除", comment: "Menu item"),
                                                     symbolName: "trash.slash", destructive: true) { [weak self] in
                        self?.deleteMessage(seqId: messageSeqId, hard: true)
                    })
                }
            }
        }

        if !cell.isDeleted, let msgIndex = messageSeqIdIndex[cell.seqId], messages[msgIndex].isSynced {
            let msg = messages[msgIndex]
            actions.append(ClawMessageAction(title: NSLocalizedString("回复", comment: "Menu item"),
                                             symbolName: "arrowshape.turn.up.left", destructive: false) { [weak self] in
                self?.showQuotedPreview(seqId: cell.seqId, isReply: true) {
                    guard let value = $0, case let .replyTo(quote, _) = value else { return }
                    self?.showInPreviewBar(content: quote, forwarded: false, onAction: .reply)
                }
            })
            actions.append(ClawMessageAction(title: NSLocalizedString("转发", comment: "Menu item"),
                                             symbolName: "arrowshape.turn.up.right", destructive: false) { [weak self] in
                self?.showForwardSelector(seqId: cell.seqId)
            })
            if isFromCurrentSender(message: msg), let content = msg.content {
                // Only allow editing messages which don't contain certain entity types.
                var canEdit = true
                let prohibitedTypes: Set = ["AU", "EX", "FM", "IM", "VC", "VD"]
                for e in content.entities ?? [] {
                    if prohibitedTypes.contains(e.tp ?? "") {
                        canEdit = false
                        break
                    }
                }
                if canEdit {
                    let prohibitedStyles: Set = ["QQ"]
                    for f in content.fmt ?? [] {
                        if prohibitedStyles.contains(f.tp ?? "") {
                            canEdit = false
                            break
                        }
                    }
                }
                if canEdit {
                    actions.append(ClawMessageAction(title: NSLocalizedString("编辑", comment: "Menu item"),
                                                     symbolName: "square.and.pencil", destructive: false) { [weak self] in
                        self?.showQuotedPreview(seqId: cell.seqId, isReply: false) {
                            guard let value = $0, case let .edit(quote, original, _) = value else { return }
                            self?.sendMessageBar.inputField.becomeFirstResponder()
                            self?.sendMessageBar.inputField.text = original
                            self?.showInPreviewBar(content: quote, forwarded: false, onAction: .edit)
                        }
                    })
                }
            }

            if topic.isAdmin {
                if self.topic!.pinned.contains(where: { $0 == cell.seqId }) {
                    actions.append(ClawMessageAction(title: NSLocalizedString("取消置顶", comment: "Menu item for un-pinning message"),
                                                     symbolName: "pin.slash", destructive: false) { [weak self] in
                        self?.pinMessage(seqId: cell.seqId, pin: false)
                    })
                } else {
                    actions.append(ClawMessageAction(title: NSLocalizedString("置顶", comment: "Menu item for pinning message"),
                                                     symbolName: "pin", destructive: false) { [weak self] in
                        self?.pinMessage(seqId: cell.seqId, pin: true)
                    })
                }
            }
        }

        present(ClawMessageActionsViewController(actions: actions), animated: true)
    }

    @objc func willHidePopupMenu() {
        if sendMessageBar.inputField.nextResponderOverride != nil {
            sendMessageBar.inputField.nextResponderOverride!.resignFirstResponder()
            sendMessageBar.inputField.nextResponderOverride = nil
        }

        UIMenuController.shared.menuItems = nil
        NotificationCenter.default.removeObserver(self, name: UIMenuController.willHideMenuNotification, object: nil)
    }

    private func selectedMenuSeqId(sender: UIMenuController) -> Int? {
        let seqId = (sender.menuItems?.first as? MessageMenuItem)?.seqId
        return (seqId ?? 0) > 0 ? seqId : nil
    }

    func message(atSeqId seqId: Int) -> Message? {
        guard let msgIndex = messageSeqIdIndex[seqId] else { return nil }
        return messages[msgIndex]
    }

    @objc func copyMessageContent(sender: UIMenuController) {
        guard let seqId = selectedMenuSeqId(sender: sender) else { return }
        copyMessageContent(seqId: seqId)
    }

    private func copyMessageContent(seqId: Int) {
        guard let msg = message(atSeqId: seqId) else { return }

        var senderName: String?
        if let sub = topic?.getSubscription(for: msg.from), let pub = sub.pub {
            senderName = pub.fn
        }
        senderName = senderName ?? String(format: NSLocalizedString("未知 %@", comment: ""), msg.from ?? "none")
        UIPasteboard.general.string = "[\(senderName!)]: \(msg.content?.string ?? ""); \(RelativeDateFormatter.shared.shortDate(from: msg.ts))"
    }

    @objc func bulkToolbarCopy() {
        let selected = selectedBulkMessages()
        guard !selected.isEmpty else { return }
        copyBulkMessages(selected)
    }

    @objc func bulkToolbarReply() {
        let selected = selectedBulkMessages()
        guard selected.count == 1, let message = selected.first else { return }
        showQuotedPreview(seqId: message.seqId, isReply: true) { [weak self] value in
            guard let value = value, case let .replyTo(quote, _) = value else { return }
            self?.showInPreviewBar(content: quote, forwarded: false, onAction: .reply)
        }
    }

    @objc func bulkToolbarForward() {
        let selected = selectedBulkMessages()
        guard selected.count == 1, let message = selected.first else { return }
        showForwardSelector(seqId: message.seqId)
    }

    @objc func bulkToolbarRetry() {
        guard !selectedBulkMessages().isEmpty else { return }
        topic?.syncAll().thenCatch { error in
            UiUtils.showToast(message: String(format: NSLocalizedString("重试失败：%@", comment: "Retry failed"), error.localizedDescription))
            return nil
        }
        finishBulkMessageSelection()
    }

    @objc func bulkToolbarDelete() {
        let selected = selectedBulkMessages()
        guard !selected.isEmpty else { return }
        let alert = UIAlertController(
            title: NSLocalizedString("删除所选消息？", comment: "Confirm deleting selected messages"),
            message: String(format: NSLocalizedString("将删除 %d 条消息", comment: "Selected message deletion count"), selected.count),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("删除", comment: "Delete selected messages"), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            selected.forEach { self.interactor?.deleteMessage($0, hard: false) }
            self.finishBulkMessageSelection()
        })
        present(alert, animated: true)
    }

    private func copyBulkMessages(_ messages: [Message]) {
        let text = messages.map { message in
            let senderName = topic?.getSubscription(for: message.from)?.pub?.fn
                ?? String(format: NSLocalizedString("未知 %@", comment: "Unknown sender"), message.from ?? "none")
            return "[\(senderName)]: \(message.content?.string ?? ""); \(RelativeDateFormatter.shared.shortDate(from: message.ts))"
        }.joined(separator: "\n")
        UIPasteboard.general.string = text
        finishBulkMessageSelection()
    }

    func showInPreviewBar(content: Drafty?, forwarded: Bool, onAction action: PendingPreviewAction = .none) {
        guard let content = content else { return }
        let maxWidth = sendMessageBar.previewMaxWidth
        let maxHeight = collectionView.frame.height
        // Make sure it's properly formatted.
        let preview = (forwarded ? SendForwardedFormatter(defaultAttributes: [:]) : SendReplyFormatter(defaultAttributes: [:])).toAttributed(content, fitIn: CGSize(width: maxWidth, height: maxHeight))
        self.togglePreviewBar(with: preview, onAction: action)
    }

    @objc func showReplyPreview(sender: UIMenuController) {
        showQuotedPreview(sender: sender, isReply: true) {
            guard let value = $0, case let .replyTo(quote, _) = value else { return }
            self.showInPreviewBar(content: quote, forwarded: false, onAction: .reply)
        }
    }

    @objc func showEditPreview(sender: UIMenuController) {
        showQuotedPreview(sender: sender, isReply: false) {
            guard let value = $0, case let .edit(quote, original, _) = value else { return }
            self.sendMessageBar.inputField.becomeFirstResponder()
            self.sendMessageBar.inputField.text = original
            self.showInPreviewBar(content: quote, forwarded: false, onAction: .edit)
        }
    }

    @objc func pinMessage(sender: UIMenuController) {
        guard let seqId = selectedMenuSeqId(sender: sender) else { return }
        pinMessage(seqId: seqId, pin: true)
    }

    @objc func unpinMessage(sender: UIMenuController) {
        guard let seqId = selectedMenuSeqId(sender: sender) else { return }
        pinMessage(seqId: seqId, pin: false)
    }

    private func pinMessage(seqId: Int, pin: Bool) {
        interactor?.pinMessage(seqId: seqId, pin: pin)
    }

    private func showQuotedPreview(sender: UIMenuController, isReply: Bool, completion: @escaping (PendingMessage?) -> Void) {
        guard let seqId = selectedMenuSeqId(sender: sender) else { return }
        showQuotedPreview(seqId: seqId, isReply: isReply, completion: completion)
    }

    private func showQuotedPreview(seqId: Int, isReply: Bool, completion: @escaping (PendingMessage?) -> Void) {
        guard let msg = message(atSeqId: seqId) else { return }
        if let reply = interactor?.prepareQuoted(to: msg, isReply: isReply) {
            reply.then(onSuccess: { value in
                DispatchQueue.main.async {
                    completion(value)
                }
                return nil
            }, onFailure: { err in
                DispatchQueue.main.async {
                    completion(nil)
                    UiUtils.showToast(message: "Failed to create message preview: \(err)")
                }
                return nil
            })
        }
    }

    @objc func showForwardSelector(sender: UIMenuController) {
        guard let seqId = selectedMenuSeqId(sender: sender) else { return }
        showForwardSelector(seqId: seqId)
    }

    private func showForwardSelector(seqId: Int) {
        guard let sourceMessage = message(atSeqId: seqId) else { return }

        guard let pending = interactor?.createForwardedMessage(from: sourceMessage) else {
            return
        }
        guard case let .forwarded(forwardedMsg, forwardedFrom, forwardedPreview) = pending else {
            return
        }
        DispatchQueue.main.async {
            let navigator = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "ForwardToNavController") as! UINavigationController
            navigator.modalPresentationStyle = .pageSheet
            let forwardToVC = navigator.viewControllers.first as! ForwardToViewController
            forwardToVC.delegate = self
            forwardToVC.forwardedContent = forwardedMsg
            forwardToVC.forwardedFrom = forwardedFrom
            forwardToVC.forwardedPreview = forwardedPreview
            self.present(navigator, animated: true, completion: nil)
        }
        return
    }

    @objc func deleteMessageSoft(sender: UIMenuController) {
        self.deleteMessage(sender: sender, hard: false)
    }

    @objc func deleteMessageHard(sender: UIMenuController) {
        self.deleteMessage(sender: sender, hard: true)
    }

    private func deleteMessage(sender: UIMenuController, hard: Bool) {
        guard let seqId = selectedMenuSeqId(sender: sender) else { return }
        deleteMessage(seqId: seqId, hard: hard)
    }

    private func deleteMessage(seqId: Int, hard: Bool) {
        guard let msg = message(atSeqId: seqId) else { return }
        interactor?.deleteMessage(msg, hard: hard)
    }

    private func handleButtonPost(in cell: MessageCell, using url: URL) {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String]?
        if let queryItems = parts?.queryItems {
            query = [:]
            for item in queryItems {
                query![item.name] = item.value
            }
        }
        let newMsg = Drafty(content: query?["title"] ?? NSLocalizedString("undefined", comment: "Button with missing text"))
        var json: [String: JSONValue] = [:]
        // {"seq":6,"resp":{"yes":1}}
        if let name = query?["name"], let val = query?["val"] {
            var resp: [String: JSONValue] = [:]
            resp[name] = JSONValue.string(val)
            json["resp"] = JSONValue.dict(resp)
        }
        json["seq"] = JSONValue.int(cell.seqId)

        _ = interactor?.sendMessage(content: newMsg.attachJSON(json))
    }

    static func extractAttachment(from cell: MessageCell) -> [Data]? {
        guard let text = cell.content.attributedText else { return nil }
        var parts = [Data]()

        let range = NSRange(location: 0, length: text.length)
        text.enumerateAttributes(in: range, options: NSAttributedString.EnumerationOptions(rawValue: 0)) { (object, _, _) in
            if object.keys.contains(.attachment) {
                if let attachment = object[.attachment] as? NSTextAttachment, let data = attachment.contents {
                    parts.append(data)
                }
            }
        }
        return parts
    }

    func extractEntity(from cell: MessageCell, draftyEntityKey: Int?) -> Entity? {
        guard let index = messageSeqIdIndex[cell.seqId], let draftyKey = draftyEntityKey else { return nil }
        return messages[index].content?.entities?[draftyKey]
    }

    // Call EntityTextattachmentDelegate for each text attachment in the cell.
    func attachmentDelegate(from cell: MessageCell, action: String, payload: Any?) {
        guard let text = cell.content.attributedText else { return }

        let range = NSRange(location: 0, length: text.length)
        text.enumerateAttributes(in: range, options: NSAttributedString.EnumerationOptions(rawValue: 0)) { (object, _, _) in
            if object.keys.contains(.attachment) {
                if let attachment = object[.attachment] as? EntityTextAttachment {
                    attachment.delegate?.action(action, payload: payload)
                }
            }
        }
    }

    private func handleLargeAttachment(in cell: MessageCell, using url: URL) {
        guard let data = MessageViewController.extractAttachment(from: cell), !data.isEmpty else { return }
        let downloadFrom = String(decoding: data[0], as: UTF8.self)
        guard var urlComps = URLComponents(string: downloadFrom) else { return }
        if let filename = url.extractQueryParam(named: "filename") {
            urlComps.queryItems = [URLQueryItem(name: "origfn", value: filename)]
        }
        if let targetUrl = urlComps.url, targetUrl.scheme == "http" || targetUrl.scheme == "https" {
            Cache.getLargeFileHelper().startDownload(from: targetUrl)
        }
    }

    private func handleSmallAttachment(in cell: MessageCell, using url: URL) {
        // TODO: move logic to MessageInteractor.
        guard let data = MessageViewController.extractAttachment(from: cell), !data.isEmpty else { return }
        let d = data[0]
        // FIXME: use actual mime instead of nil when generating file name.
        let filename = url.extractQueryParam(named: "filename") ?? Utils.uniqueFilename(forMime: nil)
        let documentsUrl: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = documentsUrl.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: documentsUrl, withIntermediateDirectories: true, attributes: nil)
            try d.write(to: destinationURL)
            UiUtils.presentFileSharingVC(for: destinationURL)
        } catch {
            Cache.log.error("MessageVC - save attachment failed: %@", error.localizedDescription)
        }
    }

    private func handleToggleAudioPlay(in cell: MessageCell, draftyEntityKey key: Int?) {
        guard let entity = extractEntity(from: cell, draftyEntityKey: key) else { return }

        let duration = entity.data?["duration"]?.asInt() ?? 0
        let bits = entity.data?["val"]?.asData()
        let ref = entity.data?["ref"]?.asString()
        cell.toggleAudioPlay(url: ref, data: bits, duration: duration, key: key!)
    }

    private func handleAudioSeek(in cell: MessageCell, using url: URL) {
        let key = Int(url.extractQueryParam(named: "key") ?? "")
        guard let entity = extractEntity(from: cell, draftyEntityKey: key) else { return }

        let duration = entity.data?["duration"]?.asInt() ?? 0
        let bits = entity.data?["val"]?.asData()
        let ref = entity.data?["ref"]?.asString()
        guard let seekTo = Float(url.extractQueryParam(named: "pos") ?? "0") else { return }
        cell.audioSeekTo(seekTo, url: ref, data: bits, duration: duration, key: key!)
    }

    private func showImagePreview(in cell: MessageCell, draftyEntityKey: Int?) {
        // TODO: maybe pass nil to show "broken image" preview instead of returning.
        guard let index = messageSeqIdIndex[cell.seqId], let draftyKey = draftyEntityKey else { return }
        let msg = messages[index]
        guard let entity = msg.content?.entities?[draftyKey] else { return }
        let bits = entity.data?["val"]?.asData()
        let ref = entity.data?["ref"]?.asString()
        // Need to have at least one.
        guard bits != nil || ref != nil else { return }

        let content = ImagePreviewContent(
            imgContent: ImagePreviewContent.ImageContent.rawdata(bits, ref),
            caption: nil,
            fileName: entity.data?["name"]?.asString(),
            contentType: entity.data?["mime"]?.asString(),
            size: entity.data?["size"]?.asInt64() ?? Int64(bits?.count ?? 0),
            width: entity.data?["width"]?.asInt(),
            height: entity.data?["height"]?.asInt(),
            pendingMessagePreview: nil)
        performSegue(withIdentifier: "ShowImagePreview", sender: content)
    }

    private func showVideoPreview(in cell: MessageCell, draftyEntityKey: Int?) {
        // TODO: maybe pass nil to show "broken image" preview instead of returning.
        guard let index = messageSeqIdIndex[cell.seqId], let draftyKey = draftyEntityKey else { return }
        let msg = messages[index]
        guard let entity = msg.content?.entities?[draftyKey] else { return }
        let bits = entity.data?["val"]?.asData()
        let ref = entity.data?["ref"]?.asString()
        // Need to have either bits or ref.
        guard bits != nil || ref != nil else { return }

        let content = VideoPreviewContent(
            videoSrc: .remote(bits, ref),
            duration: entity.data?["duration"]?.asInt() ?? 0,
            fileName: entity.data?["name"]?.asString(),
            contentType: entity.data?["mime"]?.asString(),
            size: entity.data?["size"]?.asInt64() ?? 0,
            width: entity.data?["width"]?.asInt(),
            height: entity.data?["height"]?.asInt(),
            caption: nil,
            pendingMessagePreview: nil
        )

        performSegue(withIdentifier: "ShowVideoPreview", sender: content)
    }

    func handleQuoteClick(in cell: MessageCell) {
        guard let index = messageSeqIdIndex[cell.seqId] else { return }
        guard let seqId = Int(messages[index].head?["reply"]?.asString() ?? "") else { return }
        scrollToAndAnimate(seqId: seqId)
    }

    func scrollToAndAnimate(seqId: Int) {
        guard let index = messageSeqIdIndex[seqId] else { return }
        let path = IndexPath(item: index, section: 0)
        if let cell = collectionView.cellForItem(at: path) as? MessageCell {
            // If the cell is already visible.
            cell.highlightAnimated(withDuration: 4.0)
        } else {
            // Not visible? Memorize the cell and highlight it
            // after the view scrolls the cell into the viewport.
            self.highlightCellAtPathAfterScroll = path
        }
        self.collectionView.scrollToItem(at: path, at: .centeredVertically, animated: true)
    }
}

extension MessageViewController: PinnedMessagesDelegate {
    /// Tap on Cancel button.
    func didTapCancel(seq: Int) {
        self.interactor?.pinMessage(seqId: seq, pin: false)
    }

    /// Tap on the message.
    func didTapMessage(seq: Int) {
        scrollToAndAnimate(seqId: seq)
    }
}
