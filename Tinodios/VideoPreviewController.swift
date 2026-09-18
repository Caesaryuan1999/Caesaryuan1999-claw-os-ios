//
//  VideoPreviewController.swift
//  Tinodios
//
//  Copyright © 2022-2025 Tinode LLC. All rights reserved.
//

import MobileVLCKit
import UIKit

struct VideoPreviewContent {
    enum VideoSource {
        case local(URL, UIImage?)  // newly picked video: local video url, preview/poster
        case remote(Data?, String?)  // existing message: inline data or reference
    }

    let videoSrc: VideoSource
    // Video duration in milliseconds.
    let duration: Int
    let fileName: String?
    // Video mime type.
    let contentType: String?
    // Video file size.
    let size: Int64?
    let width: Int?
    let height: Int?
    // Text annotation.
    let caption: String?

    // ReplyTo preview (the user is replying to another message with a video).
    let pendingMessagePreview: NSAttributedString?
}

class VideoPreviewController: UIViewController {
    @IBOutlet weak var videoView: UIView!

    @IBOutlet weak var videoSlider: UISlider!
    @IBOutlet weak var currentTimeLabel: UILabel!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var controlsView: UIView!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var spinner: UIActivityIndicatorView!

    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var videoContainer: UIView!
    @IBOutlet private weak var playbackStack: UIStackView!
    @IBOutlet private weak var actionsStack: UIStackView!
    @IBOutlet private weak var muteButton: UIButton!
    @IBOutlet private weak var metadataStack: UIStackView!
    @IBOutlet private weak var fileNameLabel: UILabel!
    @IBOutlet private weak var sizeLabel: UILabel!
    @IBOutlet private weak var errorStack: UIStackView!
    @IBOutlet private weak var errorTitleLabel: UILabel!
    @IBOutlet private weak var errorMessageLabel: UILabel!
    @IBOutlet private weak var returnButton: UIButton!
    @IBOutlet private weak var shareStack: UIStackView!
    @IBOutlet private weak var shareButton: UIButton!
    @IBOutlet private weak var shareStatusLabel: UILabel!
    @IBOutlet private weak var loadingLabel: UILabel!

    private enum PlaybackState { case loading, buffering, playing, paused, ended, failed }
    private var playbackState: PlaybackState = .loading
    private var sourceAvailable = false
    private var isPreparingShare = false
    private var keyboardOverlap: CGFloat = 0

    private var player = VLCMediaPlayer()
    private let thumbnailer = ThumbnailFetcher()
    private var didSubmitVideo = false

    private var ownedContext: ClawOwnedImageContext?
    private var playbackLease: ClawOwnedPlaybackLease?
    private var playbackDownload: ClawOwnedFileDownload?
    private var playbackBudget: ClawVideoDownloadBudget?
    private var ownerTimer: Timer?
    private var preparingPlayback = false
    private var preparationFailure: ClawFileTransferError?
    private var frozenContent: VideoPreviewContent?
    private var sourceGeneration = UUID()
    private var previewVisible = false
    private let shareSlot = ClawOwnedImageSlot()
    private var download: ClawOwnedFileDownload?

    var previewContent: VideoPreviewContent? {
        didSet {
            if isViewLoaded {
                invalidatePreview()
                frozenContent = nil
                ownedContext = nil
                playbackBudget = nil
                sourceAvailable = false
                renderPlayback()
            }
        }
    }
    var captureDisplayIntent: (() -> ChatDisplayIntent)?
    var replyPreviewDelegate: PendingMessagePreviewDelegate?

    var duration: Int = 0 {
        didSet {
            durationLabel.text = duration > 0 ? AbstractFormatter.millisToTime(millis: duration, fixedMin: true) : "--:--"
            updateMetadata()
            updateSeekingAvailability()
        }
    }

    private class ThumbnailFetcher: VLCMediaThumbnailerDelegate {
        enum State {
            case none
            case fetching
            case done(CGImage?)
        }
        var state: State = .none
        var thumbnailer: VLCMediaThumbnailer!
        var completion: ((CGImage?) -> Void)?

