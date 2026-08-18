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
    func saveRemoteTopic(from remoteContact: RemoteContactHolder, completion: @escaping (Error?) -> Void)
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

    static let kTinodeImProtocol = "CLAW OS"
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
        queue.async {
            self.localContacts = self.fetchLocalContacts()
            let localIds = Set(self.localContacts?.compactMap { $0.uniqueId } ?? [])
            if let subs = self.fndTopic?.getSubscriptions(), !(self.searchQuery?.isEmpty ?? true) {
                self.remoteContacts = subs.compactMap { sub in
                    guard let uniqueId = sub.uniqueId,
                          ContactsManager.isDirectContactId(uniqueId),
                          !localIds.contains(uniqueId) else {
                        return nil
                    }
                    let accountName = AccountNames.fromTags(sub.priv)
                    let contact = RemoteContactHolder(pub: sub.pub, uniqueId: uniqueId,
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
    }

    func fetchLocalContacts() -> [ContactHolder] {
        return (self.contactsManager.fetchContacts() ?? []).filter {
            ContactsManager.isDirectContactId($0.uniqueId)
                && !($0.uniqueId.map { Cache.tinode.isMe(uid: $0) } ?? true)
        }
    }

    static let kSingleTagTest = try! NSRegularExpression(pattern: #"[\s,:]"#)

    private func matchingLocalContacts(searchQuery: String?) -> [ContactHolder] {
        guard let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return localContacts ?? []
        }
        let cleanQuery = query.first == "@" ? String(query.dropFirst()) : query
        return (localContacts ?? []).filter { contact in
            let displayName = AccountNames.contactDisplayName(displayName: contact.pub?.fn,
                                                               accountName: contact.accountName,
                                                               userId: contact.uniqueId)
            if displayName.range(of: cleanQuery, options: .caseInsensitive) != nil {
                return true
            }
            return contact.accountName?.range(of: cleanQuery, options: .caseInsensitive) != nil
        }
    }

    func loadAndPresentContacts(searchQuery: String? = nil) {
        let changed = self.searchQuery != searchQuery
        self.searchQuery = searchQuery
        queue.async {
            // Always refresh after a directory result is saved as a contact.
            self.localContacts = self.fetchLocalContacts()
            if self.remoteContacts == nil {
               self.remoteContacts = []
            }

            let contacts = self.matchingLocalContacts(searchQuery: self.searchQuery)
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

    func saveRemoteTopic(from remoteContact: RemoteContactHolder, completion: @escaping (Error?) -> Void) {
        guard let topicName = remoteContact.uniqueId, let sub = remoteContact.sub else {
            completion(NSError(domain: "CLAWOS.Find", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Failed to save group and contact info.", comment: "Error message")]))
            return
        }
        let tinode = Cache.tinode
        var topic: DefaultComTopic?
        if !tinode.isTopicTracked(topicName: topicName) {
            topic = tinode.newTopic(for: topicName) as? DefaultComTopic
            topic?.pub = sub.pub
        } else {
            topic = tinode.getTopic(topicName: topicName) as? DefaultComTopic
        }
        guard let topicUnwrapped = topic else {
            completion(NSError(domain: "CLAWOS.Find", code: 2,
                               userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Failed to save group and contact info.", comment: "Error message")]))
            return
        }

        guard topicUnwrapped.isP2PType else {
            completion(NSError(domain: "CLAWOS.Find", code: 3,
                               userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Only user contacts can be added.", comment: "Error message")]))
            return
        }
        if topicUnwrapped.attached {
            completeRemoteTopicSave(topic: topicUnwrapped, subscription: sub, topicName: topicName, completion: completion)
            return
        }
        topicUnwrapped.subscribe().then(
            onSuccess: { [weak self] _ in
                self?.completeRemoteTopicSave(
                    topic: topicUnwrapped,
                    subscription: sub,
                    topicName: topicName,
                    completion: completion)
                return nil
            },
            onFailure: { error in
                completion(error)
                return nil
            })
    }

    private func completeRemoteTopicSave(
        topic: DefaultComTopic,
        subscription: SubscriptionProto,
        topicName: String,
        completion: @escaping (Error?) -> Void) {
        topic.persist()
        contactsManager.processSubscription(sub: subscription)
        queue.async {
            self.localContacts = self.fetchLocalContacts()
            self.remoteContacts?.removeAll { $0.uniqueId == topicName }
            self.presenter?.presentLocalContacts(
                contacts: self.matchingLocalContacts(searchQuery: self.searchQuery))
            self.presenter?.presentRemoteContacts(contacts: self.remoteContacts ?? [])
        }
        completion(nil)
    }
}
