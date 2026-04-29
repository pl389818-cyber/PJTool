//
//  ScreenRecorderEngine.swift
//  PJTool
//
//  Created by Codex on 2026/4/29.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenRecorderEngine: NSObject, ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var statusMessage: String = "待机"
    @Published private(set) var lastOutputURL: URL?
    @Published private(set) var lastArtifact: RecordingArtifact?

    private let cameraEngine: CameraEngine
    private let compositionEngine = CompositionExportEngine()
    private let pipProcessingEngine = PiPFrameProcessingEngine()

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var currentRequest: RecordingRequest?
    private var activeCaptureDisplayID: CGDirectDisplayID?
    private var includesPiPWindowInScreenCapture = false

    private var screenRawURL: URL?
    private var cameraRawURL: URL?
    private var cameraFramingSidecarURL: URL?
    private var currentFaceKeyframes: [FaceFramingKeyframe] = []

    private var screenStopContinuation: CheckedContinuation<Void, Error>?
    private var recordingStartContinuation: CheckedContinuation<Void, Error>?
    private var hasRecordingOutputStarted = false
    private var stopScreenCaptureTimedOut = false
    private let screenSampleQueue = DispatchQueue(label: "PJTool.screen-recorder.screen-sample")
    private let microphoneSampleQueue = DispatchQueue(label: "PJTool.screen-recorder.microphone-sample")

    init(
        cameraEngine: CameraEngine
    ) {
        self.cameraEngine = cameraEngine
        super.init()
    }

    func startRecording(
        request: RecordingRequest,
        preferredScreen: NSScreen?
    ) async {
        guard !state.isBusy else { return }
        guard !state.isRecording else { return }
        if cameraEngine.isRecording {
            _ = try? await cameraEngine.stopRecording()
        }
        state = .preparing
        statusMessage = "准备录屏..."
        currentRequest = request
        lastArtifact = nil

        do {
            let outputContext = try makeOutputContext()
            screenRawURL = outputContext.screenRawURL
            cameraRawURL = outputContext.cameraRawURL
            cameraFramingSidecarURL = outputContext.cameraFramingSidecarURL
            currentFaceKeyframes = []

            pipProcessingEngine.configure(
                processingConfig: request.pipProcessingConfig,
                aspectRatio: request.pipAspectRatio
            )
            pipProcessingEngine.reset()
            cameraEngine.applyPreviewAudioConfig(request.pipAudioPreviewConfig)
            cameraEngine.setProcessingEnabled(true)

            var cameraTrackEnabled = false
            if let cameraID = request.cameraDeviceID, let cameraRawURL {
                cameraEngine.selectSource(withID: cameraID)
                let cameraAudioID = request.cameraAudioDeviceID ?? request.microphoneDeviceID
                if let cameraAudioID {
                    cameraEngine.selectAudioSource(withID: cameraAudioID)
                }
                let snapshot = CameraEngine.SessionSnapshot(
                    videoDeviceID: cameraID,
                    audioDeviceID: cameraAudioID
                )

                cameraEngine.onProcessingSample = { [weak self] sample in
                    guard let self else { return }
                    guard let result = self.pipProcessingEngine.processFrame(from: sample.sampleBuffer) else { return }
                    if let keyframe = result.keyframe {
                        self.currentFaceKeyframes.append(keyframe)
                    }
                }

                do {
                    try await cameraEngine.startRecording(to: cameraRawURL, snapshot: snapshot)
                    cameraTrackEnabled = true
                } catch {
                    cameraEngine.onProcessingSample = nil
                    currentFaceKeyframes = []
                    statusMessage = "摄像头接入异常，已自动降级为仅屏幕录制。"
                }
            }

            let streamBundle = try await buildScreenStream(
                screenRawURL: outputContext.screenRawURL,
                microphoneDeviceID: request.microphoneDeviceID,
                pipWindowID: request.pipWindowID
            )
            stream = streamBundle.stream
            recordingOutput = streamBundle.recordingOutput
            activeCaptureDisplayID = streamBundle.displayID
            includesPiPWindowInScreenCapture = streamBundle.includesPiPWindowInScreenCapture
            hasRecordingOutputStarted = false

            statusMessage = "等待系统开始录屏..."
            try await streamBundle.stream.startCapture()
            try await waitForRecordingStart()
            state = .recording
            let recordingStatus = cameraTrackEnabled ? "录屏中（分轨录制）" : "录屏中（仅屏幕轨）"
            let withMic = request.microphoneDeviceID != nil
            let inputStatus = withMic ? "麦克风：开启" : "麦克风：关闭"
            let pipCaptureStatus = includesPiPWindowInScreenCapture ? "屏幕含 PiP 小窗" : "屏幕不含 PiP 小窗"
            statusMessage = streamBundle.warnsAppWindowExclusion
                ? "\(recordingStatus)，\(inputStatus)，\(pipCaptureStatus)，录屏控制窗可能进入画面。"
                : "\(recordingStatus)，\(inputStatus)，\(pipCaptureStatus)"
        } catch {
            cancelPendingContinuations(with: error)
            if cameraEngine.isRecording {
                _ = try? await cameraEngine.stopRecording()
            }
            cameraEngine.stopPreview()
            cleanupTemporaryState()
            state = .failed(error.localizedDescription)
            statusMessage = "启动失败：\(error.localizedDescription)"
        }
    }

    func stopRecording() async {
        guard !state.isBusy else { return }
        guard stream != nil else { return }
        state = .stopping
        statusMessage = "停止录制..."

        let layout = currentRequest?.pipLayout ?? .default
        cameraEngine.onProcessingSample = nil

        do {
            if let stream {
                try await stopScreenCapture(stream: stream)
            }
            self.stream = nil
            self.recordingOutput = nil

            var capturedCameraURL: URL?
            if cameraEngine.isRecording {
                let rawCameraURL = try await cameraEngine.stopRecording()
                if currentRequest?.cameraDeviceID != nil {
                    capturedCameraURL = rawCameraURL
                } else {
                    capturedCameraURL = nil
                    try? FileManager.default.removeItem(at: rawCameraURL)
                }
            }

            var sidecarURL: URL?
            if let capturedCameraURL {
                let keyframesFromAsset = pipProcessingEngine.processAssetForKeyframes(cameraURL: capturedCameraURL)
                let finalKeyframes = PiPFramingKeyframeNormalizer.normalized(
                    keyframesFromAsset.isEmpty ? currentFaceKeyframes : keyframesFromAsset
                )
                if !finalKeyframes.isEmpty, let candidate = cameraFramingSidecarURL {
                    try writeSidecar(keyframes: finalKeyframes, to: candidate)
                    sidecarURL = candidate
                }
                currentFaceKeyframes = finalKeyframes
            } else {
                currentFaceKeyframes = []
            }

            let screenURL = try ensureURL(screenRawURL, name: "屏幕轨")
            let mergedURL = try makeMergedURL()
            let finalURL = try await compositionEngine.mergeScreenAndCamera(
                screenURL: screenURL,
                cameraURL: capturedCameraURL,
                pipLayout: layout,
                faceFramingKeyframes: currentFaceKeyframes,
                outputURL: mergedURL
            )

            let artifact = RecordingArtifact(
                screenURL: screenURL,
                cameraURL: capturedCameraURL,
                mergedURL: finalURL,
                cameraFramingSidecarURL: sidecarURL
            )
            lastArtifact = artifact
            lastOutputURL = finalURL
            statusMessage = stopScreenCaptureTimedOut
                ? "录制完成：已保存成片（停止阶段触发超时兜底）"
                : "录制完成：已保存成片"
            state = .idle
            cleanupTemporaryState()
        } catch {
            if cameraEngine.isRecording {
                _ = try? await cameraEngine.stopRecording()
            }
            cameraEngine.stopPreview()
            state = .failed(error.localizedDescription)
            statusMessage = "停止失败：\(error.localizedDescription)"
            cleanupTemporaryState()
        }
    }

    func updatePiPWindowCapture(windowID: CGWindowID?) async {
        guard state.isRecording else { return }
        guard let stream else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = resolvedDisplay(from: content, preferredID: activeCaptureDisplayID) else {
                return
            }
            let filterContext = makeDisplayFilterContext(
                from: content,
                display: display,
                pipWindowID: windowID
            )
            try await stream.updateContentFilter(filterContext.filter)
            includesPiPWindowInScreenCapture = filterContext.includesPiPWindowInScreenCapture
        } catch {
            statusMessage = "录屏中：更新 PiP 小窗捕获失败（\(error.localizedDescription)）"
        }
    }

    private func stopScreenCapture(stream: SCStream) async throws {
        stopScreenCaptureTimedOut = false
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        self.screenStopContinuation = continuation
                        Task { @MainActor [weak self] in
                            do {
                                try await stream.stopCapture()
                            } catch {
                                self?.resumeScreenStopContinuation(with: .failure(error))
                            }
                        }
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 6_000_000_000)
                    throw RecorderError.stopTimedOut
                }

                _ = try await group.next()
                group.cancelAll()
            }
        } catch RecorderError.stopTimedOut {
            stopScreenCaptureTimedOut = true
            resumeScreenStopContinuation(with: .success(()))
            if let recordingOutput {
                try? stream.removeRecordingOutput(recordingOutput)
            }
            try? await stream.stopCapture()
        }
    }

    private func buildScreenStream(
        screenRawURL: URL,
        microphoneDeviceID: String?,
        pipWindowID: CGWindowID?
    ) async throws -> (
        stream: SCStream,
        recordingOutput: SCRecordingOutput,
        warnsAppWindowExclusion: Bool,
        displayID: CGDirectDisplayID,
        includesPiPWindowInScreenCapture: Bool
    ) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainDisplayID = CGMainDisplayID()
        guard let display = resolvedDisplay(from: content, preferredID: mainDisplayID) else {
            throw RecorderError.noDisplay
        }
        let filterContext = makeDisplayFilterContext(
            from: content,
            display: display,
            pipWindowID: pipWindowID
        )

        let configuration = SCStreamConfiguration()
        let scale = max(CGFloat(filterContext.filter.pointPixelScale), 1)
        let captureRect = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))
        configuration.width = max(2, Int((captureRect.width * scale).rounded(.toNearestOrAwayFromZero)))
        configuration.height = max(2, Int((captureRect.height * scale).rounded(.toNearestOrAwayFromZero)))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.capturesAudio = false
        configuration.captureMicrophone = microphoneDeviceID?.isEmpty == false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        if let micID = microphoneDeviceID, !micID.isEmpty {
            configuration.microphoneCaptureDeviceID = micID
        }

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = screenRawURL
        outputConfiguration.videoCodecType = .h264
        outputConfiguration.outputFileType = .mp4

        let stream = SCStream(filter: filterContext.filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenSampleQueue)
        if configuration.captureMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: microphoneSampleQueue)
        }
        let recordingOutput = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)
        return (
            stream: stream,
            recordingOutput: recordingOutput,
            warnsAppWindowExclusion: filterContext.warnsAppWindowExclusion,
            displayID: display.displayID,
            includesPiPWindowInScreenCapture: filterContext.includesPiPWindowInScreenCapture
        )
    }

    private func resolvedDisplay(
        from content: SCShareableContent,
        preferredID: CGDirectDisplayID?
    ) -> SCDisplay? {
        if let preferredID {
            if let matched = content.displays.first(where: { $0.displayID == preferredID }) {
                return matched
            }
        }
        return content.displays.first
    }

    private func makeDisplayFilterContext(
        from content: SCShareableContent,
        display: SCDisplay,
        pipWindowID: CGWindowID?
    ) -> DisplayFilterContext {
        let excludedApplicationBundleIDs = Set(["com.apple.dock", Bundle.main.bundleIdentifier].compactMap { $0 })
        let excludedApplications = content.applications.filter { application in
            excludedApplicationBundleIDs.contains(application.bundleIdentifier)
        }
        let pipIncludedWindows = content.windows.filter { window in
            guard let pipWindowID else { return false }
            return window.windowID == pipWindowID
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: pipIncludedWindows
        )
        let warnsAppWindowExclusion = !excludedApplications.contains { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        return DisplayFilterContext(
            filter: filter,
            warnsAppWindowExclusion: warnsAppWindowExclusion,
            includesPiPWindowInScreenCapture: !pipIncludedWindows.isEmpty
        )
    }

    private func waitForRecordingStart(timeoutNanoseconds: UInt64 = 5_000_000_000) async throws {
        if hasRecordingOutputStarted {
            return
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                if self.hasRecordingOutputStarted {
                    return
                }
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.recordingStartContinuation = continuation
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw RecorderError.startTimedOut
            }

            let result = try await group.next()
            group.cancelAll()
            if let result {
                return result
            }
        }
    }

    private func makeOutputContext() throws -> OutputContext {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PJTool", isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let screenRawURL = folder.appendingPathComponent("screen-\(timestamp).mp4")
        let cameraRawURL = folder.appendingPathComponent("camera-\(timestamp).mov")
        let cameraFramingSidecarURL = folder.appendingPathComponent("camera-framing-\(timestamp).json")
        return OutputContext(
            screenRawURL: screenRawURL,
            cameraRawURL: cameraRawURL,
            cameraFramingSidecarURL: cameraFramingSidecarURL
        )
    }

    private func makeMergedURL() throws -> URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("PJTool", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return folder.appendingPathComponent("PJTool-\(formatter.string(from: Date())).mp4")
    }

    private func ensureURL(_ url: URL?, name: String) throws -> URL {
        guard let url else {
            throw RecorderError.missingIntermediate(name)
        }
        return url
    }

    private func cleanupTemporaryState() {
        hasRecordingOutputStarted = false
        stopScreenCaptureTimedOut = false
        recordingStartContinuation = nil
        screenStopContinuation = nil
        stream = nil
        recordingOutput = nil
        activeCaptureDisplayID = nil
        includesPiPWindowInScreenCapture = false
        screenRawURL = nil
        cameraRawURL = nil
        cameraFramingSidecarURL = nil
        currentFaceKeyframes = []
        cameraEngine.onProcessingSample = nil
        currentRequest = nil
    }

    private func writeSidecar(keyframes: [FaceFramingKeyframe], to url: URL) throws {
        struct Sidecar: Codable {
            let generatedAt: Date
            let keyframes: [FaceFramingKeyframe]
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let sidecar = Sidecar(generatedAt: Date(), keyframes: keyframes)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sidecar).write(to: url)
    }

    private func resumeRecordingStartContinuation(with result: Result<Void, Error>) {
        guard let continuation = recordingStartContinuation else { return }
        recordingStartContinuation = nil
        switch result {
        case .success:
            continuation.resume(returning: ())
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func resumeScreenStopContinuation(with result: Result<Void, Error>) {
        guard let continuation = screenStopContinuation else { return }
        screenStopContinuation = nil
        switch result {
        case .success:
            continuation.resume(returning: ())
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func cancelPendingContinuations(with error: Error) {
        resumeRecordingStartContinuation(with: .failure(error))
        resumeScreenStopContinuation(with: .failure(error))
    }
}

extension ScreenRecorderEngine: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.cancelPendingContinuations(with: error)
            self.state = .failed(error.localizedDescription)
            self.statusMessage = "录屏异常停止：\(error.localizedDescription)"
        }
    }
}

