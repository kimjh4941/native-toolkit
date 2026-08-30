//
//  FilePromiseSnapshotting.swift
//  MacLibrary
//

import Foundation

/// Copies a promised file's source into app-owned staging.
///
/// A file promise is fulfilled long after it is registered, so the bytes are captured at
/// registration time and the promise then writes from the copy. That makes the promise
/// survive the original being moved or deleted.
///
/// Implementations keep the blocking file I/O off the main actor.
public protocol FilePromiseSnapshotting: Sendable {
    /// Copies `source` into `stagingRoot` and returns the URL of the copy.
    ///
    /// - Throws: `CancellationError` when the task is cancelled, or
    ///   ``ClipboardError/filePromiseWriteFailed(_:)`` when the copy fails. Either way any
    ///   partial copy is removed before throwing.
    func snapshot(from source: URL, into stagingRoot: URL) async throws -> URL

    /// Removes a completed staging directory. Idempotent; a missing directory is success.
    ///
    /// Used when the task is cancelled after the copy already finished.
    func discard(stagingURL: URL) async
}
