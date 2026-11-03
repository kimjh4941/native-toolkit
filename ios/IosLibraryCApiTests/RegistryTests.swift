//
//  RegistryTests.swift
//  IosLibraryCApiTests
//

import Foundation
import IosLibrary
import XCTest
@testable import IosLibraryCApi

/// The release and the completion of an accepted operation: part 1, 5.7's tables and the orders below
/// them, chapter 6. The tests run on the main thread, so what they queue waits for `runMainQueue`, and
/// `onAnotherThread` keeps the main thread stopped while another thread calls.
@MainActor
final class RegistryTests: XCTestCase {

    // MARK: - Exactly once, on main, after the call

    func testFromMainNothingRunsInsideTheCall() {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()

        let error = acceptTestOperation(recorder) { registration in
            holder.value = registration
            registration.completeWithSuccess()
        }

        XCTAssertEqual(error, Entry.accepted)
        XCTAssertNil(holder.value, "started inside the call")
        XCTAssertEqual(recorder.completions, [])
        XCTAssertEqual(recorder.releases, [])
        XCTAssertNotEqual(recorder.outRequestID.pointee, 0)

        runMainQueue()

        XCTAssertNotNil(holder.value)
        XCTAssertEqual(recorder.completions, [.init(id: recorder.outRequestID.pointee, error: successValue, systemCode: 0, onMain: true)])
        XCTAssertEqual(recorder.releases, [true])
        XCTAssertEqual(recorder.calls, ["completion", "release"])
    }

    func testFromAnotherThreadStartCompletionAndReleaseAreOnMainAndTheCallDoesNotWaitForMain() {
        let recorder = Recorder()
        let started = MainHolder<Bool>()

        // The main thread waits for this thread here, so a call that needed the main thread would time out.
        let returned = onAnotherThread { () -> Bool in
            let error = acceptTestOperation(recorder) { registration in
                started.value = Thread.isMainThread
                registration.completeWithSuccess()
            }
            return error == Entry.accepted && recorder.outRequestID.pointee != 0 && !Thread.isMainThread
        }
        XCTAssertEqual(returned, true)
        XCTAssertNil(started.value, "the main thread cannot have run it yet")
        XCTAssertEqual(recorder.releases, [])

        runMainQueue()

        XCTAssertEqual(started.value, true)
        XCTAssertEqual(recorder.completions.map(\.onMain), [true])
        XCTAssertEqual(recorder.releases, [true])
    }

    /// A later completion from the library does nothing: the mark and the state stop it.
    func testASecondCompletionDoesNothing() {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder) { holder.value = $0 }
        runMainQueue()
        let registration = holder.value

        registration?.completeWithSuccess()
        registration?.completeWithSuccess()

