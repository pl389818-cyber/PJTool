//
//  ScreenDrawExportService.swift
//  PJTool
//
//  Created by PJ Lee + Ai on 2026/5/7.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum ScreenDrawExportError: LocalizedError {
    case cancelled
    case renderFailed
    case bitmapInitFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return L10n.tr("legacy.key_85")
        case .renderFailed:
            return L10n.tr("legacy.key_61")
        case .bitmapInitFailed:
            return L10n.tr("legacy.key_60")
        case .pngEncodingFailed:
            return L10n.tr("legacy.png")
        }
    }
}

struct ScreenDrawExportService {
    func pickOutputURL() throws -> URL {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screen_draw_\(timestamp()).png"
        panel.directoryURL = try? PJToolOutputDirectoryPolicy.prepareScreenDrawDirectory()
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            throw ScreenDrawExportError.cancelled
        }
        PJToolOutputDirectoryPolicy.rememberScreenDrawDirectory(from: url)
        return url
    }

    func writeTransparentPNG(from image: NSImage, to outputURL: URL) throws {
        guard let tiffData = image.tiffRepresentation else {
            throw ScreenDrawExportError.renderFailed
        }
        guard let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw ScreenDrawExportError.bitmapInitFailed
        }
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenDrawExportError.pngEncodingFailed
        }
        try pngData.write(to: outputURL, options: .atomic)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
