//
//  ClipboardAsyncRaceCoordinator.swift
//  IosLibrary
//

import Foundation

/// Gives a caller-facing cancellation/timeout contract to non-cooperative `async throws` system
/// APIs (`detectedPatterns(for:)` / `detectedValues(for:)`) that have no cancellation token.
///
/// Structured task groups are not used here because a group awaits its children even after one
/// wins the race, which would make the caller wait for a non-cooperative system call to finish.
/// Instead, the system call and a timeout timer are started as **unstructured** tasks; whichever
/// of {system completion, Task cancellation, timeout} arrives first resolves the single
/// continuation exactly once. Results/errors that arrive afterward are discarded — the
/// non-cooperative work may keep running in the background, but its outcome is never surfaced.
final class ClipboardAsyncRaceCoordinator<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var resolved = false

    private func attach(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    private func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard !resolved, let continuation else {
            lock.unlock()
            return
        }
        resolved = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }

    /// Runs `operation`, resolving with its result, with `ClipboardError.cancelled` on Task
    /// cancellation, or with `ClipboardError.timedOut(operation:)` after `timeout` seconds —
    /// whichever happens first.
    static func run(
        timeout: TimeInterval,
        operationKind: ClipboardOperationKind,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let coordinator = ClipboardAsyncRaceCoordinator()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
                coordinator.attach(continuation)

                Task {
                    do {
                        let value = try await operation()
                        coordinator.resolve(.success(value))
                    } catch {
                        coordinator.resolve(.failure(error))
                    }
                }

                Task {
                    let clampedTimeout = max(timeout, 0)
                    try? await Task.sleep(nanoseconds: UInt64(clampedTimeout * 1_000_000_000))
                    coordinator.resolve(.failure(ClipboardError.timedOut(operation: operationKind)))
                }
            }
        } onCancel: {
            coordinator.resolve(.failure(ClipboardError.cancelled))
        }
    }
}
