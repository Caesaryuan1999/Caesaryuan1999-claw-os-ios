//
//  MessageCell.swift
//
//  Copyright © 2019-2025 Tinode. All rights reserved.
//

import UIKit
import TinodeSDK

/// Presentation of one already-authorized AU. Playback and progress are supplied
/// by the existing owned player; this view never opens a source or runs a timer.
final class ClawVoiceBubbleView: UIView {
    let durationLabel = UILabel()
    let stateImage = UIImageView()
    let progressTrack = UIView()
    let progressFill = UIView()
    private let activity = UIActivityIndicatorView(style: .medium)
    private(set) var durationMilliseconds: Int?
    private(set) var outgoing = false
    private(set) var playbackState: ClawAudioPlayback.State = .idle
    private(set) var playbackPosition: Double = 0
    var activate: (() -> Void)?

    static func durationText(_ milliseconds: Int?) -> String {
        guard let milliseconds = milliseconds, milliseconds > 0 else { return "-:--" }
        return "\(milliseconds / 1000)″"
    }

    static func durationFont(_ traits: UITraitCollection) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 16, weight: .medium), compatibleWith: traits)
    }

    static func bodySize(duration: Int?, maximum: CGFloat, traits: UITraitCollection) -> CGSize {
        guard maximum.isFinite, maximum > 0 else { return .zero }
        let text = durationText(duration) as NSString
        let font = durationFont(traits)
        // Two 12pt insets, the nominal 16pt wave, and a 6pt gap. The original
        // wave's stroke extends 1pt outside its nominal frame on all sides.
        let fixed: CGFloat = 46
        let natural = ceil(text.size(withAttributes: [.font: font]).width) + fixed
        let width = min(maximum, max(natural,
            MessageBubbleLayoutPolicy.voiceWidth(durationMs: duration, maxWidth: maximum)))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        let textHeight = text.boundingRect(with: CGSize(width: max(1, width - fixed), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph], context: nil).height
        return CGSize(width: width, height: max(48, ceil(textHeight) + 24))
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        durationLabel.numberOfLines = 0
        durationLabel.adjustsFontForContentSizeCategory = true
        durationLabel.lineBreakMode = .byCharWrapping
        durationLabel.isAccessibilityElement = false
        stateImage.contentMode = .scaleAspectFit
        stateImage.isAccessibilityElement = false
        activity.isAccessibilityElement = false
        [durationLabel, stateImage, progressTrack, progressFill, activity].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        progressTrack.layer.cornerRadius = 1
        progressFill.layer.cornerRadius = 1
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(duration: Int?, outgoing: Bool) {
        durationMilliseconds = duration
        self.outgoing = outgoing
        durationLabel.text = Self.durationText(duration)
        display(state: .idle, position: 0)
    }

    func display(state: ClawAudioPlayback.State, position: Double) {
        playbackState = state
        playbackPosition = position.isFinite ? min(1, max(0, position)) : 0
        durationLabel.font = Self.durationFont(traitCollection)
        durationLabel.textColor = ClawTheme.ink
        stateImage.tintColor = state == .failed ? ClawTheme.danger : ClawTheme.ink
        stateImage.transform = .identity
        switch state {
        case .paused: stateImage.image = ClawTheme.symbol("pause", pointSize: 18)
        case .failed: stateImage.image = ClawTheme.symbol("exclamationmark", pointSize: 18)
        default:
            stateImage.image = UIImage(named: "claw-voice-wave")?.withRenderingMode(.alwaysTemplate)
            if !outgoing { stateImage.transform = CGAffineTransform(scaleX: -1, y: 1) }
        }
        stateImage.isHidden = state == .preparing
        activity.color = ClawTheme.ink
        if state == .preparing { activity.startAnimating() } else { activity.stopAnimating() }
        let showProgress = state == .playing || state == .paused
        progressTrack.isHidden = !showProgress
        progressFill.isHidden = !showProgress
        progressTrack.backgroundColor = ClawTheme.border
        progressFill.backgroundColor = ClawTheme.primary
        let duration = durationMilliseconds.flatMap { $0 > 0 ? "\($0 / 1000)秒" : nil } ?? "时长未知"
        accessibilityLabel = "语音，\(duration)"
        switch state {
        case .playing: accessibilityValue = "正在播放"; accessibilityHint = "轻点暂停"
        case .paused: accessibilityValue = "已暂停"; accessibilityHint = "轻点继续播放"
        case .preparing: accessibilityValue = "正在加载语音"; accessibilityHint = nil
        case .failed: accessibilityValue = "暂时无法播放"; accessibilityHint = "轻点重试或查看恢复选项"
        default: accessibilityValue = nil; accessibilityHint = "轻点播放"
        }
        setNeedsLayout()
    }

    override func accessibilityActivate() -> Bool {
        guard !isHidden, window != nil, let activate = activate else { return false }
        activate()
        return true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        durationLabel.font = Self.durationFont(traitCollection)
        let labelMaximum = max(1, bounds.width - 46)
        let size = durationLabel.sizeThatFits(CGSize(width: labelMaximum, height: .greatestFiniteMagnitude))
        let width = min(labelMaximum, ceil(size.width))
        let nominalX = outgoing ? bounds.width - 28 : 12
        stateImage.frame = CGRect(x: nominalX - 1, y: (bounds.height - 20) / 2 - 1, width: 18, height: 22)
        activity.center = CGPoint(x: nominalX + 8, y: bounds.midY)
        durationLabel.frame = CGRect(x: outgoing ? nominalX - 6 - width : 34,
                                     y: (bounds.height - ceil(size.height)) / 2,
                                     width: width, height: ceil(size.height))
        progressTrack.frame = CGRect(x: 12, y: bounds.height - 5, width: max(0, bounds.width - 24), height: 2)
        progressFill.frame = CGRect(x: 12, y: bounds.height - 5,
                                    width: progressTrack.bounds.width * CGFloat(playbackPosition), height: 2)
    }
}

