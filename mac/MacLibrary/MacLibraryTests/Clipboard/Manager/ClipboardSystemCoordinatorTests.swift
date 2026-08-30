//
//  ClipboardSystemCoordinatorTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("ClipboardSystemCoordinator")
@MainActor
struct ClipboardSystemCoordinatorTests {

    private func makeCoordinator() -> (ClipboardSystemCoordinator, MockFilePromiseSnapshotter) {
        let snapshotter = MockFilePromiseSnapshotter()
        let base = URL(filePath: "/tmp/ClipboardPromiseTests/\(UUID().uuidString)")
        return (ClipboardSystemCoordinator(snapshotter: snapshotter, stagingBase: base), snapshotter)
    }

    private func request() -> FilePromiseRequest {
        FilePromiseRequest(fileTypeIdentifier: "public.plain-text", fileName: "note.txt",
                           source: .writer { _ in })
    }

    // MARK: - Lazy providers

    @Test("a lazy provider is held until released")
    func lazyProviderLifecycle() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.registerLazyProvider(types: ["public.png"]) { _ in nil }

        #expect(coordinator.registeredLazyProviderCount == 1)
        coordinator.releaseLazyProvider(handle)
        #expect(coordinator.registeredLazyProviderCount == 0)
    }

    @Test("releasing a lazy provider twice is a no-op")
    func lazyProviderReleaseIsIdempotent() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.registerLazyProvider(types: ["public.png"]) { _ in nil }

        coordinator.releaseLazyProvider(handle)
        coordinator.releaseLazyProvider(handle)
        coordinator.releaseLazyProvider(PasteboardPromiseHandle())

        #expect(coordinator.registeredLazyProviderCount == 0)
    }

    // MARK: - File promise registration

    @Test("a reserved handle is not registered yet")
    func reserveDoesNotRegister() {
        let (coordinator, _) = makeCoordinator()
        _ = coordinator.reserveFilePromiseHandle()
        // The handle exists only so a staging path can be derived before registration.
        #expect(coordinator.registeredFilePromiseCount == 0)
    }

    @Test("reserved handles are distinct")
    func reservedHandlesAreDistinct() {
        let (coordinator, _) = makeCoordinator()
        #expect(coordinator.reserveFilePromiseHandle() != coordinator.reserveFilePromiseHandle())
    }

    @Test("the staging root is derived from the handle")
    func stagingRootUsesHandle() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        // Deriving rather than storing is what lets the copy happen before registration.
        #expect(coordinator.stagingRoot(for: handle).lastPathComponent == handle.id.uuidString)
    }

    @Test("registering stores the promise")
    func registerStoresPromise() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()

        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)

        #expect(coordinator.registeredFilePromiseCount == 1)
        #expect(coordinator.lifecycleState(for: handle) != nil)
    }

    @Test("a provisional promise has no ownership yet")
    func provisionalHasNoOwnership() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)

        #expect(coordinator.lifecycleState(for: handle)?.activatedOwnership() == nil)
    }

    @Test("activating records the ownership")
    func activateRecordsOwnership() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)

        coordinator.activateFilePromise(handle,
                                        ownership: PasteboardOwnership(scope: .general, changeCount: 7))

        #expect(coordinator.lifecycleState(for: handle)?.activatedOwnership()?.changeCount == 7)
    }

    @Test("activating an unknown handle is a no-op")
    func activateUnknownHandle() {
        let (coordinator, _) = makeCoordinator()
        coordinator.activateFilePromise(FilePromiseHandle(),
                                        ownership: PasteboardOwnership(scope: .general, changeCount: 1))
        #expect(coordinator.registeredFilePromiseCount == 0)
    }

    // MARK: - Release

    @Test("releasing removes the promise")
    func releaseRemovesPromise() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)

        coordinator.releaseFilePromise(handle)

        #expect(coordinator.registeredFilePromiseCount == 0)
    }

    @Test("releasing is idempotent for known, unknown and repeated handles")
    func releaseIsIdempotent() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)

        coordinator.releaseFilePromise(handle)
        coordinator.releaseFilePromise(handle)
        coordinator.releaseFilePromise(FilePromiseHandle())

        #expect(coordinator.registeredFilePromiseCount == 0)
    }

    @Test("a release requested during a write waits for the write to finish")
    func releaseWaitsForInFlightWrite() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)
        let state = try! #require(coordinator.lifecycleState(for: handle))

        #expect(state.beginWrite() == .proceed)
        coordinator.releaseFilePromise(handle)

        // Removing it now would leave the in-flight write writing into a promise nobody owns
        // (R6-L11).
        #expect(coordinator.registeredFilePromiseCount == 1)
    }

    @Test("a writer backed release deletes no staging directory")
    func writerReleaseDiscardsNothing() async {
        let (coordinator, snapshotter) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)

        coordinator.releaseFilePromise(handle)
        // A nil staging URL is not the same as "do not release": the promise is gone, there is
        // simply nothing on disk to remove.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(snapshotter.discardCallCount == 0)
        #expect(coordinator.registeredFilePromiseCount == 0)
    }

    @Test("a snapshot backed release deletes its staging directory")
    func snapshotReleaseDiscardsStaging() async throws {
        let (coordinator, snapshotter) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        let root = coordinator.stagingRoot(for: handle)
        _ = coordinator.registerFilePromise(request(), reserved: handle,
                                            stagingURL: root.appending(path: "note.txt"))

        coordinator.releaseFilePromise(handle)

        // The deletion is dispatched off the main actor, so give it a moment to land.
        try await Task.sleep(for: .milliseconds(50))
        #expect(snapshotter.discardCallCount == 1)
        // The root, not the file inside it: otherwise an empty directory survives per promise.
        #expect(snapshotter.discardedURLs == [root])
    }

    // MARK: - Stale monitoring

    @Test("no timer runs until a stale query is attached")
    func timerStartsOnAttach() {
        let (coordinator, _) = makeCoordinator()
        #expect(!coordinator.isStaleTimerRunning)

        coordinator.attachStaleQuery { _ in 0 }

        #expect(coordinator.isStaleTimerRunning)
    }

    @Test("a tick without a stale query does nothing")
    func tickWithoutQueryIsNoOp() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)
        coordinator.activateFilePromise(handle,
                                        ownership: PasteboardOwnership(scope: .general, changeCount: 1))

        coordinator.checkForStalePromises()

        // A promise cannot be judged stale without a way to read the current change count
        // (R6-H3).
        #expect(coordinator.registeredFilePromiseCount == 1)
    }

    @Test("a provisional promise is never judged stale")
    func provisionalIsNotStale() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)
        // Deliberately not activated: nothing has reached a pasteboard, so there is no
        // ownership to compare (R5-H3).
        coordinator.attachStaleQuery { _ in 999 }

        coordinator.checkForStalePromises()

        #expect(coordinator.registeredFilePromiseCount == 1)
    }

    @Test("an unchanged pasteboard leaves the promise registered")
    func matchingChangeCountKeepsPromise() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)
        coordinator.activateFilePromise(handle,
                                        ownership: PasteboardOwnership(scope: .general, changeCount: 7))
        coordinator.attachStaleQuery { _ in 7 }

        coordinator.checkForStalePromises()

        #expect(coordinator.registeredFilePromiseCount == 1)
    }

    @Test("a pasteboard taken over by another app releases the promise")
    func changedChangeCountReleasesPromise() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)
        coordinator.activateFilePromise(handle,
                                        ownership: PasteboardOwnership(scope: .general, changeCount: 7))
        coordinator.attachStaleQuery { _ in 8 }

        coordinator.checkForStalePromises()

        // The promise can never be fulfilled now, so holding it would leak its staging.
        #expect(coordinator.registeredFilePromiseCount == 0)
    }

    @Test("a scope that no longer resolves counts as stale")
    func unresolvableScopeIsStale() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)
        coordinator.activateFilePromise(handle,
                                        ownership: PasteboardOwnership(scope: .named("gone"), changeCount: 1))
        coordinator.attachStaleQuery { _ in throw ClipboardError.invalidPasteboardName("gone") }

        coordinator.checkForStalePromises()

        // A throwing query means the pasteboard is gone, which is staleness rather than an
        // error to report (R6-H3).
        #expect(coordinator.registeredFilePromiseCount == 0)
    }

    @Test("a stale promise with a write in flight is not removed")
    func staleWithInFlightWriteSurvives() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(request(), reserved: handle, stagingURL: nil)
        coordinator.activateFilePromise(handle,
                                        ownership: PasteboardOwnership(scope: .general, changeCount: 7))
        let state = try! #require(coordinator.lifecycleState(for: handle))
        #expect(state.beginWrite() == .proceed)
        coordinator.attachStaleQuery { _ in 8 }

        coordinator.checkForStalePromises()

        #expect(coordinator.registeredFilePromiseCount == 1)
    }

    // MARK: - Receive sessions

    @Test("registering a session stores it")
    func registerReceipt() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveReceiptHandle()

        coordinator.registerReceipt(reserved: handle, policy: .default) { _ in }

        #expect(coordinator.registeredReceiptCount == 1)
    }

    @Test("cancelling delivers exactly one terminal event")
    func cancelDeliversOnce() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveReceiptHandle()
        var events: [FilePromiseReceiptEvent] = []
        coordinator.registerReceipt(reserved: handle, policy: .default) { events.append($0) }

        coordinator.cancelReceipt(handle)
        coordinator.cancelReceipt(handle)

        #expect(events.count == 1)
        if case .finished(let receipt) = events[0] {
            #expect(receipt.terminatedBy == .cancelled)
        } else {
            Issue.record("expected a finished event, got \(events)")
        }
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("cancelling an unknown session delivers nothing")
    func cancelUnknownReceipt() {
        let (coordinator, _) = makeCoordinator()
        coordinator.cancelReceipt(FilePromiseReceiptHandle())
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("terminating without delivery emits no event")
    func terminateWithoutDelivery() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveReceiptHandle()
        var events: [FilePromiseReceiptEvent] = []
        coordinator.registerReceipt(reserved: handle, policy: .default) { events.append($0) }

        coordinator.terminateReceiptWithoutDelivery(handle)

        // The consumer is already gone, so there is nowhere to deliver (R6-M5).
        #expect(events.isEmpty)
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("discarding after a start failure emits no event")
    func discardAfterStartFailure() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveReceiptHandle()
        var events: [FilePromiseReceiptEvent] = []
        coordinator.registerReceipt(reserved: handle, policy: .default) { events.append($0) }

        coordinator.discardReceiptAfterStartFailure(handle)

        // A session that never started must produce no event at all (R5-H4).
        #expect(events.isEmpty)
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("finalizing removes the session after its terminal event")
    func finalizeRemovesSession() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveReceiptHandle()
        coordinator.registerReceipt(reserved: handle, policy: .default) { _ in }

        coordinator.finalizeReceipt(handle)

        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("cancelling after termination without delivery is silent")
    func cancelAfterTerminationIsSilent() {
        let (coordinator, _) = makeCoordinator()
        let handle = coordinator.reserveReceiptHandle()
        var events: [FilePromiseReceiptEvent] = []
        coordinator.registerReceipt(reserved: handle, policy: .default) { events.append($0) }

        coordinator.terminateReceiptWithoutDelivery(handle)
        coordinator.cancelReceipt(handle)

        #expect(events.isEmpty)
    }
}
