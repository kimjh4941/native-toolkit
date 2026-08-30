//
//  MockClipboardRepository.swift
//  MacLibraryTests
//

import Foundation
@testable import MacLibrary

/// Records every call and returns stubbed values.
///
/// Follows the repository convention of `shouldFail` / `xxxCallCount` / `stubbedXxx` so that a
/// test can assert both the result and the fact that the port was reached exactly once.
@MainActor
final class MockClipboardRepository: ClipboardRepository {

    /// Thrown by every operation when set. Lets a test prove a use case passes errors through
    /// rather than translating them.
    var shouldFail: ClipboardError?

    // MARK: Recorded calls

    private(set) var createPasteboardCallCount = 0
    private(set) var removePasteboardCallCount = 0
    private(set) var writeCallCount = 0
    private(set) var writePromisedCallCount = 0
    private(set) var appendCallCount = 0
    private(set) var readCallCount = 0
    private(set) var readDataCallCount = 0
    private(set) var snapshotCallCount = 0
    private(set) var clearCallCount = 0
    private(set) var changeCountCallCount = 0
    private(set) var writeFilePromiseCallCount = 0

    private(set) var lastRequest: PasteboardCreationRequest?
    private(set) var lastRemovedScope: PasteboardScope?
    private(set) var lastContent: ClipboardContent?
    private(set) var lastOptions: ClipboardCopyOptions?
    private(set) var lastScope: PasteboardScope?
    private(set) var lastOwnership: PasteboardOwnership?
    private(set) var lastUTType: String?
    private(set) var lastMatchingTypes: [String]??
    private(set) var lastFilePromiseHandle: FilePromiseHandle?

    // MARK: Stubs

    var stubbedScope: PasteboardScope = .unique("mock")
    var stubbedOwnership = PasteboardOwnership(scope: .general, changeCount: 1)
    var stubbedReadResult = ClipboardReadResult(items: [], changeCount: 0)
    var stubbedData: Data?
    var stubbedSnapshot = ClipboardSnapshot(changeCount: 0, itemTypes: [], matchingItemIndexes: [])
    var stubbedClearChangeCount = 1
    var stubbedChangeCount = 0

    private func failIfNeeded() throws {
        if let shouldFail { throw shouldFail }
    }

    // MARK: ClipboardRepository

    func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope {
        createPasteboardCallCount += 1
        lastRequest = request
        try failIfNeeded()
        return stubbedScope
    }

    func removePasteboard(_ scope: PasteboardScope) throws {
        removePasteboardCallCount += 1
        lastRemovedScope = scope
        try failIfNeeded()
    }

    func write(_ content: ClipboardContent,
               options: ClipboardCopyOptions,
               scope: PasteboardScope) throws -> PasteboardOwnership {
        writeCallCount += 1
        lastContent = content
        lastOptions = options
        lastScope = scope
        try failIfNeeded()
        return stubbedOwnership
    }

    func writePromised(handle: PasteboardPromiseHandle,
                       types: [String],
                       options: ClipboardCopyOptions,
                       scope: PasteboardScope) throws -> PasteboardOwnership {
        writePromisedCallCount += 1
        lastScope = scope
        try failIfNeeded()
        return stubbedOwnership
    }

    func append(_ content: ClipboardContent,
                ownership: PasteboardOwnership) throws -> PasteboardOwnership {
        appendCallCount += 1
        lastContent = content
        lastOwnership = ownership
        try failIfNeeded()
        return stubbedOwnership
    }

    func read(scope: PasteboardScope) throws -> ClipboardReadResult {
        readCallCount += 1
        lastScope = scope
        try failIfNeeded()
        return stubbedReadResult
    }

    func readData(utType: String, scope: PasteboardScope) throws -> Data? {
        readDataCallCount += 1
        lastUTType = utType
        lastScope = scope
        try failIfNeeded()
        return stubbedData
    }

    func snapshot(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot {
        snapshotCallCount += 1
        lastMatchingTypes = .some(matchingTypes)
        lastScope = scope
        try failIfNeeded()
        return stubbedSnapshot
    }

    func clear(scope: PasteboardScope) throws -> Int {
        clearCallCount += 1
        lastScope = scope
        try failIfNeeded()
        return stubbedClearChangeCount
    }

    func changeCount(scope: PasteboardScope) throws -> Int {
        changeCountCallCount += 1
        lastScope = scope
        try failIfNeeded()
        return stubbedChangeCount
    }

    func detectPatterns(_ patterns: Set<ClipboardDetectionPattern>,
                        scope: PasteboardScope) async throws -> Set<ClipboardDetectionPattern> {
        try failIfNeeded()
        return []
    }

    func detectValues(_ patterns: Set<ClipboardDetectionPattern>,
                      scope: PasteboardScope) async throws -> ClipboardDetectedValues {
        try failIfNeeded()
        return ClipboardDetectedValues(patterns: [])
    }

    func detectMetadata(scope: PasteboardScope) async throws -> ClipboardDetectedMetadata {
        try failIfNeeded()
        return ClipboardDetectedMetadata(metadataTypes: [], contentTypeIdentifier: nil)
    }

    func accessBehavior(scope: PasteboardScope) throws -> ClipboardAccessBehavior {
        try failIfNeeded()
        return .unavailable
    }

    func writeFilePromise(handle: FilePromiseHandle,
                          scope: PasteboardScope) throws -> PasteboardOwnership {
        writeFilePromiseCallCount += 1
        lastFilePromiseHandle = handle
        lastScope = scope
        try failIfNeeded()
        return stubbedOwnership
    }

    func startReceivingFilePromises(handle: FilePromiseReceiptHandle,
                                    destinationDirectory: URL,
                                    scope: PasteboardScope) throws {
        try failIfNeeded()
    }
}
