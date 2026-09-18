//
//  SendMessageBar.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit

enum AudioBarAction {
    case start
    case stopAndSend
    case stopAndDelete
    case lock
    case stopRecording
    case pauseRecording
    case playbackStart
    case playbackPause
    case playbackReset
}

public enum PendingPreviewAction {
    case none
    case reply
    case edit
}

enum MessageAttachmentAction {
    case library
    case camera
    case file
}

protocol SendMessageBarDelegate: AnyObject {
    func sendMessageBar(sendText: String)
    func sendMessageBar(attachment: MessageAttachmentAction)
    func sendMessageBar(textChangedTo text: String)
    func sendMessageBar(enablePeersMessaging: Bool)
    func sendMessageBar(recordAudio: AudioBarAction)
}

class SendMessageBar: UIView {
    enum AudioBarState {
        case longInitial // Initial locked state: recording audio.
        case longPlayback // Locked state: playing back the recording
        case longPaused // Locked state: playback paused
        case short // Not locked state: recording.
        case hidden
    }

    // MARK: - Constants

    private enum Constants {
        static let maxLines: CGFloat = 4
        static let inputFieldInsetLeading: CGFloat = 4
        static let inputFieldInsetTrailing: CGFloat = 60
        static let peerMessagingDisabledHeight: CGFloat = 30
        static let kPreviewCancelButtonMaxWidth: CGFloat = 36

        static let kSendButtonPointsNormal: CGFloat = 22
        static let kSendButtonPointsPressed: CGFloat = 44
        static let kButtonSizeNormal: CGFloat = 44
        // Size of the activated audio recording button.
        static let kSendButtonSizePressed: CGFloat = 54

        // Initial input text weight.
        static let kInitialInputFieldHeight: CGFloat = 56

