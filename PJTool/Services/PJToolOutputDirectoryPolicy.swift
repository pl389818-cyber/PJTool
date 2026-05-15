//
//  PJToolOutputDirectoryPolicy.swift
//  PJTool
//
//  Created by Codex on 2026/5/15.
//

import Foundation

struct PJToolOutputDirectoryPolicy {
    private static let appFolderName = "PJTool"
    private static let recordingsFolderName = "Recordings"
    private static let videoCutsFolderName = "VideoCuts"
    private static let audioExtractFolderName = "AudioExtract"
    private static let screenDrawFolderName = "ScreenDraw"

    private static let videoCutsLastDirectoryDefaultsKey = "pjtool.output.video_cuts.last_directory"
    private static let screenDrawLastDirectoryDefaultsKey = "pjtool.output.screen_draw.last_directory"

    static func recordingsDirectory() throws -> URL {
        let directory = moviesRootDirectory().appendingPathComponent(recordingsFolderName, isDirectory: true)
        try ensureDirectoryExists(directory)
        return directory
    }

    static func defaultAudioExtractRootDirectory() -> URL {
        moviesRootDirectory().appendingPathComponent(audioExtractFolderName, isDirectory: true)
    }

    static func preferredVideoCutsDirectory() -> URL {
        if let restored = restoredDirectory(forKey: videoCutsLastDirectoryDefaultsKey) {
            return restored
        }
        return defaultVideoCutsDirectory()
    }

    static func prepareVideoCutsDirectory() throws -> URL {
        let directory = preferredVideoCutsDirectory()
        try ensureDirectoryExists(directory)
        return directory
    }

    static func rememberVideoCutsDirectory(from exportedFileURL: URL) {
        rememberDirectory(forKey: videoCutsLastDirectoryDefaultsKey, from: exportedFileURL)
    }

    static func preferredScreenDrawDirectory() -> URL {
        if let restored = restoredDirectory(forKey: screenDrawLastDirectoryDefaultsKey) {
            return restored
        }
        return defaultScreenDrawDirectory()
    }

    static func prepareScreenDrawDirectory() throws -> URL {
        let directory = preferredScreenDrawDirectory()
        try ensureDirectoryExists(directory)
        return directory
    }

    static func rememberScreenDrawDirectory(from exportedFileURL: URL) {
        rememberDirectory(forKey: screenDrawLastDirectoryDefaultsKey, from: exportedFileURL)
    }

    private static func defaultVideoCutsDirectory() -> URL {
        moviesRootDirectory().appendingPathComponent(videoCutsFolderName, isDirectory: true)
    }

    private static func defaultScreenDrawDirectory() -> URL {
        picturesRootDirectory().appendingPathComponent(screenDrawFolderName, isDirectory: true)
    }

    private static func moviesRootDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent(appFolderName, isDirectory: true)
    }

    private static func picturesRootDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent(appFolderName, isDirectory: true)
    }

    private static func restoredDirectory(forKey key: String) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func rememberDirectory(forKey key: String, from exportedFileURL: URL) {
        let directory = exportedFileURL.deletingLastPathComponent().standardizedFileURL
        UserDefaults.standard.set(directory.path, forKey: key)
    }

    private static func ensureDirectoryExists(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
