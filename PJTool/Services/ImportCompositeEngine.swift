//
//  ImportCompositeEngine.swift
//  PJTool
//
//  Created by Codex on 2026/4/29.
//

import Combine
import CoreMedia
import Foundation

@MainActor
final class ImportCompositeEngine: ObservableObject {
    @Published private(set) var layers: [CompositionLayer] = []
    @Published private(set) var statusMessage: String = "未导入片段"

    private let compositionEngine = CompositionExportEngine()

    func addClip(url: URL, insertTimeSeconds: Double, mute: Bool) {
        let insertTime = CMTime(seconds: max(0, insertTimeSeconds), preferredTimescale: 600)
        let layer = CompositionLayer(assetURL: url, insertTime: insertTime, mute: mute)
        layers.append(layer)
        layers.sort { $0.insertTime < $1.insertTime }
        statusMessage = "已导入 \(layers.count) 个拼接片段"
    }

    func removeClip(id: UUID) {
        layers.removeAll { $0.id == id }
        statusMessage = layers.isEmpty ? "未导入片段" : "已导入 \(layers.count) 个拼接片段"
    }

    func clear() {
        layers.removeAll()
        statusMessage = "未导入片段"
    }

    func export(
        baseURL: URL,
        outputURL: URL
    ) async throws -> URL {
        let project = CompositionProject(baseAssetURL: baseURL, layers: layers)
        let result = try await compositionEngine.stitch(project: project, outputURL: outputURL)
        statusMessage = "拼接导出完成"
        return result
    }

    func reportExportFailure(_ error: Error) {
        statusMessage = "拼接导出失败：\(error.localizedDescription)"
    }
}