        static let kSendButtonImageWave = ClawTheme.symbol("mic.fill", pointSize: Constants.kSendButtonPointsNormal, weight: .medium)!
        static let kSendButtonImageWavePressed = ClawTheme.symbol("mic.circle.fill", pointSize: Constants.kSendButtonPointsPressed, weight: .medium)!
        static let kWaveInsetsShort = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 88)
        static let kWaveInsetsLong = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 52)
    }

    // MARK: Action delegate

    weak var delegate: (SendMessageBarDelegate & PendingMessagePreviewDelegate)?

    // MARK: IBOutlets

    @IBOutlet weak var attachButton: UIButton!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var sendButtonSize: NSLayoutConstraint!
    @IBOutlet weak var sendButtonHorizontal: NSLayoutConstraint!
    @IBOutlet weak var sendButtonVertical: NSLayoutConstraint!

    // Sliders for locking and deleting audio recording.
    @IBOutlet weak var verticalSliderView: UIView!
    @IBOutlet weak var horizontalSliderView: UIView!

    // Constraints.
    private var sendButtonConstrains: CGPoint?
    // Position in SendMessageBar coordinates.
    private var sendButtonLocation: CGPoint!

    @IBOutlet weak var inputField: PlaceholderTextView!
    @IBOutlet weak var inputFieldHeight: NSLayoutConstraint!

    // Overlay for writing disabled. Hidden by default.
    @IBOutlet weak var allDisabledView: UIView!
    // Message "Peer's messaging is disabled. Enable". Not installed by default.
    @IBOutlet weak var peerMessagingDisabledView: UIStackView!
    @IBOutlet weak var peerMessagingDisabledHeight: NSLayoutConstraint!
    @IBOutlet weak var previewView: RichTextView!
    @IBOutlet weak var previewViewHeight: NSLayoutConstraint!

    @IBOutlet weak var audioView: UIView!
    @IBOutlet weak var deleteAudioButton: UIButton!
    @IBOutlet weak var deleteAudioButtonWidth: NSLayoutConstraint!
    @IBOutlet weak var stopAudioRecordingButton: UIButton!
    @IBOutlet weak var playAudioButton: UIButton!
    @IBOutlet weak var pauseAudioButton: UIButton!

    @IBOutlet weak var audioDurationLabel: UILabel!
    @IBOutlet weak var audioDurationLabelHeight: NSLayoutConstraint!
    @IBOutlet weak var audioViewHeight: NSLayoutConstraint!
    @IBOutlet weak var wavePreviewImageView: WaveImageView!
    @IBOutlet weak var wavePreviewLeading: NSLayoutConstraint! // 40 <-> 8

    // MARK: Properties
    private var audioLocked: Bool = false

    private var pendingPreviewAction: PendingPreviewAction = .none
    public var pendingPreviewText: NSAttributedString? {
        get { return previewView.attributedText.length != .zero ? previewView.attributedText : nil }
        set { previewView.attributedText = newValue }
    }

    var previewMaxWidth: CGFloat {
        return inputField.frame.width - Constants.kPreviewCancelButtonMaxWidth
    }

    // MARK: IBActions

    @IBAction func attach(_ sender: UIButton) {
        inputField.resignFirstResponder()
        guard let presenter = topPresenter() else { return }
        let sheet = ClawAttachmentSheetController { [weak self] action in
            self?.delegate?.sendMessageBar(attachment: action)
        }
        presenter.present(sheet, animated: false)
    }

    private func topPresenter() -> UIViewController? {
        var presenter = window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        if let navigation = presenter as? UINavigationController {
            return navigation.visibleViewController ?? navigation
        }
        if let tabs = presenter as? UITabBarController {
            return tabs.selectedViewController ?? tabs
        }
        return presenter
    }

    @IBAction func send(_ sender: UIButton) {
        let msg = inputField.actualText.trimmingCharacters(in: .whitespacesAndNewlines)

        if audioLocked {
            self.delegate?.sendMessageBar(recordAudio: .stopAndSend)
        } else if !msg.isEmpty {
            delegate?.sendMessageBar(sendText: msg)
            inputField.text = nil
            textViewDidChange(inputField)
        }
    }

    @IBAction func deleteRecording(_ sender: Any) {
        self.delegate?.sendMessageBar(recordAudio: .stopAndDelete)
    }

    @IBAction func stopRecording(_ sender: Any) {
        self.delegate?.sendMessageBar(recordAudio: .stopRecording)
    }

    @IBAction func playRecording(_ sender: Any) {
        self.delegate?.sendMessageBar(recordAudio: .playbackStart)
    }

    @IBAction func pausePlayback(_ sender: Any) {
        self.delegate?.sendMessageBar(recordAudio: .playbackPause)
    }

    // Handle audio recorder button swipes and presses.
    @IBAction func longPressed(sender: UILongPressGestureRecognizer) {
        guard inputField.actualText.isEmpty, !audioLocked else { return }

        switch sender.state {
        case .began:
            let loc = sender.location(in: self)
            self.captureRecordingGestureOrigin()
            self.sendButtonLocation = CGPoint(x: loc.x, y: loc.y)
            self.delegate?.sendMessageBar(recordAudio: .start)
        case .ended:
            if recordingStarted {
                self.delegate?.sendMessageBar(recordAudio: .stopAndSend)
            } else {
                self.delegate?.sendMessageBar(recordAudio: .pauseRecording)
            }
        case .cancelled:
            self.delegate?.sendMessageBar(recordAudio: .pauseRecording)
        case .changed:
            guard recordingStarted, let origin = sendButtonConstrains else { return }
            // Constrain movements to either strictly horizontal or strictly vertical.
            let loc = sender.location(in: self)
            // dX and dY are negative: the movement is up and to the left.
            var dX = min(0, loc.x - sendButtonLocation.x)
            var dY = min(0, loc.y - sendButtonLocation.y)

            if abs(dX) > abs(dY) {
                // Horizontal move.
                dY = 0
            } else {
                // Vertical move.
                dX = 0
            }
            if dX < -60 {
                // User swiped to "Trash".
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioLocked = false
                sender.isEnabled = false
                audioBarState(.stopAndDelete)
                self.delegate?.sendMessageBar(recordAudio: .stopAndDelete)
                sender.isEnabled = true
            } else if dY < -60 {
                // User swiped to "Lock".
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                audioLocked = true
                sender.isEnabled = false
                audioBarState(.lock)
                sender.isEnabled = true
                self.layoutIfNeeded()
            } else {
                self.sendButtonHorizontal.constant = origin.x + dX
                self.sendButtonVertical.constant = origin.y + dY
            }
        default:
            break
        }
    }

    @IBAction func enablePeerMessagingClicked(_ sender: Any) {
        self.delegate?.sendMessageBar(enablePeersMessaging: true)
    }

    @IBAction func cancelPreviewClicked(_ sender: Any) {
        self.delegate?.dismissPendingMessagePreview()
    }

    // MARK: - Private properties

    private var recordingStarted = false
    private var inputFieldMaxHeight: CGFloat = 120

    // MARK: - Initializers

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        loadNib()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        loadNib()
    }

    // This is needed for proper calculation of size from constraints.
    override var intrinsicContentSize: CGSize {
        return CGSize.zero
    }

    // MARK: - Configuration

    private func loadNib() {
        let nib = UINib(nibName: "SendMessageBar", bundle: Bundle(for: type(of: self)))
        let nibView = nib.instantiate(withOwner: self, options: nil).first as! UIView
        nibView.backgroundColor = ClawTheme.surface
        nibView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nibView)
        NSLayoutConstraint.activate([
            nibView.topAnchor.constraint(equalTo: topAnchor),
            nibView.bottomAnchor.constraint(equalTo: bottomAnchor),
            nibView.rightAnchor.constraint(equalTo: rightAnchor),
            nibView.leftAnchor.constraint(equalTo: leftAnchor)
            ])
        configure()
    }

    private func configure() {
        horizontalSliderView.alpha = 0.9
        verticalSliderView.alpha = 0.9

        backgroundColor = ClawTheme.surface
        inputField.backgroundColor = ClawTheme.surfaceMuted
        inputField.textColor = ClawTheme.ink
        inputField.tintColor = ClawTheme.primary
        inputField.font = ClawTheme.font(16)
        inputField.adjustsFontForContentSizeCategory = true
        inputField.placeholderText = NSLocalizedString("输入消息", comment: "Message input placeholder")
        inputField.layer.borderWidth = 1
        inputField.layer.borderColor = ClawTheme.border.cgColor
        inputField.layer.cornerRadius = ClawTheme.cardRadius
        inputField.layer.cornerCurve = .continuous
        inputField.clipsToBounds = true
        inputField.autoresizingMask = [.flexibleHeight]
        inputField.delegate = self
        inputField.textContainerInset = UIEdgeInsets(
            top: inputField.textContainerInset.top,
            left: 14,
            bottom: inputField.textContainerInset.bottom,
            right: Constants.inputFieldInsetTrailing)

        ClawTheme.styleIconButton(attachButton, symbolName: "plus", pointSize: ClawTheme.iconCompact)
        attachButton.accessibilityLabel = NSLocalizedString("添加附件", comment: "Add attachment")
        sendButton.tintColor = ClawTheme.primary
        sendButton.imageView?.contentMode = .scaleAspectFit
        sendButton.contentHorizontalAlignment = .center
        sendButton.contentVerticalAlignment = .center
        sendButton.imageEdgeInsets = .zero
        sendButton.contentEdgeInsets = .zero
        sendButton.layer.cornerRadius = ClawTheme.buttonRadius
        sendButton.layer.cornerCurve = .continuous
        sendButton.accessibilityIdentifier = "claw.chat.send"
        inputField.accessibilityIdentifier = "claw.chat.input"
        deleteAudioButton.accessibilityLabel = NSLocalizedString("删除录音", comment: "Discard recording")
        stopAudioRecordingButton.accessibilityLabel = NSLocalizedString("停止录音", comment: "Stop recording")
        playAudioButton.accessibilityLabel = NSLocalizedString("播放录音", comment: "Play recording")
        pauseAudioButton.accessibilityLabel = NSLocalizedString("暂停录音", comment: "Pause recording")

        if let font = inputField.font {
            inputFieldMaxHeight = font.lineHeight * Constants.maxLines
        }

        sendButton.isEnabled = true
        toggleNotAvailableOverlay(visible: false)
        togglePeerMessagingDisabled(visible: false)
        togglePendingPreviewBar(withMessage: nil)

        showAudioBar(.hidden)
    }

    // Presentation only: existing send/record delegates retain their original semantics.
    private func updateSendButtonAppearance(sending: Bool, recording: Bool = false) {
        let font = ClawTheme.font(16, weight: .semibold)
        sendButton.titleLabel?.font = font
        let label = pendingPreviewAction == .edit && !audioLocked
            ? NSLocalizedString("保存", comment: "Save edited message")
            : NSLocalizedString("发送", comment: "Send message")
        let width: CGFloat
        let height: CGFloat
        if sending {
            sendButton.setImage(nil, for: .normal)
            sendButton.setTitle(label, for: .normal)
            sendButton.setTitleColor(ClawTheme.onBrand, for: .normal)
            sendButton.backgroundColor = ClawTheme.primary
            sendButton.accessibilityLabel = label
            sendButton.accessibilityHint = nil
            width = max(64, ceil((label as NSString).size(withAttributes: [.font: font]).width) + 20)
            height = max(48, ceil(font.lineHeight) + 16)
        } else {
            sendButton.setTitle(nil, for: .normal)
            sendButton.setImage(recording ? Constants.kSendButtonImageWavePressed : Constants.kSendButtonImageWave,
                                for: .normal)
            sendButton.backgroundColor = .clear
            sendButton.tintColor = ClawTheme.primary
            sendButton.accessibilityLabel = NSLocalizedString("录音", comment: "Record audio")
            sendButton.accessibilityHint = NSLocalizedString("按住录音，松开发送；向左滑动取消", comment: "Record gesture")
            width = recording ? Constants.kSendButtonSizePressed : 48
            height = width
        }
        sendButtonSize.constant = width
        sendButton.constraints.first(where: { $0.firstAttribute == .height })?.constant = height
        if !recording {
            sendButtonHorizontal.constant = -width / 2 - 4
            sendButtonVertical.constant = -height / 2 - 4
        }
        inputField.textContainerInset.right = width + 12
        if !inputField.isHidden {
            inputFieldHeight.constant = max(inputFieldHeight.constant, height + 8)
        }
        if !audioView.isHidden {
            audioViewHeight.constant = max(40, height + 8)
        }
    }

    private func resizeInputField() {
        let font = inputField.font ?? ClawTheme.font(16)
        let buttonHeight = sendButton.constraints.first(where: { $0.firstAttribute == .height })?.constant ?? 48
        let minimumHeight = max(Constants.kInitialInputFieldHeight, buttonHeight + 8)
        inputFieldMaxHeight = max(minimumHeight, ceil(font.lineHeight) * Constants.maxLines
                                  + inputField.textContainerInset.top + inputField.textContainerInset.bottom)
        let fitting = inputField.sizeThatFits(CGSize(width: max(1, inputField.bounds.width),
                                                      height: .greatestFiniteMagnitude))
        inputFieldHeight.constant = inputField.actualText.isEmpty ? minimumHeight
            : max(minimumHeight, min(inputFieldMaxHeight, ceil(fitting.height)))
        inputField.isScrollEnabled = fitting.height > inputFieldMaxHeight
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard inputField != nil else { return }
        inputField.layer.borderColor = ClawTheme.border.cgColor
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory,
           audioView.isHidden {
            inputField.font = ClawTheme.font(16)
            updateSendButtonAppearance(sending: !inputField.actualText.isEmpty)
            resizeInputField()
        }
    }

    // MARK: - Subviews handling

    public func toggleNotAvailableOverlay(visible: Bool) {
        allDisabledView.isHidden = !visible
        isUserInteractionEnabled = !visible
    }

    public func togglePeerMessagingDisabled(visible: Bool) {
        peerMessagingDisabledView.isHidden = !visible
        peerMessagingDisabledView.isUserInteractionEnabled = visible
        peerMessagingDisabledHeight.constant = visible ? Constants.peerMessagingDisabledHeight : 0
    }

    public func togglePendingPreviewBar(withMessage message: NSAttributedString?, onAction action: PendingPreviewAction = .none) {
        if let message = message, let delegate = self.delegate {
            let textbounds = delegate.pendingPreviewMessageSize(forMessage: message)
            previewViewHeight.constant = textbounds.height
            pendingPreviewText = message
            previewView.isHidden = false
            pendingPreviewAction = action
        } else {
            previewViewHeight.constant = .zero
            pendingPreviewText = nil
            previewView.isHidden = true
            pendingPreviewAction = .none
        }
        textViewDidChange(inputField)
    }

    // MARK: - Audio playback and recording

    // State changes are confirmed by the actual recorder/player, not the button.
    func recordingDidStart() {
        recordingStarted = true
        showAudioBar(.short)
        updateSendButtonAppearance(sending: false, recording: true)
        verticalSliderView.isHidden = false
        horizontalSliderView.isHidden = false
        layoutIfNeeded()
    }

    func recordingDidStop() {
        recordingStarted = false
        audioLocked = true
        resetRecordingGesture()
        updateSendButtonAppearance(sending: true)
        showAudioBar(.longPaused)
    }

    func resetRecordingState() {
        recordingStarted = false
        audioLocked = false
        resetRecordingGesture()
        showAudioBar(.hidden)
    }

    private func captureRecordingGestureOrigin() {
        sendButtonConstrains = CGPoint(x: sendButtonHorizontal.constant, y: sendButtonVertical.constant)
    }

    private func resetRecordingGesture() {
        // A page may disappear without ever beginning a recording gesture.
        // Consume the snapshot so a later reset cannot overwrite a new layout.
        if let origin = sendButtonConstrains {
            sendButtonHorizontal.constant = origin.x
            sendButtonVertical.constant = origin.y
            sendButtonConstrains = nil
        }
        verticalSliderView.isHidden = true
        horizontalSliderView.isHidden = true
        sendButtonSize.constant = Constants.kButtonSizeNormal
    }

    // Un-locked audio recording, show duration label & wave.
    func showAudioBar(_ state: AudioBarState) {
        if state == .hidden || state == .short {
            deleteAudioButton.show(false)
            playAudioButton.show(false)
            pauseAudioButton.show(false)
            stopAudioRecordingButton.show(false)
        } else {
            // Long bar
            deleteAudioButton.show(true, dimension: Constants.kButtonSizeNormal)
            switch state {
            case .longInitial:
                playAudioButton.show(false)
                pauseAudioButton.show(false)
                stopAudioRecordingButton.show(true, dimension: Constants.kButtonSizeNormal)
            case .longPlayback:
                playAudioButton.show(false)
                pauseAudioButton.show(true, dimension: Constants.kButtonSizeNormal)
                stopAudioRecordingButton.show(false)
            case .longPaused:
                playAudioButton.show(true, dimension: Constants.kButtonSizeNormal)
                pauseAudioButton.show(false)
                stopAudioRecordingButton.show(false)
            default:
                break
            }
        }

        if state == .hidden {
            // Bar hidden.
            inputField.show(true, height: Constants.kInitialInputFieldHeight)
            attachButton.isHidden = false
            // audioDurationLabel.show(false)
            audioDurationLabel.isHidden = true
            wavePreviewImageView.isHidden = true
            wavePreviewImageView.reset()
            audioViewHeight.constant = CGFloat.leastNonzeroMagnitude
            audioView.isHidden = true
            updateSendButtonAppearance(sending: !inputField.actualText.isEmpty)
        } else {
            // Long or short bar visible.
            inputField.resignFirstResponder() // Otherwise it does not hide
            inputField.show(false)
            attachButton.isHidden = true
            audioDurationLabel.isHidden = false
            audioDurationLabel.show(true, height: 40)
            audioDurationLabel.sizeToFit()
            audioView.isHidden = false
            let buttonHeight = sendButton.constraints.first(where: { $0.firstAttribute == .height })?.constant ?? 48
            audioViewHeight.constant = max(40, buttonHeight + 8)
            wavePreviewImageView.isHidden = false
            if state == .short {
                wavePreviewLeading.constant = 8
                wavePreviewImageView.waveInsets = Constants.kWaveInsetsShort
            } else {
                wavePreviewLeading.constant = 40
                var insets = Constants.kWaveInsetsLong
                insets.right = max(insets.right, sendButtonSize.constant + 8)
                wavePreviewImageView.waveInsets = insets
            }
        }

        audioView.setNeedsLayout()
    }

    func audioBarState(_ state: AudioBarAction) {
        UIView.animate(withDuration: 0.15, delay: 0, options: UIView.AnimationOptions.curveEaseIn, animations: {
            self.resetRecordingGesture()
            if state == .lock {
                self.updateSendButtonAppearance(sending: true)
                self.showAudioBar(.longInitial)
            } else {
                self.showAudioBar(.hidden)
            }
            self.layoutIfNeeded()
        }, completion: nil)
    }

    func audioPlaybackPreview(_ data: Data, duration: TimeInterval) {
        wavePreviewImageView?.playbackPreview(data, duration: duration)
    }

    func audioUpdateAmplitude(amplitude: Float, atTime: TimeInterval) {
        wavePreviewImageView?.put(amplitude: amplitude, atTime: atTime)
    }

    func audioPlaybackAction(_ state: AudioBarAction) {
        switch state {
        case .playbackStart:
            playAudioButton.show(false)
            pauseAudioButton.show(true, dimension: Constants.kButtonSizeNormal)
            wavePreviewImageView.play()
        case .playbackReset:
            wavePreviewImageView.reset()
            playAudioButton.show(true, dimension: Constants.kButtonSizeNormal)
            pauseAudioButton.show(false)
        case .playbackPause:
            wavePreviewImageView.pause(rewind: false)
            playAudioButton.show(true, dimension: Constants.kButtonSizeNormal)
            pauseAudioButton.show(false)
        default:
            break
        }
    }
}

