//
//  TrimModels.swift
//  PJTool
//
//  Created by Codex on 2026/4/29.
//

import CoreMedia
import Foundation

struct CutRange: Identifiable, Equatable {
    let id = UUID()
    var start: CMTime
    var end: CMTime

    var normalized: CutRange {
        if end < start {
            return CutRange(start: end, end: start)
        }
        return self
    }
}

struct TrimProject: Equatable {
    var sourceURL: URL
    var deleteRanges: [CutRange]
}

struct TrimExportRequest {
    let sourceURL: URL
    let keepRanges: [CMTimeRange]
    let outputURL: URL
}
