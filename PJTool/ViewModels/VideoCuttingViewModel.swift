//
//  VideoCuttingViewModel.swift
//  PJTool
//
//  Created by Codex on 2026/5/4.
//

import AVFoundation
import Combine
import CoreMedia
import Foundation
import UniformTypeIdentifiers

@MainActor
final class VideoCuttingViewModel: ObservableObject {
    @Published var sourceURL: URL?
    @Published var sourceDuration: Double = 0
    @Published var keepStartText: String = "0"
    @Published var keepEndText: String = "10"
    @Published var deleteRanges: [CutRange] = []
    @Published var selectedDeleteRangeID: UUID?
    @Published var statusMessage: String = L10n.tr("legacy.key_202")
    @Published var isExporting = false
    @Published var exportURL: URL?
    @Published var selectedAspectPreset: VideoCuttingAspectPreset = .adaptive
    @Published var playbackPosition: Double = 0
    @Published var isPlaying = false
    @Published var hasPlaybackReady = false
    @Published var isImportPanelPresented = false
    @Published private(set) var videoFPS: Double = 30
    @Published private(set) var frameDurationSeconds: Double = 1.0 / 30.0
    @Published private(set) var sourceVideoSize: CGSize = .zero
    @Published private(set) var sourceVideoAspect: Double = 16.0 / 9.0
    @Published var cropRectNormalized: VideoCropRect = .full
    @Published var isApplyingCrop = false
    @Published var isNoiseReductionEnabled = true
    @Published var noiseReductionPercent: Double = 50
    @Published var selectedAudioEQPreset: VideoCuttingAudioEQPreset = .balanced
    @Published private(set) var hasAudioTrack = false
    @Published private(set) var isApplyingAudioPreview = false

    private let trimEngine: TrimExportEngine
    private let composeExportEngine = VideoCuttingComposeExportEngine()
    private let audioProcessingEngine = VideoCuttingAudioProcessingEngine()
    private let importService = VideoCuttingImportService()
    private let trimService = VideoCuttingTrimService()
    private let exportService = VideoCuttingExportService()
    private var cancellables: Set<AnyCancellable> = []
    private var timeObserverToken: Any?
    private let defaultFPS: Double = 30
    private let minimumFrameDuration: Double = 1.0 / 120.0
    private let maximumFrameDuration: Double = 1.0
    private let cropMinPoints = CGSize(width: 120, height: 120)
    let player = AVPlayer()
    let noiseReductionStep: Double = 10

    init(trimEngine: TrimExportEngine? = nil) {
        self.trimEngine = trimEngine ?? TrimExportEngine()
        configurePlayerObservers()
        configurePlayerStateObservers()
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
    }

    var canExport: Bool {
        sourceURL != nil && !isBusy && sourceDuration > 0
    }

    var canDeleteSelectedRangeAndReload: Bool {
        guard sourceURL != nil, !isBusy, sourceDuration > 0, let selectedDeleteRange else { return false }
        let normalized = normalizeDeleteRanges([selectedDeleteRange])
        guard !normalized.isEmpty else { return false }
        let keepRanges = trimEngine.keepRanges(from: normalized, sourceDuration: makeDurationTime())
        return !keepRanges.isEmpty
    }

    var canExecuteCrop: Bool {
        guard sourceURL != nil, !isBusy, sourceDuration > 0 else { return false }
        let crop = normalizedCropRect
        guard crop.width > 0, crop.height > 0 else { return false }
        return !isCropNoOp
    }

    var isBusy: Bool {
        isExporting || isApplyingCrop
    }

    var audioProcessingConfig: VideoCuttingAudioProcessingConfig {
        VideoCuttingAudioProcessingConfig(
            noiseReductionEnabled: isNoiseReductionEnabled,
            noiseReductionPercent: noiseReductionPercent,
            eqPreset: selectedAudioEQPreset
        ).clamped
    }

    var hasSource: Bool {
        sourceURL != nil
    }

    var selectedDeleteRange: CutRange? {
        guard let selectedDeleteRangeID else { return nil }
        return deleteRanges.first { $0.id == selectedDeleteRangeID }
    }

    var allowedImportTypes: [UTType] {
        importService.allowedTypes
    }

