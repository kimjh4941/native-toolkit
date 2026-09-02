//
//  ClipboardRepositoryImpl.swift
//  MacLibrary
//

import AppKit
import Foundation

/// `NSPasteboard` backed implementation of ``ClipboardRepository``.
///
/// The type is deliberately thin: it converts between domain values and `NSPasteboard`, and
/// owns no system delegate. Delegates belong to the coordinator in the manager layer (H-5).
@MainActor
final class ClipboardRepositoryImpl {

    private let TAG = "ClipboardRepositoryImpl"

    private let validator: ClipboardTypeIdentifierValidator
    /// Resolves handles to the AppKit objects the coordinator owns. Held weakly so the
    /// repository never extends the lifetime of a system object it does not own (H-5).
    private weak var lookup: (any PromiseObjectLookup)?

    init(validator: ClipboardTypeIdentifierValidator,
         lookup: (any PromiseObjectLookup)? = nil) {
        self.validator = validator
        self.lookup = lookup
    }

    // MARK: - Ownership

    /// The only way this type takes ownership of a pasteboard.
    ///
    /// `prepareForNewContents(with:)` is always used and `clearContents()` never is, because
    /// only `prepareForNewContents` can carry `NSPasteboard.ContentsOptions`. Routing a copy
    /// through `clearContents()` would silently drop the caller's `localOnly` request and
    /// publish the contents to other devices (RK-05, §6.4).
    private func takeOwnership(_ pasteboard: NSPasteboard, localOnly: Bool) -> Int {
        Log.d(TAG, "[takeOwnership] pasteboard: \(pasteboard.name.rawValue), localOnly: \(localOnly)")
        let options: NSPasteboard.ContentsOptions = localOnly ? .currentHostOnly : []
        return pasteboard.prepareForNewContents(with: options)
    }
}

// MARK: - ClipboardRepository

extension ClipboardRepositoryImpl: ClipboardRepository {

    // MARK: Pasteboard lifetime (T-05)

    func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope {
        Log.d(TAG, "[createPasteboard] request: \(request)")
        let (_, scope) = try PasteboardResolver.create(request)
        return scope
    }

    func removePasteboard(_ scope: PasteboardScope) throws {
        Log.d(TAG, "[removePasteboard] scope: \(ClipboardLog.scope(scope))")
        // The guard runs before the scope is resolved, so there is no path that reaches
        // releaseGlobally() on a standard pasteboard (RK-07).
        guard !PasteboardResolver.isStandard(scope) else {
            throw ClipboardError.cannotReleaseStandardPasteboard(name: scope.name ?? "general")
        }
        let pasteboard = try PasteboardResolver.resolve(scope)
        pasteboard.releaseGlobally()
    }

    // MARK: Writing (T-04)

    func write(_ content: ClipboardContent,
               options: ClipboardCopyOptions,
               scope: PasteboardScope) throws -> PasteboardOwnership {
        Log.d(TAG, "[write] content: \(ClipboardLog.content(content)), "
              + "localOnly: \(options.localOnly), scope: \(ClipboardLog.scope(scope))")
        let pasteboard = try PasteboardResolver.resolve(scope)
        // Items are built before ownership is taken so that a malformed identifier leaves the
        // pasteboard untouched rather than emptied.
        let items = try ClipboardMappers.makeItems(from: content)
        let changeCount = takeOwnership(pasteboard, localOnly: options.localOnly)
        guard pasteboard.writeObjects(items) else {
            throw ClipboardError.writeRejected
        }
        return PasteboardOwnership(scope: scope, changeCount: changeCount)
    }

    func append(_ content: ClipboardContent,
                ownership: PasteboardOwnership) throws -> PasteboardOwnership {
        Log.d(TAG, "[append] content: \(ClipboardLog.content(content)), "
              + "scope: \(ClipboardLog.scope(ownership.scope)), expected: \(ownership.changeCount)")
        let pasteboard = try PasteboardResolver.resolve(ownership.scope)
        // Appending only works while this app still owns the pasteboard. Another owner makes
        // writeObjects return false without changing anything, so the mismatch is reported
        // before the write is attempted rather than after (RK-23, §6.3).
        let current = pasteboard.changeCount
        guard current == ownership.changeCount else {
            throw ClipboardError.ownershipLost(expected: ownership.changeCount, actual: current)
        }
        let items = try ClipboardMappers.makeItems(from: content)
        // Ownership is not retaken: prepareForNewContents would empty the pasteboard, which is
        // the opposite of appending.
        guard pasteboard.writeObjects(items) else {
            throw ClipboardError.appendRejected
        }
        // A successful append leaves the change count untouched, so the caller keeps the same
        // proof of ownership for any further append.
        return ownership
    }

