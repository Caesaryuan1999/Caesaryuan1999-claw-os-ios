//
//  MessageViewController.swift
//
//  Copyright © 2019-2025 Tinode LLC. All rights reserved.
//

import AVFoundation
import MobileVLCKit
import UIKit
import TinodeSDK
import TinodiosDB

// App-only display metadata. Never serialized into message headers or storage.
struct ChatDisplaySource: Equatable {
    let page: UUID
    let topic: DefaultComTopic
    init(page: UUID, topic: DefaultComTopic) {
        self.page = page
        self.topic = topic
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.page == rhs.page && lhs.topic === rhs.topic }
}

struct ChatSubmissionDisplayTicket {
    let source: ChatDisplaySource
    let interaction: UInt64
    let submission: UInt64
    let editing: Bool
}

enum ChatDisplayIntent {
    case passive
    case preserve
    case submission(ChatSubmissionDisplayTicket)
    static let notificationKey = "claw.chat.displayIntent"
    var source: ChatDisplaySource? {
        if case .submission(let ticket) = self { return ticket.source }
        return nil
    }
    var preservesReadingPosition: Bool {
        switch self {
        case .preserve: return true
        case .submission(let ticket): return ticket.editing
        case .passive: return false
        }
    }
}

struct ChatViewportAnchor {
    let dbID: Int64
    let seq: Int
    let offset: CGFloat
}

struct ChatViewportSnapshot {
    let anchors: [ChatViewportAnchor]
    let offset: CGPoint
    let atBottom: Bool
    let interaction: UInt64
}

enum MessageBubbleLayoutPolicy {
    // Content-sized bubbles with a conservative ceiling for long messages.
    // This keeps short messages compact and lets Dynamic Type wrap naturally.
    static let maxTextWidth: CGFloat = 360
    static let viewportFraction: CGFloat = 0.76
    static let baseVoiceWidth: CGFloat = 68
    static let voiceSecondsIncrement: CGFloat = 2
    static let maxVoiceWidth: CGFloat = 96

    static func maxContentWidth(availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return maxTextWidth }
        return min(maxTextWidth, availableWidth * viewportFraction)
    }

    static func voiceWidth(durationMs: Int?, maxWidth: CGFloat) -> CGFloat {
        let seconds = CGFloat(max(durationMs ?? 0, 0)) / 1000
        let desired = min(maxVoiceWidth,
                          max(baseVoiceWidth, baseVoiceWidth + seconds * voiceSecondsIncrement))
        return min(desired, max(maxWidth, 0))
    }
}

protocol MessageDisplayLogic: AnyObject {
    func switchTopic(topic: String?)
    func updateTitleBar(pub: TheCard?, online: Bool?, deleted: Bool)
    func setOnline(online: Bool?)
    func runTypingAnimation()
    func displayChatMessages(messages: [StoredMessage], source: ChatDisplaySource, intent: ChatDisplayIntent)
    func reloadAllMessages(source: ChatDisplaySource?)
    func reloadMessages(fromSeqId loId: Int, toSeqId hiId: Int, source: ChatDisplaySource?)
    func updateProgress(forMsgId msgId: Int64, progress: Float)
    func applyTopicPermissions(withError: Error?)
    func displayPinnedMessages(pins: [Int], selected: Int, source: ChatDisplaySource?)
    func reloadPinned(forSeq: Int, source: ChatDisplaySource?)
    func endRefresh()
    func dismissVC()
    // Display or dismiss preview (e.g. reply preview) in the send message bar.
    func togglePreviewBar(with preview: NSAttributedString?, onAction action: PendingPreviewAction)
}

// Pending message is the one the user is either  replying to or forwarding.
protocol PendingMessagePreviewDelegate: AnyObject {
    // Calculates size for preview attributed string.
    func pendingPreviewMessageSize(forMessage msg: NSAttributedString) -> CGSize
    // Cancels preview.
    func dismissPendingMessagePreview()
}

class MessageViewController: UIViewController {
    let chatPageID = UUID()
    var chatInteractionRevision: UInt64 = 0
    var chatSubmissionRevision: UInt64 = 0
    var chatConsumedSubmission: UInt64?
    var chatPresentedNonempty = false
    var chatEmptyFollowLatest = false
    var chatPageRetired = false
    var chatProgrammaticDepth = 0
    var chatLastObservedOffset: CGPoint?
    var chatPresentationRunning = false
    var chatPresentationQueue: [(@escaping () -> Void) -> Void] = []

    // Other controllers may send these notification to MessageViewController which will execute corresponding send message action.
    public static let kNotificationSendAttachment = "SendAttachment"

    // MARK: static parameters
    enum Constants {
        /// Size of the avatar in the nav bar in small state.
        static let kNavBarAvatarSmallState: CGFloat = 32

        /// Size of the avatar in group topics.
        static let kAvatarSize: CGFloat = 30

        static let kProgressViewHeight: CGFloat = 30
        static let kPinnedMessagesViewHeight: CGFloat = 50

        // Size of delivery marker (checkmarks etc)
        static let kDeliveryMarkerSize: CGFloat = 16
        // Horizontal space between delivery marker and the edge of the message bubble
        static let kDeliveryMarkerPadding: CGFloat = 10
        // Horizontal space between delivery marker and timestamp
        static let kTimestampPadding: CGFloat = 0
        // Approximate width of the timestamp
        static var kTimestampWidth: CGFloat { max(50, ceil(("00:00 PM" as NSString).size(withAttributes: [.font: kTimestampFont]).width) + 8) }
        // Approximate width of edited marker
        static let kEditedMarkerWidth: CGFloat = 70
        // Horizontal space between timestamp and edited marker
        static let kEditedMarkerPadding: CGFloat = 3
        // Progress bar paddings.
        static let kProgressBarLeftPadding: CGFloat = 10
        static let kProgressBarRightPadding: CGFloat = 25

        // R3.D1: semantic colors keep both sides legible in light and dark appearance.
        static let kOutgoingBubbleColorLight = ClawTheme.primary
        static let kOutgoingBubbleColorDark = ClawTheme.primary
        static let kOutgoingTextColorLight = ClawTheme.onBrand
        static let kOutgoingTextColorDark = ClawTheme.onBrand
        static let kIncomingBubbleColorLight = ClawTheme.surface
        static let kIncomingBubbleColorDark = ClawTheme.surface
        static let kIncomingTextColorLight = ClawTheme.ink
        static let kIncomingTextColorDark = ClawTheme.ink
        // Meta-messages, such as "Content deleted".
        static let kDeletedMessageBubbleColorLight = ClawTheme.brandSoft
        static let kDeletedMessageBubbleColorDark = ClawTheme.brandSoft
        static let kDeletedMessageTextColor = ClawTheme.muted

        static var kContentFont: UIFont { ClawTheme.font(16) }

        static var kSenderNameFont: UIFont { ClawTheme.font(12, style: .caption1) }
        static var kTimestampFont: UIFont { ClawTheme.font(12, style: .caption1) }
        static var kSenderNameLabelHeight: CGFloat { ceil(kSenderNameFont.lineHeight) + 4 }
        static var kNewDateFont: UIFont { ClawTheme.font(12, weight: .medium, style: .caption1) }
        static var kNewDateLabelHeight: CGFloat { max(24, ceil(kNewDateFont.lineHeight) + 8) }
        // Vertical spacing between messages from the same user
        static let kVerticalCellSpacing: CGFloat = 6
        static let kMediaCellSpacing: CGFloat = 8
        // Additional vertical spacing between messages from different users in P2P topics.
        static let kAdditionalP2PVerticalCellSpacing: CGFloat = 4
        static let kMinimumCellWidth: CGFloat = 94
        static let kMinimumEditedCellWidth: CGFloat = 150
        // This is the space between the other side of the message and the edge of screen.
        // I.e. for incoming messages the space between the message and the *right* edge, for
        // outgoing between the message and the left edge.
        static let kFarSideHorizontalSpacing: CGFloat = 45

        // Insets around collection view, i.e. main view padding
        static let kCollectionViewInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 2)

