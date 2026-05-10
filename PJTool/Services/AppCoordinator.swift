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
    private static let languageOptionDefaultsKey = "pjtool.appLanguage.option"
    private static let drawDismissalAnimationModeDefaultsKey = "pjtool.draw.dismissal.animation.mode"
    private static let drawDismissalAnimationFixedStyleDefaultsKey = "pjtool.draw.dismissal.animation.fixedStyle"
    private static let pipHotkeyRegisteredStatusKey = "pip.hotkey.registered.status"
    private static let pipHotkeyFallbackStatusKey = "pip.hotkey.fallback.status"
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
    @Published var languageOption: AppLanguageOption = .auto {
        didSet {
            guard languageOption != oldValue else { return }
            persistLanguageOption()
            resolveLanguage()
        }
    }
    @Published var isSidebarCollapsed = false
    @Published var sidebarWidth: CGFloat = 280

    @Published private(set) var resolvedLanguage: ResolvedAppLanguage = .en
    @Published private(set) var statusMessage = L10n.tr("legacy.key_115")
    @Published private(set) var pipStatusMessage = L10n.tr("legacy.pip_2")
    @Published private(set) var isPiPPreviewVisible = false
    @Published private(set) var drawStatusMessage = L10n.tr("legacy.key_75")
    @Published private(set) var isDrawOverlayVisible = false
    @Published private(set) var isDrawCanvasInteractionEnabled = true
    @Published private(set) var isDrawGlobalHotkeysEnabled = false
    @Published private(set) var isPiPGlobalHotkeysEnabled = false
    @Published var drawDismissalAnimationMode: DrawDismissalAnimationMode = .random {
        didSet {
            guard drawDismissalAnimationMode != oldValue else { return }
            screenDrawCanvasController.drawSessionStore.dismissalAnimationMode = drawDismissalAnimationMode
            persistDrawDismissalAnimationMode()
        }
    }
    @Published var drawDismissalAnimationFixedStyle: DrawDismissalAnimationStyle = .shatterDrop {
        didSet {
            guard drawDismissalAnimationFixedStyle != oldValue else { return }
            screenDrawCanvasController.drawSessionStore.dismissalAnimationFixedStyle = drawDismissalAnimationFixedStyle
            persistDrawDismissalAnimationFixedStyle()
        }
    }
    @Published private(set) var recorderState: RecordingState = .idle

    let audioEngine: AudioInputEngine
    let pipPreviewRuntime: PiPPreviewRuntime
    let pipController: PiPOverlayWindowController
    let screenDrawToolbarController: ScreenDrawToolbarWindowController
    let screenDrawCanvasController: ScreenDrawCanvasWindowController
    let recordingControlController: RecordingControlWindowController
    let recorder: ScreenRecorderEngine

    private let screenDrawHotkeyService: ScreenDrawHotkeyService
    private let pipHotkeyService: PiPHotkeyService
    private let screenDrawExportService = ScreenDrawExportService()
    private var cancellables: Set<AnyCancellable> = []
    private var shouldRestoreMainWindowAfterRecording = false
    private var drawSystemDefinedMonitor: Any?
    private var pendingDrawCaptureRefreshTask: Task<Void, Never>?

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
            screenDrawHotkeyService: ScreenDrawHotkeyService(),
            pipHotkeyService: PiPHotkeyService()
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
        screenDrawHotkeyService: ScreenDrawHotkeyService,
        pipHotkeyService: PiPHotkeyService
    ) {
        self.audioEngine = audioEngine
        self.pipPreviewRuntime = pipPreviewRuntime
        self.pipController = pipController
        self.screenDrawToolbarController = screenDrawToolbarController
        self.screenDrawCanvasController = screenDrawCanvasController
        self.recordingControlController = recordingControlController
        self.screenDrawHotkeyService = screenDrawHotkeyService
        self.pipHotkeyService = pipHotkeyService
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
        self.screenDrawHotkeyService.onRegistrationStatusChanged = { [weak self] isEnabled, message in
            guard let self else { return }
            self.isDrawGlobalHotkeysEnabled = isEnabled
            self.drawStatusMessage = message
        }
        self.pipHotkeyService.onAction = { [weak self] action in
            self?.handlePiPHotkeyAction(action)
        }
        self.pipHotkeyService.shouldHandleAction = { _ in true }
        self.pipHotkeyService.onRegistrationStatusChanged = { [weak self] isEnabled, _ in
            guard let self else { return }
            self.isPiPGlobalHotkeysEnabled = isEnabled
            self.pipStatusMessage = isEnabled
                ? L10n.tr(Self.pipHotkeyRegisteredStatusKey)
                : L10n.tr(Self.pipHotkeyFallbackStatusKey)
        }

        self.pipController.onVisibilityChanged = { [weak self] isVisible in
            guard let self else { return }
            if isVisible {
                self.isPiPPreviewVisible = true
                self.pipStatusMessage = L10n.tr("legacy.pip_6")
            } else {
                self.isPiPPreviewVisible = false
                self.pipPreviewRuntime.stopPreview()
                self.pipStatusMessage = L10n.tr("legacy.pip_5")
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
            self.drawStatusMessage = visible ? L10n.tr("legacy.key_72") : L10n.tr("legacy.key_71")
            self.refreshRecordingWindowCaptureIfNeeded()
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
                self.drawStatusMessage = L10n.tr("legacy.key_78")
            }
            self.refreshRecordingWindowCaptureIfNeeded()
        }
        self.screenDrawCanvasController.onScreenRecoveryEvent = { [weak self] event in
            self?.handleDrawCanvasScreenRecoveryEvent(event)
        }

        loadPersistedDrawDismissalAnimationPreferences()
        loadPersistedLanguageOption()
        resolveLanguage()
        bindState()
    }

    deinit {
        if let drawSystemDefinedMonitor {
            NSEvent.removeMonitor(drawSystemDefinedMonitor)
            self.drawSystemDefinedMonitor = nil
        }
        Task { @MainActor [screenDrawHotkeyService, pipHotkeyService] in
            screenDrawHotkeyService.stop()
            pipHotkeyService.stop()
        }
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

    var appLocale: Locale {
        resolvedLanguage.locale
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
        configurePiPHotkeysIfNeeded()
        refreshLanguageIfNeeded()
    }

    func refreshLanguageIfNeeded() {
        guard languageOption == .auto else { return }
        resolveLanguage()
    }

    func showPiPPreview(on screen: NSScreen? = nil) {
        guard enableCameraPiP else {
            pipStatusMessage = L10n.tr("legacy.pip_pip")
            print("[PiP] aborted: enableCameraPiP=false")
            return
        }
        guard isCameraAuthorized else {
            pipStatusMessage = L10n.tr("legacy.pip_23")
            print("[PiP] aborted: camera unauthorized")
            return
        }
        if pipPreviewRuntime.selectedSourceID == nil {
            pipPreviewRuntime.refreshSources()
        }
        guard pipPreviewRuntime.selectedSourceID != nil else {
            pipStatusMessage = L10n.tr("legacy.pip_26")
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

        pipStatusMessage = L10n.tr("legacy.pip_7")
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
            pipStatusMessage = L10n.tr("legacy.pip_space")
        }
    }

    func activatePiPPreview(on screen: NSScreen? = nil) {
        if !enableCameraPiP {
            enableCameraPiP = true
        }
        DispatchQueue.main.async { [weak self] in
            self?.showPiPPreview(on: screen)
        }
        refreshRecordingWindowCaptureIfNeeded()
    }

    func hidePiPPreview() {
        pipLayout = pipController.currentLayoutState()
        pipController.hide()
        refreshRecordingWindowCaptureIfNeeded()
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
            setDrawCanvasInteractionEnabled(true)
            screenDrawToolbarController.show(on: targetScreen)
            isDrawOverlayVisible = true
            refreshRecordingWindowCaptureIfNeeded()
            drawStatusMessage = L10n.tr("legacy.key_70")
        } else {
            isDrawOverlayVisible = false
            screenDrawToolbarController.hide()
            drawStatusMessage = L10n.tr("legacy.key_76")
        }
    }

    func hideScreenDrawOverlay() {
        pendingDrawCaptureRefreshTask?.cancel()
        pendingDrawCaptureRefreshTask = nil
        screenDrawToolbarController.hide()
        if screenDrawCanvasController.hasDrawableContent {
            drawStatusMessage = L10n.tr("draw.dismiss.start")
        }
        screenDrawCanvasController.hideWithDismissalAnimation { [weak self] in
            guard let self else { return }
            self.isDrawOverlayVisible = false
            self.drawStatusMessage = L10n.tr("legacy.key_69")
            self.refreshRecordingWindowCaptureIfNeeded()
        }
    }

    func clearScreenDrawCanvas() {
        if screenDrawCanvasController.hasDrawableContent {
            drawStatusMessage = L10n.tr("draw.dismiss.start")
        }
        screenDrawCanvasController.clearCanvasWithDismissalAnimation { [weak self] in
            self?.refreshRecordingWindowCaptureIfNeeded()
        }
    }

    func setDrawHandDrawnIntensity(_ value: CGFloat) {
        let clamped = max(0, min(value, 1))
        screenDrawCanvasController.drawSessionStore.handDrawnIntensity = clamped
        drawStatusMessage = L10n.f("fmt.draw.intensity", Int(clamped * 100))
    }

    func setDrawMarkStyle(_ style: ScreenDrawMarkStyle) {
        screenDrawCanvasController.drawSessionStore.markStyle = style
        drawStatusMessage = L10n.f("fmt.draw.mark_style_changed", style.title)
    }

    func exportScreenDrawCanvasAsPNG() {
        do {
            guard let image = screenDrawCanvasController.snapshotImage() else {
                drawStatusMessage = L10n.tr("legacy.key_59")
                return
            }
            let outputURL = try screenDrawExportService.pickOutputURL()
            try screenDrawExportService.writeTransparentPNG(from: image, to: outputURL)
            drawStatusMessage = L10n.f("fmt.draw.export_success", outputURL.lastPathComponent)
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } catch {
            if let exportError = error as? ScreenDrawExportError, case .cancelled = exportError {
                drawStatusMessage = exportError.errorDescription ?? L10n.tr("legacy.key_85")
                return
            }
            drawStatusMessage = L10n.f("fmt.draw.export_failed", error.localizedDescription)
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
        drawStatusMessage = L10n.tr("legacy.key_67")
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
        statusMessage = L10n.tr("legacy.key_176")
    }

    func stopRecordingAndRestoreMonitoring() {
        guard canStopRecording else { return }
        isRecordingArmed = false
        recordingControlController.setMode(.stopping)
        statusMessage = L10n.tr("legacy.key_169")
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
        L10n.tr("legacy.key_107")
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
            refreshRecordingWindowCaptureIfNeeded()
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
            statusMessage = L10n.tr("legacy.pjtool_7")
            return
        }

        audioEngine.stopMonitoring()
        pipLayout.aspectRatio = pipAspectRatio
        shouldRestoreMainWindowAfterRecording = true
        recordingControlController.setMode(.recording)
        statusMessage = L10n.tr("legacy.key_21")

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
                   !self.statusMessage.contains(L10n.tr("legacy.key_65")),
                   !self.statusMessage.contains(L10n.tr("legacy.key_37")) {
                    self.statusMessage = L10n.tr("legacy.pjtool_2")
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
        if screenDrawCanvasController.isVisible, let canvasID = screenDrawCanvasController.currentWindowID {
            ids.append(canvasID)
        }
        if screenDrawToolbarController.isVisible, let toolbarID = screenDrawToolbarController.currentWindowID {
            ids.append(toolbarID)
        }
        return ids
    }

    private func refreshRecordingWindowCaptureIfNeeded() {
        guard recorderState.isRecording else { return }
        pendingDrawCaptureRefreshTask?.cancel()
        pendingDrawCaptureRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshRecordingWindowCapture(retriesRemaining: 6)
        }
    }

    private func refreshRecordingWindowCapture(retriesRemaining: Int) async {
        guard !Task.isCancelled else { return }
        await syncPiPWindowCaptureState()

        guard retriesRemaining > 0 else { return }
        let drawStillWaiting = isDrawOverlayVisible && screenDrawWhitelistWindowIDs().isEmpty
        let pipStillWaiting = isPiPPreviewVisible && pipController.currentWindowID == nil
        guard drawStillWaiting || pipStillWaiting else { return }

        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }
        await refreshRecordingWindowCapture(retriesRemaining: retriesRemaining - 1)
    }

    private func configureDrawHotkeysIfNeeded() {
        if let drawSystemDefinedMonitor {
            NSEvent.removeMonitor(drawSystemDefinedMonitor)
            self.drawSystemDefinedMonitor = nil
        }

        isDrawGlobalHotkeysEnabled = screenDrawHotkeyService.start()
        drawStatusMessage = isDrawGlobalHotkeysEnabled
            ? L10n.tr("legacy.k_1_5_1_6_c")
            : L10n.tr("legacy.pjtool")
    }

    private func configurePiPHotkeysIfNeeded() {
        isPiPGlobalHotkeysEnabled = pipHotkeyService.start()
    }

    private func handleDrawHotkeyAction(_ action: ScreenDrawHotkeyAction) {
        switch action {
        case let .selectColor(preset):
            screenDrawCanvasController.drawSessionStore.selectedColorPreset = preset
            drawStatusMessage = L10n.f("fmt.draw.color_changed", preset.title)
        case let .selectTool(tool):
            screenDrawCanvasController.drawSessionStore.activeTool = tool
            drawStatusMessage = L10n.f("fmt.draw.tool_changed", tool.title)
        case .toggleOverlay:
            if isDrawOverlayVisible {
                hideScreenDrawOverlay()
                drawStatusMessage = L10n.tr("legacy.key_74")
            } else {
                showScreenDrawOverlay()
                drawStatusMessage = L10n.tr("legacy.key_73")
            }
        case .toggleCanvasPassthrough:
            guard isDrawOverlayVisible else {
                showScreenDrawOverlay()
                setDrawCanvasInteractionEnabled(true)
                drawStatusMessage = L10n.tr("legacy.key_180")
                return
            }
            let nextEnabled = !isDrawCanvasInteractionEnabled
            setDrawCanvasInteractionEnabled(nextEnabled)
            drawStatusMessage = nextEnabled
                ? L10n.tr("legacy.key_180")
                : L10n.tr("legacy.key_179")
        }
    }

    private func handlePiPHotkeyAction(_ action: PiPHotkeyAction) {
        switch action {
        case .togglePreview:
            if isPiPPreviewVisible {
                hidePiPPreview()
                pipStatusMessage = L10n.tr("pip.hotkey.hidden")
            } else {
                activatePiPPreview()
                pipStatusMessage = L10n.tr("pip.hotkey.showing")
            }
            refreshRecordingWindowCaptureIfNeeded()
        }
    }

    private func shouldHandleDrawHotkeyAction(_ action: ScreenDrawHotkeyAction) -> Bool {
        switch action {
        case .toggleOverlay, .toggleCanvasPassthrough:
            return true
        case .selectColor, .selectTool:
            return isDrawOverlayVisible
        }
    }

    private func setDrawCanvasInteractionEnabled(_ enabled: Bool) {
        isDrawCanvasInteractionEnabled = enabled
        screenDrawCanvasController.setCanvasInteractionEnabled(enabled)
    }

    private func handleDrawCanvasScreenRecoveryEvent(_ event: ScreenDrawCanvasWindowController.ScreenRecoveryEvent) {
        guard isDrawOverlayVisible else { return }
        switch event {
        case .switchedToFallbackMainScreen:
            drawStatusMessage = L10n.tr("legacy.key_4")
        case .switchedToFallbackFirstScreen:
            drawStatusMessage = L10n.tr("legacy.key_2")
        case .noAvailableScreen:
            drawStatusMessage = L10n.tr("legacy.key_106")
        case .frameRecomputedAfterScreenChange:
            drawStatusMessage = L10n.tr("legacy.key_156")
        }
    }

    private func handleDrawToolbarScreenRecoveryEvent(_ event: ScreenDrawToolbarWindowController.ScreenRecoveryEvent) {
        guard isDrawOverlayVisible else { return }
        switch event {
        case .switchedToFallbackMainScreen:
            drawStatusMessage = L10n.tr("legacy.key_3")
        case .switchedToFallbackFirstScreen:
            drawStatusMessage = L10n.tr("legacy.key")
        case .noAvailableScreen:
            drawStatusMessage = L10n.tr("legacy.key_106")
        case .frameRecomputedAfterScreenChange:
            drawStatusMessage = L10n.tr("legacy.key_155")
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

    private func loadPersistedLanguageOption() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.languageOptionDefaultsKey),
           let option = AppLanguageOption(rawValue: raw) {
            languageOption = option
        } else {
            languageOption = .auto
            defaults.set(languageOption.rawValue, forKey: Self.languageOptionDefaultsKey)
        }
    }

    private func persistLanguageOption() {
        UserDefaults.standard.set(languageOption.rawValue, forKey: Self.languageOptionDefaultsKey)
    }

    private func loadPersistedDrawDismissalAnimationPreferences() {
        let defaults = UserDefaults.standard
        if let rawMode = defaults.string(forKey: Self.drawDismissalAnimationModeDefaultsKey),
           let mode = DrawDismissalAnimationMode(rawValue: rawMode) {
            drawDismissalAnimationMode = mode
        }
        if let rawStyle = defaults.string(forKey: Self.drawDismissalAnimationFixedStyleDefaultsKey),
           let style = DrawDismissalAnimationStyle(rawValue: rawStyle) {
            drawDismissalAnimationFixedStyle = style
        }
        screenDrawCanvasController.drawSessionStore.dismissalAnimationMode = drawDismissalAnimationMode
        screenDrawCanvasController.drawSessionStore.dismissalAnimationFixedStyle = drawDismissalAnimationFixedStyle
    }

    private func persistDrawDismissalAnimationMode() {
        UserDefaults.standard.set(
            drawDismissalAnimationMode.rawValue,
            forKey: Self.drawDismissalAnimationModeDefaultsKey
        )
    }

    private func persistDrawDismissalAnimationFixedStyle() {
        UserDefaults.standard.set(
            drawDismissalAnimationFixedStyle.rawValue,
            forKey: Self.drawDismissalAnimationFixedStyleDefaultsKey
        )
    }

    private func resolveLanguage() {
        let regionID = Locale.autoupdatingCurrent.region?.identifier
        let next = ResolvedAppLanguage.resolve(option: languageOption, regionIdentifier: regionID)
        guard next != resolvedLanguage else { return }
        resolvedLanguage = next
        L10n.setLanguage(next)
    }
}
