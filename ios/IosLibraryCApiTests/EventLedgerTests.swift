//
//  EventLedgerTests.swift
//  IosLibraryCApiTests
//

import Foundation
import XCTest
@testable import IosLibraryCApi

/// The handle stays in the recorder's `outListener`.
private func register(_ recorder: Recorder, to ledger: EventLedger<Int32, EventCallback>) {
    XCTAssertEqual(ledger.add(callback: recordingEventCallback as EventCallback, userData: recorder.userData, release: recordingRelease,
                              outListener: recorder.outListener), Entry.accepted)
}

/// The ledger of events, through a test-only event (part 1, 5.7, 5.12.7; part 2, 5.4 and 12.1's
/// row of events, AP-21).
@MainActor
final class EventLedgerTests: XCTestCase {
    private let holdingLimit = 32

    private func makeLedger(holdLimit: Int = 32, onFirstInsertion: (@MainActor @Sendable () -> Void)? = nil) -> EventLedger<Int32, EventCallback> {
        EventLedger(holdLimit: holdLimit, deliver: { callback, userData, event in callback(userData, event) },
                    onFirstInsertion: onFirstInsertion)
    }

    // MARK: - Registering and removing

    func testNothingRunsInsideAddAndTheHandleIsThere() {
        let firstInsertion = MainHolder<Int>()
        let ledger = makeLedger { firstInsertion.value = (firstInsertion.value ?? 0) + 1 }
        let recorder = Recorder()

        register(recorder, to: ledger)

        XCTAssertNotNil(recorder.outListener.pointee)
        XCTAssertEqual(ledger.entryCount, 0, "the insertion is queued")
        XCTAssertNil(firstInsertion.value)
        runMainQueue()
        XCTAssertEqual(ledger.entryCount, 1)
        XCTAssertEqual(firstInsertion.value, 1)
        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()
    }

    func testEveryRegistrationGetsTheEventInTheOrderTheyRegistered() {
        let ledger = makeLedger()
        let first = Recorder()
        let second = Recorder()
        register(first, to: ledger)
        register(second, to: ledger)
        runMainQueue()
        let order = OrderLog()
        first.onEvent = { event in order.append("first \(event)") }
        second.onEvent = { event in order.append("second \(event)") }

        ledger.receive(7)

        XCTAssertEqual(order.items, ["first 7", "second 7"])
        Registry.removeListener(first.outListener.pointee)
        Registry.removeListener(second.outListener.pointee)
        runMainQueue()
    }

    func testRemovalFromMainStopsDeliveryAtOnceAndReleasesLaterOnce() {
        let ledger = makeLedger()
        let first = Recorder()
        let second = Recorder()
        register(first, to: ledger)
        register(second, to: ledger)
        runMainQueue()

        Registry.removeListener(first.outListener.pointee)
        ledger.receive(1)

        XCTAssertEqual(first.events, [], "before the removal's block ran")
        XCTAssertEqual(second.events, [1])
        XCTAssertEqual(first.releases, [])
        XCTAssertEqual(ledger.entryCount, 2)

        runMainQueue()

        XCTAssertEqual(first.releases, [true])
        XCTAssertEqual(ledger.entryCount, 1)
        Registry.removeListener(second.outListener.pointee)
        runMainQueue()
    }

    /// With the main thread inside a delivery: the removal returns at once, the delivery that had begun
    /// is the one that "can still come", the release comes only after it, on main.
    func testRemovalOffMainDoesNotWaitAndDeliveryThatBeganGoesOnUntilRelease() {
        let ledger = makeLedger()
        let recorder = Recorder()
        register(recorder, to: ledger)
        runMainQueue()
        let handle = UInt(bitPattern: recorder.outListener.pointee)
        let returned = MainHolder<Bool>()
        recorder.onEvent = { event in
            // On main, inside the callback; the other thread would time out if it waited for main.
            let removed = onAnotherThread { () -> Bool in
                Registry.removeListener(OpaquePointer(bitPattern: handle))
                return recorder.releases.isEmpty
            }
            MainActor.assumeIsolated { returned.value = removed }
        }

        ledger.receive(1)

        XCTAssertEqual(returned.value, true)
        XCTAssertEqual(recorder.events, [1])
        XCTAssertEqual(recorder.releases, [])

        ledger.receive(2)
        XCTAssertEqual(recorder.events, [1], "after the CAS nothing new starts")

        runMainQueue()

        XCTAssertEqual(recorder.releases, [true])
    }