        func startFetching(fromMedia media: VLCMedia) {
            guard case .none = state else { return }
            state = .fetching
            thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
            thumbnailer.fetchThumbnail()
        }

        func dismiss() {
            state = .done(nil)
        }

        func getThumbmail(completionHandler: @escaping (CGImage?) -> Void) {
            switch state {
            case .none:
                completionHandler(nil)
            case .fetching:
                completion = completionHandler
            case .done(let th):
                completionHandler(th)
            }
        }

        func mediaThumbnailerDidTimeOut(_ mediaThumbnailer: VLCMediaThumbnailer) {
            Cache.log.error("Thumbnail creation failed: timed out")
            state = .done(nil)
            completion?(nil)
        }

        func mediaThumbnailer(_ mediaThumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
            state = .done(thumbnail)
            completion?(thumbnail)
        }
    }

    private func setup() {
        navigationItem.rightBarButtonItem = nil
        guard let content = self.previewContent,
              let context = ownedContext ?? Utils.ownedImageContext(), context.isCurrent else {
            preparationFailure = .sessionExpired
            renderPlayback()
            return
        }
        ownedContext = context
        frozenContent = content
        preparationFailure = nil
        sourceAvailable = false
        preparingPlayback = false
        playbackState = .loading
        sourceGeneration = UUID()
        let source = sourceGeneration
        sendVideoBar.togglePreviewBar(with: content.pendingMessagePreview)
        duration = content.duration
        currentTimeLabel.text = "--:--"
        startOwnerMonitor()

        switch content.videoSrc {
        case .local(let videoURL, _):
            sendVideoBar.delegate = self
            sendVideoBar.replyPreviewDelegate = replyPreviewDelegate
            // The selected source is caller-owned. This preview never removes it.
            beginPlayback(VLCMedia(url: videoURL), ownedFile: nil, source: source)
        case .remote(let bits, let ref):
            if let ref = ref {
                guard let url = context.resourceURL(from: ref) else {
                    failPreparation(.invalidURL); return
                }
                do { playbackBudget = try ClawVideoDownloadBudget.captured(from: context) }
                catch { failPreparation((error as? ClawFileTransferError) ?? .invalidData); return }
                preparingPlayback = true
                renderPlayback()
                let operation = ClawOwnedFileDownload(context: context, suggestedName: content.fileName,
                    budget: playbackBudget) { [weak self] result in
                    guard let self = self, self.acceptsSource(source) else {
                        if case let .success(file) = result { ClawMediaFiles.removeExport(file) }
                        return
                    }
                    self.playbackDownload = nil
                    self.preparingPlayback = false
                    switch result {
                    case let .success(file):
                        // A local entry point is not a container-content network sandbox.
                        self.beginPlayback(VLCMedia(url: file), ownedFile: file, source: source)
                    case let .failure(error):
                        self.failPreparation((error as? ClawFileTransferError) ?? .network)
                    }
                }
                playbackDownload = operation
                operation.start(from: url)
            } else if let bits = bits, !bits.isEmpty {
                // Keep the pre-existing inline stream behavior.
                beginPlayback(VLCMedia(stream: InputStream(data: bits)), ownedFile: nil, source: source)
            } else { failPreparation(.invalidData) }
        }
    }

    private func beginPlayback(_ media: VLCMedia, ownedFile: URL?, source: UUID) {
        guard acceptsSource(source), let context = ownedContext else {
            if let ownedFile = ownedFile { ClawMediaFiles.removeExport(ownedFile) }
            return
        }
        playbackLease?.retire()
        let currentPlayer = VLCMediaPlayer()
        player = currentPlayer
        currentPlayer.drawable = videoView
        currentPlayer.media = media
        currentPlayer.delegate = self
        let lease = ClawOwnedPlaybackLease(context: context, ownedFile: ownedFile, player: currentPlayer,
            stop: { currentPlayer.stop() }, isStopped: { currentPlayer.state == .stopped },
            detach: { currentPlayer.delegate = nil; currentPlayer.drawable = nil },
            releaseMedia: { currentPlayer.media = nil })
        playbackLease = lease
        sourceAvailable = true
        playbackState = .loading
        renderPlayback()
        if !lease.play({ currentPlayer.play() }) { failPreparation(.sessionExpired) }
    }