/// State overlay in the attachment's fixed canvas. Large text scrolls inside
/// that canvas instead of changing a received message's height after download.
final class ClawImageStateView: UIView {
    let status = UILabel()
    let retryButton = UIButton(type: .system)
    let badge = UILabel()
    private let scroll = UIScrollView()
    var activate: (() -> Bool)?
    private var state: EntityTextAttachment.ImageState = .loading

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 12; clipsToBounds = true
        status.numberOfLines = 0; status.textAlignment = .center
        retryButton.setTitle("重新加载", for: .normal)
        retryButton.titleLabel?.numberOfLines = 0
        retryButton.titleLabel?.textAlignment = .center
        retryButton.layer.cornerRadius = 10
        retryButton.addTarget(self, action: #selector(retryPressed), for: .touchUpInside)
        badge.text = "长图"; badge.textAlignment = .center; badge.numberOfLines = 0
        badge.layer.cornerRadius = 4; badge.clipsToBounds = true
        scroll.addSubview(status); scroll.addSubview(retryButton)
        addSubview(scroll); addSubview(badge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func display(_ attachment: EntityTextAttachment) {
        state = attachment.imageState
        let ready = state == .ready
        backgroundColor = ready ? .clear : ClawTheme.surface.withAlphaComponent(0.94)
        scroll.isHidden = ready
        badge.isHidden = !ready || attachment.imageCanvas?.mode != .longTop
        status.text = state == .loading ? "正在加载图片…" : state == .unavailable ? "图片当前不可用" : "图片未加载"
        status.textColor = ClawTheme.muted
        status.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16), compatibleWith: traitCollection)
        retryButton.isHidden = state != .failed || !attachment.canRetryImage
        retryButton.setTitleColor(ClawTheme.primary, for: .normal); retryButton.backgroundColor = .clear
        retryButton.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16, weight: .semibold), compatibleWith: traitCollection)
        badge.textColor = .white; badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badge.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12), compatibleWith: traitCollection)
        isAccessibilityElement = ready
        accessibilityTraits = [.image, .button]
        accessibilityLabel = attachment.imageCanvas?.mode == .longTop ? "长图，查看原图" : "图片，查看原图"
        badge.isAccessibilityElement = false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let width = max(0, bounds.width - 16)
        retryButton.setTitle("重新加载", for: .normal)
        retryButton.accessibilityLabel = "重新加载"
        retryButton.accessibilityHint = "图片未加载"
        let natural = retryButton.titleLabel?.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)) ?? .zero
        var buttonWidth = min(width, max(112, ceil(natural.width) + 24))
        var buttonHeight = max(48, ceil(retryButton.titleLabel?.sizeThatFits(CGSize(width: max(1, buttonWidth - 24), height: .greatestFiniteMagnitude)).height ?? 0) + 16)
        // Preserve the system font and a readable action in the fixed canvas.
        // Accessibility retains the complete action and reason.
        if buttonHeight + 16 > bounds.height {
            retryButton.setTitle("重试", for: .normal)
            let short = retryButton.titleLabel?.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)) ?? .zero
            buttonWidth = min(width, max(112, ceil(short.width) + 24))
            buttonHeight = max(48, ceil(retryButton.titleLabel?.sizeThatFits(CGSize(width: max(1, buttonWidth - 24), height: .greatestFiniteMagnitude)).height ?? 0) + 16)
        }
        let labelHeight = ceil(status.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        status.isHidden = !retryButton.isHidden && labelHeight + 12 + buttonHeight + 16 > bounds.height
        let shownLabelHeight = status.isHidden ? 0 : labelHeight
        let gap: CGFloat = status.isHidden || retryButton.isHidden ? 0 : 12
        let height = shownLabelHeight + (retryButton.isHidden ? 0 : gap + buttonHeight)
        let top = max(8, (bounds.height - height) / 2)
        status.frame = CGRect(x: 8, y: top, width: width, height: labelHeight)
        retryButton.frame = CGRect(x: (bounds.width - buttonWidth) / 2, y: top + shownLabelHeight + gap, width: buttonWidth, height: buttonHeight)
        scroll.contentSize = CGSize(width: bounds.width, height: max(bounds.height, top + height + 8))
        let badgeSize = badge.sizeThatFits(CGSize(width: max(1, bounds.width - 28), height: .greatestFiniteMagnitude))
        let badgeWidth = min(bounds.width, ceil(badgeSize.width) + 12), badgeHeight = ceil(badgeSize.height) + 8
        badge.frame = CGRect(x: max(0, bounds.width - badgeWidth - 8), y: max(0, bounds.height - badgeHeight - 8), width: badgeWidth, height: badgeHeight)
    }

    // Ready content uses the original collection-view/glyph tap route.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        state == .ready ? nil : super.hitTest(point, with: event)
    }
    override func accessibilityActivate() -> Bool { activate?() ?? false }
    @objc private func retryPressed() { _ = activate?() }
}

