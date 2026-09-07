//
//  PasteItemProviderLoaderTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import IosLibrary

@MainActor
struct PasteItemProviderLoaderTests {

    private func makeLoader(
        limits: ClipboardLimits = .default,
        timeouts: ClipboardTimeouts = .default
    ) -> PasteItemProviderLoader {
        PasteItemProviderLoader(
            fileStore: ClipboardTemporaryFileStore(sessionID: UUID().uuidString),
            limits: limits,
            timeouts: timeouts
        )
    }

    private func textProvider(_ value: String) -> NSItemProvider {
        NSItemProvider(object: value as NSString)
    }

    @Test func allProvidersSucceedAndPreserveInputOrder() async {
        let loader = makeLoader()
        let providers = [textProvider("first"), textProvider("second"), textProvider("third")]
        let result = await withCheckedContinuation { continuation in
            loader.load(providers: providers, acceptedTypes: [UTType.plainText.identifier]) {
                continuation.resume(returning: $0)
            }
        }
        #expect(result.failures.isEmpty)
        #expect(result.items == [.text("first"), .text("second"), .text("third")])
    }

    @Test func mixedSuccessAndFailureIsAggregated() async {
        let loader = makeLoader()
        let unusable = NSItemProvider()  // advertises nothing the caller accepts
        let providers = [textProvider("ok"), unusable]
        let result = await withCheckedContinuation { continuation in
            loader.load(providers: providers, acceptedTypes: [UTType.plainText.identifier]) {
                continuation.resume(returning: $0)
            }
        }
        #expect(result.items == [.text("ok")])
        #expect(result.failures.count == 1)
    }

    @Test func allFailuresProduceEmptyItems() async {
        let loader = makeLoader()
        let result = await withCheckedContinuation { continuation in
            loader.load(providers: [NSItemProvider(), NSItemProvider()], acceptedTypes: [UTType.plainText.identifier]) {
                continuation.resume(returning: $0)
            }
        }
        #expect(result.items.isEmpty)
        #expect(result.failures.count == 2)
    }

    @Test func emptyProviderArrayReportsBothCollectionsEmpty() async {
        // U-83: an empty array is neither a success nor a per-provider failure. Mapping it onto
        // `.noMatchingItem` is the receiver view's job (U-89), not the loader's.
        let loader = makeLoader()
        let result = await withCheckedContinuation { continuation in
            loader.load(providers: [], acceptedTypes: [UTType.plainText.identifier]) {
                continuation.resume(returning: $0)
            }
        }
        #expect(result.items.isEmpty)
        #expect(result.failures.isEmpty)
        #expect(result.isCancelled == false)
    }

    @Test func acceptedTypesConstrainTheReturnedKind() async {
        // A text-only provider must not satisfy an image-only paste configuration.
        let loader = makeLoader()
        let result = await withCheckedContinuation { continuation in
            loader.load(providers: [textProvider("hi")], acceptedTypes: [UTType.image.identifier]) {
                continuation.resume(returning: $0)
            }
        }
        #expect(result.items.isEmpty)
        #expect(result.failures == [.noMatchingItem])
    }

    @Test func cancelAllDeliversCancelledToTheInternalCompletionExactlyOnce() async {
        // U-84: the internal completion keeps the S6 exactly-once contract on cancellation too.
        // Suppressing the *UI* callback (U-90) is the receiver view's job, not the loader's.
        let loader = makeLoader()
        var results: [PasteItemProviderLoader.AggregateResult] = []
        loader.load(providers: [textProvider("hi")], acceptedTypes: [UTType.plainText.identifier]) {
            results.append($0)
        }
        loader.cancelAll()
        loader.cancelAll()
        // Give the already in-flight provider completion a chance to land after cancellation.
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(results.count == 1)
        #expect(results.first?.isCancelled == true)
        #expect(results.first?.failures == [.cancelled])
        #expect(results.first?.items.isEmpty == true)
    }

    @Test func cancelAllLeavesNoTemporaryDirectoryBehind() async throws {
        // U-84 (second half): a cancelled session must not leak files into the session directory.
        let fileStore = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let loader = PasteItemProviderLoader(fileStore: fileStore)
        let fileURL = try Self.makeTemporaryFile(byteCount: 16)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        loader.load(providers: [Self.fileProvider(fileURL)], acceptedTypes: [UTType.data.identifier]) { _ in }
        loader.cancelAll()
        try? await Task.sleep(nanoseconds: 400_000_000)

        let remaining = try? FileManager.default.contentsOfDirectory(
            at: fileStore.sessionDirectory, includingPropertiesForKeys: nil
        )
        #expect((remaining ?? []).isEmpty)
    }

    @Test func newLoadSupersedesThePendingSession() async {
        let loader = makeLoader()
        var firstResults: [PasteItemProviderLoader.AggregateResult] = []
        loader.load(providers: [textProvider("first")], acceptedTypes: [UTType.plainText.identifier]) {
            firstResults.append($0)
        }
        let second = await withCheckedContinuation { continuation in
            loader.load(providers: [textProvider("second")], acceptedTypes: [UTType.plainText.identifier]) {
                continuation.resume(returning: $0)
            }
        }
        #expect(second.items == [.text("second")])
        #expect(second.isCancelled == false)
        // The superseded session is cancelled, and says so, exactly once.
        #expect(firstResults.count == 1)
        #expect(firstResults.first?.isCancelled == true)
    }

    @Test func releasingTheLoaderCancelsPendingLoadsAndDiscardsLateFiles() async throws {
        // D-16 / U-95: the raw `PasteControlFactory` path has no container to drive cleanup, so
        // the loader's own `isolated deinit` must cancel. Without it, a file load that lands after
        // the owning view is released is neither delivered nor discarded.
        final class Recorder { var results: [PasteItemProviderLoader.AggregateResult] = [] }
        let recorder = Recorder()
        let fileStore = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let source = try Self.makeTemporaryFile(byteCount: 64)
        defer { try? FileManager.default.removeItem(at: source) }

        var loader: PasteItemProviderLoader? = PasteItemProviderLoader(fileStore: fileStore)
        loader?.load(
            providers: [Self.delayedFileProvider(source, delay: 1.0)],
            acceptedTypes: [UTType.data.identifier]
        ) { recorder.results.append($0) }
        loader = nil

        #expect(recorder.results.count == 1)
        #expect(recorder.results.first?.isCancelled == true)
        #expect(recorder.results.first?.failures == [.cancelled])

        // Let the provider's delayed file representation land after the loader is gone.
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let remaining = try? FileManager.default.contentsOfDirectory(
            at: fileStore.sessionDirectory, includingPropertiesForKeys: nil
        )
        #expect((remaining ?? []).isEmpty)
    }

    // MARK: - Helpers

    private static func makeTemporaryFile(byteCount: Int) throws -> URL {
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

    /// A file provider whose representation lands only after `delay`, so the test can release the
    /// loader while the load is genuinely still in flight.
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

    @Test func providerTimeoutIsReportedAsFailure() async {
        let timeouts = ClipboardTimeouts(detection: 30, providerLoad: 0.05, imageCoding: 30)!
        let loader = makeLoader(timeouts: timeouts)
        let stalled = NSItemProvider()
        stalled.registerDataRepresentation(for: .plainText) { _ in nil }

        let result = await withCheckedContinuation { continuation in
            loader.load(providers: [stalled], acceptedTypes: [UTType.plainText.identifier]) {
                continuation.resume(returning: $0)
            }
        }
        #expect(result.items.isEmpty)
        #expect(result.failures == [.timedOut(operation: .providerLoad)])
    }
}
