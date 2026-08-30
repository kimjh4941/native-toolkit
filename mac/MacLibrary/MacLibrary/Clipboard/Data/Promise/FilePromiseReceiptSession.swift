//
//  FilePromiseReceiptSession.swift
//  MacLibrary
//

import Foundation

/// Tracks one file promise receive session and decides when it has ended.
///
/// There is no reliable way to know how many files are coming. `NSFilePromiseReceiver.h` says
/// outright that `fileTypes.count` is **not guaranteed** to equal the number of promised files,
/// because some promisers list each type once and then write several files for it. Waiting for
/// a count would therefore hang on those apps and finish early on others.
///
/// Instead the session ends on a pair of timers: a quiet interval since the last arrival, and
/// an overall deadline that fires even if nothing ever arrives. This is a heuristic and is
/// documented as one — with no guarantee from the SDK, no exact answer exists (H-3).
@MainActor
final class FilePromiseReceiptSession {

    private let TAG = "FilePromiseReceiptSession"

    /// Distinguishes callbacks belonging to this run of the session from ones that arrive
    /// after it ended. The reader keeps running on its own queue after termination, and its
    /// late results must not reopen a finished session.
    let generation: UUID

    private let policy: FilePromiseReceiptPolicy
    private let onEvent: @MainActor (FilePromiseReceiptEvent) -> Void
    /// Called after a terminal event is delivered, so the owner can drop the session.
    private let onFinished: @MainActor (FilePromiseReceiptHandle) -> Void
    private let handle: FilePromiseReceiptHandle

    private var urls: [URL] = []
    private var failures: [ClipboardError] = []
    private var isFinished = false
    private var quietTask: Task<Void, Never>?
    private var overallTask: Task<Void, Never>?

    init(handle: FilePromiseReceiptHandle,
         policy: FilePromiseReceiptPolicy,
         onEvent: @escaping @MainActor (FilePromiseReceiptEvent) -> Void,
         onFinished: @escaping @MainActor (FilePromiseReceiptHandle) -> Void) {
        Log.d("FilePromiseReceiptSession", "[init] handle: \(handle.id), "
              + "quiet: \(policy.quietInterval), overall: \(policy.overallTimeout)")
        self.handle = handle
        self.generation = UUID()
        self.policy = policy
        self.onEvent = onEvent
        self.onFinished = onFinished
    }

    /// Whether a terminal event has been delivered.
    var finished: Bool { isFinished }

    /// Files received so far. Diagnostics and tests.
    var receivedURLs: [URL] { urls }

    /// Starts the overall deadline. Called once the system side has accepted the request.
    ///
    /// The quiet timer deliberately does **not** start here. `quietInterval` measures silence
    /// *since the last arrival*, so starting it at subscription time would turn it into a
    /// deadline for the first file and discard everything from a provider that takes longer
    /// than it to produce one. Until something arrives, only the overall deadline applies.
    func start(promisedTypeCount: Int) {
        Log.d(TAG, "[start] handle: \(handle.id), promisedTypeCount: \(promisedTypeCount)")
        // Logged only. Using it as a termination condition is exactly what H-3 forbids.
        // Read out first: using `policy` inside the closure would capture `self` strongly and
        // keep the session alive past its owner.
        let overallTimeout = policy.overallTimeout
        overallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(overallTimeout))
            guard !Task.isCancelled else { return }
            self?.finish(terminatedBy: .overallTimeout)
        }
    }

    /// Records one arrived file and restarts the quiet timer.
    func recordReceived(_ url: URL, generation: UUID) {
        Log.d(TAG, "[recordReceived] url: \(ClipboardLog.url(url))")
        guard accept(generation) else { return }
        urls.append(url)
        onEvent(.received(url))
        restartQuietTimer()
    }

    /// Records one failed file. Other files in the same session keep arriving.
    func recordFailure(_ error: ClipboardError, generation: UUID) {
        Log.d(TAG, "[recordFailure] error: \(error.errorCode)")
        guard accept(generation) else { return }
        failures.append(error)
        onEvent(.failed(error))
        restartQuietTimer()
    }

    /// Delivers the terminal event. Exactly once; later calls are ignored.
    func finish(terminatedBy termination: FilePromiseReceipt.Termination) {
        Log.d(TAG, "[finish] handle: \(handle.id), terminatedBy: \(termination)")
        guard !isFinished else { return }
        isFinished = true
        stopTimers()
        // Both timeouts and an explicit cancel are ordinary endings, not failures: whatever
        // arrived before them is still delivered to the caller (R2-M6).
        onEvent(.finished(FilePromiseReceipt(urls: urls, failures: failures,
                                             terminatedBy: termination)))
        onFinished(handle)
    }

    /// Tears the session down without delivering anything.
    ///
    /// Used when the consumer is already gone, and when a start failed. In neither case is
    /// there anyone who should observe an event (R5-H4 / R6-M5).
    func terminateWithoutDelivery() {
        Log.d(TAG, "[terminateWithoutDelivery] handle: \(handle.id)")
        isFinished = true
        stopTimers()
    }

    /// Whether a callback carrying `generation` still belongs to a live session.
    private func accept(_ generation: UUID) -> Bool {
        guard !isFinished else {
            // A late reader result. The receiver keeps working on its own queue after the
            // session ended, and reopening it would break the exactly-once terminal event.
            Log.d(TAG, "[accept] discarding late callback for handle: \(handle.id)")
            return false
        }
        return generation == self.generation
    }

    private func restartQuietTimer() {
        quietTask?.cancel()
        let quietInterval = policy.quietInterval
        quietTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(quietInterval))
            guard !Task.isCancelled else { return }
            self?.finish(terminatedBy: .quiescence)
        }
    }

    private func stopTimers() {
        quietTask?.cancel()
        quietTask = nil
        overallTask?.cancel()
        overallTask = nil
    }
}

/// Receives reader outcomes from the data layer on behalf of a session.
///
/// The repository performs the system call but must not own the session, so it reports each
/// outcome through this seam instead. Implemented by the coordinator (H-5).
@MainActor
protocol FilePromiseReceiptSink: AnyObject {
    /// The generation token to stamp on callbacks for a handle, or `nil` when the session is
    /// already gone.
    func receiptGeneration(for handle: FilePromiseReceiptHandle) -> UUID?
    /// Reports one reader outcome.
    func deliverReceiptOutcome(_ handle: FilePromiseReceiptHandle,
                               generation: UUID,
                               outcome: Result<URL, ClipboardError>)
    /// Reports that the system accepted the request and how many types it advertised.
    func receiptDidStart(_ handle: FilePromiseReceiptHandle, promisedTypeCount: Int)
}
