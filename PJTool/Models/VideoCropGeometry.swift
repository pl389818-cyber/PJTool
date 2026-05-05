//
//  VideoCropGeometry.swift
//  PJTool
//
//  Created by Codex on 2026/5/5.
//

import CoreGraphics
import Foundation

enum VideoCropGeometry {
    static func clampNormalizedRect(_ rect: CGRect) -> CGRect {
        var next = rect.standardized
        next.size.width = min(1, max(0.0001, next.width))
        next.size.height = min(1, max(0.0001, next.height))
        if next.minX < 0 {
            next.origin.x = 0
        }
        if next.minY < 0 {
            next.origin.y = 0
        }
        if next.maxX > 1 {
            next.origin.x = 1 - next.width
        }
        if next.maxY > 1 {
            next.origin.y = 1 - next.height
        }
        return next
    }

    static func normalizeMinSize(
        minPoints: CGSize,
        videoDisplaySize: CGSize
    ) -> CGSize {
        guard videoDisplaySize.width > 1, videoDisplaySize.height > 1 else {
            return CGSize(width: 0.1, height: 0.1)
        }
        return CGSize(
            width: min(1, max(0.0001, minPoints.width / videoDisplaySize.width)),
            height: min(1, max(0.0001, minPoints.height / videoDisplaySize.height))
        )
    }

    static func aspectFitRect(
        contentSize: CGSize,
        boundingSize: CGSize
    ) -> CGRect {
        guard contentSize.width > 0,
              contentSize.height > 0,
              boundingSize.width > 0,
              boundingSize.height > 0 else {
            return CGRect(origin: .zero, size: boundingSize)
        }

        let scale = min(boundingSize.width / contentSize.width, boundingSize.height / contentSize.height)
        let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        let x = (boundingSize.width - size.width) / 2.0
        let y = (boundingSize.height - size.height) / 2.0
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    static func enforceMinSize(
        _ rect: CGRect,
        minSize: CGSize
    ) -> CGRect {
        var next = rect.standardized
        next.size.width = max(next.width, minSize.width)
        next.size.height = max(next.height, minSize.height)
        return clampNormalizedRect(next)
    }

    static func adjustedRectForAspect(
        rect: CGRect,
        targetRatio: CGFloat?,
        minSize: CGSize
    ) -> CGRect {
        guard let targetRatio, targetRatio > 0 else {
            return enforceMinSize(rect, minSize: minSize)
        }

        var next = rect.standardized
        let center = CGPoint(x: next.midX, y: next.midY)

        var width = max(next.width, minSize.width)
        var height = width / targetRatio
        if height < minSize.height {
            height = minSize.height
            width = height * targetRatio
        }

        if width > 1 {
            width = 1
            height = width / targetRatio
        }
        if height > 1 {
            height = 1
            width = height * targetRatio
        }

        next = CGRect(
            x: center.x - width / 2.0,
            y: center.y - height / 2.0,
            width: width,
            height: height
        )

        return clampNormalizedRect(next)
    }

    static func applyDrag(
        startRect: CGRect,
        translation: CGSize,
        handle: VideoCropHandle,
        displaySize: CGSize,
        lockedAspectRatio: CGFloat?,
        minSize: CGSize
    ) -> CGRect {
        guard displaySize.width > 0, displaySize.height > 0 else { return startRect }
        let dx = translation.width / displaySize.width
        let dy = translation.height / displaySize.height

        var rect = startRect.standardized
        let initialCenter = CGPoint(x: rect.midX, y: rect.midY)

        switch handle {
        case .move:
            rect.origin.x += dx
            rect.origin.y += dy
        case .left:
            rect.origin.x += dx
            rect.size.width -= dx
        case .right:
            rect.size.width += dx
        case .top:
            rect.origin.y += dy
            rect.size.height -= dy
        case .bottom:
            rect.size.height += dy
        case .topLeft:
            rect.origin.x += dx
            rect.size.width -= dx
            rect.origin.y += dy
            rect.size.height -= dy
        case .topRight:
            rect.size.width += dx
            rect.origin.y += dy
            rect.size.height -= dy
        case .bottomLeft:
            rect.origin.x += dx
            rect.size.width -= dx
            rect.size.height += dy
        case .bottomRight:
            rect.size.width += dx
            rect.size.height += dy
        }

        rect = rect.standardized
        rect = enforceMinSize(rect, minSize: minSize)

        if let lockedAspectRatio, lockedAspectRatio > 0, handle != .move {
            let anchor = anchorPoint(for: handle, rect: startRect)
            rect = resizeWithAspect(rect: rect, anchor: anchor, aspectRatio: lockedAspectRatio, minSize: minSize)
        }

        rect = clampNormalizedRect(rect)

        if handle == .move {
            return rect
        }

        if let lockedAspectRatio, lockedAspectRatio > 0 {
            return fitRectKeepingCenter(rect: rect, center: initialCenter, aspectRatio: lockedAspectRatio, minSize: minSize)
        }
        return rect
    }

    static func fitRectKeepingCenter(
        rect: CGRect,
        center: CGPoint,
        aspectRatio: CGFloat,
        minSize: CGSize
    ) -> CGRect {
        var width = max(rect.width, minSize.width)
        var height = width / aspectRatio
        if height < minSize.height {
            height = minSize.height
            width = height * aspectRatio
        }

        if width > 1 {
            width = 1
            height = width / aspectRatio
        }
        if height > 1 {
            height = 1
            width = height * aspectRatio
        }

        let next = CGRect(
            x: center.x - width / 2.0,
            y: center.y - height / 2.0,
            width: width,
            height: height
        )
        return clampNormalizedRect(next)
    }

    private static func resizeWithAspect(
        rect: CGRect,
        anchor: CGPoint,
        aspectRatio: CGFloat,
        minSize: CGSize
    ) -> CGRect {
        var width = max(rect.width, minSize.width)
        var height = width / aspectRatio
        if height < minSize.height {
            height = minSize.height
            width = height * aspectRatio
        }

        var next = CGRect(origin: .zero, size: CGSize(width: width, height: height))

        if anchor.x <= rect.minX + 0.0001 {
            next.origin.x = anchor.x
        } else if anchor.x >= rect.maxX - 0.0001 {
            next.origin.x = anchor.x - width
        } else {
            next.origin.x = anchor.x - width / 2.0
        }

        if anchor.y <= rect.minY + 0.0001 {
            next.origin.y = anchor.y
        } else if anchor.y >= rect.maxY - 0.0001 {
            next.origin.y = anchor.y - height
        } else {
            next.origin.y = anchor.y - height / 2.0
        }

        return clampNormalizedRect(next)
    }

    private static func anchorPoint(for handle: VideoCropHandle, rect: CGRect) -> CGPoint {
        switch handle {
        case .left:
            return CGPoint(x: rect.maxX, y: rect.midY)
        case .right:
            return CGPoint(x: rect.minX, y: rect.midY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.minY)
        case .topLeft:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        case .topRight:
            return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomLeft:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .move:
            return CGPoint(x: rect.midX, y: rect.midY)
        }
    }
}
