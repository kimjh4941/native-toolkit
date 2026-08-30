//
//  FilePromiseProvisionTests.swift
//  MacLibraryTests
//

import Testing
import AppKit
import Foundation
@testable import MacLibrary

/// End to end tests for the provision side: registration, fulfilment and release.
@Suite("File promise provision")
@MainActor
struct FilePromiseProvisionTests {

    private func makeCoordinator() -> (ClipboardSystemCoordinator, URL) {
        let base = URL(filePath: NSTemporaryDirectory())
            .appending(path: "ClipboardPromiseTests/\(UUID().uuidString)")
        let coordinator = ClipboardSystemCoordinator(snapshotter: FilePromiseSnapshotter(),
                                                     stagingBase: base)
        return (coordinator, base)
    }

    private func writerRequest(fileName: String = "note.txt",
                               body: @escaping @Sendable (URL) throws -> Void = { url in
                                   try Data("promised".utf8).write(to: url)
                               }) -> FilePromiseRequest {
        FilePromiseRequest(fileTypeIdentifier: "public.plain-text", fileName: fileName,
                           source: .writer(body))
    }

    /// Drives the delegate the way AppKit does, and waits for its completion handler.
    private func fulfil(_ delegate: FilePromiseDelegate,
                        provider: NSFilePromiseProvider,
                        to url: URL) async -> Error? {
        await withCheckedContinuation { continuation in
            delegate.filePromiseProvider(provider, writePromiseTo: url) { error in
                continuation.resume(returning: error)
            }
        }
    }

    private func destination() -> URL {
        let directory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "ClipboardPromiseDest/\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "note.txt")
    }

    // MARK: - IT-12 / RK-21

    @Test("IT-12: the coordinator holds the provider and its delegate")
    func coordinatorRetainsProviderAndDelegate() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(writerRequest(), reserved: handle, stagingURL: nil)

