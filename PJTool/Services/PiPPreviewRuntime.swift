//
//  PiPPreviewRuntime.swift
//  PJTool
//
//  Created by Codex on 2026/5/1.
//

import AppKit
@preconcurrency import AVFoundation
import Combine
import CoreMedia
import Foundation

final class PiPPreviewRuntime: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: AVAuthorizationStatus
    @Published private(set) var microphoneAuthorizationStatus: AVAuthorizationStatus
    @Published private(set) var sources: [CameraSource] = []
    @Published private(set) var audioSources: [AudioInputSource] = []
    @Published private(set) var selectedSourceID: String?
    @Published private(set) var selectedAudioSourceID: String?
    @Published private(set) var previewAudioConfig: PiPAudioPreviewConfig = .default
    @Published private(set) var previewAudioLevel: Double = 0
    @Published private(set) var isPreviewing = false
    @Published private(set) var infoMessage: String?
    @Published private(set) var lastVideoRefreshAt: Date?
    @Published private(set) var lastAudioRefreshAt: Date?
    @Published private(set) var lastVideoEnumeratedCount = 0
    @Published private(set) var lastVideoAvailableCount = 0
    @Published private(set) var lastAudioEnumeratedCount = 0
    @Published private(set) var lastAudioAvailableCount = 0
    @Published private(set) var lastVideoDiscoveryCount = 0
    @Published private(set) var lastAudioDiscoveryCount = 0
    @Published private(set) var lastVideoUsedLegacyFallback = false
    @Published private(set) var lastAudioUsedLegacyFallback = false
    @Published private(set) var lastVideoIncludedSystemDefault = false

    private let session = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private var previewAudioOutput: AVCaptureAudioPreviewOutput?
    private let isPreviewAudioPlaybackEnabled = ProcessInfo.processInfo.environment["PJTOOL_ENABLE_PIP_AUDIO_PREVIEW"] == "1"

    private let sessionQueue = DispatchQueue(label: "pjtool.pip.preview.session")
    private let videoSampleQueue = DispatchQueue(label: "pjtool.pip.preview.video.sample")
    private let audioSampleQueue = DispatchQueue(label: "pjtool.pip.preview.audio.sample")
    private var observers: [NSObjectProtocol] = []

    private let floorLevel: Double = 0.02
    private let decayFactor: Double = 0.84
    private var hasWarnedPreviewAudioPlaybackUnavailable = false
    private var cameraRefreshAttempt = 0
    private var audioRefreshAttempt = 0
    private let maxRefreshAttempt = 2

    var previewSession: AVCaptureSession { session }
    var onProcessingSample: ((CameraProcessingSample) -> Void)?

    init(
        permissionService: CameraPermissionService = .shared,
        deviceCatalog: CameraDeviceCatalog = .shared
    ) {
        self.permissionService = permissionService
        self.deviceCatalog = deviceCatalog
        self.authorizationStatus = permissionService.cameraAuthorizationStatus()
        self.microphoneAuthorizationStatus = permissionService.microphoneAuthorizationStatus()
        super.init()
        configureObservers()
        refreshSources()
        refreshAudioSources()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        sessionQueue.sync {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func requestCameraAccess(onResolved: (() -> Void)? = nil) {
        permissionService.requestCameraAccess { [weak self] granted, status in
            DispatchQueue.main.async {
                guard let self else {
                    onResolved?()
                    return
                }
                self.authorizationStatus = status
                self.infoMessage = granted ? "摄像头权限已授权，正在刷新设备..." : "摄像头权限未授权。"
                self.refreshSources()
                onResolved?()
            }
        }
    }

    func requestMicrophoneAccess(onResolved: (() -> Void)? = nil) {
        permissionService.requestMicrophoneAccess { [weak self] granted, status in
            DispatchQueue.main.async {
                guard let self else {
                    onResolved?()
                    return
                }
                self.microphoneAuthorizationStatus = status
                if granted {
                    self.refreshAudioSources()
                } else {
                    self.infoMessage = "麦克风权限未授权（仅影响 PiP 监听与摄像头音轨）。"
                }
                onResolved?()
            }
        }
    }

    func refreshSources() {
        authorizationStatus = permissionService.cameraAuthorizationStatus()
        let snapshot = deviceCatalog.fetchVideoSnapshot(includeOffline: true)
        let mapped = snapshot.devices
        sources = mapped
        lastVideoRefreshAt = Date()
        lastVideoEnumeratedCount = mapped.count
        lastVideoAvailableCount = mapped.filter(\.isAvailable).count
        lastVideoDiscoveryCount = snapshot.discoveryCount
        lastVideoUsedLegacyFallback = snapshot.usedLegacyFallback
        lastVideoIncludedSystemDefault = snapshot.includedSystemDefault
        handleVideoSourceFallback(using: mapped)
        updateVideoAvailabilityMessage(using: mapped)

        if authorizationStatus == .authorized,
           mapped.isEmpty,
           cameraRefreshAttempt < maxRefreshAttempt {
            cameraRefreshAttempt += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.refreshSources()
            }
        } else if !mapped.isEmpty {
            cameraRefreshAttempt = 0
        }
    }

    func refreshAudioSources() {
        microphoneAuthorizationStatus = permissionService.microphoneAuthorizationStatus()
        let snapshot = deviceCatalog.fetchAudioSnapshot(includeOffline: true)
        let mapped = snapshot.devices
        audioSources = mapped
        lastAudioRefreshAt = Date()
        lastAudioEnumeratedCount = mapped.count
        lastAudioAvailableCount = mapped.filter(\.isAvailable).count
        lastAudioDiscoveryCount = snapshot.discoveryCount
        lastAudioUsedLegacyFallback = snapshot.usedLegacyFallback
        handleAudioSourceFallback(using: mapped)

        if microphoneAuthorizationStatus == .authorized,
           mapped.isEmpty,
           audioRefreshAttempt < maxRefreshAttempt {
            audioRefreshAttempt += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.refreshAudioSources()
            }
        } else if !mapped.isEmpty {
            audioRefreshAttempt = 0
        }
    }

    func selectSource(withID id: String) {
        guard selectedSourceID != id else { return }
        selectedSourceID = id
        if let source = sources.first(where: { $0.id == id }) {
            infoMessage = "当前 PiP 摄像头：\(source.name)"
        } else {
            infoMessage = nil
        }
        if isPreviewing {
            rebuildPreviewSession(forceRestartRunningSession: true)
        }
    }

    func selectAudioSource(withID id: String) {
        guard selectedAudioSourceID != id else { return }
        selectedAudioSourceID = id
        if let source = audioSources.first(where: { $0.id == id }) {
            infoMessage = "当前 PiP 麦克风：\(source.name)"
        } else {
            infoMessage = nil
        }
        if isPreviewing {
            rebuildPreviewSession(forceRestartRunningSession: true)
        }
    }

    func applyPreviewAudioConfig(_ config: PiPAudioPreviewConfig) {
        previewAudioConfig = PiPAudioPreviewConfig(
            isPreviewMuted: config.isPreviewMuted,
            previewVolume: config.clampedVolume
        )
        guard let previewAudioOutput else { return }
        let volume = Float(previewAudioConfig.clampedVolume)
        sessionQueue.async {
            previewAudioOutput.volume = volume
        }
    }

    func startPreviewIfNeeded() {
        guard authorizationStatus == .authorized else { return }
        guard !isPreviewing else { return }

        if selectedSourceID == nil {
            refreshSources()
        }
        if selectedAudioSourceID == nil {
            refreshAudioSources()
        }

        isPreviewing = true
        rebuildPreviewSession(forceRestartRunningSession: false)
    }

    func stopPreview() {
        guard isPreviewing else { return }
        isPreviewing = false
        previewAudioLevel = 0
        onProcessingSample = nil
        let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private let permissionService: CameraPermissionService
    private let deviceCatalog: CameraDeviceCatalog

    private func configureObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVCaptureDevice.wasConnectedNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self else { return }
                if let device = note.object as? AVCaptureDevice {
                    if device.hasMediaType(.video) {
                        self.infoMessage = "检测到新摄像头：\(device.localizedName)"
                    } else if device.hasMediaType(.audio) {
                        self.infoMessage = "检测到新音频设备：\(device.localizedName)"
                    }
                }
                self.refreshSources()
                self.refreshAudioSources()
                if self.isPreviewing {
                    self.rebuildPreviewSession(forceRestartRunningSession: false)
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self else { return }
                guard let device = note.object as? AVCaptureDevice else {
                    self.refreshSources()
                    self.refreshAudioSources()
                    if self.isPreviewing {
                        self.rebuildPreviewSession(forceRestartRunningSession: false)
                    }
                    return
                }
                if device.uniqueID == self.selectedSourceID {
                    self.infoMessage = "当前 PiP 摄像头断开，已自动回退。"
                } else if device.uniqueID == self.selectedAudioSourceID {
                    self.infoMessage = "当前 PiP 麦克风断开，已自动回退。"
                }
                self.refreshSources()
                self.refreshAudioSources()
                if self.isPreviewing {
                    self.rebuildPreviewSession(forceRestartRunningSession: false)
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.refreshSources()
                self.refreshAudioSources()
            }
        )
    }

    private func rebuildPreviewSession(forceRestartRunningSession: Bool) {
        guard let sourceID = effectiveVideoSourceID() else {
            infoMessage = "所选摄像头不可用，等待自动回退。"
            return
        }

        let selectedAudioID = effectiveAudioSourceID()
        let includeAudioInput = microphoneAuthorizationStatus == .authorized && selectedAudioID != nil
        let shouldEnableAudioPreview = isPreviewing && !previewAudioConfig.isPreviewMuted

        let videoSnapshot = deviceCatalog.fetchVideoSnapshot(includeOffline: true)
        let audioSnapshot = deviceCatalog.fetchAudioSnapshot(includeOffline: true)
        guard let videoDevice = videoSnapshot.devices
            .first(where: { $0.id == sourceID })
            .flatMap({ Self.makeDevice(from: $0) }) else {
            refreshSources()
            return
        }
        let audioDevice = audioSnapshot.devices
            .first(where: { $0.id == selectedAudioID })
            .flatMap { Self.makeAudioDevice(from: $0) }

        let session = self.session
        let videoDataOutput = self.videoDataOutput
        let audioDataOutput = self.audioDataOutput
        let videoSampleQueue = self.videoSampleQueue
        let audioSampleQueue = self.audioSampleQueue
        let previewAudioConfig = self.previewAudioConfig

        sessionQueue.async {
            do {
                let shouldRestartRunningSession = forceRestartRunningSession && session.isRunning
                if shouldRestartRunningSession {
                    session.stopRunning()
                }

                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                let audioInput = try audioDevice.map(AVCaptureDeviceInput.init(device:))

                session.beginConfiguration()
                session.inputs.forEach { session.removeInput($0) }
                session.outputs.forEach { session.removeOutput($0) }

                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                }
                if let audioInput, session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }

                videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
                audioDataOutput.setSampleBufferDelegate(nil, queue: nil)

                videoDataOutput.alwaysDiscardsLateVideoFrames = true
                videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                videoDataOutput.setSampleBufferDelegate(self, queue: videoSampleQueue)
                if session.canAddOutput(videoDataOutput) {
                    session.addOutput(videoDataOutput)
                }

                if includeAudioInput {
                    audioDataOutput.setSampleBufferDelegate(self, queue: audioSampleQueue)
                    if session.canAddOutput(audioDataOutput) {
                        session.addOutput(audioDataOutput)
                    }

                    if shouldEnableAudioPreview {
                        if self.previewAudioOutput == nil {
                            self.previewAudioOutput = AVCaptureAudioPreviewOutput()
                        }
                        if let previewAudioOutput = self.previewAudioOutput {
                            previewAudioOutput.volume = Float(previewAudioConfig.clampedVolume)
                            if session.canAddOutput(previewAudioOutput) {
                                session.addOutput(previewAudioOutput)
                            }
                        }
                    }
                }

                session.commitConfiguration()

                if self.isPreviewing && !session.isRunning {
                    session.startRunning()
                }
            } catch {
                DispatchQueue.main.async {
                    self.infoMessage = "摄像头会话初始化失败，已自动回退：\(error.localizedDescription)"
                    self.refreshSources()
                    self.refreshAudioSources()
                }
            }
        }
    }

    private func effectiveVideoSourceID() -> String? {
        let availableIDs = Set(sources.filter(\.isAvailable).map(\.id))
        if let selected = selectedSourceID, availableIDs.contains(selected) {
            return selected
        }
        refreshSources()
        return preferredVideoSource(in: sources.filter(\.isAvailable))?.id
    }

    private func effectiveAudioSourceID() -> String? {
        let availableIDs = Set(audioSources.filter(\.isAvailable).map(\.id))
        if let selected = selectedAudioSourceID, availableIDs.contains(selected) {
            return selected
        }
        refreshAudioSources()
        if let fallback = preferredAudioSource(in: audioSources.filter(\.isAvailable))?.id {
            selectedAudioSourceID = fallback
            return fallback
        }
        return nil
    }

    private func handleVideoSourceFallback(using discovered: [CameraSource]) {
        let available = discovered.filter(\.isAvailable)
        if available.isEmpty {
            selectedSourceID = nil
            return
        }
        if let selectedSourceID, available.contains(where: { $0.id == selectedSourceID }) {
            return
        }
        selectedSourceID = preferredVideoSource(in: available)?.id ?? available.first?.id
    }

    private func handleAudioSourceFallback(using discovered: [AudioInputSource]) {
        let available = discovered.filter(\.isAvailable)
        if available.isEmpty {
            selectedAudioSourceID = nil
            return
        }
        if let selectedAudioSourceID, available.contains(where: { $0.id == selectedAudioSourceID }) {
            return
        }
        selectedAudioSourceID = preferredAudioSource(in: available)?.id ?? available.first?.id
    }

    private func updateVideoAvailabilityMessage(using discovered: [CameraSource]) {
        switch authorizationStatus {
        case .notDetermined:
            infoMessage = "尚未授予摄像头权限，请先授权后再刷新设备。"
        case .denied:
            infoMessage = "摄像头权限已被拒绝，请到系统设置 > 隐私与安全性 > 摄像头中允许 PJTool。"
        case .restricted:
            infoMessage = "摄像头权限受系统限制，当前无法访问摄像头。"
        case .authorized:
            if discovered.isEmpty {
                infoMessage = "当前未发现任何摄像头设备，请检查内建摄像头、外接摄像头或 Continuity Camera 是否可用。"
            } else if discovered.allSatisfy({ !$0.isAvailable }) {
                infoMessage = "已识别到摄像头条目，但它们当前均处于离线状态。"
            } else if let selectedSourceID,
                      let selected = discovered.first(where: { $0.id == selectedSourceID }),
                      selected.isAvailable {
                infoMessage = nil
            }
        @unknown default:
            break
        }
    }

    private func preferredVideoSource(in sources: [CameraSource]) -> CameraSource? {
        if let builtIn = sources.first(where: \.isBuiltIn) {
            return builtIn
        }
        if let continuity = sources.first(where: \.isContinuity) {
            return continuity
        }
        return sources.first
    }

    private func preferredAudioSource(in sources: [AudioInputSource]) -> AudioInputSource? {
        if let builtIn = sources.first(where: \.isBuiltIn) {
            return builtIn
        }
        if let continuity = sources.first(where: \.isContinuity) {
            return continuity
        }
        return sources.first
    }

    private static func makeDevice(from source: CameraSource) -> AVCaptureDevice? {
        CameraDeviceLookup.videoDevice(uniqueID: source.id)
    }

    private static func makeAudioDevice(from source: AudioInputSource) -> AVCaptureDevice? {
        CameraDeviceLookup.audioDevice(uniqueID: source.id)
    }
}

