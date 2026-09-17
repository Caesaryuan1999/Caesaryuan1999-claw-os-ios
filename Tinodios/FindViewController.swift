//
//  FindViewController.swift
//  Tinodios
//
//  Copyright © 2019-2025 Tinode. All rights reserved.
//

import Contacts
import MessageUI
import UIKit
import TinodeSDK

protocol FindDisplayLogic: AnyObject {
    func displayLocalContacts(contacts: [ContactHolder])
    func displayRemoteContacts(contacts: [RemoteContactHolder])
}

class FindViewController: UITableViewController, FindDisplayLogic {
    static let kLocalSavedMessagesSection = 0
    static let kLocalContactsSection = 1
    static let kRemoteContactsSection = 2

    @IBOutlet weak var inviteActionButtonItem: UIBarButtonItem!
    var interactor: FindBusinessLogic?
    var localContacts: [ContactHolder] = []
    var remoteContacts: [RemoteContactHolder] = []
    var searchController: UISearchController!
    var pendingSearchRequest: DispatchWorkItem?
    private var isSavingRemoteContact = false
    var isSelectingContactForCall = false
    private let premiumHeader = ClawContactsHeaderView()

    // Flag which indicates that the user is leaving the view.
    var transitioningOut: Bool = false

    private func addAppStateObservers() {
        // App state observers.
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.deviceRotated),
            name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    private func removeAppStateObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil)
    }

    private func updateSearchBarPlaceholder(authStatus: CNAuthorizationStatus) {
        let placeholderText: String
        let placeholderFontSize: CGFloat
        placeholderText = NSLocalizedString("搜索联系人", comment: "Contacts search placeholder")
        placeholderFontSize = 15
        searchController.searchBar.searchTextField.attributedPlaceholder =
            NSAttributedString(
                string: placeholderText,
                attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: placeholderFontSize),
                             NSAttributedString.Key.foregroundColor: UIColor.systemGray])
    }

    func createDependencies() -> (FindBusinessLogic, FindPresentationLogic) {
        return (FindInteractor(), FindPresenter())
    }

    private func setup() {
        let viewController = self
        var (interactor, presenter) = createDependencies()

        viewController.interactor = interactor
        interactor.presenter = presenter
        presenter.viewController = viewController

        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        ContactsSynchronizer.default.permissionsChangedCallback = { [weak self] authStatus in
            DispatchQueue.main.async {
                self?.updateSearchBarPlaceholder(authStatus: authStatus)
            }
        }

        premiumHeader.install(searchBar: searchController.searchBar)
        premiumHeader.onAddContact = { [weak self] in self?.activateContactSearch() }
        premiumHeader.onCreateGroup = { [weak self] in self?.openNewGroup() }
        premiumHeader.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 210)
        self.tableView.tableHeaderView = premiumHeader
        self.tableView.register(UINib(nibName: "ContactViewCell", bundle: nil), forCellReuseIdentifier: "ContactViewCell")

        transitioningOut = false

        searchController.delegate = self
        // The default is true.
        searchController.obscuresBackgroundDuringPresentation = false
        // Monitor when the search button is tapped.
        searchController.searchBar.delegate = self
        self.definesPresentationContext = true

        if !Cache.isContactSynchronizerActive() {
            Cache.synchronizeContactsPeriodically()
        }
        self.updateSearchBarPlaceholder(authStatus: ContactsSynchronizer.default.authStatus)

        navigationItem.title = NSLocalizedString("通讯录", comment: "Contacts screen title")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        inviteActionButtonItem.image = ClawTheme.symbol("person.badge.plus", pointSize: ClawTheme.iconCompact, weight: .medium)
        inviteActionButtonItem.tintColor = ClawTheme.primary
        inviteActionButtonItem.accessibilityLabel = NSLocalizedString("添加联系人", comment: "Add contact action")
        view.accessibilityIdentifier = "claw.contacts.screen"
        tableView.accessibilityIdentifier = "claw.contacts.list"
        searchController.searchBar.accessibilityIdentifier = "claw.contacts.search"
        inviteActionButtonItem.accessibilityIdentifier = "claw.contacts.add"
        ClawTheme.styleSearchBar(searchController.searchBar)
        ClawTheme.styleList(tableView, rowHeight: 84)
        tableView.backgroundColor = ClawTheme.background
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 94
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        addAppStateObservers()
    }

    deinit {
        removeAppStateObservers()
    }

    func displayLocalContacts(contacts newContacts: [ContactHolder]) {
        assert(Thread.isMainThread)
        self.localContacts = newContacts
        self.tableView.reloadData()
    }

    func displayRemoteContacts(contacts newContacts: [RemoteContactHolder]) {
        assert(Thread.isMainThread)
        self.remoteContacts = newContacts.filter { interactor?.canUse($0, input: getQueryString()) == true }
        self.tableView.reloadData()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setup()
    }

    private func scrollToTop() {
        if self.tableView.indexPathsForVisibleRows?.count ?? 0 > 0 {
            let topIndexPath = IndexPath(row: 0, section: 0)
            self.tableView.scrollToRow(at: topIndexPath, at: .top, animated: false)
        }
    }

    @objc
    func deviceRotated() {
        updateHeaderLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderLayout()
    }

    private func updateHeaderLayout() {
        ClawProfileLayout.fitHeader(in: tableView)
    }

    private func activateContactSearch() {
        searchController.isActive = true
        DispatchQueue.main.async { [weak self] in
            self?.searchController.searchBar.searchTextField.becomeFirstResponder()
        }
    }

    private func openNewGroup() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let controller = storyboard.instantiateViewController(withIdentifier: "NewGroup")
        navigationController?.pushViewController(controller, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.prefersLargeTitles = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.interactor?.setup()
        self.interactor?.attachToFndTopic()
        self.interactor?.loadAndPresentContacts(searchQuery: nil)
        self.navigationItem.rightBarButtonItem = nil
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.interactor?.cleanup()
        self.navigationItem.rightBarButtonItem = nil
    }

    @IBAction func inviteActionClicked(_ sender: Any) {
        let alert = UIAlertController(title: NSLocalizedString("新增", comment: "Contacts add menu title"), message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("发起群聊", comment: "Start a group chat"), style: .default, handler: { [weak self] _ in
            self?.openNewGroup()
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("查找联系人", comment: "Find contacts"), style: .default, handler: { [weak self] _ in
            self?.activateContactSearch()
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("邀请朋友", comment: "Invite a friend"), style: .default, handler: { [weak self] _ in
            self?.presentInviteOptions()
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Cancel action"), style: .cancel, handler: nil))
        alert.popoverPresentationController?.barButtonItem = inviteActionButtonItem
        present(alert, animated: true)
    }

    private func presentInviteOptions() {
        UiUtils.showToast(message: NSLocalizedString("邀请链接尚未配置，请通过 CLAW 号查找联系人。", comment: "Invite link unavailable"))
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case FindViewController.kLocalSavedMessagesSection:
            return getQueryString() != nil ? 0 : 1
        case FindViewController.kLocalContactsSection:
            return localContacts.isEmpty ? 1 : localContacts.count
        case FindViewController.kRemoteContactsSection:
            guard getQueryString() != nil else { return 0 }
            return remoteContacts.isEmpty ? 1 : remoteContacts.count
        default:
            return 0
        }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case FindViewController.kLocalContactsSection:
            return NSLocalizedString("联系人", comment: "Section title")
        case FindViewController.kRemoteContactsSection:
            return getQueryString() == nil ? nil : NSLocalizedString("搜索结果", comment: "Section title")
        default:
            // Saved Messages has no section title.
            return nil
        }
    }

    override func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == FindViewController.kLocalSavedMessagesSection ||
            (section == FindViewController.kRemoteContactsSection && getQueryString() == nil) {
            // Hide Saved Messages section title.
            return CGFloat.leastNonzeroMagnitude
        }
        return 40.0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isSectionEmpty(section: indexPath.section) {
            return makeEmptyContactsCell(for: indexPath.section)
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ContactViewCell", for: indexPath) as! ContactViewCell
            cell.delegate = self

            // Configure the cell...
            if indexPath.section == FindViewController.kLocalSavedMessagesSection {
                cell.avatar.set(pub: nil, id: Tinode.kTopicSlf, deleted: false)
                cell.avatar.setBrandingIcon()
                cell.title.text = NSLocalizedString("CLAW文件助手", comment: "Title of the CLAW file assistant")
                cell.subtitle.text = NSLocalizedString("为以后保存的注释、消息、链接、文件", comment: "Explanation for Saved messages topic")
                cell.subtitle.isHidden = false
            } else {
                let contact = indexPath.section == FindViewController.kLocalContactsSection ? localContacts[indexPath.row] : remoteContacts[indexPath.row]

                cell.avatar.set(pub: contact.pub, id: contact.uniqueId, deleted: false)
                cell.title.text = AccountNames.contactDisplayName(displayName: contact.pub?.fn,
                                                                   accountName: contact.accountName,
                                                                   userId: contact.uniqueId)
                let publicName = AccountNames.contactListSecondary(accountName: contact.accountName)
                let subtitle = publicName.map { "CLAW号：" + $0 } ?? contact.subtitle
                cell.subtitle.text = subtitle ?? "暂未设置 CLAW号"
                cell.subtitle.isHidden = false
            }
            cell.title.sizeToFit()
            cell.subtitle.sizeToFit()
            return cell
        }
    }

    private func isSectionEmpty(section: Int) -> Bool {
        switch section {
        case FindViewController.kLocalSavedMessagesSection:
            return getQueryString() != nil
        case FindViewController.kLocalContactsSection:
            return localContacts.isEmpty
        case FindViewController.kRemoteContactsSection:
            return getQueryString() != nil && remoteContacts.isEmpty
        default:
            return true
        }
    }

    func getUniqueId(for path: IndexPath) -> String? {
        switch path.section {
        case FindViewController.kLocalSavedMessagesSection:
            return Tinode.kTopicSlf
        case FindViewController.kLocalContactsSection:
            return self.localContacts[path.row].uniqueId
        case FindViewController.kRemoteContactsSection:
            return self.remoteContacts[path.row].uniqueId
        default: return nil
        }
    }

    // Opens a chat with the given id.
    func jumpTo(topic topicId: String) {
        presentChatReplacingCurrentVC(with: topicId)
    }
}

