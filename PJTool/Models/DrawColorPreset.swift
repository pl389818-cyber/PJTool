//
//  DrawColorPreset.swift
//  PJTool
//
//  Created by Codex on 2026/5/7.
//

import AppKit
import Foundation

enum DrawColorPreset: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .one:
            return "1 红"
        case .two:
            return "2 黄"
        case .three:
            return "3 绿"
        case .four:
            return "4 蓝"
        case .five:
            return "5 黑"
        }
    }

    var shortLabel: String {
        "\(rawValue)"
    }

    var color: NSColor {
        switch self {
        case .one:
            return .systemRed
        case .two:
            return .systemYellow
        case .three:
            return .systemGreen
        case .four:
            return .systemBlue
        case .five:
            return .black
        }
    }
}
