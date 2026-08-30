//
//  FilePromiseDelegate.swift
//  MacLibrary
//

import AppKit
import Foundation

/// Fulfils one registered file promise.
///
/// The type is `nonisolated`: `filePromiseProvider(_:writePromiseTo:completionHandler:)` is
/// declared `NS_SWIFT_NONISOLATED`, so a main actor isolated delegate cannot conform. All
/// mutable lifetime bookkeeping therefore lives in ``FilePromiseLifecycleState``, which owns
/// its own lock, and this type holds only immutable values.
///
/// - Important: `NSFilePromiseProvider.delegate` is `weak`. The coordinator holds the strong
///   reference; nothing here keeps the delegate alive (RK-21).
final class FilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {

    private let TAG = "FilePromiseDelegate"

    private let fileName: String
    private let source: FilePromiseSource
    private let state: FilePromiseLifecycleState
    private let queue: OperationQueue
    /// Called on the main actor when a write finishes and that completion is the one that
    /// makes a pending release possible.
    private let onReleasable: @Sendable (UInt64) -> Void

    init(fileName: String,
         source: FilePromiseSource,
         state: FilePromiseLifecycleState,
         queue: OperationQueue,
         onReleasable: @escaping @Sendable (UInt64) -> Void) {
        Log.d("FilePromiseDelegate", "[init] fileName: \(ClipboardLog.path(fileName))")
        self.fileName = fileName
        self.source = source
        self.state = state
        self.queue = queue
        self.onReleasable = onReleasable
        super.init()
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String {
        Log.d(TAG, "[fileNameForType] fileType: \(fileType)")
        // The name was validated at registration, so it is used as-is.
        return fileName
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        Log.d(TAG, "[operationQueue]")
        // Serial. Two concurrent writes would re-enter the same writer closure or read the
        // same staging directory while it is being copied (R2-H4).
        return queue
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                             writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        Log.d(TAG, "[writePromiseTo] url: \(ClipboardLog.url(url))")
        // Claim the write before doing anything, so a release requested concurrently cannot
        // tear the promise down underneath it.
        guard state.beginWrite() == .proceed else {
            // Already released. The promise is still advertised on the pasteboard, so a drag
            // can still ask for it; failing the write is the only honest answer (R3-H2).
            completionHandler(ClipboardError.filePromiseWriteFailed("promise already released"))
            return
        }
        var failure: Error?
        do {
            switch source {
            case .writer(let write):
                try write(url)
            case .snapshot:
                // The staging copy is the source of truth. The original path is deliberately
                // not consulted: it may have been moved or deleted since registration (R5-H2).
                guard let staging = state.stagingURLForFulfilment() else {
                    throw ClipboardError.filePromiseWriteFailed("staging directory is missing")
                }
                try copy(from: staging, to: url)
            }
        } catch let error as ClipboardError {
            failure = error
        } catch {
            failure = ClipboardError.filePromiseWriteFailed(String(describing: error))
        }
        // Exactly once per request. There is deliberately no guard that fires only once for
        // the whole provider: the system may ask for the same promise more than once (RK-21).
        if let generation = state.endWrite() {
            onReleasable(generation)
        }
        completionHandler(failure)
    }

    private func copy(from source: URL, to destination: URL) throws {
        Log.d(TAG, "[copy] from: \(ClipboardLog.url(source)), to: \(ClipboardLog.url(destination)))")
        let fileManager = FileManager()
        // The receiving app creates the destination path for us in some flows, so an existing
        // file is replaced rather than treated as an error.
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        // copyItem handles a directory recursively, which is what a promised folder needs.
        try fileManager.copyItem(at: source, to: destination)
    }
}