        // Insets for the message bubble relative to collectionView: bubble should not touch the sides of the screen.
        static let kIncomingContainerPadding = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: Constants.kFarSideHorizontalSpacing)
        static let kOutgoingContainerPadding = UIEdgeInsets(top: 0, left: Constants.kFarSideHorizontalSpacing, bottom: 0, right: 0)

        // Insets around content inside the message bubble.
        static let kIncomingMessageContentInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        static let kOutgoingMessageContentInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        static let kDeletedMessageContentInset = UIEdgeInsets(top: 4, left: 14, bottom: 0, right: 14)
        static let kMediaMessageContentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        static let kMediaCornerRadius: CGFloat = 14

        // Carve out for timestamp and delivery marker in the bottom-right corner.
        static let kIncomingMetadataCarveout = "     "
        static let kOutgoingMetadataCarveout = "       "
        static let kExternalMetadataGap: CGFloat = 2
        static var kExternalMetadataHeight: CGFloat { max(18, ceil(kTimestampFont.lineHeight)) }

        // Thresholds for tracking update batch stats/UI refresh.
        // When too many messages (batch) come in a quick succession,
        // we refresh the UI in full in order to avoid UI glitches.
        static let kUpdateBatchFullRefreshThreshold = 5
        // Max time difference between successive messages to count them as one batch.
        static let kUpdateBatchTimeDeltaThresholdMs: Int64 = 300

        // Minimum and manimum duration of an audio recording in ms.
        static let kMinDuration = 3_000
        static let kMaxDuration = 600_000

        // Call type identifiers.
        static let kAudioOnlyCall = 1
        static let kVideoCall = 2

        // Maximum size of the video preview poster in bytes.
        static let kMaxPosterSize = 1024 * 8
    }

    /// The `sendMessageBar` is used as the `inputAccessoryView` in the view controller.
    lazy var sendMessageBar: SendMessageBar = {
        let view = SendMessageBar()
        view.autoresizingMask = .flexibleHeight
        return view
    }()

    /// The `forwardMessageBar` is used as the `inputAccessoryView` in the view controller
    /// (for forwarded messages only).
    lazy var forwardMessageBar: ForwardMessageBar = {
        let view = ForwardMessageBar()
        view.autoresizingMask = .flexibleHeight
        return view
    }()

    /// Avatar in the NavBar
    lazy var navBarAvatarView: AvatarWithOnlineIndicator = {
        let avatarIcon = AvatarWithOnlineIndicator()
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(navBarAvatarTapped(tapGestureRecognizer:)))
        avatarIcon.isUserInteractionEnabled = true
        avatarIcon.addGestureRecognizer(tapGestureRecognizer)
        return avatarIcon
    }()

    /// Call button in NavBar
    lazy var navBarCallBtn: UIBarButtonItem = {
        return UIBarButtonItem(
            image: ClawTheme.symbol("phone.fill", pointSize: 20, weight: .medium),
            style: .plain,
            target: self,
            action: #selector(navBarCallTapped(sender:)))
    }()

    /// Pointer to the view holding messages.
    weak var collectionView: MessageView!
    private var collectionViewBottomAnchor: NSLayoutConstraint!
    /// Button [GO to latest message].
    private weak var goToLatestButton: UIButton!
    private var goToLatestButtonBottomAnchor: NSLayoutConstraint!
    private var goToLatestButtonMinimumHeight: NSLayoutConstraint!
    var bulkSelectionMode = false
    var selectedBulkMessageSeqIds = Set<Int>()
    private var bulkSelectionOriginalTitle: String?
    private var bulkSelectionOriginalLeftItem: UIBarButtonItem?
    private var bulkSelectionOriginalRightItems: [UIBarButtonItem]?
    private lazy var bulkActionToolbar: UIToolbar = {
        let toolbar = UIToolbar(frame: .zero)
        toolbar.barStyle = .default
        toolbar.isTranslucent = false
        toolbar.tintColor = ClawTheme.primary
        toolbar.barTintColor = ClawTheme.surface
        toolbar.accessibilityIdentifier = "claw.message.bulk.actions"
        toolbar.autoresizingMask = [.flexibleWidth]
        toolbar.sizeToFit()
        return toolbar
    }()


    var interactor: (MessageBusinessLogic & MessageDataStore)?
    let refreshControl = UIRefreshControl()

    // MARK: properties

    var topicName: String? {
        didSet {
            topicType = Tinode.topicTypeByName(name: self.topicName)
            // Needed in order to get sender's avatar and display name
            let tinode = Cache.tinode
            topic = tinode.getTopic(topicName: topicName!) as? DefaultComTopic
            if topic == nil {
                topic = tinode.newTopic(for: topicName!) as? DefaultComTopic
            }
        }
    }
    var topicType: TopicType?
    var myUID: String?
    var topic: DefaultComTopic?
    // TODO: this is ugly. Move this to MVC+SendMessageBarDelegate.swift
    var imagePicker: ImagePicker?

    // Messages to be displayed
    var messages: [Message] = []
    // For updating individual messages, we need:
    // * Tinode sequence id -> messages offset.
    var messageSeqIdIndex: [Int: Int] = [:]
    // * Database message id -> message offset.
    var messageDbIdIndex: [Int64: Int] = [:]

    // Pinned messages.
    var pinnedMessageSeqs: [Int] = []
    var pinnedSelectionIndex: Int = 0

    var isInitialLayout = true

    // Highlight this cell when scroll finishes (after the user tapped on a quote or a pinned message).
    var highlightCellAtPathAfterScroll: IndexPath?

    // Size of the present update batch.
    var updateBatchSize = 0
    // Last message received timestamp - for tracking batches.
    var lastMessageReceived = Date.distantPast

    // The two below indicate whether to send typing notifications and read receipts.
    // Determined by the user specified account notifications settings.
    internal var sendTypingNotifications = false
    internal var sendReadReceipts = false

    internal var textSizeHelper = TextSizeHelper()

    // Currently playing or paused media player.
    internal var currentAudioPlayer: VLCMediaPlayer?
    var voiceOwner: Tinode?
    var voiceUID: String?
    var voiceGeneration: UInt64?
    var voiceTopicName: String?
    var voiceRecorder: MediaRecorder?
    var recordingPlaybackPlayer: VLCMediaPlayer?
    var voicePageActive = false
    var voicePausedNotice = false
    private let voiceBackdrop = UIView()
    private var voiceBackdropWasVisible = false
    private var collectionAccessibilityBeforeVoice = false
    private var latestAccessibilityBeforeVoice = false

    // Max inband attachment/entity size.
    private var maxInbandSize: Int64 {
        // Attachment size less base64 expansion and overhead.
        return Cache.tinode.getServerLimit(for: Tinode.kMaxMessageSize, withDefault: MessageViewController.kMaxInbandAttachmentSize) * 3 / 4 - 1024
    }

    // MARK: initializers

    init() {
        super.init(nibName: nil, bundle: nil)
        self.setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
    }

    private func addAppStateObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionInterrupted(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
        // App state observers.
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appGoingInactive),
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.appBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(self.deviceRotated),
            name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    private func removeAppStateObservers() {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willResignActiveNotification,
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil)
    }

    private func setup() {
        let owner = Cache.tinode
        myUID = owner.myUid
        voiceOwner = owner
        voiceUID = owner.myUid
        voiceGeneration = Cache.ifCurrent(owner) { Cache.sessionGeneration }
        self.imagePicker = ImagePicker(presentationController: self, delegate: self, editable: false, allowVideo: true)

        let interactor = MessageInteractor()
        let presenter = MessagePresenter(pageID: chatPageID)
        interactor.presenter = presenter
        presenter.viewController = self

        // Notifications settings.
        self.sendTypingNotifications = SharedUtils.kAppDefaults.bool(forKey: SharedUtils.kTinodePrefTypingNotifications)
        self.sendReadReceipts = SharedUtils.kAppDefaults.bool(forKey: SharedUtils.kTinodePrefReadReceipts)

        self.interactor = interactor
        addAppStateObservers()
    }

    @objc
    func appBecameActive() {
        if voicePausedNotice, voiceScopeIsCurrent(), voiceRecorder?.state == .preview {
            sendMessageBar.showInterruptedRecordingPreview()
            voicePausedNotice = false
            UiUtils.showToast(message: "录音已暂停，请试听后再发送")
        }
        self.interactor?.setup(topicName: topicName, sendReadReceipts: self.sendReadReceipts)
        self.interactor?.attachToTopic(interactively: true)
        self.interactor?.loadMessagesFromCache(scrollToMostRecentMessage: false)
    }
    @objc
    func appGoingInactive() {
        suspendVoiceRecording()
        self.interactor?.cleanup()
        self.interactor?.leaveTopic()
    }
    @objc
    func deviceRotated() {
        // Invalidate cached content in the messages since it was
        // tailored for the old device orientation.
        self.messages.forEach { ($0 as? StoredMessage)?.cachedContent = nil }
        // Force a full redraw so the view can readjust the messages
        // in the view for the new screen dimensions.
        reloadChatLayoutPreservingViewport()
    }

    // MARK: lifecycle

    deinit {
        // removeMenuControllerObservers()
        removeAppStateObservers()
        // Discard only this page's unsubmitted take; no preview survives a dead page.
        discardVoiceRecording()
        self.interactor?.cleanup()
        self.interactor?.leaveTopic()
    }

    // This makes messageInputBar visible.
    override var inputAccessoryView: UIView? {
        if bulkSelectionMode {
            return bulkActionToolbar
        }
        return !isForwardingMessage ? sendMessageBar : forwardMessageBar
    }

    // Indicates whether the user is about to forward a message to this topic
    // i.e. the forwarded message preview is shown in the preview bar.
    var isForwardingMessage: Bool = false

    func beginBulkMessageSelection(starting seqId: Int) {
        guard let message = message(atSeqId: seqId), !message.isDeleted else { return }
        if !bulkSelectionMode {
            sendMessageBar.inputField.resignFirstResponder()
            bulkSelectionMode = true
            selectedBulkMessageSeqIds.removeAll()
            bulkSelectionOriginalTitle = navigationItem.title
            bulkSelectionOriginalLeftItem = navigationItem.leftBarButtonItem
            bulkSelectionOriginalRightItems = navigationItem.rightBarButtonItems
            collectionView.isBulkSelectionMode = true
        }
        selectedBulkMessageSeqIds.insert(seqId)
        updateBulkMessageSelectionUI()
        collectionView.reloadData()
        becomeFirstResponder()
        reloadInputViews()
    }

    func toggleBulkMessageSelection(seqId: Int) {
        guard bulkSelectionMode, let message = message(atSeqId: seqId), !message.isDeleted else { return }
        if selectedBulkMessageSeqIds.contains(seqId) {
            selectedBulkMessageSeqIds.remove(seqId)
        } else {
            selectedBulkMessageSeqIds.insert(seqId)
        }
        if selectedBulkMessageSeqIds.isEmpty {
            finishBulkMessageSelection()
        } else {
            updateBulkMessageSelectionUI()
            collectionView.reloadData()
        }
    }

    func finishBulkMessageSelection() {
        guard bulkSelectionMode else { return }
        bulkSelectionMode = false
        selectedBulkMessageSeqIds.removeAll()
        collectionView.isBulkSelectionMode = false
        navigationItem.title = bulkSelectionOriginalTitle
        navigationItem.leftBarButtonItem = bulkSelectionOriginalLeftItem
        navigationItem.rightBarButtonItems = bulkSelectionOriginalRightItems
        bulkSelectionOriginalTitle = nil
        bulkSelectionOriginalLeftItem = nil
        bulkSelectionOriginalRightItems = nil
        bulkActionToolbar.items = nil
        collectionView.reloadData()
        becomeFirstResponder()
        reloadInputViews()
    }

    func selectedBulkMessages() -> [Message] {
        return selectedBulkMessageSeqIds.sorted().compactMap { message(atSeqId: $0) }
    }

    private func updateBulkMessageSelectionUI() {
        let count = selectedBulkMessageSeqIds.count
        navigationItem.title = String(format: NSLocalizedString("已选择 %d 条消息", comment: "Selected message count"), count)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("取消", comment: "Cancel bulk message selection"),
            style: .plain,
            target: self,
            action: #selector(cancelBulkMessageSelection))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("完成", comment: "Finish bulk message selection"),
            style: .plain,
            target: self,
            action: #selector(finishBulkMessageSelectionFromToolbar))
        updateBulkActionToolbar()
    }

    private func updateBulkActionToolbar() {
        var items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)]
        items.append(bulkToolbarButton(
            title: NSLocalizedString("复制", comment: "Copy selected messages"),
            symbolName: "doc.on.doc",
            identifier: "copy",
            action: #selector(bulkToolbarCopy)))
        if selectedBulkMessageSeqIds.count == 1 {
            items.append(bulkToolbarButton(
                title: NSLocalizedString("回复", comment: "Reply selected message"),
                symbolName: "arrowshape.turn.up.left",
                identifier: "reply",
                action: #selector(bulkToolbarReply)))
            items.append(bulkToolbarButton(
                title: NSLocalizedString("转发", comment: "Forward selected message"),
                symbolName: "arrowshape.turn.up.right",
                identifier: "forward",
                action: #selector(bulkToolbarForward)))
        }
        items.append(bulkToolbarButton(
            title: NSLocalizedString("重试", comment: "Retry selected messages"),
            symbolName: "arrow.clockwise",
            identifier: "retry",
            action: #selector(bulkToolbarRetry)))
        let delete = bulkToolbarButton(
            title: NSLocalizedString("删除", comment: "Delete selected messages"),
            symbolName: "trash",
            identifier: "delete",
            action: #selector(bulkToolbarDelete))
        delete.tintColor = ClawTheme.danger
        items.append(delete)
        items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        bulkActionToolbar.items = items
    }

    private func bulkToolbarButton(title: String, symbolName: String, identifier: String, action: Selector) -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: ClawTheme.symbol(symbolName, pointSize: 18, weight: .medium),
            style: .plain,
            target: self,
            action: action)
        item.accessibilityLabel = title
        item.accessibilityIdentifier = "claw.message.bulk.\(identifier)"
        return item
    }

    @objc private func cancelBulkMessageSelection() {
        finishBulkMessageSelection()
    }

    @objc private func finishBulkMessageSelectionFromToolbar() {
        finishBulkMessageSelection()
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func loadView() {
        super.loadView()

        let collectionView = MessageView()

        // Appearance and behavior.
        extendedLayoutIncludesOpaqueBars = true

        // Receive notifications from FilePreviewController with an attachment to upload or send.
        NotificationCenter.default.addObserver(self, selector: #selector(sendAttachment(notification:)), name: Notification.Name(MessageViewController.kNotificationSendAttachment), object: nil)

        // Collection View setup
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        collectionView.layoutMargins = Constants.kCollectionViewInset
        collectionView.delegate = self
        collectionView.cellDelegate = self
        view.addSubview(collectionView)
        self.collectionView = collectionView

        collectionView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(self.loadPreviousPage), for: .valueChanged)

        // Setup UICollectionView constraints: fill the screen
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.collectionViewBottomAnchor = collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -(inputAccessoryView?.frame.height ?? 0))
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            self.collectionViewBottomAnchor,
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        ])

        // Setup "Go to latest message" button.
        let buttonGoToLatest = UIButton(type: .custom)
        buttonGoToLatest.backgroundColor = ClawTheme.surface
        buttonGoToLatest.layer.borderWidth = 1
        buttonGoToLatest.layer.borderColor = ClawTheme.border.cgColor
        buttonGoToLatest.setTitle("回到最新消息", for: .normal)
        buttonGoToLatest.accessibilityLabel = "回到最新消息"
        buttonGoToLatest.setTitleColor(ClawTheme.primary, for: .normal)
        buttonGoToLatest.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        buttonGoToLatest.titleLabel?.adjustsFontForContentSizeCategory = true
        buttonGoToLatest.titleLabel?.numberOfLines = 0
        buttonGoToLatest.titleLabel?.textAlignment = .center
        buttonGoToLatest.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        buttonGoToLatest.layer.cornerRadius = 22
        buttonGoToLatest.layer.shadowColor = UIColor.black.cgColor
        buttonGoToLatest.layer.shadowOpacity = 0.12
        buttonGoToLatest.layer.shadowRadius = 8
        buttonGoToLatest.layer.shadowOffset = CGSize(width: 0, height: 3)
        buttonGoToLatest.addTarget(self, action: #selector(self.goToLastMessage), for: .touchUpInside)

        view.addSubview(buttonGoToLatest)
        self.goToLatestButton = buttonGoToLatest
        buttonGoToLatest.isHidden = true

        // Button on the bottom-right.
        self.goToLatestButton.translatesAutoresizingMaskIntoConstraints = false
        self.goToLatestButtonBottomAnchor = self.goToLatestButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -(inputAccessoryView?.frame.height ?? 0) - 16)
        self.goToLatestButtonMinimumHeight = self.goToLatestButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        NSLayoutConstraint.activate([
            self.goToLatestButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44.0),
            self.goToLatestButtonMinimumHeight,
            self.goToLatestButton.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            self.goToLatestButtonBottomAnchor,
            self.goToLatestButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8)])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let layout = collectionView?.collectionViewLayout as? MessageViewLayout {
            layout.delegate = self
        }

        self.collectionView.dataSource = self
        sendMessageBar.delegate = self
        configureVoiceBackdrop()
        forwardMessageBar.delegate = self

        self.setInterfaceColors()

        if self.interactor?.setup(topicName: self.topicName, sendReadReceipts: self.sendReadReceipts) ?? false {
            self.interactor?.loadMessagesFromCache(scrollToMostRecentMessage: true)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // The accessory owns its height. Do not add another keyboard or home inset.
        sendMessageBar.voicePanelMaximumHeight = max(52,
            view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom
                - sendMessageBar.previewViewHeight.constant - sendMessageBar.peerMessagingDisabledHeight.constant - 24)

        // Make sure we leave enough space for the input field & keyboard.
        if collectionView.contentInset.bottom < 8 {
            collectionView.contentInset.bottom = 8
        }

        self.collectionViewBottomAnchor.constant = -(inputAccessoryView?.frame.height ?? 0)
        let accessoryHeight = inputAccessoryView?.frame.height ?? 0
        self.goToLatestButtonBottomAnchor.constant = -accessoryHeight - 16 - (accessoryHeight > 0 ? 0 : view.safeAreaInsets.bottom)
        if let title = goToLatestButton.titleLabel {
            let width = max(1, view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 48)
            title.preferredMaxLayoutWidth = width
            goToLatestButtonMinimumHeight.constant = max(44, title.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height + 20)
        }

        // Otherwise setting contentInset after viewDidAppear will be animated.
        if isInitialLayout {
            defer { isInitialLayout = false }
            addKeyboardObservers()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            // Reuse the existing offset-preserving redraw; no history or send operation.
            deviceRotated()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        voicePageActive = true

        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: sendMessageBar.frame.height, right: 0)

        if case let .forwarded(_, _, fwdPreview) = self.interactor?.pendingMessage {
            self.isForwardingMessage = true
            self.showInPreviewBar(content: fwdPreview, forwarded: true)
        }
        self.interactor?.attachToTopic(interactively: true)
        self.interactor?.loadMessagesFromCache(scrollToMostRecentMessage: false)
        self.interactor?.sendReadNotification(explicitSeq: nil, when: .now() + .seconds(1))
        self.applyTopicPermissions()
    }

    @objc func loadPreviousPage() {
        self.interactor?.loadPreviousPage()
    }

    @objc func goToLastMessage() {
        invalidateChatDisplayIntent()
        chatEmptyFollowLatest = true
        guard let collectionView = collectionView else { return }
        withChatProgrammaticLayout {
            collectionView.layoutIfNeeded()
            collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: chatMaximumOffset), animated: false)
        }
        updateChatLatestButton()
    }

    @objc func sendAttachment(notification: NSNotification) {
        let displayIntent = notification.userInfo?[ChatDisplayIntent.notificationKey] as? ChatDisplayIntent ?? .passive
        // Attachment size less base64 expansion and overhead.
        let maxInbandSize = self.maxInbandSize
        switch notification.object {
        case let content as FilePreviewContent:
            if content.data.count > maxInbandSize {
                self.interactor?.uploadFile(UploadDef(filename: content.fileName, mimeType: content.contentType, data: content.data), displayIntent: displayIntent)
            } else {
                _ = interactor?.sendMessage(content: Drafty().attachFile(mime: content.contentType, bits: content.data, fname: content.fileName), displayIntent: displayIntent)
            }
        case let content as ImagePreviewContent:
            guard case let ImagePreviewContent.ImageContent.uiimage(image) = content.imgContent else { return }

            guard let data = image.pixelData(forMimeType: content.contentType) else { return }
            if data.count > maxInbandSize {
                self.interactor?.uploadImage(UploadDef(caption: content.caption, filename: content.fileName, mimeType: content.contentType, image: image, data: data, width: image.size.width * image.scale, height: image.size.height * image.scale), displayIntent: displayIntent)
            } else {
                let imageWidth = max(content.width ?? Int(image.size.width * image.scale), 1)
                let imageHeight = max(content.height ?? Int(image.size.height * image.scale), 1)
                let drafty = Drafty(plainText: " ").insertImage(at: 0, mime: content.contentType, bits: data, width: imageWidth, height: imageHeight, fname: content.fileName)
                if let caption = content.caption {
                    _ = drafty.appendLineBreak().append(Drafty(plainText: caption))
                }
                _ = interactor?.sendMessage(content: drafty, displayIntent: displayIntent)
            }
        case let content as VideoPreviewContent:
            sendVideoAttachment(withContent: content, displayIntent: displayIntent)
        default:
            break
        }
    }

    private func sendVideoAttachment(withContent content: VideoPreviewContent, displayIntent: ChatDisplayIntent) {
        guard case let VideoPreviewContent.VideoSource.local(url, poster) = content.videoSrc else { return }
        let maxAttachmentSize = Cache.tinode.getServerLimit(for: Tinode.kMaxFileUploadSize, withDefault: MessageViewController.kMaxAttachmentSize)
        do {
            if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > maxAttachmentSize {
                UiUtils.showToast(message: String(format: NSLocalizedString("The file size exceeds the limit %@", comment: "Error message"), UiUtils.bytesToHumanSize(maxAttachmentSize)))
                return
            }
        } catch {
            Cache.log.error("MessageVC - failed to inspect video file: %@", error.localizedDescription)
            UiUtils.showToast(message: NSLocalizedString("Unable to read video", comment: "Video attachment read error"))
            return
        }
        let previewMime = "image/png"
        let preview = poster?.pixelData(forMimeType: previewMime)
        let maxInbandSize = self.maxInbandSize
        let posterScale = poster?.scale ?? 1
        let posterWidth = poster.map { Int($0.size.width * posterScale) } ?? 0
        let posterHeight = poster.map { Int($0.size.height * posterScale) } ?? 0
        let videoWidth = max(content.width ?? posterWidth, 1)
        let videoHeight = max(content.height ?? posterHeight, 1)
        let duration = max(content.duration, 0)

        let mimeCandidate = content.contentType ?? Utils.mimeForUrl(url: url, ifMissing: "video/mp4")
        let mime = mimeCandidate.hasPrefix("video/")
            ? mimeCandidate
            : Utils.mimeForUrl(url: url, ifMissing: "video/mp4")
        let fileName = content.fileName ?? (url.lastPathComponent.isEmpty ? Utils.uniqueFilename(forMime: mime) : url.lastPathComponent)
        Cache.log.info("MessageVC - sending video attachment topic=%@ file=%@ mime=%@", self.topicName ?? "", fileName, mime)

        // Reading a camera-library movie synchronously on the main thread can
        // make the send action look dead for several seconds. Keep the UI
        // responsive and perform the actual message/upload operation on the
        // main thread after the file has been read.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let previewSize = preview?.count ?? 0
                guard data.count >= previewSize else {
                    Cache.log.error("MessageVC - preview size (%lld bytes) is greater than video (%lld bytes)", previewSize, data.count)
                    DispatchQueue.main.async {
                        UiUtils.showToast(message: NSLocalizedString("Unable to read video", comment: "Video attachment read error"))
                    }
                    return
                }

                DispatchQueue.main.async {
                    if data.count + previewSize > maxInbandSize {
                        self.interactor?.uploadVideo(UploadDef(caption: content.caption, filename: fileName,
                                                               mimeType: mime, data: data,
                                                               width: CGFloat(videoWidth),
                                                               height: CGFloat(videoHeight),
                                                               duration: duration, preview: preview, previewMime: previewMime,
                                                               previewOutOfBand: previewSize > Constants.kMaxPosterSize), displayIntent: displayIntent)
                    } else if let drafty = try? Drafty(plainText: " ").insertVideo(at: 0, mime: mime, bits: data, refurl: nil, duration: duration, width: videoWidth, height: videoHeight, fname: fileName, size: data.count, preMime: previewMime, preview: preview, previewRef: nil) {
                        if let caption = content.caption {
                            _ = drafty.appendLineBreak().append(Drafty(plainText: caption))
                        }
                        _ = self.interactor?.sendMessage(content: drafty, displayIntent: displayIntent)
                    }
                }
            } catch {
                Cache.log.error("MessageVC - failed to read video file: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    UiUtils.showToast(message: NSLocalizedString("Unable to read video", comment: "Video attachment read error"))
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        invalidateChatDisplayIntent()
        voicePageActive = false
        discardVoiceRecording()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        // A cancelled interactive pop has only begun disappearing. Retire
        // display admission after UIKit actually removes this child instead.
        if parent == nil {
            invalidateChatDisplayIntent()
            chatPageRetired = true
        }
    }

    @objc func audioSessionInterrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
        if Thread.isMainThread { suspendVoiceRecording() }
        else { DispatchQueue.main.async { [weak self] in self?.suspendVoiceRecording() } }
    }

    func voiceScopeIsCurrent() -> Bool {
        guard voicePageActive, let owner = voiceOwner, let uid = voiceUID,
              let generation = voiceGeneration else { return false }
        return Cache.ifCurrent(owner) {
            owner.myUid == uid && owner.store?.myUid == uid && Cache.sessionGeneration == generation
        } ?? false
    }

    func voiceUI(_ recorder: MediaRecorder, _ update: () -> Void) {
        precondition(Thread.isMainThread)
        guard voiceRecorder === recorder, recorder.isCurrent,
              voiceTopicName == topicName, let owner = voiceOwner else { return }
        guard Cache.isCurrent(owner), voiceScopeIsCurrent() else { return }
        // Main presentation is outside SDK/Cache locks; it only touches this page.
        update()
    }

    func stopRecordingPlayback(discard: Bool) {
        guard let player = recordingPlaybackPlayer else { return }
        if discard {
            recordingPlaybackPlayer = nil
            if currentAudioPlayer === player { currentAudioPlayer = nil }
            let stop = { player.delegate = nil; player.stop() }
            if Thread.isMainThread { stop() } else { DispatchQueue.main.async(execute: stop) }
        } else {
            player.pause()
            sendMessageBar.audioPlaybackAction(.playbackPause)
            sendMessageBar.showAudioBar(.longPaused)
        }
    }

    func suspendVoiceRecording() {
        guard let recorder = voiceRecorder else { return }
        guard voiceScopeIsCurrent(), recorder.isCurrent, voiceTopicName == topicName else {
            discardVoiceRecording(); return
        }
        stopRecordingPlayback(discard: false)
        recorder.cancelPendingIntent()
        if recorder.stopForPreview() != nil {
            voicePausedNotice = true
            sendMessageBar.showInterruptedRecordingPreview()
        }
    }

    private func configureVoiceBackdrop() {
        // A view inside this controller: presenting another controller would
        // correctly retire the page's recording lease in viewWillDisappear.
        voiceBackdrop.translatesAutoresizingMaskIntoConstraints = false
        voiceBackdrop.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        voiceBackdrop.isHidden = true
        voiceBackdrop.isAccessibilityElement = false
        view.addSubview(voiceBackdrop)
        NSLayoutConstraint.activate([
            voiceBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            voiceBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            voiceBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            voiceBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        sendMessageBar.onVoicePresentationChanged = { [weak self] visible in
            guard let self = self else { return }
            if visible && !self.voiceBackdropWasVisible {
                self.collectionAccessibilityBeforeVoice = self.collectionView.accessibilityElementsHidden
                self.latestAccessibilityBeforeVoice = self.goToLatestButton.isAccessibilityElement
            }
            self.voiceBackdrop.isHidden = !visible
            self.collectionView.accessibilityElementsHidden = visible
                ? true : self.collectionAccessibilityBeforeVoice
            self.goToLatestButton.isAccessibilityElement = visible
                ? false : self.latestAccessibilityBeforeVoice
            self.voiceBackdropWasVisible = visible
            if visible { self.view.bringSubviewToFront(self.voiceBackdrop) }
            self.view.setNeedsLayout()
        }
        sendMessageBar.onVoiceHeightChanged = { [weak self] in self?.view.setNeedsLayout() }
    }

    func discardVoiceRecording() {
        stopRecordingPlayback(discard: true)
        let recorder = voiceRecorder
        voiceRecorder = nil
        voiceTopicName = nil
        voicePausedNotice = false
        if let recorder = recorder { Cache.releaseMediaRecorder(recorder) }
        if Thread.isMainThread, isViewLoaded { sendMessageBar.resetRecordingState() }
    }

    func sendAudioAttachment(recorder: MediaRecorder) {
        guard voiceRecorder === recorder, voiceScopeIsCurrent(), voiceTopicName == topicName,
              UIApplication.shared.applicationState == .active, let owner = voiceOwner,
              let uid = voiceUID, let generation = voiceGeneration, let name = voiceTopicName else { return }
        let displayIntent = captureChatSubmissionIntent()
        stopRecordingPlayback(discard: true)
        do {
            let (recording, data) = try recorder.prepareSubmission(minimumDuration: Constants.kMinDuration)
            guard recorder.isCurrent, voiceScopeIsCurrent() else { return }
            let def = UploadDef(mimeType: Utils.mimeForUrl(url: recording.url, ifMissing: "audio/m4a"),
                                data: data, duration: recording.duration, preview: recording.preview)
            guard interactor?.submitRecordedAudio(def, owner: owner, uid: uid,
                    generation: generation, topicName: name, displayIntent: displayIntent) == true else {
                voiceUI(recorder) { UiUtils.showToast(message: "录音尚未提交，请检查当前账号与会话后重试。") }
                return
            }
            // This is local handoff, not an ACK or a delivery indication.
            recorder.didSubmit(recording)
            discardVoiceRecording()
        } catch {
            voiceUI(recorder) {
                switch error as? MediaRecorderError {
                case .tooShort:
                    UiUtils.showToast(message: "录音不足 3 秒，请放弃后重新录制。")
                case .cancelledByUser:
                    break
                default:
                    UiUtils.showToast(message: "无法读取录音，请重试发送，或放弃后重新录制。")
                }
            }
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case "Messages2TopicInfo":
            let destinationVC = segue.destination as! TopicInfoViewController
            destinationVC.topicName = self.topicName ?? ""
        case "ShowImagePreview":
            let destinationVC = segue.destination as! ImagePreviewController
            destinationVC.previewContent = (sender as! ImagePreviewContent)
            destinationVC.replyPreviewDelegate = self
            destinationVC.captureDisplayIntent = chatPreviewIntentCapture(for: destinationVC)
        case "ShowFilePreview":
            let destinationVC = segue.destination as! FilePreviewController
            destinationVC.previewContent = (sender as! FilePreviewContent)
            destinationVC.replyPreviewDelegate = self
            destinationVC.captureDisplayIntent = chatPreviewIntentCapture(for: destinationVC)
        case "ShowVideoPreview":
            let destinationVC = segue.destination as! VideoPreviewController
            destinationVC.previewContent = (sender as! VideoPreviewContent)
            destinationVC.replyPreviewDelegate = self
            destinationVC.captureDisplayIntent = chatPreviewIntentCapture(for: destinationVC)
        case "Messages2Call":
            let destinationVC = segue.destination as! CallViewController
            if let call = sender as? CallManager.Call {
                destinationVC.callDirection = .incoming
                destinationVC.callSeqId = call.seq
                destinationVC.isAudioOnlyCall = call.audioOnly
            } else {
                destinationVC.callDirection = .outgoing
                destinationVC.isAudioOnlyCall = (sender as? Int) == Constants.kAudioOnlyCall
            }
            destinationVC.topic = self.topic
        default:
            break
        }
    }

    @objc func navBarAvatarTapped(tapGestureRecognizer: UITapGestureRecognizer) {
        if topic?.deleted ?? false {
            return
        }
        performSegue(withIdentifier: "Messages2TopicInfo", sender: nil)
    }

    private func setInterfaceColors() {
        view.backgroundColor = ClawTheme.background
        collectionView?.backgroundColor = ClawTheme.background
        goToLatestButton?.backgroundColor = ClawTheme.surface
        goToLatestButton?.layer.borderColor = ClawTheme.border.cgColor
    }

    @objc func navBarCallTapped(sender: UIMenuController) {
        switch self.topicType {
        case .p2p:
            let alert = UIAlertController(title: "发起通话", message: nil, preferredStyle: .actionSheet)
            alert.modalPresentationStyle = .popover
            alert.addAction(UIAlertAction(title: "语音通话", style: .default, handler: { audioCall in
                self.performSegue(withIdentifier: "Messages2Call", sender: Constants.kAudioOnlyCall)
            }))
            alert.addAction(UIAlertAction(title: "视频通话", style: .default, handler: { videoCall in
                self.performSegue(withIdentifier: "Messages2Call", sender: Constants.kVideoCall)
            }))
            alert.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
            if let presentation = alert.popoverPresentationController {
                presentation.barButtonItem = navBarCallBtn
            }
            self.present(alert, animated: true, completion: nil)
        default:
            break
        }
    }
}

// Methods for filling message with content and layout out message subviews.
extension MessageViewController: UICollectionViewDataSource {

    func numberOfSections(in: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        self.collectionView.toggleNoMessagesNote(on: messages.isEmpty)
        return messages.count
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionHeader {
            let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: String(describing: PinnedMessagesView.self), for: indexPath) as! PinnedMessagesView

            // Configure header.
            if self.pinnedMessageSeqs.isEmpty {
                sectionHeader.isHidden = true
            } else {
                sectionHeader.delegate = self
                sectionHeader.topicName = self.topicName
                sectionHeader.pins = self.pinnedMessageSeqs
                sectionHeader.selected = 0
                sectionHeader.isHidden = false
            }

            return sectionHeader
        }

        return UICollectionReusableView()
    }

    // Configure message cell for the given index: fill data and lay out subviews.
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: String(describing: MessageCell.self), for: indexPath) as! MessageCell

        // To capture taps.
        cell.delegate = self

        // Cell content
        let message = messages[indexPath.item]

        // Get cell attributes from cache.
        let attributes = collectionView.layoutAttributesForItem(at: indexPath) as! MessageViewLayoutAttributes

        cell.progressView.frame = attributes.progressViewFrame

        // Set colors and fill out content except for the avatar. The maxumum size is needed for placing attached images.
        configureCell(cell: cell, with: message, at: indexPath)
        cell.setBulkSelectionMode(
            (collectionView as? MessageView)?.isBulkSelectionMode == true,
            selected: selectedBulkMessageSeqIds.contains(message.seqId))

        cell.avatarView.frame = attributes.avatarFrame
        if attributes.avatarFrame != .zero {
            // The avatar image should be assigned after setting the size. Otherwise it may be drawn twice.
            let sub = topic?.getSubscription(for: message.from)
            cell.avatarView.set(pub: sub?.pub, id: message.from, deleted: sub == nil)
        }

        // Sender name under the avatar.
        cell.senderNameLabel.frame = attributes.senderNameFrame

        cell.containerView.frame = attributes.containerFrame

        // Content: RichTextLabel.
        cell.content.frame = attributes.contentFrame

        let metadataOffset = CGAffineTransform(translationX: attributes.containerFrame.minX,
                                                y: attributes.containerFrame.minY)
        cell.deliveryMarker.frame = attributes.deliveryMarkerFrame == .zero
            ? .zero : attributes.deliveryMarkerFrame.applying(metadataOffset)

        cell.timestampLabel.sizeToFit()
        cell.timestampLabel.frame = attributes.timestampFrame == .zero
            ? .zero : attributes.timestampFrame.applying(metadataOffset)

        cell.editedMarker.sizeToFit()
        cell.editedMarker.frame = attributes.editedMarkerFrame == .zero
            ? .zero : attributes.editedMarkerFrame.applying(metadataOffset)

        cell.newDateLabel.frame = attributes.newDateFrame

        // Draw the bubble
        bubbleDecorator(for: message, at: indexPath)(cell.containerView)

        return cell
    }

    private func configureCell(cell: MessageCell, with message: Message, at indexPath: IndexPath) {

        cell.seqId = message.seqId
        cell.isDeleted = message.isDeleted
        cell.timeStamp = message.ts
        let storedMessage = message as! StoredMessage
        let isVisualMedia = storedMessage.isVisualMedia

        cell.content.backgroundColor = nil
        if message.isDeleted {
            if traitCollection.userInterfaceStyle == .dark {
                cell.containerView.backgroundColor = Constants.kDeletedMessageBubbleColorDark
            } else {
                cell.containerView.backgroundColor = Constants.kDeletedMessageBubbleColorLight
            }
            cell.content.textColor = Constants.kDeletedMessageTextColor
        } else if isVisualMedia {
            cell.containerView.backgroundColor = .clear
            cell.content.textColor = ClawTheme.ink
        } else if isFromCurrentSender(message: message) {
            if traitCollection.userInterfaceStyle == .dark {
                cell.containerView.backgroundColor = Constants.kOutgoingBubbleColorDark
                cell.content.textColor = Constants.kOutgoingTextColorDark
            } else {
                cell.containerView.backgroundColor = Constants.kOutgoingBubbleColorLight
                cell.content.textColor = Constants.kOutgoingTextColorLight
            }
        } else {
            if traitCollection.userInterfaceStyle == .dark {
                cell.containerView.backgroundColor = Constants.kIncomingBubbleColorDark
                cell.content.textColor = Constants.kIncomingTextColorDark
            } else {
                cell.containerView.backgroundColor = Constants.kIncomingBubbleColorLight
                cell.content.textColor = Constants.kIncomingTextColorLight
            }
        }

        cell.content.font = Constants.kContentFont

        if let attributedText = storedMessage.cachedContent {
            let text = NSMutableAttributedString(attributedString: attributedText)
            cell.content.attributedText = text
        }

        if let (image, tint) = deliveryMarker(for: message) {
            cell.deliveryMarker.image = image
            cell.deliveryMarker.tintColor = tint
        }
        cell.timestampLabel.font = Constants.kTimestampFont
        cell.editedMarker.font = Constants.kTimestampFont
        let markerTextColor = ClawTheme.muted
        if let ts = message.ts {
            cell.timestampLabel.text = RelativeDateFormatter.shared.timeOnly(from: ts)
            cell.timestampLabel.textColor = markerTextColor
        }
        cell.deliveryMarker.tintColor = markerTextColor
        cell.editedMarker.text = editedMarkerText(forMessage: message)
        cell.editedMarker.textColor = markerTextColor
        cell.newDateLabel.attributedText = newDateLabel(for: message, at: indexPath)
        cell.senderNameLabel.attributedText = senderFullName(for: message, at: indexPath)

        if shouldShowProgressBar(for: message) {
            cell.showProgressBar()
        }
    }

    func editedMarkerText(forMessage msg: Message) -> String? {
        return msg.isEdited ? NSLocalizedString("edited", comment: "`Edited` message marker") : nil
    }

    func newDateLabel(for message: Message, at indexPath: IndexPath) -> NSAttributedString? {
        if isNewDateLabelVisible(at: indexPath) {
            return NSAttributedString(string: RelativeDateFormatter.shared.dateOnly(from: message.ts), attributes: [NSAttributedString.Key.font: Constants.kNewDateFont, NSAttributedString.Key.foregroundColor: ClawTheme.muted])
        }
        return nil
    }

    // Get sender name
    func senderFullName(for message: Message, at indexPath: IndexPath) -> NSAttributedString? {
        guard shouldShowAvatar(for: message, at: indexPath) else { return nil }

        let senderName = AccountNames.contactDisplayName(
            displayName: topic?.getSubscription(for: message.from)?.pub?.fn,
            accountName: nil, userId: message.from,
            genericDefaultName: NSLocalizedString("资料未获取", comment: "Public contact information unavailable"))

        return NSAttributedString(string: senderName, attributes: [
            NSAttributedString.Key.font: Constants.kSenderNameFont,
            NSAttributedString.Key.foregroundColor: ClawTheme.muted
            ])
    }

    func deliveryMarker(for message: Message) -> (UIImage, UIColor)? {
        guard isFromCurrentSender(message: message), let topic = topic else { return nil }
        return UiUtils.deliveryMarkerIcon(for: message, in: topic)
    }

    // Returns closure which adds message bubble mask to the supplied UIView.
    func bubbleDecorator(for message: Message, at indexPath: IndexPath) -> (UIView) -> Void {
        let isIncoming = !isFromCurrentSender(message: message)
        let isDeleted = message.isDeleted
        let isVisualMedia = (message as? StoredMessage)?.isVisualMedia == true

        let breakBefore = !isPreviousMessageSameSender(at: indexPath) || !isPreviousMessageSameDate(at: indexPath)
        let breakAfter = !isNextMessageSameSender(at: indexPath) || !isNextMessageSameDate(at: indexPath)

        let style: MessageBubbleDecorator.Style
        switch true {
        case breakBefore && breakAfter:
            style = .single
        case breakBefore:
            style = .first
        case breakAfter:
            style = .last
        default:
            style = .middle
        }

        return { view in
            view.layer.mask = nil
            if isVisualMedia && !isDeleted {
                view.layer.cornerRadius = Constants.kMediaCornerRadius
                view.layer.masksToBounds = true
                return
            }
            view.layer.cornerRadius = 0
            let path = !isDeleted ?
                MessageBubbleDecorator.draw(view.bounds, isIncoming: isIncoming, style: style) :
                MessageBubbleDecorator.drawDeleted(view.bounds)
            let mask = CAShapeLayer()
            mask.path = path.cgPath
            view.layer.mask = mask
        }
    }
}

