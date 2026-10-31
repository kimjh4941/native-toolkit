//
//  RequestBoxTests.swift
//  IosLibraryTests
//

import Foundation
import Synchronization
import Testing
@testable import IosLibrary

/// UT-03: the request box (design 6.3.2, part 1 5.13.1). Also run with the Thread Sanitizer.
struct RequestBoxTests {

    @Test func aNewBoxIsOpenAndTheFirstCloseWins() {
        let box = RequestBox()
        #expect(!box.isClosed)
        #expect(box.outcome == nil)

        #expect(box.close(.canceled))
        #expect(box.isClosed)
        #expect(!box.close(.dismissedBySystem))
        #expect(!box.close(.completed("late")))
        #expect(box.outcome?.testName == "canceled")
    }

    @MainActor
    @Test func theCloseHandlerRunsOnceOnMainAfterTheClosingCall() async {
        let box = RequestBox()
        let recorder = OutcomeRecorder()
        #expect(box.attach { recorder.record($0) })

        box.close(.completed("answer"))
        // Queued, not run inside `close` (also when `close` runs on the main thread).
        #expect(recorder.all.isEmpty)
        box.close(.canceled)
        await drainMainQueue(times: 2)

        #expect(recorder.names == ["completed(answer)"])
        #expect(recorder.all.allSatisfy { $0.isMainThread })
    }

    @MainActor
    @Test func attachingToAClosedBoxDeliversTheEarlierOutcomeLater() async {
        // Cancelled before the request started (the C ABI creates the box first, part 1 5.7).
        let box = RequestBox()
        box.close(.canceled)
        let recorder = OutcomeRecorder()

        #expect(box.attach { recorder.record($0) })
        // The same path as an open box: queued on main, not run inside `attach`.
        #expect(recorder.all.isEmpty)
        await drainMainQueue()

        #expect(recorder.names == ["canceled"])
        #expect(recorder.all.allSatisfy { $0.isMainThread })
    }

    @MainActor
    @Test func aSecondAttachIsRefusedAndNeverCalled() async {
        let box = RequestBox()
        let first = OutcomeRecorder()
        let second = OutcomeRecorder()
        #expect(box.attach { first.record($0) })
        #expect(!box.attach { second.record($0) })

        box.close(.notForeground)
        await drainMainQueue()

        #expect(first.names == ["notForeground"])
        #expect(second.all.isEmpty)
    }

    @MainActor
    @Test func aSecondAttachToAClosedBoxIsAlsoRefused() async {
        let box = RequestBox()
        let first = OutcomeRecorder()
        let second = OutcomeRecorder()
        #expect(box.attach { first.record($0) })
        box.close(.presentationFailed)
        #expect(!box.attach { second.record($0) })
        await drainMainQueue()

        #expect(first.names == ["presentationFailed"])
        #expect(second.all.isEmpty)
    }

    /// The close handler is nonisolated and only queues on main, so closing from a background
    /// thread neither traps (Swift 6 checks the isolation of a main-actor closure at run time)
    /// nor runs the handler there (SR-3).
    @Test func closingFromABackgroundThreadDeliversOnMain() async {
        let box = RequestBox()
        let recorder = OutcomeRecorder()
        let attached = await MainActor.run { box.attach { recorder.record($0) } }
        #expect(attached)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Thread.detachNewThread {
                box.close(.canceled)
                continuation.resume()
            }
        }
        await drainMainQueue()

        #expect(recorder.names == ["canceled"])
        #expect(recorder.all.allSatisfy { $0.isMainThread })
    }

    /// 8 threads close the same box 25 times each, in many rounds: exactly one close wins per
    /// round and the handler runs exactly once per round. The threads of a round wait for one
    /// another before their first close, so that the first closes really overlap.
    @Test func concurrentClosesLeaveExactlyOneWinner() async {
        let rounds = 1000
        let threads = 8
        let closesPerThread = 25
        let recorders = (0..<rounds).map { _ in OutcomeRecorder() }
        let boxes = (0..<rounds).map { _ in RequestBox() }
        let attachedAll = await MainActor.run {
            zip(boxes, recorders).allSatisfy { box, recorder in box.attach { recorder.record($0) } }
        }
        #expect(attachedAll)

        let winners = Mutex<[Int]>(Array(repeating: 0, count: rounds))
        for round in 0..<rounds {
            let box = boxes[round]
            let arrived = Atomic<Int>(0)
            DispatchQueue.concurrentPerform(iterations: threads) { thread in
                arrived.add(1, ordering: .acquiringAndReleasing)
                while arrived.load(ordering: .acquiring) < threads {}
                var won = 0
                for attempt in 0..<closesPerThread {
                    let outcome: RequestBoxOutcome = (thread + attempt).isMultiple(of: 2) ? .canceled : .completed("t\(thread)")
                    if box.close(outcome) { won += 1 }
                }
                let wins = won
                winners.withLock { $0[round] += wins }
            }
        }
        await drainMainQueue()

        let counts = winners.withLock { $0 }
        let wrongRounds = counts.enumerated().filter { $0.element != 1 }.map(\.offset)
        #expect(wrongRounds.isEmpty, "rounds with another number of winners than 1: \(wrongRounds.count)")
        #expect(recorders.allSatisfy { $0.all.count == 1 })
        #expect(zip(boxes, recorders).allSatisfy { box, recorder in box.outcome?.testName == recorder.names.first })
    }
}
