//
//  CompositionExportEngine.swift
//  PJTool
//
//  Created by Codex on 2026/4/29.
//

import AVFoundation
import CoreMedia
import Foundation

final class CompositionExportEngine {
    func mergeScreenAndCamera(
        screenURL: URL,
        cameraURL: URL?,
        pipLayout: PiPLayoutState,
        faceFramingKeyframes: [FaceFramingKeyframe] = [],
        outputURL: URL
    ) async throws -> URL {
        guard let cameraURL else {
            try removeFileIfExists(at: outputURL)
            try FileManager.default.copyItem(at: screenURL, to: outputURL)
            return outputURL
        }

        let screenAsset = AVAsset(url: screenURL)
        let cameraAsset = AVAsset(url: cameraURL)
        guard let screenVideoTrack = screenAsset.tracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack("屏幕轨道缺失")
        }
        guard let cameraVideoTrack = cameraAsset.tracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack("摄像头轨道缺失")
        }

        let composition = AVMutableComposition()
        guard let screenCompTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.compositionTrackFailed
        }
        guard let cameraCompTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.compositionTrackFailed
        }

        let screenDuration = screenAsset.duration
        try screenCompTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: screenDuration),
            of: screenVideoTrack,
            at: .zero
        )

        let cameraDuration = min(cameraAsset.duration, screenDuration)
        try cameraCompTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: cameraDuration),
            of: cameraVideoTrack,
            at: .zero
        )

        if let screenAudio = screenAsset.tracks(withMediaType: .audio).first,
           let audioCompTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audioCompTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: screenDuration),
                of: screenAudio,
                at: .zero
            )
        }

        let renderSize = orientedSize(of: screenVideoTrack)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: screenDuration)

        let baseLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: screenCompTrack)
        baseLayer.setTransform(
            transformToFit(track: screenVideoTrack, renderSize: renderSize),
            at: .zero
        )

        let pipRect = CGRect(
            x: pipLayout.normalizedRect.minX * renderSize.width,
            y: pipLayout.normalizedRect.minY * renderSize.height,
            width: pipLayout.normalizedRect.width * renderSize.width,
            height: pipLayout.normalizedRect.height * renderSize.height
        )
        let cameraLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: cameraCompTrack)
        let basePiPTransform = transformToFit(track: cameraVideoTrack, renderRect: pipRect)
        cameraLayer.setTransform(basePiPTransform, at: .zero)
        applyFaceFramingTransformRamps(
            keyframes: faceFramingKeyframes,
            to: cameraLayer,
            cameraTrack: cameraVideoTrack,
            pipRect: pipRect,
            cameraDuration: cameraDuration,
            baseTransform: basePiPTransform
        )

        instruction.layerInstructions = [cameraLayer, baseLayer]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        try await export(
            composition: composition,
            videoComposition: videoComposition,
            outputURL: outputURL
        )
        return outputURL
    }

    func stitch(project: CompositionProject, outputURL: URL) async throws -> URL {
        let baseAsset = AVAsset(url: project.baseAssetURL)
        guard let baseVideoTrack = baseAsset.tracks(withMediaType: .video).first else {
            throw ExportError.missingVideoTrack("主轨视频缺失")
        }

        let renderSize = orientedSize(of: baseVideoTrack)
        let baseDuration = baseAsset.duration
        let insertions = project.layers.sorted { $0.insertTime < $1.insertTime }

        let composition = AVMutableComposition()
        guard let videoCompTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.compositionTrackFailed
        }
        let audioCompTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        struct Segment {
            let timeRange: CMTimeRange
            let sourceTrack: AVAssetTrack
        }
        var segments: [Segment] = []

        var cursor = CMTime.zero
        var timeline = CMTime.zero

        func appendSegment(
            from asset: AVAsset,
            videoTrack: AVAssetTrack,
            range: CMTimeRange,
            muteAudio: Bool
        ) throws {
            try videoCompTrack.insertTimeRange(range, of: videoTrack, at: timeline)
            segments.append(Segment(timeRange: CMTimeRange(start: timeline, duration: range.duration), sourceTrack: videoTrack))

            if !muteAudio,
               let sourceAudioTrack = asset.tracks(withMediaType: .audio).first,
               let audioCompTrack {
                try audioCompTrack.insertTimeRange(range, of: sourceAudioTrack, at: timeline)
            }
            timeline = timeline + range.duration
        }

        for insertion in insertions {
            let insertionPoint = CMTimeMaximum(CMTime.zero, CMTimeMinimum(baseDuration, insertion.insertTime))
            if insertionPoint > cursor {
                let baseRange = CMTimeRange(start: cursor, end: insertionPoint)
                if baseRange.duration > .zero {
                    try appendSegment(
                        from: baseAsset,
                        videoTrack: baseVideoTrack,
                        range: baseRange,
                        muteAudio: false
                    )
                }
            }

            let insertAsset = AVAsset(url: insertion.assetURL)
            guard let insertVideoTrack = insertAsset.tracks(withMediaType: .video).first else {
                throw ExportError.missingVideoTrack("插入片段缺少视频：\(insertion.assetURL.lastPathComponent)")
            }
            let insertRange = CMTimeRange(start: .zero, duration: insertAsset.duration)
            if insertRange.duration > .zero {
                try appendSegment(
                    from: insertAsset,
                    videoTrack: insertVideoTrack,
                    range: insertRange,
                    muteAudio: insertion.mute
                )
            }
            cursor = insertionPoint
        }

        if cursor < baseDuration {
            let tailRange = CMTimeRange(start: cursor, end: baseDuration)
            if tailRange.duration > .zero {
                try appendSegment(from: baseAsset, videoTrack: baseVideoTrack, range: tailRange, muteAudio: false)
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = segments.map { segment in
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = segment.timeRange

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompTrack)
            layer.setTransform(
                transformToFit(track: segment.sourceTrack, renderSize: renderSize),
                at: segment.timeRange.start
            )
            instruction.layerInstructions = [layer]
            return instruction
        }

        try await export(
            composition: composition,
            videoComposition: videoComposition,
            outputURL: outputURL
        )
        return outputURL
    }

    private func export(
        composition: AVMutableComposition,
        videoComposition: AVVideoComposition?,
        outputURL: URL
    ) async throws {
        try removeFileIfExists(at: outputURL)
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportSessionFailed
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(throwing: exporter.error ?? ExportError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: ExportError.exportCancelled)
                default:
                    continuation.resume(throwing: ExportError.exportFailed)
                }
            }
        }
    }

    private func orientedSize(of track: AVAssetTrack) -> CGSize {
        let natural = track.naturalSize
        let rect = CGRect(origin: .zero, size: natural).applying(track.preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    private func transformToFit(track: AVAssetTrack, renderSize: CGSize) -> CGAffineTransform {
        let sourceSize = orientedSize(of: track)
        return transformToFit(track: track, renderRect: CGRect(origin: .zero, size: renderSize), sourceSize: sourceSize)
    }

    private func transformToFit(track: AVAssetTrack, renderRect: CGRect) -> CGAffineTransform {
        let sourceSize = orientedSize(of: track)
        return transformToFit(track: track, renderRect: renderRect, sourceSize: sourceSize)
    }

    private func transformToFit(track: AVAssetTrack, renderRect: CGRect, sourceSize: CGSize) -> CGAffineTransform {
        let baseTransform = track.preferredTransform
        guard sourceSize.width > 0, sourceSize.height > 0 else { return baseTransform }

        let scale = min(renderRect.width / sourceSize.width, renderRect.height / sourceSize.height)
        let targetSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let x = renderRect.minX + (renderRect.width - targetSize.width) / 2.0
        let y = renderRect.minY + (renderRect.height - targetSize.height) / 2.0

        return baseTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x / scale, y: y / scale))
    }

    private func applyFaceFramingTransformRamps(
        keyframes: [FaceFramingKeyframe],
        to layer: AVMutableVideoCompositionLayerInstruction,
        cameraTrack: AVAssetTrack,
        pipRect: CGRect,
        cameraDuration: CMTime,
        baseTransform: CGAffineTransform
    ) {
        guard !keyframes.isEmpty else { return }
        guard cameraDuration.seconds > 0 else { return }

        let validFrames = keyframes
            .map { frame in
                FaceFramingKeyframe(
                    id: frame.id,
                    seconds: max(0, min(cameraDuration.seconds, frame.seconds)),
                    normalizedRect: PiPGeometry.clampNormalized(frame.normalizedRect)
                )
            }
            .sorted { $0.seconds < $1.seconds }

        guard validFrames.count >= 2 else {
            if let single = validFrames.first {
                let transform = transformForFaceFrame(
                    single,
                    cameraTrack: cameraTrack,
                    pipRect: pipRect,
                    fallback: baseTransform
                )
                layer.setTransform(transform, at: CMTime(seconds: single.seconds, preferredTimescale: 600))
            }
            return
        }

        for idx in 0..<(validFrames.count - 1) {
            let current = validFrames[idx]
            let next = validFrames[idx + 1]
            guard next.seconds > current.seconds else { continue }

            let fromTransform = transformForFaceFrame(
                current,
                cameraTrack: cameraTrack,
                pipRect: pipRect,
                fallback: baseTransform
            )
            let toTransform = transformForFaceFrame(
                next,
                cameraTrack: cameraTrack,
                pipRect: pipRect,
                fallback: baseTransform
            )

            layer.setTransformRamp(
                fromStart: fromTransform,
                toEnd: toTransform,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: current.seconds, preferredTimescale: 600),
                    duration: CMTime(seconds: next.seconds - current.seconds, preferredTimescale: 600)
                )
            )
        }
    }

    private func transformForFaceFrame(
        _ frame: FaceFramingKeyframe,
        cameraTrack: AVAssetTrack,
        pipRect: CGRect,
        fallback: CGAffineTransform
    ) -> CGAffineTransform {
        let normalized = PiPGeometry.clampNormalized(frame.normalizedRect)
        guard normalized.width > 0.001, normalized.height > 0.001 else { return fallback }

        let sourceSize = orientedSize(of: cameraTrack)
        guard sourceSize.width > 1, sourceSize.height > 1 else { return fallback }

        let cropRect = CGRect(
            x: normalized.minX * sourceSize.width,
            y: normalized.minY * sourceSize.height,
            width: normalized.width * sourceSize.width,
            height: normalized.height * sourceSize.height
        )
        guard cropRect.width > 1, cropRect.height > 1 else { return fallback }

        return transformToFit(track: cameraTrack, renderRect: pipRect, sourceSize: cropRect.size)
            .concatenating(
                CGAffineTransform(translationX: -(cropRect.minX), y: -(cropRect.minY))
            )
    }

    private func removeFileIfExists(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

extension CompositionExportEngine {
    enum ExportError: LocalizedError {
        case missingVideoTrack(String)
        case compositionTrackFailed
        case exportSessionFailed
        case exportFailed
        case exportCancelled

        var errorDescription: String? {
            switch self {
            case let .missingVideoTrack(message):
                return message
            case .compositionTrackFailed:
                return "创建合成轨道失败。"
            case .exportSessionFailed:
                return "创建导出会话失败。"
            case .exportFailed:
                return "导出失败。"
            case .exportCancelled:
                return "导出已取消。"
            }
        }
    }
}
