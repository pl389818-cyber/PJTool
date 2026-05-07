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
    case screenDrawing
    case videoCutting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recording:
            return "录屏"
        case .pipCamera:
            return "PiP 摄像"
        case .screenDrawing:
            return "屏幕画图"
        case .videoCutting:
            return "视频剪切"
        }
    }

    var subtitle: String {
        switch self {
        case .recording:
            return "主屏录制"
        case .pipCamera:
            return "设备与预览"
        case .screenDrawing:
            return "透明画布工具条"
        case .videoCutting:
            return "智能裁剪弹窗"
        }
    }

    var symbolName: String {
        switch self {
        case .recording:
            return "record.circle"
        case .pipCamera:
            return "video.badge.waveform"
        case .screenDrawing:
            return "pencil.and.scribble"
        case .videoCutting:
            return "scissors"
        }
    }
}
