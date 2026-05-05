//
//  VideoCuttingExportService.swift
//  PJTool
//
//  Created by Codex on 2026/5/4.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct VideoCuttingExportService {
    func pickOutputURL(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = suggestedName
        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
