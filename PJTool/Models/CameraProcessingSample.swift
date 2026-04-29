//
//  CameraProcessingSample.swift
//  PJTool
//
//  Created by Codex on 2026/4/30.
//

import CoreMedia
import Foundation

struct CameraProcessingSample {
    let sampleBuffer: CMSampleBuffer
    let source: Source

    enum Source {
        case livePreview
        case exportedRecording
    }
}
