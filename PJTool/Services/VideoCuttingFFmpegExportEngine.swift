//
//  VideoCuttingFFmpegExportEngine.swift
//  PJTool
//
//  Created by Codex on 2026/5/12.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

final class VideoCuttingFFmpegExportEngine {
    private let binaryService = FFmpegBinaryService()
    private let runner = FFmpegRunner()

    func ensureToolsReady() throws {
        _ = try binaryService.ensureReady()
    }

    func export(
        project: VideoCuttingFFmpegProject,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let tools = try binaryService.ensureReady()
        let context = try makeExportContext(project: project)

        try removeFileIfExists(at: project.outputURL)
        let command = try buildCommand(
            tools: tools,
            context: context,
            outputURL: project.outputURL
        )
        _ = try await runner.run(command: command, onProgress: onProgress)
        guard FileManager.default.fileExists(atPath: project.outputURL.path) else {
            throw FFmpegComposeError.outputMissing
        }
        return project.outputURL
    }
}

private extension VideoCuttingFFmpegExportEngine {
    struct ExportContext {
        let sourceURL: URL
        let sourceDuration: Double
        let keepRanges: [CMTimeRange]
        let cropPixels: CGRect
        let isFullCrop: Bool
        let isFullKeep: Bool
        let hasAudioTrack: Bool
        let audioFilterChain: String?
    }

    struct FilterPlan {
        let graph: String
        let videoLabel: String
        let audioLabel: String?
    }

    func makeExportContext(project: VideoCuttingFFmpegProject) throws -> ExportContext {
        let asset = AVAsset(url: project.sourceURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw FFmpegComposeError.missingVideoTrack
        }
        let duration = max(0.001, asset.duration.seconds)
        let keepRanges = normalizeKeepRanges(project.keepRanges, sourceDuration: duration)
        guard !keepRanges.isEmpty else {
            throw FFmpegComposeError.emptyKeepRanges
        }

        let orientedSize = orientedSize(of: videoTrack)
        guard orientedSize.width > 1, orientedSize.height > 1 else {
            throw FFmpegComposeError.invalidRenderSize
        }

        let cropPixels = cropRectPixels(
            normalized: VideoCropGeometry.clampNormalizedRect(project.cropRectNormalized.cgRect),
            orientedSize: orientedSize
        )
        guard cropPixels.width > 1, cropPixels.height > 1 else {
            throw FFmpegComposeError.invalidCropRect
        }

        let fullCrop = isFullCrop(cropPixels, orientedSize: orientedSize)
        let fullKeep = isFullKeep(keepRanges, duration: duration)
        let hasAudioTrack = project.hasAudioTrack && !asset.tracks(withMediaType: .audio).isEmpty
        let audioFilter = hasAudioTrack ? buildAudioFilterChain(config: project.audioProcessingConfig) : nil
        return ExportContext(
            sourceURL: project.sourceURL,
            sourceDuration: duration,
            keepRanges: keepRanges,
            cropPixels: cropPixels,
            isFullCrop: fullCrop,
            isFullKeep: fullKeep,
            hasAudioTrack: hasAudioTrack,
            audioFilterChain: audioFilter
        )
    }

    func buildCommand(
        tools: FFmpegToolPaths,
        context: ExportContext,
        outputURL: URL
    ) throws -> FFmpegCommand {
        let shouldFastCopy = context.isFullKeep &&
            context.isFullCrop &&
            context.audioFilterChain == nil

        if shouldFastCopy {
            var args: [String] = [
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-progress", "pipe:1",
                "-i", context.sourceURL.path,
                "-map", "0:v:0"
            ]
            if context.hasAudioTrack {
                args.append(contentsOf: ["-map", "0:a:0"])
            }
            args.append(contentsOf: ["-c", "copy", "-movflags", "+faststart", outputURL.path])
            return FFmpegCommand(
                executableURL: tools.ffmpegURL,
                arguments: args,
                expectedDurationSeconds: context.sourceDuration
            )
        }

        if context.isFullKeep && context.isFullCrop && !context.hasAudioTrack {
            let args: [String] = [
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-progress", "pipe:1",
                "-i", context.sourceURL.path,
                "-map", "0:v:0",
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "18",
                "-pix_fmt", "yuv420p",
                "-an",
                "-movflags", "+faststart",
                outputURL.path
            ]
            return FFmpegCommand(
                executableURL: tools.ffmpegURL,
                arguments: args,
                expectedDurationSeconds: context.sourceDuration
            )
        }

        if context.isFullKeep && context.isFullCrop, let audioFilter = context.audioFilterChain {
            let args: [String] = [
                "-hide_banner",
                "-loglevel", "error",
                "-y",
                "-progress", "pipe:1",
                "-i", context.sourceURL.path,
                "-map", "0:v:0",
                "-map", "0:a:0",
                "-c:v", "copy",
                "-af", audioFilter,
                "-c:a", "aac",
                "-b:a", "192k",
                "-movflags", "+faststart",
                outputURL.path
            ]
            return FFmpegCommand(
                executableURL: tools.ffmpegURL,
                arguments: args,
                expectedDurationSeconds: context.sourceDuration
            )
        }

        let filterPlan = buildFilterPlan(context: context)
        var args: [String] = [
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-progress", "pipe:1",
            "-i", context.sourceURL.path,
            "-filter_complex", filterPlan.graph,
            "-map", filterPlan.videoLabel,
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", "18",
            "-pix_fmt", "yuv420p"
        ]

        if let audioLabel = filterPlan.audioLabel {
            args.append(contentsOf: [
                "-map", audioLabel,
                "-c:a", "aac",
                "-b:a", "192k"
            ])
        } else {
            args.append("-an")
        }

        args.append(contentsOf: ["-movflags", "+faststart", outputURL.path])
        return FFmpegCommand(
            executableURL: tools.ffmpegURL,
            arguments: args,
            expectedDurationSeconds: context.keepRanges.reduce(0) { $0 + $1.duration.seconds }
        )
    }

