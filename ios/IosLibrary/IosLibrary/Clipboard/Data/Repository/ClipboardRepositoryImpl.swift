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

    nonisolated init(
        resolver: PasteboardResolver = PasteboardResolver(),
        imageCoder: ClipboardImageCoder = ClipboardImageCoder(),
        detectionMapper: ClipboardDetectionMapper = ClipboardDetectionMapper(),
        fileManager: FileManager = .default
    ) {
        self.resolver = resolver
        self.imageCoder = imageCoder
        self.detectionMapper = detectionMapper
        self.fileManager = fileManager
    }

    func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope {
        Log.d(TAG, "[createPasteboard] request: \(request)")
        return try resolver.createPasteboard(request)
    }

    func removePasteboard(_ scope: PasteboardScope) throws {
        Log.d(TAG, "[removePasteboard] scope: \(scope)")
        try resolver.removePasteboard(scope)
    }

    func copy(_ content: ClipboardContent, options: ClipboardCopyOptions, scope: PasteboardScope) async throws {
        Log.d(TAG, "[copy] scope: \(scope), localOnly: \(options.localOnly)")
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
        Log.d(TAG, "[append] scope: \(scope)")
        let items = try await makeItems(from: content)
        try checkCancellation()
        let pasteboard = try resolver.resolve(scope)
        pasteboard.addItems(items)
    }

    func read(scope: PasteboardScope) throws -> ClipboardReadResult {
        Log.d(TAG, "[read] scope: \(scope)")
        let pasteboard = try resolver.resolve(scope)
        let items = pasteboard.items
        return ClipboardReadResult(items: items.map(ClipboardMappers.toItemData), numberOfItems: items.count)
    }

    func readData(utType: String, scope: PasteboardScope) throws -> Data? {
        Log.d(TAG, "[readData] utType: \(utType), scope: \(scope)")
        let pasteboard = try resolver.resolve(scope)
        return pasteboard.data(forPasteboardType: utType)
    }

    func snapshot(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot {
        Log.d(TAG, "[snapshot] scope: \(scope)")
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
        Log.d(TAG, "[clear] scope: \(scope)")
        let pasteboard = try resolver.resolve(scope)
        pasteboard.items = []
    }

    func changeCount(scope: PasteboardScope) throws -> Int {
        Log.d(TAG, "[changeCount] scope: \(scope)")
        let pasteboard = try resolver.resolve(scope)
        return pasteboard.changeCount
    }

    func detectPatterns(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope
    ) async throws -> Set<ClipboardDetectionPattern> {
        Log.d(TAG, "[detectPatterns] scope: \(scope), count: \(patterns.count)")
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
        Log.d(TAG, "[detectValues] scope: \(scope), count: \(patterns.count)")
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
