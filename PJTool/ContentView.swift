//
//  ContentView.swift
//  PJTool
//
//  Created by Jamie on 2026/4/29.
//

import SwiftUI

struct ContentView: View {
    private static let sidebarLaunchWidth: CGFloat = 200
    @ObservedObject private var appCoordinator: AppCoordinator

    @AppStorage("pjtool.sidebarCollapsed") private var sidebarCollapsedStorage = false
    @AppStorage("pjtool.sidebarWidth") private var sidebarWidthStorage = 0.0

    @State private var baseStitchURL: URL?
    @State private var stitchInsertTimeText = "0"
    @State private var stitchMuteImportedAudio = false
    @State private var stitchOutputURL: URL?

    @State private var trimSourceURL: URL?
    @State private var cutStartText = "0"
    @State private var cutEndText = "1"
    @State private var cutRanges: [CutRange] = []
    @State private var trimOutputURL: URL?

    @State private var validationSummary = "未执行"
    @State private var validationReportURL: URL?
    @State private var hasBootstrappedUIState = false
    @State private var lastKnownContainerWidth: CGFloat = 1000
    @State private var sidebarDragStartWidth: CGFloat?

    private let trimEngine = TrimExportEngine()
    private let validationService = ValidationService()

    init(appCoordinator: AppCoordinator) {
        self._appCoordinator = ObservedObject(wrappedValue: appCoordinator)
    }

    private var audioSelectionBinding: Binding<String> {
        Binding(
            get: { appCoordinator.audioEngine.selectedSourceID ?? appCoordinator.audioEngine.sources.first?.id ?? "" },
            set: { appCoordinator.audioEngine.selectSource(withID: $0, userInitiated: true) }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            HStack(spacing: 0) {
                sidebar
                    .frame(width: appCoordinator.isSidebarCollapsed ? 64 : clampedSidebarWidth(appCoordinator.sidebarWidth, totalWidth: width))

                if !appCoordinator.isSidebarCollapsed {
                    sidebarDivider(totalWidth: width)
                }

                rightPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .onAppear {
                let measuredWidth = max(width, 1)
                lastKnownContainerWidth = measuredWidth
                bootstrapUIStateIfNeeded(totalWidth: measuredWidth)
                appCoordinator.bootstrap()
            }
            .onChange(of: width) { _, newWidth in
                let measuredWidth = max(newWidth, 1)
                lastKnownContainerWidth = measuredWidth
                enforceSidebarBounds(totalWidth: measuredWidth)
            }
        }
        .frame(minWidth: 1000, minHeight: 860)
        .onAppear {
            if baseStitchURL == nil {
                baseStitchURL = appCoordinator.recorder.lastOutputURL
            }
            if trimSourceURL == nil {
                trimSourceURL = appCoordinator.recorder.lastOutputURL
            }
        }
        .onReceive(appCoordinator.recorder.$lastOutputURL) { url in
            guard let url else { return }
            baseStitchURL = url
            trimSourceURL = url
        }
        .onChange(of: appCoordinator.isSidebarCollapsed) { _, newValue in
            sidebarCollapsedStorage = newValue
        }
        .onChange(of: appCoordinator.sidebarWidth) { _, newValue in
            sidebarWidthStorage = newValue
        }
    }

    private var sidebar: some View {
        SettingsSidebarView(
            selectedSection: Binding(
                get: { appCoordinator.selectedSettingsSection },
                set: { appCoordinator.selectedSettingsSection = $0 }
            ),
            isCollapsed: Binding(
                get: { appCoordinator.isSidebarCollapsed },
                set: { appCoordinator.isSidebarCollapsed = $0 }
            )
        )
    }

    private var rightPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                currentSectionView
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var currentSectionView: some View {
        switch appCoordinator.selectedSettingsSection {
        case .recording:
            RecordingSettingsView(
                appCoordinator: appCoordinator,
                audioSelectionBinding: audioSelectionBinding
            )
        case .pipCamera:
            PiPCameraSettingsView(appCoordinator: appCoordinator)
        case .videoProcessing:
            VideoProcessingSettingsView(
                appCoordinator: appCoordinator,
                baseStitchURL: $baseStitchURL,
                stitchInsertTimeText: $stitchInsertTimeText,
                stitchMuteImportedAudio: $stitchMuteImportedAudio,
                stitchOutputURL: $stitchOutputURL,
                trimSourceURL: $trimSourceURL,
                cutStartText: $cutStartText,
                cutEndText: $cutEndText,
                cutRanges: $cutRanges,
                trimOutputURL: $trimOutputURL,
                validationSummary: $validationSummary,
                validationReportURL: $validationReportURL,
                trimEngine: trimEngine,
                validationService: validationService
            )
        }
    }

    private func bootstrapUIStateIfNeeded(totalWidth: CGFloat) {
        guard !hasBootstrappedUIState else { return }
        hasBootstrappedUIState = true

        appCoordinator.isSidebarCollapsed = false
        sidebarCollapsedStorage = false
        // Force a deterministic launch width each startup, ignoring stale cached widths.
        let initialWidth = defaultSidebarWidth(totalWidth: totalWidth)
        appCoordinator.sidebarWidth = initialWidth
        sidebarWidthStorage = initialWidth

        // Re-apply once after the first layout pass to override split-view remembered positions.
        DispatchQueue.main.async {
            guard !appCoordinator.isSidebarCollapsed else { return }
            let forcedWidth = defaultSidebarWidth(totalWidth: max(lastKnownContainerWidth, totalWidth))
            appCoordinator.sidebarWidth = forcedWidth
            sidebarWidthStorage = forcedWidth
        }
    }

    @ViewBuilder
    private func sidebarDivider(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if sidebarDragStartWidth == nil {
                            sidebarDragStartWidth = appCoordinator.sidebarWidth
                        }
                        guard let startWidth = sidebarDragStartWidth else { return }
                        let nextWidth = clampedSidebarWidth(startWidth + value.translation.width, totalWidth: totalWidth)
                        if abs(nextWidth - appCoordinator.sidebarWidth) > 0.5 {
                            appCoordinator.sidebarWidth = nextWidth
                        }
                    }
                    .onEnded { _ in
                        sidebarDragStartWidth = nil
                    }
            )
    }

    private func enforceSidebarBounds(totalWidth: CGFloat) {
        guard !appCoordinator.isSidebarCollapsed else { return }
        let clamped = clampedSidebarWidth(appCoordinator.sidebarWidth, totalWidth: totalWidth)
        if abs(clamped - appCoordinator.sidebarWidth) > 0.5 {
            appCoordinator.sidebarWidth = clamped
        }
    }

    private func defaultSidebarWidth(totalWidth: CGFloat) -> CGFloat {
        clampedSidebarWidth(Self.sidebarLaunchWidth, totalWidth: totalWidth)
    }

    private func clampedSidebarWidth(_ value: CGFloat, totalWidth: CGFloat) -> CGFloat {
        let minWidth: CGFloat = Self.sidebarLaunchWidth
        let maxWidth: CGFloat = max(minWidth, totalWidth * 0.55)
        return min(max(value, minWidth), maxWidth)
    }
}