// MARK: - Search functionality

extension FindViewController: UISearchResultsUpdating, UISearchControllerDelegate, UISearchBarDelegate {

    public func cancelPendingSearchRequest(deactivateSearch dismiss: Bool) {
        pendingSearchRequest?.cancel()
        pendingSearchRequest = nil
        if dismiss {
            searchController.isActive = false
        }
    }

    private func doSearch(queryString: String?) {
        self.interactor?.loadAndPresentContacts(searchQuery: queryString)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        cancelPendingSearchRequest(deactivateSearch: false)
        guard let s = getQueryString() else { return }
        doSearch(queryString: s)
    }

    private func getQueryString() -> String? {
        let whitespaceCharacterSet = CharacterSet.whitespaces
        let queryString =
            (searchController.searchBar.text ?? "").trimmingCharacters(in: whitespaceCharacterSet)
        return !queryString.isEmpty ? queryString : nil
    }

    func updateSearchResults(for searchController: UISearchController) {
        cancelPendingSearchRequest(deactivateSearch: false)

        if transitioningOut {
            return
        }
        let queryString = getQueryString()
        interactor?.invalidateDirectorySearch(input: queryString)
        remoteContacts.removeAll()
        tableView.reloadData()
        let currentSearchRequest = DispatchWorkItem {
            self.doSearch(queryString: queryString)
        }
        pendingSearchRequest = currentSearchRequest
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: currentSearchRequest)
    }

    // Search controller is dismissed if user clears the query OR if the user clicked on an item
    // and is moving to another view. In the second case no need to loadAndPresentContacts because
    // fnd.leave() will be called anyway. Otherwise an update to content prevents notmal navigation.
    func didDismissSearchController(_ searchController: UISearchController) {
        cancelPendingSearchRequest(deactivateSearch: false)
        if !transitioningOut {
            self.interactor?.loadAndPresentContacts(searchQuery: nil)
        }
    }
}