    func buildFilterPlan(context: ExportContext) -> FilterPlan {
        var parts: [String] = []
        let keepRanges = context.keepRanges
        let hasAudio = context.hasAudioTrack

        for (index, range) in keepRanges.enumerated() {
            let start = formatTime(range.start.seconds)
            let end = formatTime((range.start + range.duration).seconds)
            parts.append("[0:v]trim=start=\(start):end=\(end),setpts=PTS-STARTPTS[v\(index)]")
            if hasAudio {
                parts.append("[0:a]atrim=start=\(start):end=\(end),asetpts=PTS-STARTPTS[a\(index)]")
            }
        }

        let videoConcatLabel: String
        if keepRanges.count == 1 {
            videoConcatLabel = "v0"
        } else {
            let inputs = keepRanges.indices.map { "[v\($0)]" }.joined()
            parts.append("\(inputs)concat=n=\(keepRanges.count):v=1:a=0[vcat]")
            videoConcatLabel = "vcat"
        }

        let audioConcatLabel: String?
        if hasAudio {
            if keepRanges.count == 1 {
                audioConcatLabel = "a0"
            } else {
                let inputs = keepRanges.indices.map { "[a\($0)]" }.joined()
                parts.append("\(inputs)concat=n=\(keepRanges.count):v=0:a=1[acat]")
                audioConcatLabel = "acat"
            }
        } else {
            audioConcatLabel = nil
        }

        let videoOutLabel: String
        if context.isFullCrop {
            videoOutLabel = videoConcatLabel
        } else {
            let crop = context.cropPixels
            parts.append("[\(videoConcatLabel)]crop=\(Int(crop.width)):\(Int(crop.height)):\(Int(crop.minX)):\(Int(crop.minY))[vout]")
            videoOutLabel = "vout"
        }

        let audioOutLabel: String?
        if let audioConcatLabel {
            if let audioFilter = context.audioFilterChain {
                parts.append("[\(audioConcatLabel)]\(audioFilter)[aout]")
                audioOutLabel = "aout"
            } else {
                audioOutLabel = audioConcatLabel
            }
        } else {
            audioOutLabel = nil
        }

        return FilterPlan(
            graph: parts.joined(separator: ";"),
            videoLabel: "[\(videoOutLabel)]",
            audioLabel: audioOutLabel.map { "[\($0)]" }
        )
    }

