//
//  EditMembersViewController.swift
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

public protocol EditMembersDelegate: AnyObject {
    func editMembersInitialSelection(_: UIView) -> [ContactHolder]
    func editMembersDidEndEditing(_: UIView, added: [String], removed: [String], completion: @escaping (Error?) -> Void)
    func editMembersWillChangeState(_: UIView, uid: String, added: Bool, initiallySelected: Bool) -> Bool
}

class EditMembersViewController: UIViewController, UITableViewDataSource {
    private var contactsManager = ContactsManager()
    private var contacts = [ContactHolder]()
    private var filteredContacts = [ContactHolder]()
    private var initialIds = Set<String>()
    private var selectedIds = Set<String>()
    private var selectedContactIds = [String]()
    private var isSaving = false
    private var wasNavigationBarHidden = false

    private let headerTitleLabel = UILabel()
    private let headerSubtitleLabel = UILabel()
    private let selectedSectionLabel = UILabel()
    private let contactsSectionLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let primaryButton = UIButton(type: .system)

    weak var delegate: EditMembersDelegate?

    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.searchResultsUpdater = self
        controller.obscuresBackgroundDuringPresentation = false
        controller.searchBar.autocapitalizationType = .none
        controller.searchBar.placeholder = NSLocalizedString("搜索联系人", comment: "Member search placeholder")
        ClawTheme.styleSearchBar(controller.searchBar)
        controller.searchBar.delegate = self
        return controller
    }()
    private lazy var doneButtonItem = UIBarButtonItem(
        title: NSLocalizedString("完成", comment: "Button title"),
        style: .done,
        target: self,
        action: #selector(saveClicked(_:)))
    private lazy var cancelButtonItem = UIBarButtonItem(
        title: NSLocalizedString("取消", comment: "Button title"),
        style: .plain,
        target: self,
        action: #selector(cancelClicked(_:)))

    @IBOutlet var editMembersView: UIView!
    @IBOutlet weak var membersTableView: UITableView!
    @IBOutlet weak var selectedCollectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()

        membersTableView.dataSource = self
        membersTableView.delegate = self
        membersTableView.allowsMultipleSelection = true
        membersTableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")
        ClawTheme.styleList(membersTableView, rowHeight: 70)
        view.accessibilityIdentifier = "claw.group.members.screen"
        membersTableView.accessibilityIdentifier = "claw.group.members.list"
        selectedCollectionView.accessibilityIdentifier = "claw.group.members.selected"
        searchController.searchBar.accessibilityIdentifier = "claw.group.members.search"
        primaryButton.accessibilityIdentifier = "claw.group.members.done"
        backButton.accessibilityIdentifier = "claw.group.members.cancel"

        selectedCollectionView.dataSource = self
        selectedCollectionView.register(UINib(nibName: "SelectedMemberViewCell", bundle: nil), forCellWithReuseIdentifier: "SelectedMemberViewCell")
        rebuildPremiumMemberSelection()
        setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        wasNavigationBarHidden = navigationController?.isNavigationBarHidden ?? false
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(wasNavigationBarHidden, animated: false)
    }

    private func rebuildPremiumMemberSelection() {
        let table = membersTableView!
        let collection = selectedCollectionView!
        table.removeFromSuperview()
        collection.removeFromSuperview()
        view.subviews.forEach { $0.removeFromSuperview() }

        view.backgroundColor = ClawTheme.surface
        editMembersView.backgroundColor = ClawTheme.surface

        ClawTheme.styleIconButton(backButton, symbolName: "chevron.left", pointSize: 20, tintColor: ClawTheme.ink)
        backButton.addTarget(self, action: #selector(cancelClicked(_:)), for: .touchUpInside)

        headerTitleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        headerTitleLabel.textColor = ClawTheme.ink
        headerSubtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        headerSubtitleLabel.textColor = ClawTheme.muted

        let searchBar = searchController.searchBar
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundImage = UIImage()

        [selectedSectionLabel, contactsSectionLabel].forEach { label in
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textColor = ClawTheme.ink
        }
        selectedSectionLabel.text = NSLocalizedString("已选择", comment: "Selected group members section")
        contactsSectionLabel.text = NSLocalizedString("联系人", comment: "Contacts section")

        if let flow = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            flow.scrollDirection = .horizontal
            flow.minimumLineSpacing = 8
            flow.minimumInteritemSpacing = 8
            flow.sectionInset = .zero
        }
        collection.delegate = self
        collection.backgroundColor = .clear
        collection.showsHorizontalScrollIndicator = false
        collection.alwaysBounceHorizontal = true

        table.backgroundColor = ClawTheme.surface
        table.separatorColor = ClawTheme.border
        table.separatorInset = UIEdgeInsets(top: 0, left: 88, bottom: 0, right: 18)

        ClawTheme.stylePrimaryButton(primaryButton)
        primaryButton.layer.cornerRadius = 8
        primaryButton.addTarget(self, action: #selector(saveClicked(_:)), for: .touchUpInside)

        [backButton, headerTitleLabel, headerSubtitleLabel, searchBar,
         selectedSectionLabel, collection, contactsSectionLabel, table, primaryButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            backButton.topAnchor.constraint(equalTo: safe.topAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            headerTitleLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 58),
            headerTitleLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 4),
            headerTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -18),
            headerSubtitleLabel.leadingAnchor.constraint(equalTo: headerTitleLabel.leadingAnchor),
            headerSubtitleLabel.topAnchor.constraint(equalTo: headerTitleLabel.bottomAnchor, constant: 1),
            headerSubtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -18),

            searchBar.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            searchBar.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -18),
            searchBar.topAnchor.constraint(equalTo: headerSubtitleLabel.bottomAnchor, constant: 16),
            searchBar.heightAnchor.constraint(equalToConstant: 48),

            selectedSectionLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            selectedSectionLabel.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 16),
            selectedSectionLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -18),
            collection.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            collection.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -18),
            collection.topAnchor.constraint(equalTo: selectedSectionLabel.bottomAnchor, constant: 8),
            collection.heightAnchor.constraint(equalToConstant: 70),

            contactsSectionLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            contactsSectionLabel.topAnchor.constraint(equalTo: collection.bottomAnchor, constant: 8),
            contactsSectionLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -18),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: contactsSectionLabel.bottomAnchor, constant: 6),
            table.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -12),

            primaryButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 18),
            primaryButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -18),
            primaryButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
            primaryButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func setup() {
        var initialContacts = [String: ContactHolder]()
        for contact in delegate?.editMembersInitialSelection(editMembersView) ?? [] {
            guard let uid = contact.uniqueId,
                  ContactsManager.isDirectContactId(uid),
                  !Cache.tinode.isMe(uid: uid) else { continue }
            initialIds.insert(uid)
            selectedIds.insert(uid)
            initialContacts[uid] = contact
        }

        contacts = (contactsManager.fetchContacts() ?? []).filter { contact in
            guard let uid = contact.uniqueId else { return false }
            return ContactsManager.isDirectContactId(uid) && !Cache.tinode.isMe(uid: uid)
        }
        let knownIds = Set(contacts.compactMap { $0.uniqueId })
        for uid in initialIds.subtracting(knownIds).sorted() {
            if ContactsManager.isDirectContactId(uid), let contact = initialContacts[uid] {
                contacts.append(contact)
            }
        }
        filteredContacts = contacts
        selectedContactIds = contacts.compactMap { contact in
            guard let uid = contact.uniqueId, selectedIds.contains(uid) else { return nil }
            return uid
        }
        updateSelectionSummary()
    }

    private func updateSelectionSummary() {
        let selectedCount = selectedIds.filter { !Cache.tinode.isMe(uid: $0) }.count
        let creatingGroup = delegate is NewGroupViewController
        headerTitleLabel.text = creatingGroup
            ? NSLocalizedString("创建群聊", comment: "Group creation member selection title")
            : NSLocalizedString("管理成员", comment: "Group member management title")
        headerSubtitleLabel.text = String(
            format: NSLocalizedString("已选择 %d 人", comment: "Selected group member count"), selectedCount)
        let buttonFormat = creatingGroup
            ? NSLocalizedString("下一步（%d）", comment: "Continue with selected members")
            : NSLocalizedString("保存（%d）", comment: "Save selected group members")
        primaryButton.setTitle(String(format: buttonFormat, selectedCount), for: .normal)
        primaryButton.isEnabled = !isSaving && (!creatingGroup || selectedCount > 0)
    }

    private func contact(for uid: String) -> ContactHolder? {
        return contacts.first { $0.uniqueId == uid }
    }

    private func setUser(_ uid: String, selected: Bool) {
        guard ContactsManager.isDirectContactId(uid), !Cache.tinode.isMe(uid: uid) else { return }
        if selected {
            guard selectedIds.insert(uid).inserted else { return }
            selectedContactIds.append(uid)
        } else {
            selectedIds.remove(uid)
            selectedContactIds.removeAll { $0 == uid }
        }
        selectedCollectionView.reloadData()
        membersTableView.reloadData()
        updateSelectionSummary()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredContacts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell
        let contact = filteredContacts[indexPath.row]
        let selected = contact.uniqueId.map { selectedIds.contains($0) } ?? false

        cell.avatar.set(pub: contact.pub, id: contact.uniqueId, deleted: false)
        cell.title.text = contact.pub?.fn ?? contact.accountName ?? contact.uniqueId
        cell.title.font = .systemFont(ofSize: 15, weight: .semibold)
        cell.title.textColor = ClawTheme.ink
        cell.subtitle.text = contact.subtitle ?? contact.accountName ?? ""
        cell.subtitle.font = .systemFont(ofSize: 12, weight: .regular)
        cell.subtitle.textColor = ClawTheme.muted
        cell.tintColor = ClawTheme.primary
        cell.backgroundColor = ClawTheme.surface
        cell.selectedBackgroundView = {
            let selection = UIView()
            selection.backgroundColor = ClawTheme.brandSoft
            return selection
        }()
        cell.accessoryType = .none
        cell.accessoryView = selectionIndicator(selected: selected)
        if selected {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        } else {
            tableView.deselectRow(at: indexPath, animated: false)
        }
        return cell
    }

    private func selectionIndicator(selected: Bool) -> UIView {
        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        indicator.layer.cornerRadius = 12
        indicator.layer.borderWidth = selected ? 0 : 1.5
        indicator.layer.borderColor = ClawTheme.border.cgColor
        indicator.backgroundColor = selected ? ClawTheme.primary : .clear
        if selected {
            let check = UIImageView(image: ClawTheme.symbol("checkmark", pointSize: 11, weight: .bold))
            check.tintColor = .white
            check.contentMode = .center
            check.frame = indicator.bounds
            indicator.addSubview(check)
        }
        return indicator
    }

    @IBAction func saveClicked(_ sender: Any) {
        guard !isSaving else { return }

        let validSelectedIds = Set(selectedIds.filter {
            ContactsManager.isDirectContactId($0) && !Cache.tinode.isMe(uid: $0)
        })
        let validInitialIds = Set(initialIds.filter {
            ContactsManager.isDirectContactId($0) && !Cache.tinode.isMe(uid: $0)
        })
        selectedIds = validSelectedIds
        initialIds = validInitialIds
        let additions = validSelectedIds.subtracting(validInitialIds).sorted()
        let deletions = validInitialIds.subtracting(validSelectedIds).sorted()
        isSaving = true
        primaryButton.isEnabled = false
        backButton.isEnabled = false
        searchController.searchBar.isUserInteractionEnabled = false
        headerSubtitleLabel.text = NSLocalizedString("正在保存更改", comment: "View title while group member changes are being saved")

        guard let delegate = delegate else {
            finishSaving(error: nil)
            return
        }
        delegate.editMembersDidEndEditing(editMembersView, added: additions, removed: deletions) { [weak self] error in
            DispatchQueue.main.async {
                self?.finishSaving(error: error)
            }
        }
    }

    @IBAction func cancelClicked(_ sender: Any) {
        guard !isSaving else { return }
        closeEditor()
    }

    private func closeEditor() {
        searchController.isActive = false
        if navigationController?.presentingViewController != nil {
            navigationController?.dismiss(animated: true)
        } else if presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private func finishSaving(error: Error?) {
        if let error = error {
            isSaving = false
            backButton.isEnabled = true
            searchController.searchBar.isUserInteractionEnabled = true
            updateSelectionSummary()
            UiUtils.ToastFailureHandler(err: error)
            return
        }
        closeEditor()
    }
}

