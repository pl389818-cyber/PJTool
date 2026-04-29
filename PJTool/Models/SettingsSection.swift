//
//  SettingsSection.swift
//  PJTool
//
//  Created by Codex on 2026/4/30.
//

import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case recording
    case pipCamera
    case videoProcessing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording:
            return "录屏"
        case .pipCamera:
            return "PiP 摄像"
        case .videoProcessing:
            return "视频处理"
        }
    }

    var subtitle: String {
        switch self {
        case .recording:
            return "主屏录制"
        case .pipCamera:
            return "设备与预览"
        case .videoProcessing:
            return "拼接、剪切、导出"
        }
    }

    var symbolName: String {
        switch self {
        case .recording:
            return "record.circle"
        case .pipCamera:
            return "video.badge.waveform"
        case .videoProcessing:
            return "film.stack"
        }
    }
}