extension SendMessageBar: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        delegate?.sendMessageBar(textChangedTo: textView.text)
        updateSendButtonAppearance(sending: !inputField.actualText.isEmpty)
        resizeInputField()
    }
}

private final class ClawAttachmentSheetController: UIViewController {
    private let onSelect: (MessageAttachmentAction) -> Void
    private let dimControl = UIControl()
    private let panel = UIView()

    init(onSelect: @escaping (MessageAttachmentAction) -> Void) {
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.layoutIfNeeded()
        panel.transform = CGAffineTransform(translationX: 0, y: panel.bounds.height)
        dimControl.alpha = 0
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.panel.transform = .identity
            self.dimControl.alpha = 1
        }
    }

    private func configureView() {
        view.backgroundColor = .clear

        dimControl.translatesAutoresizingMaskIntoConstraints = false
        dimControl.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        dimControl.accessibilityLabel = NSLocalizedString("Cancel", comment: "Cancel action")
        dimControl.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(dimControl)

        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = ClawTheme.surface
        panel.layer.cornerRadius = 20
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.layer.cornerCurve = .continuous
        panel.clipsToBounds = true
        view.addSubview(panel)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = NSLocalizedString("Send content", comment: "Attachment sheet title")
        title.textColor = ClawTheme.ink
        title.font = ClawTheme.font(20, weight: .semibold, style: .headline)
        title.adjustsFontForContentSizeCategory = true

        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        ClawTheme.styleIconButton(close, symbolName: "xmark", pointSize: ClawTheme.iconSmall,
                                  tintColor: ClawTheme.muted)
        close.accessibilityLabel = NSLocalizedString("Cancel", comment: "Cancel action")
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        header.addSubview(close)
        panel.addSubview(header)

        let actions = UIStackView(arrangedSubviews: [
            makeTile(symbol: "photo.on.rectangle.angled",
                     title: NSLocalizedString("Choose photo or video", comment: "Media library action"),
                     action: .library),
            makeTile(symbol: "camera",
                     title: NSLocalizedString("Take photo or video", comment: "Camera action"),
                     action: .camera),
            makeTile(symbol: "doc",
                     title: NSLocalizedString("File", comment: "File attachment action"),
                     action: .file)
        ])
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.axis = .horizontal
        actions.alignment = .fill
        actions.distribution = .fillEqually
        actions.spacing = 12
        panel.addSubview(actions)

        NSLayoutConstraint.activate([
            dimControl.topAnchor.constraint(equalTo: view.topAnchor),
            dimControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimControl.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            header.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            title.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),
            title.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -8),
            title.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -8),
            close.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            close.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 48),
            close.heightAnchor.constraint(equalToConstant: 48),

            actions.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            actions.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            actions.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
            actions.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
            actions.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func makeTile(symbol: String, title: String,
                          action: MessageAttachmentAction) -> ClawAttachmentTileControl {
        let tile = ClawAttachmentTileControl(symbol: symbol, title: title, action: action)
        tile.addTarget(self, action: #selector(tileTapped(_:)), for: .touchUpInside)
        return tile
    }

    @objc private func closeTapped() {
        dismissSheet(completion: nil)
    }

    @objc private func tileTapped(_ sender: ClawAttachmentTileControl) {
        let action = sender.action
        let callback = onSelect
        dismissSheet { callback(action) }
    }

    private func dismissSheet(completion: (() -> Void)?) {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn], animations: {
            self.panel.transform = CGAffineTransform(translationX: 0, y: self.panel.bounds.height)
            self.dimControl.alpha = 0
        }) { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }
}

