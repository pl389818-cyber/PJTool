//
//  PJToolApp.swift
//  PJTool
//
//  Created by Jamie on 2026/4/29.
//

import SwiftUI

@main
struct PJToolApp: App {
    private static let videoCuttingWindowID = "video-cutting-window"
    @StateObject private var appCoordinator = AppCoordinator()
    @StateObject private var videoCuttingViewModel = VideoCuttingViewModel()

    var body: some Scene {
        WindowGroup("PJTool", id: "main-window") {
            ContentView(
                appCoordinator: appCoordinator,
                videoCuttingViewModel: videoCuttingViewModel,
                videoCuttingWindowID: Self.videoCuttingWindowID
            )
        }

        Window("智能裁剪", id: Self.videoCuttingWindowID) {
            VideoCuttingModalView(
                viewModel: videoCuttingViewModel,
                windowID: Self.videoCuttingWindowID
            )
            .onDisappear {
                if appCoordinator.selectedSettingsSection == .videoCutting {
                    appCoordinator.selectedSettingsSection = .videoProcessing
                }
            }
        }
        .defaultSize(width: 1320, height: 860)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Button(appCoordinator.recorderState.isRecording ? "停止录屏" : "开始录屏") {
                    if appCoordinator.recorderState.isRecording {
                        appCoordinator.stopRecordingAndRestoreMonitoring()
                    } else {
                        appCoordinator.startRecordingFromCurrentConfig()
                    }
                }
                .disabled(appCoordinator.recorderState.isBusy)

                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("录屏：\(appCoordinator.statusMessage)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("PiP：\(appCoordinator.pipStatusMessage)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Divider()
                Button("显示主窗口") {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows {
                        if window.isMiniaturized {
                            window.deminiaturize(nil)
                        }
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                Button("退出") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        } label: {
            Label(
                "PJTool",
                systemImage: appCoordinator.recorderState.isRecording ? "record.circle.fill" : "record.circle"
            )
        }
    }
}
