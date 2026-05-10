//
//  ScreenDrawSessionStore.swift
//  PJTool
//
//  Created by Codex on 2026/5/7.
//

import AppKit
import Combine
import QuartzCore
import Foundation

@MainActor
final class ScreenDrawSessionStore: ObservableObject {
    @Published var activeTool: ScreenDrawTool = .line
    @Published var selectedColorPreset: DrawColorPreset = .one
    @Published var handDrawnIntensity: CGFloat = 0.58
    @Published var markStyle: ScreenDrawMarkStyle = .rounded
    @Published var dismissalAnimationMode: DrawDismissalAnimationMode = .random
    @Published var dismissalAnimationFixedStyle: DrawDismissalAnimationStyle = .shatterDrop
    @Published private(set) var isDismissingWithAnimation = false
    @Published private(set) var activeDismissalStyle: DrawDismissalAnimationStyle?
    @Published private(set) var dismissalAnimationStartedAt: CFTimeInterval = 0
    @Published private(set) var shapes: [ScreenDrawShape] = []
    @Published private(set) var previewShape: ScreenDrawShape?

    var onSessionEvent: ((String) -> Void)?

    private let defaultLineWidth: CGFloat = 2
    private var lastDismissalStyle: DrawDismissalAnimationStyle?

    func beginInteraction(at point: CGPoint) {
        guard !isDismissingWithAnimation else { return }
        guard let shapeType = shapeType(for: activeTool) else { return }
        previewShape = ScreenDrawShape(
            type: shapeType,
            startPoint: point,
            endPoint: point,
            points: [point],
            colorPreset: selectedColorPreset,
            lineWidth: defaultLineWidth
        )
    }

    func continueInteraction(at point: CGPoint) {
        guard !isDismissingWithAnimation else { return }
        guard var shape = previewShape else {
            beginInteraction(at: point)
            return
        }
        shape.endPoint = point
        if shape.type == .line || shape.type == .arrow {
            appendSamplePoint(point, to: &shape.points)
        }
        previewShape = shape
    }

    func endInteraction(at point: CGPoint) {
        guard !isDismissingWithAnimation else { return }
        guard var shape = previewShape else { return }
        shape.endPoint = point
        if shape.type == .line || shape.type == .arrow {
            appendSamplePoint(point, to: &shape.points)
            if shape.points.count == 1 {
                shape.points.append(shape.points[0])
            }
        }
        if shouldCommitShape(shape) {
            shapes.append(shape)
            onSessionEvent?(
                L10n.f(
                    "fmt.draw.shape_added",
                    shape.type.tool.title,
                    shape.colorPreset.shortLabel
                )
            )
        }
        previewShape = nil
    }

    func clearCanvas() {
        guard !isDismissingWithAnimation else { return }
        if shapes.isEmpty {
            onSessionEvent?(L10n.tr("legacy.key_182"))
            return
        }
        shapes.removeAll(keepingCapacity: false)
        previewShape = nil
        onSessionEvent?(L10n.tr("legacy.key_181"))
    }

    func clearCanvasSilently() {
        shapes.removeAll(keepingCapacity: false)
        previewShape = nil
    }

    func resetForNewSession() {
        shapes.removeAll(keepingCapacity: false)
        previewShape = nil
        isDismissingWithAnimation = false
        activeDismissalStyle = nil
        dismissalAnimationStartedAt = 0
    }

    func cancelCurrentInteraction() {
        previewShape = nil
    }

    var hasDrawableContent: Bool {
        !shapes.isEmpty || previewShape != nil
    }

    func beginDismissalAnimation() -> DrawDismissalAnimationStyle? {
        guard hasDrawableContent else { return nil }
        guard !isDismissingWithAnimation else { return activeDismissalStyle }

        let style = resolvedDismissalStyle()
        isDismissingWithAnimation = true
        activeDismissalStyle = style
        dismissalAnimationStartedAt = CACurrentMediaTime()
        previewShape = nil
        return style
    }

    func completeDismissalAnimation(clearCanvas: Bool) {
        if clearCanvas {
            clearCanvasSilently()
            onSessionEvent?(L10n.tr("legacy.key_181"))
        }
        isDismissingWithAnimation = false
        activeDismissalStyle = nil
        dismissalAnimationStartedAt = 0
    }

    private func shapeType(for tool: ScreenDrawTool) -> ScreenDrawShapeType? {
        switch tool {
        case .line:
            return .line
        case .arrow:
            return .arrow
        case .rectangle:
            return .rectangle
        case .ellipse:
            return .ellipse
        case .cross:
            return .cross
        case .check:
            return .check
        }
    }

    private func shouldCommitShape(_ shape: ScreenDrawShape) -> Bool {
        if shape.type == .line || shape.type == .arrow {
            let sampled = shape.points
            if sampled.count >= 2 {
                return sampledTotalLength(sampled) >= 2.5
            }
        }
        let dx = shape.endPoint.x - shape.startPoint.x
        let dy = shape.endPoint.y - shape.startPoint.y
        return hypot(dx, dy) >= 2.5
    }

    private func appendSamplePoint(_ point: CGPoint, to points: inout [CGPoint]) {
        if let last = points.last {
            let distance = hypot(point.x - last.x, point.y - last.y)
            if distance < 0.75 {
                return
            }
        }
        points.append(point)
    }

    private func sampledTotalLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for index in 1 ..< points.count {
            let previous = points[index - 1]
            let current = points[index]
            total += hypot(current.x - previous.x, current.y - previous.y)
        }
        return total
    }

    private func resolvedDismissalStyle() -> DrawDismissalAnimationStyle {
        switch dismissalAnimationMode {
        case .fixed:
            lastDismissalStyle = dismissalAnimationFixedStyle
            return dismissalAnimationFixedStyle
        case .random:
            let all = DrawDismissalAnimationStyle.allCases
            if all.count <= 1 {
                let fallback = dismissalAnimationFixedStyle
                lastDismissalStyle = fallback
                return fallback
            }

            var candidate = all.randomElement() ?? dismissalAnimationFixedStyle
            if candidate == lastDismissalStyle, let different = all.first(where: { $0 != candidate }) {
                candidate = different
            }
            lastDismissalStyle = candidate
            return candidate
        }
    }
}
