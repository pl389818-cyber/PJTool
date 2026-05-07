//
//  ScreenDrawTool.swift
//  PJTool
//
//  Created by Codex on 2026/5/7.
//

import Foundation

enum ScreenDrawTool: String, CaseIterable, Identifiable {
    case line
    case arrow
    case rectangle
    case ellipse
    case cross
    case check

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line:
            return "画线"
        case .arrow:
            return "箭头线"
        case .rectangle:
            return "方框"
        case .ellipse:
            return "圆形"
        case .cross:
            return "错"
        case .check:
            return "对"
        }
    }

    var symbolName: String {
        switch self {
        case .line:
            return "curve"
        case .arrow:
            return "arrow.up.right"
        case .rectangle:
            return "rectangle"
        case .ellipse:
            return "circle"
        case .cross:
            return "xmark"
        case .check:
            return "checkmark"
        }
    }
}
