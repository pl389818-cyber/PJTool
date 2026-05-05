//
//  VideoCuttingAudioProcessingEngine.swift
//  PJTool
//
//  Created by Codex on 2026/5/5.
//

import AVFoundation
import CoreMedia
import MediaToolbox
import Foundation

final class VideoCuttingAudioProcessingEngine {
    func makeAudioMixIfNeeded(
        asset: AVAsset,
        config: VideoCuttingAudioProcessingConfig
    ) throws -> AVAudioMix? {
        let normalized = config.clamped
        guard normalized.hasAnyProcessing else { return nil }
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else { return nil }
        return try makeAudioMixIfNeeded(track: audioTrack, config: normalized)
    }

    func makeAudioMixIfNeeded(
        track: AVAssetTrack?,
        config: VideoCuttingAudioProcessingConfig
    ) throws -> AVAudioMix? {
        let normalized = config.clamped
        guard normalized.hasAnyProcessing else { return nil }
        guard let track else { return nil }

        let tap = try createTap(config: normalized)
        let input = AVMutableAudioMixInputParameters(track: track)
        input.audioTapProcessor = tap

        let mix = AVMutableAudioMix()
        mix.inputParameters = [input]
        return mix
    }

    private func createTap(config: VideoCuttingAudioProcessingConfig) throws -> MTAudioProcessingTap {
        let state = TapState(config: config)

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(state).toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        var tapRef: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tapRef
        )
        guard status == noErr, let tapRef else {
            throw AudioProcessingError.createTapFailed(status)
        }
        return tapRef
    }
}

private final class TapState {
    var config: VideoCuttingAudioProcessingConfig
    private var gateEnvelope: Float = 0
    private var isSupportedFormat = true

    init(config: VideoCuttingAudioProcessingConfig) {
        self.config = config.clamped
    }

    func prepare(_ processingFormat: AudioStreamBasicDescription) {
        gateEnvelope = 0
        let isLinearPCM = processingFormat.mFormatID == kAudioFormatLinearPCM
        let isFloat = (processingFormat.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let bitsPerChannel = processingFormat.mBitsPerChannel
        isSupportedFormat = isLinearPCM && isFloat && bitsPerChannel == 32
    }

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: CMItemCount) {
        guard isSupportedFormat else { return }
        let cfg = config.clamped
        let denoise = Float(cfg.noiseReductionEnabled ? cfg.noiseReductionPercent / 100.0 : 0)
        let params = eqPresetParams(cfg.eqPreset)

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard !buffers.isEmpty else { return }

        let gateThreshold: Float = 0.008 + (0.03 * denoise)
        let gateFloor: Float = max(0.05, 1.0 - denoise * 0.8)
        let release: Float = 0.992

        for buffer in buffers {
            guard let mData = buffer.mData else { continue }
            let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let validCount = min(sampleCount, Int(frameCount))
            guard validCount > 0 else { continue }

            let samples = mData.bindMemory(to: Float.self, capacity: sampleCount)
            var low: Float = 0
            var high: Float = 0

            for i in 0..<validCount {
                var sample = samples[i]

                let absSample = abs(sample)
                gateEnvelope = max(absSample, gateEnvelope * release)
                if denoise > 0, gateEnvelope < gateThreshold {
                    sample *= gateFloor
                }

                low += params.lowPassAlpha * (sample - low)
                high = params.highPassAlpha * (high + sample - (i > 0 ? samples[i - 1] : sample))
                let mid = sample - low
                sample = low * params.lowGain + mid * params.midGain + high * params.highGain

                let drive: Float = 1 + (denoise * 0.35)
                samples[i] = tanh(sample * drive)
            }
        }
    }

    private func eqPresetParams(_ preset: VideoCuttingAudioEQPreset) -> EQParams {
        switch preset {
        case .balanced:
            return EQParams(lowGain: 1.0, midGain: 1.0, highGain: 1.0, lowPassAlpha: 0.12, highPassAlpha: 0.06)
        case .vocalBoost:
            return EQParams(lowGain: 0.9, midGain: 1.22, highGain: 1.1, lowPassAlpha: 0.11, highPassAlpha: 0.07)
        case .musicBoost:
            return EQParams(lowGain: 1.14, midGain: 1.0, highGain: 1.12, lowPassAlpha: 0.12, highPassAlpha: 0.06)
        case .loudness:
            return EQParams(lowGain: 1.2, midGain: 1.12, highGain: 1.15, lowPassAlpha: 0.13, highPassAlpha: 0.065)
        case .humReduction:
            return EQParams(lowGain: 0.72, midGain: 1.05, highGain: 1.03, lowPassAlpha: 0.10, highPassAlpha: 0.09)
        case .bassBoost:
            return EQParams(lowGain: 1.3, midGain: 0.96, highGain: 0.95, lowPassAlpha: 0.13, highPassAlpha: 0.05)
        case .bassCut:
            return EQParams(lowGain: 0.76, midGain: 1.02, highGain: 1.02, lowPassAlpha: 0.11, highPassAlpha: 0.075)
        case .trebleBoost:
            return EQParams(lowGain: 0.95, midGain: 1.0, highGain: 1.28, lowPassAlpha: 0.13, highPassAlpha: 0.09)
        case .trebleCut:
            return EQParams(lowGain: 1.02, midGain: 1.0, highGain: 0.74, lowPassAlpha: 0.11, highPassAlpha: 0.05)
        }
    }
}

private struct EQParams {
    let lowGain: Float
    let midGain: Float
    let highGain: Float
    let lowPassAlpha: Float
    let highPassAlpha: Float
}

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    guard let clientInfo else { return }
    tapStorageOut.pointee = clientInfo
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<TapState>.fromOpaque(storage).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let state = Unmanaged<TapState>.fromOpaque(storage).takeUnretainedValue()
    state.prepare(processingFormat.pointee)
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in
}

private let tapProcess: MTAudioProcessingTapProcessCallback = { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
    var localFlags: MTAudioProcessingTapFlags = 0
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, &localFlags, nil, numberFramesOut)
    guard status == noErr else {
        flagsOut.pointee = localFlags
        return
    }

    let storage = MTAudioProcessingTapGetStorage(tap)
    let state = Unmanaged<TapState>.fromOpaque(storage).takeUnretainedValue()
    state.process(bufferList: bufferListInOut, frameCount: numberFramesOut.pointee)
    flagsOut.pointee = localFlags
}

extension VideoCuttingAudioProcessingEngine {
    enum AudioProcessingError: LocalizedError {
        case createTapFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .createTapFailed(status):
                return "创建音频处理链失败：\(status)"
            }
        }
    }
}
