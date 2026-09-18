//
//  MessageViewController+MessageDisplayLogic.swift
//  Tinodios
//
//  Copyright © 2023-2025 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

// Methods for updating title area and refreshing messages.
extension MessageViewController: MessageDisplayLogic {
    private func showInvitationDialog() {
        guard self.presentedViewController == nil else { return }
        let attrs = [ NSAttributedString.Key.font: UIFont.systemFont(ofSize: 20.0) ]
        let title = NSAttributedString(string: NSLocalizedString("通讯录", comment: "View title"), attributes: attrs)
        let alert = UIAlertController(
            title: nil,
            message: NSLocalizedString("你收到一个聊天邀请，要如何处理？", comment: "Call to action"),
            preferredStyle: .actionSheet)
        alert.setValue(title, forKey: "attributedTitle")
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("接受", comment: "Invite reaction button"), style: .default,
            handler: { _ in
                self.interactor?.acceptInvitation()
        }))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("忽略", comment: "Invite reaction button"), style: .default,
            handler: { _ in
                self.interactor?.ignoreInvitation()
        }))
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("屏蔽", comment: "Invite reaction button"), style: .default,
            handler: { _ in
                self.interactor?.blockTopic()
        }))
        self.present(alert, animated: true)
    }

    func switchTopic(topic: String?) {
        topicName = topic
    }

    func updateTitleBar(pub: TheCard?, online: Bool?, deleted: Bool) {
        assert(Thread.isMainThread)
        let isSlf = self.topic?.isSlfType ?? false
        let title = isSlf ?
            NSLocalizedString("CLAW文件助手", comment: "Title of the CLAW file assistant") :
            pub?.fn ?? NSLocalizedString("未命名", comment: "Undefined chat name")
        if !bulkSelectionMode {
            self.navigationItem.title = title
        }
        navBarAvatarView.set(pub: pub, id: topicName, online: isSlf ? nil : online, deleted: deleted)
        if isSlf {
            navBarAvatarView.setBrandingIcon()
        }
        navBarAvatarView.bounds = CGRect(x: 0, y: 0, width: Constants.kNavBarAvatarSmallState, height: Constants.kNavBarAvatarSmallState)

        navBarAvatarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
                navBarAvatarView.heightAnchor.constraint(equalToConstant: Constants.kNavBarAvatarSmallState),
                navBarAvatarView.widthAnchor.constraint(equalTo: navBarAvatarView.heightAnchor)
            ])
        var items = [UIBarButtonItem(customView: navBarAvatarView)]
        if let t = self.topic, t.callsAllowed {
            items.append(self.navBarCallBtn)
        }
        if !bulkSelectionMode {
            self.navigationItem.setRightBarButtonItems(items, animated: false)
        }
    }

    func displayPinnedMessages(pins: [Int], selected: Int, source: ChatDisplaySource?) {
        guard let source = source, chatDisplaySource == source else { return }
        assert(Thread.isMainThread)
        guard collectionView != nil else { return }

        reloadChatLayoutPreservingViewport { [weak self] in
            self?.pinnedMessageSeqs = pins
            if selected >= 0 && selected < pins.count {
                self?.pinnedSelectionIndex = selected
            }
        }
    }

    func reloadPinned(forSeq seq: Int, source: ChatDisplaySource?) {
        guard let source = source, chatDisplaySource == source else { return }
        if self.pinnedMessageSeqs.contains(where: { $0 == seq }) {
            reloadChatLayoutPreservingViewport()
        }
    }

    func setOnline(online: Bool?) {
        assert(Thread.isMainThread)
        navBarAvatarView.online = online
    }

    func runTypingAnimation() {
        assert(Thread.isMainThread)
        navBarAvatarView.presentTypingAnimation(steps: 30)
    }

    func reloadAllMessages(source: ChatDisplaySource?) {
        guard let source = source, chatDisplaySource == source else { return }
        assert(Thread.isMainThread)
        reloadChatLayoutPreservingViewport()
    }

    func displayChatMessages(messages newData: [StoredMessage], source: ChatDisplaySource, intent: ChatDisplayIntent) {
        assert(Thread.isMainThread)
        guard chatDisplaySource == source else { return }
        enqueueChatPresentation { [weak self] done in
            guard let self = self, self.chatDisplaySource == source, let list = self.collectionView else {
                done(); return
            }
            let oldData = self.messages
            guard !oldData.isEmpty || !newData.isEmpty else { done(); return }
            let viewport = self.captureChatViewport()
            if !oldData.isEmpty && newData.isEmpty { self.chatEmptyFollowLatest = viewport.atBottom }
            let firstNonempty = !self.chatPresentedNonempty && !newData.isEmpty
            if !newData.isEmpty { self.chatPresentedNonempty = true }
            let install = {
                self.messages = newData
                self.messageSeqIdIndex = newData.enumerated().reduce(into: [Int: Int]()) { result, entry in
                    result[entry.element.seqId] = entry.offset
                }
                self.messageDbIdIndex = newData.enumerated().reduce(into: [Int64: Int]()) { result, entry in
                    result[entry.element.msgId] = entry.offset
                }
            }
            let finish = {
                self.finishChatViewport(viewport, source: source, intent: intent, firstNonempty: firstNonempty)
                done()
            }
            // Keep the original batching threshold; it has no bearing on user intent.
            let now = Date()
            let delta = newData.count - oldData.count
            if now.millisecondsSince1970 > self.lastMessageReceived.millisecondsSince1970 + Constants.kUpdateBatchTimeDeltaThresholdMs {
                self.updateBatchSize = delta
            } else {
                self.updateBatchSize += delta
            }
            self.lastMessageReceived = now
            if oldData.isEmpty || newData.isEmpty || self.updateBatchSize > Constants.kUpdateBatchFullRefreshThreshold {
                self.withChatProgrammaticLayout {
                    install()
                    list.reloadSections(IndexSet(integer: 0))
                    list.layoutIfNeeded()
                }
                finish()
                return
            }

            // Diff against the array actually on screen, never a queued snapshot.
            let diff = Utils.diffMessageArray(sortedOld: oldData, sortedNew: newData)
            var refresh = Set<Int>()
            for index in diff.mutated {
                for neighbor in (index - 1)...(index + 1) where neighbor >= 0 && neighbor < newData.count {
                    refresh.insert(neighbor)
                }
            }
            refresh.subtract(diff.inserted)
            let refreshPaths = refresh.sorted().map { IndexPath(item: $0, section: 0) }
            let refreshPhase = {
                guard self.chatDisplaySource == source else { done(); return }
                guard !refreshPaths.isEmpty else { finish(); return }
                self.withChatProgrammaticLayout {
                    list.performBatchUpdates({ list.reloadItems(at: refreshPaths) }, completion: { _ in finish() })
                }
            }
            if !diff.inserted.isEmpty || !diff.removed.isEmpty {
                self.withChatProgrammaticLayout {
                    list.performBatchUpdates({
                        install()
                        list.deleteItems(at: diff.removed.map { IndexPath(item: $0, section: 0) })
                        list.insertItems(at: diff.inserted.map { IndexPath(item: $0, section: 0) })
                    }, completion: { _ in refreshPhase() })
                }
            } else {
                install()
                refreshPhase()
            }
        }
    }

    func reloadMessages(fromSeqId loId: Int, toSeqId hiId: Int, source: ChatDisplaySource?) {
        guard let source = source, chatDisplaySource == source else { return }
        assert(Thread.isMainThread)
        guard self.collectionView != nil else { return }
        guard loId <= hiId else { return }
        reloadChatLayoutPreservingViewport(reloadRange: loId...hiId)
    }

    func updateProgress(forMsgId msgId: Int64, progress: Float) {
        assert(Thread.isMainThread)
        if let index = self.messageDbIdIndex[msgId],
            let cell = self.collectionView.cellForItem(at: IndexPath(row: index, section: 0)) as? MessageCell {
            cell.progressView.setProgress(progress)
        }
    }

    func applyTopicPermissions(withError err: Error? = nil) {
        assert(Thread.isMainThread)
        // Make sure the view is visible.
        guard self.isViewLoaded && ((self.view?.window) != nil) else { return }

        if !(self.topic?.isReader ?? false) || err != nil {
            self.collectionView.showNoAccessOverlay(withMessage: err?.localizedDescription)
        } else {
            self.collectionView.removeNoAccessOverlay()
        }

        let publishingForbidden = !(self.topic?.isWriter ?? false) || err != nil
        // No "W" permission. Replace input field with a message "Not available".
        self.sendMessageBar.toggleNotAvailableOverlay(visible: publishingForbidden)
        if publishingForbidden {
            // Dismiss all pending messages.
            self.togglePreviewBar(with: nil)
            self.interactor?.dismissPendingMessage()
        }
        // The peer is missing either "W" or "R" permissions. Show "Peer's messaging is disabled" message.
        if let acs = self.topic?.peer?.acs, let missing = acs.missing {
            self.sendMessageBar.togglePeerMessagingDisabled(visible: acs.isJoiner(for: .want) && (missing.isReader || missing.isWriter))
        }
        // We are offered to join a chat.
        if let acs = self.topic?.accessMode, acs.isJoiner(for: Acs.Side.given) && (acs.excessive?.description.contains("RW") ?? false) {
            self.showInvitationDialog()
        }
    }

    func endRefresh() {
        assert(Thread.isMainThread)
        self.refreshControl.endRefreshing()
    }

    func dismissVC() {
        assert(Thread.isMainThread)
        self.navigationController?.popViewController(animated: true)
        self.dismiss(animated: true)
    }

    func togglePreviewBar(with preview: NSAttributedString?, onAction action: PendingPreviewAction = .none) {
        if preview == nil {
            isForwardingMessage = false
        }
        if isForwardingMessage {
            self.forwardMessageBar.togglePendingPreviewBar(with: preview)
        } else {
            self.sendMessageBar.togglePendingPreviewBar(withMessage: preview, onAction: action)
        }
        self.reloadInputViews()
    }
}