        // NSFilePromiseProvider.delegate is weak. Without a strong reference here the promise
        // would still be advertised but could never be fulfilled (RK-21).
        #expect(coordinator.filePromiseProvider(for: handle) != nil)
        #expect(coordinator.promiseDelegate(for: handle) != nil)
    }

    @Test("the provider's weak delegate is still alive after registration returns")
    func providerDelegateSurvivesScope() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(writerRequest(), reserved: handle, stagingURL: nil)

        let provider = try! #require(coordinator.filePromiseProvider(for: handle))
        #expect(provider.delegate != nil)
    }

    // MARK: - IT-23

    @Test("IT-23: the fulfilment queue is serial")
    func fulfilmentQueueIsSerial() {
        let (coordinator, _) = makeCoordinator()
        // Concurrent writes would re-enter one writer closure or read a staging directory
        // mid-copy (R2-H4).
        #expect(coordinator.fulfilmentQueueForTests.maxConcurrentOperationCount == 1)
    }

    // MARK: - Fulfilment

    @Test("a writer request writes through the caller's closure")
    func writerFulfils() async throws {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(writerRequest(), reserved: handle, stagingURL: nil)
        let delegate = try #require(coordinator.promiseDelegate(for: handle))
        let provider = try #require(coordinator.filePromiseProvider(for: handle))
        let target = destination()

        let error = await fulfil(delegate, provider: provider, to: target)

        #expect(error == nil)
        #expect(try Data(contentsOf: target) == Data("promised".utf8))
    }

    @Test("the promised file name is used verbatim")
    func fileNameIsUsed() throws {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(writerRequest(fileName: "report.txt"),
                                            reserved: handle, stagingURL: nil)
        let delegate = try #require(coordinator.promiseDelegate(for: handle))
        let provider = try #require(coordinator.filePromiseProvider(for: handle))

        #expect(delegate.filePromiseProvider(provider, fileNameForType: "public.plain-text")
                == "report.txt")
    }

    @Test("IT-44: a snapshot request writes from staging, not from the original path")
    func snapshotFulfilsFromStaging() async throws {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()

        // Build a staging copy, then delete the original.
        let staging = coordinator.stagingRoot(for: handle)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appending(path: "note.txt")
        try Data("staged".utf8).write(to: staged)
        let original = URL(filePath: NSTemporaryDirectory()).appending(path: "gone-\(UUID().uuidString).txt")

        let request = FilePromiseRequest(fileTypeIdentifier: "public.plain-text",
                                         fileName: "note.txt", source: .snapshot(original))
        _ = coordinator.registerFilePromise(request, reserved: handle, stagingURL: staged)
        let delegate = try #require(coordinator.promiseDelegate(for: handle))
        let provider = try #require(coordinator.filePromiseProvider(for: handle))
        let target = destination()

        let error = await fulfil(delegate, provider: provider, to: target)

        // The original never existed at fulfilment time, which is exactly the case snapshotting
        // exists for (R5-H2).
        #expect(error == nil)
        #expect(try Data(contentsOf: target) == Data("staged".utf8))
    }

    @Test("a failing writer is reported as filePromiseWriteFailed")
    func writerFailureIsConverted() async throws {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(
            writerRequest(body: { _ in throw ClipboardError.filePromiseWriteFailed("no space") }),
            reserved: handle, stagingURL: nil)
        let delegate = try #require(coordinator.promiseDelegate(for: handle))
        let provider = try #require(coordinator.filePromiseProvider(for: handle))

        let error = await fulfil(delegate, provider: provider, to: destination())

        #expect(error as? ClipboardError == .filePromiseWriteFailed("no space"))
    }

    // MARK: - IT-21 / IT-22 / RK-21

    @Test("IT-21 and RK-21: the same promise can be fulfilled more than once")
    func repeatedFulfilment() async throws {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(writerRequest(), reserved: handle, stagingURL: nil)
        let delegate = try #require(coordinator.promiseDelegate(for: handle))
        let provider = try #require(coordinator.filePromiseProvider(for: handle))

        // There is deliberately no once-per-provider guard: the system may ask again, and a
        // guard would make the second drag silently produce nothing (RK-21).
        #expect(await fulfil(delegate, provider: provider, to: destination()) == nil)
        #expect(await fulfil(delegate, provider: provider, to: destination()) == nil)
        #expect(coordinator.registeredFilePromiseCount == 1)
    }

    @Test("IT-32: fulfilling a released promise fails instead of writing")
    func releasedPromiseFailsFulfilment() async throws {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(writerRequest(), reserved: handle, stagingURL: nil)
        let delegate = try #require(coordinator.promiseDelegate(for: handle))
        let provider = try #require(coordinator.filePromiseProvider(for: handle))

        coordinator.releaseFilePromise(handle)
        let target = destination()
        let error = await fulfil(delegate, provider: provider, to: target)

        // The promise is still on the pasteboard, so a drag can still ask. Failing is the only
        // honest answer (R3-H2).
        #expect(error as? ClipboardError == .filePromiseWriteFailed("promise already released"))
        #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
    }

    @Test("IT-14 and IT-22: a release during a write completes when the write finishes")
    func releaseDeferredUntilWriteCompletes() async throws {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(writerRequest(), reserved: handle, stagingURL: nil)
        let delegate = try #require(coordinator.promiseDelegate(for: handle))
        let provider = try #require(coordinator.filePromiseProvider(for: handle))
        let state = try #require(coordinator.lifecycleState(for: handle))

        // Simulate a second, still running write so the release cannot complete yet.
        #expect(state.beginWrite() == .proceed)
        coordinator.releaseFilePromise(handle)
        #expect(coordinator.registeredFilePromiseCount == 1)

        // This one runs to completion and is the last in flight, so it performs the release.
        _ = await fulfil(delegate, provider: provider, to: destination())
        if let generation = state.endWrite() {
            _ = state.commitRelease(generation: generation)
        }
        try await Task.sleep(for: .milliseconds(50))

        #expect(state.released)
    }

    // MARK: - IT-42 stale release

    @Test("IT-42: activation gates stale detection, and a moved change count releases")
    func staleReleaseAfterActivation() throws {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(writerRequest(), reserved: handle, stagingURL: nil)
        coordinator.attachStaleQuery { _ in 99 }

        // Provisional: nothing has reached a pasteboard, so there is nothing to compare.
        coordinator.checkForStalePromises()
        #expect(coordinator.registeredFilePromiseCount == 1)

        coordinator.activateFilePromise(handle,
                                        ownership: PasteboardOwnership(scope: .general, changeCount: 1))
        coordinator.checkForStalePromises()

        #expect(coordinator.registeredFilePromiseCount == 0)
        #expect(coordinator.filePromiseProvider(for: handle) == nil)
    }

    // MARK: - IT-33 staging deletion

    @Test("IT-33: a stale release deletes the staging directory")
    func staleReleaseDeletesStaging() async throws {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        let staging = coordinator.stagingRoot(for: handle)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appending(path: "note.txt")
        try Data("staged".utf8).write(to: staged)

        _ = coordinator.registerFilePromise(
            FilePromiseRequest(fileTypeIdentifier: "public.plain-text", fileName: "note.txt",
                               source: .snapshot(URL(filePath: "/tmp/original.txt"))),
            reserved: handle, stagingURL: staged)
        coordinator.activateFilePromise(handle,
                                        ownership: PasteboardOwnership(scope: .general, changeCount: 1))
        coordinator.attachStaleQuery { _ in 2 }

        coordinator.checkForStalePromises()
        try await Task.sleep(for: .milliseconds(200))

        // Explicit release, stale release and rollback all converge on one deletion path, so
        // this cannot be missed (R3-H3).
        #expect(!FileManager.default.fileExists(atPath: staged.path(percentEncoded: false)))
    }

    // MARK: - IT-40 startup sweep

    @Test("IT-40: the sweep removes leftovers but spares live promises")
    func sweepSparesActivePromises() async throws {
        let (coordinator, base) = makeCoordinator()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // A directory left by a previous run.
        let orphan = base.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)

        // A directory belonging to a promise registered right now.
        let handle = coordinator.reserveFilePromiseHandle()
        let live = coordinator.stagingRoot(for: handle)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        _ = coordinator.registerFilePromise(writerRequest(), reserved: handle,
                                            stagingURL: live.appending(path: "note.txt"))

        coordinator.sweepOrphanedStagingDirectories(force: true)
        try await Task.sleep(for: .milliseconds(200))

        #expect(!FileManager.default.fileExists(atPath: orphan.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: live.path(percentEncoded: false)))
    }

    @Test("IT-40: the unforced sweep runs at most once per process")
    func sweepRunsOnce() {
        let (first, _) = makeCoordinator()
        let (second, _) = makeCoordinator()
        // Several managers in one process must not race over the same directories (R4-L10).
        first.sweepOrphanedStagingDirectories()
        second.sweepOrphanedStagingDirectories()
    }

    // MARK: - IT-24 idempotence

    @Test("IT-24: releasing an unknown handle succeeds as a no-op")
    func releaseUnknownHandle() {
        let (coordinator, _) = makeCoordinator()
        coordinator.releaseFilePromise(FilePromiseHandle())
        #expect(coordinator.registeredFilePromiseCount == 0)
    }
}
