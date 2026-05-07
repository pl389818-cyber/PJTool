//
//  ScreenDrawMarkStyle.swift
//  PJTool
//
//  Created by Codex on 2026/5/7.
//

import Foundation

enum ScreenDrawMarkStyle: String, CaseIterable, Identifiable {
    case rounded
    case crisp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded:
            return "圆润"
        case .crisp:
            return "利落"
        }
    }
}