/// A protocol used to detect events in the chat message.
protocol MessageCellDelegate: AnyObject {
    /// Long tap anywhere in massage cell.
    func didLongTap(in cell: MessageCell)
    /// Tap on the message bubble.
    func didTapMessage(in cell: MessageCell)
    /// Tap on message content.
    func didTapContent(in cell: MessageCell, url: URL?)
    /// Tap on avatar.
    func didTapAvatar(in cell: MessageCell)
    /// Tap outside of message.
    func didTapOutsideContent(in cell: MessageCell)
    /// Clicked on cancel upload.
    func didTapCancelUpload(in cell: MessageCell)
    /// Actual state of this cell's owned ordinary-AU attempt.
    func didChangeAudio(in cell: MessageCell, playback: ClawAudioPlayback)
    func isImageCurrent(in cell: MessageCell, attachment: EntityTextAttachment) -> Bool
}

extension MessageCellDelegate {
    func isImageCurrent(in cell: MessageCell, attachment: EntityTextAttachment) -> Bool { false }
}

// Optional date, avatar, sender name, message bubble: content, delivery marker, timestamp.
class MessageCell: UICollectionViewCell {

    var seqId: Int = 0
    var isDeleted: Bool = false
    var timeStamp: Date? = nil

    // Player for audio messages.
    var audioPlayback: ClawAudioPlayback?
    // Invalidates references even when a recycled cell later has the same seq.
    var audioBinding = UUID()
    // Which entity is configured in the player: entity key.
    var mediaEntityKey: Int?
    private(set) var compactVoiceEntityKey: Int?
    let voiceBubble = ClawVoiceBubbleView()
    let voiceTail = UIImageView()
    private var bulkSelectionEnabled = false
    private var bulkMessageSelected = false
    private var imageConsumer = UUID()
    private var imageStates = [UUID: (attachment: EntityTextAttachment, view: ClawImageStateView)]()

    // MARK: - Initializers

    public override init(frame: CGRect) {
        super.init(frame: frame)
        applyThemeBackground()
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupSubviews()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        applyThemeBackground()
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        setupSubviews()
    }

    func applyThemeBackground() {
        backgroundColor = ClawTheme.background
        contentView.backgroundColor = .clear
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle { applyThemeBackground() }
        setNeedsLayout()
        if compactVoiceEntityKey != nil {
            applyCompactVoiceAppearance()
            voiceBubble.display(state: voiceBubble.playbackState, position: voiceBubble.playbackPosition)
            updateCompactVoiceSelection()
        }
    }

