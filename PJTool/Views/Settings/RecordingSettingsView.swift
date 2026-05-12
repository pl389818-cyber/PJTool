//
//  RecordingSettingsView.swift
//  PJTool
//
//  Created by PJ Lee + Ai on 2026/4/30.
//

import AVFoundation
import AppKit
import SwiftUI

struct RecordingSettingsView: View {
    @ObservedObject var appCoordinator: AppCoordinator
    let audioSelectionBinding: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(L10n.tr("legacy.key_112"), subtitle: L10n.tr("legacy.key_5"))

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
                    Button(L10n.tr("legacy.key_123")) {
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
            return L10n.tr("legacy.key_15")
        }
        if appCoordinator.isRecordingArmed {
            return L10n.tr("legacy.key_189")
        }
        return L10n.tr("legacy.key_102")
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
                statusRow(L10n.tr("legacy.key_228"), isAudioAuthorized, audioPermissionText)
                statusRow(L10n.tr("legacy.key_134"), isCameraAuthorized, cameraPermissionText)
            }
        }
    }

    private var microphoneCard: some View {
        card {
            Text(L10n.tr("legacy.key_111"))
                .font(.headline)

            Picker(L10n.tr("legacy.key_205"), selection: audioSelectionBinding) {
                ForEach(appCoordinator.audioEngine.sources) { source in
                    let label = source.badgeText.isEmpty ? source.name : "\(source.name) (\(source.badgeText))"
                    Text(label).tag(source.id)
                }
            }
            .pickerStyle(.menu)
            .disabled(!isAudioAuthorized || appCoordinator.audioEngine.sources.isEmpty)

            HStack(spacing: 12) {
                Button(L10n.tr("legacy.key_31")) { appCoordinator.audioEngine.refreshSources() }

                Button(appCoordinator.audioEngine.isMonitoring ? L10n.tr("legacy.key_17") : L10n.tr("legacy.key_99")) {
                    if appCoordinator.audioEngine.isMonitoring {
                        appCoordinator.audioEngine.stopMonitoring()
                    } else {
                        appCoordinator.audioEngine.startMonitoringIfNeeded()
                    }
                }
                .disabled(!isAudioAuthorized || appCoordinator.audioEngine.sources.isEmpty)

                if !isAudioAuthorized {
                    Button(L10n.tr("legacy.key_204")) { appCoordinator.audioEngine.requestMicrophoneAccess() }
                }
            }

            AudioLevelMeterView(level: appCoordinator.audioEngine.level)
                .frame(height: 12)
            Text(L10n.f("fmt.input.level", Int(appCoordinator.audioEngine.level * 100)))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let infoMessage = appCoordinator.audioEngine.infoMessage, !infoMessage.isEmpty {
                Text(L10n.f("fmt.device.status", infoMessage))
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
        case .authorized: return L10n.tr("legacy.key_90")
        case .notDetermined: return L10n.tr("legacy.key_166")
        case .denied: return L10n.tr("legacy.key_89")
        case .restricted: return L10n.tr("legacy.key_36")
        @unknown default: return L10n.tr("legacy.key_164")
        }
    }

    private var cameraPermissionText: String {
        switch appCoordinator.pipPreviewRuntime.authorizationStatus {
        case .authorized: return L10n.tr("legacy.key_90")
        case .notDetermined: return L10n.tr("legacy.key_166")
        case .denied: return L10n.tr("legacy.key_89")
        case .restricted: return L10n.tr("legacy.key_36")
        @unknown default: return L10n.tr("legacy.key_164")
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