    func testRemovingNullDoesNothing() {
        Registry.removeListener(nil)
    }

    /// The handle is the caller's reference (part 1, 5.7): removal lets go of it and the block's own,
    /// and the ledger's goes with the removal.
    func testTheRegistrationIsFreedAfterRelease() throws {
        let ledger = makeLedger()
        let recorder = Recorder()
        register(recorder, to: ledger)
        runMainQueue()
        let handle = try XCTUnwrap(recorder.outListener.pointee)
        weak let registration = Unmanaged<Registration<EventCallback>>.fromOpaque(UnsafeRawPointer(handle)).takeUnretainedValue()
        XCTAssertNotNil(registration)

        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()

        XCTAssertEqual(recorder.releases, [true])
        XCTAssertEqual(ledger.entryCount, 0)
        XCTAssertNil(registration)
    }

    /// The order table: in one main turn, the insertion runs first, then the removal.
    func testAddAndRemoveInTheSameTurnReleasesOnceAndTakesNothing() {
        let ledger = makeLedger()
        ledger.receive(1)
        let recorder = Recorder()

        register(recorder, to: ledger)
        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()

        XCTAssertEqual(recorder.events, [], "the held event is not for it")
        XCTAssertEqual(recorder.releases, [true])
        XCTAssertEqual(ledger.entryCount, 0)
        XCTAssertEqual(ledger.heldCount, 1)
    }

    /// A removal off main before the insertion's turn: the same with the main thread stopped.
    func testRemovalOffMainBeforeTheInsertion() {
        let ledger = makeLedger()
        let recorder = Recorder()

        let removed = onAnotherThread { () -> Bool in
            _ = ledger.add(callback: recordingEventCallback as EventCallback, userData: recorder.userData,
                           release: recordingRelease, outListener: recorder.outListener)
            Registry.removeListener(recorder.outListener.pointee)
            return true
        }
        XCTAssertEqual(removed, true)
        runMainQueue()

        XCTAssertEqual(ledger.entryCount, 0)
        XCTAssertEqual(recorder.releases, [true])
    }

    // MARK: - Reentrant

    func testAddAndRemoveInsideACallback() {
        let ledger = makeLedger()
        let first = Recorder()
        let second = Recorder()
        let added = Recorder()
        register(first, to: ledger)
        register(second, to: ledger)
        runMainQueue()
        let secondHandle = UInt(bitPattern: second.outListener.pointee)
        first.onEvent = { [first] _ in
            MainActor.assumeIsolated {
                // Stops the next delivery of this very event.
                Registry.removeListener(OpaquePointer(bitPattern: secondHandle))
                Registry.removeListener(first.outListener.pointee)
                register(added, to: ledger)
            }
        }

        ledger.receive(1)

        XCTAssertEqual(first.events, [1])
        XCTAssertEqual(second.events, [], "removed by the callback before it")
        XCTAssertEqual(added.events, [], "added during the event; its insertion is queued")
        XCTAssertEqual(first.releases, [])
        XCTAssertEqual(second.releases, [])

        runMainQueue()
        XCTAssertEqual(first.releases, [true])
        XCTAssertEqual(second.releases, [true])

        ledger.receive(2)
        XCTAssertEqual(added.events, [2])
        XCTAssertEqual(first.events, [1])
        Registry.removeListener(added.outListener.pointee)
        runMainQueue()
    }

    /// release runs outside everything: it may add to the same ledger.
    func testReleaseMayAddToTheLedger() {
        let ledger = makeLedger()
        let first = Recorder()
        let next = Recorder()
        register(first, to: ledger)
        runMainQueue()
        first.onRelease = {
            MainActor.assumeIsolated { register(next, to: ledger) }
        }

        Registry.removeListener(first.outListener.pointee)
        runMainQueue()
        runMainQueue()
        ledger.receive(1)

        XCTAssertEqual(next.events, [1])
        Registry.removeListener(next.outListener.pointee)
        runMainQueue()
    }

    // MARK: - Events that arrive during a delivery (part 2, 5.4)

