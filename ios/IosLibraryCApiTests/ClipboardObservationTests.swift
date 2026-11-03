//
//  ClipboardObservationTests.swift
//  IosLibraryCApiTests
//

import IosLibrary
import UIKit
import XCTest
@testable import IosLibraryCApi

/// OP-13, OP-14, OP-16, OP-17 through C, on named pasteboards (part 2, 5.4, 6.1 and 12.1, "イベント"; P2-16,
/// P2-17), with the events `IosLibrary` really sends, so that the ledger runs on the real path: `EventLedgerTests`
/// has the same orders with a test-only event.
final class ClipboardObservationTests: ClipboardTestCase {
    private let plainType = "public.plain-text"
    private let queuedType = "com.example.queued"

    /// Says whether a change of `pasteboard` was posted since the holder was last set to false.
    private func arrivalWatcher(on pasteboard: UIPasteboard) -> (holder: MainHolder<Bool>, observer: any NSObjectProtocol) {
        let holder = MainHolder<Bool>()
        let observer = NotificationCenter.default.addObserver(forName: UIPasteboard.changedNotification, object: pasteboard, queue: .main) { _ in
            MainActor.assumeIsolated { holder.value = true }
        }
        return (holder, observer)
    }

    /// Observation belongs to the process: every test leaves it stopped.
    private func stop(file: StaticString = #filePath, line: UInt = #line) {
        let done = completion(file: file, line: line) { ntk_clipboard_stop_observing_async(recordDone, $0.userData, recordRelease) }
        XCTAssertEqual(done?.error, ClipboardErrorValue.none, file: file, line: line)
    }

    private func start(_ scope: ntk_clipboard_scope, file: StaticString = #filePath, line: UInt = #line) -> Int32? {
        var scope = scope
        return completion(file: file, line: line) { ntk_clipboard_start_observing_async(&scope, recordDone, $0.userData, recordRelease) }?.error
    }

