//
//  VideoCuttingModalView.swift
//  PJTool
//
//  Created by Codex on 2026/5/4.
//

import AVKit
import SwiftUI

struct VideoCuttingModalView: View {
    @ObservedObject var viewModel: VideoCuttingViewModel
    @Environment(\.dismissWindow) private var dismissWindow
    let windowID: String?

    @State private var cropDragStartRect: CGRect?

    private let aspectGridRows: [[VideoCuttingAspectPreset]] = [
        [.adaptive, .nineBySixteen, .sixteenByNine, .oneByOne],
        [.fourByThree, .threeByFour, .fivePointEight, .twoByOne],
        [.twoPointThreeFiveByOne, .onePointEightFiveByOne]
    ]

    init(viewModel: VideoCuttingViewModel, windowID: String? = nil) {
        self.viewModel = viewModel
        self.windowID = windowID
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Color.black.opacity(0.35))
            bodyContent
            Divider().overlay(Color.black.opacity(0.35))
            bottomBar
        }
        .frame(minWidth: 1320, minHeight: 860)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .fileImporter(
            isPresented: $viewModel.isImportPanelPresented,
            allowedContentTypes: viewModel.allowedImportTypes,
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleImportPanelResult(result)
        } onCancellation: {
            viewModel.handleImportPanelCancellation()
        }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Button {
                    dismissCuttingWindow()
                } label: {
                    Circle()
                        .fill(Color.red.opacity(0.92))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                Spacer()
            }

            Text("智能裁剪")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.19, green: 0.20, blue: 0.23))
    }

    private var bodyContent: some View {
        HStack(spacing: 0) {
            previewPanel
            Divider().overlay(Color.black.opacity(0.35))
            sidePanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewPanel: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black

                if viewModel.hasSource {
                    videoPreview
                } else {
                    importDropZone
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if viewModel.hasSource {
                timelineBar
            }
        }
    }

    private var importDropZone: some View {
        Button {
            viewModel.importByPanel()
        } label: {
            VStack(spacing: 16) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(Color.cyan.opacity(0.95))
                Text("导入视频")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Text("拖动视频到此处，或点击按钮选择文件")
                    .font(.body)
                    .foregroundStyle(Color.white.opacity(0.45))
                Text("选择文件导入")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.cyan.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 680, height: 430)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .foregroundStyle(Color.white.opacity(0.2))
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            viewModel.handleDrop(providers: providers)
            return true
        }
    }

    private var videoPreview: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let fitRect = VideoCropGeometry.aspectFitRect(
                contentSize: viewModel.sourceVideoSize,
                boundingSize: proxy.size
            )
            ZStack {
                VideoPlayer(player: viewModel.player)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(width: proxy.size.width, height: proxy.size.height)

                cropOverlay(fitRect: fitRect)
            }
            .contentShape(Rectangle())
            .frame(width: bounds.width, height: bounds.height)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                viewModel.handleDrop(providers: providers)
                return true
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func cropOverlay(fitRect: CGRect) -> some View {
        let crop = VideoCropGeometry.clampNormalizedRect(viewModel.cropRectNormalized.cgRect)
        let cropFrame = CGRect(
            x: fitRect.minX + fitRect.width * crop.minX,
            y: fitRect.minY + fitRect.height * crop.minY,
            width: fitRect.width * crop.width,
            height: fitRect.height * crop.height
        )

        return ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .mask(
                    Rectangle().overlay(
                        Rectangle()
                            .frame(width: cropFrame.width, height: cropFrame.height)
                            .offset(x: cropFrame.midX - fitRect.midX, y: cropFrame.midY - fitRect.midY)
                            .blendMode(.destinationOut)
                    )
                )
                .compositingGroup()

            // Transparent hit area so users can drag the crop box from anywhere inside it.
            Rectangle()
                .fill(Color.clear)
                .frame(width: cropFrame.width, height: cropFrame.height)
                .position(x: cropFrame.midX, y: cropFrame.midY)
                .contentShape(Rectangle())
                .gesture(cropDragGesture(handle: .move, fitRect: fitRect))

            Rectangle()
                .stroke(Color.cyan.opacity(0.95), lineWidth: 2)
                .frame(width: cropFrame.width, height: cropFrame.height)
                .position(x: cropFrame.midX, y: cropFrame.midY)

            cropHandles(cropFrame: cropFrame, fitRect: fitRect)
        }
    }

    private func cropHandles(cropFrame: CGRect, fitRect: CGRect) -> some View {
        ZStack {
            handleDot(position: CGPoint(x: cropFrame.minX, y: cropFrame.minY), handle: .topLeft, fitRect: fitRect)
            handleDot(position: CGPoint(x: cropFrame.midX, y: cropFrame.minY), handle: .top, fitRect: fitRect)
            handleDot(position: CGPoint(x: cropFrame.maxX, y: cropFrame.minY), handle: .topRight, fitRect: fitRect)
            handleDot(position: CGPoint(x: cropFrame.minX, y: cropFrame.midY), handle: .left, fitRect: fitRect)
            handleDot(position: CGPoint(x: cropFrame.maxX, y: cropFrame.midY), handle: .right, fitRect: fitRect)
            handleDot(position: CGPoint(x: cropFrame.minX, y: cropFrame.maxY), handle: .bottomLeft, fitRect: fitRect)
            handleDot(position: CGPoint(x: cropFrame.midX, y: cropFrame.maxY), handle: .bottom, fitRect: fitRect)
            handleDot(position: CGPoint(x: cropFrame.maxX, y: cropFrame.maxY), handle: .bottomRight, fitRect: fitRect)
        }
    }

    private func handleDot(position: CGPoint, handle: VideoCropHandle, fitRect: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 10, height: 10)
            .position(position)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(cropDragGesture(handle: handle, fitRect: fitRect))
    }

    private func cropDragGesture(handle: VideoCropHandle, fitRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if cropDragStartRect == nil {
                    cropDragStartRect = viewModel.cropRectNormalized.cgRect
                }
                guard let start = cropDragStartRect else { return }

                if viewModel.cropRectNormalized.cgRect != start {
                    // keep using the first rect for stable relative drag
                }

                viewModel.cropRectNormalized = VideoCropRect(start)
                viewModel.updateCropRectByDrag(
                    handle: handle,
                    translation: value.translation,
                    overlayVideoDisplaySize: fitRect.size
                )
            }
            .onEnded { _ in
                cropDragStartRect = nil
            }
    }

    private var timelineBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(Color.white.opacity(0.95))
                }
                .buttonStyle(.plain)

                Text(viewModel.currentTimeText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.92))

                Text("保留开始(秒)")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.65))
                TextField("0", text: $viewModel.keepStartText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)

                Text("保留结束(秒)")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.65))
                TextField("10", text: $viewModel.keepEndText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)

                Button("应用保留区间") {
                    viewModel.applyQuickKeepRangeInput()
                }
                .buttonStyle(.bordered)

                Text(viewModel.totalDurationText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.72))

                Spacer(minLength: 0)
            }

            Slider(
                value: Binding(
                    get: { viewModel.playbackPosition },
                    set: { viewModel.scrub(to: $0) }
                ),
                in: 0...max(viewModel.sourceDuration, 0.1)
            )
            .tint(Color.cyan.opacity(0.95))

            deleteTrackToolbar
            deleteTrackArea
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.62))
    }

    private var deleteTrackToolbar: some View {
        HStack(spacing: 10) {
            Text("删除区间轨道")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.8))

            Text("FPS \(String(format: "%.2f", viewModel.videoFPS))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.52))

            Button("新增区间") {
                viewModel.addDeleteRangeAtPlayhead()
            }
            .buttonStyle(.bordered)

            Button(viewModel.isExporting ? "处理中..." : "选中删除") {
                viewModel.deleteSelectedRangeAndReload()
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canDeleteSelectedRangeAndReload)

            Spacer(minLength: 0)
        }
    }

    private var deleteTrackArea: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)

                if viewModel.deleteRanges.isEmpty {
                    Text("暂无删除区间，可点击“新增区间”或通过保留区间快捷生成。")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.horizontal, 10)
                } else {
                    ForEach(viewModel.deleteRanges) { range in
                        deleteRangeChip(range: range, trackWidth: proxy.size.width)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.selectDeleteRange(id: nil)
            }
        }
        .frame(height: 42)
    }

    private func deleteRangeChip(range: CutRange, trackWidth: CGFloat) -> some View {
        let duration = max(viewModel.sourceDuration, 0.001)
        let start = viewModel.deleteRangeStartSeconds(for: range.id)
        let end = viewModel.deleteRangeEndSeconds(for: range.id)
        let startRatio = CGFloat(start / duration)
        let endRatio = CGFloat(end / duration)
        let x = trackWidth * startRatio
        let width = max(18, trackWidth * max(0, endRatio - startRatio))
        let isSelected = viewModel.selectedDeleteRangeID == range.id

        return HStack(spacing: 0) {
            handleView(systemName: "chevron.left.2", trackWidth: trackWidth) { delta in
                let nextStart = start + delta * duration
                viewModel.updateDeleteRange(id: range.id, start: nextStart)
            }

            Rectangle()
                .fill(Color.red.opacity(isSelected ? 0.75 : 0.55))
                .overlay(
                    Text("\(String(format: "%.2f", start))s - \(String(format: "%.2f", end))s")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .padding(.horizontal, 6),
                    alignment: .center
                )
                .onTapGesture {
                    viewModel.selectDeleteRange(id: range.id)
                }

            handleView(systemName: "chevron.right.2", trackWidth: trackWidth) { delta in
                let nextEnd = end + delta * duration
                viewModel.updateDeleteRange(id: range.id, end: nextEnd)
            }
        }
        .frame(width: width, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? Color.cyan.opacity(0.9) : Color.white.opacity(0.18), lineWidth: isSelected ? 2 : 1)
        )
        .position(x: x + width / 2, y: 21)
    }

    private func handleView(systemName: String, trackWidth: CGFloat, onDragDeltaRatio: @escaping (Double) -> Void) -> some View {
        Image(systemName: systemName)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.white.opacity(0.9))
            .frame(width: 14, height: 30)
            .background(Color.black.opacity(0.22))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let deltaRatio = value.translation.width / max(trackWidth, 1)
                        onDragDeltaRatio(Double(deltaRatio))
                    }
            )
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text("目标比例")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                Button(viewModel.isApplyingCrop ? "处理中..." : "执行裁切") {
                    viewModel.executeCropAndReload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canExecuteCrop)
            }

            VStack(spacing: 10) {
                ForEach(Array(aspectGridRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 10) {
                        ForEach(row) { preset in
                            aspectCard(for: preset)
                        }
                        if row.count < 4 {
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("重置裁切框") {
                    viewModel.resetCropRect()
                }
                .buttonStyle(.bordered)

                if viewModel.isCropNoOp {
                    Text("当前无可裁切变化")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }

            Divider().overlay(Color.white.opacity(0.08))
                .padding(.vertical, 4)

            audioSection

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(width: 380)
        .background(Color(red: 0.11, green: 0.12, blue: 0.14))
    }

    private func aspectCard(for preset: VideoCuttingAspectPreset) -> some View {
        let selected = preset == viewModel.selectedAspectPreset
        return Button {
            viewModel.selectedAspectPreset = preset
            viewModel.applyPresetToCropRect()
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.2)
                    .frame(width: 32, height: 20)
                Text(preset.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .frame(width: 80, height: 80)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Color.cyan.opacity(0.95) : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("声音降噪🔊")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("背景降噪")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.78))

                    Toggle("", isOn: Binding(
                        get: { viewModel.isNoiseReductionEnabled },
                        set: { viewModel.updateNoiseReductionEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!viewModel.hasAudioTrack)

                    Spacer(minLength: 0)

                    Text("\(Int(viewModel.noiseReductionPercent.rounded())) %")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.82))
                }

                Slider(
                    value: Binding(
                        get: { viewModel.noiseReductionPercent },
                        set: { viewModel.updateNoiseReductionPercent($0) }
                    ),
                    in: 0...100,
                    step: 1
                )
                .tint(Color.cyan.opacity(0.9))
                .disabled(!viewModel.hasAudioTrack || !viewModel.isNoiseReductionEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 10) {
                Text("均衡器")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.78))
                Spacer(minLength: 0)
                Picker(
                    "",
                    selection: Binding(
                        get: { viewModel.selectedAudioEQPreset },
                        set: { viewModel.updateAudioEQPreset($0) }
                    )
                ) {
                    ForEach(VideoCuttingAudioEQPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!viewModel.hasAudioTrack)
                .frame(width: 170)
            }

            if !viewModel.hasAudioTrack {
                Text("源视频无音频轨道")
                    .font(.caption)
                    .foregroundStyle(Color.orange.opacity(0.86))
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("重新导入") {
                viewModel.importByPanel()
            }
            .buttonStyle(.bordered)

            if let exportURL = viewModel.exportURL {
                Button("打开导出文件") {
                    viewModel.revealExport()
                }
                .buttonStyle(.bordered)
                .help(exportURL.path)
            }

            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.64))
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(viewModel.isExporting ? "导出中..." : "导出") {
                viewModel.exportTrimmedVideo()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canExport)

            Button("导入到新草稿") {
                viewModel.importByPanel()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.19, green: 0.20, blue: 0.23))
    }

    private func dismissCuttingWindow() {
        if let windowID {
            dismissWindow(id: windowID)
        } else {
            dismissWindow()
        }
    }
}
