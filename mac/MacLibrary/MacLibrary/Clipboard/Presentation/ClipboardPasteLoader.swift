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
/// does not cancel the others, and the whole thing is bounded by a deadline (H-8).
///
/// Two properties drive the structure.
///
/// The loader outlives a single press, because the button stays on screen. Exactly-once is
/// therefore **per press**, tracked by a generation, not a single flag for the loader's whole
/// life. A press that is still running when the next one starts is superseded: its result is
/// for a payload the user has already replaced.
///
/// The deadline must hold even against a provider that never calls back. A task group would
/// wait for every child before returning, so one unresponsive provider would keep the whole
/// load pending forever. Provider tasks are therefore unstructured and their results are
/// collected as they arrive; the deadline settles whatever is still outstanding without
/// waiting for it.
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

    /// Identifies the current press. Results carrying an older generation are dropped.
    private var generation: UInt64 = 0
    /// Generation whose result has already been delivered, so a deadline and a final provider
    /// finishing together cannot both report.
    private var deliveredGeneration: UInt64?
    /// Set once the owning view is gone. Permanent: nothing is delivered afterwards.
    private var isCancelled = false

    private var pending: Set<Int> = []
    private var items: [ClipboardPasteItem] = []
    private var failures: [ClipboardPasteFailure] = []
    private var providerTasks: [Task<Void, Never>] = []
    private var deadlineTask: Task<Void, Never>?

    /// - Throws: ``ClipboardError/invalidTypeIdentifier(_:)`` for an empty or malformed accepted
    ///   type, and ``ClipboardError/invalidConfiguration(_:)`` for a timeout outside
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

    /// Loads every source and delivers one result for this press.
    func load(from sources: [any Source]) {
        Log.d(TAG, "[load] sources: \(sources.count)")
        guard !isCancelled else { return }

        // Supersede whatever the previous press was doing.
        stopInFlightWork()
        generation &+= 1
        let current = generation
        items = []
        failures = []
        pending = Set(sources.indices)

        guard !sources.isEmpty else {
            deliver(generation: current)
            return
        }

        let acceptedTypes = self.acceptedTypes
        for (index, source) in sources.enumerated() {
            providerTasks.append(Task { [weak self] in
                let outcome = await Self.load(source: source, acceptedTypes: acceptedTypes)
                // Back on the main actor: the task inherits this type's isolation.
                self?.record(index: index, outcome: outcome, generation: current)
            })
        }

        let timeout = self.timeout
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.settleByDeadline(generation: current, seconds: Int(timeout))
        }
    }

    /// Cancels the current press and refuses any further one. Idempotent.
    func cancel() {
        Log.d(TAG, "[cancel] generation: \(generation)")
        isCancelled = true
        stopInFlightWork()
    }

    // MARK: - Private

    private func stopInFlightWork() {
        deadlineTask?.cancel()
        deadlineTask = nil
        for task in providerTasks {
            task.cancel()
        }
        providerTasks = []
        pending = []
    }

    private func record(index: Int,
                        outcome: Result<ClipboardItemData, ClipboardError>,
                        generation current: UInt64) {
        Log.d(TAG, "[record] index: \(index), generation: \(current)")
        guard current == generation, deliveredGeneration != current else {
            // A superseded press, or one that has already reported.
            return
        }
        guard pending.remove(index) != nil else { return }
        switch outcome {
        case .success(let data):
            items.append(ClipboardPasteItem(providerIndex: index, data: data))
        case .failure(let error):
            failures.append(ClipboardPasteFailure(providerIndex: index, error: error))
        }
        guard pending.isEmpty else { return }
        deliver(generation: current)
    }

    private func settleByDeadline(generation current: UInt64, seconds: Int) {
        Log.d(TAG, "[settleByDeadline] generation: \(current), pending: \(pending.count)")
        guard current == generation, deliveredGeneration != current else { return }
        // Whatever has not answered is recorded as timed out, so every input index appears in
        // exactly one of the two arrays. The provider tasks are not awaited: one of them may
        // never finish, which is the case this deadline exists for.
        for index in pending.sorted() {
            failures.append(ClipboardPasteFailure(providerIndex: index,
                                                  error: .pasteLoadTimedOut(seconds: seconds)))
        }
        pending = []
        deliver(generation: current)
    }

    private func deliver(generation current: UInt64) {
        Log.d(TAG, "[deliver] generation: \(current), items: \(items.count), "
              + "failures: \(failures.count)")
        guard !isCancelled, current == generation, deliveredGeneration != current else { return }
        deliveredGeneration = current
        // The initialiser sorts both arrays back into input order (R2-M10).
        let result = ClipboardPasteResult(items: items, failures: failures)
        stopInFlightWork()
        onPaste(result)
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