    /// Registered once the main thread ran. The handle is in `recorder.outListener`.
    private func listen(_ recorder: ClipboardRecorder, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ntk_clipboard_add_change_listener(recordChange, recorder.userData, recordRelease, recorder.outListener),
                       ClipboardErrorValue.none, file: file, line: line)
        XCTAssertNotNil(recorder.outListener.pointee, file: file, line: line)
        runMainQueue(file: file, line: line)
    }

    private func remove(_ recorder: ClipboardRecorder, file: StaticString = #filePath, line: UInt = #line) {
        ntk_clipboard_listener_remove(recorder.outListener.pointee)
        runMainQueue(file: file, line: line)
    }

    /// Long enough for a change that would come; the tests that expect one wait on it instead.
    private func assertNoChange(_ recorder: ClipboardRecorder, file: StaticString = #filePath, line: UInt = #line) {
        spin(0.3)
        XCTAssertEqual(recorder.changes, [], file: file, line: line)
    }

    private func waitForChange(_ recorder: ClipboardRecorder, count: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        spin(5) { recorder.changes.count >= count }
        XCTAssertGreaterThanOrEqual(recorder.changes.count, count, "no change came", file: file, line: line)
    }

    /// The types a change added, in the order of the changes.
    private func addedTypes(_ recorder: ClipboardRecorder) -> [[String]] {
        recorder.changes.map(\.added).filter { !$0.isEmpty }
    }

    // MARK: - The entry

    func testTheListenerOutputIsNullOnEveryRejection() {
        let recorder = ClipboardRecorder()
        recorder.outListener.pointee = OpaquePointer(bitPattern: 0x10)

        XCTAssertEqual(ntk_clipboard_add_change_listener(nil, recorder.userData, recordRelease, recorder.outListener), ClipboardErrorValue.invalidParameter)

        XCTAssertNil(recorder.outListener.pointee, "R-8")
        XCTAssertEqual(recorder.releases, [true])
    }

    func testANullListenerOutputIsRejected() {
        let recorder = ClipboardRecorder()
        XCTAssertEqual(ntk_clipboard_add_change_listener(recordChange, recorder.userData, recordRelease, nil), ClipboardErrorValue.invalidParameter)
        XCTAssertEqual(recorder.releases, [true])
        runMainQueue()
        XCTAssertEqual(recorder.calls, ["release"])
    }

    func testARejectedListenerOffTheMainThreadReleasesOnThatThread() {
        let recorder = ClipboardRecorder()
        XCTAssertEqual(onAnotherThread { ntk_clipboard_add_change_listener(nil, recorder.userData, recordRelease, recorder.outListener) },
                       ClipboardErrorValue.invalidParameter)
        XCTAssertEqual(recorder.releases, [false])
    }

    func testStartingAndStoppingReject() {
        var bad = named("a.name")
        bad.reserved1 = 1
        let recorder = ClipboardRecorder()
        XCTAssertEqual(ntk_clipboard_start_observing_async(&bad, recordDone, recorder.userData, recordRelease), ClipboardErrorValue.invalidParameter)
        XCTAssertEqual(recorder.releases, [true])

        for call in [{ ntk_clipboard_start_observing_async(nil, nil, $0.userData, recordRelease) },
                     { ntk_clipboard_stop_observing_async(nil, $0.userData, recordRelease) }] as [(ClipboardRecorder) -> Int32] {
            let other = ClipboardRecorder()
            XCTAssertEqual(call(other), ClipboardErrorValue.invalidParameter)
            XCTAssertEqual(other.releases, [true])
        }
    }

    func testRemovingNullDoesNothing() {
        ntk_clipboard_listener_remove(nil)
    }

    func testAddingAndRemovingFromAnotherThreadWithTheMainThreadStopped() {
        let recorder = ClipboardRecorder()
        let returned = onAnotherThread { () -> Bool in
            guard ntk_clipboard_add_change_listener(recordChange, recorder.userData, recordRelease, recorder.outListener) == 0 else { return false }
            ntk_clipboard_listener_remove(recorder.outListener.pointee)
            return true
        }
        XCTAssertEqual(returned, true)
        XCTAssertEqual(recorder.calls, [])
        runMainQueue()
        XCTAssertEqual(recorder.releases, [true], "released on the main thread, never inserted")
    }

    // MARK: - Observing

    func testStoppingWhenNotObservingSucceeds() {
        stop()
        stop()
    }

    func testRegisteringDoesNotStartObserving() {
        stop()
        let scope = makeNamedPasteboard()
        let recorder = ClipboardRecorder()
        listen(recorder)
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        assertNoChange(recorder)
        remove(recorder)
    }

    func testAChangeComesToEveryListenerOnTheMainThread() throws {
        let scope = makeNamedPasteboard()
        let first = ClipboardRecorder()
        let second = ClipboardRecorder()
        listen(first)
        listen(second)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }

        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        waitForChange(first)
        waitForChange(second)

        XCTAssertEqual(first.changes, second.changes)
        let change = try XCTUnwrap(first.changes.first)
        XCTAssertEqual(change.kind, 0)
        XCTAssertEqual(change.scopeKind, 1)
        XCTAssertEqual(change.scopeName, String(cString: scope.name))
        XCTAssertTrue(change.onMain)
        XCTAssertTrue(first.changes.contains { $0.added.contains(plainType) }, "\(first.changes)")
        remove(first)
        remove(second)
        XCTAssertEqual(first.releases, [true])
        XCTAssertEqual(second.releases, [true])
    }

    func testRemovingThePasteboardGivesARemoval() {
        let scope = makeNamedPasteboard()
        var scopeValue = scope
        let recorder = ClipboardRecorder()
        listen(recorder)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }

        XCTAssertEqual(completion { ntk_clipboard_remove_pasteboard_async(&scopeValue, recordDone, $0.userData, recordRelease) }?.error, ClipboardErrorValue.none)
        spin(5) { recorder.changes.contains { $0.kind == 1 } }

        let removal = recorder.changes.first { $0.kind == 1 }
        XCTAssertEqual(removal?.scopeKind, 1)
        XCTAssertEqual(removal?.scopeName, String(cString: scope.name))
        XCTAssertEqual(removal?.added, [])
        remove(recorder)
    }

    /// P2-17: removing the listener leaves the observation going, for the next one.
    func testRemovingAListenerLeavesObservingGoing() {
        let scope = makeNamedPasteboard()
        let gone = ClipboardRecorder()
        listen(gone)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }
        remove(gone)
        XCTAssertEqual(gone.releases, [true])

        let next = ClipboardRecorder()
        listen(next)
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        waitForChange(next)

        XCTAssertEqual(gone.changes, [], "nothing after the removal")
        remove(next)
    }

    /// Part 2, 5.4: Clipboard holds nothing for a later listener.
    func testAChangeWithNoListenerIsNotHeld() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        spin(0.3)
        let late = ClipboardRecorder()
        listen(late)
        assertNoChange(late)
        remove(late)
    }

    func testStoppingStopsTheChanges() {
        let scope = makeNamedPasteboard()
        let recorder = ClipboardRecorder()
        listen(recorder)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        stop()
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        assertNoChange(recorder)
        remove(recorder)
    }

    func testASecondStartReplacesTheFirst() throws {
        let first = makeNamedPasteboard()
        let second = makeNamedPasteboard()
        let recorder = ClipboardRecorder()
        listen(recorder)
        XCTAssertEqual(start(first), ClipboardErrorValue.none)
        XCTAssertEqual(start(second), ClipboardErrorValue.none)
        defer { stop() }

        XCTAssertEqual(copy(plainText("x"), to: first), ClipboardErrorValue.none)
        assertNoChange(recorder)
        XCTAssertEqual(copy(plainText("x"), to: second), ClipboardErrorValue.none)
        waitForChange(recorder)
        XCTAssertEqual(try XCTUnwrap(recorder.changes.first).scopeName, String(cString: second.name))
        remove(recorder)
    }

    /// Part 2, 6.1 and the header: when a start fails, the previous observation has already stopped.
    func testAFailedStartLeavesNothingObserved() {
        let scope = makeNamedPasteboard()
        let recorder = ClipboardRecorder()
        listen(recorder)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }

        XCTAssertEqual(start(named("ntk.capi.tests.notcreated.\(UUID().uuidString)")), ClipboardErrorValue.unavailable)

        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        assertNoChange(recorder)
        remove(recorder)
    }

    // MARK: - The ledger on the real path

    /// Writing the pasteboard directly inside a callback: the library sends the event before the write
    /// returns (the local observer says so), so it arrives during a delivery. It waits for that delivery,
    /// and both listeners see the same order.
    func testAChangeArrivingDuringADeliveryComesAfterItForEveryone() throws {
        let scope = makeNamedPasteboard()
        let name = String(cString: scope.name)
        let first = ClipboardRecorder()
        let second = ClipboardRecorder()
        listen(first)
        listen(second)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }

        let pasteboard = try XCTUnwrap(UIPasteboard(name: UIPasteboard.Name(name), create: false))
        let nested = "com.example.nested"
        let notified = MainHolder<Bool>()
        let observer = NotificationCenter.default.addObserver(forName: UIPasteboard.changedNotification, object: pasteboard, queue: .main) { _ in
            MainActor.assumeIsolated { notified.value = true }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let secondSeen = MainHolder<Int>()
        let arrivedInside = MainHolder<Bool>()
        first.onChange = { change in
            guard change.added.contains(self.plainType) else { return }
            MainActor.assumeIsolated {
                notified.value = false
                pasteboard.setItems([[nested: Data([1])]])
                arrivedInside.value = notified.value
                secondSeen.value = first.changes.count - second.changes.count
            }
        }

        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        spin(5) { addedTypes(first).count >= 2 && addedTypes(second).count >= 2 }

        XCTAssertEqual(arrivedInside.value, true, "the event did not arrive inside the delivery, so this test did not reach that path")
        XCTAssertEqual(first.deepestChange, 1, "a delivery ran inside a delivery")
        XCTAssertEqual(secondSeen.value, 1, "the second listener gets the change in progress after this callback")
        XCTAssertEqual(first.changes, second.changes, "every listener sees the same order")
        XCTAssertEqual(addedTypes(first).first?.contains(plainType), true)
        XCTAssertEqual(addedTypes(first).last, [nested])
        remove(first)
        remove(second)
    }

    /// Part 2, 6.1: after a stop has completed nothing more comes, also of what was queued. The sequence is the
    /// real one: the write in the test body is not inside a block of the main queue, so the callback can turn
    /// the run loop until the stop completes. The second write arrives during the delivery of the first.
    func testAStopInsideADeliveryDropsWhatWasQueued() throws {
        let scope = makeNamedPasteboard()
        let first = ClipboardRecorder()
        let second = ClipboardRecorder()
        listen(first)
        listen(second)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }
        let pasteboard = try XCTUnwrap(UIPasteboard(name: UIPasteboard.Name(String(cString: scope.name)), create: false))
        let arrived = arrivalWatcher(on: pasteboard)
        defer { NotificationCenter.default.removeObserver(arrived.observer) }
        let holder = arrived.holder
        let stopped = ClipboardRecorder()
        let seen = MainHolder<[Int]>()
        first.onChange = { _ in
            MainActor.assumeIsolated {
                guard seen.value == nil else { return }
                seen.value = []
                holder.value = false
                pasteboard.setItems([[self.queuedType: Data([2])]])
                XCTAssertEqual(holder.value, true, "the second write did not arrive inside the delivery, so this test did not reach that path")
                XCTAssertEqual(ntk_clipboard_stop_observing_async(recordDone, stopped.userData, recordRelease), ClipboardErrorValue.none)
                self.spin(5) { !stopped.releases.isEmpty }
                seen.value = [first.changes.count, second.changes.count]
            }
        }

        pasteboard.setItems([["com.example.first": Data([1])]])
        spin(0.3)

        XCTAssertEqual(stopped.calls, ["completion", "release"], "the stop did not complete inside the callback")
        XCTAssertEqual(seen.value, [1, 0])
        XCTAssertEqual(first.changes.count, 1, "came after the stop completed: \(first.changes)")
        XCTAssertEqual(second.changes, [], "came after the stop completed")
        remove(first)
        remove(second)
    }

    /// The same for a second start, which stops the first observation (part 2, 6.1). What comes of the new one comes.
    func testASecondStartInsideADeliveryDropsWhatWasQueuedOfTheFirst() throws {
        let scope = makeNamedPasteboard()
        let other = makeNamedPasteboard()
        let otherPointer = UInt(bitPattern: array([other]))
        let recorder = ClipboardRecorder()
        listen(recorder)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }
        let pasteboard = try XCTUnwrap(UIPasteboard(name: UIPasteboard.Name(String(cString: scope.name)), create: false))
        let arrived = arrivalWatcher(on: pasteboard)
        defer { NotificationCenter.default.removeObserver(arrived.observer) }
        let holder = arrived.holder
        let started = ClipboardRecorder()
        let once = MainHolder<Bool>()
        recorder.onChange = { _ in
            MainActor.assumeIsolated {
                guard once.value == nil else { return }
                once.value = true
                holder.value = false
                pasteboard.setItems([[self.queuedType: Data([2])]])
                XCTAssertEqual(holder.value, true, "the second write did not arrive inside the delivery, so this test did not reach that path")
                XCTAssertEqual(ntk_clipboard_start_observing_async(UnsafePointer(bitPattern: otherPointer), recordDone, started.userData, recordRelease), ClipboardErrorValue.none)
                self.spin(5) { !started.releases.isEmpty }
            }
        }

        pasteboard.setItems([["com.example.first": Data([1])]])
        spin(0.3)

        XCTAssertEqual(started.calls, ["completion", "release"], "the start did not complete inside the callback")
        XCTAssertEqual(recorder.changes.count, 1, "came after the second start completed: \(recorder.changes)")
        XCTAssertEqual(copy(plainText("x"), to: other), ClipboardErrorValue.none)
        waitForChange(recorder, count: 2)
        XCTAssertEqual(recorder.changes.last?.scopeName, String(cString: other.name))
        remove(recorder)
    }

    /// A stop when nothing is delivered takes nothing from the observation after it.
    func testAStartAfterAStopDeliversAgain() {
        let scope = makeNamedPasteboard()
        let recorder = ClipboardRecorder()
        listen(recorder)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        stop()
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        waitForChange(recorder)
        remove(recorder)
    }

    /// Part 2, 6.1: what the C ABI has no value for reaches no listener. Neither event touches a pasteboard.
    func testAnEventTheCABICannotSayReachesNoListener() {
        let recorder = ClipboardRecorder()
        listen(recorder)
        ClipboardReceiver.receive(ClipboardChangeEvent(kind: .changedDetectedOnForeground, scope: .general))
        ClipboardReceiver.receive(ClipboardChangeEvent(kind: .changedDetectedOnForeground, scope: .named("a.name")))
        XCTAssertEqual(recorder.changes, [])

        ClipboardReceiver.receive(ClipboardChangeEvent(kind: .removed, scope: .named("a.name")))
        XCTAssertEqual(recorder.changes.count, 1, "the path itself works")
        remove(recorder)
    }

    /// The only delivery in progress removes its own registration: the release waits for the return, and
    /// the listener after it still gets the change.
    func testAListenerRemovingItselfDuringItsCallback() {
        let scope = makeNamedPasteboard()
        let leaving = ClipboardRecorder()
        let staying = ClipboardRecorder()
        listen(leaving)
        listen(staying)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }
        let handle = UInt(bitPattern: leaving.outListener.pointee)
        let releasedInside = MainHolder<Int>()
        leaving.onChange = { _ in
            ntk_clipboard_listener_remove(OpaquePointer(bitPattern: handle))
            MainActor.assumeIsolated { releasedInside.value = leaving.releases.count }
        }

        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        waitForChange(leaving)
        waitForChange(staying)
        spin(5) { !leaving.releases.isEmpty }

        XCTAssertEqual(releasedInside.value, 0, "no release inside its callback")
        XCTAssertEqual(leaving.releases, [true])
        XCTAssertEqual(leaving.changes.count, 1, "nothing after the removal")

        let count = staying.changes.count
        XCTAssertEqual(copy(plainText("y"), to: scope), ClipboardErrorValue.none)
        waitForChange(staying, count: count + 1)
        XCTAssertEqual(leaving.changes.count, 1)
        remove(staying)
    }

    /// From another thread during the callback, with the main thread inside it: it returns at once, and the
    /// release comes after the callback.
    func testARemovalFromAnotherThreadDuringTheCallback() {
        let scope = makeNamedPasteboard()
        let recorder = ClipboardRecorder()
        listen(recorder)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }
        let handle = UInt(bitPattern: recorder.outListener.pointee)
        let returned = MainHolder<Bool>()
        recorder.onChange = { _ in
            let done = onAnotherThread { () -> Bool in
                ntk_clipboard_listener_remove(OpaquePointer(bitPattern: handle))
                return recorder.releases.isEmpty
            }
            MainActor.assumeIsolated { returned.value = done }
        }

        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        waitForChange(recorder)
        spin(5) { !recorder.releases.isEmpty }

        XCTAssertEqual(returned.value, true)
        XCTAssertEqual(recorder.releases, [true])
        XCTAssertEqual(recorder.changes.count, 1)
    }

    /// A listener added inside a callback waits for the main thread: it does not get the change in progress.
    func testAListenerAddedDuringACallbackStartsWithTheNextChange() {
        let scope = makeNamedPasteboard()
        let recorder = ClipboardRecorder()
        let added = ClipboardRecorder()
        listen(recorder)
        XCTAssertEqual(start(scope), ClipboardErrorValue.none)
        defer { stop() }
        let once = MainHolder<Bool>()
        recorder.onChange = { _ in
            MainActor.assumeIsolated {
                guard once.value == nil else { return }
                once.value = true
                XCTAssertEqual(ntk_clipboard_add_change_listener(recordChange, added.userData, recordRelease, added.outListener), ClipboardErrorValue.none)
            }
        }

        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        waitForChange(recorder)
        spin(0.3)
        let before = added.changes.count
        XCTAssertEqual(before, 0, "\(added.changes)")

        XCTAssertEqual(copy(plainText("y"), to: scope), ClipboardErrorValue.none)
        waitForChange(added)
        remove(recorder)
        remove(added)
    }
}
