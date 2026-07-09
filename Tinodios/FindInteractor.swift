//
//  FindInteractor.swift
//  Tinodios
//
//  Copyright © 2019-2025 Tinode. All rights reserved.
//

import Foundation
import TinodeSDK

protocol FindBusinessLogic: AnyObject {
    var presenter: FindPresentationLogic? { get set }
    var fndTopic: DefaultFndTopic? { get }
    func loadAndPresentContacts(searchQuery: String?)
    func updateAndPresentRemoteContacts()
    func saveRemoteTopic(from remoteContact: RemoteContactHolder) -> Bool
    func setup()
    func cleanup()
    func attachToFndTopic()
}

class RemoteContactHolder: ContactHolder {
    var sub: Subscription<TheCard, [String]>?
}

class FindInteractor: FindBusinessLogic {
    private class FndListener: DefaultFndTopic.Listener {
        weak var interactor: FindBusinessLogic?
        override func onMetaSub(sub: Subscription<TheCard, [String]>) {
            // bitmaps?
        }
        override func onSubsUpdated() {
            self.interactor?.updateAndPresentRemoteContacts()
        }
    }

    static let kTinodeImProtocol = "Tinode"
    var presenter: FindPresentationLogic?
    private var queue = DispatchQueue(label: "co.tinode.contacts")
    // All known contacts from BaseDb's Users table.
    private var localContacts: [ContactHolder]?
    // Current search query (nil if none).
    private var searchQuery: String?
    var fndTopic: DefaultFndTopic?
    private var fndListener: FindInteractor.FndListener?
    // Contacts returned by the server
    // in response to a search request.
    private var remoteContacts: [RemoteContactHolder]?
    private var contactsManager = ContactsManager()

    func setup() {
        fndListener = FindInteractor.FndListener()
        fndListener?.interactor = self
    }
    func cleanup() {
        fndTopic?.listener = nil
        if fndTopic?.attached ?? false {
            fndTopic?.leave()
        }
    }
    func attachToFndTopic() {
        let tinode = Cache.tinode
        UiUtils.attachToFndTopic(fndListener: self.fndListener)?.then(
                onSuccess: { [weak self] _ in
                    self?.fndTopic = tinode.getOrCreateFndTopic()
                    return nil
                },
                onFailure: { err in
                    Cache.log.error("FindInteractor - failed to attach to fnd topic: %@", err.localizedDescription)
                    return nil
                })

    }
    func updateAndPresentRemoteContacts() {
        if let subs = fndTopic?.getSubscriptions(), !(searchQuery?.isEmpty ?? true) {
            self.remoteContacts = subs.map { sub in
                let accountName = AccountNames.fromTags(sub.priv)
                let contact = RemoteContactHolder(pub: sub.pub, uniqueId: sub.uniqueId,
                                                  accountName: accountName,
                                                  subtitle: AccountNames.contactListSecondary(accountName: accountName))
                contact.sub = sub
                return contact
            }
        } else {
            self.remoteContacts?.removeAll()
        }
        self.presenter?.presentRemoteContacts(contacts: self.remoteContacts ?? [])
    }

    func fetchLocalContacts() -> [ContactHolder] {
        return self.contactsManager.fetchContacts() ?? []
    }

    static let kSingleTagTest = try! NSRegularExpression(pattern: #"[\s,:]"#)
    func loadAndPresentContacts(searchQuery: String? = nil) {
        let changed = self.searchQuery != searchQuery
        self.searchQuery = searchQuery
        queue.async {
            if self.localContacts == nil {
                self.localContacts = self.fetchLocalContacts()
            }
            if self.remoteContacts == nil {
               self.remoteContacts = []
            }

            let contacts: [ContactHolder] =
                self.searchQuery != nil ?
                    self.localContacts!.filter { u in
                        let query = self.searchQuery!
                        let displayName = AccountNames.contactDisplayName(displayName: u.pub?.fn,
                                                                           accountName: u.accountName,
                                                                           userId: u.uniqueId)
                        if let r = displayName.range(of: query, options: .caseInsensitive),
                           r.contains(displayName.startIndex) {
                            return true
                        }
                        guard let accountName = u.accountName,
                              let r = accountName.range(of: query, options: .caseInsensitive) else {
                            return false
                        }
                        return r.contains(accountName.startIndex)
                    } :
                    self.localContacts!
            if changed {
                var searchStr: String? = nil
                if let query = searchQuery, !query.isEmpty,
                   FindInteractor.kSingleTagTest.firstMatch(in: query, range: NSRange(location: 0, length: query.count)) == nil {
                    let cleanQuery = query.first == "@" ? String(query.dropFirst()) : query
                    searchStr = AccountNames.directorySearchQuery(cleanQuery)
                }
                _ = self.fndTopic?.setMeta(desc: MetaSetDesc(pub: searchStr ?? Tinode.kNullValue, priv: nil))
            }

            self.remoteContacts?.removeAll()
            if let searchQuery = searchQuery,
               searchQuery.count >= UiUtils.kMinTagLength,
               AccountNames.directorySearchQuery(searchQuery) != nil {
                self.fndTopic?.getMeta(query: MsgGetMeta.sub())
            } else {
                // Clear remoteContacts.
                self.presenter?.presentRemoteContacts(contacts: self.remoteContacts!)
            }
            self.presenter?.presentLocalContacts(contacts: contacts)
        }
    }

    func saveRemoteTopic(from remoteContact: RemoteContactHolder) -> Bool {
        guard let topicName = remoteContact.uniqueId, let sub = remoteContact.sub else {
            return false
        }
        let tinode = Cache.tinode
        var topic: DefaultComTopic?
        if !tinode.isTopicTracked(topicName: topicName) {
            topic = tinode.newTopic(for: topicName) as? DefaultComTopic
            topic?.pub = sub.pub
            topic?.persist()
        } else {
            topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        }
        guard let topicUnwrapped = topic else { return false }
        if topicUnwrapped.isP2PType {
            contactsManager.processSubscription(sub: sub)
        }
        return true
    }
}