    var isCropNoOp: Bool {
        let crop = normalizedCropRect
        let full = abs(crop.minX) <= 0.0005 &&
            abs(crop.minY) <= 0.0005 &&
            abs(crop.width - 1) <= 0.0005 &&
            abs(crop.height - 1) <= 0.0005
        return full && normalizeDeleteRanges(deleteRanges).isEmpty
    }

    func importByPanel() {
        isImportPanelPresented = true
    }

    func handleImportPanelResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let selectedURL = urls.first else {
                statusMessage = L10n.tr("legacy.key_52")
                return
            }
            do {
                let persisted = try importService.persistImportedVideo(from: selectedURL)
                loadVideo(url: persisted)
            } catch {
                statusMessage = error.localizedDescription
            }
        case let .failure(error):
            statusMessage = L10n.f("fmt.video.import_failed", error.localizedDescription)
        }
    }

    func handleImportPanelCancellation() {
        statusMessage = L10n.tr("legacy.key_84")
    }

    func handleDrop(providers: [NSItemProvider]) {
        importService.resolveDroppedProviders(providers) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(url):
                self.loadVideo(url: url)
            case let .failure(error):
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func applyQuickKeepRangeInput() {
        guard hasSource else {
            statusMessage = L10n.tr("legacy.key_201")
            return
        }

        guard let start = Double(keepStartText), let end = Double(keepEndText) else {
            statusMessage = L10n.tr("legacy.key_11")
            return
        }

        let snappedStart = snapToFrame(start)
        let snappedEnd = snapToFrame(end)
        let lower = min(snappedStart, snappedEnd)
        let upper = max(snappedStart, snappedEnd)

        guard upper > lower else {
            statusMessage = L10n.tr("legacy.key_10")
            return
        }

        var ranges: [CutRange] = []
        if lower > 0 {
            ranges.append(makeCutRange(start: 0, end: lower))
        }
        if upper < sourceDuration {
            ranges.append(makeCutRange(start: upper, end: sourceDuration))
        }

        keepStartText = formatSecondsForInput(lower)
        keepEndText = formatSecondsForInput(upper)
        applyDeleteRangeEdit(ranges, preferSelection: nil, editMessage: L10n.tr("legacy.key_87"))
    }

    func addDeleteRangeAtPlayhead() {
        guard hasSource else {
            statusMessage = L10n.tr("legacy.key_201")
            return
        }
        let start = snapToFrame(playbackPosition)
        let defaultLength = max(frameDurationSeconds * 15, 0.5)
        let end = snapToFrame(min(sourceDuration, start + defaultLength))
        guard end > start else {
            statusMessage = L10n.tr("legacy.key_150")
            return
        }
        var updated = deleteRanges
        let range = makeCutRange(start: start, end: end)
        updated.append(range)
        applyDeleteRangeEdit(updated, preferSelection: range.id, editMessage: L10n.tr("legacy.key_91"))
    }

    func updateDeleteRange(id: UUID, start: Double? = nil, end: Double? = nil) {
        guard let index = deleteRanges.firstIndex(where: { $0.id == id }) else { return }
        var range = deleteRanges[index]
        if let start {
            range.start = makeTime(snapToFrame(start))
        }
        if let end {
            range.end = makeTime(snapToFrame(end))
        }
        var updated = deleteRanges
        updated[index] = range
        applyDeleteRangeEdit(updated, preferSelection: id)
    }

    func removeDeleteRange(id: UUID) {
        let updated = deleteRanges.filter { $0.id != id }
        applyDeleteRangeEdit(updated, preferSelection: selectedDeleteRangeID, editMessage: L10n.tr("legacy.key_83"))
    }

    func removeSelectedDeleteRange() {
        guard let selectedDeleteRangeID else { return }
        removeDeleteRange(id: selectedDeleteRangeID)
    }

    func deleteSelectedRangeAndReload() {
        guard let sourceURL else {
            statusMessage = L10n.tr("legacy.key_26")
            return
        }
        guard let selectedDeleteRange else {
            statusMessage = L10n.tr("legacy.key_27")
            return
        }

        let normalized = normalizeDeleteRanges([selectedDeleteRange])
        guard let selectedRange = normalized.first else {
            statusMessage = L10n.tr("legacy.key_28")
            return
        }

        let sourceDuration = makeDurationTime()
        let keepRanges = trimEngine.keepRanges(from: [selectedRange], sourceDuration: sourceDuration)
        guard !keepRanges.isEmpty else {
            statusMessage = L10n.tr("legacy.key_29")
            return
        }

        let outputURL: URL
        do {
            outputURL = try makeInlineTrimOutputURL(for: sourceURL, suffix: "cut")
        } catch {
            statusMessage = L10n.tr("legacy.key_25")
            return
        }

        let project = trimService.makeProject(
            sourceURL: sourceURL,
            sourceDuration: sourceDuration,
            deleteRanges: [selectedRange]
        )

        isExporting = true
        statusMessage = L10n.tr("legacy.key_170")
        Task {
            defer { isExporting = false }
            do {
                let exported = try await trimEngine.export(project: project, outputURL: outputURL)
                loadVideo(url: exported)
                statusMessage = L10n.f("fmt.video.delete_selected_reloaded", exported.lastPathComponent)
            } catch {
                statusMessage = L10n.f("fmt.video.delete_failed", error.localizedDescription)
            }
        }
    }

    func selectDeleteRange(id: UUID?) {
        selectedDeleteRangeID = id
    }

    func deleteRangeStartSeconds(for id: UUID) -> Double {
        guard let range = deleteRanges.first(where: { $0.id == id }) else { return 0 }
        return clampedSeconds(range.normalized.start.seconds)
    }

    func deleteRangeEndSeconds(for id: UUID) -> Double {
        guard let range = deleteRanges.first(where: { $0.id == id }) else { return 0 }
        return clampedSeconds(range.normalized.end.seconds)
    }

    func exportTrimmedVideo() {
        guard let sourceURL else {
            statusMessage = L10n.tr("legacy.key_62")
            return
        }

        guard let outputURL = exportService.pickOutputURL(suggestedName: suggestedOutputName(for: sourceURL)) else {
            statusMessage = L10n.tr("legacy.key_85")
            return
        }

        let project = VideoCuttingComposeProject(
            sourceURL: sourceURL,
            deleteRanges: [],
            cropRectNormalized: .full,
            targetAspectPreset: .adaptive,
            audioProcessingConfig: audioProcessingConfig,
            outputURL: outputURL
        )

        isExporting = true
        if hasAudioTrack {
            statusMessage = L10n.tr("legacy.key_56")
        } else {
            statusMessage = L10n.tr("legacy.key_57")
        }
        Task {
            defer { isExporting = false }
            do {
                let exported = try await composeExportEngine.export(project: project)
                exportURL = exported
                let removedTempFiles = cleanupHistoricalTemporaryFilesAfterExport(
                    keeping: [sourceURL, exported]
                )
                if removedTempFiles > 0 {
                    statusMessage = L10n.f(
                        "fmt.video.export_done_with_cleanup",
                        exported.lastPathComponent,
                        removedTempFiles
                    )
                } else {
                    statusMessage = L10n.f("fmt.video.export_done", exported.lastPathComponent)
                }
            } catch {
                statusMessage = L10n.f("fmt.video.export_failed", error.localizedDescription)
            }
        }
    }

    func revealExport() {
        guard let exportURL else { return }
        exportService.revealInFinder(exportURL)
    }

    func updateNoiseReductionEnabled(_ isEnabled: Bool) {
        isNoiseReductionEnabled = isEnabled
        applyAudioPreviewProcessing()
    }

    func updateNoiseReductionPercent(_ percent: Double) {
        let clamped = max(0, min(100, percent))
        let snapped = (clamped / noiseReductionStep).rounded() * noiseReductionStep
        noiseReductionPercent = max(0, min(100, snapped))
        applyAudioPreviewProcessing()
    }

    func updateAudioEQPreset(_ preset: VideoCuttingAudioEQPreset) {
        selectedAudioEQPreset = preset
        applyAudioPreviewProcessing()
    }

    func applyAudioPreviewProcessing() {
        guard hasSource else { return }
        guard hasAudioTrack else { return }
        guard let sourceURL else { return }

        isApplyingAudioPreview = true
        defer { isApplyingAudioPreview = false }

        let asset = AVAsset(url: sourceURL)
        let item = makePlayerItem(for: asset)
        player.replaceCurrentItem(with: item)
        let seekTime = makeTime(playbackPosition)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        if isPlaying {
            player.play()
        } else {
            player.pause()
        }
    }

    func executeCropAndReload() {
        guard let sourceURL else {
            statusMessage = L10n.tr("legacy.key_129")
            return
        }
        guard canExecuteCrop else {
            statusMessage = isCropNoOp ? L10n.tr("legacy.key_104") : L10n.tr("legacy.key_128")
            return
        }

        let outputURL: URL
        do {
            outputURL = try makeInlineTrimOutputURL(for: sourceURL, suffix: "crop")
        } catch {
            statusMessage = L10n.tr("legacy.key_127")
            return
        }

        let project = VideoCuttingComposeProject(
            sourceURL: sourceURL,
            deleteRanges: normalizeDeleteRanges(deleteRanges),
            cropRectNormalized: VideoCropRect(normalizedCropRect),
            targetAspectPreset: selectedAspectPreset,
            audioProcessingConfig: audioProcessingConfig,
            outputURL: outputURL
        )

        isApplyingCrop = true
        statusMessage = L10n.tr("legacy.key_88")
        Task {
            defer { isApplyingCrop = false }
            do {
                let exported = try await composeExportEngine.export(project: project)
                loadVideo(url: exported)
                statusMessage = L10n.f("fmt.video.crop_reloaded", exported.lastPathComponent)
            } catch {
                statusMessage = L10n.f("fmt.video.crop_failed", error.localizedDescription)
            }
        }
    }

    func resetCropRect(showStatus: Bool = true) {
        guard hasSource else { return }
        cropRectNormalized = .full
        if showStatus {
            statusMessage = L10n.tr("legacy.key_94")
        }
    }

    func selectAspectPresetWithReset(_ preset: VideoCuttingAspectPreset) {
        guard hasSource else {
            selectedAspectPreset = preset
            return
        }
        selectedAspectPreset = preset
        // Prevent prior drag state from affecting new aspect interaction.
        resetCropRect(showStatus: false)
        applyPresetToCropRect()
    }

    func applyPresetToCropRect() {
        guard hasSource else { return }
        let minSize = normalizedCropMinSize(for: sourceVideoSize)
        let adjusted = VideoCropGeometry.adjustedRectForAspect(
            rect: normalizedCropRect,
            targetRatio: selectedAspectPreset.widthOverHeightRatio,
            minSize: minSize
        )
        cropRectNormalized = VideoCropRect(adjusted)
    }

    func updateCropRectByDrag(
        handle: VideoCropHandle,
        translation: CGSize,
        overlayVideoDisplaySize: CGSize
    ) {
        guard hasSource else { return }
        let minSize = normalizedCropMinSize(for: overlayVideoDisplaySize)
        let next = VideoCropGeometry.applyDrag(
            startRect: normalizedCropRect,
            translation: translation,
            handle: handle,
            displaySize: overlayVideoDisplaySize,
            lockedAspectRatio: selectedAspectPreset.widthOverHeightRatio,
            minSize: minSize
        )
        cropRectNormalized = VideoCropRect(next)
    }

    func togglePlayPause() {
        guard hasSource else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func seek(to seconds: Double) {
        let bounded = clampedSeconds(seconds)
        let time = makeTime(bounded)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        playbackPosition = bounded
    }

    func scrub(to seconds: Double) {
        seek(to: seconds)
    }

    func snapToFrame(_ seconds: Double) -> Double {
        let clamped = clampedSeconds(seconds)
        let frame = normalizedFrameDuration
        guard frame > 0 else { return clamped }
        let snapped = (clamped / frame).rounded() * frame
        let final = clampedSeconds(snapped)
        if sourceDuration > 0, sourceDuration - final <= frame / 2 {
            return sourceDuration
        }
        return final
    }

    func normalizeDeleteRanges(_ ranges: [CutRange]) -> [CutRange] {
        let snapped = ranges
            .map(\.normalized)
            .compactMap { range -> CutRange? in
                let start = snapToFrame(range.start.seconds)
                let end = snapToFrame(range.end.seconds)
                guard end > start else { return nil }
                return CutRange(id: range.id, start: makeTime(start), end: makeTime(end))
            }
            .sorted { lhs, rhs in
                if lhs.start == rhs.start {
                    return lhs.end < rhs.end
                }
                return lhs.start < rhs.start
            }

        guard var current = snapped.first else { return [] }
        var merged: [CutRange] = []
        let mergeTolerance = normalizedFrameDuration + 0.000_1

        for range in snapped.dropFirst() {
            let currentEnd = clampedSeconds(current.end.seconds)
            let nextStart = clampedSeconds(range.start.seconds)
            if nextStart <= currentEnd + mergeTolerance {
                let newEnd = max(currentEnd, clampedSeconds(range.end.seconds))
                current.end = makeTime(newEnd)
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }

    var totalDurationText: String {
        formatTime(sourceDuration)
    }

    var currentTimeText: String {
        formatTime(playbackPosition)
    }

    private var normalizedCropRect: CGRect {
        VideoCropGeometry.clampNormalizedRect(cropRectNormalized.cgRect)
    }

    private func loadVideo(url: URL) {
        guard importService.isSupportedVideo(url: url) else {
            statusMessage = L10n.tr("legacy.mp4_mov")
            return
        }

        let asset = AVAsset(url: url)
        let duration = max(0, asset.duration.seconds)
        guard duration > 0 else {
            statusMessage = L10n.tr("legacy.key_51")
            return
        }

        updateFrameInfo(from: asset)
        sourceURL = url
        sourceDuration = duration
        keepStartText = formatSecondsForInput(0)
        keepEndText = formatSecondsForInput(duration)
        deleteRanges = []
        selectedDeleteRangeID = nil
        cropRectNormalized = .full
        exportURL = nil
        playbackPosition = 0
        hasPlaybackReady = true
        hasAudioTrack = !asset.tracks(withMediaType: .audio).isEmpty
        player.pause()
        let item = makePlayerItem(for: asset)
        player.replaceCurrentItem(with: item)
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        isPlaying = false
        if hasAudioTrack {
            statusMessage = L10n.f("fmt.video.imported", url.lastPathComponent)
        } else {
            statusMessage = L10n.f("fmt.video.imported_no_audio_track", url.lastPathComponent)
        }
    }

    private func applyDeleteRangeEdit(_ ranges: [CutRange], preferSelection: UUID?, editMessage: String? = nil) {
        let normalized = normalizeDeleteRanges(ranges)
        deleteRanges = normalized
        resolveSelection(preferSelection: preferSelection)

        let keepRanges = trimEngine.keepRanges(from: normalized, sourceDuration: makeDurationTime())
        if keepRanges.isEmpty {
            statusMessage = L10n.tr("legacy.key_153")
            return
        }

        if normalized.isEmpty {
            statusMessage = L10n.tr("legacy.key_105")
            return
        }

        if let editMessage {
            statusMessage = L10n.f("fmt.video.edit_message_with_delete_count", editMessage, normalized.count)
        } else {
            statusMessage = L10n.f("fmt.video.delete_ranges_updated", normalized.count)
        }
    }

    private func resolveSelection(preferSelection: UUID?) {
        if let preferSelection, deleteRanges.contains(where: { $0.id == preferSelection }) {
            selectedDeleteRangeID = preferSelection
            return
        }
        if let selectedDeleteRangeID, deleteRanges.contains(where: { $0.id == selectedDeleteRangeID }) {
            return
        }
        selectedDeleteRangeID = deleteRanges.first?.id
    }

    private func updateFrameInfo(from asset: AVAsset) {
        guard let track = asset.tracks(withMediaType: .video).first else {
            videoFPS = defaultFPS
            frameDurationSeconds = 1.0 / defaultFPS
            sourceVideoSize = CGSize(width: 1920, height: 1080)
            sourceVideoAspect = 16.0 / 9.0
            return
        }

        let nominal = Double(track.nominalFrameRate)
        if nominal.isFinite, nominal > 0.1 {
            videoFPS = nominal
            frameDurationSeconds = 1.0 / nominal
        } else {
            let minDuration = track.minFrameDuration.seconds
            if minDuration.isFinite, minDuration > 0 {
                frameDurationSeconds = minDuration
                videoFPS = 1.0 / minDuration
            } else {
                videoFPS = defaultFPS
                frameDurationSeconds = 1.0 / defaultFPS
            }
        }

        let natural = track.naturalSize
        let oriented = CGRect(origin: .zero, size: natural).applying(track.preferredTransform)
        let size = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        sourceVideoSize = size
        if size.width > 1, size.height > 1 {
            sourceVideoAspect = Double(size.width / size.height)
        }
    }

    private func makeCutRange(start: Double, end: Double) -> CutRange {
        CutRange(start: makeTime(start), end: makeTime(end))
    }

    private func clampedSeconds(_ seconds: Double) -> Double {
        guard sourceDuration > 0 else { return max(0, seconds) }
        return max(0, min(seconds, sourceDuration))
    }

    private var normalizedFrameDuration: Double {
        let raw = frameDurationSeconds.isFinite && frameDurationSeconds > 0
            ? frameDurationSeconds
            : (1.0 / defaultFPS)
        return min(max(raw, minimumFrameDuration), maximumFrameDuration)
    }

    private func makeDurationTime() -> CMTime {
        makeTime(sourceDuration)
    }

    private func makeTime(_ seconds: Double) -> CMTime {
        let fpsTimescale = Int32((max(videoFPS, defaultFPS) * 1000).rounded())
        let timescale = max(CMTimeScale(600), CMTimeScale(fpsTimescale))
        return CMTime(seconds: max(0, seconds), preferredTimescale: timescale)
    }

    private func formatSecondsForInput(_ seconds: Double) -> String {
        String(format: "%.3f", max(0, seconds))
    }

    private func suggestedOutputName(for sourceURL: URL) -> String {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        return "\(stem)-trimmed.mp4"
    }

    private func makeInlineTrimOutputURL(for sourceURL: URL, suffix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PJTool", isDirectory: true)
            .appendingPathComponent("VideoCuttingEdits", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let shortID = String(UUID().uuidString.prefix(8))
        return folder.appendingPathComponent("\(stem)-\(suffix)-\(shortID).mp4")
    }

    @discardableResult
    private func cleanupHistoricalTemporaryFilesAfterExport(keeping urls: [URL]) -> Int {
        let expirationInterval: TimeInterval = 3 * 24 * 60 * 60
        let now = Date()
        let keepPaths = Set(urls.map { $0.standardizedFileURL.path })
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PJTool", isDirectory: true)
        let folders = [
            tempRoot.appendingPathComponent("VideoCuttingImports", isDirectory: true),
            tempRoot.appendingPathComponent("VideoCuttingEdits", isDirectory: true)
        ]

        var removedCount = 0
        for folder in folders {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for fileURL in files {
                let normalized = fileURL.standardizedFileURL
                guard !keepPaths.contains(normalized.path) else { continue }
                guard shouldRemoveTemporaryFile(
                    at: normalized,
                    now: now,
                    expirationInterval: expirationInterval
                ) else {
                    continue
                }
                do {
                    try FileManager.default.removeItem(at: normalized)
                    removedCount += 1
                } catch {
                    continue
                }
            }
        }
        return removedCount
    }

    private func shouldRemoveTemporaryFile(
        at fileURL: URL,
        now: Date,
        expirationInterval: TimeInterval
    ) -> Bool {
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
        guard values?.isRegularFile == true else { return false }
        let modifiedAt = values?.contentModificationDate ?? .distantPast
        return now.timeIntervalSince(modifiedAt) >= expirationInterval
    }

    private func normalizedCropMinSize(for displaySize: CGSize) -> CGSize {
        VideoCropGeometry.normalizeMinSize(minPoints: cropMinPoints, videoDisplaySize: displaySize)
    }

    private func makePlayerItem(for asset: AVAsset) -> AVPlayerItem {
        let item = AVPlayerItem(asset: asset)
        guard hasAudioTrack else { return item }
        guard let track = item.asset.tracks(withMediaType: .audio).first else { return item }
        do {
            item.audioMix = try audioProcessingEngine.makeAudioMixIfNeeded(
                track: track,
                config: audioProcessingConfig
            )
        } catch {
            statusMessage = L10n.f("fmt.video.audio_preview_processing_failed", error.localizedDescription)
        }
        return item
    }

    private func configurePlayerObservers() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = max(0, time.seconds)
                self.playbackPosition = min(seconds, self.sourceDuration)
            }
        }
    }

    private func configurePlayerStateObservers() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = (status == .playing)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isPlaying = false
                self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                self.playbackPosition = 0
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                self.isPlaying = false
                let message: String
                if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                    message = error.localizedDescription
                } else {
                    message = L10n.tr("legacy.key_165")
                }
                self.statusMessage = L10n.f("fmt.video.playback_failed", message)
            }
            .store(in: &cancellables)
    }

    private func formatTime(_ seconds: Double) -> String {
        let safe = max(0, Int(seconds.rounded(.down)))
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