extension FindViewController: ContactViewCellDelegate {
    func selected(from cell: UITableViewCell) {
        guard let indexPath = tableView.indexPathForSelectedRow else { return }
        guard let id = getUniqueId(for: indexPath) else { return }
        if indexPath.section == FindViewController.kRemoteContactsSection {
            guard !isSavingRemoteContact else { return }
            guard let interactor = interactor,
                  remoteContacts.indices.contains(indexPath.row) else { return }
            let selected = remoteContacts[indexPath.row]
            guard interactor.canUse(selected, input: getQueryString()) else { return }
            isSavingRemoteContact = true
            tableView.isUserInteractionEnabled = false
            interactor.saveRemoteTopic(from: selected) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isSavingRemoteContact = false
                    self.tableView.isUserInteractionEnabled = true
                    if let error = error {
                        UiUtils.ToastFailureHandler(err: error)
                        return
                    }
                    guard interactor.canUse(selected, input: self.getQueryString()) else { return }
                    UiUtils.showToast(message: NSLocalizedString("Added to contacts", comment: "Directory search result saved"))
                    self.openSelectedContact(id: id)
                }
            }
            return
        }

        openSelectedContact(id: id)
    }

    private func openSelectedContact(id: String) {
        // Make sure there are no pending search requests.
        cancelPendingSearchRequest(deactivateSearch: false)

        if isSelectingContactForCall {
            presentCallTypePicker(for: id)
            return
        }
        transitioningOut = true

        // If the search bar is active, deactivate it.
        if searchController.isActive {
            // Disable the animation as we are going straight to another view.
            // This call takes very long time to complete.
            searchController.dismiss(animated: false, completion: { self.jumpTo(topic: id) })
        } else {
            jumpTo(topic: id)
        }
    }

    private func makeEmptyContactsCell(for section: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.backgroundColor = ClawTheme.surface

        let iconView = UIImageView(image: UIImage(
            systemName: section == FindViewController.kRemoteContactsSection
                ? "person.2"
                : "person.2.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = ClawTheme.muted
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentHuggingPriority(.required, for: .vertical)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = section == FindViewController.kRemoteContactsSection
            ? NSLocalizedString("No results", comment: "Empty search results")
            : NSLocalizedString("暂无联系人，可通过 CLAW 号查找并添加。", comment: "Empty contacts list")
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = ClawTheme.muted
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        cell.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: cell.contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -18)
        ])
        return cell
    }

    private func presentCallTypePicker(for topicId: String) {
        let alert = UIAlertController(
            title: NSLocalizedString("发起通话", comment: "Start call title"),
            message: NSLocalizedString("选择通话方式", comment: "Choose call type"),
            preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("语音通话", comment: "Audio call"),
            style: .default) { [weak self] _ in
                self?.startCall(topicId: topicId, audioOnly: true)
            })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("视频通话", comment: "Video call"),
            style: .default) { [weak self] _ in
                self?.startCall(topicId: topicId, audioOnly: false)
            })
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("取消", comment: "Cancel"),
            style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 32, width: 1, height: 1)
        }
        present(alert, animated: true)
    }

    private func startCall(topicId: String, audioOnly: Bool) {
        isSelectingContactForCall = false
        UiUtils.routeToMessageVC(forTopic: topicId) { messageVC in
            guard let messageVC = messageVC else { return }
            let callType = audioOnly
                ? MessageViewController.Constants.kAudioOnlyCall
                : MessageViewController.Constants.kVideoCall
            messageVC.performSegue(withIdentifier: "Messages2Call", sender: callType)
        }
    }
}

