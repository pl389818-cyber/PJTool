//
//  ValidationService.swift
//  PJTool
//
//  Created by Codex on 2026/4/29.
//

import AVFoundation
import Foundation

final class ValidationService {
    func makeReport(
        mergedOutputURL: URL?,
        cameraSources: [CameraSource],
        audioSources: [AudioInputSource]
    ) -> ValidationReport {
        var items: [ValidationItem] = []

        if let mergedOutputURL,
           FileManager.default.fileExists(atPath: mergedOutputURL.path) {
            items.append(
                ValidationItem(
                    name: "导出文件存在",
                    status: .pass,
                    detail: mergedOutputURL.path
                )
            )

            let inspection = inspectAsset(at: mergedOutputURL)
            if inspection.videoTrackCount > 0 {
                items.append(
                    ValidationItem(
                        name: "导出视频轨存在",
                        status: .pass,
                        detail: "videoTracks=\(inspection.videoTrackCount)"
                    )
                )
            } else {
                items.append(
                    ValidationItem(
                        name: "导出视频轨存在",
                        status: .fail,
                        detail: "videoTracks=0"
                    )
                )
            }

            if inspection.durationSeconds > 0 {
                items.append(
                    ValidationItem(
                        name: "导出时长大于0",
                        status: .pass,
                        detail: String(format: "%.3fs", inspection.durationSeconds)
                    )
                )
            } else {
                items.append(
                    ValidationItem(
                        name: "导出时长大于0",
                        status: .fail,
                        detail: String(format: "%.3fs", inspection.durationSeconds)
                    )
                )
            }
        } else {
            items.append(
                ValidationItem(
                    name: "导出文件存在",
                    status: .fail,
                    detail: "未找到导出文件"
                )
            )
            items.append(
                ValidationItem(
                    name: "导出视频轨存在",
                    status: .fail,
                    detail: "无法读取导出文件"
                )
            )
            items.append(
                ValidationItem(
                    name: "导出时长大于0",
                    status: .fail,
                    detail: "无法读取导出文件"
                )
            )
        }

        let hasIPhoneCamera = cameraSources.contains { $0.name.lowercased().contains("iphone") || $0.isContinuity }
        let hasIPhoneMic = audioSources.contains { $0.name.lowercased().contains("iphone") || $0.isContinuity }
        items.append(
            ValidationItem(
                name: "iPhone 摄像头可见",
                status: hasIPhoneCamera ? .pass : .blocked,
                detail: hasIPhoneCamera ? "检测到 iPhone/Continuity 摄像头" : "未检测到 iPhone 摄像头"
            )
        )
        items.append(
            ValidationItem(
                name: "iPhone 麦克风可见",
                status: hasIPhoneMic ? .pass : .blocked,
                detail: hasIPhoneMic ? "检测到 iPhone 麦克风" : "未检测到 iPhone 麦克风"
            )
        )

        let hasIPadCamera = cameraSources.contains { $0.name.lowercased().contains("ipad") }
        let hasIPadMic = audioSources.contains { $0.name.lowercased().contains("ipad") }
        items.append(
            ValidationItem(
                name: "iPad 摄像头条件测",
                status: hasIPadCamera ? .pass : .blocked,
                detail: hasIPadCamera ? "系统已识别 iPad 摄像头" : "系统未识别 iPad 摄像头（条件阻塞）"
            )
        )
        items.append(
            ValidationItem(
                name: "iPad 麦克风条件测",
                status: hasIPadMic ? .pass : .blocked,
                detail: hasIPadMic ? "系统已识别 iPad 麦克风" : "系统未识别 iPad 麦克风（条件阻塞）"
            )
        )

        items.append(
            ValidationItem(
                name: "全链路人工冒烟",
                status: .blocked,
                detail: "需在本机 GUI 实测：录屏 + PiP + 拼接 + 多段剪切"
            )
        )

        return ValidationReport(createdAt: Date(), items: items)
    }

    func persist(report: ValidationReport) throws -> URL {
        try persist(
            report: report,
            directory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Movies", isDirectory: true)
                .appendingPathComponent("PJTool", isDirectory: true)
        )
    }

    func persist(report: ValidationReport, directory: URL) throws -> URL {
        let folder = directory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let file = folder.appendingPathComponent("ValidationReport-\(formatter.string(from: Date())).json")
        let data = try JSONEncoder.pretty.encode(report)
        try data.write(to: file)
        return file
    }

    private func inspectAsset(at url: URL) -> (durationSeconds: Double, videoTrackCount: Int, audioTrackCount: Int) {
        let asset = AVAsset(url: url)
        return (
            durationSeconds: max(0, asset.duration.seconds),
            videoTrackCount: asset.tracks(withMediaType: .video).count,
            audioTrackCount: asset.tracks(withMediaType: .audio).count
        )
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
