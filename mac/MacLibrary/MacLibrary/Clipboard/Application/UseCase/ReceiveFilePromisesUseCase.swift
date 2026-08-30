//
//  ReceiveFilePromisesUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-18. Starts receiving files promised by another app.
///
/// Every start path goes through this type: the callback API, the stream and the aggregating
/// async call. Registration and start are one transaction, so a start that fails leaves no
/// session and no timer behind (R4-M5).
@MainActor
public struct ReceiveFilePromisesUseCase {

    private let TAG = "ReceiveFilePromisesUseCase"

    private let repository: any ClipboardRepository
    private let registry: any ClipboardPromiseRegistry

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository, registry: any ClipboardPromiseRegistry) {
        self.repository = repository
        self.registry = registry
    }

    /// - Parameter onEvent: Called for each file, then once with
    ///   ``FilePromiseReceiptEvent/finished(_:)``. Never called at all when this method throws.
    /// - Returns: The handle identifying the session, for use with
    ///   ``CancelReceiveFilePromisesUseCase``.
    /// - Throws: Whatever the repository reports when the session cannot be started, after the
    ///   registration has been rolled back.
    public func callAsFunction(destinationDirectory: URL,
                               scope: PasteboardScope,
                               policy: FilePromiseReceiptPolicy,
                               onEvent: @escaping @MainActor (FilePromiseReceiptEvent) -> Void)
    throws -> FilePromiseReceiptHandle {
        Log.d(TAG, "[callAsFunction] destination: \(ClipboardLog.url(destinationDirectory)), "
              + "scope: \(ClipboardLog.scope(scope))")
        // The handle is issued before registration so that a cancellation handler installed
        // around this call already has a session to name (R6-H4).
        return try start(handle: registry.reserveReceiptHandle(),
                         destinationDirectory: destinationDirectory,
                         scope: scope, policy: policy, onEvent: onEvent)
    }

    /// Starts a session on a handle the caller already reserved.
    ///
    /// The aggregating form needs the handle before this call, so that the cancellation
    /// handler it installs can name the session even if cancellation arrives first (R6-H4).
    public func start(handle: FilePromiseReceiptHandle,
                      destinationDirectory: URL,
                      scope: PasteboardScope,
                      policy: FilePromiseReceiptPolicy,
                      onEvent: @escaping @MainActor (FilePromiseReceiptEvent) -> Void)
    throws -> FilePromiseReceiptHandle {
        Log.d(TAG, "[start] handle: \(handle.id), "
              + "destination: \(ClipboardLog.url(destinationDirectory)), "
              + "scope: \(ClipboardLog.scope(scope)), quiet: \(policy.quietInterval), "
              + "overall: \(policy.overallTimeout)")
        registry.registerReceipt(reserved: handle, policy: policy, onEvent: onEvent)
        do {
            try repository.startReceivingFilePromises(handle: handle,
                                                      destinationDirectory: destinationDirectory,
                                                      scope: scope)
        } catch {
            // Rollback, not cancellation. A session that never started must produce no event
            // at all, so the public cancel path is deliberately not reused here (R5-H4).
            registry.discardReceiptAfterStartFailure(handle)
            throw error
        }
        return handle
    }
}
