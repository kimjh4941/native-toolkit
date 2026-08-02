//
//  MockClipboardRepository.swift
//  IosLibraryTests
//

import Foundation
@testable import IosLibrary

@MainActor
final class MockClipboardRepository: ClipboardRepository {
    var shouldFail = false
    var errorToThrow: ClipboardError = .unknown(ClipboardFailureDetail(domain: "test", code: -1, debugMessage: "test"))

    var stubbedCreatedScope: PasteboardScope = .unique("mock-unique")
    var stubbedReadResult = ClipboardReadResult(items: [], numberOfItems: 0)
    var stubbedData: Data?
    var stubbedSnapshot = ClipboardSnapshot(
        hasStrings: false, hasURLs: false, hasImages: false, hasColors: false,
        numberOfItems: 0, typeIdentifiers: [], allTypeIdentifiers: [], matchingItemIndexes: nil
    )
    var stubbedChangeCount = 0
    var stubbedDetectedPatterns: Set<ClipboardDetectionPattern> = []
    var stubbedDetectedValues: ClipboardDetectedValues = .empty

    private(set) var createPasteboardCallCount = 0
    private(set) var removePasteboardCallCount = 0
    private(set) var copyCallCount = 0
    private(set) var appendCallCount = 0
    private(set) var readCallCount = 0
    private(set) var readDataCallCount = 0
    private(set) var snapshotCallCount = 0
    private(set) var clearCallCount = 0
    private(set) var changeCountCallCount = 0
    private(set) var detectPatternsCallCount = 0
    private(set) var detectValuesCallCount = 0

    private(set) var lastCopiedContent: ClipboardContent?
    private(set) var lastCopyOptions: ClipboardCopyOptions?
    private(set) var lastAppendedContent: ClipboardContent?
    private(set) var lastRemovedScope: PasteboardScope?
    private(set) var lastReadDataUTType: String?
    private(set) var lastMatchingTypes: [String]?

    func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope {
        createPasteboardCallCount += 1
        if shouldFail { throw errorToThrow }
        return stubbedCreatedScope
    }

    func removePasteboard(_ scope: PasteboardScope) throws {
        removePasteboardCallCount += 1
        lastRemovedScope = scope
        if shouldFail { throw errorToThrow }
    }

    func copy(_ content: ClipboardContent, options: ClipboardCopyOptions, scope: PasteboardScope) async throws {
        copyCallCount += 1
        lastCopiedContent = content
        lastCopyOptions = options
        if shouldFail { throw errorToThrow }
    }

    func append(_ content: ClipboardContent, scope: PasteboardScope) async throws {
        appendCallCount += 1
        lastAppendedContent = content
        if shouldFail { throw errorToThrow }
    }

    func read(scope: PasteboardScope) throws -> ClipboardReadResult {
        readCallCount += 1
        if shouldFail { throw errorToThrow }
        return stubbedReadResult
    }

    func readData(utType: String, scope: PasteboardScope) throws -> Data? {
        readDataCallCount += 1
        lastReadDataUTType = utType
        if shouldFail { throw errorToThrow }
        return stubbedData
    }

    func snapshot(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot {
        snapshotCallCount += 1
        lastMatchingTypes = matchingTypes
        if shouldFail { throw errorToThrow }
        return stubbedSnapshot
    }

    func clear(scope: PasteboardScope) throws {
        clearCallCount += 1
        if shouldFail { throw errorToThrow }
    }

    func changeCount(scope: PasteboardScope) throws -> Int {
        changeCountCallCount += 1
        if shouldFail { throw errorToThrow }
        return stubbedChangeCount
    }

    func detectPatterns(_ patterns: Set<ClipboardDetectionPattern>, scope: PasteboardScope) async throws -> Set<ClipboardDetectionPattern> {
        detectPatternsCallCount += 1
        if shouldFail { throw errorToThrow }
        return stubbedDetectedPatterns
    }

    func detectValues(_ patterns: Set<ClipboardDetectionPattern>, scope: PasteboardScope) async throws -> ClipboardDetectedValues {
        detectValuesCallCount += 1
        if shouldFail { throw errorToThrow }
        return stubbedDetectedValues
    }
}
