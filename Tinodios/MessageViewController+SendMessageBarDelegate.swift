//
//  MessageViewController+SendMessageBarDelegate.swift
//  Tinodios
//
//  Copyright © 2019-2025 Tinode. All rights reserved.
//

import AVFoundation
import MobileCoreServices
import MobileVLCKit
import TinodeSDK
import UIKit

extension MessageViewController: SendMessageBarDelegate {
    // Default 256K server limit. Does not account for base64 compression and overhead.
    static let kMaxInbandAttachmentSize: Int64 = 1 << 18
    // Default upload size.
    static let kMaxAttachmentSize: Int64 = 1 << 23

    func sendMessageBar(sendText: String) {
        let displayIntent = captureChatSubmissionIntent()
        interactor?.sendMessage(content: Drafty(content: sendText), displayIntent: displayIntent)
    }

    func sendMessageBar(attachment: MessageAttachmentAction) {
        switch attachment {
        case .file:
            attachFile()
        case .library:
            attachImage(source: .photoLibrary)
        case .camera:
            attachImage(source: .camera)
        }
    }
    private func attachFile() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .image])
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        self.present(documentPicker, animated: true, completion: nil)
    }

    private func attachImage(source: UIImagePickerController.SourceType) {
        guard UIImagePickerController.isSourceTypeAvailable(source) else {
            UiUtils.showToast(message: NSLocalizedString("Camera is not available", comment: "Camera unavailable error"))
            return
        }
        imagePicker?.present(source: source)
    }

    func sendMessageBar(textChangedTo text: String) {
        if self.sendTypingNotifications {
            interactor?.sendTypingNotification()
        }
    }

    func sendMessageBar(enablePeersMessaging: Bool) {
        if enablePeersMessaging {
            interactor?.enablePeersMessaging()
        }
    }

    func sendMessageBar(recordAudio action: AudioBarAction) {
        switch action {
        case .start:
            guard voiceScopeIsCurrent(), UIApplication.shared.applicationState == .active,
                  let owner = voiceOwner, topicName != nil else { return }
            if voiceRecorder == nil {
                guard let recorder = Cache.makeMediaRecorder(for: owner) else { return }
                voiceRecorder = recorder
                voiceTopicName = topicName
                recorder.delegate = self
                recorder.onRetired = { [weak self, weak recorder] in
                    guard let self = self, self.voiceRecorder === recorder else { return }
                    self.stopRecordingPlayback(discard: true)
                    self.voiceRecorder = nil
                    self.voiceTopicName = nil
                    self.sendMessageBar.resetRecordingState()
                }
            }
            guard let recorder = voiceRecorder, recorder.isCurrent, voiceTopicName == topicName else { return }
            recorder.start()
        case .stopAndSend:
            guard let recorder = voiceRecorder else { return }
            guard !recorder.deferSubmissionForRecordingCompletion() else { return }
            sendAudioAttachment(recorder: recorder)
        case .stopRecording, .pauseRecording:
            guard let recorder = voiceRecorder, voiceScopeIsCurrent() else { return }
            _ = recorder.stopForPreview()
        case .stopAndDelete:
            discardVoiceRecording()
        case .playbackStart:
            guard let recorder = voiceRecorder, recorder.isCurrent, voiceScopeIsCurrent(),
                  voiceTopicName == topicName, recorder.state == .preview,
                  let url = recorder.recordFileURL, UIApplication.shared.applicationState == .active else { return }
            if let player = recordingPlaybackPlayer,
               player.state == .ended || player.state == .stopped || player.state == .error {
                stopRecordingPlayback(discard: true)
            }
            if recordingPlaybackPlayer == nil {
                let player = VLCMediaPlayer()
                player.delegate = self
                player.media = VLCMedia(url: url)
                recordingPlaybackPlayer = player
            }
            guard let player = recordingPlaybackPlayer else { return }
            if let current = currentAudioPlayer, current !== player { current.pause() }
            currentAudioPlayer = player
            // A paused player resumes the same media/time. UI changes only after
            // an observed playing state/time callback from this exact player.
            player.play()
        case .playbackPause:
            guard voiceScopeIsCurrent() else { return }
            stopRecordingPlayback(discard: false)
        default:
            break
        }
    }
}

extension MessageViewController: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true, completion: nil)
        // NOTE(Apple's bug, Tinode's hack):
        // When UIDocumentPickerDelegate is dismissed it keeps the keyboard window
        // active. If then we show a toast, the keyboard window is counted "last"
        // in the window stack and we attempt to present the toast over it.
        // In reality, though, the window turns out at the bottom of the stack
        // and thus the toast ends up covered by the key window and never presented
        // to the user.
        // sendMessageBar.becomeFirstResponder() "fixes" the window stack.
        // This is UGLY because it pops the keyboard. Find a better solution.
        (self.inputAccessoryView as? SendMessageBar)?.inputField.becomeFirstResponder()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // Convert file to Data and attach to message
        guard let url = urls.first else { return }
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            // See comment in documentPickerWasCancelled().
            (self.inputAccessoryView as? SendMessageBar)?.inputField.becomeFirstResponder()

            let maxAttachmentSize = Cache.tinode.getServerLimit(for: Tinode.kMaxFileUploadSize, withDefault: MessageViewController.kMaxAttachmentSize)
            if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > maxAttachmentSize {
                UiUtils.showToast(message: String(format: NSLocalizedString("The file size exceeds the limit %@", comment: "Error message"), UiUtils.bytesToHumanSize(maxAttachmentSize)))
                return
            }

            let bits = try ClawMediaFiles.read(url)
            let fname = url.lastPathComponent
            var mimeType = Utils.mimeForUrl(url: url)
            if mimeType == "application/json" {
                // Replace JSON mime type with 'application/octet-stream' to avoid collision with Drafty form responses.
                // Remove this code in 2026.
                mimeType = "application/octet-stream"
            }
            guard bits.count <= maxAttachmentSize else {
                UiUtils.showToast(message: String(format: NSLocalizedString("The file size exceeds the limit %@", comment: "Error message"), UiUtils.bytesToHumanSize(maxAttachmentSize)))
                return
            }

            let pendingPreview = (self.inputAccessoryView as! SendMessageBar).pendingPreviewText
            let content = FilePreviewContent(
                data: bits,
                refUrl: url,
                fileName: fname,
                contentType: mimeType,
                size: bits.count,
                destinationName: topic?.pub?.fn,
                pendingMessagePreview: pendingPreview
            )
            performSegue(withIdentifier: "ShowFilePreview", sender: content)
        } catch {
            Cache.log.error("attachment_read_failed")
            UiUtils.showToast(message: ClawMediaFiles.readRecovery)
        }
    }
}

