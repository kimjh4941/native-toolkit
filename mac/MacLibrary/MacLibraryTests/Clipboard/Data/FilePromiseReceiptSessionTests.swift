//
//  FilePromiseReceiptSessionTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

/// Termination behaviour of a receive session (H-3).
@Suite("FilePromiseReceiptSession")
@MainActor
struct FilePromiseReceiptSessionTests {

    /// Short timers so the suite does not spend real seconds waiting.
    private func policy(quiet: TimeInterval = 0.05,
                        overall: TimeInterval = 1.0) throws -> FilePromiseReceiptPolicy {
        try FilePromiseReceiptPolicy(quietInterval: quiet, overallTimeout: overall)
    }

    private final class Recorder {
        var events: [FilePromiseReceiptEvent] = []
        var finishedHandles: [FilePromiseReceiptHandle] = []
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

    private func makeSession(_ policy: FilePromiseReceiptPolicy)
    -> (FilePromiseReceiptSession, Recorder, FilePromiseReceiptHandle) {
        let recorder = Recorder()
        let handle = FilePromiseReceiptHandle()
        let session = FilePromiseReceiptSession(
            handle: handle,
            policy: policy,
            onEvent: { recorder.events.append($0) },
            onFinished: { recorder.finishedHandles.append($0) })
        return (session, recorder, handle)
    }

    // MARK: - IT-15

    @Test("IT-15: quiescence delivers exactly one terminal event")
    func quiescenceFinishesOnce() async throws {
        let (session, recorder, _) = makeSession(try policy())
        session.start(promisedTypeCount: 1)
        session.recordReceived(URL(filePath: "/tmp/a.txt"), generation: session.generation)

        try await Task.sleep(for: .milliseconds(200))

        #expect(recorder.finishedCount == 1)
        #expect(recorder.terminal?.terminatedBy == .quiescence)
        #expect(recorder.terminal?.urls == [URL(filePath: "/tmp/a.txt")])
    }

    @Test("each arrival restarts the quiet timer")
    func arrivalsExtendTheQuietWindow() async throws {
        let (session, recorder, _) = makeSession(try policy(quiet: 0.15, overall: 5))
        session.start(promisedTypeCount: 1)

        // Three arrivals spaced closer than the quiet interval must not terminate in between.
        for index in 0..<3 {
            try await Task.sleep(for: .milliseconds(80))
            session.recordReceived(URL(filePath: "/tmp/\(index).txt"), generation: session.generation)
            #expect(recorder.finishedCount == 0)
        }
        try await Task.sleep(for: .milliseconds(300))

        #expect(recorder.finishedCount == 1)
        #expect(recorder.terminal?.urls.count == 3)
    }

    // MARK: - IT-16

    @Test("IT-16: the number of arrivals is irrelevant to termination")
    func terminationIgnoresPromisedCount() async throws {
        let (session, recorder, _) = makeSession(try policy())
        // The receiver advertises one type but writes three files, which is the case the SDK
        // header warns about. Termination must not depend on the count either way.
        session.start(promisedTypeCount: 1)
        for index in 0..<3 {
            session.recordReceived(URL(filePath: "/tmp/\(index).txt"), generation: session.generation)
        }

        try await Task.sleep(for: .milliseconds(200))

        #expect(recorder.terminal?.urls.count == 3)
        #expect(recorder.terminal?.terminatedBy == .quiescence)
    }

    @Test("a session where nothing arrives still terminates")
    func emptySessionTerminates() async throws {
        let (session, recorder, _) = makeSession(try policy())
        session.start(promisedTypeCount: 5)

        try await Task.sleep(for: .milliseconds(200))

        // Five types were advertised and nothing arrived. A count based design would wait
        // forever here.
        #expect(recorder.finishedCount == 1)
        #expect(recorder.terminal?.urls.isEmpty == true)
    }

    // MARK: - IT-17

