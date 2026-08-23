//
//  ClipboardProviderLoadExecutorTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
import UIKit
import UniformTypeIdentifiers
@testable import IosLibrary

/// Serialized: these cases race real timeouts against real provider callbacks on the main actor,
/// so concurrent main-actor work from sibling cases can starve the timeout Task.
@MainActor
@Suite(.serialized)
struct ClipboardProviderLoadExecutorTests {

    // MARK: - requestKind(for:acceptedTypes:)

    @Test func acceptedTypesConstrainWhichRepresentationIsTaken() {
        // A provider advertising both text and image must yield `.image` when the caller only
        // accepts images — the previous implementation always preferred text.
        let provider = NSItemProvider()
        provider.registerDataRepresentation(for: .plainText) { handler in
            handler(Data("hi".utf8), nil); return nil
        }
        provider.registerDataRepresentation(for: .png) { handler in
            handler(Data([0x89, 0x50]), nil); return nil
        }

        let imageOnly = ClipboardProviderLoadExecutor.requestKind(
            for: provider, acceptedTypes: [UTType.image.identifier]
        )
        #expect(imageOnly == .image)
    }

    @Test func textIsPreferredWhenBothTextAndImageAreAccepted() {
        let provider = NSItemProvider(object: "hello" as NSString)
        let kind = ClipboardProviderLoadExecutor.requestKind(
            for: provider,
            acceptedTypes: [UTType.plainText.identifier, UTType.image.identifier]
        )
        #expect(kind == .text)
    }

    @Test func unacceptedProviderYieldsNil() {
        let provider = NSItemProvider(object: "hello" as NSString)
        let kind = ClipboardProviderLoadExecutor.requestKind(
            for: provider, acceptedTypes: [UTType.image.identifier]
        )
        #expect(kind == nil)
    }