extension FindViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}

extension FindViewController: MFMessageComposeViewControllerDelegate {
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: true)
    }
}

// MARK: - R3.D1 contacts actions
private final class ClawContactsHeaderView: UIView {
    var onAddContact: (() -> Void)?
    var onCreateGroup: (() -> Void)?
    private let searchContainer = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func install(searchBar: UISearchBar) {
        searchBar.removeFromSuperview()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor),
            searchBar.topAnchor.constraint(equalTo: searchContainer.topAnchor),
            searchBar.bottomAnchor.constraint(equalTo: searchContainer.bottomAnchor)
        ])
    }

    private func setupViews() {
        backgroundColor = ClawTheme.background
        let brand = ClawProfileLayout.label("CLAW OS", size: 12, color: ClawTheme.primary)
        let add = UIButton(type: .system)
        ClawTheme.styleSecondaryButton(add)
        add.setTitle("添加联系人", for: .normal)
        add.titleLabel?.numberOfLines = 0
        add.accessibilityIdentifier = "claw.contacts.add"
        add.backgroundColor = ClawTheme.brandSoft
        add.layer.cornerRadius = 12
        add.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        add.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        add.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        let top = UIStackView(arrangedSubviews: [brand, UIView(), add])
        top.alignment = .center
        top.spacing = 12

        let group = UIButton(type: .system)
        ClawTheme.styleSecondaryButton(group)
        group.setTitle("发起群聊", for: .normal)
        group.titleLabel?.numberOfLines = 0
        let chevron = UIImageView(image: ClawTheme.symbol("chevron.right", pointSize: 16, weight: .regular))
        chevron.tintColor = ClawTheme.muted
        chevron.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: group.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: group.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 20),
            chevron.heightAnchor.constraint(equalToConstant: 20)
        ])
        group.accessibilityIdentifier = "claw.contacts.create-group"
        group.backgroundColor = ClawTheme.surface
        group.layer.cornerRadius = 12
        group.contentHorizontalAlignment = .leading
        group.contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 48)
        group.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        group.addTarget(self, action: #selector(groupTapped), for: .touchUpInside)

        searchContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        let stack = UIStackView(arrangedSubviews: [top, searchContainer, group])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    @objc private func addTapped() { onAddContact?() }
    @objc private func groupTapped() { onCreateGroup?() }
}
