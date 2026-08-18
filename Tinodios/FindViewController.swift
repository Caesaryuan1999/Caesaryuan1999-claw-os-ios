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
        placeholderText = NSLocalizedString("搜索用户名", comment: "Contacts search placeholder")
        placeholderFontSize = 15
        searchController.searchBar.textField?.attributedPlaceholder =
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
        premiumHeader.collectionView.dataSource = self
        premiumHeader.collectionView.delegate = self
        premiumHeader.collectionView.register(
            ClawActiveContactCell.self,
            forCellWithReuseIdentifier: ClawActiveContactCell.reuseIdentifier)
        premiumHeader.onViewAll = { [weak self] in
            guard let self = self, !self.localContacts.isEmpty else { return }
            self.tableView.scrollToRow(
                at: IndexPath(row: 0, section: FindViewController.kLocalContactsSection),
                at: .top,
                animated: true)
        }
        premiumHeader.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: ClawContactsHeaderView.height)
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
        inviteActionButtonItem.image = ClawTheme.symbol("person.badge.plus", pointSize: ClawTheme.iconCompact, weight: .medium)
        inviteActionButtonItem.tintColor = ClawTheme.primary
        view.accessibilityIdentifier = "claw.contacts.screen"
        tableView.accessibilityIdentifier = "claw.contacts.list"
        searchController.searchBar.accessibilityIdentifier = "claw.contacts.search"
        inviteActionButtonItem.accessibilityIdentifier = "claw.contacts.add"
        ClawTheme.styleSearchBar(searchController.searchBar)
        ClawTheme.styleList(tableView, rowHeight: 76)
        tableView.backgroundColor = ClawTheme.surface
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
        self.premiumHeader.collectionView.reloadData()
        self.tableView.reloadData()
    }

    func displayRemoteContacts(contacts newContacts: [RemoteContactHolder]) {
        assert(Thread.isMainThread)
        self.remoteContacts = newContacts
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
        guard premiumHeader.frame.width != tableView.bounds.width else {
            premiumHeader.collectionView.collectionViewLayout.invalidateLayout()
            return
        }
        premiumHeader.frame = CGRect(
            x: 0,
            y: 0,
            width: tableView.bounds.width,
            height: ClawContactsHeaderView.height)
        tableView.tableHeaderView = premiumHeader
        premiumHeader.collectionView.collectionViewLayout.invalidateLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.interactor?.setup()
        self.interactor?.attachToFndTopic()
        self.interactor?.loadAndPresentContacts(searchQuery: nil)
        self.navigationItem.rightBarButtonItem = inviteActionButtonItem
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.interactor?.cleanup()
        self.navigationItem.rightBarButtonItem = nil
    }

    @IBAction func inviteActionClicked(_ sender: Any) {
        let alert = UIAlertController(title: NSLocalizedString("新增", comment: "Contacts add menu title"), message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("发起群聊", comment: "Start a group chat"), style: .default, handler: { [weak self] _ in
            guard let self = self else { return }
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let controller = storyboard.instantiateViewController(withIdentifier: "NewGroup")
            self.navigationController?.pushViewController(controller, animated: true)
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("查找联系人", comment: "Find contacts"), style: .default, handler: { [weak self] _ in
            guard let self = self else { return }
            self.searchController.isActive = true
            DispatchQueue.main.async {
                self.searchController.searchBar.searchTextField.becomeFirstResponder()
            }
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("邀请朋友", comment: "Invite a friend"), style: .default, handler: { [weak self] _ in
            self?.presentInviteOptions()
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Cancel action"), style: .cancel, handler: nil))
        alert.popoverPresentationController?.barButtonItem = inviteActionButtonItem
        present(alert, animated: true)
    }

    private func presentInviteOptions() {
        let inviteSubject = NSLocalizedString("CLAW OS", comment: "Invitation subject")
        let inviteBody = NSLocalizedString("下载 CLAW OS： https://veilping.app/", comment: "Invitation body")
        let attrs = [ NSAttributedString.Key.font: UIFont.systemFont(ofSize: 20.0) ]
        let dialogTitle = NSAttributedString(string: NSLocalizedString("Invite", comment: "Dialog title: call to action"), attributes: attrs)
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.setValue(dialogTitle, forKey: "attributedTitle")
        alert.addAction(UIAlertAction(title: NSLocalizedString("Copy to clipboard", comment: "Alert action"), style: .default, handler: { _ in
            let pasteboard = UIPasteboard.general
            pasteboard.string = inviteBody
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Email", comment: "Alert action"), style: .default, handler: { _ in
            if MFMailComposeViewController.canSendMail() {
                let mailVC = MFMailComposeViewController()
                mailVC.mailComposeDelegate = self
                mailVC.setSubject(inviteSubject)
                mailVC.setMessageBody(inviteBody, isHTML: false)

                self.present(mailVC, animated: true)
            } else {
                UiUtils.showToast(message: NSLocalizedString("No access to email", comment: "Error message"))
            }
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Messages", comment: "Alert action"), style: .default, handler: { _ in
            if MFMessageComposeViewController.canSendText() {
                let messageVC = MFMessageComposeViewController()
                messageVC.messageComposeDelegate = self
                messageVC.body = inviteBody

                self.present(messageVC, animated: true)
            } else {
                UiUtils.showToast(message: NSLocalizedString("No access to messages", comment: "Toast error message"))
            }
        }))
        alert.addAction(UIAlertAction(title: NSLocalizedString("取消", comment: "Cancel action"), style: .cancel, handler: nil))
        alert.popoverPresentationController?.barButtonItem = inviteActionButtonItem
        self.present(alert, animated: true)
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
                cell.title.text = NSLocalizedString("已保存消息", comment: "Title of the slf topic")
                cell.subtitle.text = NSLocalizedString("为以后保存的注释、消息、链接、文件", comment: "Explanation for Saved messages topic")
                cell.subtitle.isHidden = false
            } else {
                let contact = indexPath.section == FindViewController.kLocalContactsSection ? localContacts[indexPath.row] : remoteContacts[indexPath.row]

                cell.avatar.set(pub: contact.pub, id: contact.uniqueId, deleted: false)
                cell.title.text = AccountNames.contactDisplayName(displayName: contact.pub?.fn,
                                                                   accountName: contact.accountName,
                                                                   userId: contact.uniqueId)
                let subtitle = contact.subtitle ?? AccountNames.contactListSecondary(accountName: contact.accountName)
                cell.subtitle.text = subtitle ?? ""
                cell.subtitle.isHidden = subtitle == nil
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
            searchController.searchBar.text!.trimmingCharacters(in: whitespaceCharacterSet)
        return !queryString.isEmpty ? queryString : nil
    }

    func updateSearchResults(for searchController: UISearchController) {
        cancelPendingSearchRequest(deactivateSearch: false)

        if transitioningOut {
            return
        }
        let queryString = getQueryString()
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
            guard let interactor = interactor else { return }
            isSavingRemoteContact = true
            tableView.isUserInteractionEnabled = false
            interactor.saveRemoteTopic(from: remoteContacts[indexPath.row]) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isSavingRemoteContact = false
                    self.tableView.isUserInteractionEnabled = true
                    if let error = error {
                        UiUtils.ToastFailureHandler(err: error)
                        return
                    }
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
            : NSLocalizedString("暂无联系人，可通过用户名搜索并添加。", comment: "Empty contacts list")
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

// MARK: - CLAW OS premium contacts header

extension FindViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private var activeContacts: [ContactHolder] {
        let activeCallTopic = Cache.callManager.callInProgress?.topic
        return localContacts.sorted { lhs, rhs in
            let lhsInCall = lhs.uniqueId == activeCallTopic
            let rhsInCall = rhs.uniqueId == activeCallTopic
            if lhsInCall != rhsInCall {
                return lhsInCall && !rhsInCall
            }
            let lhsOnline = contactOnlineStatus(lhs)
            let rhsOnline = contactOnlineStatus(rhs)
            if lhsOnline != rhsOnline {
                return lhsOnline && !rhsOnline
            }
            let lhsName = AccountNames.contactDisplayName(
                displayName: lhs.pub?.fn,
                accountName: lhs.accountName,
                userId: lhs.uniqueId)
            let rhsName = AccountNames.contactDisplayName(
                displayName: rhs.pub?.fn,
                accountName: rhs.accountName,
                userId: rhs.uniqueId)
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private func contactOnlineStatus(_ contact: ContactHolder) -> Bool {
        guard let topicName = contact.uniqueId,
              let topic = Cache.tinode.getTopic(topicName: topicName) as? DefaultComTopic else {
            return false
        }
        return topic.online
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let count = activeContacts.count
        let visibleCount = ActiveContactsLayoutMetrics.visibleCount(
            viewportWidth: collectionView.bounds.width,
            horizontalInset: 20)
        collectionView.alwaysBounceHorizontal = count > visibleCount
        return count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ClawActiveContactCell.reuseIdentifier,
            for: indexPath) as? ClawActiveContactCell else {
            return UICollectionViewCell()
        }
        let contact = activeContacts[indexPath.item]
        let inCall = contact.uniqueId == Cache.callManager.callInProgress?.topic
        let online = contactOnlineStatus(contact)
        cell.configure(
            pub: contact.pub,
            id: contact.uniqueId,
            name: AccountNames.contactDisplayName(
                displayName: contact.pub?.fn,
                accountName: contact.accountName,
                userId: contact.uniqueId),
            status: inCall
                ? NSLocalizedString("通话中", comment: "Contact is currently in a call")
                : online
                    ? NSLocalizedString("在线", comment: "Online contact status")
                    : NSLocalizedString("最近活跃", comment: "Recently active contact status"),
            online: online,
            inCall: inCall)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < activeContacts.count,
              let id = activeContacts[indexPath.item].uniqueId else { return }
        openSelectedContact(id: id)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(
            width: ActiveContactsLayoutMetrics.itemWidth(
                viewportWidth: collectionView.bounds.width,
                horizontalInset: 20),
            height: ActiveContactsLayoutMetrics.stripHeight)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 8
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
    }
}

private final class ClawContactsHeaderView: UIView {
    static var height: CGFloat { 98 + ActiveContactsLayoutMetrics.stripHeight }

    let collectionView: UICollectionView
    var onViewAll: (() -> Void)?
    private let searchContainer = UIView()
    private let sectionTitle = UILabel()
    private let viewAllButton = UIButton(type: .system)

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 8
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
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
        backgroundColor = ClawTheme.surface
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        viewAllButton.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        sectionTitle.text = NSLocalizedString("活跃联系人", comment: "Active contacts section title")
        sectionTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        sectionTitle.textColor = ClawTheme.ink

        viewAllButton.setTitle(NSLocalizedString("查看全部", comment: "View all contacts"), for: .normal)
        viewAllButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        viewAllButton.tintColor = ClawTheme.primary
        viewAllButton.setTitleColor(ClawTheme.primary, for: .normal)
        viewAllButton.addTarget(self, action: #selector(viewAllTapped), for: .touchUpInside)

        collectionView.backgroundColor = ClawTheme.surface
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = false

        addSubview(searchContainer)
        addSubview(sectionTitle)
        addSubview(viewAllButton)
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            searchContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            searchContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            searchContainer.heightAnchor.constraint(equalToConstant: 52),

            sectionTitle.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 12),
            sectionTitle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            sectionTitle.heightAnchor.constraint(equalToConstant: 22),

            viewAllButton.centerYAnchor.constraint(equalTo: sectionTitle.centerYAnchor),
            viewAllButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            viewAllButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            collectionView.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: 2),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @objc private func viewAllTapped() {
        onViewAll?()
    }
}

private final class ClawActiveContactCell: UICollectionViewCell {
    static let reuseIdentifier = "ClawActiveContactCell"

    private let avatar = RoundImageView()
    private let onlineDot = UIView()
    private let callBadge = UIView()
    private let callIcon = UIImageView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        statusLabel.text = nil
        onlineDot.isHidden = true
        callBadge.isHidden = true
    }

    func configure(pub: TheCard?, id: String?, name: String, status: String, online: Bool, inCall: Bool) {
        avatar.set(pub: pub, id: id, deleted: false)
        nameLabel.text = name
        statusLabel.text = status
        statusLabel.textColor = (inCall || online) ? ClawTheme.primary : ClawTheme.muted
        onlineDot.isHidden = inCall || !online
        callBadge.isHidden = !inCall
    }

    private func setupViews() {
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true

        onlineDot.translatesAutoresizingMaskIntoConstraints = false
        onlineDot.backgroundColor = ClawTheme.success
        onlineDot.layer.cornerRadius = 6
        onlineDot.layer.borderWidth = 2
        onlineDot.layer.borderColor = ClawTheme.surface.cgColor

        callBadge.translatesAutoresizingMaskIntoConstraints = false
        callBadge.backgroundColor = ClawTheme.accent
        callBadge.layer.cornerRadius = 9
        callBadge.layer.cornerCurve = .continuous
        callBadge.isHidden = true

        callIcon.translatesAutoresizingMaskIntoConstraints = false
        callIcon.image = ClawTheme.symbol("phone.fill", pointSize: 11, weight: .semibold)
        callIcon.tintColor = .white
        callIcon.contentMode = .scaleAspectFit

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = ClawTheme.ink
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.adjustsFontSizeToFitWidth = false
        nameLabel.lineBreakMode = .byTruncatingTail

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 10, weight: .regular)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = ClawTheme.muted
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 1

        contentView.addSubview(avatar)
        contentView.addSubview(onlineDot)
        contentView.addSubview(callBadge)
        callBadge.addSubview(callIcon)
        contentView.addSubview(nameLabel)
        contentView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            avatar.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 54),
            avatar.heightAnchor.constraint(equalToConstant: 54),

            onlineDot.widthAnchor.constraint(equalToConstant: 12),
            onlineDot.heightAnchor.constraint(equalToConstant: 12),
            onlineDot.trailingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 1),
            onlineDot.bottomAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 1),

            callBadge.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            callBadge.bottomAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 6),
            callBadge.widthAnchor.constraint(equalToConstant: 36),
            callBadge.heightAnchor.constraint(equalToConstant: 18),
            callIcon.centerXAnchor.constraint(equalTo: callBadge.centerXAnchor),
            callIcon.centerYAnchor.constraint(equalTo: callBadge.centerYAnchor),
            callIcon.widthAnchor.constraint(equalToConstant: 14),
            callIcon.heightAnchor.constraint(equalToConstant: 12),

            nameLabel.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 5),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            nameLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            statusLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -4)
        ])
    }
}

// UISearchBar.searchTextField is only available in iOS 13+.
// Needed so we can change placeholder font size in the search bar.
extension UISearchBar {
    var textField: UITextField? {
        return self.searchTextField
    }
}