    @Test("IT-17: a callback arriving after termination is discarded")
    func lateCallbackIsDiscarded() async throws {
        let (session, recorder, _) = makeSession(try policy())
        session.start(promisedTypeCount: 1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(recorder.finishedCount == 1)

        session.recordReceived(URL(filePath: "/tmp/late.txt"), generation: session.generation)

        // The reader keeps running on its own queue after the session ends. Accepting this
        // would emit an event after the terminal one.
        #expect(recorder.events.count == 1)
        #expect(recorder.finishedCount == 1)
    }

    @Test("a callback from a previous generation is discarded")
    func staleGenerationIsDiscarded() throws {
        let (session, recorder, _) = makeSession(try policy(quiet: 5, overall: 10))
        session.start(promisedTypeCount: 1)

        session.recordReceived(URL(filePath: "/tmp/other.txt"), generation: UUID())

        #expect(recorder.events.isEmpty)
    }

    // MARK: - IT-18

    @Test("IT-18: a producer that never goes quiet is ended by the overall timeout")
    func overallTimeoutTerminates() async throws {
        // quietInterval must be shorter than overallTimeout, so the overall deadline can only
        // win when arrivals keep restarting the quiet timer for longer than it.
        let (session, recorder, _) = makeSession(try policy(quiet: 0.2, overall: 0.4))
        session.start(promisedTypeCount: 1)

        let feeder = Task { @MainActor in
            for index in 0..<20 where !Task.isCancelled {
                session.recordReceived(URL(filePath: "/tmp/\(index).txt"),
                                       generation: session.generation)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
        try await Task.sleep(for: .milliseconds(700))
        feeder.cancel()

        #expect(recorder.terminal?.terminatedBy == .overallTimeout)
        #expect(recorder.finishedCount == 1)
    }

    @Test("the overall timeout keeps what already arrived")
    func overallTimeoutKeepsPartialResults() async throws {
        let (session, recorder, _) = makeSession(try policy(quiet: 0.2, overall: 0.4))
        session.start(promisedTypeCount: 3)

        let feeder = Task { @MainActor in
            session.recordFailure(.filePromiseReceiveFailed("b"), generation: session.generation)
            for index in 0..<20 where !Task.isCancelled {
                session.recordReceived(URL(filePath: "/tmp/\(index).txt"),
                                       generation: session.generation)
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
        try await Task.sleep(for: .milliseconds(700))
        feeder.cancel()

        // A timeout is an ordinary ending, not a failure: the partial receipt is the result
        // (R2-M6).
        #expect(recorder.terminal?.terminatedBy == .overallTimeout)
        #expect(recorder.terminal?.urls.isEmpty == false)
        #expect(recorder.terminal?.failures.count == 1)
    }

    @Test("a policy whose quiet interval is not shorter than the overall timeout is rejected")
    func policyOrderingIsEnforced() {
        // The overall timeout is a backstop, so a quiet interval at least as long would make
        // it unreachable.
        #expect(throws: ClipboardError.invalidConfiguration(
            "quietInterval must be shorter than overallTimeout.")) {
            _ = try FilePromiseReceiptPolicy(quietInterval: 5, overallTimeout: 0.2)
        }
    }

    // MARK: - Failures

    @Test("a failed file does not end the session")
    func failureDoesNotTerminate() async throws {
        let (session, recorder, _) = makeSession(try policy(quiet: 0.15, overall: 5))
        session.start(promisedTypeCount: 2)

        session.recordFailure(.filePromiseReceiveFailed("a"), generation: session.generation)
        #expect(recorder.finishedCount == 0)
        try await Task.sleep(for: .milliseconds(80))
        session.recordReceived(URL(filePath: "/tmp/b.txt"), generation: session.generation)
        #expect(recorder.finishedCount == 0)

        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.terminal?.urls.count == 1)
        #expect(recorder.terminal?.failures.count == 1)
    }

    // MARK: - Terminal exactly-once

    @Test("finishing twice delivers one event")
    func finishIsExactlyOnce() throws {
        let (session, recorder, _) = makeSession(try policy(quiet: 5, overall: 10))
        session.start(promisedTypeCount: 1)

        session.finish(terminatedBy: .cancelled)
        session.finish(terminatedBy: .quiescence)

        #expect(recorder.finishedCount == 1)
        #expect(recorder.terminal?.terminatedBy == .cancelled)
    }

    @Test("a terminated session reports itself as finished and notifies its owner")
    func finishNotifiesOwner() throws {
        let (session, recorder, handle) = makeSession(try policy(quiet: 5, overall: 10))
        session.start(promisedTypeCount: 1)

        session.finish(terminatedBy: .quiescence)

        #expect(session.finished)
        #expect(recorder.finishedHandles == [handle])
    }

    @Test("terminating without delivery emits nothing and stops the timers")
    func terminateWithoutDeliveryIsSilent() async throws {
        let (session, recorder, _) = makeSession(try policy())
        session.start(promisedTypeCount: 1)

        session.terminateWithoutDelivery()
        try await Task.sleep(for: .milliseconds(200))

        // Neither the explicit call nor the quiet timer may produce an event (R6-M5).
        #expect(recorder.events.isEmpty)
        #expect(recorder.finishedHandles.isEmpty)
    }

    @Test("cancelling after termination without delivery stays silent")
    func cancelAfterSilentTerminationIsSilent() {
        let (session, recorder, _) = makeSession(try! policy(quiet: 5, overall: 10))
        session.start(promisedTypeCount: 1)

        session.terminateWithoutDelivery()
        session.finish(terminatedBy: .cancelled)

        #expect(recorder.events.isEmpty)
    }
}
