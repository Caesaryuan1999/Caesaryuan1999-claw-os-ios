//
//  MessagePresenter.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

protocol MessagePresentationLogic {
    var chatPageID: UUID { get }
    func switchTopic(topic: String?)
    func updateTitleBar(pub: TheCard?, online: Bool?, deleted: Bool)
    func setOnline(online: Bool?)
    func runTypingAnimation()
    func displayPinnedMessages(pins: [Int], selected: Int, source: ChatDisplaySource?)
    func reloadPinned(forSeq: Int, source: ChatDisplaySource?)
    func presentMessages(messages: [StoredMessage], source: ChatDisplaySource, intent: ChatDisplayIntent)
    func reloadMessages(fromSeqId loId: Int, toSeqId hiId: Int, source: ChatDisplaySource?)
    func reloadAllMessages(source: ChatDisplaySource?)
    func updateProgress(forMsgId msgId: Int64, progress: Float)
    func applyTopicPermissions(withError: Error?)
    func endRefresh()
    func dismiss()
    func dismissPendingMessagePreviewBar()
    func clearInputField()
}

class MessagePresenter: MessagePresentationLogic {
    let chatPageID: UUID
    init(pageID: UUID) { chatPageID = pageID }
    weak var viewController: MessageDisplayLogic?

    func switchTopic(topic: String?) {
        DispatchQueue.main.async {
            self.viewController?.switchTopic(topic: topic)
        }
    }

    func updateTitleBar(pub: TheCard?, online: Bool?, deleted: Bool) {
        DispatchQueue.main.async {
            self.viewController?.updateTitleBar(pub: pub, online: online, deleted: deleted)
        }
    }
    func setOnline(online: Bool?) {
        DispatchQueue.main.async {
            self.viewController?.setOnline(online: online)
        }
    }
    func displayPinnedMessages(pins: [Int], selected: Int, source: ChatDisplaySource?) {
        DispatchQueue.main.async {
            self.viewController?.displayPinnedMessages(pins: pins, selected: selected, source: source)
        }
    }
    func reloadPinned(forSeq seq: Int, source: ChatDisplaySource?) {
        DispatchQueue.main.async {
            self.viewController?.reloadPinned(forSeq: seq, source: source)
        }
    }
    func presentMessages(messages: [StoredMessage], source: ChatDisplaySource, intent: ChatDisplayIntent) {
        DispatchQueue.main.async {
            self.viewController?.displayChatMessages(messages: messages, source: source, intent: intent)
        }
    }
    func reloadMessages(fromSeqId loId: Int, toSeqId hiId: Int, source: ChatDisplaySource?) {
        DispatchQueue.main.async {
            self.viewController?.reloadMessages(fromSeqId: loId, toSeqId: hiId, source: source)
        }
    }
    func reloadAllMessages(source: ChatDisplaySource?) {
        DispatchQueue.main.async {
            self.viewController?.reloadAllMessages(source: source)
        }
    }
    func updateProgress(forMsgId msgId: Int64, progress: Float) {
        DispatchQueue.main.async {
            self.viewController?.updateProgress(forMsgId: msgId, progress: progress)
        }
    }
    func endRefresh() {
        DispatchQueue.main.async {
            self.viewController?.endRefresh()
        }
    }
    func runTypingAnimation() {
        DispatchQueue.main.async {
            self.viewController?.runTypingAnimation()
        }
    }
    func applyTopicPermissions(withError err: Error? = nil) {
        DispatchQueue.main.async {
            self.viewController?.applyTopicPermissions(withError: err)
        }
    }
    func dismiss() {
        DispatchQueue.main.async {
            self.viewController?.dismissVC()
        }
    }
    func dismissPendingMessagePreviewBar() {
        DispatchQueue.main.async {
            self.viewController?.togglePreviewBar(with: nil, onAction: .none)
        }
    }

    private func clearInput() {
        (self.viewController as? MessageViewController)?.sendMessageBar.inputField.text = nil
    }

    func clearInputField() {
        if Thread.isMainThread {
            // We are on main thread. Clear synchronously.
            clearInput()
            return
        }
        DispatchQueue.main.async {
            self.clearInput()
        }
    }
}
