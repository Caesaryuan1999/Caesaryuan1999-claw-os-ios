//
//  EntityTextAttachment.swift
//  Tinodios
//
//  Copyright © 2022 Tinode LLC. All rights reserved.
//

import TinodeSDK
import UIKit

public protocol EntityTextAttachmentDelegate: AnyObject {
    func action(_ action: String, payload: Any?)
}

public class EntityTextAttachment: NSTextAttachment {
    public var draftyEntityKey: Int?
    public var type: String?
    public var delegate: EntityTextAttachmentDelegate?

    // Full-message IM only. Quotes, video covers and other attachments opt out.
    var imageCanvas: ClawImageCanvas?
    var imageSourceEntity: Entity?
}

/// Immutable display geometry. It never changes the original entity or pixels.
struct ClawImageCanvas {
    enum Mode: Equatable { case proportional, longTop, unknownFit }
    let mode: Mode
    let size: CGSize

    init?(width: Int?, height: Int?, decoded: UIImage?, maximum: CGSize) {
        guard maximum.width.isFinite, maximum.height.isFinite,
              maximum.width >= 1, maximum.height >= 1 else { return nil }
        let original: CGSize?
        if let width = width, let height = height, width > 0, height > 0 {
            original = CGSize(width: width, height: height)
        } else if let decoded = decoded, decoded.size.width.isFinite, decoded.size.height.isFinite,
                  decoded.size.width > 0, decoded.size.height > 0 {
            original = decoded.size
        } else {
            original = nil
        }
        if let original = original {
            if original.height / original.width >= 3 {
                mode = .longTop
                let width = min(240, maximum.width, maximum.height * 0.75)
                size = CGSize(width: width, height: width * 4 / 3)
            } else {
                mode = .proportional
                let scale = min(1, maximum.width / original.width, maximum.height / original.height)
                size = CGSize(width: original.width * scale, height: original.height * scale)
            }
        } else {
            mode = .unknownFit
            let width = min(240, maximum.width, maximum.height * 1.5)
            size = CGSize(width: width, height: width * 2 / 3)
        }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
    }

    /// UIImage.draw handles orientation. Long images crop from y=0; other modes
    /// show the entire image with transparent, theme-inheriting letterboxing.
    func rendered(_ image: UIImage?) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let canvas = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: canvas, cornerRadius: min(12, size.width / 2)).addClip()
            guard let image = image, image.size.width > 0, image.size.height > 0,
                  image.size.width.isFinite, image.size.height.isFinite else {
                UIColor.secondarySystemFill.setFill()
                context.fill(canvas)
                return
            }
            let sx = size.width / image.size.width, sy = size.height / image.size.height
            let scale = mode == .longTop ? max(sx, sy) : min(sx, sy)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (size.width - drawn.width) / 2,
                                  y: mode == .longTop ? 0 : (size.height - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
    }
}