    func writePromised(handle: PasteboardPromiseHandle,
                       types: [String],
                       options: ClipboardCopyOptions,
                       scope: PasteboardScope) throws -> PasteboardOwnership {
        Log.d(TAG, "[writePromised] handle: \(handle.id), types: \(ClipboardLog.types(types)), "
              + "scope: \(ClipboardLog.scope(scope))")
        guard !types.isEmpty else {
            throw ClipboardError.emptyRepresentations(itemIndex: 0)
        }
        // Resolved, never owned: the provider belongs to the coordinator (H-5).
        guard let provider = lookup?.lazyProvider(for: handle) else {
            throw ClipboardError.writeRejected
        }
        let pasteboard = try PasteboardResolver.resolve(scope)
        let item = NSPasteboardItem()
        let pasteboardTypes = types.map { NSPasteboard.PasteboardType($0) }
        // Declares the types without supplying any bytes. The provider is asked only when a
        // reader requests one of them.
        guard item.setDataProvider(provider, forTypes: pasteboardTypes) else {
            throw ClipboardError.invalidTypeIdentifier(types.joined(separator: ","))
        }
        let changeCount = takeOwnership(pasteboard, localOnly: options.localOnly)
        guard pasteboard.writeObjects([item]) else {
            throw ClipboardError.writeRejected
        }
        return PasteboardOwnership(scope: scope, changeCount: changeCount)
    }

    // MARK: Reading (T-04)

    func read(scope: PasteboardScope) throws -> ClipboardReadResult {
        Log.d(TAG, "[read] scope: \(ClipboardLog.scope(scope))")
        let pasteboard = try PasteboardResolver.resolve(scope)
        guard let items = pasteboard.pasteboardItems else {
            throw ClipboardError.pasteboardUnavailable(name: pasteboard.name.rawValue)
        }
        return ClipboardReadResult(items: ClipboardMappers.makeItemData(from: items),
                                   changeCount: pasteboard.changeCount)
    }

    func readData(utType: String, scope: PasteboardScope) throws -> Data? {
        Log.d(TAG, "[readData] utType: \(utType), scope: \(ClipboardLog.scope(scope))")
        let pasteboard = try PasteboardResolver.resolve(scope)
        // A type that is not present is an ordinary outcome, not a failure (M-1).
        return pasteboard.data(forType: NSPasteboard.PasteboardType(utType))
    }

