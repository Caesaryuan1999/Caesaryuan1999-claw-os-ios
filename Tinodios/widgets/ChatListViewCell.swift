//
//  ChatListTableViewCell.swift
//
//  Copyright © 2019-2025 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK
import TinodiosDB

class ChatListViewCell: UITableViewCell {
    private static let kIconWidth: CGFloat = 18
    private static let kMessageStatusWidth: CGFloat = 14

    @IBOutlet weak var icon: AvatarWithOnlineIndicator!
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var subtitle: UILabel!
    @IBOutlet weak var unreadCount: UILabel!
    @IBOutlet weak var iconBlocked: UIImageView!
    @IBOutlet weak var iconMuted: UIImageView!
    @IBOutlet weak var iconBlockedWidth: NSLayoutConstraint!
    @IBOutlet weak var unreadCountWidth: NSLayoutConstraint!
    @IBOutlet weak var channelIndicator: UIImageView!
    @IBOutlet weak var channelIndicatorWidth: NSLayoutConstraint!
    @IBOutlet weak var iconMessageStatus: UIImageView!
    @IBOutlet weak var iconMessageStatusWidth: NSLayoutConstraint!
    @IBOutlet weak var badgeVerified: UIImageView!
    @IBOutlet weak var badgeVerifiedWidth: NSLayoutConstraint!
    @IBOutlet weak var badgeStaff: UIImageView!
    @IBOutlet weak var badgeStaffWidth: NSLayoutConstraint!
    @IBOutlet weak var badgeDanger: UIImageView!
    @IBOutlet weak var badgeDangerWidth: NSLayoutConstraint!

    private let messageTimeLabel = UILabel()
    private let cardView = UIView()
    private var premiumLayoutInstalled = false
    private let rowDivider = UIView()
    private var rowMetrics: [(NSLayoutConstraint, CGFloat, CGFloat)] = []
    private var titleRow: UIStackView!
    private var previewRow: UIStackView!
    private var timeRow: UIStackView!