    private func failPreparation(_ error: ClawFileTransferError) {
        preparingPlayback = false
        preparationFailure = error
        sourceAvailable = false
        playbackState = .failed
        renderPlayback()
    }

    private func startOwnerMonitor() {
        ownerTimer?.invalidate()
        let source = sourceGeneration
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, self.previewVisible, self.sourceGeneration == source else { return }
            guard self.ownedContext?.isCurrent == true, self.playbackLease?.checkOwner() != false else {
                self.invalidatePreview()
                self.sendVideoBar.delegate = nil
                self.resignFirstResponder()
                self.reloadInputViews()
                self.failPreparation(.sessionExpired)
                return
            }
        }
        ownerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureInterface()
        // A custom inputAccessoryView is only installed after the controller
        // becomes first responder. Without this, the video preview opens but
        // the send bar is missing on iOS.
        DispatchQueue.main.async { self.becomeFirstResponder() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previewVisible = true
        setup()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        invalidatePreview()
    }

    private func invalidatePreview() {
        previewVisible = false
        ownerTimer?.invalidate()
        ownerTimer = nil
        sourceGeneration = UUID()
        playbackDownload?.cancel()
        playbackDownload = nil
        preparingPlayback = false
        shareSlot.invalidate()
        download?.cancel()
        download = nil
        isPreparingShare = false
        playbackLease?.retire()
        playbackLease = nil
    }

    private func acceptsSource(_ generation: UUID) -> Bool {
        previewVisible && frozenContent != nil && sourceGeneration == generation && ownedContext?.isCurrent == true
    }

    /// The `sendImageBar` is used as an optional `inputAccessoryView` in the view controller.
    private lazy var sendVideoBar: SendImageBar = {
        let view = SendImageBar()
        view.autoresizingMask = .flexibleHeight
        view.togglePreviewBar(with: nil)
        view.inputField.placeholderText = NSLocalizedString("Video caption", comment: "Video caption placeholder")
        return view
    }()

    // This makes input bar visible.
    override var inputAccessoryView: UIView? {
        //return super.inputAccessoryView
        //return sendVideoBar
        return previewContent?.videoSrc != nil && sendVideoBar.delegate != nil ? sendVideoBar : super.inputAccessoryView
    }

    override var canBecomeFirstResponder: Bool {
        return previewContent?.videoSrc != nil && sendVideoBar.delegate != nil
    }

    private func configureInterface() {
        navigationItem.largeTitleDisplayMode = .never
        videoContainer.layer.cornerRadius = ClawTheme.buttonRadius
        actionsStack.distribution = .fillEqually
        for button in [playPauseButton!, muteButton!, shareButton!, returnButton!] {
            ClawTheme.styleSecondaryButton(button)
            button.layer.cornerRadius = ClawTheme.buttonRadius
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.textAlignment = .center
            button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
            button.setTitleColor(ClawTheme.muted, for: .disabled)
        }
        for label in [fileNameLabel!, sizeLabel!, shareStatusLabel!, loadingLabel!,
                      errorMessageLabel!, currentTimeLabel!, durationLabel!] {
            label.font = ClawTheme.font(label === errorMessageLabel ? 16 : 14)
            label.adjustsFontForContentSizeCategory = true
        }
        errorTitleLabel.font = ClawTheme.font(24, weight: .bold, style: .title2)
        errorTitleLabel.adjustsFontForContentSizeCategory = true
        durationLabel.textAlignment = .right
        loadingLabel.textAlignment = .center
        spinner.color = .white
        currentTimeLabel.isAccessibilityElement = false
        durationLabel.isAccessibilityElement = false
        videoSlider.accessibilityLabel = "播放进度"
        playbackStack.accessibilityElements = [playPauseButton!, videoSlider!, muteButton!]
        playPauseButton.accessibilityIdentifier = "video.playback"
        muteButton.accessibilityIdentifier = "video.sound"
        shareButton.accessibilityIdentifier = "video.share"
        returnButton.accessibilityIdentifier = "video.return"
        shareStatusLabel.isHidden = true
        setInterfaceColors()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        ownerTimer?.invalidate()
        playbackDownload?.cancel()
        download?.cancel()
        let lease = playbackLease
        if Thread.isMainThread { lease?.retire() }
        else { DispatchQueue.main.async { lease?.retire() } }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let vertical = traitCollection.preferredContentSizeCategory.isAccessibilityCategory || view.bounds.width < 350
        let axis: NSLayoutConstraint.Axis = vertical ? .vertical : .horizontal
        if actionsStack.axis != axis { actionsStack.axis = axis }
        for button in [playPauseButton!, muteButton!, shareButton!, returnButton!] {
            guard let label = button.titleLabel else { continue }
            let width = button.bounds.width - button.contentEdgeInsets.left - button.contentEdgeInsets.right
            guard width > 0 else { continue }
            let textHeight = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            let minimum = max(52, ceil(textHeight + button.contentEdgeInsets.top + button.contentEdgeInsets.bottom))
            if let height = button.constraints.first(where: {
                $0.firstAttribute == .height && $0.relation == .greaterThanOrEqual
            }), abs(height.constant - minimum) > 0.5 {
                height.constant = minimum
            }
        }
        updateLocalAccessoryInsets()
    }

