//
//  ClipboardPromiseRegistry.swift
//  MacLibrary
//

import Foundation

/// Owns every system delegate the clipboard feature registers.
///
/// `NSFilePromiseProvider.delegate` is `weak` and the delegate protocol has no completion
/// notification, so something has to hold the strong reference and decide when to let go.
/// One coordinator in the manager layer does that for lazy data providers, file promise
/// providers, receive sessions and paste loaders. This port is how the application layer
/// asks for those registrations without seeing any AppKit type.
@MainActor
public protocol ClipboardPromiseRegistry {

    // MARK: Lazy data providers

    /// Registers a provider that supplies bytes on demand.
    func registerLazyProvider(types: [String],
                              provide: @escaping @Sendable (String) -> Data?) -> PasteboardPromiseHandle

    /// Releases a lazy provider. Idempotent.
    func releaseLazyProvider(_ handle: PasteboardPromiseHandle)

    // MARK: File promise providers

    /// Issues a handle before registration so the staging path can be derived from it.
    func reserveFilePromiseHandle() -> FilePromiseHandle

    /// Staging directory for a reserved handle.
    func stagingRoot(for handle: FilePromiseHandle) -> URL

    /// Registers a reserved handle. The promise is not yet watched for staleness because no
    /// pasteboard ownership exists until the provider has been written.
    func registerFilePromise(_ request: FilePromiseRequest,
                             reserved: FilePromiseHandle,
                             stagingURL: URL?) -> FilePromiseHandle

    /// Records the ownership captured when the provider was written, which starts stale
    /// monitoring for this handle.
    func activateFilePromise(_ handle: FilePromiseHandle, ownership: PasteboardOwnership)

    /// Releases a file promise and its staging directory. Idempotent; unknown and already
    /// released handles are a no-op.
    func releaseFilePromise(_ handle: FilePromiseHandle)

    // MARK: Receive sessions

    /// Issues a handle before the session starts, so a cancellation handler installed around
    /// the start can already name the session it will cancel.
    func reserveReceiptHandle() -> FilePromiseReceiptHandle

    /// Registers a reserved receive session.
    func registerReceipt(reserved: FilePromiseReceiptHandle,
                         policy: FilePromiseReceiptPolicy,
                         onEvent: @escaping @MainActor (FilePromiseReceiptEvent) -> Void)

    /// Cancels a session and delivers `.finished(.cancelled)` if it is still subscribed.
    /// Idempotent.
    func cancelReceipt(_ handle: FilePromiseReceiptHandle)

    /// Tears a session down without attempting any delivery.
    ///
    /// Used from a stream's `onTermination`, where the consumer is already gone.
    func terminateReceiptWithoutDelivery(_ handle: FilePromiseReceiptHandle)

    /// Tears a session down without delivery after the start failed, so no event is ever
    /// observed for a session that never began.
    func discardReceiptAfterStartFailure(_ handle: FilePromiseReceiptHandle)

    /// Removes a session after its terminal event has been delivered.
    func finalizeReceipt(_ handle: FilePromiseReceiptHandle)
}