extension PiPPreviewRuntime: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    private struct SendableSampleBuffer: @unchecked Sendable {
        let value: CMSampleBuffer
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let incomingLevel = CameraAudioLevelExtractor.extract(from: sampleBuffer)
        let sendableSample = SendableSampleBuffer(value: sampleBuffer)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if output === self.videoDataOutput {
                self.onProcessingSample?(
                    CameraProcessingSample(
                        sampleBuffer: sendableSample.value,
                        source: .livePreview
                    )
                )
                return
            }
            if output === self.audioDataOutput {
                let decayed = self.previewAudioLevel * self.decayFactor
                let smoothed = max(decayed, incomingLevel)
                self.previewAudioLevel = smoothed < self.floorLevel ? 0 : smoothed
                if !self.previewAudioConfig.isPreviewMuted,
                   !self.isPreviewAudioPlaybackEnabled,
                   !self.hasWarnedPreviewAudioPlaybackUnavailable {
                    self.hasWarnedPreviewAudioPlaybackUnavailable = true
                    self.infoMessage = "当前运行环境不支持 PiP 监听回放，已切换为仅电平显示。"
                }
            }
        }
    }
}

private enum CameraDeviceLookup {
    static func videoDevice(uniqueID: String) -> AVCaptureDevice? {
        let all = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .continuityCamera,
                .external,
                .deskViewCamera
            ],
            mediaType: .video,
            position: .unspecified
        ).devices + AVCaptureDevice.devices(for: .video)
        return deduped(all).first(where: { $0.uniqueID == uniqueID })
    }

    static func audioDevice(uniqueID: String) -> AVCaptureDevice? {
        let all = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices + AVCaptureDevice.devices(for: .audio)
        return deduped(all).first(where: { $0.uniqueID == uniqueID })
    }

    private static func deduped(_ devices: [AVCaptureDevice]) -> [AVCaptureDevice] {
        Array(
            Dictionary(
                devices.map { ($0.uniqueID, $0) },
                uniquingKeysWith: { current, _ in current }
            ).values
        )
    }
}

extension PiPPreviewRuntime {
    struct SessionSnapshot: Equatable {
        let videoDeviceID: String
        let audioDeviceID: String?
    }

    var sessionSnapshot: SessionSnapshot? {
        let selectedVideoID = selectedSourceID
        guard let selectedVideoID else { return nil }
        return SessionSnapshot(
            videoDeviceID: selectedVideoID,
            audioDeviceID: selectedAudioSourceID
        )
    }
}
