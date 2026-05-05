//
//  VideoCuttingComposeExportEngine.swift
//  PJTool
//
//  Created by Codex on 2026/5/5.
//

import AVFoundation
import CoreMedia
import Foundation

final class VideoCuttingComposeExportEngine {
    private let trimEngine = TrimExportEngine()
    private let audioProcessingEngine = VideoCuttingAudioProcessingEngine()

    func export(project: VideoCuttingComposeProject) async throws -> URL {
        let asset = AVAsset(url: project.sourceURL)
        let duration = asset.duration
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw ComposeError.missingVideoTrack
        }

        let keepRanges = trimEngine.keepRanges(from: project.deleteRanges, sourceDuration: duration)
        guard !keepRanges.isEmpty else {
            throw ComposeError.emptyKeepRanges
        }

        let orientedSize = orientedSize(of: videoTrack)
        guard orientedSize.width > 1, orientedSize.height > 1 else {
            throw ComposeError.invalidRenderSize
        }

        let normalizedCrop = VideoCropGeometry.clampNormalizedRect(project.cropRectNormalized.cgRect)
        let cropPixels = cropRectPixels(normalized: normalizedCrop, orientedSize: orientedSize)
        guard cropPixels.width > 1, cropPixels.height > 1 else {
            throw ComposeError.invalidCropRect
        }

        let request = ComposeRequest(
            keepRanges: keepRanges,
            cropPixels: cropPixels,
            renderSize: cropPixels.size,
            audioProcessingConfig: project.audioProcessingConfig,
            outputURL: project.outputURL
        )

        return try await compose(request: request, sourceAsset: asset, sourceVideoTrack: videoTrack)
    }

    private func compose(
        request: ComposeRequest,
        sourceAsset: AVAsset,
        sourceVideoTrack: AVAssetTrack
    ) async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoCompTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ComposeError.compositionTrackFailed
        }
        let audioCompTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first

        var timeline = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for range in request.keepRanges where range.duration > .zero {
            try videoCompTrack.insertTimeRange(range, of: sourceVideoTrack, at: timeline)
            if let sourceAudioTrack, let audioCompTrack {
                try audioCompTrack.insertTimeRange(range, of: sourceAudioTrack, at: timeline)
            }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: timeline, duration: range.duration)

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompTrack)
            let transform = cropTransform(
                sourceTrack: sourceVideoTrack,
                cropPixels: request.cropPixels
            )
            layer.setTransform(transform, at: timeline)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            timeline = timeline + range.duration
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.renderSize = request.renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let hasAudioTrack = audioCompTrack != nil && sourceAudioTrack != nil
        let audioMix: AVAudioMix?
        if hasAudioTrack {
            do {
                audioMix = try audioProcessingEngine.makeAudioMixIfNeeded(
                    track: audioCompTrack,
                    config: request.audioProcessingConfig
                )
            } catch {
                throw ComposeError.audioProcessingFailed(error.localizedDescription)
            }
        } else {
            audioMix = nil
        }

        try removeFileIfExists(at: request.outputURL)
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ComposeError.exportSessionFailed
        }
        exporter.outputURL = request.outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition
        exporter.audioMix = audioMix
        exporter.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(throwing: exporter.error ?? ComposeError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: ComposeError.exportCancelled)
                default:
                    continuation.resume(throwing: ComposeError.exportFailed)
                }
            }
        }

        return request.outputURL
    }

    private func cropRectPixels(normalized: CGRect, orientedSize: CGSize) -> CGRect {
        let clamped = VideoCropGeometry.clampNormalizedRect(normalized)
        var x = clamped.minX * orientedSize.width
        var y = clamped.minY * orientedSize.height
        var width = clamped.width * orientedSize.width
        var height = clamped.height * orientedSize.height

        x = floor(max(0, x))
        y = floor(max(0, y))
        width = floor(max(2, min(orientedSize.width - x, width)))
        height = floor(max(2, min(orientedSize.height - y, height)))

        // H.264-friendly even dimensions.
        if Int(width) % 2 != 0 {
            width = max(2, width - 1)
        }
        if Int(height) % 2 != 0 {
            height = max(2, height - 1)
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func cropTransform(
        sourceTrack: AVAssetTrack,
        cropPixels: CGRect
    ) -> CGAffineTransform {
        // Keep orientation by applying source preferred transform first, then shift cropped top-left to render origin.
        let base = sourceTrack.preferredTransform
        return base.concatenating(CGAffineTransform(translationX: -cropPixels.minX, y: -cropPixels.minY))
    }

    private func orientedSize(of track: AVAssetTrack) -> CGSize {
        let natural = track.naturalSize
        let rect = CGRect(origin: .zero, size: natural).applying(track.preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    private func removeFileIfExists(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

private extension VideoCuttingComposeExportEngine {
    struct ComposeRequest {
        let keepRanges: [CMTimeRange]
        let cropPixels: CGRect
        let renderSize: CGSize
        let audioProcessingConfig: VideoCuttingAudioProcessingConfig
        let outputURL: URL
    }
}

extension VideoCuttingComposeExportEngine {
    enum ComposeError: LocalizedError {
        case missingVideoTrack
        case emptyKeepRanges
        case invalidCropRect
        case invalidRenderSize
        case compositionTrackFailed
        case exportSessionFailed
        case audioProcessingFailed(String)
        case exportFailed
        case exportCancelled

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                return "源视频没有可用视频轨道。"
            case .emptyKeepRanges:
                return "没有可导出的保留区间。"
            case .invalidCropRect:
                return "裁切框无效。"
            case .invalidRenderSize:
                return "裁切输出尺寸无效。"
            case .compositionTrackFailed:
                return "创建合成轨道失败。"
            case .exportSessionFailed:
                return "创建导出会话失败。"
            case let .audioProcessingFailed(message):
                return "音频处理失败：\(message)"
            case .exportFailed:
                return "执行裁切导出失败。"
            case .exportCancelled:
                return "执行裁切已取消。"
            }
        }
    }
}
