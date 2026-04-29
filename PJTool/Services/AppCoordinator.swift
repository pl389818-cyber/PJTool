//
//  AppCoordinator.swift
//  PJTool
//
//  Created by Codex on 2026/4/30.
//

import AppKit
import AVFoundation
import Combine
import CoreGraphics
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var isRecordingArmed = false
    @Published var enableCameraPiP = false {
        didSet {
            guard enableCameraPiP != oldValue else { return }
            if !enableCameraPiP {
                hidePiPPreview()
            }
        }
    }
    @Published var pipLayout = PiPLayoutState.default
    @Published var pipAspectRatio: PiPAspectRatio = .auto {
        didSet {
            guard pipAspectRatio != oldValue else { return }
            pipLayout.aspectRatio = pipAspectRatio
            let nextAspectRatio = pipAspectRatio
            DispatchQueue.main.async { [weak self] in
                self?.pipController.updateAspectRatio(nextAspectRatio)
            }
        }
    }
    @Published var pipWindowConfig: PiPWindowConfig = .default {
        didSet {
            guard pipWindowConfig != oldValue else { return }
            pipController.applyWindowConfig(pipWindowConfig)
        }
    }
    @Published var pipAudioPreviewConfig: PiPAudioPreviewConfig = .default {
        didSet {
            guard pipAudioPreviewConfig != oldValue else { return }
            pipPreviewRuntime.applyPreviewAudioConfig(pipAudioPreviewConfig)
        }
    }
    @Published var pipProcessingConfig: PiPProcessingConfig = .default
    @Published var selectedSettingsSection: SettingsSection = .recording
    @Published var isSidebarCollapsed = false
    @Published var sidebarWidth: CGFloat = 280

    @Published private(set) var statusMessage = "待机"
    @Published private(set) var pipStatusMessage = "PiP 待机"
    @Published private(set) var isPiPPreviewVisible = false
    @Published private(set) var recorderState: RecordingState = .idle

    let audioEngine: AudioInputEngine
    let pipPreviewRuntime: PiPPreviewRuntime
    let pipController: PiPOverlayWindowController
    let recordingControlController: RecordingControlWindowController
    let recorder: ScreenRecorderEngine
    let importEngine: ImportCompositeEngine

    private var cancellables: Set<AnyCancellable> = []
    private var hasRequestedLaunchPermissions = false
    private var shouldRestoreMainWindowAfterRecording = false

    convenience init() {
        self.init(
            audioEngine: AudioInputEngine(),
            recordingCameraEngine: CameraEngine(),
            pipPreviewRuntime: PiPPreviewRuntime(),
            pipController: PiPOverlayWindowController(),
            recordingControlController: RecordingControlWindowController(),
            importEngine: ImportCompositeEngine()
        )
    }

    init(
        audioEngine: AudioInputEngine,
        recordingCameraEngine: CameraEngine,
        pipPreviewRuntime: PiPPreviewRuntime,
        pipController: PiPOverlayWindowController,
        recordingControlController: RecordingControlWindowController,
        importEngine: ImportCompositeEngine
    ) {
        self.audioEngine = audioEngine
        self.pipPreviewRuntime = pipPreviewRuntime
        self.pipController = pipController
        self.recordingControlController = recordingControlController
        self.importEngine = importEngine
        self.recorder = ScreenRecorderEngine(cameraEngine: recordingCameraEngine)
        self.pipController.onVisibilityChanged = { [weak self] isVisible in
            guard let self else { return }
            if isVisible {
                self.isPiPPreviewVisible = true
                self.pipStatusMessage = "PiP 预览已显示"
            } else {
                self.isPiPPreviewVisible = false
                self.pipPreviewRuntime.stopPreview()
                self.pipStatusMessage = "PiP 预览已收起"
            }
            if self.recorderState.isRecording {
                Task { [weak self] in
                    guard let self else { return }
                    await self.syncPiPWindowCaptureState()
                }
            }
        }
        self.recordingControlController.onStartRequested = { [weak self] in
            self?.beginRecordingFromOverlay()
        }
        self.recordingControlController.onStopRequested = { [weak self] in
            self?.stopRecordingAndRestoreMonitoring()
        }
        bindState()
    }

    var canStartRecording: Bool {
        !recorderState.isBusy && !recorderState.isRecording && !isRecordingArmed
    }

    var canStopRecording: Bool {
        (recorderState.isRecording || recorder.state.isRecording) && !recorderState.isBusy
    }

    var isAudioAuthorized: Bool {
        audioEngine.authorizationStatus == .authorized
    }

    var isCameraAuthorized: Bool {
        pipPreviewRuntime.authorizationStatus == .authorized
    }

    func bootstrap() {
        audioEngine.refreshSources()
        pipPreviewRuntime.refreshSources()
        pipPreviewRuntime.refreshAudioSources()
        if isAudioAuthorized {
            audioEngine.startMonitoringIfNeeded()
        }
        pipController.applyWindowConfig(pipWindowConfig)
        pipPreviewRuntime.applyPreviewAudioConfig(pipAudioPreviewConfig)
    }

    func requestPermissionsOnLaunchIfNeeded() {
        guard !hasRequestedLaunchPermissions else { return }
        hasRequestedLaunchPermissions = true
        _ = requestScreenRecordingAccessIfNeeded()
        requestPiPPermissionsSequentially()
    }

    private func requestPiPPermissionsSequentially() {
        if pipPreviewRuntime.authorizationStatus == .notDetermined {
            pipPreviewRuntime.requestCameraAccess { [weak self] in
                self?.requestPiPMicrophonePermissionIfNeeded()
            }
            return
        }
        requestPiPMicrophonePermissionIfNeeded()
    }

    private func requestPiPMicrophonePermissionIfNeeded() {
        guard pipPreviewRuntime.microphoneAuthorizationStatus == .notDetermined else { return }
        pipPreviewRuntime.requestMicrophoneAccess()
    }

    func showPiPPreview(on screen: NSScreen? = nil) {
        print("[PiP] show request enable=\(enableCameraPiP) cameraAuth=\(isCameraAuthorized) selectedCamera=\(pipPreviewRuntime.selectedSourceID ?? "nil")")
        guard enableCameraPiP else {
            pipStatusMessage = "PiP 已关闭，请先启用摄像头 PiP。"
            print("[PiP] aborted: enableCameraPiP=false")
            return
        }
        guard isCameraAuthorized else {
            pipStatusMessage = "摄像头权限未授权，无法显示 PiP 预览。"
            print("[PiP] aborted: camera unauthorized")
            return
        }
        if pipPreviewRuntime.selectedSourceID == nil {
            pipPreviewRuntime.refreshSources()
        }
        guard pipPreviewRuntime.selectedSourceID != nil else {
            pipStatusMessage = "未发现可用摄像头，无法显示 PiP 预览。"
            print("[PiP] aborted: no selected camera after refresh")
            return
        }

        let targetScreen = screen
            ?? activeScreenByPointer()
            ?? NSApp.keyWindow?.screen
            ?? NSApp.mainWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let targetScreen else {
            print("[PiP] aborted: no target screen")
            return
        }
        print("[PiP] target screen visibleFrame=\(NSStringFromRect(targetScreen.visibleFrame))")

        pipStatusMessage = "PiP 预览弹出中..."
        pipPreviewRuntime.applyPreviewAudioConfig(pipAudioPreviewConfig)
        pipPreviewRuntime.startPreviewIfNeeded()
        pipLayout.aspectRatio = pipAspectRatio
        let layout = PiPLayoutState(
            normalizedRect: pipLayout.normalizedRect,
            aspectRatio: pipAspectRatio
        )
        pipLayout = layout
        let didShow = pipController.show(session: pipPreviewRuntime.previewSession, on: targetScreen, layout: layout)
        print("[PiP] didShow=\(didShow) visible=\(pipController.isVisible)")
        if !didShow {
            pipStatusMessage = "PiP 预览窗口显示失败，请检查系统窗口权限与当前 Space。"
        }
    }

    func activatePiPPreview(on screen: NSScreen? = nil) {
        if !enableCameraPiP {
            enableCameraPiP = true
        }
        DispatchQueue.main.async { [weak self] in
            self?.showPiPPreview(on: screen)
        }
    }

    func hidePiPPreview() {
        pipLayout = pipController.currentLayoutState()
        pipController.hide()
    }

    func startRecordingFromCurrentConfig(preferredScreen: NSScreen? = nil) {
        guard canStartRecording else {
            statusMessage = unavailableReason()
            return
        }
        isRecordingArmed = true
        let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first
        recordingControlController.setMode(.readyToStart)
        recordingControlController.show(on: screen)
        statusMessage = "点击悬浮小相机开始录屏"
    }

    func stopRecordingAndRestoreMonitoring() {
        guard canStopRecording else { return }
        isRecordingArmed = false
        recordingControlController.setMode(.stopping)
        statusMessage = "正在停止录屏..."
        Task { [weak self] in
            guard let self else { return }
            await recorder.stopRecording()
            pipLayout = pipController.currentLayoutState()
            recordingControlController.hide()
            if isAudioAuthorized {
                audioEngine.startMonitoringIfNeeded()
            }
            restoreMainWindowAfterRecording()
        }
    }

    private func bindState() {
        pipPreviewRuntime.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        audioEngine.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        recorder.$statusMessage
            .receive(on: RunLoop.main)
            .assign(to: &$statusMessage)

        recorder.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] nextState in
                self?.recorderState = nextState
                self?.syncRecordingUI(for: nextState)
            }
            .store(in: &cancellables)

        pipController.$layoutState
            .receive(on: RunLoop.main)
            .sink { [weak self] layout in
                self?.pipLayout = layout
                if self?.pipAspectRatio != layout.aspectRatio {
                    self?.pipAspectRatio = layout.aspectRatio
                }
            }
            .store(in: &cancellables)
    }

    private func unavailableReason() -> String {
        return "当前状态不可开始录制。"
    }

    private func hideMainWindowForRecording() {
        for window in NSApp.windows where !(window is NSPanel) {
            window.orderOut(nil)
        }
    }

    private func restoreMainWindowAfterRecording() {
        guard shouldRestoreMainWindowAfterRecording else { return }
        shouldRestoreMainWindowAfterRecording = false
        recordingControlController.hide()
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where !(window is NSPanel) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func syncRecordingUI(for state: RecordingState) {
        switch state {
        case .recording:
            isRecordingArmed = false
            hideMainWindowForRecording()
            recordingControlController.setMode(.recording)
            let screen = NSScreen.main ?? NSScreen.screens.first
            recordingControlController.show(on: screen)
        case .idle:
            isRecordingArmed = false
            recordingControlController.hide()
            restoreMainWindowAfterRecording()
        case .failed:
            isRecordingArmed = false
            recordingControlController.hide()
            restoreMainWindowAfterRecording()
            if isAudioAuthorized {
                audioEngine.startMonitoringIfNeeded()
            }
        case .preparing, .stopping:
            break
        }
    }

    private func syncPiPWindowCaptureState() async {
        guard recorderState.isRecording else { return }
        let pipWindowID = isPiPPreviewVisible ? pipController.currentWindowID : nil
        await recorder.updatePiPWindowCapture(windowID: pipWindowID)
    }

    private func beginRecordingFromOverlay() {
        guard isRecordingArmed else { return }
        guard !recorderState.isBusy && !recorderState.isRecording else {
            isRecordingArmed = false
            recordingControlController.hide()
            statusMessage = unavailableReason()
            return
        }
        guard requestScreenRecordingAccessIfNeeded() else {
            isRecordingArmed = false
            recordingControlController.hide()
            statusMessage = "请在 系统设置 > 隐私与安全性 > 屏幕与系统音频录制 中允许 PJTool 后重试。"
            return
        }

        audioEngine.stopMonitoring()
        pipLayout.aspectRatio = pipAspectRatio
        shouldRestoreMainWindowAfterRecording = true
        recordingControlController.setMode(.recording)
        statusMessage = "准备录屏..."

        // 录屏主成片以“屏幕真实内容”为准，不再叠加独立摄像头二轨。
        let shouldCaptureCameraTrack = false
        let shouldCaptureMicrophone = isAudioAuthorized
            && audioEngine.selectedSourceID != nil

        let request = RecordingRequest(
            microphoneDeviceID: shouldCaptureMicrophone ? audioEngine.selectedSourceID : nil,
            cameraDeviceID: shouldCaptureCameraTrack ? pipPreviewRuntime.selectedSourceID : nil,
            cameraAudioDeviceID: shouldCaptureCameraTrack ? pipPreviewRuntime.selectedAudioSourceID : nil,
            pipWindowID: isPiPPreviewVisible ? pipController.currentWindowID : nil,
            pipLayout: pipLayout,
            pipAspectRatio: pipAspectRatio,
            pipProcessingConfig: pipProcessingConfig,
            pipAudioPreviewConfig: pipAudioPreviewConfig
        )

        let screen = NSScreen.main ?? NSScreen.screens.first
        Task { [weak self] in
            guard let self else { return }
            await recorder.startRecording(request: request, preferredScreen: screen)
            if self.recorder.state.isRecording {
                self.recordingControlController.setMode(.recording)
                self.recordingControlController.show(on: screen)
            } else {
                self.isRecordingArmed = false
                self.recordingControlController.hide()
                if case .failed = self.recorder.state,
                   !self.statusMessage.contains("屏幕录制权限"),
                   !self.statusMessage.contains("启动失败") {
                    self.statusMessage = "启动失败：请在 系统设置 > 隐私与安全性 > 屏幕与系统音频录制 中允许 PJTool 后重试。"
                }
                self.restoreMainWindowAfterRecording()
                if self.isAudioAuthorized {
                    self.audioEngine.startMonitoringIfNeeded()
                }
            }
        }
    }

    private func activeScreenByPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })
    }

    @discardableResult
    private func requestScreenRecordingAccessIfNeeded() -> Bool {
        if #available(macOS 11.0, *) {
            if CGPreflightScreenCaptureAccess() {
                return true
            }
            return CGRequestScreenCaptureAccess()
        }
        return true
    }
}
