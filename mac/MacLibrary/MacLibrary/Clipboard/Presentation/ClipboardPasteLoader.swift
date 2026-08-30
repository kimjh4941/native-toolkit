//
//  ClipboardPasteLoader.swift
//  MacLibrary
//

import Foundation
import UniformTypeIdentifiers

/// Loads the items behind a paste button into domain values.
///
/// `PasteButton` hands over `NSItemProvider`s, whose contents arrive asynchronously and one at
/// a time. This type turns that into a single result: providers load concurrently, one failure
/// does not cancel the others, and the whole thing is bounded by a timeout so a provider that
/// never answers cannot leave the caller waiting forever (H-8).
@MainActor
final class ClipboardPasteLoader {

    private let TAG = "ClipboardPasteLoader"

    /// What a provider can be asked for. `NSItemProvider` is not `Sendable`, so the loader is
    /// written against this instead: the AppKit type is adapted at the call site and the logic
    /// here stays testable without one.
    protocol Source: Sendable {
        /// Whether the source can supply the identifier.
        func conforms(to identifier: String) async -> Bool
        /// Bytes for the identifier.
        func loadData(for identifier: String) async throws -> Data
    }

    private let acceptedTypes: [String]
    private let timeout: TimeInterval
    private let onPaste: @MainActor (ClipboardPasteResult) -> Void

    /// Ensures `onPaste` runs once. The timeout and the last provider can finish at the same
    /// moment, and delivering twice would double-handle a paste (H-8).
    private var hasDelivered = false
    private var loadTask: Task<Void, Never>?

    /// - Throws: ``ClipboardError/invalidTypeIdentifier(_:)`` for an empty accepted type list,
    ///   and ``ClipboardError/invalidConfiguration(_:)`` for a timeout outside
    ///   `0 < timeout <= 300`.
    init(acceptedTypes: [String],
         timeout: TimeInterval,
         validator: any ClipboardTypeIdentifierValidating,
         onPaste: @escaping @MainActor (ClipboardPasteResult) -> Void) throws {
        Log.d("ClipboardPasteLoader", "[init] acceptedTypes: \(ClipboardLog.types(acceptedTypes)), "
              + "timeout: \(timeout)")
        guard !acceptedTypes.isEmpty else {
            throw ClipboardError.invalidTypeIdentifier("")
        }
        for identifier in acceptedTypes where !validator.isValid(identifier) {
            throw ClipboardError.invalidTypeIdentifier(identifier)
        }
        guard timeout > 0, timeout <= 300 else {
            throw ClipboardError.invalidConfiguration(
                "Paste timeout must be greater than 0 and at most 300 seconds.")
        }
        self.acceptedTypes = acceptedTypes
        self.timeout = timeout
        self.onPaste = onPaste
    }

    /// Loads every source and delivers one result.
    func load(from sources: [any Source]) {
        Log.d(TAG, "[load] sources: \(sources.count)")
        guard sources.count > 0 else {
            deliver(ClipboardPasteResult(items: [], failures: []))
            return
        }
        let acceptedTypes = self.acceptedTypes
        let timeout = self.timeout
        loadTask = Task { [weak self] in
            let outcome = await Self.loadAll(sources: sources, acceptedTypes: acceptedTypes,
                                             timeout: timeout)
            guard !Task.isCancelled else { return }
            self?.deliver(outcome)
        }
    }

    /// Cancels an in-flight load. Idempotent, and suppresses delivery.
    func cancel() {
        Log.d(TAG, "[cancel] delivered: \(hasDelivered)")
        loadTask?.cancel()
        loadTask = nil
        // A cancelled paste has no result to report: the view that asked for it is gone.
        hasDelivered = true
    }

    private func deliver(_ result: ClipboardPasteResult) {
        Log.d(TAG, "[deliver] items: \(result.items.count), failures: \(result.failures.count)")
        guard !hasDelivered else { return }
        hasDelivered = true
        onPaste(result)
    }

    /// Runs every provider concurrently under one deadline.
    private nonisolated static func loadAll(sources: [any Source],
                                            acceptedTypes: [String],
                                            timeout: TimeInterval) async -> ClipboardPasteResult {
        var items: [ClipboardPasteItem] = []
        var failures: [ClipboardPasteFailure] = []
        // Providers that never answer are recorded as timed out, so every input index appears
        // in exactly one of the two arrays.
        var pending = Set(sources.indices)

        await withTaskGroup(of: (Int, Result<ClipboardItemData, ClipboardError>)?.self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    let outcome = await load(source: source, acceptedTypes: acceptedTypes)
                    return (index, outcome)
                }
            }
            // A racing sleep rather than a per-provider timeout: the contract is one overall
            // deadline, and cancelling the group is what stops the stragglers.
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            for await result in group {
                guard let (index, outcome) = result else {
                    // The deadline won.
                    break
                }
                pending.remove(index)
                switch outcome {
                case .success(let data):
                    items.append(ClipboardPasteItem(providerIndex: index, data: data))
                case .failure(let error):
                    failures.append(ClipboardPasteFailure(providerIndex: index, error: error))
                }
                if pending.isEmpty { break }
            }
            group.cancelAll()
        }

        for index in pending.sorted() {
            failures.append(ClipboardPasteFailure(providerIndex: index,
                                                  error: .pasteLoadTimedOut(seconds: Int(timeout))))
        }
        // The initialiser sorts both arrays back into input order (R2-M10).
        return ClipboardPasteResult(items: items, failures: failures)
    }

    private nonisolated static func load(source: any Source,
                                         acceptedTypes: [String])
    async -> Result<ClipboardItemData, ClipboardError> {
        // The caller's order is the priority order, so the same pasteboard always yields the
        // same representation.
        for identifier in acceptedTypes where await source.conforms(to: identifier) {
            do {
                let data = try await source.loadData(for: identifier)
                return .success(ClipboardItemData(representations: [identifier: data]))
            } catch {
                return .failure(.pasteLoadFailed(String(describing: error)))
            }
        }
        return .failure(.pasteLoadFailed("no accepted type available"))
    }
}