// Helper methods for displaying message content
extension MessageViewController {

    // MARK: helper methods for displaying message content.

    func isPreviousMessageSameDate(at indexPath: IndexPath) -> Bool {
        guard indexPath.item > 0 else { return false }
        guard let this = messages[indexPath.item].ts, let prev = messages[indexPath.item - 1].ts else { return false }
        return Calendar.current.isDate(this, inSameDayAs: prev)
    }

    func isNextMessageSameDate(at indexPath: IndexPath) -> Bool {
        guard indexPath.item + 1 < messages.count else { return false }
        guard let this = messages[indexPath.item].ts, let next = messages[indexPath.item + 1].ts else { return false }
        return Calendar.current.isDate(this, inSameDayAs: next)
    }

    func isPreviousMessageSameSender(at indexPath: IndexPath) -> Bool {
        guard indexPath.item > 0 else { return false }
        return messages[indexPath.item].from == messages[indexPath.item - 1].from
    }

    func isNextMessageSameSender(at indexPath: IndexPath) -> Bool {
        guard indexPath.item + 1 < messages.count else { return false }
        return messages[indexPath.item].from == messages[indexPath.item + 1].from
    }

    func isFromCurrentSender(message: Message) -> Bool {
        return message.from == myUID
    }

    // Should avatars be shown at all for any message?
    func avatarsVisible(message: Message) -> Bool {
        return (topic?.isGrpType ?? false) && !(topic?.isChannel ?? false) && !isFromCurrentSender(message: message)
    }

