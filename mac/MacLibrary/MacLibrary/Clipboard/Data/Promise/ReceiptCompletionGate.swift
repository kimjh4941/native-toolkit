//
//  ReceiptCompletionGate.swift
//  MacLibrary
//

import Foundation

/// Lets exactly one of several racing paths finish a continuation.
///
/// The aggregating form of the receive API can end two ways at once: the session delivers its
/// terminal event, or the calling task is cancelled. The two run on different isolations and
/// neither can see the other, so without arbitration the continuation could be resumed twice,
/// which traps.
///
/// The gate is `nonisolated`: a cancellation handler is synchronous and nonisolated, so a main
/// actor isolated flag could not be read from it, and a lock does not lift actor isolation.
/// The state therefore lives here behind its own lock (R4-M4).
///
/// Cancellation can also arrive *before* the continuation exists, because
/// `withTaskCancellationHandler` runs its handler immediately when the task is already
/// cancelled. The outcome is then held until ``attach(_:)`` supplies somewhere to deliver it.
final class ReceiptCompletionGate: @unchecked Sendable {

    /// How the session ended.
    enum Outcome {
        case finished(FilePromiseReceipt)
        case failed(any Error)
    }

    private let lock = NSLock()
    private var resume: (@Sendable (Outcome) -> Void)?
    private var pending: Outcome?
    private var isDelivered = false

    init() {}

    /// Supplies the continuation to resume.
    ///
    /// If an outcome was already claimed, it is delivered right away rather than lost.
    func attach(_ resume: @escaping @Sendable (Outcome) -> Void) {
        let immediate: Outcome? = lock.withLock {
            guard !isDelivered else { return nil }
            if let pending {
                isDelivered = true
                return pending
            }
            self.resume = resume
            return nil
        }
        if let immediate { resume(immediate) }
    }

    /// Claims the right to end the session.
    ///
    /// - Returns: `true` for the first caller only. A losing caller must not resume anything;
    ///   it may still perform its own cleanup.
    @discardableResult
    func claim(_ outcome: Outcome) -> Bool {
        let action: (@Sendable (Outcome) -> Void)? = lock.withLock {
            guard pending == nil, !isDelivered else { return nil }
            guard let resume else {
                // Cancelled before the continuation existed. Hold it for attach.
                pending = outcome
                return nil
            }
            isDelivered = true
            self.resume = nil
            return resume
        }
        guard let action else {
            return lock.withLock { pending != nil && !isDelivered }
        }
        action(outcome)
        return true
    }

    /// Whether an outcome has been claimed. Diagnostics and tests.
    var claimed: Bool {
        lock.withLock { isDelivered || pending != nil }
    }
}
