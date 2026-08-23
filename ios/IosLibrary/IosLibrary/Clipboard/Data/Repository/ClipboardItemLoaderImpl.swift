//
//  ClipboardItemLoaderImpl.swift
//  IosLibrary
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// `NSItemProvider`-backed implementation of `ClipboardItemLoader`.
///
/// Implements the exactly-once delivery contract: every request is registered in `requests` at
/// issuance time (before a provider is even searched for), so `cancelAll()` / a token's
/// `cancel()` catch it even on the immediate-failure path. The actual provider load — including
/// its timeout, size limits, and temporary-file cleanup — is delegated to
/// `ClipboardProviderLoadExecutor`, which is shared with the `UIPasteControl` path so both behave
/// identically.
@MainActor
final class ClipboardItemLoaderImpl: ClipboardItemLoader {
    private final class Request {
        let completion: (Result<ClipboardLoadedItem, ClipboardError>) -> Void
        var handle: ClipboardProviderLoadHandle?
        init(completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void) {
            self.completion = completion
        }
    }

    private let TAG = "ClipboardItemLoaderImpl"
    private let resolver: PasteboardResolver
    private let executor: ClipboardProviderLoadExecutor
    private var nextID = 0
    private var requests: [Int: Request] = [:]

    init(
        resolver: PasteboardResolver? = nil,
        executor: ClipboardProviderLoadExecutor? = nil,
        fileStore: ClipboardTemporaryFileStore? = nil,
        imageCoder: ClipboardImageCoder? = nil,
        limits: ClipboardLimits = .default,
        timeouts: ClipboardTimeouts = .default
    ) {
        self.resolver = resolver ?? PasteboardResolver()
        self.executor = executor ?? ClipboardProviderLoadExecutor(
            fileStore: fileStore, imageCoder: imageCoder, limits: limits, timeouts: timeouts
        )
    }

    @discardableResult
    func load(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) -> any ClipboardLoadToken {
        Log.d(TAG, "[load] scope: \(scope.redactedDescription)")
        let id = nextID
        nextID += 1
        let state = Request(completion: completion)
        requests[id] = state
        let token = ClipboardLoadTokenImpl(loader: self, id: id)

        let pasteboard: UIPasteboard
        do {
            pasteboard = try resolver.resolve(scope)
        } catch let error as ClipboardError {
            scheduleImmediateFailure(id: id, error: error)
            return token
        } catch {
            scheduleImmediateFailure(id: id, error: .unknown(ClipboardFailureDetail(systemError: error)))
            return token
        }

        guard let provider = Self.firstMatchingProvider(request, in: pasteboard.itemProviders) else {
            scheduleImmediateFailure(id: id, error: .noMatchingItem)
            return token
        }

        state.handle = executor.start(request, from: provider) { [weak self] result in
            self?.finish(id: id, outcome: result)
        }
        return token
    }

    func cancelAll() {
        Log.d(TAG, "[cancelAll]")
        let pending = requests
        requests.removeAll()
        for (_, state) in pending {
            deliverCancellation(state)
        }
    }

    func cancel(id: Int) {
        Log.d(TAG, "[cancel] id: \(id)")
        guard let state = requests.removeValue(forKey: id) else { return }
        deliverCancellation(state)
    }

    isolated deinit {
        cancelAll()
    }

    // MARK: - Private

    private func deliverCancellation(_ state: Request) {
        if let handle = state.handle {
            // The executor's gate turns this into exactly one `.cancelled` delivery, which routes
            // back through `finish(id:outcome:)` — but the id is already removed, so deliver here.
            handle.cancel()
            state.completion(.failure(.cancelled))
        } else {
            // No provider load was ever started (immediate-failure or not-yet-started path).
            state.completion(.failure(.cancelled))
        }
    }

    private static func firstMatchingProvider(
        _ request: ClipboardLoadRequest,
        in providers: [NSItemProvider]
    ) -> NSItemProvider? {
        switch request {
        case .text:
            return providers.first { $0.canLoadObject(ofClass: NSString.self) }
        case .url:
            return providers.first { $0.canLoadObject(ofClass: NSURL.self) }
        case .image:
            return providers.first { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        case .file(let utType):
            return providers.first { $0.hasItemConformingToTypeIdentifier(utType) }
        }
    }

    /// Delivers an immediate failure without executing it synchronously, so that a `cancelAll()`
    /// issued right after `load` still wins the race and reports `.cancelled` exactly once.
    private func scheduleImmediateFailure(id: Int, error: ClipboardError) {
        Task { @MainActor [weak self] in
            self?.finish(id: id, outcome: .failure(error))
        }
    }

    /// The single gate resolving success / error / cancellation / timeout exactly once.
    private func finish(id: Int, outcome: Result<ClipboardLoadedItem, ClipboardError>) {
        guard let state = requests.removeValue(forKey: id) else { return }
        state.completion(outcome)
    }
}

/// Cancellation handle returned by `ClipboardItemLoaderImpl.load`.
@MainActor
final class ClipboardLoadTokenImpl: ClipboardLoadToken {
    private weak var loader: ClipboardItemLoaderImpl?
    private let id: Int

    init(loader: ClipboardItemLoaderImpl, id: Int) {
        self.loader = loader
        self.id = id
    }

    func cancel() {
        loader?.cancel(id: id)
    }
}
