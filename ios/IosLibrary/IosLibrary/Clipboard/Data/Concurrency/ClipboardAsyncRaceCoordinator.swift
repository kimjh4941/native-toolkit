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
///
/// A winner that arrives *before* the continuation is attached (e.g. entering
/// `withTaskCancellationHandler` on an already-cancelled Task, so `onCancel` runs first) is
/// latched in `pendingResult` and replayed the moment the continuation attaches, so an early
/// cancellation is never lost.
final class ClipboardAsyncRaceCoordinator<Value: Sendable>: @unchecked Sendable {
    private static var TAG: String { "ClipboardAsyncRaceCoordinator" }
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var resolved = false
    private var timeoutTask: Task<Void, Never>?

    /// Attaches the caller's continuation. `internal` rather than `private` so the three-way race
    /// gate (U-111) can be driven directly from tests in a deterministic arrival order.
    func attach(_ continuation: CheckedContinuation<Value, Error>) {
        Log.d(Self.TAG, "[attach]")
        lock.lock()
        if let pendingResult {
            // A winner already arrived before we could attach; replay it immediately.
            self.pendingResult = nil
            lock.unlock()
            continuation.resume(with: pendingResult)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    private func setTimeoutTask(_ task: Task<Void, Never>) {
        lock.lock()
        if resolved {
            lock.unlock()
            task.cancel()
            return
        }
        timeoutTask = task
        lock.unlock()
    }

    /// Resolves the race. `internal` rather than `private` so tests can drive the arrival order of
    /// {completion, cancellation, timeout} deterministically (U-111).
    /// - Returns: `true` only for the arrival that won the race and was delivered.
    @discardableResult
    func resolve(_ result: Result<Value, Error>) -> Bool {
        Log.d(Self.TAG, "[resolve] isSuccess: \((try? result.get()) != nil)")
        lock.lock()
        guard !resolved else {
            lock.unlock()
            return false
        }
        resolved = true
        let capturedContinuation = continuation
        let capturedTimeoutTask = timeoutTask
        continuation = nil
        timeoutTask = nil
        if capturedContinuation == nil {
            // Continuation not attached yet: latch the winner for `attach` to replay.
            pendingResult = result
        }
        lock.unlock()

        // Stop the timeout timer as soon as the race is decided, so a settled operation does not
        // keep a pending task alive for the remainder of its timeout window.
        capturedTimeoutTask?.cancel()
        capturedContinuation?.resume(with: result)
        return true
    }

    /// Runs `operation`, resolving with its result, with `ClipboardError.cancelled` on Task
    /// cancellation, or with `ClipboardError.timedOut(operation:)` after `timeout` seconds —
    /// whichever happens first.
    static func run(
        timeout: TimeInterval,
        operationKind: ClipboardOperationKind,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        Log.d(TAG, "[run] timeout: \(timeout), operationKind: \(operationKind)")
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

                let timeoutTask = Task {
                    let clampedTimeout = max(timeout, 0)
                    try? await Task.sleep(nanoseconds: UInt64(clampedTimeout * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    coordinator.resolve(.failure(ClipboardError.timedOut(operation: operationKind)))
                }
                coordinator.setTimeoutTask(timeoutTask)
            }
        } onCancel: {
            coordinator.resolve(.failure(ClipboardError.cancelled))
        }
    }
}
