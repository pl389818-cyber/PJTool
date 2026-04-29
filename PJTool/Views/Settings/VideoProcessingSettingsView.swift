//
//  VideoProcessingSettingsView.swift
//  PJTool
//
//  Created by Codex on 2026/4/30.
//

import AppKit
import CoreMedia
import SwiftUI
import UniformTypeIdentifiers

struct VideoProcessingSettingsView: View {
    @ObservedObject var appCoordinator: AppCoordinator

    @Binding var baseStitchURL: URL?
    @Binding var stitchInsertTimeText: String
    @Binding var stitchMuteImportedAudio: Bool
    @Binding var stitchOutputURL: URL?

    @Binding var trimSourceURL: URL?
    @Binding var cutStartText: String
    @Binding var cutEndText: String
    @Binding var cutRanges: [CutRange]
    @Binding var trimOutputURL: URL?

    @Binding var validationSummary: String
    @Binding var validationReportURL: URL?

    let trimEngine: TrimExportEngine
    let validationService: ValidationService

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("视频处理", subtitle: "拼接、剪切、导出与验证")

            stitchCard
            trimCard
            validationCard
        }
    }

    private var stitchCard: some View {
        card {
            Text("导入视频拼接")
                .font(.headline)

            HStack(spacing: 12) {
                Button("选择主轨视频") {
                    if let url = pickVideoFile() { baseStitchURL = url }
                }
                Button("使用最近录屏成片") {
                    baseStitchURL = appCoordinator.recorder.lastOutputURL
                }
            }

            Text("主轨：\(baseStitchURL?.lastPathComponent ?? "未选择")")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("插入时间(秒)", text: $stitchInsertTimeText)
                    .frame(width: 140)
                Toggle("导入片段静音", isOn: $stitchMuteImportedAudio)
                Button("导入拼接片段") { importClipForStitch() }
            }

            if appCoordinator.importEngine.layers.isEmpty {
                Text("暂无导入片段")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appCoordinator.importEngine.layers) { layer in
                    HStack {
                        Text("\(layer.assetURL.lastPathComponent) @ \(layer.insertTime.seconds, specifier: "%.2f")s")
                        Spacer()
                        Text(layer.mute ? "静音" : "保留音频")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("删除") { appCoordinator.importEngine.removeClip(id: layer.id) }
                    }
                    .font(.footnote)
                }
            }

            HStack(spacing: 12) {
                Button("导出拼接") { exportStitch() }
                    .disabled(baseStitchURL == nil || appCoordinator.importEngine.layers.isEmpty)
                if let stitchOutputURL {
                    Button("打开拼接结果") { NSWorkspace.shared.activateFileViewerSelecting([stitchOutputURL]) }
                }
            }

            Text(appCoordinator.importEngine.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var trimCard: some View {
        card {
            Text("多段剪切")
                .font(.headline)

            HStack(spacing: 12) {
                Button("选择剪切源") {
                    if let url = pickVideoFile() { trimSourceURL = url }
                }
                Button("使用拼接结果") {
                    trimSourceURL = stitchOutputURL ?? appCoordinator.recorder.lastOutputURL
                }
            }

            Text("剪切源：\(trimSourceURL?.lastPathComponent ?? "未选择")")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("删除开始(秒)", text: $cutStartText).frame(width: 120)
                TextField("删除结束(秒)", text: $cutEndText).frame(width: 120)
                Button("添加删除段") { addCutRange() }
            }

            if cutRanges.isEmpty {
                Text("暂无删除段")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cutRanges) { range in
                    HStack {
                        Text("\(range.start.seconds, specifier: "%.2f")s - \(range.end.seconds, specifier: "%.2f")s")
                        Spacer()
                        Button("删除") {
                            cutRanges.removeAll { $0.id == range.id }
                        }
                    }
                    .font(.footnote)
                }
            }

            HStack(spacing: 12) {
                Button("导出剪切") { exportTrim() }
                    .disabled(trimSourceURL == nil || cutRanges.isEmpty)
                if let trimOutputURL {
                    Button("打开剪切结果") { NSWorkspace.shared.activateFileViewerSelecting([trimOutputURL]) }
                }
            }
        }
    }

    private var validationCard: some View {
        card {
            Text("验证报告")
                .font(.headline)

            Button("生成 ValidationReport") { generateValidationReport() }

            Text("结果：\(validationSummary)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let validationReportURL {
                Text("报告文件：\(validationReportURL.path)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func importClipForStitch() {
        guard let url = pickVideoFile() else { return }
        let insert = Double(stitchInsertTimeText) ?? 0
        appCoordinator.importEngine.addClip(url: url, insertTimeSeconds: max(0, insert), mute: stitchMuteImportedAudio)
    }

    private func exportStitch() {
        guard let baseStitchURL else { return }
        Task {
            do {
                let outputURL = try makeOutputURL(prefix: "Stitch")
                stitchOutputURL = try await appCoordinator.importEngine.export(baseURL: baseStitchURL, outputURL: outputURL)
                trimSourceURL = stitchOutputURL
            } catch {
                appCoordinator.importEngine.reportExportFailure(error)
            }
        }
    }

    private func addCutRange() {
        guard let start = Double(cutStartText), let end = Double(cutEndText) else { return }
        let range = CutRange(
            start: CMTime(seconds: max(0, start), preferredTimescale: 600),
            end: CMTime(seconds: max(0, end), preferredTimescale: 600)
        )
        cutRanges.append(range.normalized)
    }

    private func exportTrim() {
        guard let trimSourceURL else { return }
        let project = TrimProject(sourceURL: trimSourceURL, deleteRanges: cutRanges)
        Task {
            do {
                let outputURL = try makeOutputURL(prefix: "Trim")
                trimOutputURL = try await trimEngine.export(project: project, outputURL: outputURL)
            } catch {
                validationSummary = "剪切失败：\(error.localizedDescription)"
            }
        }
    }

    private func generateValidationReport() {
        let output = trimOutputURL ?? stitchOutputURL ?? appCoordinator.recorder.lastOutputURL
        let report = validationService.makeReport(
            mergedOutputURL: output,
            cameraSources: appCoordinator.pipPreviewRuntime.sources,
            audioSources: appCoordinator.audioEngine.sources
        )
        do {
            let url = try validationService.persist(report: report)
            validationReportURL = url
            validationSummary = report.summary
        } catch {
            validationSummary = "报告写入失败：\(error.localizedDescription)"
        }
    }

    private func pickVideoFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    private func makeOutputURL(prefix: String) throws -> URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("PJTool", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return folder.appendingPathComponent("\(prefix)-\(formatter.string(from: Date())).mp4")
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}
