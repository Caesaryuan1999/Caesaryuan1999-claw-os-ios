//
//  AsyncTextAttachment.swift
//
//  Copyright © 2020-2022 Tinode LLC. All rights reserved.
//

import TinodeSDK
import UIKit

/// An image text attachment which gets updated after loading an image from URL.
public class AsyncImageTextAttachment: EntityTextAttachment {
    /// Container to be notified when the image is updated: successfully fetched or failed.
    private weak var textContainer: NSTextContainer?

    /// Source of the image
    public var url: URL {
        didSet { imageSlot.invalidate(); imageLoad?.cancel(); imageLoad = nil }
    }
    private let imageContext: ClawOwnedImageContext?
    private let imageLoader: ClawOwnedImageLoader
    private let imageSlot = ClawOwnedImageSlot()
    private var imageLoad: ClawOwnedImageLoad?
    private var imageError: UIImage?

    /// Postprocessing callback after the image's been downloaded
    private var postprocessing: ((UIImage) -> UIImage?)?

    /// Designated initializer
    public convenience init(url: URL, afterDownloaded: ((UIImage) -> UIImage?)? = nil) {
        self.init(url: url, afterDownloaded: afterDownloaded, context: Utils.ownedImageContext(), loader: .shared)
    }

    init(url: URL, afterDownloaded: ((UIImage) -> UIImage?)? = nil,
         context: ClawOwnedImageContext?, loader: ClawOwnedImageLoader) {
        self.imageContext = context
        self.imageLoader = loader
        self.url = url
        self.postprocessing = afterDownloaded

        super.init(data: nil, ofType: nil)
        self.type = "image"
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }

    deinit { imageLoad?.cancel() }

    public func startDownload(onError errorImage: UIImage) {
        if imageCanvas != nil {
            if !Thread.isMainThread {
                let ticket = imageSlot.invalidate()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.imageSlot.accepts(ticket) else { return }
                    self.startFullImageDownload(onError: errorImage)
                }
            } else {
                startFullImageDownload(onError: errorImage)
            }
            return
        }
        let ticket = imageSlot.invalidate()
        imageLoad?.cancel()
        let requestURL = url
        guard let context = imageContext else { return }
        imageLoad = imageLoader.load(from: requestURL, context: context) { [weak self] result in
            guard let self = self else { return }
            context.withCurrent {
                guard self.imageSlot.accepts(ticket), self.url == requestURL else { return }
                switch result {
                case .success(let image):
                    if let process = self.postprocessing {
                        self.image = process(image) ?? errorImage
                    } else {
                        self.image = image
                    }
                case .failure:
                    self.image = errorImage
                    Log.default.info("inline_image_load_failed")
                }
                let length = self.textContainer?.layoutManager?.textStorage?.length
                self.textContainer?.layoutManager?.invalidateDisplay(
                    forCharacterRange: NSRange(location: 0, length: length ?? 1))
            }
        }
    }

    override var canRetryImage: Bool {
        imageCanvas != nil && imageState == .failed && imageError != nil && originalImageSourceIsCurrent
    }

    private var originalImageSourceIsCurrent: Bool {
        guard let context = imageContext, context.isCurrent,
              let reference = imageSourceEntity?.data?["ref"]?.asString() else { return false }
        return context.resourceURL(from: reference) == url
    }

    /// Explicit retry keeps this attachment's original context and URL. The page
    /// validates the entity and consumer binding again before entering here.
    @discardableResult
    func retryImage() -> Bool {
        guard Thread.isMainThread, canRetryImage, imageConsumerIsCurrent,
              let error = imageError else { return false }
        startFullImageDownload(onError: error)
        return true
    }

    override func cancelImageLoad() {
        imageSlot.invalidate()
        imageLoad?.cancel(); imageLoad = nil
        if imageState == .loading { displayImageState(.failed) }
    }

    private func startFullImageDownload(onError errorImage: UIImage) {
        precondition(Thread.isMainThread)
        imageError = errorImage
        let ticket = imageSlot.invalidate()
        imageLoad?.cancel(); imageLoad = nil
        guard let context = imageContext, originalImageSourceIsCurrent, imageConsumerIsCurrent else {
            displayImageState(.unavailable)
            return
        }
        displayImageState(.loading)
        guard imageSlot.accepts(ticket), context.isCurrent, imageConsumerIsCurrent else { return }
        let requestURL = url
        imageLoad = imageLoader.load(from: requestURL, context: context) { [weak self] result in
            guard let self = self, self.imageSlot.accepts(ticket), self.url == requestURL,
                  self.imageConsumerIsCurrent else { return }
            // Drawing and UI callbacks stay outside the SDK/Cache gate.
            guard context.isCurrent else { self.displayImageState(.unavailable); return }
            let rendered: UIImage?
            switch result {
            case .success(let image): rendered = self.postprocessing?(image) ?? image
            case .failure: rendered = nil
            }
            let applied = context.withCurrent { () -> Bool in
                guard self.imageSlot.accepts(ticket), self.url == requestURL else { return false }
                self.image = rendered ?? errorImage
                return true
            } ?? false
            guard applied, self.imageConsumerIsCurrent, context.isCurrent else { return }
            self.imageLoad = nil
            self.displayImageState(rendered == nil ? .failed : .ready)
            let length = self.textContainer?.layoutManager?.textStorage?.length ?? 0
            if length > 0 {
                self.textContainer?.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length))
            }
        }
    }

    public override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        // Keep reference to text container. It will be updated if image changes.
        self.textContainer = textContainer
        return image
    }
}
