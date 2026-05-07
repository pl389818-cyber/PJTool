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
    @Published private(set) var drawStatusMessage = "屏幕画图待机"
    @Published private(set) var isDrawOverlayVisible = false
    @Published private(set) var isDrawGlobalHotkeysEnabled = false
    @Published private(set) var recorderState: RecordingState = .idle

    let audioEngine: AudioInputEngine
    let pipPreviewRuntime: PiPPreviewRuntime
    let pipController: PiPOverlayWindowController
    let screenDrawToolbarController: ScreenDrawToolbarWindowController
    let screenDrawCanvasController: ScreenDrawCanvasWindowController
    let recordingControlController: RecordingControlWindowController
    let recorder: ScreenRecorderEngine

    private let screenDrawHotkeyService: ScreenDrawHotkeyService
    private let screenDrawExportService = ScreenDrawExportService()
    private var cancellables: Set<AnyCancellable> = []
    private var shouldRestoreMainWindowAfterRecording = false
    private var drawSystemDefinedMonitor: Any?

    convenience init() {
        let drawSessionStore = ScreenDrawSessionStore()
        self.init(
            audioEngine: AudioInputEngine(),
            recordingCameraEngine: CameraEngine(),
            pipPreviewRuntime: PiPPreviewRuntime(),
            pipController: PiPOverlayWindowController(),
            screenDrawToolbarController: ScreenDrawToolbarWindowController(sessionStore: drawSessionStore),
            screenDrawCanvasController: ScreenDrawCanvasWindowController(sessionStore: drawSessionStore),
            recordingControlController: RecordingControlWindowController(),
            screenDrawHotkeyService: ScreenDrawHotkeyService()
        )
    }

    init(
        audioEngine: AudioInputEngine,
        recordingCameraEngine: CameraEngine,
        pipPreviewRuntime: PiPPreviewRuntime,
        pipController: PiPOverlayWindowController,
        screenDrawToolbarController: ScreenDrawToolbarWindowController,
        screenDrawCanvasController: ScreenDrawCanvasWindowController,
        recordingControlController: RecordingControlWindowController,
        screenDrawHotkeyService: ScreenDrawHotkeyService
    ) {
        self.audioEngine = audioEngine
        self.pipPreviewRuntime = pipPreviewRuntime
        self.pipController = pipController
        self.screenDrawToolbarController = screenDrawToolbarController
        self.screenDrawCanvasController = screenDrawCanvasController
        self.recordingControlController = recordingControlController
        self.screenDrawHotkeyService = screenDrawHotkeyService
        self.recorder = ScreenRecorderEngine(cameraEngine: recordingCameraEngine)

        if self.screenDrawToolbarController.drawSessionStore !== self.screenDrawCanvasController.drawSessionStore {
            assertionFailure("Screen drawing toolbar and canvas must share the same session store")
        }

        self.screenDrawCanvasController.drawSessionStore.onSessionEvent = { [weak self] event in
            guard let self else { return }
            self.drawStatusMessage = event
        }

        self.screenDrawHotkeyService.onAction = { [weak self] action in
            self?.handleDrawHotkeyAction(action)
        }
        self.screenDrawHotkeyService.shouldHandleAction = { [weak self] action in
            self?.shouldHandleDrawHotkeyAction(action) ?? false
        }

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

        self.screenDrawToolbarController.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            self.isDrawOverlayVisible = visible
            self.drawStatusMessage = visible ? "屏幕画图工具条已显示" : "屏幕画图工具条已收起"
        }
        self.screenDrawToolbarController.onRequestClose = { [weak self] in
            self?.hideScreenDrawOverlay()
        }
        self.screenDrawToolbarController.onScreenRecoveryEvent = { [weak self] event in
            self?.handleDrawToolbarScreenRecoveryEvent(event)
        }
        self.screenDrawCanvasController.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            if !visible {
                self.isDrawOverlayVisible = false
                self.drawStatusMessage = "屏幕画图画布已收起"
            }
        }
        self.screenDrawCanvasController.onScreenRecoveryEvent = { [weak self] event in
            self?.handleDrawCanvasScreenRecoveryEvent(event)
        }

        bindState()
    }

    deinit {
        if let drawSystemDefinedMonitor {
            NSEvent.removeMonitor(drawSystemDefinedMonitor)
            self.drawSystemDefinedMonitor = nil
        }
        screenDrawHotkeyService.stop()
    }

    var canStartRecording: Bool {
        !recorderState.isBusy && !recorderState.isRecording && !isRecordingArmed
    }

    var canStopRecording: Bool {
        (recorderState.isRecording || recorder.state.isRecording) && !recorderState.isBusy
    }

    var drawHandDrawnIntensity: CGFloat {
        screenDrawCanvasController.drawSessionStore.handDrawnIntensity
    }

    var drawMarkStyle: ScreenDrawMarkStyle {
        screenDrawCanvasController.drawSessionStore.markStyle
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
        configureDrawHotkeysIfNeeded()
    }

    func showPiPPreview(on screen: NSScreen? = nil) {
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

    func showScreenDrawOverlay() {
        guard !isDrawOverlayVisible else { return }
        let targetScreen = activeScreenByPointer()
            ?? NSApp.keyWindow?.screen
            ?? NSApp.mainWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first

        let didShowCanvas = screenDrawCanvasController.show(on: targetScreen)
        if didShowCanvas {
            screenDrawCanvasController.setCanvasInteractionEnabled(true)
            screenDrawToolbarController.show(on: targetScreen)
            isDrawOverlayVisible = true
            drawStatusMessage = "屏幕画图工具条与透明画布已显示"
        } else {
            isDrawOverlayVisible = false
            screenDrawToolbarController.hide()
            drawStatusMessage = "屏幕画图显示失败，请检查当前桌面空间。"
        }
    }

    func hideScreenDrawOverlay() {
        screenDrawToolbarController.hide()
        screenDrawCanvasController.hide()
        isDrawOverlayVisible = false
        drawStatusMessage = "屏幕画图工具条与透明画布已收起"
    }

    func clearScreenDrawCanvas() {
        screenDrawCanvasController.drawSessionStore.clearCanvas()
    }

    func setDrawHandDrawnIntensity(_ value: CGFloat) {
        let clamped = max(0, min(value, 1))
        screenDrawCanvasController.drawSessionStore.handDrawnIntensity = clamped
        drawStatusMessage = "手绘强度：\(Int(clamped * 100))%"
    }

    func setDrawMarkStyle(_ style: ScreenDrawMarkStyle) {
        screenDrawCanvasController.drawSessionStore.markStyle = style
        drawStatusMessage = "对/错风格已切换：\(style.title)"
    }

    func exportScreenDrawCanvasAsPNG() {
        do {
            guard let image = screenDrawCanvasController.snapshotImage() else {
                drawStatusMessage = "导出失败：当前画布不可用。"
                return
            }
            let outputURL = try screenDrawExportService.pickOutputURL()
            try screenDrawExportService.writeTransparentPNG(from: image, to: outputURL)
            drawStatusMessage = "导出成功：\(outputURL.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } catch {
            if let exportError = error as? ScreenDrawExportError, case .cancelled = exportError {
                drawStatusMessage = exportError.errorDescription ?? "已取消导出。"
                return
            }
            drawStatusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    // Compatibility wrappers for existing callers.
    func showScreenDrawingOverlay() {
        showScreenDrawOverlay()
    }

    func hideScreenDrawingOverlay() {
        hideScreenDrawOverlay()
    }

    func endScreenDrawingSession() {
        screenDrawCanvasController.drawSessionStore.resetForNewSession()
        hideScreenDrawOverlay()
        drawStatusMessage = "屏幕画图会话已结束。"
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
        "当前状态不可开始录制。"
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
        await recorder.updatePiPWindowCapture(windowID: pipWindowID, extraWindowIDs: screenDrawWhitelistWindowIDs())
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
            screenDrawWindowIDs: screenDrawWhitelistWindowIDs(),
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

    private func screenDrawWhitelistWindowIDs() -> [CGWindowID] {
        var ids: [CGWindowID] = []
        if isDrawOverlayVisible {
            if let canvasID = screenDrawCanvasController.currentWindowID {
                ids.append(canvasID)
            }
            if let toolbarID = screenDrawToolbarController.currentWindowID {
                ids.append(toolbarID)
            }
        }
        return ids
    }

    private func configureDrawHotkeysIfNeeded() {
        if let drawSystemDefinedMonitor {
            NSEvent.removeMonitor(drawSystemDefinedMonitor)
            self.drawSystemDefinedMonitor = nil
        }

        isDrawGlobalHotkeysEnabled = screenDrawHotkeyService.start()
        if isDrawGlobalHotkeysEnabled {
            drawStatusMessage = "快捷键已就绪：⌃⌥1~5 颜色，⌘⌥1~6 工具，⌘⌥C 清空。"
        } else {
            drawStatusMessage = "全局快捷键注册失败：请先重启 PJTool；若仍失败，请先用前台快捷键并在系统设置检查权限。"
        }
    }

    private func handleDrawHotkeyAction(_ action: ScreenDrawHotkeyAction) {
        switch action {
        case let .selectColor(preset):
            screenDrawCanvasController.drawSessionStore.selectedColorPreset = preset
            drawStatusMessage = "颜色已切换：\(preset.title)"
        case let .selectTool(tool):
            screenDrawCanvasController.drawSessionStore.activeTool = tool
            drawStatusMessage = "工具已切换：\(tool.title)"
        case .clearCanvas:
            clearScreenDrawCanvas()
        case .showOverlay:
            showScreenDrawOverlay()
            drawStatusMessage = "屏幕画图已展示。"
        case .hideOverlay:
            hideScreenDrawOverlay()
            drawStatusMessage = "屏幕画图已收起。"
        case .disableCanvas:
            if !isDrawOverlayVisible {
                showScreenDrawOverlay()
            }
            screenDrawCanvasController.setCanvasInteractionEnabled(false)
            drawStatusMessage = "画布已关闭交互，鼠标可穿透到其他应用。"
        case .enableCanvas:
            if !isDrawOverlayVisible {
                showScreenDrawOverlay()
            }
            screenDrawCanvasController.setCanvasInteractionEnabled(true)
            drawStatusMessage = "画布已启用，可继续绘制。"
        }
    }

    private func shouldHandleDrawHotkeyAction(_ action: ScreenDrawHotkeyAction) -> Bool {
        switch action {
        case .showOverlay, .hideOverlay:
            return true
        case .enableCanvas, .disableCanvas:
            return true
        case .clearCanvas, .selectColor, .selectTool:
            return isDrawOverlayVisible
        }
    }

    private func handleDrawCanvasScreenRecoveryEvent(_ event: ScreenDrawCanvasWindowController.ScreenRecoveryEvent) {
        guard isDrawOverlayVisible else { return }
        switch event {
        case .switchedToFallbackMainScreen:
            drawStatusMessage = "主屏变化：透明画布已回退到当前主屏。"
        case .switchedToFallbackFirstScreen:
            drawStatusMessage = "主屏不可用：透明画布已回退到可用显示器。"
        case .noAvailableScreen:
            drawStatusMessage = "当前未检测到可用显示器，屏幕画图暂不可用。"
        case .frameRecomputedAfterScreenChange:
            drawStatusMessage = "显示器拓扑变化：透明画布已重算位置。"
        }
    }

    private func handleDrawToolbarScreenRecoveryEvent(_ event: ScreenDrawToolbarWindowController.ScreenRecoveryEvent) {
        guard isDrawOverlayVisible else { return }
        switch event {
        case .switchedToFallbackMainScreen:
            drawStatusMessage = "主屏变化：工具条已回退到当前主屏。"
        case .switchedToFallbackFirstScreen:
            drawStatusMessage = "主屏不可用：工具条已回退到可用显示器。"
        case .noAvailableScreen:
            drawStatusMessage = "当前未检测到可用显示器，屏幕画图暂不可用。"
        case .frameRecomputedAfterScreenChange:
            drawStatusMessage = "显示器拓扑变化：工具条已重算位置。"
        }
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