    @objc private func keyboardFrameChanged(_ notification: Notification) {
        guard previewVisible, sendVideoBar.delegate != nil,
              let rect = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(rect, from: nil)
        let overlap = view.bounds.intersection(converted)
        keyboardOverlap = overlap.isNull ? 0 : overlap.height
        updateLocalAccessoryInsets()
        // Re-evaluate the actual accessory frame after UIKit completes its keyboard layout.
        DispatchQueue.main.async { [weak self] in self?.updateLocalAccessoryInsets() }
    }

    private func updateLocalAccessoryInsets() {
        guard sendVideoBar.delegate != nil else { return }
        var covered = keyboardOverlap
        if sendVideoBar.window != nil, sendVideoBar.window === view.window {
            let rect = sendVideoBar.convert(sendVideoBar.bounds, to: view)
            let overlap = view.bounds.intersection(rect)
            if !overlap.isNull {
                covered = max(covered, view.bounds.maxY - overlap.minY)
            }
        }
        let bottom = max(0, covered - view.safeAreaInsets.bottom)
        if abs(scrollView.contentInset.bottom - bottom) > 0.5 {
            scrollView.contentInset.bottom = bottom
            scrollView.verticalScrollIndicatorInsets.bottom = bottom
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isViewLoaded else { return }
        setInterfaceColors()
        view.setNeedsLayout()
    }

    private func setInterfaceColors() {
        view.backgroundColor = ClawTheme.background
        scrollView.backgroundColor = ClawTheme.background
        videoContainer.backgroundColor = .black
        videoView.backgroundColor = .black
        controlsView.backgroundColor = .black
        for button in [playPauseButton!, muteButton!, shareButton!, returnButton!] {
            button.backgroundColor = ClawTheme.surface
        }
        for label in [fileNameLabel!, sizeLabel!, shareStatusLabel!, currentTimeLabel!, durationLabel!, errorMessageLabel!] {
            label.textColor = ClawTheme.muted
        }
        errorTitleLabel.textColor = ClawTheme.ink
        loadingLabel.textColor = .white
        videoSlider.tintColor = ClawTheme.primary
    }

    private var canShareOriginal: Bool {
        guard sourceAvailable, ownedContext?.isCurrent == true,
              let content = frozenContent, case .remote = content.videoSrc else { return false }
        return true
    }

    private func updateMetadata() {
        guard let content = frozenContent else { return }
        let name = content.fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        fileNameLabel.text = name?.isEmpty == false ? name : "视频附件"
        var parts = [duration > 0 ? AbstractFormatter.millisToTime(millis: duration, fixedMin: true) : "时长未知"]
        if let size = content.size, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        sizeLabel.text = parts.joined(separator: " · ")
    }

    private func updateSeekingAvailability() {
        let ready = sourceAvailable && ownedContext?.isCurrent == true &&
            (playbackState == .playing || playbackState == .paused || playbackState == .ended)
        videoSlider.isEnabled = ready && duration > 0 && player.isSeekable
        videoSlider.accessibilityValue = "\(currentTimeLabel.text ?? "--:--")，总时长\(durationLabel.text ?? "--:--")"
        videoSlider.accessibilityHint = videoSlider.isEnabled ? "向上或向下轻扫调整播放进度" : "当前暂不可调整进度"
    }

    private func refreshPlaybackState() {
        switch player.state {
        case .opening: playbackState = .loading
        case .buffering: playbackState = .buffering
        case .playing: playbackState = .playing
        case .paused: playbackState = .paused
        case .stopped:
            if playbackState != .failed && playbackState != .ended { playbackState = .paused }
        case .ended: playbackState = .ended
        case .error: playbackState = .failed
        default: break
        }
    }

    private func renderPlayback() {
        let failed = !sourceAvailable || ownedContext?.isCurrent != true || playbackState == .failed
        let loading = !failed && (playbackState == .loading || playbackState == .buffering)
        videoContainer.isHidden = failed
        playbackStack.isHidden = failed
        metadataStack.isHidden = failed
        errorStack.isHidden = !failed
        controlsView.isHidden = !loading
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
        loadingLabel.text = playbackState == .buffering ? "正在缓冲…" : "正在加载视频…"
        playPauseButton.isEnabled = !failed && !loading
        let title = playbackState == .ended ? "重新播放" : (player.isPlaying ? "暂停" : "播放")
        playPauseButton.setTitle(title, for: .normal)
        playPauseButton.accessibilityLabel = title
        let audio = player.audio
        let soundTitle: String
        if let audio = audio { soundTitle = audio.isMuted ? "开启声音" : "静音" }
        else { soundTitle = "声音暂不可用" }
        muteButton.setTitle(soundTitle, for: .normal)
        muteButton.accessibilityLabel = soundTitle
        muteButton.isEnabled = !failed && !loading && audio != nil
        returnButton.setTitle(preparingPlayback ? "取消并返回" : "返回聊天", for: .normal)
        if preparingPlayback {
            errorTitleLabel.text = "正在准备视频"
            errorMessageLabel.text = "视频下载完成后即可播放。返回聊天将取消本次加载。"
        } else if ownedContext?.isCurrent != true {
            errorTitleLabel.text = "视频已停止"
            errorMessageLabel.text = "当前会话已失效，请返回聊天后重新打开。"
        } else if let failure = preparationFailure {
            errorTitleLabel.text = "视频未加载完成"
            switch failure {
            case .network:
                errorMessageLabel.text = "请检查网络后，返回聊天重新打开视频。"
            case .http(403): errorMessageLabel.text = "当前账号无权查看这段视频。"
            case .tooLarge, .insufficientSpace, .spaceUnavailable: errorMessageLabel.text = failure.message
            case .write: errorMessageLabel.text = "无法准备本机视频文件，请稍后重新打开。"
            case .redirect: errorMessageLabel.text = "视频地址发生跳转，暂时无法安全加载。请返回聊天。"
            case .sessionExpired, .cancelled: errorMessageLabel.text = "操作已结束，请返回聊天后重新打开。"
            default: errorMessageLabel.text = "视频文件无法完整获取，请返回聊天检查此消息是否仍可访问。"
            }
        } else {
            errorTitleLabel.text = "视频暂时无法播放"
            errorMessageLabel.text = canShareOriginal
                ? "你可以返回聊天后重新打开，或分享原文件。"
                : "请返回聊天检查此消息是否仍可访问。"
        }
        shareStack.isHidden = !canShareOriginal
        shareButton.isEnabled = canShareOriginal && !isPreparingShare
        shareButton.setTitle(isPreparingShare ? "正在准备分享…" : "分享视频", for: .normal)
        shareButton.accessibilityLabel = isPreparingShare ? "正在准备分享" : "分享视频"
        updateMetadata()
        updateSeekingAvailability()
    }

    @IBAction private func returnToChat(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction func playPauseClicked(_ sender: Any) {
        guard acceptsSource(sourceGeneration), sourceAvailable, playbackState != .failed,
              playbackState != .loading, playbackState != .buffering else { return }
        if player.state == .ended || player.state == .stopped {
            player.position = 0
            playbackLease?.play { player.play() }
            return
        }

        if player.isPlaying {
            player.pause()
        } else {
            playbackLease?.play { player.play() }
        }
    }

    @IBAction func videoSliderChanged(_ sender: Any) {
        guard acceptsSource(sourceGeneration), self.duration > 0 && player.isSeekable else { return }
        guard let slider = sender as? UISlider else { return }
        let value = slider.value
        player.position = value
    }

    @IBAction func saveVideoButtonClicked(_ sender: Any) {
        guard acceptsSource(sourceGeneration), canShareOriginal, !isPreparingShare,
              let context = ownedContext,
              let content = frozenContent, case let .remote(bits, ref) = content.videoSrc,
              let button = sender as? UIButton, button === shareButton else { return }
        let source = sourceGeneration
        let attempt = shareSlot.invalidate()
        download?.cancel()
        isPreparingShare = true
        shareStatusLabel.isHidden = true
        renderPlayback()
        let presentation = ClawOwnedFilePresentation(context: context, attemptIsCurrent: { [weak self] in
            self?.acceptsSource(source) == true && self?.shareSlot.accepts(attempt) == true
        })
        let completed: ClawOwnedFileDownload.Completion = { [weak self, weak button] result in
            guard let self = self, let button = button, button === self.shareButton else {
                if case let .success(file) = result { ClawMediaFiles.removeExport(file) }
                return
            }
            presentation.complete(result, restore: {
                self.download = nil
                self.isPreparingShare = false
                self.renderPlayback()
            }, success: { file in
                UiUtils.presentFileSharingVC(for: file, presentation: presentation, from: self)
            }, failure: { error in
                self.shareStatusLabel.text = (error as? ClawFileTransferError)?.message
                    ?? ClawFileTransferError.write.message
                self.shareStatusLabel.isHidden = false
                UIAccessibility.post(notification: .layoutChanged, argument: self.shareStatusLabel)
            })
        }
        if let ref = ref {
            guard let url = context.resourceURL(from: ref), let budget = playbackBudget else {
                completed(.failure(ClawFileTransferError.invalidURL)); return
            }
            let operation = ClawOwnedFileDownload(context: context, suggestedName: content.fileName,
                                                  budget: budget, completion: completed)
            download = operation
            operation.start(from: url)
        } else if let bits = bits, !bits.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Swift.Result<URL, Error>
                do {
                    guard context.isCurrent else { throw ClawFileTransferError.sessionExpired }
                    let file = try ClawMediaFiles.exportData(bits, suggestedName: content.fileName)
                    if context.isCurrent { result = .success(file) }
                    else {
                        ClawMediaFiles.removeExport(file)
                        result = .failure(ClawFileTransferError.sessionExpired)
                    }
                } catch { result = .failure(ClawFileTransferError.write) }
                DispatchQueue.main.async { completed(result) }
            }
        } else {
            completed(.failure(ClawFileTransferError.invalidData))
        }
    }