extension ScreenRecorderEngine: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        _ = sampleBuffer
        _ = outputType
    }
}

extension ScreenRecorderEngine: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            self?.hasRecordingOutputStarted = true
            self?.resumeRecordingStartContinuation(with: .success(()))
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.resumeScreenStopContinuation(with: .success(()))
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.cancelPendingContinuations(with: error)
        }
    }
}

extension ScreenRecorderEngine {
    private struct OutputContext {
        let screenRawURL: URL
        let cameraRawURL: URL
        let cameraFramingSidecarURL: URL
    }

    private struct DisplayFilterContext {
        let filter: SCContentFilter
        let warnsAppWindowExclusion: Bool
        let includesPiPWindowInScreenCapture: Bool
    }

    enum RecorderError: LocalizedError {
        case noDisplay
        case missingIntermediate(String)
        case startTimedOut
        case stopTimedOut

        var errorDescription: String? {
            switch self {
            case .noDisplay:
                return "没有可用显示器，无法启动录屏。"
            case let .missingIntermediate(name):
                return "缺少中间文件：\(name)"
            case .startTimedOut:
                return "系统未在预期时间内开始录屏，请检查屏幕录制权限与当前显示器状态。"
            case .stopTimedOut:
                return "停止录屏超时。"
            }
        }
    }
}