    // Show avatar in the given message
    func shouldShowAvatar(for message: Message, at indexPath: IndexPath) -> Bool {
        return avatarsVisible(message: message) && (!isNextMessageSameSender(at: indexPath) || !isNextMessageSameDate(at: indexPath))
    }

    // Should we show upload progress bar for reference attachment messages?
    func shouldShowProgressBar(for message: Message) -> Bool {
        return message.isPending && (message.content?.hasRefEntity ?? false)
    }

    func isNewDateLabelVisible(at indexPath: IndexPath) -> Bool {
        return !isPreviousMessageSameDate(at: indexPath)
    }
}

// Message size calculation
extension MessageViewController: MessageViewLayoutDelegate {

    // MARK: MessageViewLayoutDelegate method

    // Claculate positions and sizes of all subviews in a cell.
    func collectionView(_ collectionView: UICollectionView, fillAttributes attr: MessageViewLayoutAttributes) {
        if attr.representedElementCategory == .supplementaryView {
            // Request for pinned area attributes (section header).
            let height: CGFloat = self.pinnedMessageSeqs.isEmpty ? 0 : Constants.kPinnedMessagesViewHeight
            attr.frame = CGRect(origin: CGPoint(), size: CGSize(width: collectionView.frame.width - collectionView.layoutMargins.left - collectionView.layoutMargins.right, height: height))
            attr.zIndex = 1
            return
        } else if attr.representedElementCategory == .decorationView {
            // This should not happen.
            return
        }

        // Fill out attributes for a regular message bubble.

        let indexPath = attr.indexPath

        // Cell content
        let message = messages[indexPath.item]

        // Is this an outgoing message?
        let isOutgoing = isFromCurrentSender(message: message)
        // The message set has avatars.
        let hasAvatars = avatarsVisible(message: message)
        let isDeleted = message.isDeleted
        // This message has an avatar.
        let isAvatarVisible = !isDeleted && shouldShowAvatar(for: message, at: indexPath)
        // This message has been edited.
        let isEdited = message.isEdited

        // Insets for the message bubble relative to collectionView: bubble should not touch the sides of the screen.
        let containerPadding = isOutgoing ? Constants.kOutgoingContainerPadding : Constants.kIncomingContainerPadding

        // Size of the message bubble.
        let showUploadProgress = shouldShowProgressBar(for: message)
        let containerSize = calcContainerSize(for: message, avatarsVisible: hasAvatars, progressVisible: showUploadProgress)
        // Get cell size.
        let cellSize = !isDeleted ? calcCellSize(forItemAt: indexPath) : containerSize
        attr.cellSpacing = (message as? StoredMessage)?.isVisualMedia == true
            ? Constants.kMediaCellSpacing
            : Constants.kVerticalCellSpacing

        // Height of the field with the current date above the first message of the day.
        let newDateLabelHeight = !isDeleted ? calcNewDateLabelHeight(at: indexPath) : 0

        // This is the height of the field with the sender's name.
        let senderNameLabelHeight = isAvatarVisible ? Constants.kSenderNameLabelHeight : 0

        if isAvatarVisible {
            attr.avatarFrame = CGRect(x: 0, y: cellSize.height - Constants.kAvatarSize - senderNameLabelHeight, width: Constants.kAvatarSize, height: Constants.kAvatarSize)

            // Sender name under the avatar.
            attr.senderNameFrame = CGRect(origin: CGPoint(x: 0, y: cellSize.height - senderNameLabelHeight), size: CGSize(width: cellSize.width, height: senderNameLabelHeight))
        } else {
            attr.avatarFrame = .zero
            attr.senderNameFrame = .zero
        }

        // Additional left padding in group topics with avatar
        let avatarPadding = hasAvatars ? Constants.kAvatarSize : 0

        // isDeleted ? center container : else
        // isFromCurrent Sender ? Flush container right : flush left.
        let originX =
            isDeleted ? (collectionView.bounds.width - containerSize.width) / 2 :
            isOutgoing ? cellSize.width - avatarPadding - containerSize.width - containerPadding.right : avatarPadding + containerPadding.left
        attr.containerFrame = CGRect(origin: CGPoint(x: originX, y: newDateLabelHeight + containerPadding.top), size: containerSize)

        // Content: RichTextLabel.
        let contentInset = contentInsets(for: message)
        attr.contentFrame = CGRect(x: contentInset.left, y: contentInset.top, width: attr.containerFrame.width - contentInset.left - contentInset.right, height: attr.containerFrame.height - contentInset.top - contentInset.bottom - (showUploadProgress ? Constants.kProgressViewHeight : 0))

        let metadataY = attr.containerFrame.height + Constants.kExternalMetadataGap
        var rightEdge = CGPoint(x: attr.containerFrame.width - Constants.kDeliveryMarkerPadding, y: metadataY)
        if isOutgoing {
            rightEdge.x -= Constants.kDeliveryMarkerSize
            attr.deliveryMarkerFrame = CGRect(x: rightEdge.x, y: rightEdge.y, width: Constants.kDeliveryMarkerSize, height: Constants.kDeliveryMarkerSize)
        } else {
            attr.deliveryMarkerFrame = .zero
        }

        attr.timestampFrame = !message.isDeleted ? CGRect(x: rightEdge.x - Constants.kTimestampWidth - Constants.kTimestampPadding, y: rightEdge.y, width: Constants.kTimestampWidth, height: Constants.kExternalMetadataHeight) : .zero

        if isEdited {
            let x = attr.timestampFrame.origin != .zero ? attr.timestampFrame.origin.x - Constants.kEditedMarkerWidth - Constants.kEditedMarkerPadding : rightEdge.x
            attr.editedMarkerFrame = CGRect(x: x, y: rightEdge.y, width: Constants.kEditedMarkerWidth, height: Constants.kExternalMetadataHeight)
        } else {
            attr.editedMarkerFrame = .zero
        }

        // New date label
        if newDateLabelHeight > 0 {
            attr.newDateFrame = CGRect(origin: CGPoint(x: 0, y: attr.containerFrame.minY - containerPadding.top - newDateLabelHeight), size: CGSize(width: cellSize.width, height: newDateLabelHeight))
        } else {
            attr.newDateFrame = .zero
        }

        if showUploadProgress {
            let origin = CGPoint(x: attr.contentFrame.origin.x, y: attr.contentFrame.origin.y + attr.contentFrame.size.height)
            attr.progressViewFrame =
                CGRect(origin: origin, size: CGSize(width: attr.contentFrame.width, height: Constants.kProgressViewHeight))
        } else {
            attr.progressViewFrame = .zero
        }

        attr.frame = CGRect(origin: CGPoint(), size: cellSize)
    }