private final class ClawAttachmentTileControl: UIControl {
    let action: MessageAttachmentAction

    init(symbol: String, title: String, action: MessageAttachmentAction) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button

        let iconFrame = UIView()
        iconFrame.translatesAutoresizingMaskIntoConstraints = false
        iconFrame.backgroundColor = ClawTheme.surfaceMuted
        iconFrame.layer.cornerRadius = 16
        iconFrame.layer.cornerCurve = .continuous
        iconFrame.isUserInteractionEnabled = false

        let icon = UIImageView(image: ClawTheme.symbol(symbol, pointSize: ClawTheme.iconStandard, weight: .regular))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = action == .library ? ClawTheme.primary : ClawTheme.ink
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        iconFrame.addSubview(icon)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.textColor = ClawTheme.ink
        label.font = ClawTheme.font(13, weight: .medium, style: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 2
        label.isUserInteractionEnabled = false

        addSubview(iconFrame)
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
            iconFrame.topAnchor.constraint(equalTo: topAnchor),
            iconFrame.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconFrame.widthAnchor.constraint(equalToConstant: 56),
            iconFrame.heightAnchor.constraint(equalToConstant: 56),
            icon.centerXAnchor.constraint(equalTo: iconFrame.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconFrame.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            label.topAnchor.constraint(equalTo: iconFrame.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.alpha = self.isHighlighted ? 0.58 : 1
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }
}
