//
//  FFmpegRunner.swift
//  PJTool
//
//  Created by Codex on 2026/5/12.
//

import Foundation

final class FFmpegRunner {
    func run(
        command: FFmpegCommand,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> FFmpegExecutionResult {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let lock = NSLock()
        var stdoutText = ""
        var stderrText = ""
        var progressLineBuffer = ""

        func appendStdout(_ text: String) {
            lock.lock()
            stdoutText.append(text)
            lock.unlock()
        }

        func appendStderr(_ text: String) {
            lock.lock()
            stderrText.append(text)
            lock.unlock()
        }

        func parseProgressIfNeeded(_ text: String) {
            guard let expected = command.expectedDurationSeconds, expected > 0 else { return }
            progressLineBuffer.append(text)
            while let index = progressLineBuffer.firstIndex(of: "\n") {
                let line = String(progressLineBuffer[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
                progressLineBuffer.removeSubrange(progressLineBuffer.startIndex...index)
                if let msValue = line.split(separator: "=", maxSplits: 1).last,
                   line.hasPrefix("out_time_ms="),
                   let ms = Double(msValue) {
                    let ratio = max(0, min(1, (ms / 1_000_000.0) / expected))
                    onProgress?(ratio)
                }
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            appendStdout(text)
            parseProgressIfNeeded(text)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            appendStderr(String(decoding: data, as: UTF8.self))
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let stdoutTail = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                if !stdoutTail.isEmpty {
                    appendStdout(String(decoding: stdoutTail, as: UTF8.self))
                }
                let stderrTail = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                if !stderrTail.isEmpty {
                    appendStderr(String(decoding: stderrTail, as: UTF8.self))
                }

                lock.lock()
                let out = stdoutText
                let err = stderrText
                lock.unlock()

                let result = FFmpegExecutionResult(
                    stdout: out,
                    stderr: err,
                    exitCode: process.terminationStatus
                )

                if process.terminationStatus == 0 {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: FFmpegRunnerError.commandFailed(result))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FFmpegRunnerError.launchFailed(error.localizedDescription))
            }
        }
    }
}

extension FFmpegRunner {
    enum FFmpegRunnerError: LocalizedError {
        case launchFailed(String)
        case commandFailed(FFmpegExecutionResult)

        var errorDescription: String? {
            switch self {
            case let .launchFailed(reason):
                return L10n.f("fmt.ffmpeg.launch_failed", reason)
            case let .commandFailed(result):
                let message = result.stderr.isEmpty ? result.stdout : result.stderr
                return L10n.f("fmt.ffmpeg.command_failed", result.exitCode, message)
            }
        }
    }
}
