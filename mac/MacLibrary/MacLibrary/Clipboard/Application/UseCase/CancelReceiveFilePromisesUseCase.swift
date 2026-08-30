//
//  CancelReceiveFilePromisesUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-20. Ends a file promise receive session early.
///
/// Every cancellation path converges here: the public call, a stream's termination and a
/// cancelled task. Keeping one entry point is what makes the terminal event exactly-once
/// (R2-H2).
@MainActor
public struct CancelReceiveFilePromisesUseCase {

    private let TAG = "CancelReceiveFilePromisesUseCase"

    private let registry: any ClipboardPromiseRegistry

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(registry: any ClipboardPromiseRegistry) {
        self.registry = registry
    }

    /// Idempotent and non throwing. A session that is unknown or has already delivered its
    /// terminal event is a no-op.
    ///
    /// When the session is still subscribed, it receives
    /// ``FilePromiseReceiptEvent/finished(_:)`` with
    /// ``FilePromiseReceipt/Termination/cancelled`` and keeps the files already received.
    public func callAsFunction(_ handle: FilePromiseReceiptHandle) {
        Log.d(TAG, "[callAsFunction] handle: \(handle.id)")
        registry.cancelReceipt(handle)
    }
}
