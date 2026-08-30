//
//  FilePromiseLifecycleState.swift
//  MacLibrary
//

import Foundation

/// Lifetime bookkeeping for one registered file promise provider.
///
/// The state deliberately lives outside the main actor isolated coordinator. The promise
/// delegate is `nonisolated` (`NSFilePromiseProviderDelegate` declares the write callback
/// that way), and a lock does not lift actor isolation, so a main actor isolated property
/// simply cannot be updated from the delegate. Instead the lock and every field are private
/// here and the only way in is through the transition methods below. The coordinator keeps
/// these boxes in a main actor dictionary and mutates that dictionary on the main actor.
///
/// The tricky part is releasing. A provider can be asked to write more than once, so a
/// counter is needed rather than a flag, and the actual teardown has to hop to the main
/// actor. Between claiming a release and performing it a new write can start, so the claim
/// carries a generation and is re-checked before teardown. `scheduledGeneration` is an
/// optional generation rather than a boolean so that a stale claim cannot clear a newer one.
final class FilePromiseLifecycleState: @unchecked Sendable {

    /// Whether a write request may proceed.
    enum StartOutcome: Equatable {
        /// The caller should fulfil the promise.
        case proceed
        /// The promise is gone; the caller should fail the write instead of fulfilling it.
        case rejectedAlreadyReleased
    }

    /// Result of the main actor side re-check.
    enum CommitReleaseOutcome: Equatable {
        /// Tear down. The staging directory is `nil` for writer backed promises, which is
        /// not the same thing as "do not tear down".
        case released(stagingURL: URL?)
        /// A newer write invalidated the reservation; do nothing.
        case reservationInvalid
    }

    private let TAG = "FilePromiseLifecycleState"

    private let lock = NSLock()
    private var inFlightCount = 0
    private var releaseRequested = false
    private var generation: UInt64 = 0
    private var scheduledGeneration: UInt64?
    private var isReleased = false
    private let stagingURL: URL?
    private var ownership: PasteboardOwnership?

    /// - Parameter stagingURL: Directory to delete on release, or `nil` for writer backed
    ///   promises that own no staging.
    init(stagingURL: URL?) {
        Log.d("FilePromiseLifecycleState", "[init] \(ClipboardLog.url(stagingURL))")
        self.stagingURL = stagingURL
    }

    // MARK: Write lifecycle

    /// Records the start of a write. Call before running the caller's writer.
    func beginWrite() -> StartOutcome {
        Log.d(TAG, "[beginWrite]")
        lock.lock()
        defer { lock.unlock() }
        if isReleased { return .rejectedAlreadyReleased }
        inFlightCount += 1
        generation &+= 1
        // A write that starts after a release was queued invalidates that reservation.
        scheduledGeneration = nil
        return .proceed
    }

    /// Records the end of a write. Call immediately before the completion handler.
    ///
    /// - Returns: The generation to pass to ``commitRelease(generation:)`` when this
    ///   completion is the one that makes release possible, otherwise `nil`.
    func endWrite() -> UInt64? {
        Log.d(TAG, "[endWrite]")
        lock.lock()
        defer { lock.unlock() }
        if inFlightCount > 0 { inFlightCount -= 1 }
        return claimReleaseLocked()
    }

    // MARK: Release

    /// Requests release, either explicitly or because the promise went stale.
    ///
    /// - Returns: The generation to pass to ``commitRelease(generation:)`` when release can
    ///   be attempted now, otherwise `nil`.
    func requestRelease() -> UInt64? {
        Log.d(TAG, "[requestRelease]")
        lock.lock()
        defer { lock.unlock() }
        releaseRequested = true
        return claimReleaseLocked()
    }

    /// Re-checks the claim on the main actor and, if it still holds, marks the promise
    /// released and hands back the staging directory to delete.
    func commitRelease(generation claimed: UInt64) -> CommitReleaseOutcome {
        Log.d(TAG, "[commitRelease] generation: \(claimed)")
        lock.lock()
        defer { lock.unlock() }
        guard releaseRequested,
              inFlightCount == 0,
              scheduledGeneration == claimed,
              !isReleased else {
            return .reservationInvalid
        }
        isReleased = true
        scheduledGeneration = nil
        return .released(stagingURL: stagingURL)
    }

    /// Drops a reservation that did not survive the re-check.
    ///
    /// Only clears when the reservation is still this caller's, so a stale claim cannot
    /// cancel a newer one.
    func abandonReservation(generation claimed: UInt64) {
        Log.d(TAG, "[abandonReservation] generation: \(claimed)")
        lock.lock()
        defer { lock.unlock() }
        if scheduledGeneration == claimed {
            scheduledGeneration = nil
        }
    }

    // MARK: Ownership

    /// Records the ownership captured when the provider was written to a pasteboard.
    /// Stale monitoring only applies after this.
    func activate(ownership value: PasteboardOwnership) {
        Log.d(TAG, "[activate] \(ClipboardLog.scope(value.scope)), changeCount: \(value.changeCount)")
        lock.lock()
        defer { lock.unlock() }
        ownership = value
    }

    /// Staging directory to copy from while fulfilling a promise.
    ///
    /// Returns `nil` once released, so a write that raced past ``beginWrite()`` cannot read a
    /// directory that is being deleted. Writer backed promises always return `nil`; they have
    /// no staging and never take this path.
    func stagingURLForFulfilment() -> URL? {
        Log.d(TAG, "[stagingURLForFulfilment]")
        lock.lock()
        defer { lock.unlock() }
        return isReleased ? nil : stagingURL
    }

    /// Ownership to compare against, or `nil` while the promise is still provisional.
    func activatedOwnership() -> PasteboardOwnership? {
        Log.d(TAG, "[activatedOwnership]")
        lock.lock()
        defer { lock.unlock() }
        return ownership
    }

    /// Whether release already completed. Test and diagnostics helper.
    var released: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isReleased
    }

    /// Writes currently in flight. Test and diagnostics helper.
    var inFlight: Int {
        lock.lock()
        defer { lock.unlock() }
        return inFlightCount
    }

    // MARK: Private

    /// Reserves the release for exactly one caller. Must be called with the lock held.
    private func claimReleaseLocked() -> UInt64? {
        guard releaseRequested,
              inFlightCount == 0,
              scheduledGeneration == nil,
              !isReleased else {
            return nil
        }
        scheduledGeneration = generation
        return generation
    }
}