    func normalizeKeepRanges(_ ranges: [CMTimeRange], sourceDuration: Double) -> [CMTimeRange] {
        let maxDuration = max(0, sourceDuration)
        let normalized = ranges.compactMap { range -> CMTimeRange? in
            let rawStart = max(0, range.start.seconds)
            let rawEnd = max(rawStart, (range.start + range.duration).seconds)
            let start = min(maxDuration, rawStart)
            let end = min(maxDuration, rawEnd)
            guard end - start > 0.0005 else { return nil }
            return CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )
        }
        return normalized.sorted { $0.start < $1.start }
    }

    func isFullKeep(_ keepRanges: [CMTimeRange], duration: Double) -> Bool {
        guard keepRanges.count == 1 else { return false }
        let range = keepRanges[0]
        return abs(range.start.seconds) <= 0.0005 && abs(range.duration.seconds - duration) <= 0.01
    }

    func isFullCrop(_ cropPixels: CGRect, orientedSize: CGSize) -> Bool {
        abs(cropPixels.minX) <= 1 &&
            abs(cropPixels.minY) <= 1 &&
            abs(cropPixels.width - orientedSize.width) <= 1 &&
            abs(cropPixels.height - orientedSize.height) <= 1
    }

    func cropRectPixels(normalized: CGRect, orientedSize: CGSize) -> CGRect {
        let clamped = VideoCropGeometry.clampNormalizedRect(normalized)
        var x = floor(max(0, clamped.minX * orientedSize.width))
        var y = floor(max(0, clamped.minY * orientedSize.height))
        var width = floor(max(2, min(orientedSize.width - x, clamped.width * orientedSize.width)))
        var height = floor(max(2, min(orientedSize.height - y, clamped.height * orientedSize.height)))

        if Int(width) % 2 != 0 {
            width = max(2, width - 1)
        }
        if Int(height) % 2 != 0 {
            height = max(2, height - 1)
        }

        if x + width > orientedSize.width {
            x = max(0, orientedSize.width - width)
        }
        if y + height > orientedSize.height {
            y = max(0, orientedSize.height - height)
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    func orientedSize(of track: AVAssetTrack) -> CGSize {
        let natural = track.naturalSize
        let rect = CGRect(origin: .zero, size: natural).applying(track.preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    func buildAudioFilterChain(config: VideoCuttingAudioProcessingConfig) -> String? {
        let cfg = config.clamped
        guard cfg.hasAnyProcessing else { return nil }

        var filters: [String] = []

        if cfg.noiseReductionEnabled {
            let p = max(0, min(100, cfg.noiseReductionPercent)) / 100.0
            let hp = Int(60 + p * 70)
            let lp = Int(14_000 - p * 5_000)
            let afftdnNR = String(format: "%.2f", 10 + p * 20)
            let afftdnNF = String(format: "%.2f", -55 + p * 10)
            let rejectWidth = String(format: "%.1f", 1.8 + p * 3.2)
            filters.append("highpass=f=\(hp)")
            filters.append("lowpass=f=\(lp)")
            filters.append("bandreject=f=50:t=q:w=\(rejectWidth)")
            filters.append("bandreject=f=60:t=q:w=\(rejectWidth)")
            filters.append("bandreject=f=100:t=q:w=\(rejectWidth)")
            filters.append("bandreject=f=120:t=q:w=\(rejectWidth)")
            filters.append("afftdn=nr=\(afftdnNR):nf=\(afftdnNF):tn=1")
        }

        filters.append(contentsOf: eqFilterChain(for: cfg.eqPreset))
        return filters.isEmpty ? nil : filters.joined(separator: ",")
    }

    func eqFilterChain(for preset: VideoCuttingAudioEQPreset) -> [String] {
        switch preset {
        case .balanced:
            return [
                "equalizer=f=180:t=q:w=0.9:g=-2.5",
                "equalizer=f=2500:t=q:w=1.1:g=2.4",
                "equalizer=f=6200:t=q:w=1.0:g=-1.4"
            ]
        case .vocalBoost:
            return [
                "equalizer=f=200:t=q:w=1.0:g=-1.2",
                "equalizer=f=1800:t=q:w=1.0:g=2.0",
                "equalizer=f=4200:t=q:w=1.2:g=1.8"
            ]
        case .musicBoost:
            return [
                "equalizer=f=120:t=q:w=0.8:g=2.0",
                "equalizer=f=1800:t=q:w=1.0:g=0.8",
                "equalizer=f=8000:t=q:w=1.1:g=1.8"
            ]
        case .loudness:
            return [
                "equalizer=f=120:t=q:w=0.9:g=2.4",
                "equalizer=f=1000:t=q:w=0.9:g=1.2",
                "equalizer=f=7800:t=q:w=1.0:g=2.0"
            ]
        case .humReduction:
            return [
                "bandreject=f=50:t=q:w=3.4",
                "bandreject=f=60:t=q:w=3.4",
                "bandreject=f=100:t=q:w=2.8",
                "bandreject=f=120:t=q:w=2.8",
                "equalizer=f=240:t=q:w=1.0:g=-1.2"
            ]
        case .bassBoost:
            return [
                "equalizer=f=90:t=q:w=0.8:g=3.2",
                "equalizer=f=220:t=q:w=1.0:g=1.4"
            ]
        case .bassCut:
            return [
                "equalizer=f=100:t=q:w=0.9:g=-3.0",
                "equalizer=f=220:t=q:w=1.1:g=-1.3"
            ]
        case .trebleBoost:
            return [
                "equalizer=f=5200:t=q:w=1.2:g=2.6",
                "equalizer=f=9000:t=q:w=1.0:g=2.2"
            ]
        case .trebleCut:
            return [
                "equalizer=f=5200:t=q:w=1.2:g=-2.4",
                "equalizer=f=9000:t=q:w=1.0:g=-2.0"
            ]
        }
    }

    func formatTime(_ seconds: Double) -> String {
        String(format: "%.6f", max(0, seconds))
    }

    func removeFileIfExists(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

extension VideoCuttingFFmpegExportEngine {
    enum FFmpegComposeError: LocalizedError {
        case missingVideoTrack
        case emptyKeepRanges
        case invalidCropRect
        case invalidRenderSize
        case outputMissing

        var errorDescription: String? {
            switch self {
            case .missingVideoTrack:
                return L10n.tr("legacy.key_175")
            case .emptyKeepRanges:
                return L10n.tr("legacy.key_172")
            case .invalidCropRect:
                return L10n.tr("legacy.key_195")
            case .invalidRenderSize:
                return L10n.tr("legacy.key_196")
            case .outputMissing:
                return L10n.tr("legacy.ffmpeg.output_missing")
            }
        }
    }
}
