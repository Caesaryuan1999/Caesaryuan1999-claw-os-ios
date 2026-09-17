//
//  ChatListInteractor.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import Foundation
import UIKit
import TinodeSDK

protocol ChatListBusinessLogic: AnyObject {
    func loadAndPresentTopics()
    func attachToMeTopic()
    func leaveMeTopic()
    func updateChat(_ name: String)
    func setup()
    func cleanup()
    func deleteTopic(_ topic: DefaultComTopic, owner: Tinode, permit: ClawConversationRemovalPermit)
    func changeArchivedStatus(forTopic name: String, archived: Bool)
}

protocol ChatListDataStore: AnyObject {
    var topics: [DefaultComTopic]? { get set }
}

class ChatListInteractor: ChatListBusinessLogic, ChatListDataStore {
    private class MeListener: DefaultMeTopic.Listener {
        weak var interactor: ChatListBusinessLogic?

        override func onPres(pres: MsgServerPres) {
            if pres.what == "msg" {
                interactor?.loadAndPresentTopics()
            } else if pres.what == "off" || pres.what == "on" {
                if let name = pres.src {
                    interactor?.updateChat(name)
                }
            }
        }
        override func onMetaSub(sub: Subscription<TheCard, PrivateType>) {
            if Tinode.topicTypeByName(name: sub.topic) == .p2p {
                ContactsManager.default.processSubscription(sub: sub)
            }
        }
        override func onMetaDesc(desc: Description<TheCard, PrivateType>) {
            // Handle description for me topic:
            // add/update user info for ME.
            if let uid = Cache.tinode.myUid {
                ContactsManager.default.processDescription(uid: uid, desc: desc)
            }
        }
        override func onSubsUpdated() {
            interactor?.loadAndPresentTopics()
        }
        override func onContUpdate(sub: Subscription<TheCard, PrivateType>) {
            // Method makes no sense in context of MeTopic.
            // throw new UnsupportedOperationException();
        }
    }
    private class ChatEventListener: UiTinodeEventListener {
        private weak var interactor: ChatListBusinessLogic?
        init(interactor: ChatListBusinessLogic?, connected: Bool) {
            super.init(connected: connected)
            self.interactor = interactor
        }
        override func onLogin(code: Int, text: String) {
            super.onLogin(code: code, text: text)
            self.interactor?.attachToMeTopic()
        }
        override func onDisconnect(byServer: Bool, code: URLSessionWebSocketTask.CloseCode, reason: String) {
            super.onDisconnect(byServer: byServer, code: code, reason: reason)
            // Update presence indicators (all should be off).
            self.interactor?.loadAndPresentTopics()
        }
        override func onDataMessage(data: MsgServerData?) {
            super.onDataMessage(data: data)
            if let topic = data?.topic {
                interactor?.updateChat(topic)
            }
        }
        override func onInfoMessage(info: MsgServerInfo?) {
            super.onInfoMessage(info: info)
            if info?.what != "call", let topic = info?.src {
                interactor?.updateChat(topic)
            }
        }
    }

    var presenter: ChatListPresentationLogic?
    var router: ChatListRoutingLogic?
    var topics: [DefaultComTopic]?
    private var archivedTopics: [DefaultComTopic]?
    private var meListener: MeListener?
    private var meTopic: DefaultMeTopic?
    private var tinodeEventListener: ChatEventListener?

    func attachToMeTopic() {
        let tinode = Cache.tinode
        guard meTopic == nil || !meTopic!.attached else {
            return
        }

        UiUtils.attachToMeTopic(meListener: self.meListener)?.then(
            onSuccess: { [weak self] _ in
                self?.loadAndPresentTopics()
                self?.meTopic = tinode.getMeTopic()
                return nil
            }, onFailure: { [weak self] err in
                if let e = err as? TinodeError, case .serverResponseError(let code, _, _) = e {
                    if code == 401 || code==403 || code == 404 {
                        self?.router?.routeToLogin()
                    }
                }
                return nil
            })
    }
    func leaveMeTopic() {
        if self.meTopic?.attached ?? false {
            self.meTopic?.leave()
        }
    }
    func setup() {
        if self.meListener == nil {
            self.meListener = MeListener()
        }
        self.meListener?.interactor = self
        self.meTopic?.listener = meListener
        let tinode = Cache.tinode
        if self.tinodeEventListener == nil {
            self.tinodeEventListener = ChatEventListener(
                interactor: self,
                connected: tinode.isConnected)
        }
        tinode.addListener(self.tinodeEventListener!)
    }
    func cleanup() {
        if self.meTopic?.listener === self.meListener {
            self.meTopic?.listener = nil
        }
        let tinode = Cache.tinode
        if let listener = self.tinodeEventListener {
            tinode.removeListener(listener)
        }
    }
    private func getTopics(archived: Bool) -> [DefaultComTopic]? {
        return Utils.fetchTopics(archived: archived)
    }
    func loadAndPresentTopics() {
        self.topics = self.getTopics(archived: false)
        self.archivedTopics = self.getTopics(archived: true)
        self.presenter?.presentTopics(
            self.topics ?? [], archivedTopics: self.archivedTopics)
    }

    func updateChat(_ name: String) {
        self.presenter?.topicUpdated(name)
    }

    func deleteTopic(_ topic: DefaultComTopic, owner: Tinode, permit: ClawConversationRemovalPermit) {
        guard Cache.isCurrent(owner), topic.isP2PType else { return }
        permit.perform(currentActor: owner, currentTopic: owner.getTopic(topicName: topic.name),
            kind: ClawConversationRemovalPermit.kind(isP2P: topic.isP2PType, isGroup: topic.isGrpType, isSaved: topic.isSlfType),
            isOwner: topic.isOwner) { route in
                guard route == .deleteTopic else { return }
                topic.delete(hard: true).then(
                    onSuccess: { [weak self] _ in
                        DispatchQueue.main.async {
                            guard Cache.isCurrent(owner) else { return }
                            self?.loadAndPresentTopics()
                        }
                        return nil
                    },
                    onFailure: { _ in
                        DispatchQueue.main.async {
                            guard Cache.isCurrent(owner) else { return }
                            UiUtils.showToast(message: "删除会话未完成，请检查连接后重试。")
                        }
                        return nil
                    })
            }
    }

    func changeArchivedStatus(forTopic name: String, archived: Bool) {
        let topic = Cache.tinode.getTopic(topicName: name) as! DefaultComTopic
        topic.updateArchived(archived: archived)?.then(
            onSuccess: { [weak self] _ in
                self?.loadAndPresentTopics()
                return nil
            },
            onFailure: UiUtils.ToastFailureHandler
        )
    }
}
