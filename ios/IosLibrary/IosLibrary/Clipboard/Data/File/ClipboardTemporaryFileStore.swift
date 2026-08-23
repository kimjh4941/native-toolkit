//
//  ClipboardTemporaryFileStore.swift
//  IosLibrary
//

import Foundation

/// Manages request-scoped temporary directories under
/// `<NSTemporaryDirectory()>/IosLibraryClipboard/<sessionID>/<requestID>/<UUID>.<ext>`.
///
/// Never trusts an externally-suggested file name: only its extension is used, filtered through
/// an allow-list (falling back to `bin`), so the generated destination cannot escape the
/// freshly-created request directory. Startup cleanup runs once per process and only removes
/// **other** sessions' directories older than 24 hours, never the active session.
final class ClipboardTemporaryFileStore: @unchecked Sendable {
    private static let allowedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "webp", "txt", "pdf"
    ]
    private static let rootDirectoryName = "IosLibraryClipboard"
    private static let startupCleanupLock = NSLock()
    // Guarded exclusively by `startupCleanupLock`; safe to opt out of the compiler's global
    // shared mutable state check.
    nonisolated(unsafe) private static var didRunStartupCleanup = false

    private let TAG = "ClipboardTemporaryFileStore"
    private let fileManager: FileManager
    let sessionID: String
    let rootDirectory: URL
    let sessionDirectory: URL

    init(fileManager: FileManager = .default, sessionID: String = UUID().uuidString) {
        self.fileManager = fileManager
        self.sessionID = sessionID
        self.rootDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(Self.rootDirectoryName, isDirectory: true)
        self.sessionDirectory = rootDirectory.appendingPathComponent(sessionID, isDirectory: true)
        Log.d(TAG, "[init] sessionID: \(sessionID)")
        Self.runStartupCleanupOnce(fileManager: fileManager, rootDirectory: rootDirectory, activeSessionID: sessionID)
    }

    /// Copies `sourceURL` into a new request-scoped directory. `suggestedName` is used only for
    /// its extension (filtered through the allow-list); the file name itself is always a UUID.
    /// - Throws: `ClipboardError.fileCopyFailed` on any failure; the partial request directory is
    ///   removed before rethrowing.
    func store(sourceURL: URL, suggestedName: String?) throws -> URL {
        let requestDirectory = sessionDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileName = Self.safeFileName(sourceURL: sourceURL, suggestedName: suggestedName)
        let destination = requestDirectory.appendingPathComponent(fileName)
        guard Self.isContained(destination, in: requestDirectory) else {
            throw ClipboardError.fileCopyFailed(
                ClipboardFailureDetail(domain: "ClipboardTemporaryFileStore", code: -1,
                                       debugMessage: "destination escaped request directory")
            )
        }
        do {
            try fileManager.createDirectory(at: requestDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: requestDirectory)
            throw ClipboardError.fileCopyFailed(ClipboardFailureDetail(systemError: error))
        }
    }

    /// Deletes the request-scoped directory containing `fileURL` (i.e. its parent directory).
    /// Used to discard undelivered results on cancellation, timeout, or failure.
    func discard(_ fileURL: URL) {
        let requestDirectory = fileURL.deletingLastPathComponent()
        try? fileManager.removeItem(at: requestDirectory)
    }

    static func safeFileName(sourceURL: URL, suggestedName: String?) -> String {
        let candidates = [sourceURL.pathExtension, (suggestedName as NSString?)?.pathExtension ?? ""]
        let ext = candidates
            .map { $0.lowercased() }
            .first { allowedExtensions.contains($0) } ?? "bin"
        return "\(UUID().uuidString).\(ext)"
    }

    static func isContained(_ destination: URL, in directory: URL) -> Bool {
        let base = directory.standardizedFileURL.path
        let baseWithSlash = base.hasSuffix("/") ? base : base + "/"
        return destination.standardizedFileURL.path.hasPrefix(baseWithSlash)
    }

    private static func runStartupCleanupOnce(fileManager: FileManager, rootDirectory: URL, activeSessionID: String) {
        startupCleanupLock.lock()
        defer { startupCleanupLock.unlock() }
        guard !didRunStartupCleanup else { return }
        didRunStartupCleanup = true
        guard let sessionDirs = try? fileManager.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for dir in sessionDirs where dir.lastPathComponent != activeSessionID {
            guard let values = try? dir.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: dir)
        }
    }

    /// Test-only hook to allow verifying cleanup behavior across simulated "process" boundaries.
    static func resetStartupCleanupStateForTesting() {
        startupCleanupLock.lock()
        didRunStartupCleanup = false
        startupCleanupLock.unlock()
    }
}
