//
//  MainQueue.swift
//  IosLibraryCApi
//

import Dispatch

/// The one way the C ABI gets onto the main thread (part 1, 5.6, P1-4). The state machine of
/// `Registry.swift` relies on the blocks running in the order they were queued, which GCD documents
/// for the main queue and does not for the start of a `Task`. There is no form that waits (part 1, 1.3).
enum MainQueue {
    /// Queues `body`, also when called on the main thread: it never runs inside this call.
    static func async(_ body: @escaping @MainActor @Sendable () -> Void) {
        CApiLog.common.debug("[MainQueue.async] body: provided")
        DispatchQueue.main.async {
            MainActor.assumeIsolated(body)
        }
    }
}
