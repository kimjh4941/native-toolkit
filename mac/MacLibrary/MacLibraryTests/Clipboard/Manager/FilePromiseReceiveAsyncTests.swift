//
//  FilePromiseReceiveAsyncTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

/// The stream and aggregating forms of OP-18, and the race between their two endings.
@Suite("File promise receive async forms")
@MainActor
struct FilePromiseReceiveAsyncTests {

    private func makeManager() -> (MacClipboardManager, MockClipboardRepository,
                                   ClipboardSystemCoordinator) {
        let repository = MockClipboardRepository()
        let snapshotter = MockFilePromiseSnapshotter()
        let coordinator = ClipboardSystemCoordinator(
            snapshotter: snapshotter,
            stagingBase: URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString))
        let useCases = ClipboardUseCases(repository: repository,
                                         registry: coordinator,
                                         snapshotter: snapshotter,
                                         typeValidator: MockClipboardTypeIdentifierValidating())
        return (MacClipboardManager(coordinator: coordinator, useCases: useCases,
                                    repository: repository), repository, coordinator)
    }

    private func destination() -> URL {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Stream form

    @Test("IT-30: a start failure throws instead of producing a stream")
    func startFailureThrowsWithoutStream() {
        let (manager, repository, coordinator) = makeManager()
        repository.shouldFail = .destinationNotWritable("dest")

        #expect(throws: ClipboardError.destinationNotWritable("dest")) {
            _ = try manager.receiveFilePromiseEvents(destinationDirectory: self.destination())
        }
        // No stream means no element to misread as an error, and no session to leak (R3-H1).
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("IT-35: the stream publishes the handle that cancels it")
    func streamPublishesItsHandle() async throws {
        let (manager, _, _) = makeManager()
        let subscription = try manager.receiveFilePromiseEvents(destinationDirectory: destination())

        manager.cancelReceiveFilePromises(subscription.handle)

        var events: [FilePromiseReceiptEvent] = []
        for await event in subscription.events { events.append(event) }

        // Without the handle the consumer could not cancel the session it is reading (R4-H1).
        #expect(events.count == 1)
        if case .finished(let receipt) = events[0] {
            #expect(receipt.terminatedBy == .cancelled)
        } else {
            Issue.record("expected a finished event, got \(events)")
        }
    }

    @Test("the stream ends after the terminal event")
    func streamFinishesAfterTerminal() async throws {
        let (manager, _, coordinator) = makeManager()
        let subscription = try manager.receiveFilePromiseEvents(destinationDirectory: destination())
        let session = try #require(coordinator.receiptSession(for: subscription.handle))

        session.recordReceived(URL(filePath: "/tmp/a.txt"), generation: session.generation)
        session.finish(terminatedBy: .quiescence)

        var events: [FilePromiseReceiptEvent] = []
        for await event in subscription.events { events.append(event) }

        #expect(events.count == 2)
    }

    @Test("IT-27: abandoning the stream tears the session down without delivering")
    func abandonedStreamCleansUpSilently() async throws {
        let (manager, _, coordinator) = makeManager()
        var handle: FilePromiseReceiptHandle?
        var collected: [FilePromiseReceiptEvent] = []

        do {
            let subscription = try manager.receiveFilePromiseEvents(
                destinationDirectory: destination())
            handle = subscription.handle
            // Drop the stream without consuming it. onTermination runs *after* the stream has
            // ended, so a terminal yielded from there could never reach anyone (R3-H1).
            for await event in subscription.events.prefix(0) { collected.append(event) }
        }
        try await Task.sleep(for: .milliseconds(150))

        #expect(collected.isEmpty)
        #expect(coordinator.registeredReceiptCount == 0)
        // The session is gone, so a later cancel on the same handle finds nothing to end.
        let abandoned = try #require(handle)
        manager.cancelReceiveFilePromises(abandoned)
        #expect(coordinator.receiptSession(for: abandoned) == nil)
    }

    // MARK: - Aggregating form

    @Test("the aggregating form returns the receipt")
    func aggregateReturnsReceipt() async throws {
        let (manager, _, coordinator) = makeManager()
        let directory = destination()

        async let receipt = manager.receiveFilePromises(destinationDirectory: directory)
        try await Task.sleep(for: .milliseconds(50))
        let handle = try #require(coordinator.firstReceiptHandleForTests)
        let session = try #require(coordinator.receiptSession(for: handle))
        session.recordReceived(URL(filePath: "/tmp/a.txt"), generation: session.generation)
        session.finish(terminatedBy: .quiescence)

        let value = try await receipt
        #expect(value.urls == [URL(filePath: "/tmp/a.txt")])
        #expect(value.terminatedBy == .quiescence)
    }

    @Test("IT-26 and R2-M6: a timeout returns a partial receipt rather than throwing")
    func timeoutReturnsPartialReceipt() async throws {
        let (manager, _, coordinator) = makeManager()

        async let receipt = manager.receiveFilePromises(destinationDirectory: destination())
        try await Task.sleep(for: .milliseconds(50))
        let handle = try #require(coordinator.firstReceiptHandleForTests)
        let session = try #require(coordinator.receiptSession(for: handle))
        session.recordReceived(URL(filePath: "/tmp/a.txt"), generation: session.generation)
        session.finish(terminatedBy: .overallTimeout)

        // Throwing here would discard files that were successfully received.
        let value = try await receipt
        #expect(value.terminatedBy == .overallTimeout)
        #expect(value.urls.count == 1)
    }

    @Test("a start failure throws from the aggregating form")
    func aggregateStartFailureThrows() async {
        let (manager, repository, _) = makeManager()
        repository.shouldFail = .destinationNotWritable("dest")

        await #expect(throws: ClipboardError.destinationNotWritable("dest")) {
            _ = try await manager.receiveFilePromises(destinationDirectory: self.destination())
        }
    }

    // MARK: - CT-13 to CT-16

    @Test("CT-15: cancelling the task reports CancellationError, not a domain error")
    func taskCancellationThrowsCancellationError() async throws {
        let (manager, _, _) = makeManager()
        let directory = destination()

        let task = Task { @MainActor in
            try await manager.receiveFilePromises(destinationDirectory: directory)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // R5-M10: a cancelled task is standard cancellation, not ClipboardError.cancelled.
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test("CT-14: cancellation cleans the session up despite the actor hop")
    func cancellationCleansUp() async throws {
        let (manager, _, coordinator) = makeManager()
        let directory = destination()

        let task = Task { @MainActor in
            try await manager.receiveFilePromises(destinationDirectory: directory)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        _ = try? await task.value
        try await Task.sleep(for: .milliseconds(100))

        // onCancel is nonisolated, so the cleanup has to hop to the main actor to run at all.
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("CT-13 and CT-16: the gate lets exactly one ending through")
    func gateAllowsOneOutcome() {
        let gate = ReceiptCompletionGate()
        var delivered: [String] = []
        gate.attach { outcome in
            switch outcome {
            case .finished: delivered.append("finished")
            case .failed: delivered.append("failed")
            }
        }

        #expect(gate.claim(.finished(FilePromiseReceipt(urls: [], failures: [],
                                                        terminatedBy: .quiescence))))
        #expect(!gate.claim(.failed(CancellationError())))

        #expect(delivered == ["finished"])
        #expect(gate.claimed)
    }

    @Test("CT-15: a claim made before the continuation exists is delivered on attach")
    func gateHoldsOutcomeUntilAttach() {
        // withTaskCancellationHandler runs its handler immediately when the task is already
        // cancelled, which happens before the continuation is created.
        let gate = ReceiptCompletionGate()
        #expect(gate.claim(.failed(CancellationError())))

        var delivered: [String] = []
        gate.attach { outcome in
            if case .failed = outcome { delivered.append("failed") }
        }

        #expect(delivered == ["failed"])
    }

    @Test("CT-16: a losing terminal does not resume a second time")
    func losingTerminalIsDropped() {
        let gate = ReceiptCompletionGate()
        var count = 0
        gate.attach { _ in count += 1 }

        #expect(gate.claim(.failed(CancellationError())))
        #expect(!gate.claim(.finished(FilePromiseReceipt(urls: [], failures: [],
                                                         terminatedBy: .quiescence))))

        #expect(count == 1)
    }

    @Test("a task cancelled before it starts still reports cancellation")
    func alreadyCancelledTask() async throws {
        let (manager, _, _) = makeManager()
        let directory = destination()

        let task = Task { @MainActor in
            try await manager.receiveFilePromises(destinationDirectory: directory)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