    /// Without the queue, the second listener would see 2 inside the first one's 1, and then 1.
    func testAnEventArrivingDuringADeliveryComesAfterItForEveryone() {
        let ledger = makeLedger()
        let first = Recorder()
        let second = Recorder()
        register(first, to: ledger)
        register(second, to: ledger)
        runMainQueue()
        let order = OrderLog()
        first.onEvent = { event in
            order.append("first \(event)")
            guard event == 1 else { return }
            MainActor.assumeIsolated { ledger.receive(2) }
            order.append("first 1 goes on")
        }
        second.onEvent = { event in order.append("second \(event)") }

        ledger.receive(1)

        XCTAssertEqual(second.events, [1, 2])
        XCTAssertEqual(first.events, [1, 2])
        XCTAssertEqual(order.items, ["first 1", "first 1 goes on", "second 1", "first 2", "second 2"])
        XCTAssertEqual(ledger.heldCount, 0)
        Registry.removeListener(first.outListener.pointee)
        Registry.removeListener(second.outListener.pointee)
        runMainQueue()
    }

    func testEventsArrivingDuringADeliveryKeepTheirOrder() {
        let ledger = makeLedger()
        let recorder = Recorder()
        register(recorder, to: ledger)
        runMainQueue()
        recorder.onEvent = { event in
            guard event == 1 else { return }
            MainActor.assumeIsolated {
                ledger.receive(2)
                ledger.receive(3)
            }
        }

        ledger.receive(1)

        XCTAssertEqual(recorder.events, [1, 2, 3])
        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()
    }

    /// An event goes to those ACTIVE when its turn comes: not one removed since it arrived.
    func testAnEventArrivingDuringADeliveryGoesToThoseThenActive() {
        let ledger = makeLedger()
        let first = Recorder()
        let second = Recorder()
        register(first, to: ledger)
        register(second, to: ledger)
        runMainQueue()
        first.onEvent = { event in
            guard event == 1 else { return }
            MainActor.assumeIsolated {
                ledger.receive(2)
                Registry.removeListener(second.outListener.pointee)
            }
        }

        ledger.receive(1)

        XCTAssertEqual(first.events, [1, 2])
        XCTAssertEqual(second.events, [])
        Registry.removeListener(first.outListener.pointee)
        runMainQueue()
    }

    /// With none left, they are held like any other: the limit, and the next registration alone.
    func testEventsArrivingAsTheOnlyRegistrationIsRemovedAreHeldUnderTheLimit() {
        let ledger = makeLedger()
        let first = Recorder()
        register(first, to: ledger)
        runMainQueue()
        first.onEvent = { [first] _ in
            Registry.removeListener(first.outListener.pointee)
            MainActor.assumeIsolated {
                for event in Int32(2)...41 { ledger.receive(event) }
            }
        }

        ledger.receive(1)

        XCTAssertEqual(first.events, [1])
        XCTAssertEqual(ledger.heldCount, 32)
        runMainQueue()
        let next = Recorder()
        let other = Recorder()
        register(next, to: ledger)
        register(other, to: ledger)
        runMainQueue()
        XCTAssertEqual(next.events, Array(10...41), "the oldest are gone")
        XCTAssertEqual(other.events, [])
        Registry.removeListener(next.outListener.pointee)
        Registry.removeListener(other.outListener.pointee)
        runMainQueue()
    }

    /// When the last held event is being delivered, nothing is held any more: it still waits its turn.
    func testAnEventArrivingDuringTheLastHeldEventComesAfterIt() {
        let ledger = makeLedger()
        ledger.receive(1)
        let recorder = Recorder()
        register(recorder, to: ledger)
        let order = OrderLog()
        recorder.onEvent = { event in
            guard event == 1 else { return }
            MainActor.assumeIsolated { ledger.receive(2) }
            order.append("1 goes on with \(recorder.events)")
        }

        runMainQueue()

        XCTAssertEqual(recorder.events, [1, 2])
        XCTAssertEqual(order.items, ["1 goes on with [1]"])
        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()
    }

    // MARK: - The release never overlaps a callback (part 1, 5.7)

    /// The removal runs on a run loop that the callback spins: out of the ledger there, the release after the return.
    func testARemovalRunningInsideAnEventLeavesTheReleaseForItsReturn() {
        let ledger = makeLedger()
        let recorder = Recorder()
        register(recorder, to: ledger)
        runMainQueue()
        let inside = MainHolder<(entries: Int, releases: [Bool])>()
        recorder.onEvent = { _ in
            Registry.removeListener(recorder.outListener.pointee)
            MainActor.assumeIsolated {
                runMainQueue()
                inside.value = (ledger.entryCount, recorder.releases)
            }
        }

        ledger.receive(1)

        XCTAssertEqual(inside.value?.entries, 0)
        XCTAssertEqual(inside.value?.releases, [])
        XCTAssertEqual(recorder.timeline, ["enter", "return", "release"])
        runMainQueue()
        assertReleasedOnceOutsideCallbacks(recorder)
    }

