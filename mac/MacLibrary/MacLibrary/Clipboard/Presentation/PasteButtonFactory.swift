//
//  PasteButtonFactory.swift
//  MacLibrary
//

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Builds a system paste button wired to a loader.
///
/// - Important: The macOS `PasteButton` does **not** validate or invalidate itself the way its
///   iOS counterpart does. It stays enabled whether or not the pasteboard holds an accepted
///   type, and the load simply reports that nothing matched (RK-16).
@MainActor
enum PasteButtonFactory {

    private static let TAG = "PasteButtonFactory"

    /// Adapts an `NSItemProvider` to the loader's source protocol.
    ///
    /// `NSItemProvider` is not `Sendable`, so the adapter is the boundary: the loader never
    /// sees the AppKit type, and this wrapper confines it to the main actor.
    struct ItemProviderSource: ClipboardPasteLoader.Source, @unchecked Sendable {
        let provider: NSItemProvider

        func conforms(to identifier: String) async -> Bool {
            provider.hasItemConformingToTypeIdentifier(identifier)
        }

        func loadData(for identifier: String) async throws -> Data {
            // The returned Progress is kept and cancelled, and the continuation is resumed
            // exactly once through a gate. Without this a provider that never calls back would
            // leave the task alive for the life of the process, and cancelling the load would
            // not actually stop the work underneath it.
            let gate = LoadGate()
            let progress = ProgressBox()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    gate.attach(continuation)
                    progress.install(provider.loadDataRepresentation(
                        forTypeIdentifier: identifier
                    ) { data, error in
                        if let data {
                            gate.finish(.success(data))
                        } else {
                            gate.finish(.failure(error ?? ClipboardError.pasteLoadFailed("no data")))
                        }
                    })
                }
            } onCancel: {
                progress.cancel()
                gate.finish(.failure(CancellationError()))
            }
        }
    }

    /// Creates the button and the view that owns its lifetime.
    ///
    /// - Returns: The container view. Releasing it cancels any load in progress.
    /// - Throws: ``ClipboardError/invalidTypeIdentifier(_:)`` for an empty or malformed
    ///   accepted type, and ``ClipboardError/invalidConfiguration(_:)`` for a timeout outside
    ///   `0 < timeout <= 300`.
    static func makePasteButton(acceptedTypes: [String],
                                timeout: TimeInterval,
                                validator: any ClipboardTypeIdentifierValidating,
                                register: (ClipboardPasteLoader) -> ClipboardPasteHandle,
                                cancel: @escaping @MainActor (ClipboardPasteHandle) -> Void,
                                onPaste: @escaping @MainActor (ClipboardPasteResult) -> Void)
    throws -> NSView {
        Log.d(TAG, "[makePasteButton] acceptedTypes: \(ClipboardLog.types(acceptedTypes)), "
              + "timeout: \(timeout)")
        let loader = try ClipboardPasteLoader(acceptedTypes: acceptedTypes,
                                              timeout: timeout,
                                              validator: validator,
                                              onPaste: onPaste)
        let handle = register(loader)
        let contentTypes = acceptedTypes.compactMap { UTType($0) }
        let button = PasteButton(supportedContentTypes: contentTypes) { providers in
            loader.load(from: providers.map { ItemProviderSource(provider: $0) })
        }
        return ClipboardPasteContainerView(handle: handle,
                                           content: NSHostingView(rootView: button),
                                           onCancel: cancel)
    }
}

/// Holds the `Progress` an item provider returns so a cancellation handler can reach it.
///
/// `nonisolated` and lock guarded because `onCancel` runs synchronously outside any actor.
///
/// The box remembers that cancellation happened, not just the `Progress`. The provider returns
/// its `Progress` only after the load has started, so cancellation can arrive while the box is
/// still empty. A box that only stored the value would let that `Progress` be installed
/// afterwards and never cancelled: the caller returns either way, but the provider keeps
/// reading in the background for a paste nobody is waiting for.
private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Progress?
    private var isCancelled = false

    /// Stores the provider's `Progress`, cancelling it immediately if cancellation already
    /// happened.
    func install(_ progress: Progress?) {
        let cancelNow: Bool = lock.withLock {
            stored = progress
            return isCancelled
        }
        if cancelNow { progress?.cancel() }
    }

    /// Cancels the stored `Progress`, and any that arrives later.
    func cancel() {
        let progress: Progress? = lock.withLock {
            isCancelled = true
            return stored
        }
        progress?.cancel()
    }
}

/// Resumes a continuation exactly once, whichever of the provider callback and the
/// cancellation handler gets there first.
///
/// Cancellation can arrive before the continuation exists, so an outcome claimed early is held
/// until ``attach(_:)`` supplies somewhere to deliver it.
private final class LoadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var pending: Result<Data, any Error>?
    private var isDone = false

    func attach(_ continuation: CheckedContinuation<Data, any Error>) {
        let immediate: Result<Data, any Error>? = lock.withLock {
            guard !isDone else { return nil }
            if let pending {
                isDone = true
                return pending
            }
            self.continuation = continuation
            return nil
        }
        if let immediate { continuation.resume(with: immediate) }
    }

    func finish(_ outcome: Result<Data, any Error>) {
        let resume: CheckedContinuation<Data, any Error>? = lock.withLock {
            guard !isDone else { return nil }
            guard let continuation else {
                pending = outcome
                return nil
            }
            isDone = true
            self.continuation = nil
            return continuation
        }
        resume?.resume(with: outcome)
    }
}