    @Test func customFileTypeIsSelectedWhenAccepted() {
        let customType = "com.jonghyunkim.nativetoolkit.custom-payload"
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: customType, visibility: .all) { handler in
            handler(Data([1, 2, 3]), nil); return nil
        }
        let kind = ClipboardProviderLoadExecutor.requestKind(for: provider, acceptedTypes: [customType])
        // File loading must be reachable; previously any custom UTI fell through to noMatchingItem.
        #expect(kind == .file(utType: customType))
    }

    // MARK: - Loading, limits, cancellation

    private func makeExecutor(limits: ClipboardLimits = .default, timeouts: ClipboardTimeouts = .default) -> ClipboardProviderLoadExecutor {
        ClipboardProviderLoadExecutor(
            fileStore: ClipboardTemporaryFileStore(sessionID: UUID().uuidString),
            limits: limits,
            timeouts: timeouts
        )
    }

    private func makeExecutor(
        fileStore: ClipboardTemporaryFileStore,
        limits: ClipboardLimits = .default,
        timeouts: ClipboardTimeouts = .default
    ) -> ClipboardProviderLoadExecutor {
        ClipboardProviderLoadExecutor(fileStore: fileStore, limits: limits, timeouts: timeouts)
    }

    private static func pngData(side: Int) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    private static func writeTemporaryFile(byteCount: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).bin")
        try Data(repeating: 0x41, count: byteCount).write(to: url)
        return url
    }

    private static func fileProvider(_ url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.data.identifier, fileOptions: [], visibility: .all
        ) { handler in
            handler(url, true, nil)
            return nil
        }
        return provider
    }

    /// A file provider whose representation lands only after `delay`, so a shorter `providerLoad`
    /// timeout is guaranteed to win the race.
    private static func delayedFileProvider(_ url: URL, delay: TimeInterval) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.data.identifier, fileOptions: [], visibility: .all
        ) { handler in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                handler(url, true, nil)
            }
            return nil
        }
        return provider
    }

    private static func imageProvider(_ data: Data) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { handler in
            handler(data, nil)
            return nil
        }
        return provider
    }

    private func sessionDirectoryIsEmpty(_ fileStore: ClipboardTemporaryFileStore) -> Bool {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: fileStore.sessionDirectory, includingPropertiesForKeys: nil
        )
        return (contents ?? []).isEmpty
    }

    // MARK: - Image boundaries

    @Test func imageLoadSucceedsAndReturnsPNG() async {
        let executor = makeExecutor()
        let provider = Self.imageProvider(Self.pngData(side: 4))
        let result = await withCheckedContinuation { continuation in
            executor.start(.image, from: provider) { continuation.resume(returning: $0) }
        }
        guard case .success(.imageData(let data, let utType)) = result else {
            Issue.record("expected imageData success"); return
        }
        #expect(utType == UTType.png.identifier)
        #expect(!data.isEmpty)
    }

    @Test func imageLoadRejectsInputOverLoadLimit() async {
        let data = Self.pngData(side: 32)
        let limits = ClipboardLimits(
            maxCopyByteCount: 64 * 1024 * 1024, maxLoadByteCount: data.count - 1, maxImagePixelCount: 100_000_000
        )!
        let executor = makeExecutor(limits: limits)
        let result = await withCheckedContinuation { continuation in
            executor.start(.image, from: Self.imageProvider(data)) { continuation.resume(returning: $0) }
        }
        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect(error.errorCode == ClipboardError.contentTooLarge(byteCount: 1, limit: 1).errorCode)
    }

    @Test func imageLoadAcceptsInputExactlyAtTheLoadLimit() async {
        let data = Self.pngData(side: 4)
        let limits = ClipboardLimits(
            maxCopyByteCount: 64 * 1024 * 1024, maxLoadByteCount: data.count, maxImagePixelCount: 100_000_000
        )!
        let executor = makeExecutor(limits: limits)
        let result = await withCheckedContinuation { continuation in
            executor.start(.image, from: Self.imageProvider(data)) { continuation.resume(returning: $0) }
        }
        // The limit is inclusive: exactly-at-limit input must not be rejected.
        if case .failure(let error) = result {
            #expect(error.errorCode != ClipboardError.contentTooLarge(byteCount: 1, limit: 1).errorCode)
        }
    }

    @Test func imageLoadRejectsPixelCountOverLimit() async {
        let limits = ClipboardLimits(
            maxCopyByteCount: 64 * 1024 * 1024, maxLoadByteCount: 64 * 1024 * 1024, maxImagePixelCount: 4
        )!
        let executor = makeExecutor(limits: limits)
        let result = await withCheckedContinuation { continuation in
            executor.start(.image, from: Self.imageProvider(Self.pngData(side: 32))) {
                continuation.resume(returning: $0)
            }
        }
        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect(error.errorCode == ClipboardError.contentTooLarge(byteCount: 1, limit: 1).errorCode)
    }

    // MARK: - File boundaries and temporary-file cleanup

    @Test func fileLoadSucceedsAndProducesACopy() async throws {
        let fileStore = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let executor = makeExecutor(fileStore: fileStore)
        let source = try Self.writeTemporaryFile(byteCount: 128)
        defer { try? FileManager.default.removeItem(at: source) }

        let result = await withCheckedContinuation { continuation in
            executor.start(.file(utType: UTType.data.identifier), from: Self.fileProvider(source)) {
                continuation.resume(returning: $0)
            }
        }
        guard case .success(.file(let url)) = result else { Issue.record("expected file success"); return }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.path.hasPrefix(fileStore.sessionDirectory.path))
    }

    @Test func fileLoadRejectsOversizeSourceWithoutCopyingIt() async throws {
        // H-01: the size limit is a security boundary, so an oversize source must be rejected
        // before a single byte lands in the temporary directory.
        let limits = ClipboardLimits(maxCopyByteCount: 1_000, maxLoadByteCount: 64, maxImagePixelCount: 1_000)!
        let fileStore = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let executor = makeExecutor(fileStore: fileStore, limits: limits)
        let source = try Self.writeTemporaryFile(byteCount: 4_096)
        defer { try? FileManager.default.removeItem(at: source) }

        let result = await withCheckedContinuation { continuation in
            executor.start(.file(utType: UTType.data.identifier), from: Self.fileProvider(source)) {
                continuation.resume(returning: $0)
            }
        }
        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect(error.errorCode == ClipboardError.contentTooLarge(byteCount: 1, limit: 1).errorCode)
        #expect(sessionDirectoryIsEmpty(fileStore))
    }

    @Test func fileLoadFailsWhenTheSourceSizeCannotBeVerified() async throws {
        // A directory has no `fileSize`, so the size limit cannot be enforced. The copy must not
        // start at all rather than proceed unbounded.
        let limits = ClipboardLimits(maxCopyByteCount: 1_000, maxLoadByteCount: 64, maxImagePixelCount: 1_000)!
        let fileStore = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let executor = makeExecutor(fileStore: fileStore, limits: limits)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4_096).write(to: directory.appendingPathComponent("payload.bin"))
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = await withCheckedContinuation { continuation in
            executor.start(.file(utType: UTType.data.identifier), from: Self.fileProvider(directory)) {
                continuation.resume(returning: $0)
            }
        }
        guard case .failure(.fileCopyFailed(let detail)) = result else {
            Issue.record("expected fileCopyFailed"); return
        }
        // Pin the exact boundary that rejected the load: a provider-side representation error
        // would otherwise satisfy a looser assertion and hide a regression here.
        #expect(detail.domain == ClipboardProviderLoadExecutor.FailureDetailCode.domain)
        #expect(detail.code == ClipboardProviderLoadExecutor.FailureDetailCode.sourceSizeUnverifiable)
        #expect(sessionDirectoryIsEmpty(fileStore))
    }

    @Test func cancellingAFileLoadLeavesNoTemporaryFileBehind() async throws {
        let fileStore = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let executor = makeExecutor(fileStore: fileStore)
        let source = try Self.writeTemporaryFile(byteCount: 4_096)
        defer { try? FileManager.default.removeItem(at: source) }

        var deliveries: [Result<ClipboardLoadedItem, ClipboardError>] = []
        let handle = executor.start(.file(utType: UTType.data.identifier), from: Self.fileProvider(source)) {
            deliveries.append($0)
        }
        handle.cancel()
        try? await Task.sleep(nanoseconds: 400_000_000)

        #expect(deliveries.count == 1)
        #expect(sessionDirectoryIsEmpty(fileStore))
    }

    @Test func timingOutAFileLoadLeavesNoTemporaryFileBehind() async throws {
        let timeouts = ClipboardTimeouts(detection: 30, providerLoad: 0.05, imageCoding: 30)!
        let fileStore = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let executor = makeExecutor(fileStore: fileStore, timeouts: timeouts)
        let source = try Self.writeTemporaryFile(byteCount: 4_096)
        defer { try? FileManager.default.removeItem(at: source) }

        // A wide margin (0.05s timeout vs 2s delivery): the timeout fires from a main-actor Task,
        // so a narrow gap can invert under main-actor contention from parallel suites.
        let provider = Self.delayedFileProvider(source, delay: 2.0)
        let result = await withCheckedContinuation { continuation in
            executor.start(.file(utType: UTType.data.identifier), from: provider) {
                continuation.resume(returning: $0)
            }
        }
        guard case .failure(let error) = result else { Issue.record("expected failure"); return }
        #expect(error == .timedOut(operation: .providerLoad))
        // Any copy that lands after the timeout must still be discarded.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(sessionDirectoryIsEmpty(fileStore))
    }

    @Test func textLoadSucceeds() async {
        let executor = makeExecutor()
        let provider = NSItemProvider(object: "hello" as NSString)
        let result = await withCheckedContinuation { continuation in
            executor.start(.text, from: provider) { continuation.resume(returning: $0) }
        }
        #expect(result == .success(.text("hello")))
    }

    @Test func textLoadRejectsPayloadOverLoadLimit() async {
        let limits = ClipboardLimits(maxCopyByteCount: 1_000, maxLoadByteCount: 4, maxImagePixelCount: 1_000)!
        let executor = makeExecutor(limits: limits)
        let provider = NSItemProvider(object: String(repeating: "a", count: 64) as NSString)
        let result = await withCheckedContinuation { continuation in
            executor.start(.text, from: provider) { continuation.resume(returning: $0) }
        }
        guard case .failure(let error) = result else {
            Issue.record("expected failure"); return
        }
        #expect(error.errorCode == ClipboardError.contentTooLarge(byteCount: 64, limit: 4).errorCode)
    }

    @Test func urlLoadRejectsPayloadOverLoadLimit() async {
        let limits = ClipboardLimits(maxCopyByteCount: 1_000, maxLoadByteCount: 4, maxImagePixelCount: 1_000)!
        let executor = makeExecutor(limits: limits)
        let provider = NSItemProvider(object: NSURL(string: "https://example.com/a-fairly-long-path")!)
        let result = await withCheckedContinuation { continuation in
            executor.start(.url, from: provider) { continuation.resume(returning: $0) }
        }
        guard case .failure(let error) = result else {
            Issue.record("expected failure"); return
        }
        #expect(error.errorCode == ClipboardError.contentTooLarge(byteCount: 1, limit: 4).errorCode)
    }

    @Test func cancelDeliversCancelledExactlyOnce() async {
        let executor = makeExecutor()
        let provider = NSItemProvider(object: "hello" as NSString)
        var deliveries: [Result<ClipboardLoadedItem, ClipboardError>] = []
        let handle = executor.start(.text, from: provider) { deliveries.append($0) }
        handle.cancel()
        handle.cancel()
        // Give any in-flight provider completion a chance to land after cancellation.
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(deliveries.count == 1)
        if case .failure(let error) = deliveries.first {
            #expect(error == .cancelled)
        } else {
            Issue.record("expected a single .cancelled delivery")
        }
    }

    @Test func timeoutDeliversTimedOutForANeverCompletingProvider() async {
        let timeouts = ClipboardTimeouts(detection: 30, providerLoad: 0.05, imageCoding: 30)!
        let executor = makeExecutor(timeouts: timeouts)
        let provider = NSItemProvider()
        // Registers a representation whose load handler never calls back.
        provider.registerDataRepresentation(for: .plainText) { _ in nil }

        let result = await withCheckedContinuation { continuation in
            executor.start(.text, from: provider) { continuation.resume(returning: $0) }
        }
        guard case .failure(let error) = result else {
            Issue.record("expected failure"); return
        }
        #expect(error == .timedOut(operation: .providerLoad))
    }
}