    func snapshot(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot {
        Log.d(TAG, "[snapshot] matchingTypes: \(matchingTypes.map(ClipboardLog.types) ?? "nil"), "
              + "scope: \(ClipboardLog.scope(scope))")
        if let matchingTypes, matchingTypes.isEmpty {
            // An empty filter would silently match nothing, which reads as "the pasteboard is
            // empty" at the call site. Rejecting it keeps the two cases distinguishable.
            throw ClipboardError.emptyTypeFilter
        }
        let pasteboard = try PasteboardResolver.resolve(scope)
        guard let items = pasteboard.pasteboardItems else {
            throw ClipboardError.pasteboardUnavailable(name: pasteboard.name.rawValue)
        }
        // Only the advertised types are inspected; no representation is fetched.
        let itemTypes = ClipboardMappers.makeItemTypes(from: items)
        let matching: [Int]
        if let matchingTypes {
            matching = itemTypes.indices.filter { index in
                itemTypes[index].contains { validator.conforms($0, toAnyOf: matchingTypes) }
            }
        } else {
            matching = Array(itemTypes.indices)
        }
        return ClipboardSnapshot(changeCount: pasteboard.changeCount,
                                 itemTypes: itemTypes,
                                 matchingItemIndexes: matching)
    }

    // MARK: Clearing and observing (T-04)

    func clear(scope: PasteboardScope) throws -> Int {
        Log.d(TAG, "[clear] scope: \(ClipboardLog.scope(scope))")
        let pasteboard = try PasteboardResolver.resolve(scope)
        // The only use of clearContents() in the whole type (§6.4).
        return pasteboard.clearContents()
    }

    func changeCount(scope: PasteboardScope) throws -> Int {
        Log.d(TAG, "[changeCount] scope: \(ClipboardLog.scope(scope))")
        return try PasteboardResolver.resolve(scope).changeCount
    }

    // MARK: Detection

    /// Version the detection APIs were introduced in.
    ///
    /// There is deliberately no fallback below it. `canReadItem(withDataConformingToTypes:)`
    /// looks like one, but whether it triggers the same user notification is unverified, and
    /// the research explicitly forbids adopting it until that is settled (RK-01 / V-1).
    private static let detectionMinimumOS = "15.4"

    func detectPatterns(_ patterns: Set<ClipboardDetectionPattern>,
                        scope: PasteboardScope) async throws -> Set<ClipboardDetectionPattern> {
        Log.d(TAG, "[detectPatterns] patterns: \(patterns.count), scope: \(ClipboardLog.scope(scope))")
        guard #available(macOS 15.4, *) else {
            throw ClipboardError.detectionUnavailable(minimumOS: Self.detectionMinimumOS)
        }
        do {
            // Resolved inside the mapper so the pasteboard never leaves one isolation domain.
            return try await ClipboardDetectionMapper.detectPatterns(scope: scope, patterns: patterns)
        } catch {
            throw Self.detectionError(from: error)
        }
    }

    func detectValues(_ patterns: Set<ClipboardDetectionPattern>,
                      scope: PasteboardScope) async throws -> ClipboardDetectedValues {
        Log.d(TAG, "[detectValues] patterns: \(patterns.count), scope: \(ClipboardLog.scope(scope))")
        guard #available(macOS 15.4, *) else {
            throw ClipboardError.detectionUnavailable(minimumOS: Self.detectionMinimumOS)
        }
        do {
            // Resolved inside the mapper so the pasteboard never leaves one isolation domain.
            return try await ClipboardDetectionMapper.detectValues(scope: scope, patterns: patterns)
        } catch {
            throw Self.detectionError(from: error)
        }
    }

    func detectMetadata(scope: PasteboardScope) async throws -> ClipboardDetectedMetadata {
        Log.d(TAG, "[detectMetadata] scope: \(ClipboardLog.scope(scope))")
        guard #available(macOS 15.4, *) else {
            throw ClipboardError.detectionUnavailable(minimumOS: Self.detectionMinimumOS)
        }
        do {
            return try await ClipboardDetectionMapper.detectMetadata(
                scope: scope, types: Set(ClipboardMetadataType.allCases))
        } catch {
            throw Self.detectionError(from: error)
        }
    }

    func accessBehavior(scope: PasteboardScope) throws -> ClipboardAccessBehavior {
        Log.d(TAG, "[accessBehavior] scope: \(ClipboardLog.scope(scope))")
        // Resolved first: an unusable scope is an error even on versions that cannot report
        // the behaviour.
        let pasteboard = try PasteboardResolver.resolve(scope)
        guard #available(macOS 15.4, *) else {
            // Not knowing is a normal state on these versions, not a failure (M-2).
            return .unavailable
        }
        switch pasteboard.accessBehavior {
        case .ask: return .ask
        case .alwaysAllow: return .alwaysAllow
        case .alwaysDeny: return .alwaysDeny
        case .default: return .default
        @unknown default: return .unavailable
        }
    }

    /// Converts a detection failure into a domain error.
    ///
    /// A cancelled task keeps the standard `CancellationError` shape at the boundary but is
    /// reported as ``ClipboardError/cancelled`` here, because the detection operations are the
    /// only ones that use it (R5-M10).
    private static func detectionError(from error: any Error) -> ClipboardError {
        if error is CancellationError {
            return .cancelled
        }
        let nsError = error as NSError
        // The system reports a refused pasteboard read as an error rather than as an empty
        // result, so the caller can tell "denied" from "nothing matched" (RK-03).
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return .detectionDenied
        }
        return .detectionFailed(nsError.localizedDescription)
    }
}