    // MARK: supporting methods

    // Calculate and cache message cell size
    func calcCellSize(forItemAt indexPath: IndexPath) -> CGSize {
        // if let size = cellSizeCache[indexPath.item] {
        //    return size
        // }

        let message = messages[indexPath.item]
        let hasAvatars = avatarsVisible(message: message)
        let showProgress = shouldShowProgressBar(for: message)
        let containerHeight = calcContainerSize(for: message, avatarsVisible: hasAvatars, progressVisible: showProgress).height
        let size = CGSize(width: calcCellWidth(), height: calcCellHeightFromContent(for: message, at: indexPath, containerHeight: containerHeight, avatarsVisible: hasAvatars, progressVisible: showProgress))
        return size
    }

    func calcCellWidth() -> CGFloat {
        return collectionView.frame.width - collectionView.layoutMargins.left - collectionView.layoutMargins.right
    }

    func calcCellHeightFromContent(
        for message: Message, at indexPath: IndexPath, containerHeight: CGFloat,
        avatarsVisible hasAvatars: Bool, progressVisible: Bool) -> CGFloat {

        let senderNameLabelHeight: CGFloat = shouldShowAvatar(for: message, at: indexPath) ? Constants.kSenderNameLabelHeight : 0
        let newDateLabelHeight: CGFloat = calcNewDateLabelHeight(at: indexPath)
        let avatarHeight = hasAvatars ? Constants.kAvatarSize : 0

        let metadataHeight = message.isDeleted
            ? 0
            : Constants.kExternalMetadataGap + Constants.kExternalMetadataHeight
        let totalLabelHeight: CGFloat = newDateLabelHeight + containerHeight + metadataHeight + senderNameLabelHeight + (progressVisible ? Constants.kProgressViewHeight : 0)
        return max(avatarHeight, totalLabelHeight)
    }