    /// A held event is delivered from the insertion's block, and inside a block of the main queue a run loop
    /// does not run the next one: the removal comes after the return, with the rest left for the next
    /// registration.
    func testARemovalInsideAHeldEventReleasesAfterItsReturn() {
        let ledger = makeLedger()
        for event in Int32(1)...3 { ledger.receive(event) }
        let recorder = Recorder()
        register(recorder, to: ledger)
        recorder.onEvent = { _ in
            Registry.removeListener(recorder.outListener.pointee)
        }

        runMainQueue()
        runMainQueue()

        XCTAssertEqual(recorder.events, [1])
        XCTAssertEqual(recorder.timeline, ["enter", "return", "release"])
        XCTAssertEqual(ledger.heldCount, 2)
        let next = Recorder()
        register(next, to: ledger)
        runMainQueue()
        XCTAssertEqual(next.events, [2, 3])
        Registry.removeListener(next.outListener.pointee)
        runMainQueue()
    }

    /// One registration's callback may release another: only its own callback holds a release back.
    func testACallbackOfAnotherRegistrationDoesNotHoldTheReleaseBack() {
        let ledger = makeLedger()
        let first = Recorder()
        let second = Recorder()
        register(first, to: ledger)
        register(second, to: ledger)
        runMainQueue()
        let seenInside = MainHolder<[Bool]>()
        first.onEvent = { _ in
            Registry.removeListener(second.outListener.pointee)
            MainActor.assumeIsolated {
                runMainQueue()
                seenInside.value = second.releases
            }
        }

        ledger.receive(1)

        XCTAssertEqual(seenInside.value, [true])
        Registry.removeListener(first.outListener.pointee)
        runMainQueue()
    }

    // MARK: - RELEASED (part 1, 5.7's right column)

    private func registration(of recorder: Recorder) throws -> Registration<EventCallback> {
        let handle = try XCTUnwrap(recorder.outListener.pointee)
        return Unmanaged<Registration<EventCallback>>.fromOpaque(UnsafeRawPointer(handle)).takeUnretainedValue()
    }

    func testARegistrationReleasedBeforeItsInsertionIsNotInserted() throws {
        let runs = MainHolder<Int>()
        let ledger = makeLedger { runs.value = (runs.value ?? 0) + 1 }
        ledger.receive(1)
        let recorder = Recorder()
        register(recorder, to: ledger)
        XCTAssertTrue(Registry.tryRelease(try registration(of: recorder), expected: .active))

        runMainQueue()

        XCTAssertEqual(ledger.entryCount, 0)
        XCTAssertNil(runs.value)
        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(ledger.heldCount, 1)
        XCTAssertEqual(recorder.releases, [true])
    }

    func testARegistrationReleasedInTheLedgerGetsNoEvent() throws {
        let ledger = makeLedger()
        let recorder = Recorder()
        register(recorder, to: ledger)
        runMainQueue()
        XCTAssertTrue(Registry.tryRelease(try registration(of: recorder), expected: .active))

        ledger.receive(1)

        XCTAssertEqual(recorder.events, [])
        XCTAssertEqual(ledger.heldCount, 1, "RELEASED is not ACTIVE")
        XCTAssertEqual(recorder.releases, [true])
    }

    // MARK: - Held events (AP-21)

    func testEventsWithNoRegistrationWaitForTheNextInsertionAndNotForAnyOther() {
        let ledger = makeLedger()
        ledger.receive(1)
        ledger.receive(2)
        XCTAssertEqual(ledger.heldCount, 2)
        let first = Recorder()
        let second = Recorder()

        register(first, to: ledger)
        register(second, to: ledger)
        XCTAssertEqual(first.events, [], "not inside add")
        runMainQueue()

        XCTAssertEqual(first.events, [1, 2], "in the order they came")
        XCTAssertEqual(second.events, [], "the next registration alone")
        XCTAssertEqual(ledger.heldCount, 0)
        Registry.removeListener(first.outListener.pointee)
        Registry.removeListener(second.outListener.pointee)
        runMainQueue()
    }

