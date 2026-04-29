import AVFoundation
import CoreMedia
import Foundation

private enum SmokeTask: String {
    case task1
    case task2
    case task3
    case all
}

private struct Options {
    let task: SmokeTask
    let baseURL: URL
    let cameraURL: URL
    let insertURL: URL
    let tempDirectory: URL

    init(arguments: [String]) throws {
        func value(for flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }

        let taskRaw = value(for: "--task") ?? "all"
        guard let task = SmokeTask(rawValue: taskRaw) else {
            throw SmokeError.usage("Invalid --task value: \(taskRaw)")
        }
        self.task = task

        guard let base = value(for: "--base") else {
            throw SmokeError.usage("Missing --base")
        }
        guard let camera = value(for: "--camera") else {
            throw SmokeError.usage("Missing --camera")
        }
        guard let insert = value(for: "--insert") else {
            throw SmokeError.usage("Missing --insert")
        }
        guard let tmp = value(for: "--tmp") else {
            throw SmokeError.usage("Missing --tmp")
        }

        baseURL = URL(fileURLWithPath: base)
        cameraURL = URL(fileURLWithPath: camera)
        insertURL = URL(fileURLWithPath: insert)
        tempDirectory = URL(fileURLWithPath: tmp, isDirectory: true)
    }
}

private struct AssetInfo {
    let durationSeconds: Double
    let videoTrackCount: Int
    let audioTrackCount: Int
}

@main
private struct PipelineSmokeRunner {
    static func main() async {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            try await run(options: options)
        } catch {
            fputs("SMOKE_FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run(options: Options) async throws {
        let compositionEngine = CompositionExportEngine()
        let trimEngine = TrimExportEngine()

        var stitchOutputURL: URL?

        if options.task == .task1 || options.task == .all {
            let pipOutputURL = options.tempDirectory.appendingPathComponent("task1-pip-merged.mp4")
            _ = try await compositionEngine.mergeScreenAndCamera(
                screenURL: options.baseURL,
                cameraURL: options.cameraURL,
                pipLayout: .default,
                outputURL: pipOutputURL
            )
            let info = try await inspectAsset(at: pipOutputURL)
            try require(FileManager.default.fileExists(atPath: pipOutputURL.path), "Task1 output file missing")
            try require(info.videoTrackCount >= 1, "Task1 merged output has no video track")
            try require(info.durationSeconds > 1.5, "Task1 merged output duration too short")
            let durationText = String(format: "%.3f", info.durationSeconds)
            print("TASK1 PASS duration=\(durationText) videoTracks=\(info.videoTrackCount) audioTracks=\(info.audioTrackCount)")
        }

        if options.task == .task2 || options.task == .all || options.task == .task3 {
            let task2OutputURL = options.tempDirectory.appendingPathComponent("task2-stitched.mp4")
            let project = CompositionProject(
                baseAssetURL: options.baseURL,
                layers: [
                    CompositionLayer(
                        assetURL: options.insertURL,
                        insertTime: CMTime(seconds: 1.0, preferredTimescale: 600),
                        mute: false
                    )
                ]
            )
            _ = try await compositionEngine.stitch(project: project, outputURL: task2OutputURL)
            let info = try await inspectAsset(at: task2OutputURL)
            try require(FileManager.default.fileExists(atPath: task2OutputURL.path), "Task2 stitched output file missing")
            try require(info.videoTrackCount >= 1, "Task2 stitched output has no video track")
            try require(info.durationSeconds > 2.70 && info.durationSeconds < 3.40, "Task2 duration not in expected stitched range")
            stitchOutputURL = task2OutputURL
            if options.task == .task2 || options.task == .all {
                let durationText = String(format: "%.3f", info.durationSeconds)
                print("TASK2 PASS duration=\(durationText) videoTracks=\(info.videoTrackCount) audioTracks=\(info.audioTrackCount)")
            }
        }

        if options.task == .task3 || options.task == .all {
            guard let trimSourceURL = stitchOutputURL else {
                throw SmokeError.assertionFailed("Task3 could not resolve trim source")
            }

            let task3OutputURL = options.tempDirectory.appendingPathComponent("task3-trimmed.mp4")
            let deleteRanges = [
                CutRange(
                    start: CMTime(seconds: 0.50, preferredTimescale: 600),
                    end: CMTime(seconds: 0.90, preferredTimescale: 600)
                ),
                CutRange(
                    start: CMTime(seconds: 2.00, preferredTimescale: 600),
                    end: CMTime(seconds: 2.40, preferredTimescale: 600)
                )
            ]
            let trimProject = TrimProject(sourceURL: trimSourceURL, deleteRanges: deleteRanges)
            _ = try await trimEngine.export(project: trimProject, outputURL: task3OutputURL)
            let info = try await inspectAsset(at: task3OutputURL)
            try require(FileManager.default.fileExists(atPath: task3OutputURL.path), "Task3 trim output file missing")
            try require(info.videoTrackCount >= 1, "Task3 trim output has no video track")
            try require(info.durationSeconds > 1.90 && info.durationSeconds < 2.50, "Task3 duration not in expected trimmed range")
            let durationText = String(format: "%.3f", info.durationSeconds)
            print("TASK3 PASS duration=\(durationText) videoTracks=\(info.videoTrackCount) audioTracks=\(info.audioTrackCount)")
        }
    }

    private static func inspectAsset(at url: URL) async throws -> AssetInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        return AssetInfo(
            durationSeconds: max(0, duration.seconds),
            videoTrackCount: videoTracks.count,
            audioTrackCount: audioTracks.count
        )
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw SmokeError.assertionFailed(message)
        }
    }
}

private enum SmokeError: LocalizedError {
    case usage(String)
    case assertionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .usage(message), let .assertionFailed(message):
            return message
        }
    }
}
