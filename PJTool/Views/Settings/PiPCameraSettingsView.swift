//
//  PiPCameraSettingsView.swift
//  PJTool
//
//  Created by Codex on 2026/4/30.
//

import AVFoundation
import AppKit
import SwiftUI

struct PiPCameraSettingsView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    @ObservedObject private var pipRuntime: PiPPreviewRuntime
    @State private var diagnosticFeedback: String?
    @State private var showingDiagnostics = false

    init(appCoordinator: AppCoordinator) {
        self._appCoordinator = ObservedObject(wrappedValue: appCoordinator)
        self._pipRuntime = ObservedObject(wrappedValue: appCoordinator.pipPreviewRuntime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("PiP 摄像", subtitle: "原生悬浮预览、设备选择、麦克风监听与窗口比例")
            pipTopActionRow

            card {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("预览控制台")
                            .font(.headline)
                        Text(previewConsoleSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    previewStateBadge
                }
            }

            card {
                Text("设备选择")
                    .font(.headline)

                Picker("摄像头设备", selection: cameraSelectionBinding) {
                    ForEach(pipRuntime.sources) { source in
                        let label = source.badgeText.isEmpty ? source.name : "\(source.name) (\(source.badgeText))"
                        Text(label).tag(source.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!isCameraAuthorized || pipRuntime.sources.isEmpty)

                Picker("PiP 麦克风", selection: cameraAudioSelectionBinding) {
                    ForEach(pipRuntime.audioSources) { source in
                        let label = source.badgeText.isEmpty ? source.name : "\(source.name) (\(source.badgeText))"
                        Text(label).tag(source.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!isCameraAudioAuthorized || pipRuntime.audioSources.isEmpty)

                Text(selectedDeviceSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("刷新设备") {
                        pipRuntime.refreshSources()
                        pipRuntime.refreshAudioSources()
                    }
                    if !isCameraAuthorized {
                        Button("请求摄像头权限") { pipRuntime.requestCameraAccess() }
                    }
                    if !isCameraAudioAuthorized {
                        Button("请求 PiP 麦克风权限") { pipRuntime.requestMicrophoneAccess() }
                    }
                    Button("打开系统隐私设置") { openPrivacySettings() }
                    Button(showingDiagnostics ? "诊断中..." : "运行应用内诊断") {
                        runInAppDiagnostics()
                    }
                    .disabled(showingDiagnostics)
                }

                if needsPermissionRecovery {
                    permissionRecoveryGuide
                }

                if pipRuntime.sources.isEmpty {
                    statusBanner(
                        title: isCameraAuthorized ? "未发现摄像头设备" : "摄像头权限未就绪",
                        detail: cameraEmptyStateText
                    )
                } else if pipRuntime.sources.allSatisfy({ !$0.isAvailable }) {
                    statusBanner(
                        title: "摄像头设备均离线",
                        detail: "已枚举到摄像头条目，但当前都不可用。请检查是否被其他应用占用，或重新连接外设 / iPhone Continuity Camera。"
                    )
                }

                diagnosticSummary

                if let diagnosticFeedback, !diagnosticFeedback.isEmpty {
                    Text(diagnosticFeedback)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("当前状态：\(appCoordinator.pipStatusMessage)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            card {
                Text("窗口比例与自动放缩")
                    .font(.headline)

                Toggle("选中置顶", isOn: Binding(
                    get: { appCoordinator.pipWindowConfig.isAlwaysOnTop },
                    set: { newValue in
                        var next = appCoordinator.pipWindowConfig
                        next.isAlwaysOnTop = newValue
                        appCoordinator.pipWindowConfig = next
                    }
                ))

                HStack(alignment: .center, spacing: 10) {
                    Text("PiP 摄像标题栏")
                        .font(.subheadline.weight(.medium))
                    TextField(
                        "PiP 摄像",
                        text: Binding(
                            get: { appCoordinator.pipWindowConfig.windowTitle },
                            set: { newValue in
                                var next = appCoordinator.pipWindowConfig
                                next.windowTitle = newValue
                                appCoordinator.pipWindowConfig = next
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                }

                Picker("画面比例", selection: Binding(
                    get: { appCoordinator.pipAspectRatio },
                    set: { appCoordinator.pipAspectRatio = $0 }
                )) {
                    ForEach(PiPAspectRatio.allCases) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .pickerStyle(.segmented)

                Text("当前布局：x \(appCoordinator.pipLayout.normalizedRect.minX, specifier: "%.2f") · y \(appCoordinator.pipLayout.normalizedRect.minY, specifier: "%.2f") · w \(appCoordinator.pipLayout.normalizedRect.width, specifier: "%.2f") · h \(appCoordinator.pipLayout.normalizedRect.height, specifier: "%.2f")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("当前标题：\(appCoordinator.pipWindowConfig.resolvedWindowTitle)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("窗口默认以 240x240 弹出，后续可直接拖拽边缘或滚轮自由缩放。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            card {
                Text("PiP 预览监听")
                    .font(.headline)

                Toggle("预览监听静音", isOn: Binding(
                    get: { appCoordinator.pipAudioPreviewConfig.isPreviewMuted },
                    set: { newValue in
                        var next = appCoordinator.pipAudioPreviewConfig
                        next.isPreviewMuted = newValue
                        appCoordinator.pipAudioPreviewConfig = next
                    }
                ))

                HStack(spacing: 10) {
                    Text("预览音量")
                    Slider(value: Binding(
                        get: { appCoordinator.pipAudioPreviewConfig.previewVolume },
                        set: { newValue in
                            var next = appCoordinator.pipAudioPreviewConfig
                            next.previewVolume = newValue
                            appCoordinator.pipAudioPreviewConfig = next
                        }
                    ), in: 0...1)
                    Text("\(Int(appCoordinator.pipAudioPreviewConfig.clampedVolume * 100))")
                        .frame(width: 38, alignment: .trailing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                AudioLevelMeterView(level: pipRuntime.previewAudioLevel)
                    .frame(height: 12)

                Text("监听状态：\(appCoordinator.pipAudioPreviewConfig.isPreviewMuted ? "静音（沙盒模式仅电平）" : "监听中") · Level \(Int(pipRuntime.previewAudioLevel * 100))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let infoMessage = pipRuntime.infoMessage, !infoMessage.isEmpty {
                Text("设备状态：\(infoMessage)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cameraSelectionBinding: Binding<String> {
        Binding(
            get: { pipRuntime.selectedSourceID ?? pipRuntime.sources.first?.id ?? "" },
            set: { pipRuntime.selectSource(withID: $0) }
        )
    }

    private var cameraAudioSelectionBinding: Binding<String> {
        Binding(
            get: { pipRuntime.selectedAudioSourceID ?? pipRuntime.audioSources.first?.id ?? "" },
            set: { pipRuntime.selectAudioSource(withID: $0) }
        )
    }

    private var pipTopActionRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("桌面悬浮预览")
                    .font(.title3.weight(.semibold))
                Text("弹出原生前置 PiP 窗口，在桌面工作流中保持可见。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if appCoordinator.isPiPPreviewVisible {
                Button("收起 PiP 摄像") {
                    appCoordinator.hidePiPPreview()
                }
                .buttonStyle(.bordered)
            } else {
                Button("弹出 PiP 摄像") {
                    appCoordinator.activatePiPPreview()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var previewStateBadge: some View {
        let label: String
        let tint: Color
        if appCoordinator.isPiPPreviewVisible {
            label = "预览中"
            tint = .green
        } else if appCoordinator.enableCameraPiP {
            label = "已就绪"
            tint = .blue
        } else {
            label = "未弹出"
            tint = .secondary
        }

        return Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }

    private var previewConsoleSummary: String {
        if appCoordinator.isPiPPreviewVisible {
            return "悬浮预览已显示，可继续切换设备、比例和监听。"
        }
        if appCoordinator.enableCameraPiP {
            return "PiP 已就绪，再次点击右上角可重新弹出悬浮预览。"
        }
        return "当前未显示悬浮预览。点击右上角会自动启用并弹出 PiP 摄像。"
    }

    private var selectedDeviceSummary: String {
        let selectedCamera = pipRuntime.sources.first(where: {
            $0.id == pipRuntime.selectedSourceID
        })?.name ?? "未选择"
        let selectedMic = pipRuntime.audioSources.first(where: {
            $0.id == pipRuntime.selectedAudioSourceID
        })?.name ?? "未选择"
        return "当前摄像头：\(selectedCamera) · 当前 PiP 麦克风：\(selectedMic)"
    }

    private var needsPermissionRecovery: Bool {
        pipRuntime.authorizationStatus != .authorized
            || pipRuntime.microphoneAuthorizationStatus != .authorized
            || (pipRuntime.lastVideoEnumeratedCount == 0 && pipRuntime.lastAudioEnumeratedCount == 0)
    }

    @ViewBuilder
    private var permissionRecoveryGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("恢复步骤")
                .font(.subheadline.weight(.semibold))
            Text("1. 先点“请求摄像头权限”和“请求 PiP 麦克风权限”。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("2. 若系统拒绝，点“打开系统隐私设置”手动允许 PJTool。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("3. 回到应用后点“刷新设备”或“运行设备诊断”确认设备可见。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.blue.opacity(0.25), lineWidth: 1)
        )
    }

    private var isCameraAuthorized: Bool {
        pipRuntime.authorizationStatus == .authorized
    }

    private var isCameraAudioAuthorized: Bool {
        pipRuntime.microphoneAuthorizationStatus == .authorized
    }

    private var cameraEmptyStateText: String {
        switch pipRuntime.authorizationStatus {
        case .notDetermined:
            return "应用尚未获得摄像头权限。点击“请求摄像头权限”后，再执行一次“刷新设备”。"
        case .denied:
            return "系统已拒绝摄像头访问。请到系统设置 > 隐私与安全性 > 摄像头中开启 PJTool。"
        case .restricted:
            return "当前环境限制了摄像头访问，应用无法枚举任何 PiP 摄像头。"
        case .authorized:
            return "权限已正常，但当前没有枚举到设备。已补充 macOS 的外接/Continuity 发现逻辑；如果仍为空，请检查设备是否真的出现在系统相机列表中。"
        @unknown default:
            return "摄像头状态未知，请刷新设备或重启应用后再试。"
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func statusBanner(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var diagnosticSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("设备诊断")
                .font(.subheadline.weight(.semibold))

            Text("视频授权：\(authText(for: pipRuntime.authorizationStatus))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("视频枚举：\(pipRuntime.lastVideoEnumeratedCount)（可用 \(pipRuntime.lastVideoAvailableCount)）")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("视频发现源：Discovery \(pipRuntime.lastVideoDiscoveryCount) · LegacyFallback \(yesNo(pipRuntime.lastVideoUsedLegacyFallback)) · Default并入 \(yesNo(pipRuntime.lastVideoIncludedSystemDefault))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("音频授权：\(authText(for: pipRuntime.microphoneAuthorizationStatus))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("音频枚举：\(pipRuntime.lastAudioEnumeratedCount)（可用 \(pipRuntime.lastAudioAvailableCount)）")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("音频发现源：Discovery \(pipRuntime.lastAudioDiscoveryCount) · LegacyFallback \(yesNo(pipRuntime.lastAudioUsedLegacyFallback))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("最后刷新：视频 \(timestampText(pipRuntime.lastVideoRefreshAt)) · 音频 \(timestampText(pipRuntime.lastAudioRefreshAt))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func runInAppDiagnostics() {
        showingDiagnostics = true
        diagnosticFeedback = "正在运行设备诊断..."
        pipRuntime.refreshSources()
        pipRuntime.refreshAudioSources()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            pipRuntime.refreshSources()
            pipRuntime.refreshAudioSources()
            diagnosticFeedback = summarizeInAppDiagnostics()
            showingDiagnostics = false
        }
    }

    private func summarizeInAppDiagnostics() -> String {
        let videoAuth = authText(for: pipRuntime.authorizationStatus)
        let audioAuth = authText(for: pipRuntime.microphoneAuthorizationStatus)
        let videoTotal = pipRuntime.lastVideoEnumeratedCount
        let videoAvailable = pipRuntime.lastVideoAvailableCount
        let audioTotal = pipRuntime.lastAudioEnumeratedCount
        let audioAvailable = pipRuntime.lastAudioAvailableCount
        let pass = pipRuntime.authorizationStatus == .authorized
            && pipRuntime.microphoneAuthorizationStatus == .authorized
            && videoTotal > 0
            && audioTotal > 0
        let result = pass ? "PASS" : "BLOCKED"
        return "应用内诊断 \(result) · videoAuth=\(videoAuth) audioAuth=\(audioAuth) · video \(videoAvailable)/\(videoTotal) · audio \(audioAvailable)/\(audioTotal)"
    }

    private func authText(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "已授权"
        case .notDetermined: return "未请求"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        @unknown default: return "未知"
        }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "YES" : "NO"
    }

    private func timestampText(_ date: Date?) -> String {
        guard let date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