    /// R-7: after the count of registrations went back to 0, and with a removal still on its way.
    func testAnEventWhileTheOnlyRegistrationIsBeingRemovedIsHeld() {
        let ledger = makeLedger()
        let first = Recorder()
        register(first, to: ledger)
        runMainQueue()

        Registry.removeListener(first.outListener.pointee)
        ledger.receive(1)
        XCTAssertEqual(ledger.heldCount, 1, "CANCEL_REQUESTED is not ACTIVE")
        runMainQueue()
        ledger.receive(2)
        XCTAssertEqual(ledger.heldCount, 2)
        XCTAssertEqual(first.events, [])

        let next = Recorder()
        register(next, to: ledger)
        runMainQueue()

        XCTAssertEqual(next.events, [1, 2])
        Registry.removeListener(next.outListener.pointee)
        runMainQueue()
    }

    /// The row of 12.1 that AP-21 was rewritten for: the callback removes the only registration and adds a
    /// new one, and the rest of the held events go to the new one, with none lost and none twice.
    func testACallbackRemovingTheOnlyRegistrationLeavesTheRestForTheNextOne() {
        let ledger = makeLedger()
        for event in Int32(1)...5 { ledger.receive(event) }
        let first = Recorder()
        let second = Recorder()
        register(first, to: ledger)
        first.onEvent = { [first] event in
            guard event == 2 else { return }
            MainActor.assumeIsolated {
                Registry.removeListener(first.outListener.pointee)
                register(second, to: ledger)
            }
        }

        runMainQueue()
        runMainQueue()

        XCTAssertEqual(first.events, [1, 2])
        XCTAssertEqual(second.events, [3, 4, 5])
        XCTAssertEqual(first.releases, [true])
        XCTAssertEqual(ledger.heldCount, 0)
        Registry.removeListener(second.outListener.pointee)
        runMainQueue()
    }

    /// The same when the new registration comes much later, and with an event in between.
    func testHeldEventsSurviveAGapAfterTheCallbackRemovedTheOnlyRegistration() {
        let ledger = makeLedger()
        for event in Int32(1)...3 { ledger.receive(event) }
        let first = Recorder()
        register(first, to: ledger)
        first.onEvent = { [first] _ in Registry.removeListener(first.outListener.pointee) }
        runMainQueue()

        XCTAssertEqual(first.events, [1])
        XCTAssertEqual(ledger.heldCount, 2)
        ledger.receive(4)
        XCTAssertEqual(ledger.heldCount, 3)

        let next = Recorder()
        register(next, to: ledger)
        runMainQueue()

        XCTAssertEqual(next.events, [2, 3, 4])
        Registry.removeListener(next.outListener.pointee)
        runMainQueue()
    }

    /// An event that arrives inside a delivery of held events goes behind them.
    func testAnEventArrivingWhileHeldEventsAreDeliveredKeepsTheOrder() {
        let ledger = makeLedger()
        ledger.receive(1)
        ledger.receive(2)
        let recorder = Recorder()
        register(recorder, to: ledger)
        recorder.onEvent = { event in
            guard event == 1 else { return }
            MainActor.assumeIsolated { ledger.receive(3) }
        }

        runMainQueue()

        XCTAssertEqual(recorder.events, [1, 2, 3])
        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()
    }

    func test33rdEventDropsTheOldest() {
        let ledger = makeLedger()
        for event in Int32(1)...33 { ledger.receive(event) }
        XCTAssertEqual(ledger.heldCount, holdingLimit)
        let recorder = Recorder()

        register(recorder, to: ledger)
        runMainQueue()

        XCTAssertEqual(recorder.events, Array(2...33))
        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()
    }

    func test32EventsAreAllKept() {
        let ledger = makeLedger()
        for event in Int32(1)...32 { ledger.receive(event) }
        let recorder = Recorder()

        register(recorder, to: ledger)
        runMainQueue()

        XCTAssertEqual(recorder.events, Array(1...32))
        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()
    }

    /// The limit holds inside a delivery too: each held event brings 2 more.
    func testTheLimitHoldsWhileHeldEventsAreDelivered() {
        let ledger = makeLedger()
        for event in Int32(1)...32 { ledger.receive(event) }
        let recorder = Recorder()
        register(recorder, to: ledger)
        let most = MainHolder<Int>()
        recorder.onEvent = { event in
            guard event <= 32 else { return }
            MainActor.assumeIsolated {
                ledger.receive(1000 + event)
                ledger.receive(2000 + event)
                most.value = max(most.value ?? 0, ledger.heldCount)
            }
        }

        runMainQueue()

        XCTAssertEqual(most.value, holdingLimit)
        XCTAssertEqual(ledger.heldCount, 0)
        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()
    }

