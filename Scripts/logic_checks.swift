import CoreGraphics
import CoreMedia
import Foundation

@main
private struct LogicChecksRunner {
    static func main() {
        var failures: [String] = []

        if PiPLayoutState.minimumSize != CGSize(width: 120, height: 67) {
            failures.append("PiP minimum size is not 120x67")
        }

        // Task A: keep-height aspect switch + bounds clamp.
        let sourceRect = CGRect(x: 0.78, y: 0.80, width: 0.20, height: 0.12)
        let switched = PiPGeometry.applyAspectSwitchKeepHeight(
            normalizedRect: sourceRect,
            targetAspectRatio: .fourByThree,
            screenSize: CGSize(width: 1920, height: 1080)
        )
        let switchedHeightPixels = switched.height * 1080
        let sourceHeightPixels = sourceRect.height * 1080
        if abs(switchedHeightPixels - sourceHeightPixels) > 1.0 {
            failures.append("Aspect switch should keep height in pixels")
        }
        if switched.maxX > 1.0001 || switched.maxY > 1.0001 || switched.minX < -0.0001 || switched.minY < -0.0001 {
            failures.append("Aspect switch output must stay inside normalized bounds")
        }

        let normalized = PiPGeometry.normalizeLayout(
            PiPLayoutState(
                normalizedRect: CGRect(x: 0.95, y: 0.95, width: 0.5, height: 0.5),
                aspectRatio: .sixteenByNine
            ),
            screenSize: CGSize(width: 1280, height: 720)
        )
        if normalized.normalizedRect.maxX > 1.0001 || normalized.normalizedRect.maxY > 1.0001 {
            failures.append("Normalized PiP layout should clamp to screen bounds")
        }
        let minW = PiPLayoutState.minimumSize.width / 1280.0
        let minH = PiPLayoutState.minimumSize.height / 720.0
        if normalized.normalizedRect.width < minW - 0.0001 || normalized.normalizedRect.height < minH - 0.0001 {
            failures.append("Normalized PiP layout should enforce minimum size")
        }

        let autoScaled = PiPGeometry.normalizeLayout(
            PiPLayoutState(
                normalizedRect: CGRect(x: 0.94, y: 0.92, width: 0.50, height: 0.38),
                aspectRatio: .auto
            ),
            screenSize: CGSize(width: 1920, height: 1080)
        )
        let autoRect = autoScaled.normalizedRect
        if autoRect.maxX > 1.0001 || autoRect.maxY > 1.0001 || autoRect.minX < -0.0001 || autoRect.minY < -0.0001 {
            failures.append("Auto aspect should remain inside normalized bounds")
        }
        if autoRect.width > (PiPGeometry.maxWidthRatio + 0.0001) {
            failures.append("Auto aspect should obey max width ratio")
        }

        // Task B: Continuity/offline badge and source sorting semantics.
        let continuity = CameraSource(
            id: "cam.cont",
            name: "iPhone Camera",
            manufacturer: "Apple",
            modelID: "cont",
            isBuiltIn: false,
            isContinuity: true,
            isAvailable: true
        )
        let offline = CameraSource(
            id: "cam.off",
            name: "External Cam",
            manufacturer: "Vendor",
            modelID: "usb",
            isBuiltIn: false,
            isContinuity: false,
            isAvailable: false
        )
        if !continuity.badgeText.contains("Continuity") {
            failures.append("Continuity camera should include Continuity badge")
        }
        if !offline.badgeText.contains("Offline") {
            failures.append("Offline camera should include Offline badge")
        }

        // Existing insert-at-any-time behavior.
        let importEngine = ImportCompositeEngine()
        importEngine.addClip(
            url: URL(fileURLWithPath: "/tmp/insert-late.mp4"),
            insertTimeSeconds: 5.0,
            mute: false
        )
        importEngine.addClip(
            url: URL(fileURLWithPath: "/tmp/insert-early.mp4"),
            insertTimeSeconds: -2.0,
            mute: true
        )
        let layers = importEngine.layers
        if layers.count != 2 {
            failures.append("Import engine should contain exactly 2 layers")
        } else {
            if abs(layers[0].insertTime.seconds - 0.0) > 0.0001 {
                failures.append("Negative insert time should be clamped to 0")
            }
            if abs(layers[1].insertTime.seconds - 5.0) > 0.0001 {
                failures.append("Layers should remain sorted by insert time")
            }
        }

        // Task C: preview mute semantics are config-level only (export unaffected).
        let mutedConfig = PiPAudioPreviewConfig(isPreviewMuted: true, previewVolume: 0.7)
        let unmutedConfig = PiPAudioPreviewConfig(isPreviewMuted: false, previewVolume: 0.7)
        if mutedConfig.clampedVolume != unmutedConfig.clampedVolume {
            failures.append("Preview mute should not change configured volume")
        }
        if !mutedConfig.isPreviewMuted || unmutedConfig.isPreviewMuted {
            failures.append("Preview mute flags did not roundtrip")
        }

        // Task D: keyframe normalization and monotonic timeline.
        let keyframes = [
            FaceFramingKeyframe(seconds: 0.35, normalizedRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
            FaceFramingKeyframe(seconds: -0.1, normalizedRect: CGRect(x: -0.2, y: -0.2, width: 1.4, height: 1.4)),
            FaceFramingKeyframe(seconds: 0.70, normalizedRect: CGRect(x: 0.3, y: 0.1, width: 0.5, height: 0.6))
        ]
        let normalizedFrames = PiPFramingKeyframeNormalizer.normalized(keyframes)
        if normalizedFrames.count != 2 {
            failures.append("Keyframe normalization should drop negative timestamp frames")
        } else {
            if normalizedFrames[0].seconds > normalizedFrames[1].seconds {
                failures.append("Keyframes should be sorted by ascending seconds")
            }
            for frame in normalizedFrames {
                let rect = frame.normalizedRect
                if rect.minX < -0.0001 || rect.minY < -0.0001 || rect.maxX > 1.0001 || rect.maxY > 1.0001 {
                    failures.append("Normalized keyframe rect must be in [0,1] range")
                    break
                }
            }
        }

        // Existing trim keep-range check.
        let trimEngine = TrimExportEngine()
        let deleteRanges = [
            CutRange(
                start: CMTime(seconds: 2.0, preferredTimescale: 600),
                end: CMTime(seconds: 1.0, preferredTimescale: 600)
            ),
            CutRange(
                start: CMTime(seconds: 3.0, preferredTimescale: 600),
                end: CMTime(seconds: 5.0, preferredTimescale: 600)
            ),
            CutRange(
                start: CMTime(seconds: 4.0, preferredTimescale: 600),
                end: CMTime(seconds: 6.0, preferredTimescale: 600)
            )
        ]
        let keepRanges = trimEngine.keepRanges(
            from: deleteRanges,
            sourceDuration: CMTime(seconds: 10.0, preferredTimescale: 600)
        )
        let expected: [(Double, Double)] = [(0.0, 1.0), (2.0, 3.0), (6.0, 10.0)]
        if keepRanges.count != expected.count {
            failures.append("Unexpected keep range count: \(keepRanges.count)")
        } else {
            for (index, range) in keepRanges.enumerated() {
                let start = range.start.seconds
                let end = CMTimeRangeGetEnd(range).seconds
                let target = expected[index]
                if abs(start - target.0) > 0.001 || abs(end - target.1) > 0.001 {
                    failures.append("Keep range mismatch at index \(index): got [\(start), \(end)]")
                }
            }
        }

        if failures.isEmpty {
            print("LOGIC_CHECK PASS")
            print("- TaskA geometry: keep-height + bounds + min-size")
            print("- TaskB badges: Continuity/Offline visibility")
            print("- TaskC preview mute semantics: monitor-only config")
            print("- TaskD keyframes: monotonic + normalized rect range")
            print("- Stitch insert and multi-trim baseline checks")
            exit(0)
        }

        print("LOGIC_CHECK FAIL")
        for failure in failures {
            print("- \(failure)")
        }
        exit(1)
    }
}
