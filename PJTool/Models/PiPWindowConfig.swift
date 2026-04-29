//
//  PiPWindowConfig.swift
//  PJTool
//
//  Created by Codex on 2026/4/30.
//

import Foundation

struct PiPWindowConfig: Equatable, Codable {
    var isAlwaysOnTop: Bool
    var windowTitle: String

    static let defaultWindowTitle = "PiP 摄像"

    var resolvedWindowTitle: String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultWindowTitle : trimmed
    }

    static let `default` = PiPWindowConfig(
        isAlwaysOnTop: true,
        windowTitle: defaultWindowTitle
    )
}
