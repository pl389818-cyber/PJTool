//
//  ScreenDrawSessionStore.swift
//  PJTool
//
//  Created by Codex on 2026/5/7.
//

import AppKit
import Combine
import Foundation

@MainActor
final class ScreenDrawSessionStore: ObservableObject {
    @Published var activeTool: ScreenDrawTool = .line
    @Published var selectedColorPreset: DrawColorPreset = .one
    @Published var handDrawnIntensity: CGFloat = 0.58
    @Published var markStyle: ScreenDrawMarkStyle = .rounded
    @Published private(set) var shapes: [ScreenDrawShape] = []
    @Published private(set) var previewShape: ScreenDrawShape?

    var onSessionEvent: ((String) -> Void)?

    private let defaultLineWidth: CGFloat = 2

    func beginInteraction(at point: CGPoint) {
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
            onSessionEvent?("已添加\(shape.type.tool.title)（颜色 \(shape.colorPreset.shortLabel)）")
        }
        previewShape = nil
    }

    func clearCanvas() {
        if shapes.isEmpty {
            onSessionEvent?("画布已经是空白。")
            return
        }
        shapes.removeAll(keepingCapacity: false)
        previewShape = nil
        onSessionEvent?("画布已清空。")
    }

    func resetForNewSession() {
        shapes.removeAll(keepingCapacity: false)
        previewShape = nil
    }

    func cancelCurrentInteraction() {
        previewShape = nil
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
}
