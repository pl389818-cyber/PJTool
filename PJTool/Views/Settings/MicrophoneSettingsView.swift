//
//  MicrophoneSettingsView.swift
//  PJTool
//
//  Created by Codex on 2026/4/30.
//

import AVFoundation
import SwiftUI

struct MicrophoneSettingsView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    let audioSelectionBinding: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("麦克风", subtitle: "输入设备、监听与电平")

            card {
                Picker("输入设备", selection: audioSelectionBinding) {
                    ForEach(appCoordinator.audioEngine.sources) { source in
                        let label = source.badgeText.isEmpty ? source.name : "\(source.name) (\(source.badgeText))"
                        Text(label).tag(source.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!isAudioAuthorized || appCoordinator.audioEngine.sources.isEmpty)

                HStack(spacing: 12) {
                    Button("刷新设备") { appCoordinator.audioEngine.refreshSources() }

                    Button(appCoordinator.audioEngine.isMonitoring ? "停止监控" : "开始监控") {
                        if appCoordinator.audioEngine.isMonitoring {
                            appCoordinator.audioEngine.stopMonitoring()
                        } else {
                            appCoordinator.audioEngine.startMonitoringIfNeeded()
                        }
                    }
                    .disabled(!isAudioAuthorized || appCoordinator.audioEngine.sources.isEmpty)

                    if !isAudioAuthorized {
                        Button("请求麦克风权限") { appCoordinator.audioEngine.requestMicrophoneAccess() }
                    }
                }

                AudioLevelMeterView(level: appCoordinator.audioEngine.level)
                    .frame(height: 12)
                Text("输入电平：\(Int(appCoordinator.audioEngine.level * 100))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            card {
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

                AudioLevelMeterView(level: appCoordinator.pipPreviewRuntime.previewAudioLevel)
                    .frame(height: 12)
                Text("PiP 监听状态：\(appCoordinator.pipAudioPreviewConfig.isPreviewMuted ? "静音" : "监听中") · Level \(Int(appCoordinator.pipPreviewRuntime.previewAudioLevel * 100))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isAudioAuthorized: Bool {
        appCoordinator.audioEngine.authorizationStatus == .authorized
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
}
