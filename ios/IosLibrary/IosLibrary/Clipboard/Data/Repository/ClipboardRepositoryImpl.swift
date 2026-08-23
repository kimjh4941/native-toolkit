//
//  ClipboardRepositoryImpl.swift
//  IosLibrary
//

import Foundation
import UIKit

/// `UIPasteboard`-backed implementation of `ClipboardRepository`.
///
/// `copy` / `append` are `async throws` solely because their content enum may carry an image
/// (`.imageFile`), which is decoded/encoded off the main actor via `ClipboardImageCoder` before
/// the (synchronous) pasteboard write. Non-image content never triggers a background hop: it is
/// converted and written within the same actor turn.
@MainActor
final class ClipboardRepositoryImpl: ClipboardRepository {
    private let TAG = "ClipboardRepositoryImpl"
    private let resolver: PasteboardResolver
    private let imageCoder: ClipboardImageCoder
    private let detectionMapper: ClipboardDetectionMapper
    private let fileManager: FileManager
    private let limits: ClipboardLimits

    init(
        resolver: PasteboardResolver? = nil,
        imageCoder: ClipboardImageCoder? = nil,
        detectionMapper: ClipboardDetectionMapper = ClipboardDetectionMapper(),
        fileManager: FileManager = .default,
        limits: ClipboardLimits = .default,
        timeouts: ClipboardTimeouts = .default
    ) {
        self.resolver = resolver ?? PasteboardResolver()
        self.imageCoder = imageCoder ?? ClipboardImageCoder(limits: limits, timeouts: timeouts)
        self.detectionMapper = detectionMapper
        self.fileManager = fileManager
        self.limits = limits
    }

    func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope {
        Log.d(TAG, "[createPasteboard] request: \(request.redactedDescription)")
        return try resolver.createPasteboard(request)
    }

    func removePasteboard(_ scope: PasteboardScope) throws {
        Log.d(TAG, "[removePasteboard] scope: \(scope.redactedDescription)")
        try resolver.removePasteboard(scope)
    }

    func copy(_ content: ClipboardContent, options: ClipboardCopyOptions, scope: PasteboardScope) async throws {
        Log.d(TAG, "[copy] scope: \(scope.redactedDescription), localOnly: \(options.localOnly)")
        let items = try await makeItems(from: content)
        try checkCancellation()
        let pasteboard = try resolver.resolve(scope)
        var pbOptions: [UIPasteboard.OptionsKey: Any] = [.localOnly: options.localOnly]
        if let expirationDate = options.expirationDate {
            pbOptions[.expirationDate] = expirationDate
        }
        pasteboard.setItems(items, options: pbOptions)
    }

    func append(_ content: ClipboardContent, scope: PasteboardScope) async throws {
        Log.d(TAG, "[append] scope: \(scope.redactedDescription)")
        let items = try await makeItems(from: content)
        try checkCancellation()
        let pasteboard = try resolver.resolve(scope)
        pasteboard.addItems(items)
    }

    func read(scope: PasteboardScope) throws -> ClipboardReadResult {
        Log.d(TAG, "[read] scope: \(scope.redactedDescription)")
        let pasteboard = try resolver.resolve(scope)
        let items = pasteboard.items
        return ClipboardReadResult(items: items.map(ClipboardMappers.toItemData), numberOfItems: items.count)
    }

    func readData(utType: String, scope: PasteboardScope) throws -> Data? {
        Log.d(TAG, "[readData] utType: \(utType), scope: \(scope.redactedDescription)")
        let pasteboard = try resolver.resolve(scope)
        return pasteboard.data(forPasteboardType: utType)
    }

    func snapshot(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot {
        Log.d(TAG, "[snapshot] scope: \(scope.redactedDescription)")
        let pasteboard = try resolver.resolve(scope)
        var matchingIndexes: [Int]?
        if let matchingTypes, !matchingTypes.isEmpty {
            matchingIndexes = pasteboard.itemSet(withPasteboardTypes: matchingTypes)?.sorted() ?? []
        }
        return ClipboardSnapshot(
            hasStrings: pasteboard.hasStrings,
            hasURLs: pasteboard.hasURLs,
            hasImages: pasteboard.hasImages,
            hasColors: pasteboard.hasColors,
            numberOfItems: pasteboard.numberOfItems,
            typeIdentifiers: pasteboard.types,
            allTypeIdentifiers: pasteboard.types(forItemSet: nil) ?? [],
            matchingItemIndexes: matchingIndexes
        )
    }

    func clear(scope: PasteboardScope) throws {
        Log.d(TAG, "[clear] scope: \(scope.redactedDescription)")
        let pasteboard = try resolver.resolve(scope)
        pasteboard.items = []
    }

    func changeCount(scope: PasteboardScope) throws -> Int {
        Log.d(TAG, "[changeCount] scope: \(scope.redactedDescription)")
        let pasteboard = try resolver.resolve(scope)
        return pasteboard.changeCount
    }

    func detectPatterns(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope
    ) async throws -> Set<ClipboardDetectionPattern> {
        Log.d(TAG, "[detectPatterns] scope: \(scope.redactedDescription), count: \(patterns.count)")
        let pasteboard = try resolver.resolve(scope)
        let keyPaths = detectionMapper.keyPaths(for: patterns)
        do {
            let detected = try await pasteboard.detectedPatterns(for: keyPaths)
            return detectionMapper.patterns(for: detected)
        } catch {
            throw ClipboardError.detectionFailed(ClipboardFailureDetail(systemError: error))
        }
    }

    func detectValues(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope
    ) async throws -> ClipboardDetectedValues {
        Log.d(TAG, "[detectValues] scope: \(scope.redactedDescription), count: \(patterns.count)")
        let pasteboard = try resolver.resolve(scope)
        let keyPaths = detectionMapper.keyPaths(for: patterns)
        do {
            let values = try await pasteboard.detectedValues(for: keyPaths)
            return detectionMapper.toDomain(values)
        } catch {
            throw ClipboardError.detectionFailed(ClipboardFailureDetail(systemError: error))
        }
    }

    private func makeItems(from content: ClipboardContent) async throws -> [[String: Any]] {
        switch content {
        case .imageFile(let path):
            guard fileManager.fileExists(atPath: path) else {
                throw ClipboardError.fileNotFound(path: path)
            }
            // Check the on-disk size before decoding: the limit is a security boundary, so an
            // oversized (or unverifiable) file must be rejected before it is loaded into memory.
            let fileSize = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let fileSize else {
                throw ClipboardError.imageLoadFailed(path: path)
            }
            guard fileSize <= limits.maxCopyByteCount else {
                throw ClipboardError.contentTooLarge(byteCount: fileSize, limit: limits.maxCopyByteCount)
            }
            let encoded = try await imageCoder.loadAndEncodeImageFile(atPath: path)
            return try ClipboardMappers.makeItems(from: content, encodedImage: encoded)

        case .imageData(let data, _):
            try await imageCoder.validateImageData(data)
            return try ClipboardMappers.makeItems(from: content, encodedImage: nil)

        default:
            return try ClipboardMappers.makeItems(from: content, encodedImage: nil)
        }
    }

    private func checkCancellation() throws {
        guard !Task.isCancelled else { throw ClipboardError.cancelled }
    }
}