        XCTAssertEqual(recorder.completions.count, 1)
        XCTAssertEqual(recorder.releases.count, 1)
    }

    /// The completion row: with the mark already set it does not call again, and it still releases, once the
    /// callback that is on the stack has returned.
    func testACompletionInsideTheCallbackOnlyLeavesTheReleaseForItsReturn() throws {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        let inner = MainHolder<Bool>()
        let seenInside = MainHolder<[Bool]>()
        acceptTestOperation(recorder) { holder.value = $0 }
        runMainQueue()
        let registration = try XCTUnwrap(holder.value)
        recorder.onCompletion = { _ in
            MainActor.assumeIsolated {
                registration.complete { _, _, _ in inner.value = true }
                seenInside.value = recorder.releases
            }
        }

        registration.completeWithSuccess()

        XCTAssertNil(inner.value)
        XCTAssertEqual(seenInside.value, [])
        XCTAssertEqual(recorder.completions.count, 1)
        XCTAssertEqual(recorder.timeline, ["enter", "return", "release"])
        XCTAssertEqual(registration.currentState, .released)
    }

    func testReleaseMayBeNull() {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder, hasRelease: false) { holder.value = $0 }
        runMainQueue()

        holder.value?.completeWithSuccess()

        XCTAssertEqual(recorder.completions.count, 1)
        XCTAssertEqual(holder.value?.currentState, .released)
    }

    func testIdsCountUpAndAreNeverReused() {
        let first = Recorder()
        let second = Recorder()
        acceptTestOperation(first, cancellable: nil) { $0.completeWithSuccess() }
        runMainQueue()
        acceptTestOperation(second, cancellable: nil) { $0.completeWithSuccess() }
        runMainQueue()

        XCTAssertGreaterThan(first.outRequestID.pointee, 0)
        XCTAssertGreaterThan(second.outRequestID.pointee, first.outRequestID.pointee)
    }

    /// P2-21: without an out pointer there is nothing to cancel with, and the operation still runs.
    func testTheRequestIdOutputMayBeNull() {
        let recorder = Recorder()
        acceptTestOperation(recorder, writesID: false) { $0.completeWithSuccess() }
        runMainQueue()

        XCTAssertEqual(recorder.outRequestID.pointee, 0)
        XCTAssertEqual(recorder.completions.count, 1)
        XCTAssertEqual(recorder.releases.count, 1)
    }

    // MARK: - tryRelease

    func testTryReleaseWorksOnceAndOnlyFromTheExpectedState() throws {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder) { holder.value = $0 }
        runMainQueue()
        let registration = try XCTUnwrap(holder.value)

        XCTAssertFalse(Registry.tryRelease(registration, expected: .cancelRequested))
        XCTAssertEqual(recorder.releases, [])
        XCTAssertEqual(registration.currentState, .active)

        XCTAssertTrue(Registry.tryRelease(registration, expected: .active))
        XCTAssertEqual(recorder.releases, [true])
        XCTAssertEqual(registration.currentState, .released)

        XCTAssertFalse(Registry.tryRelease(registration, expected: .active))
        XCTAssertFalse(Registry.tryRelease(registration, expected: .released))
        XCTAssertEqual(recorder.releases, [true])
    }

    func testAReleasedRequestLeavesTheTable() {
        let count = Registry.requestCount
        let recorder = Recorder()
        acceptTestOperation(recorder) { $0.completeWithSuccess() }
        XCTAssertEqual(Registry.requestCount, count + 1)

        runMainQueue()

        XCTAssertEqual(Registry.requestCount, count)
    }

    /// A request that cannot be cancelled is not in the table at all.
    func testARequestThatCannotBeCancelledHasNoBoxAndIsNotInTheTable() {
        let count = Registry.requestCount
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder, cancellable: nil) { holder.value = $0 }
        XCTAssertEqual(Registry.requestCount, count)
        runMainQueue()
        XCTAssertNil(holder.value?.requestBox)

        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)
        runMainQueue()

        XCTAssertEqual(holder.value?.currentState, .active)
        holder.value?.completeWithSuccess()
        XCTAssertEqual(recorder.completions.map(\.error), [successValue])
    }

    /// release is the caller's code and may call back in: it runs outside the table's lock.
    func testReleaseMayCallBackIn() {
        let recorder = Recorder()
        let other = Recorder()
        recorder.onRelease = { [other] in
            Registry.cancel(id: UInt64.max, request: DialogReceiver.cancelKind)
            _ = acceptTestOperation(other) { $0.completeWithSuccess() }
        }
        acceptTestOperation(recorder) { $0.completeWithSuccess() }

        runMainQueue()
        runMainQueue()

        XCTAssertEqual(recorder.releases.count, 1)
        XCTAssertEqual(other.releases.count, 1)
    }

    // MARK: - Rejected at the entry (C-3)

    func testARejectionReleasesOnTheCallingThreadBeforeItReturnsAndCompletesNothing() {
        let recorder = Recorder()
        let count = Registry.requestCount

        let error = Entry.reject(.invalidParameter, userData: recorder.userData, release: recordingRelease)

        XCTAssertEqual(error, 1)
        XCTAssertEqual(recorder.releases, [true], "on the main thread here, before the return")

        let offMain = Recorder()
        let seen = onAnotherThread { () -> [Bool] in
            _ = Entry.reject(ntk_share_error(NTK_SHARE_ERROR_EMPTY_CONTENT), userData: offMain.userData, release: recordingRelease)
            return offMain.releases
        }
        XCTAssertEqual(seen, [false], "on the calling thread, before the return, with the main thread stopped")

        runMainQueue()
        XCTAssertEqual(recorder.releases.count, 1)
        XCTAssertEqual(offMain.releases.count, 1)
        XCTAssertEqual(recorder.completions, [])
        XCTAssertEqual(offMain.completions, [])
        XCTAssertEqual(Registry.requestCount, count)
    }

    func testARejectionReturnsTheErrorItWasGivenAndReleaseMayBeNull() {
        XCTAssertEqual(Entry.reject(.notSupported, userData: nil, release: nil), 3)
        XCTAssertEqual(Entry.reject(.notInitialized, userData: nil, release: nil), 2)
        XCTAssertEqual(Entry.reject(ntk_share_error(NTK_SHARE_ERROR_EMPTY_CONTENT), userData: nil, release: nil),
                       ntk_share_error(NTK_SHARE_ERROR_EMPTY_CONTENT))
    }

    // MARK: - Cancel

    func testCancelBeforeTheFirstMainTurnNeverStartsAndCompletesAsCanceled() throws {
        let recorder = Recorder()
        let started = MainHolder<Registration<OperationCallback>>()
        let count = Registry.requestCount
        acceptTestOperation(recorder) { started.value = $0 }

        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)

        XCTAssertEqual(recorder.completions, [], "the completion comes on a later turn")
        XCTAssertEqual(recorder.releases, [])

        runMainQueue()

        XCTAssertNil(started.value)
        XCTAssertEqual(recorder.completions.map(\.error), [canceledValue])
        XCTAssertEqual(recorder.completions.map(\.onMain), [true])
        XCTAssertEqual(recorder.calls, ["completion", "release"])
        XCTAssertEqual(Registry.requestCount, count)
    }

    /// The same with the main thread stopped from the accept to the cancel (part 2, 12.1).
    func testCancelFromAnotherThreadBeforeTheFirstMainTurn() {
        let recorder = Recorder()
        let started = MainHolder<Bool>()

        let done = onAnotherThread { () -> Bool in
            _ = acceptTestOperation(recorder) { _ in started.value = true }
            Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)
            return recorder.completions.isEmpty && recorder.releases.isEmpty
        }
        XCTAssertEqual(done, true)
        runMainQueue()

        XCTAssertNil(started.value)
        XCTAssertEqual(recorder.completions.map(\.error), [canceledValue])
        XCTAssertEqual(recorder.completions.map(\.onMain), [true])
        XCTAssertEqual(recorder.releases, [true])
    }

    /// Part 2, 5.3: the box closes inside the call, on the caller's thread with the main thread stopped,
    /// for both kinds of request. So a start that was already queued would find it closed.
    func testCancelClosesTheBoxInsideTheCallFromAnotherThread() throws {
        for request in [DialogReceiver.cancelKind, ClipboardReceiver.loadCancelKind] {
            let recorder = Recorder()
            let holder = MainHolder<Registration<OperationCallback>>()
            acceptTestOperation(recorder, cancellable: request) { holder.value = $0 }
            runMainQueue()
            let registration = try XCTUnwrap(holder.value)
            let box = try XCTUnwrap(registration.requestBox)
            XCTAssertFalse(box.isClosed)

            let closed = onAnotherThread { () -> Bool in
                Registry.cancel(id: recorder.outRequestID.pointee, request: request)
                return box.isClosed
            }

            XCTAssertEqual(closed, true)
            XCTAssertEqual(registration.currentState, .cancelRequested)
            XCTAssertEqual(recorder.completions, [])
            runMainQueue()
            XCTAssertEqual(recorder.completions.map(\.error), [canceledValue])
            XCTAssertEqual(recorder.releases, [true])
        }
    }

    /// Part 2, 5.3: a cancel before the first main turn closes a box that is already there, inside the call.
    func testACancelBeforeTheStartClosesTheBox() {
        let closes = BoxCloses()
        let kind = CancellableKind(name: "test") { closes.record($0) }
        let recorder = Recorder()
        let started = MainHolder<Bool>()
        acceptTestOperation(recorder, cancellable: kind) { _ in started.value = true }

        Registry.cancel(id: recorder.outRequestID.pointee, request: kind)

        XCTAssertEqual(closes.count, 1, "inside the call, before the first main turn")
        XCTAssertNil(started.value)
        runMainQueue()
        XCTAssertEqual(closes.count, 1)
        XCTAssertNil(started.value)
        XCTAssertEqual(recorder.completions.map(\.error), [canceledValue])
        XCTAssertEqual(recorder.releases, [true])
    }

    /// A RELEASED registration does not start (the start row).
    func testARegistrationReleasedBeforeItsTurnDoesNotStart() throws {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder) { holder.value = $0 }
        runMainQueue()
        let registration = try XCTUnwrap(holder.value)
        XCTAssertTrue(Registry.tryRelease(registration, expected: .active))
        let started = MainHolder<Bool>()

        registration.startIfActive { _ in started.value = true }

        XCTAssertNil(started.value)
        XCTAssertEqual(recorder.releases, [true])
    }

    /// The order table: a cancel inside the completion's callback gets the release from the queued
    /// removal, after the callback returned, and no second completion.
    func testCancelDuringTheCompletionCompletesOnceAndReleasesOnce() throws {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder) { holder.value = $0 }
        runMainQueue()
        let registration = try XCTUnwrap(holder.value)
        let seenInside = MainHolder<[Bool]>()
        recorder.onCompletion = { completion in
            Registry.cancel(id: completion.id, request: DialogReceiver.cancelKind)
            MainActor.assumeIsolated { seenInside.value = recorder.releases }
        }

        registration.completeWithSuccess()

        XCTAssertEqual(seenInside.value, [], "no release inside the callback")
        XCTAssertEqual(recorder.releases, [], "the release is the removal's, not this completion's")
        XCTAssertEqual(registration.currentState, .cancelRequested)

        runMainQueue()

        XCTAssertEqual(recorder.completions.map(\.error), [successValue])
        XCTAssertEqual(recorder.releases, [true])
        XCTAssertEqual(registration.currentState, .released)
    }

    func testACompletionAfterACancelCompletesAsCanceledAndTheRemovalThenDoesNothing() throws {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder) { holder.value = $0 }
        runMainQueue()
        let registration = try XCTUnwrap(holder.value)

        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)
        registration.completeWithSuccess()

        XCTAssertEqual(recorder.completions.map(\.error), [canceledValue], "the result is dropped")
        XCTAssertEqual(recorder.releases, [true])

        runMainQueue()

        XCTAssertEqual(recorder.completions.count, 1, "the removal does nothing after RELEASED")
        XCTAssertEqual(recorder.releases.count, 1)
    }

    /// The mark also covers CANCELED: a result that arrives inside that callback does not call it again.
    func testAResultArrivingInsideTheCanceledCallbackDoesNotCompleteAgain() throws {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder) { holder.value = $0 }
        runMainQueue()
        let registration = try XCTUnwrap(holder.value)
        let file = try makeLoadedFile()
        recorder.onCompletion = { _ in
            MainActor.assumeIsolated { registration.completeWithSuccess(result: ClipboardReceiver.loadedFile(at: file)) }
        }

        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)
        runMainQueue()

        XCTAssertEqual(recorder.completions.map(\.error), [canceledValue])
        XCTAssertEqual(recorder.releases.count, 1)
        XCTAssertFalse(exists(file))
    }

    func testACompletionAfterRemovalDoesNothing() throws {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder) { holder.value = $0 }
        runMainQueue()
        let registration = try XCTUnwrap(holder.value)
        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)
        runMainQueue()
        XCTAssertEqual(registration.currentState, .released)

        registration.completeWithSuccess()

        XCTAssertEqual(recorder.completions.map(\.error), [canceledValue])
        XCTAssertEqual(recorder.releases.count, 1)
    }

    func testCancelAfterTheCompletionUnknownIdsAndTheOtherKindDoNothing() throws {
        let recorder = Recorder()
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder) { $0.completeWithSuccess() }
        runMainQueue()
        let done = recorder.outRequestID.pointee

        Registry.cancel(id: done, request: DialogReceiver.cancelKind)
        Registry.cancel(id: 0, request: DialogReceiver.cancelKind)
        Registry.cancel(id: UInt64.max, request: ClipboardReceiver.loadCancelKind)
        runMainQueue()
        XCTAssertEqual(recorder.completions.map(\.error), [successValue])
        XCTAssertEqual(recorder.releases.count, 1)

        let other = Recorder()
        acceptTestOperation(other, cancellable: ClipboardReceiver.loadCancelKind) { holder.value = $0 }
        runMainQueue()
        Registry.cancel(id: other.outRequestID.pointee, request: DialogReceiver.cancelKind)
        runMainQueue()
        let registration = try XCTUnwrap(holder.value)
        XCTAssertEqual(registration.currentState, .active, "ntk_dialog_cancel with a load's id is an unknown id")
        XCTAssertEqual(registration.requestBox?.isClosed, false)
        registration.completeWithSuccess()
    }

    func testASecondCancelDoesNothing() {
        let recorder = Recorder()
        acceptTestOperation(recorder)
        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)
        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)
        runMainQueue()
        runMainQueue()

        XCTAssertEqual(recorder.completions.count, 1)
        XCTAssertEqual(recorder.releases.count, 1)
    }

    // MARK: - The release never overlaps a callback (part 1, 5.7)

    /// A removal on a run loop that the callback spins: it runs there, the release waits for the return,
    /// and the release still comes, with nothing else queued to do it.
    func testARemovalRunningInsideTheCallbackLeavesTheReleaseForItsReturn() throws {
        let recorder = Recorder()
        let registration = try acceptedRegistration(recorder)
        let seenInside = MainHolder<[Bool]>()
        recorder.onCompletion = { completion in
            MainActor.assumeIsolated {
                Registry.cancel(id: completion.id, request: DialogReceiver.cancelKind)
                runMainQueue()
                seenInside.value = recorder.releases
            }
        }

        registration.completeWithSuccess()

        XCTAssertEqual(seenInside.value, [])
        XCTAssertEqual(recorder.timeline, ["enter", "return", "release"])
        XCTAssertEqual(registration.currentState, .released)
        runMainQueue()
        assertReleasedOnceOutsideCallbacks(recorder)
    }

    /// The same inside CANCELED: there the removal is what is on the stack.
    func testACompletionInsideTheCanceledCallbackLeavesTheReleaseForItsReturn() throws {
        let recorder = Recorder()
        let registration = try acceptedRegistration(recorder)
        let seenInside = MainHolder<[Bool]>()
        recorder.onCompletion = { _ in
            MainActor.assumeIsolated {
                registration.completeWithSuccess()
                seenInside.value = recorder.releases
            }
        }

        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)
        runMainQueue()

        XCTAssertEqual(seenInside.value, [])
        XCTAssertEqual(recorder.completions.map(\.error), [canceledValue])
        XCTAssertEqual(recorder.timeline, ["enter", "return", "release"])
    }

    /// The release that came due in ACTIVE goes from the state at the return: a cancel came meanwhile.
    func testAReleaseThatCameDueThenACancelStillReleasesOnce() throws {
        let recorder = Recorder()
        let registration = try acceptedRegistration(recorder)
        recorder.onCompletion = { completion in
            MainActor.assumeIsolated {
                registration.complete { _, _, _ in }
                Registry.cancel(id: completion.id, request: DialogReceiver.cancelKind)
            }
        }

        registration.completeWithSuccess()

        XCTAssertEqual(recorder.timeline, ["enter", "return", "release"])
        runMainQueue()
        XCTAssertEqual(recorder.completions.map(\.error), [successValue])
        assertReleasedOnceOutsideCallbacks(recorder)
    }

    /// Only the outermost return does it.
    func testANestedCallbackReturningDoesNotRelease() throws {
        let recorder = Recorder()
        let registration = try acceptedRegistration(recorder)
        let seenAfterInner = MainHolder<[Bool]>()

        registration.runCallback {
            registration.runCallback {
                Registry.tryRelease(registration, expected: .active)
            }
            seenAfterInner.value = recorder.releases
        }

        XCTAssertEqual(seenAfterInner.value, [])
        XCTAssertEqual(recorder.releases, [true])
    }

    /// The other direction: nothing came due, so the return releases nothing.
    func testACallbackReturningWithNothingDueDoesNotRelease() throws {
        let recorder = Recorder()
        let registration = try acceptedRegistration(recorder)

        registration.runCallback {}

        XCTAssertEqual(recorder.releases, [])
        XCTAssertEqual(registration.currentState, .active)
        registration.completeWithSuccess()
        assertReleasedOnceOutsideCallbacks(recorder)
    }

    // MARK: - A result that owns a file (part 2, 5.3)

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func acceptedRegistration(_ recorder: Recorder) throws -> Registration<OperationCallback> {
        let holder = MainHolder<Registration<OperationCallback>>()
        acceptTestOperation(recorder) { holder.value = $0 }
        runMainQueue()
        return try XCTUnwrap(holder.value)
    }

    func testAHandedOverFileStays() throws {
        let file = try makeLoadedFile()
        let recorder = Recorder()
        let registration = try acceptedRegistration(recorder)

        registration.completeWithSuccess(result: ClipboardReceiver.loadedFile(at: file))

        XCTAssertEqual(recorder.completions.map(\.error), [successValue])
        XCTAssertTrue(exists(file))
        try FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    /// The hand-over mark is set before the callback: a cancel from inside it, with its removal running
    /// on a run loop the callback spins, leaves the file that the callback was given.
    func testACancelInsideTheCallbackDoesNotDeleteTheFileItWasGiven() throws {
        let file = try makeLoadedFile()
        let recorder = Recorder()
        let registration = try acceptedRegistration(recorder)
        let owned = ClipboardReceiver.loadedFile(at: file)
        let markInside = MainHolder<Bool>()
        recorder.onCompletion = { completion in
            MainActor.assumeIsolated {
                markInside.value = owned.isHandedOver
                Registry.cancel(id: completion.id, request: DialogReceiver.cancelKind)
                runMainQueue()
                owned.discardUnlessHandedOver()
            }
        }

        registration.completeWithSuccess(result: owned)
        runMainQueue()

        XCTAssertEqual(markInside.value, true)
        XCTAssertEqual(recorder.completions.map(\.error), [successValue])
        XCTAssertEqual(recorder.releases.count, 1)
        XCTAssertTrue(exists(file))
        try FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    func testAResultOfACancelledRequestIsDeletedWithItsFolder() throws {
        let file = try makeLoadedFile()
        let recorder = Recorder()
        let registration = try acceptedRegistration(recorder)
        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)

        registration.completeWithSuccess(result: ClipboardReceiver.loadedFile(at: file))

        XCTAssertEqual(recorder.completions.map(\.error), [canceledValue])
        XCTAssertFalse(exists(file))
        XCTAssertFalse(exists(file.deletingLastPathComponent()))
    }

    /// Part 2, 5.3: between the box closing and its onClose, a cancel's removal can run first.
    func testAResultAfterReleasedIsDeletedAndTouchesNothingElse() throws {
        let file = try makeLoadedFile()
        let recorder = Recorder()
        let registration = try acceptedRegistration(recorder)
        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)
        runMainQueue()
        XCTAssertEqual(registration.currentState, .released)
        let callsBefore = recorder.calls

        registration.completeWithSuccess(result: ClipboardReceiver.loadedFile(at: file))

        XCTAssertFalse(exists(file))
        XCTAssertFalse(exists(file.deletingLastPathComponent()))
        XCTAssertEqual(recorder.calls, callsBefore)
    }

    func testASecondResultIsNotHandedOverAndIsDeleted() throws {
        let first = try makeLoadedFile()
        let second = try makeLoadedFile()
        let recorder = Recorder()
        let registration = try acceptedRegistration(recorder)

        registration.completeWithSuccess(result: ClipboardReceiver.loadedFile(at: first))
        registration.completeWithSuccess(result: ClipboardReceiver.loadedFile(at: second))

        XCTAssertTrue(exists(first))
        XCTAssertFalse(exists(second))
        XCTAssertEqual(recorder.completions.count, 1)
        try FileManager.default.removeItem(at: first.deletingLastPathComponent())
    }

    func testAResultIsDiscardedOnlyOnce() {
        let count = MainHolder<Int>()
        let owned = OwnedResult { count.value = (count.value ?? 0) + 1 }

        owned.discardUnlessHandedOver()
        owned.discardUnlessHandedOver()

        XCTAssertEqual(count.value, 1)
    }

    func testAFileThatIsAlreadyGoneIsNotAProblem() throws {
        let file = try makeLoadedFile()
        try FileManager.default.removeItem(at: file.deletingLastPathComponent())

        ClipboardReceiver.loadedFile(at: file).discardUnlessHandedOver()
    }

    // MARK: - Races (they mean something under TSan; the counts hold anyway)

    /// The order table: whichever CAS wins, one completion and one release. The file exists exactly when
    /// the caller was given it. The delay moves the cancel across the completion, so both sides win.
    func testCancelOnAnotherThreadAgainstTheCompletionOnMain() throws {
        for round in 0..<300 {
            let recorder = Recorder()
            let file = try makeLoadedFile()
            let registration = try acceptedRegistration(recorder)
            let id = recorder.outRequestID.pointee
            let race = RaceStart()
            let finished = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                race.waitForGo()
                Registry.cancel(id: id, request: DialogReceiver.cancelKind)
                finished.signal()
            }
            race.go(afterSpinning: (round % 30) * 200)
            registration.completeWithSuccess(result: ClipboardReceiver.loadedFile(at: file))
            XCTAssertEqual(finished.wait(timeout: .now() + 10), .success, "round \(round)")
            runMainQueue()

            XCTAssertEqual(recorder.completions.count, 1)
            XCTAssertEqual(recorder.releases, [true])
            XCTAssertEqual(recorder.completions.map(\.onMain), [true])
            let error = try XCTUnwrap(recorder.completions.first?.error)
            XCTAssertEqual(exists(file), error == successValue)
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
    }

    /// 8 threads, 25 calls each (part 1, chapter 6): every other request is also cancelled.
    func testManyThreadsCallAtOnce() {
        let count = Registry.requestCount
        let recorders = (0..<200).map { _ in Recorder() }
        let group = DispatchGroup()
        for thread in 0..<8 {
            group.enter()
            let mine = Array(recorders[(thread * 25)..<((thread + 1) * 25)])
            Thread.detachNewThread {
                for (index, recorder) in mine.enumerated() {
                    _ = acceptTestOperation(recorder) { $0.completeWithSuccess() }
                    if index % 2 == 0 {
                        Registry.cancel(id: recorder.outRequestID.pointee, request: DialogReceiver.cancelKind)
                    }
                }
                group.leave()
            }
        }
        let deadline = Date(timeIntervalSinceNow: 20)
        while group.wait(timeout: .now()) != .success, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        runMainQueue()

        for recorder in recorders {
            XCTAssertEqual(recorder.completions.count, 1)
            XCTAssertEqual(recorder.completions.map(\.onMain), [true])
            XCTAssertEqual(recorder.releases, [true])
        }
        XCTAssertEqual(Set(recorders.map(\.outRequestID.pointee)).count, recorders.count, "ids are not reused")
        XCTAssertEqual(Registry.requestCount, count)
    }
}

/// A kind's close, recorded, for a test without a manager behind it.
private final class BoxCloses: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = 0

    var count: Int { lock.withLock { closed } }

    func record(_ box: RequestBox) {
        lock.withLock { closed += 1 }
    }
}
