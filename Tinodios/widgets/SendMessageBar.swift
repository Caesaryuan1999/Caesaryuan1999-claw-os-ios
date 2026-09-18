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
    // Keep gesture coordinates in the same window while the accessory grows.
    private weak var recordingGestureWindow: UIWindow?
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
    @IBOutlet weak var stopAudioRecordingButton: UIButton!
    @IBOutlet weak var playAudioButton: UIButton!
    @IBOutlet weak var pauseAudioButton: UIButton!

    @IBOutlet weak var audioDurationLabel: UILabel!
    @IBOutlet weak var audioViewHeight: NSLayoutConstraint!
    @IBOutlet weak var wavePreviewImageView: WaveImageView!
    @IBOutlet weak var voiceScrollView: UIScrollView!
    @IBOutlet weak var voiceStackView: UIStackView!
    @IBOutlet weak var voiceDescriptionLabel: UILabel!
    @IBOutlet weak var voiceSendButton: UIButton!
    @IBOutlet weak var voiceGestureSpacer: UIView!

    // MARK: Properties
    private var audioLocked: Bool = false
    private var displayedAudioState: AudioBarState = .hidden
    private var recordedDuration: TimeInterval = 0
    private var playbackTime: TimeInterval = 0
    private var previewWasInterrupted = false
    private var playbackIsPaused = false
    private var lastVoiceAnnouncement: String?
    var onVoicePresentationChanged: ((Bool) -> Void)?
    var onVoiceHeightChanged: (() -> Void)?
    var voicePanelMaximumHeight: CGFloat = 420 {
        didSet {
            if abs(oldValue - voicePanelMaximumHeight) > 0.5 { setNeedsLayout() }
        }
    }

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

    @IBAction func sendRecording(_ sender: Any) {
        self.delegate?.sendMessageBar(recordAudio: .stopAndSend)
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
            guard let gestureWindow = window else { return }
            recordingGestureWindow = gestureWindow
            let loc = sender.location(in: gestureWindow)
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
            guard let gestureWindow = recordingGestureWindow, window === gestureWindow else { return }
            // Constrain movements to either strictly horizontal or strictly vertical.
            let loc = sender.location(in: gestureWindow)
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
        configureVoicePresentation()

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
            sendButton.accessibilityHint = NSLocalizedString("按住录音，松开发送；左滑取消，上滑锁定录音", comment: "Record gesture")
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
    }

    private func resizeInputField() {
        guard audioView.isHidden else { return }
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
        guard inputField != nil, voiceStackView != nil else { return }
        inputField.layer.borderColor = ClawTheme.border.cgColor
        configureVoicePresentation()
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            inputField.font = ClawTheme.font(16)
            if audioView.isHidden {
                updateSendButtonAppearance(sending: !inputField.actualText.isEmpty)
                resizeInputField()
            }
            setNeedsLayout()
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
        recordedDuration = 0
        playbackTime = 0
        previewWasInterrupted = false
        playbackIsPaused = false
        recordingStarted = true
        showAudioBar(.short)
        updateSendButtonAppearance(sending: false, recording: true)
        // The panel describes both gestures. Keep the original gesture view alive.
        verticalSliderView.isHidden = true
        horizontalSliderView.isHidden = true
        updateVoiceCopy(announce: true)
        layoutIfNeeded()
    }

    func recordingDidStop() {
        recordingStarted = false
        audioLocked = true
        resetRecordingGesture()
        updateSendButtonAppearance(sending: true)
        showAudioBar(.longPaused)
        updateVoiceCopy(announce: true)
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

    // Presentation only. Recorder/player callbacks determine every state.
    func showAudioBar(_ state: AudioBarState) {
        let wasVisible = displayedAudioState != .hidden
        displayedAudioState = state
        stopAudioRecordingButton.isHidden = state != .longInitial
        voiceSendButton.isHidden = state == .hidden || state == .short
        playAudioButton.isHidden = state != .longPaused
        pauseAudioButton.isHidden = state != .longPlayback
        deleteAudioButton.isHidden = state == .hidden
        voiceGestureSpacer.isHidden = state != .short
        sendButton.isHidden = state != .hidden && state != .short
        if state == .hidden {
            inputField.show(true, height: Constants.kInitialInputFieldHeight)
            attachButton.isHidden = false
            wavePreviewImageView.pause(rewind: false)
            wavePreviewImageView.reset()
            audioViewHeight.constant = CGFloat.leastNonzeroMagnitude
            audioView.isHidden = true
            recordingGestureWindow = nil
            recordedDuration = 0
            playbackTime = 0
            previewWasInterrupted = false
            playbackIsPaused = false
            lastVoiceAnnouncement = nil
            updateSendButtonAppearance(sending: !inputField.actualText.isEmpty)
            resizeInputField()
        } else {
            inputField.resignFirstResponder()
            inputField.show(false)
            attachButton.isHidden = true
            audioView.isHidden = false
            if !wasVisible { voiceScrollView.setContentOffset(.zero, animated: false) }
            if state == .longInitial {
                ClawTheme.styleSecondaryButton(voiceSendButton)
            } else {
                ClawTheme.stylePrimaryButton(voiceSendButton)
            }
            updateVoiceCopy()
        }
        if wasVisible != (state != .hidden) { onVoicePresentationChanged?(state != .hidden) }
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    func audioBarState(_ state: AudioBarAction) {
        UIView.animate(withDuration: 0.15, delay: 0, options: UIView.AnimationOptions.curveEaseIn, animations: {
            self.resetRecordingGesture()
            if state == .lock {
                self.updateSendButtonAppearance(sending: true)
                self.showAudioBar(.longInitial)
                self.updateVoiceCopy(announce: true)
            } else {
                self.showAudioBar(.hidden)
            }
            self.layoutIfNeeded()
        }, completion: nil)
    }

    func audioPlaybackPreview(_ data: Data, duration: TimeInterval) {
        recordedDuration = max(0, duration)
        playbackTime = 0
        wavePreviewImageView?.playbackPreview(data, duration: duration)
        // Refresh the actual samples immediately, before playback begins.
        wavePreviewImageView?.waveInsets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        updateVoiceCopy()
    }

    func audioUpdateAmplitude(amplitude: Float, atTime: TimeInterval) {
        wavePreviewImageView?.put(amplitude: amplitude, atTime: atTime)
        recordedDuration = max(0, atTime)
        updateVoiceCopy()
    }

    func audioPlaybackTime(_ time: TimeInterval) {
        playbackTime = min(recordedDuration, max(0, time))
        updateVoiceCopy()
    }

    func showInterruptedRecordingPreview() {
        guard displayedAudioState == .longPaused else { return }
        previewWasInterrupted = true
        updateVoiceCopy(announce: true)
    }

    func audioPlaybackAction(_ state: AudioBarAction) {
        switch state {
        case .playbackStart:
            playbackIsPaused = false
            previewWasInterrupted = false
            wavePreviewImageView.play()
        case .playbackReset:
            playbackIsPaused = false
            playbackTime = 0
            wavePreviewImageView.pause(rewind: true)
        case .playbackPause:
            playbackIsPaused = true
            wavePreviewImageView.pause(rewind: false)
        default:
            break
        }
        updateVoiceCopy(announce: true)
    }

    private func configureVoicePresentation() {
        audioView.backgroundColor = ClawTheme.surface
        audioView.layer.cornerRadius = 20
        audioView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        audioView.layer.cornerCurve = .continuous
        audioView.clipsToBounds = true
        audioDurationLabel.font = ClawTheme.font(20, weight: .semibold, style: .headline)
        audioDurationLabel.textColor = ClawTheme.ink
        audioDurationLabel.adjustsFontForContentSizeCategory = true
        audioDurationLabel.accessibilityTraits.insert(.header)
        audioDurationLabel.accessibilityIdentifier = "claw.voice.status"
        voiceDescriptionLabel.font = ClawTheme.font(14, style: .subheadline)
        voiceDescriptionLabel.textColor = ClawTheme.muted
        voiceDescriptionLabel.adjustsFontForContentSizeCategory = true
        voiceScrollView.keyboardDismissMode = .none
        wavePreviewImageView.waveInsets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        wavePreviewImageView.isAccessibilityElement = false
        let buttons = [stopAudioRecordingButton!, voiceSendButton!, playAudioButton!,
                       pauseAudioButton!, deleteAudioButton!]
        for button in buttons {
            ClawTheme.styleSecondaryButton(button)
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.textAlignment = .center
            button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
            button.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        ClawTheme.stylePrimaryButton(stopAudioRecordingButton)
        if displayedAudioState != .longInitial { ClawTheme.stylePrimaryButton(voiceSendButton) }
        deleteAudioButton.setTitleColor(ClawTheme.danger, for: .normal)
        stopAudioRecordingButton.accessibilityIdentifier = "claw.voice.stop"
        voiceSendButton.accessibilityIdentifier = "claw.voice.send"
        playAudioButton.accessibilityIdentifier = "claw.voice.listen"
        pauseAudioButton.accessibilityIdentifier = "claw.voice.pause"
        deleteAudioButton.accessibilityIdentifier = "claw.voice.discard"
        voiceSendButton.accessibilityHint = "发送本次录音，发送结果以消息中的状态为准"
        deleteAudioButton.accessibilityHint = "仅放弃本次尚未发送的录音"
        stopAudioRecordingButton.accessibilityHint = "结束采集并保留录音，可先试听再发送"
    }

    private func updateVoiceCopy(announce: Bool = false) {
        guard displayedAudioState != .hidden else { return }
        let heading: String
        let detail: String
        switch displayedAudioState {
        case .short:
            heading = "正在录音"
            detail = "持续按住录音按钮，松开发送。左滑取消，上滑锁定录音。"
        case .longInitial:
            heading = "正在录音"
            detail = "已锁定录音，可以松开手指。停止后可先试听，也可以直接发送。"
        case .longPlayback:
            heading = "正在试听"
            detail = "正在试听本次录音，语音尚未发送。可以暂停，也可以确认后发送。"
        case .longPaused:
            heading = previewWasInterrupted ? "录音已暂停" : (playbackIsPaused ? "试听已暂停" : "录音已完成")
            detail = previewWasInterrupted ? "录音已暂停，请试听后再发送。语音尚未发送，不会自动继续录音。"
                : "语音尚未发送。你可以先试听，确认后再发送。"
        case .hidden: return
        }
        let showPlaybackTime = !previewWasInterrupted && (displayedAudioState == .longPlayback || playbackIsPaused)
        let time = showPlaybackTime
            ? "\(playbackTime.asDurationString) / \(recordedDuration.asDurationString)"
            : recordedDuration.asDurationString
        let title = "\(heading) · \(time)"
        if audioDurationLabel.text != title { audioDurationLabel.text = title }
        if voiceDescriptionLabel.text != detail { voiceDescriptionLabel.text = detail; setNeedsLayout() }
        deleteAudioButton.setTitle(recordingStarted ? "取消录音" : "放弃录音", for: .normal)
        playAudioButton.setTitle(playbackIsPaused ? "继续试听" : "试听", for: .normal)
        // Announce transitions, never the high frequency meter/time updates.
        let announcement = heading + detail
        if announce && lastVoiceAnnouncement != announcement {
            lastVoiceAnnouncement = announcement
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: heading + "。" + detail)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard audioView != nil, !audioView.isHidden, bounds.width > 0 else { return }
        let width = max(1, audioView.bounds.width - 40)
        let fitting = voiceStackView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let height = min(max(52, voicePanelMaximumHeight), ceil(fitting.height) + 40)
        voiceScrollView.isScrollEnabled = fitting.height + 40 > height + 0.5
        if abs(audioViewHeight.constant - height) > 0.5 {
            audioViewHeight.constant = height
            invalidateIntrinsicContentSize()
            onVoiceHeightChanged?()
        }
    }
}

extension SendMessageBar: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        delegate?.sendMessageBar(textChangedTo: textView.text)
        if audioView.isHidden { updateSendButtonAppearance(sending: !inputField.actualText.isEmpty) }
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