    @IBAction func muteButtonClicked(_ sender: Any) {
        guard acceptsSource(sourceGeneration) else { return }
        if let btn = sender as? UIButton, let audio = player.audio {
            let isMuted = audio.isMuted
            audio.isMuted = !isMuted

            let title = audio.isMuted ? "开启声音" : "静音"
            btn.setTitle(title, for: .normal)
            btn.accessibilityLabel = title
        }
    }
}

extension VideoPreviewController: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.mediaPlayerStateChanged(aNotification) }
            return
        }
        guard acceptsSource(sourceGeneration), let player = aNotification.object as? VLCMediaPlayer,
              player === self.player else { return }
        switch player.state {
        case .playing:
            // Auto-play for remote videos only.
            var shouldPause = false
            if case .none = thumbnailer.state {
                if case .local(_, _) = frozenContent!.videoSrc {
                    // Video's just started playing.
                    thumbnailer.startFetching(fromMedia: player.media!)
                    shouldPause = true
                } else {
                    thumbnailer.dismiss()
                }
                // Maybe update duration.
                if duration == 0 {
                    duration = Int(truncating: player.media!.length.value ?? 0)
                }
                // Set initial time.
                setTime(VLCTime(number: 0))
            }
            playbackState = .playing
            if shouldPause {
                playPauseClicked(playPauseButton!)
                playbackState = .paused
            }
            renderPlayback()
        case .opening:
            playbackState = .loading
            renderPlayback()
        case .buffering:
            playbackState = .buffering
            renderPlayback()
        case .error:
            playbackState = .failed
            renderPlayback()
            UIAccessibility.post(notification: .layoutChanged, argument: errorTitleLabel)
        case .ended:
            // Update slider position and ts label
            // in case the corresponding VLCMediaPlayer event doesn't fire for whatever reason.
            videoSlider.value = 1
            currentTimeLabel.text = self.durationLabel.text
            playbackState = .ended
            renderPlayback()
        case .stopped, .paused:
            // A VLC stop following an error must not erase its recovery page.
            if playbackState != .failed && playbackState != .ended { playbackState = .paused }
            renderPlayback()
        default:
            break
        }
    }

    private func setTime(_ time: VLCTime) {
        guard let ts = time.value else { return }
        if self.duration > 0 {
            videoSlider.value = Float(truncating: ts) / Float(self.duration)
        }
        currentTimeLabel.text = time.stringValue
        updateSeekingAvailability()
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.mediaPlayerTimeChanged(aNotification) }
            return
        }
        guard acceptsSource(sourceGeneration), let player = aNotification.object as? VLCMediaPlayer,
              player === self.player else { return }
        setTime(player.time)
    }
}

