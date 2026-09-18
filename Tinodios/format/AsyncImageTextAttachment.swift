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

    public override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        // Keep reference to text container. It will be updated if image changes.
        self.textContainer = textContainer
        return image
    }
}