extension EditMembersViewController: UISearchResultsUpdating, UISearchBarDelegate {
    func updateSearchResults(for searchController: UISearchController) {
        applyFilter(searchController.searchBar.text)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilter(searchText)
    }

    private func applyFilter(_ text: String?) {
        let query = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if query.isEmpty {
            filteredContacts = contacts
        } else {
            filteredContacts = contacts.filter { contact in
                [contact.pub?.fn, contact.accountName, contact.subtitle]
                    .compactMap { $0?.lowercased() }
                    .contains { $0.contains(query) }
            }
        }
        membersTableView.reloadData()
    }
}

extension EditMembersViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let uid = filteredContacts[indexPath.row].uniqueId,
              ContactsManager.isDirectContactId(uid),
              !Cache.tinode.isMe(uid: uid) else { return nil }
        let allowed = delegate?.editMembersWillChangeState(
            editMembersView, uid: uid, added: true, initiallySelected: initialIds.contains(uid)) ?? true
        return allowed ? indexPath : nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let uid = filteredContacts[indexPath.row].uniqueId,
              ContactsManager.isDirectContactId(uid),
              !Cache.tinode.isMe(uid: uid) else { return }
        setUser(uid, selected: true)
    }

    func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let uid = filteredContacts[indexPath.row].uniqueId,
              ContactsManager.isDirectContactId(uid),
              !Cache.tinode.isMe(uid: uid) else { return nil }
        let allowed = delegate?.editMembersWillChangeState(
            editMembersView, uid: uid, added: false, initiallySelected: initialIds.contains(uid)) ?? true
        return allowed ? indexPath : nil
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let uid = filteredContacts[indexPath.row].uniqueId,
              ContactsManager.isDirectContactId(uid),
              !Cache.tinode.isMe(uid: uid) else { return }
        setUser(uid, selected: false)
    }
}

extension EditMembersViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return selectedContactIds.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "SelectedMemberViewCell", for: indexPath) as! SelectedMemberViewCell
        let uid = selectedContactIds[indexPath.item]
        let selectedContact = contact(for: uid)
        cell.avatarImageView.set(pub: selectedContact?.pub, id: uid, deleted: false)
        cell.configure(name: selectedContact?.pub?.fn ?? selectedContact?.accountName ?? uid)
        cell.onRemove = { [weak self] in
            guard let self = self else { return }
            let allowed = self.delegate?.editMembersWillChangeState(
                self.editMembersView, uid: uid, added: false,
                initiallySelected: self.initialIds.contains(uid)) ?? true
            if allowed {
                self.setUser(uid, selected: false)
            }
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 64, height: 70)
    }
}