    deinit {
        audioPlayback?.retire()
        for item in imageStates.values { item.attachment.unbindImageConsumer(imageConsumer) }
    }

    /// The image view with the avatar.
    var avatarView: RoundImageView = RoundImageView()

    /// The UIImageView with background being the bubble,
    /// holds the message's content view.
    var containerView: UIImageView = {
        let view = UIImageView()
        view.clipsToBounds = true
        view.layer.masksToBounds = true
        return view
    }()

    /// The message content
    var content: RichTextView = {
        let content = RichTextView()
        content.isUserInteractionEnabled = true
        content.contentInsetAdjustmentBehavior = .never

        content.isScrollEnabled = false
        content.isUserInteractionEnabled = true
        content.isEditable = false
        content.isSelectable = true

        return content
    }()

    /// The label above the messageBubble which holds the date of conversation.
    var newDateLabel: PaddedLabel = {
        let label = PaddedLabel()
        label.textAlignment = .center
        return label
    }()

    /// The label under the messageBubble: sender's name in group topics.
    var senderNameLabel: PaddedLabel = {
        let label = PaddedLabel()
        label.textAlignment = .natural
        return label
    }()

    /// Delivery marker.
    var deliveryMarker: UIImageView = {
        let view = UIImageView()
        view.contentMode = UIView.ContentMode.scaleAspectFit
        return view
    }()

    /// Message timestamp.
    var timestampLabel: PaddedLabel = {
        let label = PaddedLabel()
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        return label
    }()

    /// Edited marker.
    var editedMarker: PaddedLabel = {
        let label = PaddedLabel()
        label.font = UIFont.preferredFont(forTextStyle: .caption2).withTraits(traits: .traitItalic)
        label.textAlignment = .right
        label.adjustsFontSizeToFitWidth = true
        return label
    }()

    var progressView = ProgressView()

