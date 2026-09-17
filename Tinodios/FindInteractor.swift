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
    func invalidateDirectorySearch(input: String?)
    func canUse(_ remoteContact: RemoteContactHolder, input: String?) -> Bool
    func updateAndPresentRemoteContacts()
    func saveRemoteTopic(from remoteContact: RemoteContactHolder, completion: @escaping (Error?) -> Void)
    func setup()
    func cleanup()
    func attachToFndTopic()
}

class RemoteContactHolder: ContactHolder {
    var sub: FndSubscription?
    var lookupTicket: ClawPublicDirectoryLookup.Ticket?
}

class FindInteractor: FindBusinessLogic {
    private class FndListener: DefaultFndTopic.Listener {
        weak var interactor: FindBusinessLogic?
        override func onSubsUpdated() { interactor?.updateAndPresentRemoteContacts() }
    }

    static let kTinodeImProtocol = "CLAW OS"
    var presenter: FindPresentationLogic?
    // Query state, result acceptance and clicks share the UI queue.
    private var localContacts: [ContactHolder]?
    private var searchQuery: String?
    private var owner: Tinode?
    private var active = false
    var fndTopic: DefaultFndTopic?
    private var fndListener: FndListener?
    private var remoteContacts: [RemoteContactHolder] = []
    private let contactsManager = ContactsManager()
    private let lookup = ClawPublicDirectoryLookup()
    private static var staleLookup: NSError {
        NSError(domain: "CLAWOS.Find", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "查找已失效，请重新输入完整 CLAW号"])
    }

    func setup() {
        lookup.invalidate()
        fndTopic = nil
        owner = Cache.tinode
        active = true
        fndListener = FndListener()
        fndListener?.interactor = self
    }

    func cleanup() {
        active = false
        lookup.invalidate()
        remoteContacts.removeAll()
        fndTopic?.listener = nil
        if fndTopic?.attached == true { fndTopic?.leave() }
    }

    func attachToFndTopic() {
        guard active, let owner = owner, Cache.isCurrent(owner) else { return }
        let fnd = owner.getOrCreateFndTopic()
        fnd.listener = fndListener
        let attached = fnd.attached ? PromisedReply<ServerMessage>(value: ServerMessage()) : fnd.subscribe(set: nil, get: nil)
        attached.then(onSuccess: { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.active, Cache.isCurrent(owner), self.owner === owner else { return }
                self.fndTopic = fnd
                self.loadAndPresentContacts(searchQuery: self.searchQuery)
            }
            return nil
        }, onFailure: { _ in
            Cache.log.error("Directory attachment failed")
            return nil
        })
    }

    func invalidateDirectorySearch(input: String?) {
        searchQuery = input
        lookup.invalidate()
        remoteContacts.removeAll()
        presenter?.presentRemoteContacts(contacts: [])
    }

    func canUse(_ remoteContact: RemoteContactHolder, input: String?) -> Bool {
        guard active, let owner = owner, Cache.isCurrent(owner), owner.isConnectionAuthenticated,
              let ticket = remoteContact.lookupTicket, let sub = remoteContact.sub,
              remoteContact.uniqueId == (sub.user ?? sub.topic) else { return false }
        return lookup.matches(ticket, owner: owner, input: input, subscription: sub)
    }

    func updateAndPresentRemoteContacts() {
        // fnd cache callbacks have no request/query identity. Only the matching
        // getMeta promise below may admit subscriptions to the visible results.
    }

    func fetchLocalContacts() -> [ContactHolder] {
        guard let owner = owner else { return [] }
        return Cache.ifCurrent(owner) {
            ClawLocalContactRead.read(active: active, owner: owner, slotIsCurrent: { Cache.isCurrent(owner) }) {
                (contactsManager.fetchContacts() ?? []).filter {
                    ContactsManager.isDirectContactId($0.uniqueId)
                        && !($0.uniqueId.map { owner.isMe(uid: $0) } ?? true)
                }
            }
        } ?? []
    }

    private func matchingLocalContacts(searchQuery: String?) -> [ContactHolder] {
        guard let query = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return localContacts ?? []
        }
        let cleanQuery = query.first == "@" ? String(query.dropFirst()) : query
        return (localContacts ?? []).filter { contact in
            let name = AccountNames.contactDisplayName(displayName: contact.pub?.fn,
                                                        accountName: contact.accountName, userId: contact.uniqueId)
            return name.range(of: cleanQuery, options: .caseInsensitive) != nil
                || contact.accountName?.range(of: cleanQuery, options: .caseInsensitive) != nil
        }
    }

    func loadAndPresentContacts(searchQuery: String? = nil) {
        invalidateDirectorySearch(input: searchQuery)
        localContacts = fetchLocalContacts()
        presenter?.presentLocalContacts(contacts: matchingLocalContacts(searchQuery: searchQuery))
        guard active, let owner = owner, Cache.isCurrent(owner), owner.isConnectionAuthenticated,
              let fnd = fndTopic, fnd.attached,
              let ticket = lookup.begin(input: searchQuery, owner: owner) else { return }
        fnd.setMeta(desc: MetaSetDesc(pub: ticket.wireQuery, priv: nil)).thenApply { [weak self] _ in
            guard let self = self, Cache.isCurrent(owner),
                  self.lookup.isCurrent(ticket, owner: owner, input: ticket.input) else {
                return PromisedReply<ServerMessage>(error: Self.staleLookup)
            }
            return fnd.getMeta(query: MsgGetMeta.sub())
        }.then(onSuccess: { [weak self] response in
            DispatchQueue.main.async {
                guard let self = self, self.active, Cache.isCurrent(owner),
                      self.lookup.isCurrent(ticket, owner: owner, input: self.searchQuery) else { return }
                let localIds = Set(self.localContacts?.compactMap { $0.uniqueId } ?? [])
                self.remoteContacts = (response?.meta?.sub?.compactMap { $0 as? FndSubscription } ?? []).compactMap { sub in
                    var contact: RemoteContactHolder?
                    self.lookup.consume(ticket, owner: owner, input: self.searchQuery, subscription: sub) { uid in
                        guard ContactsManager.isDirectContactId(uid), !localIds.contains(uid), !owner.isMe(uid: uid) else { return }
                        let accountName = AccountNames.fromTags(sub.priv)
                        let found = RemoteContactHolder(pub: sub.pub, uniqueId: uid, accountName: accountName,
                            subtitle: AccountNames.contactListSecondary(accountName: accountName))
                        found.sub = sub
                        found.lookupTicket = ticket
                        contact = found
                    }
                    return contact
                }
                self.presenter?.presentRemoteContacts(contacts: self.remoteContacts)
            }
            return nil
        }, onFailure: { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, Cache.isCurrent(owner),
                      self.lookup.isCurrent(ticket, owner: owner, input: self.searchQuery) else { return }
                self.presenter?.presentRemoteContacts(contacts: [])
            }
            return nil
        })
    }

    func saveRemoteTopic(from remoteContact: RemoteContactHolder, completion: @escaping (Error?) -> Void) {
        guard canUse(remoteContact, input: searchQuery), let owner = owner,
              let ticket = remoteContact.lookupTicket, let sub = remoteContact.sub else {
            completion(Self.staleLookup); return
        }
        var selected: DefaultComTopic?
        lookup.consume(ticket, owner: owner, input: searchQuery, subscription: sub) { uid in
            selected = Cache.ifCurrent(owner) {
                if let existing = owner.getTopic(topicName: uid) as? DefaultComTopic { return existing }
                let created = owner.newTopic(for: uid) as? DefaultComTopic
                created?.pub = sub.pub
                return created
            } ?? nil
        }
        guard let topic = selected, topic.isP2PType else { completion(Self.staleLookup); return }
        let finish = { [weak self] in
            guard let self = self, self.canUse(remoteContact, input: self.searchQuery) else {
                completion(Self.staleLookup); return
            }
            var saved = false
            self.lookup.consume(ticket, owner: owner, input: self.searchQuery, subscription: sub) { _ in
                saved = Cache.ifCurrent(owner) {
                    topic.persist()
                    self.contactsManager.processSubscription(sub: sub)
                    return true
                } ?? false
            }
            guard saved else { completion(Self.staleLookup); return }
            self.localContacts = self.fetchLocalContacts()
            self.remoteContacts.removeAll { $0.uniqueId == remoteContact.uniqueId }
            self.presenter?.presentLocalContacts(contacts: self.matchingLocalContacts(searchQuery: self.searchQuery))
            self.presenter?.presentRemoteContacts(contacts: self.remoteContacts)
            completion(nil)
        }
        if topic.attached { finish(); return }
        guard canUse(remoteContact, input: searchQuery) else { completion(Self.staleLookup); return }
        topic.subscribe().then(onSuccess: { _ in
            DispatchQueue.main.async(execute: finish)
            return nil
        }, onFailure: { error in
            DispatchQueue.main.async { completion(error) }
            return nil
        })
    }
}
