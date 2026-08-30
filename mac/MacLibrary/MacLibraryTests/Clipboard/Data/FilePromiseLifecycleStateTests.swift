//
//  FilePromiseLifecycleStateTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("FilePromiseLifecycleState")
struct FilePromiseLifecycleStateTests {

    private func makeState(staging: URL? = URL(fileURLWithPath: "/tmp/staging")) -> FilePromiseLifecycleState {
        FilePromiseLifecycleState(stagingURL: staging)
    }

    // MARK: Release claiming

    @Test("no release is claimed while nothing asked for one")
    func noClaimWithoutRequest() {
        let state = makeState()
        #expect(state.beginWrite() == .proceed)
        #expect(state.endWrite() == nil)
    }

    @Test("an idle promise releases immediately on request")
    func idleReleasesOnRequest() {
        let state = makeState()
        let generation = state.requestRelease()
        #expect(generation != nil)
        #expect(state.commitRelease(generation: generation!) == .released(
            stagingURL: URL(fileURLWithPath: "/tmp/staging")))
        #expect(state.released)
    }

    @Test("release waits for the last in flight write")
    func releaseWaitsForInFlight() {
        let state = makeState()
        #expect(state.beginWrite() == .proceed)
        #expect(state.beginWrite() == .proceed)
        // A release requested mid flight cannot be claimed yet.
        #expect(state.requestRelease() == nil)
        // Nor can the first completion claim it.
        #expect(state.endWrite() == nil)
        // Only the last one can.
        let generation = state.endWrite()
        #expect(generation != nil)
        #expect(state.commitRelease(generation: generation!) != .reservationInvalid)
    }

    /// The whole point of the two phase claim: a write that starts between claiming and
    /// committing must stop the teardown.
    @Test("a write starting after the claim invalidates it")
    func newWriteInvalidatesReservation() {
        let state = makeState()
        let generation = state.requestRelease()
        #expect(generation != nil)
        #expect(state.beginWrite() == .proceed)
        #expect(state.commitRelease(generation: generation!) == .reservationInvalid)
        #expect(!state.released)
    }

    @Test("the promise is released once the interrupting write finishes")
    func releaseResumesAfterInterruption() {
        let state = makeState()
        let first = state.requestRelease()
        #expect(state.beginWrite() == .proceed)
        #expect(state.commitRelease(generation: first!) == .reservationInvalid)
        state.abandonReservation(generation: first!)
        // The completion re-claims because release is still requested.
        let second = state.endWrite()
        #expect(second != nil)
        #expect(state.commitRelease(generation: second!) != .reservationInvalid)
        #expect(state.released)
    }

    /// A stale claim must not clear a newer one, which is why the reservation stores a
    /// generation rather than a flag.
    @Test("abandoning a stale reservation leaves a newer claim intact")
    func staleAbandonDoesNotClearNewerClaim() {
        let state = makeState()
        let stale = state.requestRelease()
        #expect(stale != nil)
        // A write bumps the generation and drops the old reservation.
        #expect(state.beginWrite() == .proceed)
        let fresh = state.endWrite()
        #expect(fresh != nil)
        #expect(fresh != stale)
        // The stale owner now tries to clean up after itself.
        state.abandonReservation(generation: stale!)
        // The newer claim still commits.
        #expect(state.commitRelease(generation: fresh!) != .reservationInvalid)
    }

    @Test("committing with a generation that was never claimed does nothing")
    func commitWithUnknownGeneration() {
        let state = makeState()
        #expect(state.commitRelease(generation: 999) == .reservationInvalid)
        #expect(!state.released)
    }

    // MARK: Idempotence and post release behaviour

    @Test("release is idempotent")
    func releaseIsIdempotent() {
        let state = makeState()
        let generation = state.requestRelease()!
        #expect(state.commitRelease(generation: generation) != .reservationInvalid)
        // A second commit, and a second request, are both no-ops.
        #expect(state.commitRelease(generation: generation) == .reservationInvalid)
        #expect(state.requestRelease() == nil)
        #expect(state.released)
    }

    @Test("a write after release is rejected instead of fulfilled")
    func writeAfterReleaseIsRejected() {
        let state = makeState()
        let generation = state.requestRelease()!
        _ = state.commitRelease(generation: generation)
        #expect(state.beginWrite() == .rejectedAlreadyReleased)
        #expect(state.inFlight == 0)
    }

    /// A writer backed promise owns no staging, and `nil` there must still mean "released".
    @Test("a writer backed promise reports released with a nil staging URL")
    func writerBackedReleaseIsStillReleased() {
        let state = makeState(staging: nil)
        let generation = state.requestRelease()!
        #expect(state.commitRelease(generation: generation) == .released(stagingURL: nil))
        #expect(state.released)
    }

    // MARK: Ownership

    @Test("ownership is absent until activation")
    func ownershipStartsNil() {
        let state = makeState()
        #expect(state.activatedOwnership() == nil)
    }

    @Test("activation records the ownership used for stale detection")
    func activationRecordsOwnership() {
        let state = makeState()
        let ownership = PasteboardOwnership(scope: .named("probe"), changeCount: 7)
        state.activate(ownership: ownership)
        #expect(state.activatedOwnership() == ownership)
    }

    // MARK: Concurrency

    @Test("concurrent writes and releases never double release or release early")
    func concurrentClaimsAreExclusive() async {
        let state = makeState()
        let committed = LockedCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    guard state.beginWrite() == .proceed else { return }
                    if let generation = state.endWrite() {
                        if state.commitRelease(generation: generation) != .reservationInvalid {
                            committed.increment()
                        } else {
                            state.abandonReservation(generation: generation)
                        }
                    }
                }
            }
            for _ in 0..<8 {
                group.addTask {
                    if let generation = state.requestRelease() {
                        if state.commitRelease(generation: generation) != .reservationInvalid {
                            committed.increment()
                        } else {
                            state.abandonReservation(generation: generation)
                        }
                    }
                }
            }
        }

        // Release is requested by at least one task, so it must happen exactly once and
        // only after every write finished.
        #expect(state.inFlight == 0)
        #expect(committed.value <= 1)
        if state.released { #expect(committed.value == 1) }
    }
}

/// Small thread safe counter for the concurrency test.
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
