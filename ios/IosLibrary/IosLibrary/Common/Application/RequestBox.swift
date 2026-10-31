//
//  RequestBox.swift
//  IosLibrary
//

import Foundation
import os
import Synchronization

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "RequestBox")

/// One request of an operation that completes once: a box that is closed exactly once.
///
/// Create a box before you start a request when you need to cancel that request later, and pass
/// it to the operation; its manager cancels the request through the box. An operation that is
/// not given a box creates its own.
///
/// - Note: The operations that take a box and the manager methods that cancel through it (the
///   dialog manager's `show(_:presenter:requestBox:completion:)` and `cancel(_:)`, the clipboard
///   manager's `loadItem(_:scope:requestBox:completion:)` and `cancelLoad(_:)`) are added in a
///   later commit of 2.0.0. Until then nothing in the library takes a `RequestBox`.
///
/// The request ends when the box closes, and only the first close counts: the user's answer,
/// a cancellation, a failure to present, or the system dismissing the presented UI. Whatever
/// closes it later is ignored, so the operation's completion is invoked once.
///
/// A box belongs to one request. Passing a box that another request already uses makes the
/// second request fail at once as an invalid request; the first request is not affected.
///
/// ## Threading
/// `RequestBox` is `Sendable`. ``init()`` and ``isClosed`` can be used on any thread, and
/// closing never waits for the main thread.
public final class RequestBox: Sendable {
    /// Everything that changes, behind one lock.
    private struct State {
        var outcome: RequestBoxOutcome?
        var isAttached = false
        var onClose: (@Sendable (RequestBoxOutcome) -> Void)?
    }

    private enum Attachment {
        case alreadyAttached
        case closed(RequestBoxOutcome)
        case open
    }

    private let state = Mutex(State())

    /// Creates an open box that no request uses yet.
    public init() {
        logger.log(level: .libraryDebug, "[init]")
    }

    /// Whether the request has ended (or was cancelled before it started).
    ///
    /// A closed box stays closed. The completion of the request may still be on its way to the
    /// main thread when this becomes `true`.
    public var isClosed: Bool {
        state.withLock { $0.outcome != nil }
    }

    /// How the box was closed, or `nil` while it is open.
    var outcome: RequestBoxOutcome? {
        state.withLock { $0.outcome }
    }

    /// Ties the box to one request: `onClose` runs once, on the main thread, after the box
    /// closes. It is never called inside this call, also when the box is already closed (then it
    /// is queued at once with the outcome the box was closed with).
    ///
    /// - Returns: `false` when the box was already attached to a request; `onClose` is then
    ///   dropped and never called, and the caller fails its request as invalid.
    func attach(_ onClose: @escaping @MainActor @Sendable (RequestBoxOutcome) -> Void) -> Bool {
        logger.log(level: .libraryDebug, "[attach] onClose: provided")
        // Nonisolated on purpose: whoever closes the box (any thread) calls this, and it only
        // queues on the main queue (FIFO), where the main-actor part runs.
        let deliver: @Sendable (RequestBoxOutcome) -> Void = { outcome in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { onClose(outcome) }
            }
        }
        // One lock region decides everything: whether the box was free, and whether it is
        // already closed (then this call delivers) or not (then the closing call delivers).
        let attachment = state.withLock { state -> Attachment in
            guard !state.isAttached else { return .alreadyAttached }
            state.isAttached = true
            if let outcome = state.outcome { return .closed(outcome) }
            state.onClose = deliver
            return .open
        }
        switch attachment {
        case .alreadyAttached:
            logger.error("[attach] the box is already used by another request")
            return false
        case .closed(let outcome):
            logger.log(level: .libraryDebug, "[attach] already closed, queueing outcome: \(outcome.logName, privacy: .public)")
            // Outside the lock (S-8): the closure only queues on the main queue.
            deliver(outcome)
            return true
        case .open:
            return true
        }
    }

    /// Closes the box with `outcome` when it is still open. Any thread; never waits.
    ///
    /// - Returns: `true` when this call closed the box, `false` when it was already closed (the
    ///   outcome is then dropped).
    @discardableResult
    func close(_ outcome: RequestBoxOutcome) -> Bool {
        logger.log(level: .libraryDebug, "[close] outcome: \(outcome.logName, privacy: .public)")
        let (closed, onClose) = state.withLock { state -> (Bool, (@Sendable (RequestBoxOutcome) -> Void)?) in
            guard state.outcome == nil else { return (false, nil) }
            state.outcome = outcome
            let onClose = state.onClose
            state.onClose = nil
            return (true, onClose)
        }
        if !closed {
            logger.log(level: .libraryDebug, "[close] already closed, dropped outcome: \(outcome.logName, privacy: .public)")
        }
        // Outside the lock (S-8): the closure only queues on the main queue.
        onClose?(outcome)
        return closed
    }
}

/// How a ``RequestBox`` was closed.
enum RequestBoxOutcome: Sendable {
    /// The operation's own result (for example the button the user pressed).
    case completed(any Sendable)
    /// Cancelled through the manager.
    case canceled
    /// No view controller in the foreground to present from.
    case notForeground
    /// The presentation did not happen: not settled after the single wait, or UIKit declined it.
    case presentationFailed
    /// The presented UI went away without the library or its handlers closing the box (for
    /// example dismissed from outside).
    case dismissedBySystem

    /// The case name, without the operation's result (which can hold user values).
    var logName: String {
        switch self {
        case .completed: return "completed"
        case .canceled: return "canceled"
        case .notForeground: return "notForeground"
        case .presentationFailed: return "presentationFailed"
        case .dismissedBySystem: return "dismissedBySystem"
        }
    }
}
