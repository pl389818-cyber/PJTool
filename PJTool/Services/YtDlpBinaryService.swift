//
//  YtDlpBinaryService.swift
//  PJTool
//
//  Created by Codex on 2026/5/14.
//

import Foundation

struct YtDlpBinaryService {
    private let fileManager = FileManager.default

    private static let bundledOnedirDirectoryName = "yt-dlp_macos.bundle"
    private static let executableName = "yt-dlp_macos"

    func ensureReady() throws -> YtDlpLaunchCommand {
        var validationErrors: [String] = []

        if let bundledOnedir = bundledOnedirExecutableURL() {
            if let command = validateCandidate(at: bundledOnedir, label: "bundled-standalone", errors: &validationErrors) {
                return command
            }
        } else {
            validationErrors.append("bundled-standalone: \(YtDlpError.missingBundledBinary(Self.bundledOnedirDirectoryName).localizedDescription)")
        }

        validationErrors.append("bundled-script: disabled; PJTool sandbox must not launch /usr/bin/env python3 yt-dlp")
        validationErrors.append("runtime-install: disabled; PJTool sandbox must not unzip/install yt-dlp at runtime")
        throw YtDlpError.binaryValidationFailed("yt-dlp", validationErrors.joined(separator: " | "))
    }

    private func bundledOnedirExecutableURL() -> URL? {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(
                resourceURL
                    .appendingPathComponent(Self.bundledOnedirDirectoryName, isDirectory: true)
                    .appendingPathComponent(Self.executableName)
            )
        }
        if let direct = Bundle.main.url(
            forResource: Self.executableName,
            withExtension: nil,
            subdirectory: Self.bundledOnedirDirectoryName
        ) {
            candidates.append(direct)
        }
        if let legacy = Bundle.main.url(
            forResource: Self.executableName,
            withExtension: nil,
            subdirectory: "ThirdParty/yt-dlp/arm64/\(Self.bundledOnedirDirectoryName)"
        ) {
            candidates.append(legacy)
        }

        var visited = Set<String>()
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath()
            let path = resolved.path
            guard visited.insert(path).inserted else { continue }
            if fileManager.fileExists(atPath: path) {
                return resolved
            }
        }

        return nil
    }

    private func validateCandidate(
        at url: URL,
        label: String,
        errors: inout [String]
    ) -> YtDlpLaunchCommand? {
        do {
            let command = try buildLaunchCommand(for: url)
            try validateTool(with: command)
            return command
        } catch {
            let debug = collectDebugState(for: url)
            errors.append("\(label)=\(url.path): \(error.localizedDescription) [\(debug)]")
            return nil
        }
    }

    private func buildLaunchCommand(for candidate: URL) throws -> YtDlpLaunchCommand {
        let path = candidate.standardizedFileURL.path
        guard fileManager.fileExists(atPath: path) else {
            throw YtDlpError.missingBundledBinary(candidate.lastPathComponent)
        }
        guard candidate.lastPathComponent == Self.executableName else {
            throw YtDlpError.binaryValidationFailed(
                candidate.lastPathComponent,
                "Only bundled standalone \(Self.executableName) is supported."
            )
        }

        return YtDlpLaunchCommand(
            executableURL: URL(fileURLWithPath: path),
            workingDirectoryURL: URL(fileURLWithPath: path).deletingLastPathComponent(),
            environment: buildEnvironment(extraPath: URL(fileURLWithPath: path).deletingLastPathComponent().path),
            prependArguments: [],
            candidatePath: path
        )
    }

    private func buildEnvironment(extraPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        let existingPath = environment["PATH"] ?? defaultPath
        environment["PATH"] = ([extraPath, existingPath, defaultPath])
            .flatMap { $0.split(separator: ":").map(String.init) }
            .reduce(into: [String]()) { partial, item in
                if !partial.contains(item) {
                    partial.append(item)
                }
            }
            .joined(separator: ":")
        environment["PYTHONIOENCODING"] = "utf-8"
        return environment
    }

    private func collectDebugState(for candidate: URL) -> String {
        let path = candidate.path
        let resolved = candidate.resolvingSymlinksInPath().path
        let exists = fileManager.fileExists(atPath: path)
        let resolvedExists = fileManager.fileExists(atPath: resolved)
        let executable = fileManager.isExecutableFile(atPath: path)
        let shebang = readShebang(from: path) ?? "<none>"
        return [
            "path=\(path)",
            "exists=\(exists)",
            "exec=\(executable)",
            "resolved=\(resolved)",
            "resolvedExists=\(resolvedExists)",
            "shebang=\(shebang)",
        ].joined(separator: ",")
    }

    private func readShebang(from path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 256)
        guard let newlineIndex = data.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) else { return nil }
        let firstLineData = data.prefix(upTo: newlineIndex)
        guard let line = String(data: firstLineData, encoding: .utf8) else { return nil }
        guard line.hasPrefix("#!") else { return nil }
        let shebang = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        return shebang.isEmpty ? nil : shebang
    }

    private func validateTool(with command: YtDlpLaunchCommand) throws {
        let process = Process()
        process.executableURL = command.executableURL
        process.currentDirectoryURL = command.workingDirectoryURL
        process.environment = command.environment
        process.arguments = command.makeArguments(["--version"])
        let sink = Pipe()
        process.standardOutput = sink
        process.standardError = sink
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw YtDlpError.binaryValidationFailed(command.candidatePath, error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let output = String(
                decoding: sink.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            let clipped = output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .suffix(8)
                .joined(separator: " | ")
            let reason = clipped.isEmpty ? "exit=\(process.terminationStatus)" : "exit=\(process.terminationStatus): \(clipped)"
            throw YtDlpError.binaryValidationFailed(command.candidatePath, reason)
        }
    }
}

extension YtDlpBinaryService {
    enum YtDlpError: LocalizedError {
        case installPathUnavailable
        case missingBundledBinary(String)
        case installCopyFailed(String, String)
        case binaryValidationFailed(String, String)

        var errorDescription: String? {
            switch self {
            case .installPathUnavailable:
                return "yt-dlp install path is unavailable."
            case let .missingBundledBinary(name):
                return "Missing bundled yt-dlp file: \(name)."
            case let .installCopyFailed(name, reason):
                return "Failed to install yt-dlp (\(name)): \(reason)."
            case let .binaryValidationFailed(name, reason):
                return "yt-dlp validation failed (\(name)): \(reason)."
            }
        }
    }
}
