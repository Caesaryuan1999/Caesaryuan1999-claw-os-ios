//
//  MessageBubbleDecorator.swift
//  Tinodios
//
//  Copyright © 2019 Tinode. All rights reserved.
//

import UIKit

/// Draws the stable, tail-free bubble shape from the CLAW OS Figma system.
class MessageBubbleDecorator {

    public enum Style {
        case single, last, middle, first
    }

    public static func drawDeleted(_ rect: CGRect) -> UIBezierPath {
        UIBezierPath(roundedRect: rect, cornerRadius: 15.22)
    }

    public static func draw(_ rect: CGRect, isIncoming: Bool, style: Style) -> UIBezierPath {
        UIBezierPath(roundedRect: rect, cornerRadius: 18)
    }
}
