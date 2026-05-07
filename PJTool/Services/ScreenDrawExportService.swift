//
//  ScreenDrawExportService.swift
//  PJTool
//
//  Created by Codex on 2026/5/7.
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
            return "已取消导出。"
        case .renderFailed:
            return "导出失败：无法渲染当前画布。"
        case .bitmapInitFailed:
            return "导出失败：无法创建位图数据。"
        case .pngEncodingFailed:
            return "导出失败：PNG 编码失败。"
        }
    }
}

struct ScreenDrawExportService {
    func pickOutputURL() throws -> URL {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screen_draw_\(timestamp()).png"
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            throw ScreenDrawExportError.cancelled
        }
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

