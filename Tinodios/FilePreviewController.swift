//
//  FilePreviewController.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

import UIKit
import TinodeSDK

struct FilePreviewContent {
    let data: Data
    let refUrl: URL?
    let fileName: String?
    let contentType: String?
    let size: Int?
    var destinationName: String? = nil

    // ReplyTo preview (the user is replying to another message with a file).
    let pendingMessagePreview: NSAttributedString?
}

class FilePreviewController: UIViewController, UIScrollViewDelegate {

    var previewContent: FilePreviewContent?
    var captureDisplayIntent: (() -> ChatDisplayIntent)?
    var replyPreviewDelegate: PendingMessagePreviewDelegate?
    private var sending = false
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var contentTypeLabel: UILabel!
    @IBOutlet weak var fileNameLabel: UILabel!
    @IBOutlet weak var sizeLabel: UILabel!

    @IBOutlet weak var previewView: RichTextView!
    @IBOutlet weak var previewViewHeight: NSLayoutConstraint!

    @IBAction func sendFileAttachment(_ sender: UIButton) {
        guard let content = previewContent, !sending else { return }
        let displayIntent = captureDisplayIntent?() ?? .passive
        sending = true
        sendButton.isEnabled = false
        // The existing message flow owns upload and publish state.
        NotificationCenter.default.post(name: Notification.Name(MessageViewController.kNotificationSendAttachment), object: content,
            userInfo: [ChatDisplayIntent.notificationKey: displayIntent])
        // Return to MessageViewController.
        navigationController?.popViewController(animated: true)
    }

    @IBAction func cancelFilePreview(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction func cancelPreviewClicked(_ sender: Any) {
        self.togglePreviewBar(with: nil)
        self.replyPreviewDelegate?.dismissPendingMessagePreview()
    }

    private func setup() {
        title = "发送文件"
        ClawTheme.stylePrimaryButton(sendButton)
        ClawTheme.styleSecondaryButton(cancelButton)
        sendButton.setTitle("发送文件", for: .normal)
        sendButton.accessibilityLabel = "发送文件"
        cancelButton.setTitle("取消", for: .normal)
        cancelButton.accessibilityLabel = "取消发送文件"
        guard let content = self.previewContent else {
            sendButton.isEnabled = false
            return
        }

        // Set icon appropriate for mime type
        imageView.image = UIImage(named: FilePreviewController.iconFromMime(previewContent?.contentType))

        // Fill out attachment details.
        fileNameLabel.text = content.fileName ?? NSLocalizedString("undefined", comment: "Placeholder for missing file name")
        contentTypeLabel.text = content.contentType ?? NSLocalizedString("undefined", comment: "Placeholder for missing file type")
        var sizeString = "?? KB"
        if let size = content.size {
            sizeString = UiUtils.bytesToHumanSize(Int64(size))
        }
        sizeLabel.text = sizeString
        self.togglePreviewBar(with: content.pendingMessagePreview)
        fileNameLabel.numberOfLines = 0
        fileNameLabel.lineBreakMode = .byWordWrapping
        if let details = fileNameLabel.superview?.superview as? UIStackView {
            details.distribution = .fill
            let destination = UILabel()
            destination.numberOfLines = 0
            destination.font = .preferredFont(forTextStyle: .subheadline)
            destination.textColor = ClawTheme.ink
            destination.text = content.destinationName.flatMap { $0.isEmpty ? nil : "将发送到「" + $0 + "」" }
                ?? "将发送到当前会话"
            let explanation = UILabel()
            explanation.numberOfLines = 0
            explanation.font = .preferredFont(forTextStyle: .footnote)
            explanation.textColor = ClawTheme.muted
            explanation.text = "发送前请确认文件内容。需要上传的文件会先完成上传，再提交消息。"
            details.addArrangedSubview(destination)
            details.addArrangedSubview(explanation)
        }
        setInterfaceColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
    }

    private func setInterfaceColors() {
        view.backgroundColor = ClawTheme.background
        fileNameLabel.textColor = ClawTheme.ink
        contentTypeLabel.textColor = ClawTheme.muted
        sizeLabel.textColor = ClawTheme.muted
        imageView.tintColor = ClawTheme.primary
    }

    // Get icon name from mime type.
    // If more icons become available in material icons, add them to this mime-to-icon mapping.
    static let kMimeToIcon = ["text": "file-text-125", "image": "file-image-125", "video": "file-video-125", "audio": "file-audio-125"]
    static let kDefaultIcon = "file"
    private static func iconFromMime(_ mime: String?) -> String {
        guard let mime = mime else { return FilePreviewController.kDefaultIcon }

        // Try full mime type first, e.g. "text/plain".
        if let icon = FilePreviewController.kMimeToIcon[mime] {
            return icon
        }

        // Full not found, try major part, e.g. "text/plain" -> "text".
        let parts = mime.split(separator: "/")
        if let icon = FilePreviewController.kMimeToIcon[String(parts[0])] {
            return icon
        }

        return FilePreviewController.kDefaultIcon
    }

    public func togglePreviewBar(with message: NSAttributedString?) {
        if let message = message, let delegate = self.replyPreviewDelegate {
            let textBounds = delegate.pendingPreviewMessageSize(forMessage: message)
            previewViewHeight.constant = textBounds.height
            previewView.attributedText = message
            previewView.isHidden = false
        } else {
            previewViewHeight.constant = CGFloat.zero
            previewView.attributedText = nil
            previewView.isHidden = true
        }
    }
}
