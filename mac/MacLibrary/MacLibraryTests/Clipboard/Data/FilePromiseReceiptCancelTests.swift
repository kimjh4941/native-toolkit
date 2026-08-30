//
//  FilePromiseReceiptCancelTests.swift
//  MacLibraryTests
//

import Testing
import AppKit
import Foundation
@testable import MacLibrary

/// Cancellation and start-failure rollback for the receive side.
///
/// The two look similar and are deliberately different: cancelling a running session is an
/// ordinary ending that the caller observes, while a session that never started must be
/// invisible (R5-H4).
@Suite("File promise receipt cancellation")
@MainActor
struct FilePromiseReceiptCancelTests {

    private final class Recorder {
        var events: [FilePromiseReceiptEvent] = []
        var terminal: FilePromiseReceipt? {
            for case .finished(let receipt) in events { return receipt }
            return nil
        }
        var finishedCount: Int {
            events.reduce(0) { count, event in
                if case .finished = event { return count + 1 }
                return count
            }
        }
    }

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
        let manager = MacClipboardManager(coordinator: coordinator,
                                          useCases: useCases,
                                          repository: repository)
        return (manager, repository, coordinator)
    }

    private func destination() -> URL {
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - IT-19 / IT-25

    @Test("IT-19 and IT-25: the public cancel delivers one cancelled terminal event")
    func publicCancelDeliversOnce() throws {
        let (manager, _, _) = makeManager()
        let recorder = Recorder()

        let handle = try manager.receiveFilePromises(destinationDirectory: destination(),
                                                     onEvent: { recorder.events.append($0) })
        manager.cancelReceiveFilePromises(handle)
        manager.cancelReceiveFilePromises(handle)

        #expect(recorder.finishedCount == 1)
        #expect(recorder.terminal?.terminatedBy == .cancelled)
    }

    @Test("cancelling keeps the files that already arrived")
    func cancelKeepsPartialResults() throws {
        let (manager, _, coordinator) = makeManager()
        let recorder = Recorder()

        let handle = try manager.receiveFilePromises(destinationDirectory: destination(),
                                                     onEvent: { recorder.events.append($0) })
        let session = try #require(coordinator.receiptSession(for: handle))
        session.recordReceived(URL(filePath: "/tmp/a.txt"), generation: session.generation)

        manager.cancelReceiveFilePromises(handle)

        // Cancellation is an ordinary ending, not a failure: what arrived is still the result
        // (R2-M6).
        #expect(recorder.terminal?.urls == [URL(filePath: "/tmp/a.txt")])
        #expect(recorder.terminal?.terminatedBy == .cancelled)
    }

    // MARK: - IT-36

    @Test("IT-36: cancelling after the session already ended is a no-op")
    func cancelAfterTerminationIsNoOp() throws {
        let (manager, _, coordinator) = makeManager()
        let recorder = Recorder()

        let handle = try manager.receiveFilePromises(destinationDirectory: destination(),
                                                     onEvent: { recorder.events.append($0) })
        let session = try #require(coordinator.receiptSession(for: handle))
        session.finish(terminatedBy: .quiescence)

        manager.cancelReceiveFilePromises(handle)

        // A second terminal event would break the exactly-once contract.
        #expect(recorder.finishedCount == 1)
        #expect(recorder.terminal?.terminatedBy == .quiescence)
    }

    @Test("IT-36: cancelling an unknown handle is a no-op")
    func cancelUnknownHandleIsNoOp() {
        let (manager, _, coordinator) = makeManager()
        manager.cancelReceiveFilePromises(FilePromiseReceiptHandle())
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("IT-36: cancelling after a silent teardown stays silent")
    func cancelAfterSilentTeardown() throws {
        let (manager, _, coordinator) = makeManager()
        let recorder = Recorder()

        let handle = try manager.receiveFilePromises(destinationDirectory: destination(),
                                                     onEvent: { recorder.events.append($0) })
        coordinator.terminateReceiptWithoutDelivery(handle)
        manager.cancelReceiveFilePromises(handle)

        // The consumer is gone, so neither path may produce an event (R6-M5).
        #expect(recorder.events.isEmpty)
    }

    // MARK: - IT-37 / IT-43

    @Test("IT-43: a start failure produces no event at all")
    func startFailureIsSilent() {
        let (manager, repository, _) = makeManager()
        repository.shouldFail = .destinationNotWritable("dest")
        let recorder = Recorder()

        #expect(throws: ClipboardError.destinationNotWritable("dest")) {
            _ = try manager.receiveFilePromises(destinationDirectory: self.destination(),
                                                onEvent: { recorder.events.append($0) })
        }

        // Not even a cancelled terminal event: a session that never began must be invisible
        // (R5-H4).
        #expect(recorder.events.isEmpty)
    }

    @Test("IT-37: a start failure leaves no session or timer behind")
    func startFailureLeavesNothing() {
        let (manager, repository, coordinator) = makeManager()
        repository.shouldFail = .destinationNotWritable("dest")

        #expect(throws: ClipboardError.self) {
            _ = try manager.receiveFilePromises(destinationDirectory: self.destination(),
                                                onEvent: { _ in })
        }

        // The registration happens before the start, so without a rollback it would survive
        // (R4-M5).
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("IT-37: the rollback path is not the public cancel path")
    func rollbackIsNotCancel() {
        let (manager, repository, _) = makeManager()
        repository.shouldFail = .filePromiseReceiveFailed("no promise")
        var terminalSeen = false

        #expect(throws: ClipboardError.self) {
            _ = try manager.receiveFilePromises(destinationDirectory: self.destination(),
                                                onEvent: { event in
                if case .finished = event { terminalSeen = true }
            })
        }

        #expect(!terminalSeen)
    }

    @Test("the callback form reports a start failure as an error code")
    func startFailureThroughCallback() {
        let (manager, repository, _) = makeManager()
        repository.shouldFail = .destinationNotWritable("dest")
        var received: (Bool, Int)?

        manager.receiveFilePromises(destinationDirectory: destination(),
                                    onEvent: { _ in },
                                    completion: { isSuccess, _, code, _ in
            received = (isSuccess, code)
        })

        #expect(received?.0 == false)
        #expect(received?.1 == ClipboardError.destinationNotWritable("dest").errorCode)
    }

    // MARK: - IT-38

    @Test("IT-38: tearing a session down does not delete the files it already received")
    func teardownKeepsReceivedFiles() throws {
        let (manager, _, coordinator) = makeManager()
        let directory = destination()
        let received = directory.appending(path: "arrived.txt")
        try Data("arrived".utf8).write(to: received)

        let handle = try manager.receiveFilePromises(destinationDirectory: directory,
                                                     onEvent: { _ in })
        let session = try #require(coordinator.receiptSession(for: handle))
        session.recordReceived(received, generation: session.generation)

        coordinator.terminateReceiptWithoutDelivery(handle)

        // Cleanup releases the session, its timers and its closures. Files already handed to
        // the caller's destination are theirs (R4-L9 / R5-L12).
        #expect(FileManager.default.fileExists(atPath: received.path(percentEncoded: false)))
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("IT-38: a cancelled session's received files survive")
    func cancelKeepsReceivedFiles() throws {
        let (manager, _, coordinator) = makeManager()
        let directory = destination()
        let received = directory.appending(path: "arrived.txt")
        try Data("arrived".utf8).write(to: received)

        let handle = try manager.receiveFilePromises(destinationDirectory: directory,
                                                     onEvent: { _ in })
        let session = try #require(coordinator.receiptSession(for: handle))
        session.recordReceived(received, generation: session.generation)

        manager.cancelReceiveFilePromises(handle)

        #expect(FileManager.default.fileExists(atPath: received.path(percentEncoded: false)))
    }

    // MARK: - Session removal

    @Test("a finished session is removed from the coordinator")
    func finishedSessionIsRemoved() throws {
        let (manager, _, coordinator) = makeManager()
        let handle = try manager.receiveFilePromises(destinationDirectory: destination(),
                                                     onEvent: { _ in })
        #expect(coordinator.registeredReceiptCount == 1)

        manager.cancelReceiveFilePromises(handle)

        // Holding a finished session would leak its closures for the life of the app (R6-M6).
        #expect(coordinator.registeredReceiptCount == 0)
    }

    @Test("a late reader result after cancellation is discarded")
    func lateResultAfterCancelIsDiscarded() throws {
        let (manager, _, coordinator) = makeManager()
        let recorder = Recorder()
        let handle = try manager.receiveFilePromises(destinationDirectory: destination(),
                                                     onEvent: { recorder.events.append($0) })
        let session = try #require(coordinator.receiptSession(for: handle))
        let generation = session.generation

        manager.cancelReceiveFilePromises(handle)
        // The receiver is still running on its own queue and reports one more file.
        coordinator.deliverReceiptOutcome(handle, generation: generation,
                                          outcome: .success(URL(filePath: "/tmp/late.txt")))

        #expect(recorder.events.count == 1)
        #expect(recorder.finishedCount == 1)
    }
}
