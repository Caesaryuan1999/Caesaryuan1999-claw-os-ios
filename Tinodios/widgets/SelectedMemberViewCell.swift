//
//  SelectedMemberViewCell.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

class SelectedMemberViewCell: UICollectionViewCell {

    @IBOutlet weak var avatarImageView: RoundImageView!

    private let nameLabel = UILabel()
    private let removeButton = UIButton(type: .system)
    var onRemove: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()

        clipsToBounds = false
        contentView.clipsToBounds = false
        backgroundColor = .clear

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true

        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = ClawTheme.ink
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(nameLabel)

        ClawTheme.styleIconButton(removeButton, symbolName: "xmark", pointSize: 9, tintColor: .white)
        removeButton.backgroundColor = ClawTheme.primary
        removeButton.layer.cornerRadius = 9
        removeButton.clipsToBounds = true
        removeButton.accessibilityLabel = NSLocalizedString("Remove", comment: "Remove selected group member")
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        contentView.addSubview(removeButton)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatarImageView.frame = CGRect(x: 8, y: 0, width: 48, height: 48)
        avatarImageView.layer.cornerRadius = 24
        removeButton.frame = CGRect(x: 44, y: 0, width: 18, height: 18)
        nameLabel.frame = CGRect(x: 0, y: 52, width: bounds.width, height: 16)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        nameLabel.text = nil
        onRemove = nil
    }

    func configure(name: String) {
        nameLabel.text = name
        accessibilityLabel = name
    }

    @objc private func removeTapped() {
        onRemove?()
    }
}
