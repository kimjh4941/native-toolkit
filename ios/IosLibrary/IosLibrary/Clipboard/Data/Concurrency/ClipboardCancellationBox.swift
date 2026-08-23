//
//  ClipboardCancellationBox.swift
//  IosLibrary
//

import Foundation

/// Thread-safe relay that forwards a Swift Task cancellation to a main-actor `ClipboardLoadToken`.
///
/// `withTaskCancellationHandler`'s `onCancel` closure is a `@Sendable` **synchronous** closure and
/// cannot touch an `@MainActor`-isolated token directly; this box bridges that gap with an
/// internal lock and hops to the main actor to deliver the cancellation.
final class ClipboardCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var token: (any ClipboardLoadToken)?
    private var isCancelled = false

    /// Callable from any thread, including a `@Sendable` cancellation handler.
    func cancel() {
        lock.lock()
        isCancelled = true
        let captured = token
        token = nil
        lock.unlock()
        guard let captured else { return }
        Task { @MainActor in captured.cancel() }
    }

    /// Attaches the token once the load has started. Cancels immediately if already cancelled,
    /// so a cancellation that races the attach is never lost.
    @MainActor
    func attach(_ newToken: any ClipboardLoadToken) {
        lock.lock()
        let alreadyCancelled = isCancelled
        if !alreadyCancelled { token = newToken }
        lock.unlock()
        if alreadyCancelled { newToken.cancel() }
    }
}
