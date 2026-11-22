//
//  CommonTestSupport.swift
//  IosLibraryTests
//

import Foundation
import Synchronization
@testable import IosLibrary

/// Waits until everything queued on the main queue before this call has run (the main queue is
/// FIFO, and the library delivers request completions with `DispatchQueue.main.async`).
func drainMainQueue(times: Int = 1) async {
    for _ in 0..<times {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

/// Records the outcomes a request box delivered, with the thread they arrived on.
final class OutcomeRecorder: Sendable {
    struct Delivery: Sendable {
        let outcome: String
        let isMainThread: Bool
    }

    private let deliveries = Mutex<[Delivery]>([])

    var all: [Delivery] { deliveries.withLock { $0 } }
    var names: [String] { all.map(\.outcome) }

    func record(_ outcome: RequestBoxOutcome) {
        let delivery = Delivery(outcome: outcome.testName, isMainThread: Thread.isMainThread)
        deliveries.withLock { $0.append(delivery) }
    }
}

extension RequestBoxOutcome {
    /// The case name, with the payload of `completed` when it is a `String`.
    var testName: String {
        if case .completed(let value) = self { return "completed(\(value as? String ?? "?"))" }
        return logName
    }
}
