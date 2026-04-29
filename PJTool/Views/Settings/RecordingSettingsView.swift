//
//  RecordingSettingsView.swift
//  PJTool
//
//  Created by Codex on 2026/4/30.
//

import AVFoundation
import AppKit
import SwiftUI

struct RecordingSettingsView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    let audioSelectionBinding: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("录屏", subtitle: "主屏录制、录制控制与录音输入")

            recordingControlCard
            permissionStatusCard
            microphoneCard
        }
    }

    private var recordingControlCard: some View {
        card {
            HStack(spacing: 12) {
                Button(actionButtonTitle) {
                    if appCoordinator.recorderState.isRecording {
                        appCoordinator.stopRecordingAndRestoreMonitoring()
                    } else {
                        appCoordinator.startRecordingFromCurrentConfig()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(actionButtonDisabled)

                if let outputURL = appCoordinator.recorder.lastOutputURL {
                    Button("打开成片") {
                        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 10)

                Label(
                    appCoordinator.statusMessage,
                    systemImage: appCoordinator.recorderState.isRecording ? "record.circle.fill" : "record.circle"
                )
                .font(.footnote)
                .foregroundStyle(appCoordinator.recorderState.isRecording ? Color.red : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
        }
    }

    private var actionButtonTitle: String {
        if appCoordinator.recorderState.isRecording {
            return "停止录屏"
        }
        if appCoordinator.isRecordingArmed {
            return "等待小相机开始..."
        }
        return "弹出录屏小相机"
    }

    private var actionButtonDisabled: Bool {
        if appCoordinator.recorderState.isRecording {
            return appCoordinator.recorderState.isBusy
        }
        return appCoordinator.recorderState.isBusy || !appCoordinator.canStartRecording
    }

    private var permissionStatusCard: some View {
        card {
            VStack(alignment: .leading, spacing: 6) {
                statusRow("麦克风", isAudioAuthorized, audioPermissionText)
                statusRow("摄像头", isCameraAuthorized, cameraPermissionText)
            }
        }
    }

    private var microphoneCard: some View {
        card {
            Text("录制麦克风")
                .font(.headline)

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

                Button(appCoordinator.audioEngine.isMonitoring ? "停止监听" : "开始监听") {
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

            if let infoMessage = appCoordinator.audioEngine.infoMessage, !infoMessage.isEmpty {
                Text("设备状态：\(infoMessage)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isAudioAuthorized: Bool {
        appCoordinator.audioEngine.authorizationStatus == .authorized
    }

    private var isCameraAuthorized: Bool {
        appCoordinator.pipPreviewRuntime.authorizationStatus == .authorized
    }

    private var audioPermissionText: String {
        switch appCoordinator.audioEngine.authorizationStatus {
        case .authorized: return "已授权"
        case .notDetermined: return "未请求"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        @unknown default: return "未知"
        }
    }

    private var cameraPermissionText: String {
        switch appCoordinator.pipPreviewRuntime.authorizationStatus {
        case .authorized: return "已授权"
        case .notDetermined: return "未请求"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        @unknown default: return "未知"
        }
    }

    @ViewBuilder
    private func statusRow(_ label: String, _ ok: Bool, _ text: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? .green : .orange).frame(width: 9, height: 9)
            Text("\(label)：\(text)")
                .font(.callout)
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
}