    func calcNewDateLabelHeight(at indexPath: IndexPath) -> CGFloat {
        let height: CGFloat
        if isNewDateLabelVisible(at: indexPath) {
            height = Constants.kNewDateLabelHeight
        } else if !(topic?.isGrpType ?? false) && !isPreviousMessageSameSender(at: indexPath) {
            height = Constants.kAdditionalP2PVerticalCellSpacing
        } else {
            height = 0
        }
        return height
    }

    // Calculate maximum width of content inside message bubble
    func calcMaxContentWidth(for message: Message, avatarsVisible: Bool) -> CGFloat {

        let insets = contentInsets(for: message)

        let avatarWidth = avatarsVisible ? Constants.kAvatarSize : 0

        let padding = isFromCurrentSender(message: message) ? Constants.kOutgoingContainerPadding : Constants.kIncomingContainerPadding

        let availableWidth = calcCellWidth() - avatarWidth - padding.left - padding.right
        // The design ceiling includes the bubble's padding, not just its text.
        return max(0, MessageBubbleLayoutPolicy.maxContentWidth(availableWidth: availableWidth)
                   - insets.left - insets.right)
    }

    /// Calculate size of the view which holds message content.
    func calcContainerSize(for message: Message, avatarsVisible: Bool, progressVisible: Bool) -> CGSize {
        let maxWidth = calcMaxContentWidth(for: message, avatarsVisible: avatarsVisible)
        let insets = contentInsets(for: message)
        let isVisualMedia = (message as? StoredMessage)?.isVisualMedia == true

        var size = calcContentSize(for: message, maxWidth: maxWidth)

        size.width += insets.left + insets.right
        if !isVisualMedia {
            size.width = max(size.width,
                             message.isEdited ? Constants.kMinimumEditedCellWidth : Constants.kMinimumCellWidth)
        }
        size.height += insets.top + insets.bottom
        if progressVisible {
            size.height += Constants.kProgressViewHeight
        }

        return size
    }

