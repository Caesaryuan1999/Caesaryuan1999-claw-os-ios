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

    private let player = VLCMediaPlayer()
    private let thumbnailer = ThumbnailFetcher()
    private var didSubmitVideo = false

    private var ownedContext: ClawOwnedImageContext?
    private var ownedHelper: LargeFileHelper?
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
                ownedHelper = nil
            }
        }
    }
    var replyPreviewDelegate: PendingMessagePreviewDelegate?

    var duration: Int = 0 {
        didSet {
            let success = duration != 0
            videoSlider.isEnabled = success
            durationLabel.text = duration > 0 ? AbstractFormatter.millisToTime(millis: duration, fixedMin: true) : "--:--"
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
        navigationItem.rightBarButtonItem?.isEnabled = false
        guard let content = self.previewContent, let context = Utils.ownedImageContext() else { return }
        ownedContext = context
        ownedHelper = Cache.ifCurrent(context.owner) { Cache.getLargeFileHelper() }
        frozenContent = content
        navigationItem.rightBarButtonItem?.image = nil
        navigationItem.rightBarButtonItem?.title = "分享视频"
        navigationItem.rightBarButtonItem?.accessibilityLabel = "分享视频"

        var url: URL?
        var stream: Stream?
        switch content.videoSrc {
        case .local(let videoUrl, _):
            url = videoUrl
            sendVideoBar.delegate = self

            sendVideoBar.replyPreviewDelegate = replyPreviewDelegate
            // Hide [Save video] button.
            navigationItem.rightBarButtonItem = nil
        case .remote(let bits, let ref):
            if let ref = ref {
                guard let mediaURL = context.resourceURL(from: ref) else { return }
                // VLC playback remains separate; the URL is bound to the captured owner.
                url = context.withCurrent { context.owner.addAuthQueryParams(mediaURL) }
            } else if let bits = bits, !bits.isEmpty {
                stream = InputStream(data: bits)
            } else {
                return
            }
        }
        sendVideoBar.togglePreviewBar(with: content.pendingMessagePreview)
        self.duration = content.duration

        currentTimeLabel.text = "--:--"

        updatePlayPauseButton(isPlaying: false)

        player.drawable = videoView
        var media: VLCMedia
        if let url = url {
            media = VLCMedia(url: url)
        } else if let stream = stream as? InputStream {
            media = VLCMedia(stream: stream)
        } else {
            DispatchQueue.main.async {
                UiUtils.showToast(message: NSLocalizedString("Invalid video", comment: "Invalid video input"))
            }
            return
        }
        player.media = media
        player.delegate = self
        if context.isCurrent { player.play() }

        setInterfaceColors()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
        // A custom inputAccessoryView is only installed after the controller
        // becomes first responder. Without this, the video preview opens but
        // the send bar is missing on iOS.
        DispatchQueue.main.async { self.becomeFirstResponder() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        previewVisible = true
        navigationItem.rightBarButtonItem?.isEnabled = ownedContext?.isCurrent == true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        invalidatePreview()
    }

    private func invalidatePreview() {
        previewVisible = false
        sourceGeneration = UUID()
        shareSlot.invalidate()
        download?.cancel()
        download = nil
        player.stop()
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        self.setInterfaceColors()
    }

    private func setInterfaceColors() {
        view.backgroundColor = .black
        videoView.backgroundColor = .black
    }

    private func updatePlayPauseButton(isPlaying: Bool) {
        let im = UIImage(systemName: isPlaying ? "pause.fill" : "play.fill",
                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 70, weight: .regular, scale: .large))
        playPauseButton.setImage(im, for: .normal)
        if isPlaying {
            UIView.animate(withDuration: 1) {
                self.playPauseButton.alpha = 0.2
            }
        } else {
            self.playPauseButton.alpha = 1
        }
    }

    @IBAction func playPauseClicked(_ sender: Any) {
        guard acceptsSource(sourceGeneration) else { return }
        if player.state == .ended || player.state == .stopped {
            player.stop()
            player.position = 0
            player.play()
            return
        }

        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    @IBAction func videoSliderChanged(_ sender: Any) {
        guard acceptsSource(sourceGeneration), self.duration > 0 && player.isSeekable else { return }
        let value = (sender as! UISlider).value
        player.position = value
    }

    @IBAction func saveVideoButtonClicked(_ sender: Any) {
        guard acceptsSource(sourceGeneration), let context = ownedContext,
              let content = frozenContent, case let .remote(bits, ref) = content.videoSrc,
              let button = sender as? UIBarButtonItem else { return }
        let source = sourceGeneration
        let attempt = shareSlot.invalidate()
        download?.cancel()
        button.isEnabled = false
        let presentation = ClawOwnedFilePresentation(context: context, attemptIsCurrent: { [weak self] in
            self?.acceptsSource(source) == true && self?.shareSlot.accepts(attempt) == true
        })
        let completed: ClawOwnedFileDownload.Completion = { [weak self, weak button] result in
            guard let self = self, let button = button else {
                if case let .success(file) = result { ClawMediaFiles.removeExport(file) }
                return
            }
            presentation.complete(result, restore: {
                self.download = nil
                button.isEnabled = true
            }, success: { file in
                UiUtils.presentFileSharingVC(for: file, presentation: presentation, from: self)
            }, failure: { error in
                UiUtils.showToast(message: (error as? ClawFileTransferError)?.message
                    ?? ClawFileTransferError.write.message)
            })
        }
        if let ref = ref {
            guard let url = context.resourceURL(from: ref), let helper = ownedHelper else {
                completed(.failure(ClawFileTransferError.invalidURL)); return
            }
            download = helper.startOwnedDownload(from: url, context: context,
                suggestedName: content.fileName, completion: completed)
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

            let im = UIImage(systemName: !isMuted ? "speaker.slash.fill" : "speaker.fill")
            btn.setImage(im, for: .normal)
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
            spinner.stopAnimating()
            spinner.isHidden = true
            controlsView.backgroundColor = .clear
            controlsView.alpha = 1
            playPauseButton.isHidden = false
            if shouldPause {
                playPauseClicked(playPauseButton!)
            }
            updatePlayPauseButton(isPlaying: !shouldPause)
        case .opening:
            controlsView.backgroundColor = .black
            controlsView.alpha = 0.65
            spinner.startAnimating()
            spinner.isHidden = false
        case .buffering:
            debugPrint("buffering")
        case .error:
            spinner.stopAnimating()
            spinner.isHidden = true
            controlsView.backgroundColor = .clear
            controlsView.alpha = 1
            playPauseButton.isHidden = false
            UiUtils.showToast(message: NSLocalizedString("Video playback error", comment: "Video playback error"))
        case .ended:
            // Update slider position and ts label
            // in case the corresponding VLCMediaPlayer event doesn't fire for whatever reason.
            videoSlider.value = 1
            currentTimeLabel.text = self.durationLabel.text
            fallthrough
        case .stopped, .paused:
            updatePlayPauseButton(isPlaying: false)
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
                NotificationCenter.default.post(name: Notification.Name(MessageViewController.kNotificationSendAttachment), object: content2)
                // Return to MessageViewController.
                self.navigationController?.popViewController(animated: true)
            }
        }
    }

    func dismissPreview() {
        self.replyPreviewDelegate?.dismissPendingMessagePreview()
    }
}
