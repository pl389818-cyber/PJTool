import AVFoundation
import Foundation

private struct DeviceSnapshot {
    let videoAuth: AVAuthorizationStatus
    let audioAuth: AVAuthorizationStatus
    let videoDiscoveryCount: Int
    let videoLegacyCount: Int
    let videoMergedCount: Int
    let videoAvailableCount: Int
    let audioDiscoveryCount: Int
    let audioLegacyCount: Int
    let audioMergedCount: Int
    let audioAvailableCount: Int
    let includesSystemDefaultVideo: Bool
    let videoNames: [String]
    let audioNames: [String]
}

@main
private struct DeviceDiagnosticsRunner {
    static func main() {
        let snapshot = collect()
        print("DEVICE_DIAGNOSTICS")
        print("videoAuth=\(authText(snapshot.videoAuth))")
        print("audioAuth=\(authText(snapshot.audioAuth))")
        print("video: discovery=\(snapshot.videoDiscoveryCount) legacy=\(snapshot.videoLegacyCount) merged=\(snapshot.videoMergedCount) available=\(snapshot.videoAvailableCount) includesDefault=\(snapshot.includesSystemDefaultVideo)")
        print("audio: discovery=\(snapshot.audioDiscoveryCount) legacy=\(snapshot.audioLegacyCount) merged=\(snapshot.audioMergedCount) available=\(snapshot.audioAvailableCount)")
        print("videoNames=\(snapshot.videoNames.joined(separator: " | "))")
        print("audioNames=\(snapshot.audioNames.joined(separator: " | "))")
        let videoPass = snapshot.videoMergedCount > 0 || snapshot.videoDiscoveryCount > 0 || snapshot.videoLegacyCount > 0
        let audioPass = snapshot.audioMergedCount > 0 || snapshot.audioDiscoveryCount > 0 || snapshot.audioLegacyCount > 0
        if videoPass && audioPass {
            print("DIAGNOSTIC_RESULT PASS")
            exit(0)
        }
        print("DIAGNOSTIC_RESULT WARN")
        exit(2)
    }

    private static func collect() -> DeviceSnapshot {
        let videoAuth = AVCaptureDevice.authorizationStatus(for: .video)
        let audioAuth = AVCaptureDevice.authorizationStatus(for: .audio)

        let videoDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        let videoLegacy = AVCaptureDevice.devices(for: .video)

        var mergedVideo = deduplicate(videoDiscovery + videoLegacy)
        var includesSystemDefaultVideo = false
        if let preferred = AVCaptureDevice.default(for: .video),
           !mergedVideo.contains(where: { $0.uniqueID == preferred.uniqueID }) {
            mergedVideo.append(preferred)
            includesSystemDefaultVideo = true
        }
        mergedVideo.sort { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }

        let audioDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
        let audioLegacy = AVCaptureDevice.devices(for: .audio)
        let mergedAudio = deduplicate(audioDiscovery + audioLegacy)
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }

        return DeviceSnapshot(
            videoAuth: videoAuth,
            audioAuth: audioAuth,
            videoDiscoveryCount: videoDiscovery.count,
            videoLegacyCount: videoLegacy.count,
            videoMergedCount: mergedVideo.count,
            videoAvailableCount: mergedVideo.filter { $0.isConnected && !$0.isSuspended }.count,
            audioDiscoveryCount: audioDiscovery.count,
            audioLegacyCount: audioLegacy.count,
            audioMergedCount: mergedAudio.count,
            audioAvailableCount: mergedAudio.filter { $0.isConnected && !$0.isSuspended }.count,
            includesSystemDefaultVideo: includesSystemDefaultVideo,
            videoNames: mergedVideo.map { describe($0) },
            audioNames: mergedAudio.map { describe($0) }
        )
    }

    private static func deduplicate(_ devices: [AVCaptureDevice]) -> [AVCaptureDevice] {
        Array(Dictionary(devices.map { ($0.uniqueID, $0) }, uniquingKeysWith: { current, _ in current }).values)
    }

    private static func describe(_ device: AVCaptureDevice) -> String {
        let continuity = device.isContinuityCamera ? "Continuity" : "Standard"
        let availability = device.isConnected && !device.isSuspended ? "Online" : "Offline"
        return "\(device.localizedName)[\(continuity),\(availability)]"
    }

    private static func authText(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }
}