    private let bulkSelectionBadge: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1.5
        view.layer.borderColor = ClawTheme.border.cgColor
        view.backgroundColor = ClawTheme.surface
        view.isHidden = true
        return view
    }()

    private let bulkSelectionCheckmark: UIImageView = {
        let view = UIImageView(image: ClawTheme.symbol("checkmark", pointSize: 12, weight: .bold))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = .white
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        return view
    }()

    /// The `MessageCellDelegate` for the cell.
    weak var delegate: MessageCellDelegate?

    func setupSubviews() {
        contentView.addSubview(newDateLabel)
        contentView.addSubview(senderNameLabel)
        voiceTail.isHidden = true
        voiceTail.isAccessibilityElement = false
        voiceTail.image = UIImage(named: "claw-voice-tail")?.withRenderingMode(.alwaysTemplate)
        contentView.addSubview(voiceTail)
        contentView.addSubview(containerView)
        containerView.addSubview(content)
        voiceBubble.isHidden = true
        voiceBubble.activate = { [weak self] in
            guard let self = self, self.compactVoiceEntityKey != nil else { return }
            self.delegate?.didTapMessage(in: self)
        }
        contentView.addSubview(voiceBubble)
        // Metadata belongs to the cell, not the colored message bubble.
        contentView.addSubview(timestampLabel)
        contentView.addSubview(deliveryMarker)
        contentView.addSubview(editedMarker)
        contentView.addSubview(avatarView)
        contentView.addSubview(bulkSelectionBadge)
        bulkSelectionBadge.addSubview(bulkSelectionCheckmark)
        NSLayoutConstraint.activate([
            bulkSelectionBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            bulkSelectionBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            bulkSelectionBadge.widthAnchor.constraint(equalToConstant: 24),
            bulkSelectionBadge.heightAnchor.constraint(equalToConstant: 24),
            bulkSelectionCheckmark.centerXAnchor.constraint(equalTo: bulkSelectionBadge.centerXAnchor),
            bulkSelectionCheckmark.centerYAnchor.constraint(equalTo: bulkSelectionBadge.centerYAnchor),
            bulkSelectionCheckmark.widthAnchor.constraint(equalToConstant: 14),
            bulkSelectionCheckmark.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    func setBulkSelectionMode(_ enabled: Bool, selected: Bool) {
        bulkSelectionEnabled = enabled
        bulkMessageSelected = enabled && selected
        bulkSelectionBadge.isHidden = !enabled
        bulkSelectionCheckmark.isHidden = !selected
        bulkSelectionBadge.backgroundColor = selected ? ClawTheme.primary : ClawTheme.surface
        bulkSelectionBadge.layer.borderColor = selected ? ClawTheme.primary.cgColor : ClawTheme.border.cgColor
        guard compactVoiceEntityKey != nil else { return }
        voiceBubble.display(state: voiceBubble.playbackState, position: voiceBubble.playbackPosition)
        updateCompactVoiceSelection()
    }

    func configureCompactVoice(key: Int?, duration: Int?, outgoing: Bool) {
        compactVoiceEntityKey = key
        let compact = key != nil
        voiceBubble.isHidden = !compact
        voiceTail.isHidden = !compact
        content.isHidden = compact
        content.accessibilityElementsHidden = compact
        guard compact else { voiceBubble.display(state: .idle, position: 0); return }
        voiceBubble.configure(duration: duration, outgoing: outgoing)
        applyCompactVoiceAppearance()
        if let playback = audioPlayback, playback.entityKey == key, playback.isCurrent {
            voiceBubble.display(state: playback.state, position: playback.position)
        }
        updateCompactVoiceSelection()
        setNeedsLayout()
    }

    func displayCompactVoice(playback: ClawAudioPlayback) {
        guard compactVoiceEntityKey == playback.entityKey, audioPlayback === playback,
              mediaEntityKey == playback.entityKey,
              playback.state == .retired || playback.isCurrent else { return }
        voiceBubble.display(state: playback.state, position: playback.position)
        updateCompactVoiceSelection()
    }

    private func updateCompactVoiceSelection() {
        voiceBubble.accessibilityTraits = bulkMessageSelected ? [.button, .selected] : .button
        if bulkSelectionEnabled {
            voiceBubble.accessibilityHint = bulkMessageSelected ? "轻点取消选择" : "轻点选择此消息"
        }
    }

    private func applyCompactVoiceAppearance() {
        containerView.backgroundColor = voiceBubble.outgoing ? ClawTheme.brandSoft : ClawTheme.surface
        containerView.layer.mask = nil
        containerView.layer.cornerRadius = 8
        voiceTail.tintColor = containerView.backgroundColor
        voiceTail.transform = voiceBubble.outgoing ? .identity : CGAffineTransform(scaleX: -1, y: 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutImageStates()
        guard compactVoiceEntityKey != nil else { return }
        voiceBubble.frame = containerView.frame
        // Original six-point tail overlaps the body by one point: five points
        // extend outside. This matches the Figma export without cropping it.
        voiceTail.frame = CGRect(x: voiceBubble.outgoing ? containerView.frame.maxX - 1 : containerView.frame.minX - 5,
                                 y: containerView.frame.midY - 6, width: 6, height: 12)
    }

    func showProgressBar() {
        containerView.addSubview(progressView)
        progressView.isHidden = false
        containerView.bringSubviewToFront(progressView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        clearImageStates()

        content.text = nil
        content.attributedText = nil
        newDateLabel.text = nil
        senderNameLabel.text = nil
        timestampLabel.text = nil
        editedMarker.text = nil
        deliveryMarker.image = nil
        avatarView.image = nil
        progressView.isHidden = true

        isDeleted = false
        configureCompactVoice(key: nil, duration: nil, outgoing: false)
        containerView.backgroundColor = nil
        containerView.layer.mask = nil
        containerView.layer.cornerRadius = 0
        containerView.layer.masksToBounds = false
        content.backgroundColor = nil

        stopAudio()
        audioBinding = UUID()
        seqId = 0
        mediaEntityKey = nil

        timeStamp = nil
        setBulkSelectionMode(false, selected: false)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { clearImageStates() } else { setNeedsLayout() }
    }

    func imageAttachment(binding: UUID) -> EntityTextAttachment? {
        var found: EntityTextAttachment?
        content.textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.textStorage.length)) { value, _, stop in
            if let attachment = value as? EntityTextAttachment, attachment.imageBinding == binding, attachment.imageCanvas != nil {
                found = attachment; stop.pointee = true
            }
        }
        return found
    }

    private func clearImageStates() {
        let previous = imageStates
        imageStates.removeAll()
        for item in previous.values {
            item.attachment.unbindImageConsumer(imageConsumer)
            item.view.removeFromSuperview()
        }
        imageConsumer = UUID()
    }

    private func layoutImageStates() {
        guard window != nil, !content.isHidden else { clearImageStates(); return }
        content.layoutManager.ensureLayout(for: content.textContainer)
        var seen = Set<UUID>()
        content.textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: content.textStorage.length)) { [weak self] value, range, _ in
            guard let self = self, let attachment = value as? EntityTextAttachment,
                  let canvas = attachment.imageCanvas else { return }
            let binding = attachment.imageBinding
            seen.insert(binding)
            let overlay = self.imageStates[binding]?.view ?? ClawImageStateView()
            // The legacy bubble UIImageView disables interaction. Keep the
            // explicit retry control as a sibling, without changing old taps.
            if overlay.superview == nil { self.contentView.addSubview(overlay) }
            self.imageStates[binding] = (attachment, overlay)
            let token = self.imageConsumer, sequence = self.seqId
            attachment.bindImageConsumer(token, isCurrent: { [weak self, weak attachment] in
                guard let self = self, let attachment = attachment, self.imageConsumer == token,
                      self.seqId == sequence, self.window != nil, !self.isDeleted,
                      self.imageAttachment(binding: binding) === attachment else { return false }
                return self.delegate?.isImageCurrent(in: self, attachment: attachment) == true
            }, changed: { [weak self, weak attachment, weak overlay] in
                guard let self = self, let attachment = attachment, let overlay = overlay,
                      self.imageConsumer == token, self.imageStates[binding]?.view === overlay else { return }
                overlay.display(attachment)
            })
            overlay.activate = { [weak self, weak attachment] in
                guard let self = self, let attachment = attachment, self.imageConsumer == token,
                      self.window != nil, self.imageAttachment(binding: binding) === attachment else { return false }
                if self.bulkSelectionEnabled { self.delegate?.didTapMessage(in: self); return true }
                guard attachment.imageConsumerIsCurrent, let url = attachment.imageActionURL else { return false }
                self.delegate?.didTapContent(in: self, url: url)
                return true
            }
            let glyphs = self.content.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let glyph = self.content.layoutManager.boundingRect(forGlyphRange: glyphs, in: self.content.textContainer)
            let rect = CGRect(x: glyph.minX, y: glyph.maxY - canvas.size.height, width: canvas.size.width, height: canvas.size.height)
            overlay.frame = self.content.convert(rect, to: self.contentView)
            overlay.display(attachment)
        }
        for binding in imageStates.keys.filter({ !seen.contains($0) }) {
            let item = imageStates.removeValue(forKey: binding)
            item?.attachment.unbindImageConsumer(imageConsumer)
            item?.view.removeFromSuperview()
        }
        if !progressView.isHidden { containerView.bringSubviewToFront(progressView) }
    }

    /// Handle tap gesture on contentView and its subviews.
    func handleTapGesture(_ gesture: UIGestureRecognizer) {
        if gesture.isKind(of: UILongPressGestureRecognizer.self) {
            delegate?.didLongTap(in: self)
            return
        }

        let touchLocation = gesture.location(in: self)

        switch true {
        case !progressView.isHidden && progressView.cancelButton.frame.contains(convert(touchLocation, to: progressView)):
            delegate?.didTapCancelUpload(in: self)
        case compactVoiceEntityKey != nil && containerView.frame.contains(touchLocation):
            delegate?.didTapMessage(in: self)
        case content.frame.contains(convert(touchLocation, to: containerView)):
            let url = content.getURLForTap(convert(touchLocation, to: content))
            delegate?.didTapContent(in: self, url: url)
        case containerView.frame.contains(touchLocation):
            delegate?.didTapMessage(in: self)
        case avatarView.frame.contains(touchLocation):
            delegate?.didTapAvatar(in: self)
        default:
            delegate?.didTapOutsideContent(in: self)
            break
        }
    }

    @objc func cancelUploadClicked(sender: UIButton!) {
        delegate?.didTapCancelUpload(in: self)
    }

    /// Handle long press gesture, return true when gestureRecognizer's touch point in `containerView`'s frame
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let touchPoint = gestureRecognizer.location(in: self)
        guard gestureRecognizer.isKind(of: UILongPressGestureRecognizer.self) else { return false }
        return containerView.frame.contains(touchPoint)
    }

    /// This is needed for the context menu to work correctly.
    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func resignFirstResponder() -> Bool {
        super.resignFirstResponder()
        return true
    }

    /// Highlights the cell by gradually changing its background color to a darker one and back.
    func highlightAnimated(withDuration duration: TimeInterval) {
        let halfDuration = 0.5 * duration
        UIView.animate(withDuration: halfDuration) {
            self.containerView.backgroundColor = self.containerView.backgroundColor?.darker()
        }
        UIView.animate(withDuration: halfDuration) {
            self.containerView.backgroundColor = self.containerView.backgroundColor?.lighter()
        }
    }
}