    /// Clipboard's change does not wait (part 2, 5.4).
    func testALedgerWithoutHoldingDropsEvents() {
        let ledger = makeLedger(holdLimit: 0)
        ledger.receive(1)
        XCTAssertEqual(ledger.heldCount, 0)
        let recorder = Recorder()
        register(recorder, to: ledger)
        runMainQueue()
        XCTAssertEqual(recorder.events, [])
        ledger.receive(2)
        XCTAssertEqual(recorder.events, [2])
        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()
    }

    // MARK: - The library's listener (part 2, 5.4)

    /// It runs once, after the first registration is in the ledger, so what the library delivers while
    /// the listener is added reaches that registration there and then, instead of waiting.
    func testTheFirstInsertionHookRunsOnceWithTheRegistrationInTheLedger() {
        let holder = MainHolder<EventLedger<Int32, EventCallback>>()
        let runs = MainHolder<Int>()
        let first = Recorder()
        let seenInside = MainHolder<[Int32]>()
        let ledger = makeLedger {
            runs.value = (runs.value ?? 0) + 1
            holder.value?.receive(9)
            seenInside.value = first.events
        }
        holder.value = ledger
        register(first, to: ledger)
        runMainQueue()
        XCTAssertEqual(runs.value, 1)
        XCTAssertEqual(seenInside.value, [9])
        XCTAssertEqual(first.events, [9])

        let second = Recorder()
        Registry.removeListener(first.outListener.pointee)
        register(second, to: ledger)
        runMainQueue()

        XCTAssertEqual(runs.value, 1, "the listener is added once and never taken away")
        Registry.removeListener(second.outListener.pointee)
        runMainQueue()
    }

    /// A registration cancelled before its turn does not count as the first.
    func testACancelledRegistrationDoesNotTriggerTheFirstInsertion() {
        let runs = MainHolder<Int>()
        let ledger = makeLedger { runs.value = (runs.value ?? 0) + 1 }
        let recorder = Recorder()
        register(recorder, to: ledger)
        Registry.removeListener(recorder.outListener.pointee)
        runMainQueue()

        XCTAssertNil(runs.value)
    }

    // MARK: - Two callback types (ntk_notification_listener_remove takes either)

    func testRemovalDoesNotNeedTheTypeOfTheCallback() {
        let events = makeLedger()
        let others = EventLedger<String, ntk_release_fn>(holdLimit: 0, deliver: { callback, userData, _ in callback(userData) })
        let first = Recorder()
        let second = Recorder()
        register(first, to: events)
        XCTAssertEqual(others.add(callback: recordingRelease as ntk_release_fn, userData: second.userData, release: recordingRelease,
                                  outListener: second.outListener), Entry.accepted)
        runMainQueue()
        XCTAssertEqual(others.entryCount, 1)

        Registry.removeListener(first.outListener.pointee)
        Registry.removeListener(second.outListener.pointee)
        runMainQueue()

        XCTAssertEqual(events.entryCount, 0)
        XCTAssertEqual(others.entryCount, 0)
        XCTAssertEqual(first.releases, [true])
        XCTAssertEqual(second.releases, [true])
    }

    // MARK: - Races

    /// Removal on another thread against deliveries on main: one release, and nothing after it.
    func testRemovalOnAnotherThreadAgainstDeliveries() {
        for round in 0..<200 {
            let ledger = makeLedger()
            let recorder = Recorder()
            register(recorder, to: ledger)
            runMainQueue()
            let handle = UInt(bitPattern: recorder.outListener.pointee)
            let race = RaceStart()
            let finished = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                race.waitForGo()
                Registry.removeListener(OpaquePointer(bitPattern: handle))
                finished.signal()
            }
            race.go(afterSpinning: (round % 20) * 100)
            for event in Int32(0)..<5 { ledger.receive(event) }
            XCTAssertEqual(finished.wait(timeout: .now() + 10), .success, "round \(round)")
            runMainQueue()

            XCTAssertEqual(recorder.releases, [true], "round \(round)")
            XCTAssertEqual(recorder.calls.last, "release", "round \(round)")
            let after = recorder.calls.count
            ledger.receive(100)
            XCTAssertEqual(recorder.calls.count, after, "round \(round)")
            // Each event is delivered or held, in order; none is lost.
            XCTAssertEqual(recorder.events, Array(0..<Int32(recorder.events.count)), "round \(round)")
            XCTAssertEqual(ledger.heldCount, 5 - recorder.events.count + 1, "round \(round)")
        }
    }
}

/// A list for hooks to append to.
private final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    var items: [String] { lock.withLock { values } }

    func append(_ value: String) {
        lock.withLock { values.append(value) }
    }
}