    /// Calculate size of message content.
    func calcContentSize(for message: Message, maxWidth: CGFloat) -> CGSize {
        let attributedText = NSMutableAttributedString()

        let textColor: UIColor
        if message.isDeleted {
            textColor = Constants.kDeletedMessageTextColor
        } else if traitCollection.userInterfaceStyle == .dark {
            textColor = isFromCurrentSender(message: message) ? Constants.kOutgoingTextColorDark : Constants.kIncomingTextColorDark
        } else {
            textColor = isFromCurrentSender(message: message) ? Constants.kOutgoingTextColorLight : Constants.kIncomingTextColorLight
        }

        let storedMessage = message as! StoredMessage
        if let content = storedMessage.attributedContent(fitIn: CGSize(width: maxWidth, height: collectionView.frame.height * 0.66), withDefaultAttributes: [.font: Constants.kContentFont, .foregroundColor: textColor]) {
            attributedText.append(content)
        } else {
            attributedText.append(NSAttributedString(string: "none", attributes: [.font: Constants.kContentFont]))
        }
        // FIXME: storedMessage may contain an image surrounded by text. In such cases,
        // size calculations may be wrong. Handle it.
        return storedMessage.isVisualMedia ?
            attributedText.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                                        context: nil).integral.size :
            textSizeHelper.computeSize(for: attributedText, within: maxWidth)
    }

    private func contentInsets(for message: Message) -> UIEdgeInsets {
        if message.isDeleted {
            return Constants.kDeletedMessageContentInset
        }
        if (message as? StoredMessage)?.isVisualMedia == true {
            return Constants.kMediaMessageContentInset
        }
        return isFromCurrentSender(message: message)
            ? Constants.kOutgoingMessageContentInset
            : Constants.kIncomingMessageContentInset
    }
}

