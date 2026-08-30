//
//  FilePromiseSnapshotter.swift
//  MacLibrary
//

import Foundation

/// Copies a promise's source into app-owned staging on a dedicated queue.
///
/// `FileManager` copies are blocking and unbounded in size, so they must not run on the main
/// actor. They are also not cooperatively cancellable, which shapes the contract here:
/// cancellation is checked before starting and the caller checks again afterwards, and a copy
/// that finished after cancellation is removed with ``discard(stagingURL:)``.
///
/// The queue is serial so that concurrent registrations cannot interleave large copies.
///
/// - Note: `FileManager` is not `Sendable`, so this type cannot hold one. A fresh instance
///   is built inside the queue for each operation, which also keeps every instance confined
///   to a single queue. Tests inject a different factory rather than a shared object.
public final class FilePromiseSnapshotter: FilePromiseSnapshotting {

    private let TAG = "FilePromiseSnapshotter"

    private let queue: DispatchQueue
    private let makeFileManager: @Sendable () -> FileManager

    /// - Parameter makeFileManager: Builds the file manager used inside the queue. Injected
    ///   by tests; the default creates a fresh instance per operation.
    public init(makeFileManager: @escaping @Sendable () -> FileManager = { FileManager() }) {
        Log.d("FilePromiseSnapshotter", "[init]")
        self.makeFileManager = makeFileManager
        self.queue = DispatchQueue(label: "com.nativetoolkit.clipboard.snapshot")
    }

    /// Copies `source` into `stagingRoot` off the main actor, deleting a partial copy on failure or cancellation.
    public func snapshot(from source: URL, into stagingRoot: URL) async throws -> URL {
        Log.d(TAG, "[snapshot] from: \(ClipboardLog.url(source)), "
              + "into: \(ClipboardLog.url(stagingRoot))")
        try Task.checkCancellation()

        let destination = stagingRoot.appendingPathComponent(source.lastPathComponent)
        let makeFileManager = self.makeFileManager

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                let fileManager = makeFileManager()
                do {
                    // Start from a clean directory so a retry cannot merge with leftovers.
                    if fileManager.fileExists(atPath: stagingRoot.path) {
                        try fileManager.removeItem(at: stagingRoot)
                    }
                    try fileManager.createDirectory(at: stagingRoot,
                                                    withIntermediateDirectories: true)
                    // copyItem handles both files and directories.
                    try fileManager.copyItem(at: source, to: destination)
                    continuation.resume()
                } catch {
                    // Never leave a half written staging directory behind.
                    try? fileManager.removeItem(at: stagingRoot)
                    continuation.resume(
                        throwing: ClipboardError.filePromiseWriteFailed(error.localizedDescription))
                }
            }
        }

        do {
            try Task.checkCancellation()
        } catch {
            // The copy completed after cancellation; the caller never sees this staging.
            await discard(stagingURL: stagingRoot)
            throw error
        }
        return destination
    }

    /// Deletes a completed staging copy. Idempotent; a missing path is success.
    public func discard(stagingURL: URL) async {
        Log.d(TAG, "[discard] \(ClipboardLog.url(stagingURL))")
        let makeFileManager = self.makeFileManager
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                // Removing a directory that is already gone is success, not an error.
                try? makeFileManager().removeItem(at: stagingURL)
                continuation.resume()
            }
        }
    }
}
