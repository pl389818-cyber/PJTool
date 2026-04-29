import AVFoundation
import Foundation

private struct Options {
    let outputURL: URL?
    let reportDirectory: URL?

    init(arguments: [String]) {
        if let index = arguments.firstIndex(of: "--output"), index + 1 < arguments.count {
            outputURL = URL(fileURLWithPath: arguments[index + 1])
        } else {
            outputURL = nil
        }

        if let index = arguments.firstIndex(of: "--report-dir"), index + 1 < arguments.count {
            reportDirectory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            reportDirectory = nil
        }
    }
}

@main
private struct ValidationSmokeRunner {
    static func main() {
        do {
            let options = Options(arguments: Array(CommandLine.arguments.dropFirst()))

            let cameraDevices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external],
                mediaType: .video,
                position: .unspecified
            ).devices
            let audioDevices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external],
                mediaType: .audio,
                position: .unspecified
            ).devices

            let cameraSources = cameraDevices.map(CameraSource.init(device:))
            let audioSources = audioDevices.map(AudioInputSource.init(device:))

            let service = ValidationService()
            let report = service.makeReport(
                mergedOutputURL: options.outputURL,
                cameraSources: cameraSources,
                audioSources: audioSources
            )
            let reportURL: URL
            if let reportDirectory = options.reportDirectory {
                reportURL = try service.persist(report: report, directory: reportDirectory)
            } else {
                reportURL = try service.persist(report: report)
            }

            guard FileManager.default.fileExists(atPath: reportURL.path) else {
                throw SmokeError.assertionFailed("Validation report file was not created")
            }
            guard report.items.contains(where: { $0.name == "导出文件存在" }) else {
                throw SmokeError.assertionFailed("Validation report missing export file check")
            }
            guard report.items.contains(where: { $0.name == "iPhone 摄像头可见" }) else {
                throw SmokeError.assertionFailed("Validation report missing iPhone camera check")
            }

            print("TASK4 PASS summary=\(report.summary)")
            print("TASK4 REPORT=\(reportURL.path)")
            for item in report.items {
                print("- \(item.status.rawValue) \(item.name): \(item.detail)")
            }
        } catch {
            fputs("SMOKE_FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private enum SmokeError: LocalizedError {
    case assertionFailed(String)

    var errorDescription: String? {
        switch self {
        case let .assertionFailed(message):
            return message
        }
    }
}
