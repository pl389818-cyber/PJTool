//
//  TrimExportEngine.swift
//  PJTool
//
//  Created by Codex on 2026/4/29.
//

import AVFoundation
import CoreMedia
import Foundation

final class TrimExportEngine {
    func keepRanges(from deleteRanges: [CutRange], sourceDuration: CMTime) -> [CMTimeRange] {
        let mergedDeletes = mergedDeleteRanges(deleteRanges, sourceDuration: sourceDuration)
        guard !mergedDeletes.isEmpty else {
            return [CMTimeRange(start: .zero, duration: sourceDuration)]
        }

        var keep: [CMTimeRange] = []
        var cursor = CMTime.zero

        for deletion in mergedDeletes {
            if deletion.start > cursor {
                keep.append(CMTimeRange(start: cursor, end: deletion.start))
            }
            cursor = deletion.end
        }

        if cursor < sourceDuration {
            keep.append(CMTimeRange(start: cursor, end: sourceDuration))
        }

        return keep.filter { $0.duration > .zero }
    }

    func export(
        project: TrimProject,
        outputURL: URL
    ) async throws -> URL {
        let asset = AVAsset(url: project.sourceURL)
        let duration = asset.duration
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw TrimError.missingVideoTrack
        }

        let keep = keepRanges(from: project.deleteRanges, sourceDuration: duration)
        let request = TrimExportRequest(sourceURL: project.sourceURL, keepRanges: keep, outputURL: outputURL)
        return try await export(request: request, sourceAsset: asset, sourceVideoTrack: videoTrack)
    }

    private func export(
        request: TrimExportRequest,
        sourceAsset: AVAsset,
        sourceVideoTrack: AVAssetTrack
    ) async throws -> URL {
        let composition = AVMutableComposition()
        guard let videoCompTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TrimError.compositionTrackFailed
        }
        let audioCompTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let sourceAudioTrack = sourceAsset.tracks(withMediaType: .audio).first

        var timeline = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []
        let renderSize = orientedSize(of: sourceVideoTrack)

        for range in request.keepRanges where range.duration > .zero {
            try videoCompTrack.insertTimeRange(range, of: sourceVideoTrack, at: timeline)
            if let sourceAudioTrack, let audioCompTrack {
                try audioCompTrack.insertTimeRange(range, of: sourceAudioTrack, at: timeline)
            }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: timeline, duration: range.duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompTrack)
            layer.setTransform(sourceVideoTrack.preferredTransform, at: timeline)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            timeline = timeline + range.duration
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        try removeFileIfExists(at: request.outputURL)
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw TrimError.exportSessionFailed
        }

        exporter.outputURL = request.outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(throwing: exporter.error ?? TrimError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: TrimError.exportCancelled)
                default:
                    continuation.resume(throwing: TrimError.exportFailed)
                }
            }
        }

        return request.outputURL
    }

    private func mergedDeleteRanges(
        _ ranges: [CutRange],
        sourceDuration: CMTime
    ) -> [CMTimeRange] {
        let normalizedRanges = ranges
            .map { $0.normalized }
            .map {
                CMTimeRange(
                    start: CMTimeMaximum(.zero, $0.start),
                    end: CMTimeMinimum(sourceDuration, $0.end)
                )
            }
            .filter { $0.duration > .zero }
            .sorted { $0.start < $1.start }

        guard var current = normalizedRanges.first else { return [] }
        var merged: [CMTimeRange] = []

        for range in normalizedRanges.dropFirst() {
            if range.start <= current.end {
                current = CMTimeRange(start: current.start, end: CMTimeMaximum(current.end, range.end))
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
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

extension TrimExportEngine {
    enum TrimError: LocalizedError {
        case missingVideoTrack
        case compositionTrackFailed
        case exportSessionFailed
        case exportFailed
        case exportCancelled

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                return "源视频没有可用视频轨道。"
            case .compositionTrackFailed:
                return "创建合成轨道失败。"
            case .exportSessionFailed:
                return "创建导出会话失败。"
            case .exportFailed:
                return "剪切导出失败。"
            case .exportCancelled:
                return "剪切导出已取消。"
            }
        }
    }
}
