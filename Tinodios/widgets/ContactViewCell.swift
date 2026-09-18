//
//  ContactViewCell.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

protocol ContactViewCellDelegate: AnyObject {
    func selected(from: UITableViewCell)
}

class ContactViewCell: UITableViewCell {
    private static let kSelectedBackgroundColor = UIColor(red: 0xC2/255, green: 0xC9/255, blue: 0xF9/255, alpha: 0.5)
    private static let kNormalBackgroundColor = UIColor.clear

    public weak var delegate: ContactViewCellDelegate?

    @IBOutlet weak var avatar: RoundImageView!
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var subtitle: UILabel!
    @IBOutlet var statusLabels: [ContactViewCellStatusLabel]!
    @IBOutlet private var avatarLeading: NSLayoutConstraint!
    @IBOutlet private var titleTop: NSLayoutConstraint!
    @IBOutlet private var minimumHeight: NSLayoutConstraint!
    @IBOutlet private var subtitleBottom: NSLayoutConstraint!
    @IBOutlet private var subtitleTrailing: NSLayoutConstraint!
    @IBOutlet private var statusesTrailing: NSLayoutConstraint!
    private let rowDivider = UIView()

    // Only the contacts home opts in. Member/group pickers retain their default nib.
    var usesContinuousLayout = false {
        didSet { if avatarLeading != nil { applyRowLayout() } }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        let card = UIView()
        card.backgroundColor = ClawTheme.surface
        card.layer.cornerRadius = 16
        backgroundView = card
        let selectedCard = UIView()
        selectedCard.backgroundColor = ClawTheme.brandSoft
        selectedCard.layer.cornerRadius = 16
        selectedBackgroundView = selectedCard
        selectionStyle = .default
        title.font = ClawTheme.font(16, weight: .medium)
        title.textColor = ClawTheme.ink
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        subtitle.font = ClawTheme.font(13)
        subtitle.textColor = ClawTheme.muted
        subtitle.numberOfLines = 0
        subtitle.adjustsFontForContentSizeCategory = true
        avatar.contentMode = .scaleAspectFill
        for label in statusLabels {
            label.font = ClawTheme.font(12)
            label.adjustsFontForContentSizeCategory = true
            if label.isHidden { label.text = nil }
        }
        accessibilityTraits = .button
        rowDivider.translatesAutoresizingMaskIntoConstraints = false
        rowDivider.backgroundColor = ClawTheme.border
        rowDivider.isUserInteractionEnabled = false
        rowDivider.accessibilityIdentifier = "claw.contact.divider"
        contentView.addSubview(rowDivider)
        NSLayoutConstraint.activate([
            rowDivider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rowDivider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rowDivider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rowDivider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])
        applyRowLayout()
    }

    private func applyRowLayout() {
        avatarLeading.constant = usesContinuousLayout ? 16 : 32
        titleTop.constant = usesContinuousLayout ? 12 : 17
        minimumHeight.constant = usesContinuousLayout ? 84 : 94
        subtitleBottom.constant = usesContinuousLayout ? 12 : 17
        subtitleTrailing.constant = usesContinuousLayout ? 16 : 32
        statusesTrailing.constant = usesContinuousLayout ? 16 : 32
        backgroundView?.layer.cornerRadius = usesContinuousLayout ? 0 : 16
        selectedBackgroundView?.layer.cornerRadius = usesContinuousLayout ? 0 : 16
        rowDivider.isHidden = !usesContinuousLayout
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        usesContinuousLayout = false
        delegate = nil
    }

    override func layoutSubviews() {
        for label in statusLabels where label.isHidden { label.text = nil }
        super.layoutSubviews()
        let cardFrame = usesContinuousLayout ? bounds : bounds.inset(by: UIEdgeInsets(top: 5, left: 20, bottom: 5, right: 20))
        backgroundView?.frame = cardFrame
        selectedBackgroundView?.frame = cardFrame
        avatar.layer.cornerRadius = 16
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        if selected {
            delegate?.selected(from: self)
        }
    }
}

class ContactViewCellStatusLabel: PaddedLabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        let insets = super.textInsets
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}
