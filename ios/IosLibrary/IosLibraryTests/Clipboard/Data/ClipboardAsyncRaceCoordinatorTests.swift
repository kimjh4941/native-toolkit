//
//  ClipboardAsyncRaceCoordinatorTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
@testable import IosLibrary

struct ClipboardAsyncRaceCoordinatorTests {

    @Test func successfulOperationReturnsItsValue() async throws {
        let value = try await ClipboardAsyncRaceCoordinator<Int>.run(
            timeout: 10, operationKind: .detection
        ) { 42 }
        #expect(value == 42)
    }

    @Test func operationErrorIsPropagated() async {
        await #expect(throws: ClipboardError.noMatchingItem) {
            try await ClipboardAsyncRaceCoordinator<Int>.run(timeout: 10, operationKind: .detection) {
                throw ClipboardError.noMatchingItem
            }
        }
    }

    @Test func timeoutReturnsTimedOutWithoutWaitingForOperation() async {
        let start = Date()
        await #expect(throws: ClipboardError.timedOut(operation: .detection)) {
            try await ClipboardAsyncRaceCoordinator<Int>.run(timeout: 0.05, operationKind: .detection) {
                // Simulates a non-cooperative system call that keeps running well past the timeout.
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
        // The caller must be released at the timeout, not after the operation finishes.
        #expect(Date().timeIntervalSince(start) < 3.0)
    }

    @Test func cancellationBeforeContinuationAttachStillReturnsCancelled() async {
        // Regression for the attach-before-cancel race: the Task is cancelled before the
        // coordinator's continuation is attached, so `onCancel` runs first and the `.cancelled`
        // result must be latched and replayed rather than dropped.
        let task = Task<Int, Error> {
            try await ClipboardAsyncRaceCoordinator<Int>.run(timeout: 30, operationKind: .detection) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
        task.cancel()

        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 3.0)
        switch result {
        case .success:
            Issue.record("expected cancellation, got a value")
        case .failure(let error):
            #expect((error as? ClipboardError) == .cancelled)
        }
    }

    @Test func threeWayRaceDeliversExactlyOneArrivalInEveryOrder() async {
        // U-111: whichever of {completion, cancellation, timeout} arrives first must be the one
        // delivered, and the two losers must be dropped — for every arrival order.
        let completion = Result<Int, Error>.success(42)
        let cancellation = Result<Int, Error>.failure(ClipboardError.cancelled)
        let timeout = Result<Int, Error>.failure(ClipboardError.timedOut(operation: .detection))
        let orders: [[Result<Int, Error>]] = [
            [completion, cancellation, timeout],
            [cancellation, timeout, completion],
            [timeout, completion, cancellation]
        ]

        for order in orders {
            let coordinator = ClipboardAsyncRaceCoordinator<Int>()
            var accepted: [Bool] = []
            let delivered: Result<Int, Error>
            do {
                let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                    coordinator.attach(continuation)
                    for arrival in order {
                        accepted.append(coordinator.resolve(arrival))
                    }
                }
                delivered = .success(value)
            } catch {
                delivered = .failure(error)
            }

            // Exactly one arrival wins; a second resume would have trapped the checked continuation.
            #expect(accepted == [true, false, false])
            switch (delivered, order[0]) {
            case (.success(let actual), .success(let expected)):
                #expect(actual == expected)
            case (.failure(let actual), .failure(let expected)):
                #expect((actual as? ClipboardError) == (expected as? ClipboardError))
            default:
                Issue.record("delivered outcome did not match the first arrival")
            }
        }
    }

    @Test func lateArrivalsAfterAnEarlyCancellationAreAlsoDropped() async {
        // The `pendingResult` latch must not turn into a second delivery when the operation
        // finishes after a cancellation that arrived before `attach`.
        let coordinator = ClipboardAsyncRaceCoordinator<Int>()
        #expect(coordinator.resolve(.failure(ClipboardError.cancelled)) == true)
        #expect(coordinator.resolve(.success(1)) == false)

        let delivered: Result<Int, Error>
        do {
            let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                coordinator.attach(continuation)
            }
            delivered = .success(value)
        } catch {
            delivered = .failure(error)
        }
        if case .failure(let error) = delivered {
            #expect((error as? ClipboardError) == .cancelled)
        } else {
            Issue.record("expected the latched cancellation to be replayed")
        }
    }

    @Test func cancellationDuringOperationReturnsCancelledImmediately() async {
        let started = AsyncSignal()
        let task = Task<Int, Error> {
            try await ClipboardAsyncRaceCoordinator<Int>.run(timeout: 30, operationKind: .detection) {
                await started.signal()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
        await started.wait()
        task.cancel()

        let start = Date()
        let result = await task.result
        #expect(Date().timeIntervalSince(start) < 3.0)
        if case .failure(let error) = result {
            #expect((error as? ClipboardError) == .cancelled)
        } else {
            Issue.record("expected cancellation, got a value")
        }
    }
}

/// Minimal one-shot async signal used to synchronize a test with work started inside a Task.
actor AsyncSignal {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isSignaled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        if isSignaled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