    // Explicit opt-in: archive/blocked consumers retain their original card layout.
    var usesContinuousLayout = false {
        didSet { if premiumLayoutInstalled { applyRowLayout() } }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        installPremiumLayout()
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        title.font = ClawTheme.font(16, weight: .semibold)
        title.textColor = ClawTheme.ink
        subtitle.font = ClawTheme.font(13, style: .subheadline)
        subtitle.textColor = ClawTheme.muted
        icon.avatar.setFixedCornerRadius(16)
        unreadCount.backgroundColor = ClawTheme.primary
        unreadCount.textColor = ClawTheme.onBrand
        unreadCount.font = ClawTheme.font(12, weight: .semibold, style: .caption1)
        let labels: [UILabel] = [title, subtitle, messageTimeLabel, unreadCount]
        labels.forEach { $0.adjustsFontForContentSizeCategory = true }
        unreadCount.constraints.first(where: { $0.firstAttribute == .height })?.constant =
            max(24, ceil(unreadCount.font.lineHeight) + 8)
        unreadCount.layer.cornerRadius = 10
        unreadCount.layer.cornerCurve = .continuous
        unreadCount.clipsToBounds = true
        [iconBlocked, iconMuted, channelIndicator, iconMessageStatus,
         badgeVerified, badgeStaff, badgeDanger].forEach {
            $0?.contentMode = .scaleAspectFit
        }
        iconMuted.tintColor = ClawTheme.muted
        iconBlocked.tintColor = iconMuted.tintColor
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    private func installPremiumLayout() {
        guard !premiumLayoutInstalled else { return }
        premiumLayoutInstalled = true

        let legacyViews: [UIView] = [
            icon, title, subtitle, unreadCount, iconBlocked, iconMuted,
            channelIndicator, iconMessageStatus, badgeVerified, badgeStaff, badgeDanger
        ]
        let identifiers = Set(legacyViews.map { ObjectIdentifier($0) })
        let legacyConstraints = contentView.constraints.filter { constraint in
            let firstMatches = (constraint.firstItem as? UIView).map {
                identifiers.contains(ObjectIdentifier($0))
            } ?? false
            let secondMatches = (constraint.secondItem as? UIView).map {
                identifiers.contains(ObjectIdentifier($0))
            } ?? false
            return firstMatches || secondMatches
        }
        NSLayoutConstraint.deactivate(legacyConstraints)

        icon.translatesAutoresizingMaskIntoConstraints = false
        title.numberOfLines = 2
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        subtitle.numberOfLines = 2
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.setContentHuggingPriority(.defaultLow, for: .horizontal)

        messageTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        messageTimeLabel.font = ClawTheme.font(12, style: .caption1)
        messageTimeLabel.textColor = ClawTheme.muted
        messageTimeLabel.textAlignment = .right
        messageTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        messageTimeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleContent = UIStackView(arrangedSubviews: [
            title, channelIndicator, badgeVerified, badgeStaff, badgeDanger
        ])
        titleContent.alignment = .center
        titleContent.spacing = 4
        timeRow = UIStackView(arrangedSubviews: [messageTimeLabel])
        timeRow.alignment = .center
        timeRow.spacing = 8
        titleRow = UIStackView(arrangedSubviews: [titleContent, timeRow])
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 4

        previewRow = UIStackView(arrangedSubviews: [
            iconMessageStatus, subtitle, iconMuted, iconBlocked, unreadCount
        ])
        previewRow.translatesAutoresizingMaskIntoConstraints = false
        previewRow.axis = .horizontal
        previewRow.alignment = .center
        previewRow.spacing = 4

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.isUserInteractionEnabled = false
        cardView.backgroundColor = ClawTheme.surface
        cardView.layer.cornerRadius = ClawTheme.cardRadius
        cardView.layer.cornerCurve = .continuous
        contentView.insertSubview(cardView, at: 0)

        let textRows = UIStackView(arrangedSubviews: [titleRow, previewRow])
        textRows.translatesAutoresizingMaskIntoConstraints = false
        textRows.axis = .vertical
        textRows.spacing = 4
        contentView.addSubview(textRows)

        iconBlockedWidth.constant = ChatListViewCell.kIconWidth
        unreadCountWidth.constant = 20
        iconMuted.constraints.first(where: { $0.firstAttribute == .width })?.constant = ChatListViewCell.kIconWidth

        // Keep both presentations on the same nib and original data outlets.
        func metric(_ constraint: NSLayoutConstraint, continuous: CGFloat) -> NSLayoutConstraint {
            rowMetrics.append((constraint, constraint.constant, continuous))
            return constraint
        }
        rowDivider.translatesAutoresizingMaskIntoConstraints = false
        rowDivider.backgroundColor = ClawTheme.border
        rowDivider.isUserInteractionEnabled = false
        rowDivider.accessibilityIdentifier = "claw.conversation.divider"
        contentView.addSubview(rowDivider)
        NSLayoutConstraint.activate([
            metric(cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20), continuous: 0),
            metric(cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20), continuous: 0),
            metric(cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5), continuous: 0),
            metric(cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5), continuous: 0),
            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 84),
            metric(icon.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12), continuous: 16),
            icon.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            icon.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -12),
            textRows.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            metric(textRows.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12), continuous: -16),
            textRows.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            textRows.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            messageTimeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            rowDivider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rowDivider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rowDivider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rowDivider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
        applyRowLayout()
    }

    private func applyRowLayout() {
        guard let timeRow = timeRow, let previewRow = previewRow else { return }
        rowMetrics.forEach { $0.0.constant = usesContinuousLayout ? $0.2 : $0.1 }
        cardView.layer.cornerRadius = usesContinuousLayout ? 0 : ClawTheme.cardRadius
        rowDivider.isHidden = !usesContinuousLayout
        title.numberOfLines = usesContinuousLayout ? 0 : 2
        let destination = usesContinuousLayout ? timeRow : previewRow
        if unreadCount.superview !== destination {
            (unreadCount.superview as? UIStackView)?.removeArrangedSubview(unreadCount)
            unreadCount.removeFromSuperview()
            destination.addArrangedSubview(unreadCount)
        }
        updateRowAxes()
        setNeedsLayout()
    }

    private func updateRowAxes() {
        guard let titleRow = titleRow else { return }
        titleRow.axis = usesContinuousLayout && traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            ? .vertical : .horizontal
        titleRow.alignment = titleRow.axis == .vertical ? .fill : .center
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        usesContinuousLayout = false
        title.text = nil
        subtitle.text = nil
        subtitle.attributedText = nil
        messageTimeLabel.text = nil
        unreadCount.isHidden = true
        setMessageStatusVisibility(hidden: true)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        cardView.backgroundColor = selected || isHighlighted ? ClawTheme.brandSoft : ClawTheme.surface
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        cardView.backgroundColor = highlighted || isSelected ? ClawTheme.brandSoft : ClawTheme.surface
    }

    override func layoutSubviews() {
        updateRowAxes()
        super.layoutSubviews()
        unreadCount.constraints.first(where: { $0.firstAttribute == .height })?.constant =
            max(24, ceil(unreadCount.font.lineHeight) + 8)
        unreadCount.layer.cornerRadius = unreadCount.bounds.height / 2
    }

    private func setMessageStatusVisibility(hidden: Bool) {
        let width: CGFloat = hidden ? 0 : ChatListViewCell.kMessageStatusWidth
        iconMessageStatus.isHidden = hidden
        iconMessageStatusWidth.constant = width
    }

    public func fillFromTopic(topic: DefaultComTopic) {
        title.text = topic.isSlfType ? NSLocalizedString("CLAW文件助手", comment: "Title of the CLAW file assistant") :
            topic.pub?.fn ?? NSLocalizedString("Unknown or unnamed", comment: "Topic title when it has no name")
        var latestTimestamp = topic.touched
        if let msg = topic.latestMessage as? StoredMessage {
            // If we have a latestMessage and its up to date.
            let availableWidth = max(contentView.bounds.width - 132, 140)
            subtitle.attributedText = msg.attributedPreview(
                fitIn: CGSize(width: availableWidth, height: ceil(subtitle.font.lineHeight) * 2),
                withDefaultAttributes: [
                    .font: ClawTheme.font(13, style: .subheadline),
                    .foregroundColor: ClawTheme.muted
                ])
            latestTimestamp = msg.ts
            if msg.from == Cache.tinode.myUid {
                setMessageStatusVisibility(hidden: false)
                let (image, tint) = UiUtils.deliveryMarkerIcon(for: msg, in: topic)
                iconMessageStatus.image = image
                iconMessageStatus.tintColor = tint
            } else {
                setMessageStatusVisibility(hidden: true)
            }
        } else {
            subtitle.text = topic.isSlfType ?
                NSLocalizedString("为以后保存的注释、消息、链接、文件", comment: "Explanation for Saved messages topic") :
                topic.comment
            setMessageStatusVisibility(hidden: true)
        }
        messageTimeLabel.text = latestTimestamp.map {
            RelativeDateFormatter.shared.shortDate(from: $0)
        } ?? ""
        if topic.isChannel {
            channelIndicator.isHidden = false
            channelIndicatorWidth.constant = ChatListViewCell.kIconWidth
        } else {
            channelIndicator.isHidden = true
            channelIndicatorWidth.constant = .leastNonzeroMagnitude
        }

        if topic.isVerified {
            badgeVerified.isHidden = false
            badgeVerifiedWidth.constant = ChatListViewCell.kIconWidth
        } else {
            badgeVerified.isHidden = true
            badgeVerifiedWidth.constant = .leastNonzeroMagnitude
        }
        if topic.isStaffManaged {
            badgeStaff.isHidden = false
            badgeStaffWidth.constant = ChatListViewCell.kIconWidth
        } else {
            badgeStaff.isHidden = true
            badgeStaffWidth.constant = .leastNonzeroMagnitude
        }
        if topic.isDangerous {
            badgeDanger.isHidden = false
            badgeDangerWidth.constant = ChatListViewCell.kIconWidth
        } else {
            badgeDanger.isHidden = true
            badgeDangerWidth.constant = .leastNonzeroMagnitude
        }

        let unread = topic.unread
        if unread > 0 {
            unreadCount.text = unread > 9 ? "9+" : String(unread)
            unreadCount.isHidden = false
            let badgeTextWidth = (unreadCount.text! as NSString).size(
                withAttributes: [.font: unreadCount.font!]).width
            unreadCountWidth.constant = max(24, ceil(badgeTextWidth) + 12)
        } else {
            unreadCount.isHidden = true
            unreadCountWidth.constant = .leastNonzeroMagnitude
        }

        let isBlocked = !topic.isJoiner
        iconBlocked.isHidden = !isBlocked
        iconBlockedWidth.constant = isBlocked ? ChatListViewCell.kIconWidth : .leastNonzeroMagnitude

        iconMuted.isHidden = topic.isSlfType || !topic.isMuted

        // Avatar image
        icon.set(pub: topic.pub, id: topic.name, online: (topic.isChannel || topic.isSlfType) ? nil : topic.online, deleted: topic.deleted)
        if topic.isSlfType {
            icon.setBrandingIcon()
        }

        accessibilityLabel = [title.text, subtitle.attributedText?.string ?? subtitle.text,
                              messageTimeLabel.text]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