extension VideoPreviewController: SendImageBarDelegate {
    func sendImageBar(caption: String?) {
        guard acceptsSource(sourceGeneration), let originalContent = frozenContent,
              case .local(let url, _) = originalContent.videoSrc,
              let media = player.media,
              !didSubmitVideo else { return }

        let displayIntent = captureDisplayIntent?() ?? .passive
        didSubmitVideo = true
        sendVideoBar.sendButton.isEnabled = false

        let size = player.videoSize
        let width = Int(size.width) > 0 ? Int(size.width) : max(originalContent.width ?? 0, 1)
        let height = Int(size.height) > 0 ? Int(size.height) : max(originalContent.height ?? 0, 1)
        let duration = max(Int(truncating: media.length.value ?? 0), 0)
        let mimeType = originalContent.contentType ?? Utils.mimeForUrl(url: url, ifMissing: "video/mp4")
        let fileName = originalContent.fileName ?? url.lastPathComponent
        let source = sourceGeneration
        thumbnailer.getThumbmail { [weak self] thumbnail in
            DispatchQueue.main.async {
                guard let self = self, self.acceptsSource(source) else { return }
                var preview: UIImage?
                if let th = thumbnail {
                    preview = UIImage(cgImage: th)
                }
                let content2 = VideoPreviewContent(
                    videoSrc: .local(url, preview),
                    duration: duration,
                    fileName: fileName.isEmpty ? Utils.uniqueFilename(forMime: mimeType) : fileName,
                    contentType: mimeType,
                    size: 0,
                    width: width,
                    height: height,
                    caption: caption,
                    pendingMessagePreview: nil
                )

                // This notification is received by the MessageViewController.
                NotificationCenter.default.post(name: Notification.Name(MessageViewController.kNotificationSendAttachment), object: content2,
                    userInfo: [ChatDisplayIntent.notificationKey: displayIntent])
                // Return to MessageViewController.
                self.navigationController?.popViewController(animated: true)
            }
        }
    }

    func dismissPreview() {
        self.replyPreviewDelegate?.dismissPendingMessagePreview()
    }
}
