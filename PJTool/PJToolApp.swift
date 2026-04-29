//
//  PJToolApp.swift
//  PJTool
//
//  Created by Jamie on 2026/4/29.
//

import SwiftUI

@main
struct PJToolApp: App {
    @StateObject private var appCoordinator = AppCoordinator()
    @State private var hasRequestedLaunchPermissions = false

    var body: some Scene {
        WindowGroup("PJTool", id: "main-window") {
            ContentView(appCoordinator: appCoordinator)
                .onAppear {
                    guard !hasRequestedLaunchPermissions else { return }
                    hasRequestedLaunchPermissions = true
                    appCoordinator.requestPermissionsOnLaunchIfNeeded()
                }
        }

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
