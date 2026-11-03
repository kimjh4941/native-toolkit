//
//  TestThreads.swift
//  IosLibraryCApiTests
//

import Foundation

private final class ResultBox<Value>: @unchecked Sendable {
    var value: Value?
}

/// Runs `body` on another thread while the calling thread waits, and returns what it returned, or nil
/// when it did not return in time. Called from a test, whose thread is the main thread, so that a
/// `body` that waits for the main thread times out.
func onAnotherThread<Value: Sendable>(timeout: TimeInterval = 5, _ body: @escaping @Sendable () -> Value) -> Value? {
    let box = ResultBox<Value>()
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        box.value = body()
        done.signal()
    }
    return done.wait(timeout: .now() + timeout) == .success ? box.value : nil
}
