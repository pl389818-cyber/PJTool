//
//  VideoCuttingAudioModels.swift
//  PJTool
//
//  Created by Codex on 2026/5/5.
//

import Foundation

enum VideoCuttingAudioEQPreset: String, CaseIterable, Identifiable, Codable {
    case balanced
    case vocalBoost
    case musicBoost
    case loudness
    case humReduction
    case bassBoost
    case bassCut
    case trebleBoost
    case trebleCut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return "平缓"
        case .vocalBoost:
            return "人声增强"
        case .musicBoost:
            return "音乐增强"
        case .loudness:
            return "响度"
        case .humReduction:
            return "嗡嗡声减弱"
        case .bassBoost:
            return "低音增强"
        case .bassCut:
            return "低音减弱"
        case .trebleBoost:
            return "高音增强"
        case .trebleCut:
            return "高音减弱"
        }
    }
}

struct VideoCuttingAudioProcessingConfig: Equatable, Codable {
    var noiseReductionEnabled: Bool
    var noiseReductionPercent: Double
    var eqPreset: VideoCuttingAudioEQPreset

    static let `default` = VideoCuttingAudioProcessingConfig(
        noiseReductionEnabled: true,
        noiseReductionPercent: 50,
        eqPreset: .balanced
    )

    var clamped: VideoCuttingAudioProcessingConfig {
        VideoCuttingAudioProcessingConfig(
            noiseReductionEnabled: noiseReductionEnabled,
            noiseReductionPercent: max(0, min(100, noiseReductionPercent)),
            eqPreset: eqPreset
        )
    }

    var hasAnyProcessing: Bool {
        clamped.noiseReductionEnabled || clamped.eqPreset != .balanced
    }
}