extension MessageViewController: ImagePickerDelegate {
    func didSelect(media: ImagePickerMediaType?) {
        guard let media = media else { return }
        switch media {
        case .image(let image, let mime, let fname):
            guard let image = image else { return }

            let width = Int(image.size.width * image.scale)
            let height = Int(image.size.height * image.scale)

            let pendingPreview = (self.inputAccessoryView as! SendMessageBar).pendingPreviewText
            let content = ImagePreviewContent(
                imgContent: ImagePreviewContent.ImageContent.uiimage(image),
                caption: nil,
                fileName: fname,
                contentType: mime,
                size: 0,
                width: width,
                height: height,
                pendingMessagePreview: pendingPreview)

            performSegue(withIdentifier: "ShowImagePreview", sender: content)
        case .video(let videoUrl, let mime, let fname):
            guard let videoUrl = videoUrl else { return }
            let pendingPreview = (self.inputAccessoryView as! SendMessageBar).pendingPreviewText
            let content = VideoPreviewContent(
                videoSrc: .local(videoUrl, nil),
                duration: 0,
                fileName: fname,
                contentType: mime,
                size: 0,
                width: nil,
                height: nil, caption: nil,
                pendingMessagePreview: pendingPreview)

            performSegue(withIdentifier: "ShowVideoPreview", sender: content)
        }
    }
}

extension MessageViewController: MediaRecorderDelegate {
    func didStartRecording(recorder: MediaRecorder) {
        voiceUI(recorder) { sendMessageBar.recordingDidStart() }
    }

    func didFinishRecording(recorder: MediaRecorder, url: URL?, duration: TimeInterval) {
        voiceUI(recorder) {
            sendMessageBar.recordingDidStop()
            sendMessageBar.audioPlaybackPreview(recorder.preview, duration: duration)
            if voicePausedNotice { sendMessageBar.showInterruptedRecordingPreview() }
            if recorder.reachedDurationLimit {
                UiUtils.showToast(message: "已达60秒，试听后发送")
            }
        }
    }

    func didUpdateRecording(recorder: MediaRecorder, amplitude: Float, atTime: TimeInterval) {
        voiceUI(recorder) {
            sendMessageBar.audioUpdateAmplitude(amplitude: amplitude, atTime: atTime)
        }
    }

    func didFailRecording(recorder: MediaRecorder, _ error: Error) {
        voiceUI(recorder) {
            sendMessageBar.resetRecordingState()
            if error as? MediaRecorderError != .cancelledByUser {
                UiUtils.showToast(message: "录音未能开始或已中断，请重新录制。")
            }
        }
    }

    func didUpdateRecordingPermission(recorder: MediaRecorder, event: MediaRecorderPermissionEvent) {
        voiceUI(recorder) {
            sendMessageBar.resetRecordingState()
            switch event {
            case .requesting: break
            case .granted: UiUtils.showToast(message: "已允许使用麦克风，请再次按住录音")
            case .denied: UiUtils.showToast(message: "未开启麦克风权限，可在系统设置中开启")
            }
        }
    }
}

extension MessageViewController: VLCMediaPlayerDelegate {
    private func updateRecordingPlayback(_ notification: Notification) {
        let update = { [weak self] in
            guard let self = self, let player = notification.object as? VLCMediaPlayer,
                  self.recordingPlaybackPlayer === player, let recorder = self.voiceRecorder else { return }
            self.voiceUI(recorder) {
                if let time = player.time.value {
                    self.sendMessageBar.audioPlaybackTime(TimeInterval(truncating: time) / 1000)
                }
                switch player.state {
                case .playing:
                    if player.isPlaying {
                        self.sendMessageBar.showAudioBar(.longPlayback)
                        self.sendMessageBar.audioPlaybackAction(.playbackStart)
                    }
                case .error:
                    self.sendMessageBar.showAudioBar(.longPaused)
                    self.sendMessageBar.audioPlaybackAction(.playbackReset)
                    UiUtils.showToast(message: "无法试听录音，可重试或放弃后重新录制。")
                case .paused:
                    self.sendMessageBar.showAudioBar(.longPaused)
                    self.sendMessageBar.audioPlaybackAction(.playbackPause)
                case .stopped, .ended:
                    self.sendMessageBar.showAudioBar(.longPaused)
                    self.sendMessageBar.audioPlaybackAction(.playbackReset)
                default: break
                }
            }
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    func mediaPlayerStateChanged(_ notification: Notification) { updateRecordingPlayback(notification) }
    func mediaPlayerTimeChanged(_ notification: Notification) { updateRecordingPlayback(notification) }
}