extension MessageViewController: PendingMessagePreviewDelegate {
    func pendingPreviewMessageSize(forMessage msg: NSAttributedString) -> CGSize {
        return self.textSizeHelper.computeSize(for: msg, within: CGFloat.infinity)
    }
    func dismissPendingMessagePreview() {
        // Make sure MessageVC is the first responder so we can successfully reload
        // the input accessory view.
        self.becomeFirstResponder()
        self.interactor?.dismissPendingMessage()
        self.togglePreviewBar(with: nil)
        self.view.setNeedsLayout()
    }
}

extension MessageViewController: ForwardToDelegate {
    func forwardMessage(_ message: Drafty, preview: Drafty, from originTopic: String, to topicId: String) {
        self.presentChatReplacingCurrentVC(with: topicId, initializationCallback: {
            ($0 as! MessageViewController).attachForwardedMessage(message, preview, from: originTopic)
        })
    }

    func attachForwardedMessage(_ message: Drafty, _ preview: Drafty, from origin: String) {
        if self.topic?.isWriter ?? false {
            self.interactor?.prepareToForward(message: message, forwardedFrom: origin, preview: preview)
        }
    }
}

extension MessageViewController {
    var chatDisplaySource: ChatDisplaySource? {
        guard !chatPageRetired, let topic = topic else { return nil }
        return ChatDisplaySource(page: chatPageID, topic: topic)
    }

    func invalidateChatDisplayIntent() {
        assert(Thread.isMainThread)
        chatInteractionRevision &+= 1
        if messages.isEmpty { chatEmptyFollowLatest = false }
    }

    func captureChatSubmissionIntent() -> ChatDisplayIntent {
        assert(Thread.isMainThread)
        chatSubmissionRevision &+= 1
        let editing: Bool
        if case .edit? = interactor?.pendingMessage { editing = true } else { editing = false }
        guard let source = chatDisplaySource else { return .preserve }
        return .submission(ChatSubmissionDisplayTicket(source: source,
            interaction: chatInteractionRevision, submission: chatSubmissionRevision, editing: editing))
    }

    func chatPreviewIntentCapture(for preview: UIViewController) -> () -> ChatDisplayIntent {
        let originalSource = chatDisplaySource
        return { [weak self, weak preview] in
            // The chat is normally offscreen while its preview is on top. This
            // is an ownership check for UI intent, not a send authorization gate.
            guard let self = self, let preview = preview,
                  originalSource != nil, self.chatDisplaySource == originalSource,
                  let stack = self.navigationController?.viewControllers,
                  stack.contains(where: { $0 === self }), stack.last === preview else { return .preserve }
            return self.captureChatSubmissionIntent()
        }
    }

    var chatMaximumOffset: CGFloat {
        guard let list = collectionView else { return 0 }
        return max(-list.adjustedContentInset.top,
                   list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom)
    }

    func updateChatLatestButton() {
        guard let list = collectionView, let button = goToLatestButton else { return }
        button.isHidden = list.contentOffset.y >= chatMaximumOffset - 40
    }

    func withChatProgrammaticLayout(_ operation: () -> Void) {
        chatProgrammaticDepth += 1
        defer {
            chatLastObservedOffset = collectionView?.contentOffset
            chatProgrammaticDepth -= 1
        }
        operation()
    }

    func captureChatViewport() -> ChatViewportSnapshot {
        guard let list = collectionView else {
            return ChatViewportSnapshot(anchors: [], offset: .zero, atBottom: false,
                                        interaction: chatInteractionRevision)
        }
        // A contentOffset change can precede UICollectionView's visible-cell
        // cache update. Capture current layout geometry, including newly visible
        // neighbors, without suppressing scroll delegate intent invalidation.
        list.layoutIfNeeded()
        let top = list.contentOffset.y + list.adjustedContentInset.top
        let bottom = list.contentOffset.y + list.bounds.height - list.adjustedContentInset.bottom
        let viewport = CGRect(x: list.contentOffset.x + list.adjustedContentInset.left, y: top,
                              width: max(0, list.bounds.width - list.adjustedContentInset.left - list.adjustedContentInset.right),
                              height: max(0, bottom - top))
        let attributes = (list.collectionViewLayout.layoutAttributesForElements(in: viewport) ?? [])
            .filter { $0.representedElementCategory == .cell && $0.indexPath.section == 0 &&
                messages.indices.contains($0.indexPath.item) && $0.frame.intersects(viewport) }
            .sorted { $0.frame.minY < $1.frame.minY }
        let anchors = attributes.map { attribute -> ChatViewportAnchor in
            let message = messages[attribute.indexPath.item]
            return ChatViewportAnchor(dbID: message.msgId, seq: message.seqId,
                                      offset: attribute.frame.minY - top)
        }
        let atBottom = messages.isEmpty
            ? (chatPresentedNonempty ? chatEmptyFollowLatest : chatInteractionRevision == 0 || chatEmptyFollowLatest)
            : list.contentOffset.y >= chatMaximumOffset - 40
        return ChatViewportSnapshot(anchors: anchors, offset: list.contentOffset,
            atBottom: atBottom, interaction: chatInteractionRevision)
    }

    func finishChatViewport(_ snapshot: ChatViewportSnapshot, source: ChatDisplaySource,
                            intent: ChatDisplayIntent, firstNonempty: Bool = false) {
        guard chatDisplaySource == source, snapshot.interaction == chatInteractionRevision,
              let list = collectionView else { return }
        withChatProgrammaticLayout {
            list.layoutIfNeeded()
            var latest = false
            switch intent {
            case .preserve: break
            case .passive:
                latest = snapshot.atBottom || (firstNonempty && chatInteractionRevision == 0)
            case .submission(let ticket):
                if ticket.editing { break }
                if ticket.source == source, ticket.interaction == chatInteractionRevision,
                   ticket.submission == chatSubmissionRevision, chatConsumedSubmission != ticket.submission,
                   !messages.isEmpty {
                    chatConsumedSubmission = ticket.submission
                    latest = true
                } else {
                    latest = snapshot.atBottom
                }
            }
            var y = snapshot.offset.y
            if latest {
                y = chatMaximumOffset
            } else {
                for anchor in snapshot.anchors {
                    let byID = anchor.dbID > 0 ? messages.firstIndex { $0.msgId == anchor.dbID } : nil
                    let index = byID ?? (anchor.seq > 0 ? messages.firstIndex { $0.seqId == anchor.seq } : nil)
                    if let index = index, let attributes = list.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) {
                        y = attributes.frame.minY - anchor.offset - list.adjustedContentInset.top
                        break
                    }
                }
            }
            y = min(chatMaximumOffset, max(-list.adjustedContentInset.top, y))
            list.setContentOffset(CGPoint(x: snapshot.offset.x, y: y), animated: false)
        }
        updateChatLatestButton()
    }

    // Only UIKit work is serialized. Later snapshots do not replace the array
    // until both phases of the currently presented batch have completed.
    func enqueueChatPresentation(_ operation: @escaping (@escaping () -> Void) -> Void) {
        assert(Thread.isMainThread)
        chatPresentationQueue.append(operation)
        drainChatPresentations()
    }

    func drainChatPresentations() {
        guard !chatPresentationRunning, !chatPresentationQueue.isEmpty else { return }
        chatPresentationRunning = true
        let operation = chatPresentationQueue.removeFirst()
        operation { [weak self] in
            guard let self = self else { return }
            self.chatPresentationRunning = false
            self.drainChatPresentations()
        }
    }

    func reloadChatLayoutPreservingViewport(reloadRange: ClosedRange<Int>? = nil, _ changes: (() -> Void)? = nil) {
        guard let source = chatDisplaySource else { return }
        enqueueChatPresentation { [weak self] done in
            guard let self = self, self.chatDisplaySource == source, let list = self.collectionView else {
                done(); return
            }
            let viewport = self.captureChatViewport()
            self.withChatProgrammaticLayout {
                changes?()
                if let range = reloadRange {
                    let paths = self.messageSeqIdIndex.filter { range.contains($0.key) }.map { IndexPath(item: $0.value, section: 0) }
                    list.reloadItems(at: paths)
                } else {
                    list.reloadSections(IndexSet(integer: 0))
                }
                list.layoutIfNeeded()
            }
            self.finishChatViewport(viewport, source: source, intent: .preserve)
            done()
        }
    }
}

extension MessageViewController: UICollectionViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        invalidateChatDisplayIntent()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if chatProgrammaticDepth == 0, let previous = chatLastObservedOffset,
           previous != scrollView.contentOffset {
            // Includes accessibility and other unattributed viewport movement.
            invalidateChatDisplayIntent()
        }
        chatLastObservedOffset = scrollView.contentOffset
        updateChatLatestButton()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard let path = self.highlightCellAtPathAfterScroll else { return }
        self.highlightCellAtPathAfterScroll = nil
        guard let cell = collectionView.cellForItem(at: path) as? MessageCell else { return }
        cell.highlightAnimated(withDuration: 4.0)
    }
}
