//
//  ImagePreviewController.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//

// Shows full-screen
import Kingfisher
import TinodeSDK
import UIKit

struct ImagePreviewContent {
    enum ImageContent {
        case uiimage(UIImage)
        case rawdata(Data?, String?)  // inline data or reference
    }

    let imgContent: ImageContent
    let caption: String?
    let fileName: String?
    let contentType: String?
    let size: Int64?
    let width: Int?
    let height: Int?

    // ReplyTo preview (the user is replying to another message with an image).
    let pendingMessagePreview: NSAttributedString?
}

class ImagePreviewController: UIViewController, UIScrollViewDelegate {
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var imageView: UIImageView!

    var previewContent: ImagePreviewContent?
    var captureDisplayIntent: (() -> ChatDisplayIntent)?
    var replyPreviewDelegate: PendingMessagePreviewDelegate?
    private let mediaState = ClawMediaPreviewState()
    private var mediaOwner: Tinode?
    private var mediaSession: ClawMediaSession?
    private var serviceURL: URL?
    private var downloadURL: URL?
    private var downloadTask: DownloadTask?
    private var downloader: ImageDownloader?
    private let recoveryStack = UIStackView()
    private let recoveryTitle = UILabel()
    private let recoveryDetail = UILabel()
    private let retryButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }

    private func setup() {
        guard let content = previewContent else { return }
        title = "图片"
        setInterfaceColors()
        switch content.imgContent {
        case .uiimage(let image):
            imageView.image = image
            sendImageBar.delegate = self
            sendImageBar.replyPreviewDelegate = replyPreviewDelegate
            sendImageBar.togglePreviewBar(with: content.pendingMessagePreview)
            navigationItem.rightBarButtonItem = nil
        case .rawdata(let bits, let ref):
            let owner = Cache.tinode
            let snapshot = Cache.ifCurrent(owner) { () -> (ClawMediaSession, URL?)? in
                guard let uid = owner.myUid, owner.store?.myUid == uid else { return nil }
                return (ClawMediaSession(owner: ObjectIdentifier(owner), uid: uid,
                                         generation: Cache.sessionGeneration),
                        owner.baseURL(useWebsocketProtocol: false))
            } ?? nil
            mediaOwner = owner
            mediaSession = snapshot?.0
            serviceURL = snapshot?.1
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "分享", style: .plain,
                target: self, action: #selector(saveImageButtonClicked(_:)))
            setupRecovery()
            sendImageBar.togglePreviewBar(with: nil)
            guard withMediaOwner({ true }) == true else {
                mediaState.fail(mediaState.begin(), forbidden: true)
                renderMediaState()
                return
            }
            if let ref = ref {
                // Inline bits accompanying a reference are only a thumbnail.
                imageView.image = bits.flatMap { UIImage(data: $0) }
                if let service = serviceURL, let url = URL(string: ref, relativeTo: service)?.absoluteURL,
                   ClawMediaFiles.isAllowedMediaURL(url, service: service) {
                    downloadURL = url
                    startDownload()
                } else {
                    mediaState.fail(mediaState.begin())
                    renderMediaState()
                }
            } else {
                imageView.image = mediaState.loadInline(bits)
                renderMediaState()
            }
        }
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 8
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if mediaOwner != nil, withMediaOwner({ true }) != true {
            mediaState.fail(mediaState.begin(), forbidden: true)
            imageView.image = nil
            renderMediaState()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            downloadTask?.cancel()
            mediaState.fail(mediaState.begin())
        }
    }

    deinit { downloadTask?.cancel() }

    /// Lock order follows Cache: SDK session, then Cache. No asynchronous wait under the gate.
    private func withMediaOwner<T>(_ body: () -> T) -> T? {
        guard let owner = mediaOwner, let snapshot = mediaSession else { return nil }
        return Cache.ifCurrent(owner) {
            guard snapshot.accepts(owner: owner, uid: owner.myUid, storedUID: owner.store?.myUid,
                                   generation: Cache.sessionGeneration) else { return nil }
            return body()
        } ?? nil
    }

    private lazy var sendImageBar: SendImageBar = {
        let bar = SendImageBar()
        bar.autoresizingMask = .flexibleHeight
        return bar
    }()

    override var inputAccessoryView: UIView? {
        previewContent?.imgContent != nil && sendImageBar.delegate != nil ? sendImageBar : super.inputAccessoryView
    }

    override var canBecomeFirstResponder: Bool {
        previewContent?.imgContent != nil && sendImageBar.delegate != nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else { return }
        setInterfaceColors()
    }

    private func setInterfaceColors() {
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        scrollView.backgroundColor = .black
        imageView.backgroundColor = .black
    }

    func viewForZooming(in: UIScrollView) -> UIView? { imageView }

    private func setupRecovery() {
        recoveryStack.axis = .vertical
        recoveryStack.spacing = 16
        recoveryStack.translatesAutoresizingMaskIntoConstraints = false
        recoveryTitle.font = .preferredFont(forTextStyle: .headline)
        recoveryTitle.textColor = ClawTheme.ink
        recoveryTitle.numberOfLines = 0
        recoveryDetail.font = .preferredFont(forTextStyle: .body)
        recoveryDetail.textColor = ClawTheme.muted
        recoveryDetail.numberOfLines = 0
        ClawTheme.stylePrimaryButton(retryButton)
        retryButton.setTitle("重试加载", for: .normal)
        retryButton.accessibilityLabel = "重试加载图片"
        retryButton.addTarget(self, action: #selector(retryDownload), for: .touchUpInside)
        let back = UIButton(type: .system)
        ClawTheme.styleSecondaryButton(back)
        back.setTitle("返回聊天", for: .normal)
        back.addTarget(self, action: #selector(returnToChat), for: .touchUpInside)
        for button in [retryButton, back] {
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        }
        for item in [recoveryTitle, recoveryDetail, retryButton, back] { recoveryStack.addArrangedSubview(item) }
        view.addSubview(recoveryStack)
        NSLayoutConstraint.activate([
            recoveryStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            recoveryStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            recoveryStack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private func renderMediaState() {
        let phase = mediaState.phase
        navigationItem.rightBarButtonItem?.isEnabled = phase == .ready
        recoveryStack.isHidden = phase == .ready
        imageView.isHidden = phase != .ready
        recoveryTitle.text = phase == .loading ? "正在加载图片" : "图片暂时无法加载"
        recoveryDetail.text = phase == .forbidden ? "当前账号无权查看这张图片。"
            : phase == .loading ? "图片尚未加载完成，暂时无法分享。"
            : "请重试，或返回聊天检查此消息是否仍可访问。"
        retryButton.isHidden = downloadURL == nil || phase == .loading || phase == .forbidden
    }

    @objc private func retryDownload() { startDownload() }
    @objc private func returnToChat() { navigationController?.popViewController(animated: true) }

    @IBAction func saveImageButtonClicked(_ sender: Any) {
        guard let content = previewContent, case .rawdata = content.imgContent,
              let owner = mediaOwner else { return }
        guard let data = withMediaOwner({ mediaState.shareData }) ?? nil else {
            UiUtils.showToast(message: "图片尚未加载完成，暂时无法分享。")
            return
        }
        do {
            let destination = try ClawMediaFiles.exportPNG(data, suggestedName: content.fileName)
            guard withMediaOwner({ true }) == true else { return }
            UiUtils.presentFileSharingVC(for: destination, for: owner)
        } catch {
            Cache.log.info("image_export_failed")
            if withMediaOwner({ true }) == true {
                UiUtils.showToast(message: "无法准备分享文件，请稍后重试。")
            }
        }
    }

    private func startDownload() {
        guard let url = downloadURL, let service = serviceURL, let snapshot = mediaSession,
              let owner = mediaOwner,
              let key = ClawMediaFiles.cacheKey(origin: service, uid: snapshot.uid, url: url),
              withMediaOwner({ true }) == true else { return }
        downloadTask?.cancel()
        let requestID = mediaState.begin()
        renderMediaState()
        let modifier = AnyModifier { [weak self] request in
            guard let self = self else { return nil }
            return self.withMediaOwner { () -> URLRequest? in
                guard self.mediaState.isCurrent(requestID), let requestURL = request.url,
                      ClawMediaFiles.isAllowedMediaURL(requestURL, service: service) else { return nil }
                var modified = request
                // External HTTPS resources may carry their own signed query. Never attach Tinode credentials.
                if ClawMediaFiles.origin(requestURL) == ClawMediaFiles.origin(service) {
                    LargeFileHelper.addCommonHeaders(to: &modified, using: owner)
                }
                return modified
            } ?? nil
        }
        // Dedicated transport prevents URL-only coalescing across account sessions.
        let transport = ImageDownloader(name: key + "-" + requestID.uuidString)
        transport.sessionConfiguration = .ephemeral
        downloader = transport
        let denyRedirect = AnyRedirectHandler { _, _, _, completion in completion(nil) }
        let resource = Kingfisher.ImageResource(downloadURL: url, cacheKey: key)
        downloadTask = KingfisherManager.shared.retrieveImage(with: resource,
            options: [.requestModifier(modifier), .redirectHandler(denyRedirect), .downloader(transport)],
            completionHandler: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.withMediaOwner {
                        guard self.mediaState.isCurrent(requestID) else { return }
                        switch result {
                        case .success(let value):
                            if self.mediaState.complete(requestID, image: value.image) {
                                self.imageView.image = value.image
                            }
                        case .failure(let error):
                            self.mediaState.fail(requestID, forbidden: error.isInvalidResponseStatusCode(403))
                            self.imageView.image = nil
                            Cache.log.info("image_load_failed")
                        }
                        self.renderMediaState()
                    }
                }
            })
    }
}

extension ImagePreviewController: SendImageBarDelegate {
    func sendImageBar(caption: String?) {
        guard let originalContent = self.previewContent else { return }
        guard case let .uiimage(originalImage) = originalContent.imgContent else { return }
        let displayIntent = captureDisplayIntent?() ?? .passive

        let mimeType = originalContent.contentType == "image/png" ?  "image/png" : "image/jpeg"
        // Ensure image linear dimensions are under the limits.
        guard let image = originalImage.resize(width: UiUtils.kMaxBitmapSize, height: UiUtils.kMaxBitmapSize, clip: false) else { return }

        let content = ImagePreviewContent(
            imgContent: ImagePreviewContent.ImageContent.uiimage(image),
            caption: caption,
            fileName: originalContent.fileName,
            contentType: mimeType,
            size: -1,
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale),
            pendingMessagePreview: nil
        )

        // This notification is received by the MessageViewController.
        NotificationCenter.default.post(name: Notification.Name(MessageViewController.kNotificationSendAttachment), object: content,
            userInfo: [ChatDisplayIntent.notificationKey: displayIntent])
        // Return to MessageViewController.
        navigationController?.popViewController(animated: true)
    }
    func dismissPreview() {
        self.replyPreviewDelegate?.dismissPendingMessagePreview()
    }
}
