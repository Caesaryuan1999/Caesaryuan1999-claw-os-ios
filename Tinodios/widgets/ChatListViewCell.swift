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
    private var premiumLayoutInstalled = false

    override func awakeFromNib() {
        super.awakeFromNib()
        installPremiumLayout()
        backgroundColor = .white
        contentView.backgroundColor = .white
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = ClawTheme.ink
        subtitle.font = .systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = ClawTheme.muted
        icon.avatar.setFixedCornerRadius(12)
        unreadCount.backgroundColor = ClawTheme.primary
        unreadCount.textColor = .white
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
        title.numberOfLines = 1
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        subtitle.numberOfLines = 1
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.setContentHuggingPriority(.defaultLow, for: .horizontal)

        messageTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        messageTimeLabel.font = .systemFont(ofSize: 11, weight: .regular)
        messageTimeLabel.textColor = ClawTheme.muted
        messageTimeLabel.textAlignment = .right
        messageTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        messageTimeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleRow = UIStackView(arrangedSubviews: [
            title, channelIndicator, badgeVerified, badgeStaff, badgeDanger, messageTimeLabel
        ])
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 4

        let previewRow = UIStackView(arrangedSubviews: [
            iconMessageStatus, subtitle, iconMuted, iconBlocked, unreadCount
        ])
        previewRow.translatesAutoresizingMaskIntoConstraints = false
        previewRow.axis = .horizontal
        previewRow.alignment = .center
        previewRow.spacing = 4

        contentView.addSubview(titleRow)
        contentView.addSubview(previewRow)

        iconBlockedWidth.constant = ChatListViewCell.kIconWidth
        unreadCountWidth.constant = 20
        iconMuted.constraints.first(where: { $0.firstAttribute == .width })?.constant = ChatListViewCell.kIconWidth

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            titleRow.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            titleRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleRow.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            titleRow.heightAnchor.constraint(equalToConstant: 22),

            previewRow.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            previewRow.trailingAnchor.constraint(equalTo: titleRow.trailingAnchor),
            previewRow.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 4),
            previewRow.heightAnchor.constraint(equalToConstant: 24),

            messageTimeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        title.text = nil
        subtitle.text = nil
        subtitle.attributedText = nil
        messageTimeLabel.text = nil
        unreadCount.isHidden = true
        setMessageStatusVisibility(hidden: true)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
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
                fitIn: CGSize(width: availableWidth, height: 24),
                withDefaultAttributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .regular),
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
            unreadCountWidth.constant = 20
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
