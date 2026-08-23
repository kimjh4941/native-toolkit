//
//  PasteItemProviderLoader.swift
//  IosLibrary
//

import Foundation
import UIKit

/// Aggregates loading an explicit `[NSItemProvider]` array handed over by
/// `UIResponder.paste(itemProviders:)`.
///
/// Lives in Presentation because `NSItemProvider` must not appear in an Application Port. The
/// per-provider work itself is delegated to `ClipboardProviderLoadExecutor`, so this path gets the
/// same exactly-once, timeout, cancellation, size-limit, and temporary-file cleanup semantics as
/// `loadItem` (P-11).
///
/// The caller's `acceptedTypes` constrain which representation is taken from each provider
/// (priority: text > url > image > file), so a provider advertising several types never yields a
/// kind the caller did not accept.
@MainActor
final class PasteItemProviderLoader {
    struct AggregateResult {
        let items: [ClipboardLoadedItem]
        let failures: [ClipboardError]
        /// `true` when the session was superseded or torn down by the caller. The internal
        /// completion still fires exactly once (D-4 / U-84), but the owning view must not turn a
        /// cancelled result into a UI callback (U-90).
        let isCancelled: Bool

        init(items: [ClipboardLoadedItem], failures: [ClipboardError], isCancelled: Bool = false) {
            self.items = items
            self.failures = failures
            self.isCancelled = isCancelled
        }
    }

    private final class Session {
        var results: [Result<ClipboardLoadedItem, ClipboardError>?]
        var handles: [ClipboardProviderLoadHandle?]
        var remaining: Int
        var isCancelled = false
        private var completion: ((AggregateResult) -> Void)?

        init(count: Int, completion: @escaping (AggregateResult) -> Void) {
            self.results = Array(repeating: nil, count: count)
            self.handles = Array(repeating: nil, count: count)
            self.remaining = count
            self.completion = completion
        }

        /// Delivers the aggregate result exactly once; every later attempt is dropped.
        func deliver(_ result: AggregateResult) {
            guard let completion else { return }
            self.completion = nil
            completion(result)
        }
    }

    private let TAG = "PasteItemProviderLoader"
    private let executor: ClipboardProviderLoadExecutor
    private let fileStore: ClipboardTemporaryFileStore
    private var currentSession: Session?

    init(
        executor: ClipboardProviderLoadExecutor? = nil,
        fileStore: ClipboardTemporaryFileStore? = nil,
        imageCoder: ClipboardImageCoder? = nil,
        limits: ClipboardLimits = .default,
        timeouts: ClipboardTimeouts = .default
    ) {
        let resolvedFileStore = fileStore ?? ClipboardTemporaryFileStore()
        self.fileStore = resolvedFileStore
        self.executor = executor ?? ClipboardProviderLoadExecutor(
            fileStore: resolvedFileStore, imageCoder: imageCoder, limits: limits, timeouts: timeouts
        )
    }

    /// Cancels any pending session when the loader — and therefore the view that owns it — goes
    /// away (D-16). Without this, a provider load that completes after the owning view is released
    /// would leave its temporary file on disk: the aggregation closure holds the loader weakly, so
    /// nobody would be left to discard the produced file. `isolated deinit` is required because
    /// `cancelAll` touches main-actor state.
    isolated deinit {
        Log.d(TAG, "[deinit] hasPendingSession: \(currentSession != nil)")
        cancelAll()
    }

    /// Loads every provider, preserving input order in `items`. A new call supersedes any pending
    /// session, whose completion receives a cancelled result exactly once (see `cancelAll`).
    func load(
        providers: [NSItemProvider],
        acceptedTypes: [String],
        completion: @escaping (AggregateResult) -> Void
    ) {
        Log.d(TAG, "[load] providerCount: \(providers.count), acceptedTypeCount: \(acceptedTypes.count)")
        cancelAll()
        guard !providers.isEmpty else {
            // U-83: an empty provider array is neither a success nor a per-provider failure. The
            // owning view maps "no items, no failures" onto `onPasteFailure(.noMatchingItem)`.
            completion(AggregateResult(items: [], failures: []))
            return
        }

        let session = Session(count: providers.count, completion: completion)
        currentSession = session

        for (index, provider) in providers.enumerated() {
            guard let request = ClipboardProviderLoadExecutor.requestKind(
                for: provider, acceptedTypes: acceptedTypes
            ) else {
                finishOne(session: session, index: index, outcome: .failure(.noMatchingItem))
                continue
            }
            session.handles[index] = executor.start(request, from: provider) { [weak self] result in
                self?.finishOne(session: session, index: index, outcome: result)
            }
        }
    }

    /// Cancels the pending session, if any. The internal completion still fires **exactly once**
    /// with `.cancelled` (D-4 / U-84); suppressing the *UI* callback (U-90) is the owning view's
    /// job, driven by `AggregateResult.isCancelled`. Any file already produced is removed.
    func cancelAll() {
        Log.d(TAG, "[cancelAll] hasPendingSession: \(currentSession != nil)")
        guard let session = currentSession else { return }
        session.isCancelled = true
        currentSession = nil
        for handle in session.handles {
            handle?.cancel()
        }
        discardUndeliveredFiles(in: session)
        session.deliver(AggregateResult(items: [], failures: [.cancelled], isCancelled: true))
    }

    // MARK: - Private

    private func finishOne(
        session: Session,
        index: Int,
        outcome: Result<ClipboardLoadedItem, ClipboardError>
    ) {
        guard !session.isCancelled, currentSession === session else {
            // Late result for a superseded/cancelled session: discard, including any file.
            if case .success(.file(let url)) = outcome {
                fileStore.discard(url)
            }
            return
        }
        guard session.results[index] == nil else { return }
        session.results[index] = outcome
        session.remaining -= 1
        guard session.remaining == 0 else { return }
        currentSession = nil

        var items: [ClipboardLoadedItem] = []
        var failures: [ClipboardError] = []
        for result in session.results {
            switch result {
            case .success(let item): items.append(item)
            case .failure(let error): failures.append(error)
            case .none: break
            }
        }
        session.deliver(AggregateResult(items: items, failures: failures))
    }

    private func discardUndeliveredFiles(in session: Session) {
        for result in session.results {
            if case .success(.file(let url)) = result {
                fileStore.discard(url)
            }
        }
    }
}
