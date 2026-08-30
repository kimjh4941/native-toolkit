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
        return (MacClipboardManager(coordinator: coordinator, useCases: useCases), repository, coordinator)
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

    // MARK: - CT-17 cancellation at each point of the start sequence

    /// A repository whose `startReceivingFilePromises` calls a hook, so cancellation can be
    /// injected at a known point of the start sequence.
    ///
    /// The hook runs **inside** the start, synchronously, which is what makes the "during
    /// registration" moment reachable: the session is registered and the start has not
    /// returned. A blocking barrier cannot be used here — the start runs on the main actor, so
    /// blocking it would deadlock the very test meant to release it.
    @MainActor
    private final class GatedRepository: ClipboardRepository {
        private let base = MockClipboardRepository()
        /// Runs inside the start, before it returns.
        var onStart: (@MainActor (FilePromiseReceiptHandle) -> Void)?
        private(set) var startCallCount = 0
        private(set) var startedHandles: [FilePromiseReceiptHandle] = []

        func startReceivingFilePromises(handle: FilePromiseReceiptHandle,
                                        destinationDirectory: URL,
                                        scope: PasteboardScope) throws {
            startCallCount += 1
            startedHandles.append(handle)
            onStart?(handle)
        }

        func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope {
            try base.createPasteboard(request)
        }
        func removePasteboard(_ scope: PasteboardScope) throws { try base.removePasteboard(scope) }
        func write(_ content: ClipboardContent, options: ClipboardCopyOptions,
                   scope: PasteboardScope) throws -> PasteboardOwnership {
            try base.write(content, options: options, scope: scope)
        }
        func writePromised(handle: PasteboardPromiseHandle, types: [String],
                           options: ClipboardCopyOptions,
                           scope: PasteboardScope) throws -> PasteboardOwnership {
            try base.writePromised(handle: handle, types: types, options: options, scope: scope)
        }
        func append(_ content: ClipboardContent,
                    ownership: PasteboardOwnership) throws -> PasteboardOwnership {
            try base.append(content, ownership: ownership)
        }
        func read(scope: PasteboardScope) throws -> ClipboardReadResult { try base.read(scope: scope) }
        func readData(utType: String, scope: PasteboardScope) throws -> Data? {
            try base.readData(utType: utType, scope: scope)
        }
        func snapshot(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot {
            try base.snapshot(matchingTypes: matchingTypes, scope: scope)
        }
        func clear(scope: PasteboardScope) throws -> Int { try base.clear(scope: scope) }
        func changeCount(scope: PasteboardScope) throws -> Int { try base.changeCount(scope: scope) }
        func detectPatterns(_ patterns: Set<ClipboardDetectionPattern>,
                            scope: PasteboardScope) async throws -> Set<ClipboardDetectionPattern> {
            try await base.detectPatterns(patterns, scope: scope)
        }
        func detectValues(_ patterns: Set<ClipboardDetectionPattern>,
                          scope: PasteboardScope) async throws -> ClipboardDetectedValues {
            try await base.detectValues(patterns, scope: scope)
        }
        func detectMetadata(scope: PasteboardScope) async throws -> ClipboardDetectedMetadata {
            try await base.detectMetadata(scope: scope)
        }
        func accessBehavior(scope: PasteboardScope) throws -> ClipboardAccessBehavior {
            try base.accessBehavior(scope: scope)
        }
        func writeFilePromise(handle: FilePromiseHandle,
                              scope: PasteboardScope) throws -> PasteboardOwnership {
            try base.writeFilePromise(handle: handle, scope: scope)
        }
    }

    private func makeGatedManager() -> (MacClipboardManager, GatedRepository,
                                        ClipboardSystemCoordinator) {
        let repository = GatedRepository()
        let snapshotter = MockFilePromiseSnapshotter()
        let coordinator = ClipboardSystemCoordinator(
            snapshotter: snapshotter,
            stagingBase: URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString))
        let useCases = ClipboardUseCases(repository: repository,
                                         registry: coordinator,
                                         snapshotter: snapshotter,
                                         typeValidator: MockClipboardTypeIdentifierValidating())
        return (MacClipboardManager(coordinator: coordinator, useCases: useCases),
                repository, coordinator)
    }

    @Test("CT-17: cancelling just after the handle is reserved leaves no session")
    func cancelJustAfterReservation() async throws {
        let (manager, repository, coordinator) = makeGatedManager()
        let directory = destination()

        // Cancelled before the task body runs, so the handle has been reserved by the time
        // onCancel fires but the start has not been reached.
        let task = Task { @MainActor in
            try await manager.receiveFilePromises(destinationDirectory: directory)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) { _ = try await task.value }
        try await Task.sleep(for: .milliseconds(150))
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("CT-17: cancelling while the start is in flight leaves no session", .timeLimit(.minutes(1)))
    func cancelDuringRegistration() async throws {
        let (manager, repository, coordinator) = makeGatedManager()
        let directory = destination()

        var task: Task<FilePromiseReceipt, any Error>?
        // Fires inside the start: the session is registered and the call has not returned,
        // which is the window R6-H4 was about. No sleeping is involved.
        repository.onStart = { _ in task?.cancel() }

        task = Task { @MainActor in
            try await manager.receiveFilePromises(destinationDirectory: directory)
        }
        _ = try? await task?.value
        try await Task.sleep(for: .milliseconds(200))

        #expect(repository.startCallCount == 1)
        #expect(coordinator.registeredReceiptCount == 0)
        let started = try #require(repository.startedHandles.first)
        #expect(coordinator.receiptSession(for: started) == nil)
    }

    @Test("CT-17: cancelling just after the start returns leaves no session", .timeLimit(.minutes(1)))
    func cancelJustAfterRegistration() async throws {
        let (manager, repository, coordinator) = makeGatedManager()
        let directory = destination()

        let task = Task { @MainActor in
            try await manager.receiveFilePromises(destinationDirectory: directory)
        }
        // Yield until the start has returned, rather than sleeping for long enough to hope.
        try await waitUntil { repository.startCallCount == 1 }
        #expect(coordinator.registeredReceiptCount == 1)
        let started = try #require(repository.startedHandles.first)

        task.cancel()
        _ = try? await task.value
        try await Task.sleep(for: .milliseconds(200))

        #expect(coordinator.registeredReceiptCount == 0)
        #expect(coordinator.receiptSession(for: started) == nil)
    }

    @Test("CT-17: every cancellation point acts on the reserved handle", .timeLimit(.minutes(1)))
    func cancellationUsesTheReservedHandle() async throws {
        // The same assertion at each of the three points: the handle the start was given is
        // the one torn down. A handle assigned later would leave that session behind (R6-H4).
        enum Point: String, CaseIterable {
            case beforeStart, duringStart, afterStart
        }

        for point in Point.allCases {
            let (manager, repository, coordinator) = makeGatedManager()
            let directory = destination()
            var task: Task<FilePromiseReceipt, any Error>?
            if point == .duringStart {
                repository.onStart = { _ in task?.cancel() }
            }

            task = Task { @MainActor in
                try await manager.receiveFilePromises(destinationDirectory: directory)
            }
            switch point {
            case .beforeStart:
                task?.cancel()
            case .duringStart:
                break
            case .afterStart:
                try await waitUntil { repository.startCallCount == 1 }
                task?.cancel()
            }
            _ = try? await task?.value
            try await Task.sleep(for: .milliseconds(200))

            #expect(coordinator.registeredReceiptCount == 0, "\(point.rawValue)")
            if let started = repository.startedHandles.first {
                #expect(coordinator.receiptSession(for: started) == nil, "\(point.rawValue)")
            }
        }
    }

    /// Yields until `condition` holds, so a test can wait for a step instead of a duration.
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("condition never became true")
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
