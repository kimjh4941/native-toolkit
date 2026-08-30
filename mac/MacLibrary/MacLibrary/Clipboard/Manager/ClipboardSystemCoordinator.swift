//
//  ClipboardSystemCoordinator.swift
//  MacLibrary
//

import AppKit
import Foundation

/// The single owner of every system object the clipboard feature registers.
///
/// `NSFilePromiseProvider.delegate` is `weak` and the delegate protocol never reports that a
/// promise is finished with, so something has to hold the strong reference and decide when to
/// let go. common.md requires that owner to be exactly one manager layer class, and this is
/// it: lazy data providers, file promise providers and their delegates, receive sessions and
/// paste loaders all live here. The repository resolves handles through a read-only view and
/// holds nothing (H-5).
///
/// Registered promises are also watched for staleness. A promise stays advertised on a
/// pasteboard until someone drags it, but the pasteboard can be taken over by another app in
/// the meantime, at which point the promise can never be fulfilled and its staging directory
/// would leak. A periodic tick compares the recorded change count against the current one and
/// releases what can no longer be honoured.
@MainActor
final class ClipboardSystemCoordinator {

    private let TAG = "ClipboardSystemCoordinator"

    /// How often stale registrations are looked for.
    ///
    /// A promise going stale is not urgent: nothing is broken until the user tries to drag it,
    /// and the cost of waiting is a staging directory living a few seconds longer. Five
    /// seconds keeps the timer cheap while bounding that window.
    static let staleCheckInterval: TimeInterval = 5

    private let snapshotter: any FilePromiseSnapshotting

    /// Reads the current change count for a scope. Injected after construction because the
    /// path to it runs through the repository, which is built after this type (R6-H3).
    private var staleQuery: (@MainActor (PasteboardScope) throws -> Int)?

    private var filePromises: [FilePromiseHandle: FilePromiseLifecycleState] = [:]
    /// The provider and its delegate. `NSFilePromiseProvider.delegate` is `weak`, so the
    /// delegate is held here or it would be deallocated while the promise is still
    /// advertised on a pasteboard (RK-21).
    private var filePromiseObjects: [FilePromiseHandle: (provider: NSFilePromiseProvider,
                                                          delegate: FilePromiseDelegate)] = [:]
    private var lazyProviders: [PasteboardPromiseHandle: LazyProviderRegistration] = [:]
    private var receipts: [FilePromiseReceiptHandle: FilePromiseReceiptSession] = [:]
    private var pasteLoaders: [ClipboardPasteHandle: ClipboardPasteLoader] = [:]

    /// Repeating stale check.
    ///
    /// A `Task` rather than a `Timer` because `deinit` on a main actor isolated class is
    /// nonisolated, and Swift 6 forbids touching a non-`Sendable` `Timer` from there. `Task`
    /// is `Sendable`, so it can be cancelled during teardown.
    private var staleTask: Task<Void, Never>?

    /// Root of every staging directory, `<temp>/ClipboardPromise/<handle id>/`.
    private let stagingBase: URL

    /// Serial queue handed to every promise delegate.
    ///
    /// Serial so that two writes for the same provider cannot re-enter one writer closure or
    /// read a staging directory while it is being copied (R2-H4).
    private let fulfilmentQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.nativetoolkit.clipboard.filepromise"
        return queue
    }()

    init(snapshotter: any FilePromiseSnapshotting,
         stagingBase: URL = FileManager.default.temporaryDirectory.appending(path: "ClipboardPromise")) {
        Log.d("ClipboardSystemCoordinator", "[init] stagingBase: \(ClipboardLog.url(stagingBase))")
        self.snapshotter = snapshotter
        self.stagingBase = stagingBase
    }

    // MARK: - Paste loaders

    /// Takes ownership of a paste loader for as long as its view exists.
    func registerPasteLoader(_ loader: ClipboardPasteLoader) -> ClipboardPasteHandle {
        Log.d(TAG, "[registerPasteLoader]")
        let handle = ClipboardPasteHandle()
        pasteLoaders[handle] = loader
        return handle
    }

    /// Cancels a paste in progress and drops the loader. Idempotent.
    ///
    /// Called from the container view's `deinit`, so it must tolerate being called for a
    /// handle that is already gone (R2-M10).
    func cancelPaste(_ handle: ClipboardPasteHandle) {
        Log.d(TAG, "[cancelPaste] handle: \(handle.id)")
        guard let loader = pasteLoaders[handle] else { return }
        loader.cancel()
        pasteLoaders[handle] = nil
    }

    var registeredPasteLoaderCount: Int { pasteLoaders.count }

    // MARK: - Startup staging cleanup

    /// Runs the leftover staging sweep once per process.
    ///
    /// A crash leaves staging directories behind, and nothing else ever deletes them. The
    /// sweep is `static` so that several managers in one process do not race each other over
    /// the same directories (R4-L10).
    private static let startupSweepToken = SweepToken()

    private final class SweepToken: @unchecked Sendable {
        private let lock = NSLock()
        private var didRun = false
        /// - Returns: `true` for the first caller only.
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if didRun { return false }
            didRun = true
            return true
        }
    }

    /// Deletes staging directories left by a previous run.
    ///
    /// Directories belonging to promises registered in this process are skipped: the sweep can
    /// be requested at any time, and deleting a live staging directory would break a promise
    /// that is still fulfillable (R4-L10).
    func sweepOrphanedStagingDirectories(force: Bool = false) {
        Log.d(TAG, "[sweepOrphanedStagingDirectories] force: \(force)")
        guard force || Self.startupSweepToken.claim() else { return }
        let active = Set(filePromises.keys.map(\.id.uuidString))
        let base = stagingBase
        Task.detached {
            let fileManager = FileManager()
            guard let entries = try? fileManager.contentsOfDirectory(at: base,
                                                                     includingPropertiesForKeys: nil)
            else { return }
            for entry in entries where !active.contains(entry.lastPathComponent) {
                do {
                    try fileManager.removeItem(at: entry)
                } catch {
                    // Logged rather than surfaced: the next launch tries again, and a failure
                    // here must not stop the app from starting.
                    Log.e("ClipboardSystemCoordinator",
                          "[sweepOrphanedStagingDirectories] failed: \(entry.lastPathComponent)")
                }
            }
        }
    }

    deinit {
        // Without this the loop would keep waking up for a coordinator that no longer exists.
        staleTask?.cancel()
    }

    /// Stops the stale check. Idempotent.
    func stopStaleMonitoring() {
        Log.d(TAG, "[stopStaleMonitoring] running: \(staleTask != nil)")
        staleTask?.cancel()
        staleTask = nil
    }

    // MARK: - Stale monitoring

    /// Supplies the change count lookup and starts the periodic check.
    ///
    /// Until this is called every tick is a no-op, which is what makes the initialisation
    /// order safe: the coordinator exists before the repository that can answer the query.
    func attachStaleQuery(_ query: @escaping @MainActor (PasteboardScope) throws -> Int) {
        Log.d(TAG, "[attachStaleQuery]")
        staleQuery = query
        startStaleTimerIfNeeded()
    }

    private func startStaleTimerIfNeeded() {
        Log.d(TAG, "[startStaleTimerIfNeeded] running: \(staleTask != nil)")
        guard staleTask == nil else { return }
        staleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.staleCheckInterval))
                // A weak capture, so the loop does not keep the coordinator alive; it ends on
                // its own once the coordinator is gone.
                guard let self else { return }
                self.checkForStalePromises()
            }
        }
    }

    /// Releases every activated promise whose pasteboard has moved on.
    ///
    /// Internal rather than private so a test can drive it without waiting for the timer.
    func checkForStalePromises() {
        Log.d(TAG, "[checkForStalePromises] promises: \(filePromises.count)")
        guard let staleQuery else {
            // Not attached yet. Doing nothing is correct: a promise cannot be judged stale
            // without a way to read the current change count (R6-H3).
            return
        }
        for (handle, state) in filePromises {
            guard let ownership = state.activatedOwnership() else {
                // Still provisional. Nothing has been written to a pasteboard, so there is no
                // ownership to compare against.
                continue
            }
            let isStale: Bool
            do {
                isStale = try staleQuery(ownership.scope) != ownership.changeCount
            } catch {
                // The scope no longer resolves, so the pasteboard is gone and the promise can
                // never be fulfilled. That is staleness, not an error to report.
                Log.d(TAG, "[checkForStalePromises] scope unresolvable, treating as stale: "
                      + "\(ClipboardLog.scope(ownership.scope))")
                isStale = true
            }
            guard isStale else { continue }
            if let claim = state.requestRelease() {
                completeRelease(handle: handle, state: state, claim: claim)
            }
        }
    }

    /// Performs the main actor side of a release that was claimed elsewhere.
    private func completeRelease(handle: FilePromiseHandle,
                                 state: FilePromiseLifecycleState,
                                 claim: UInt64) {
        Log.d(TAG, "[completeRelease] handle: \(handle.id)")
        switch state.commitRelease(generation: claim) {
        case .released(let stagingURL):
            filePromises[handle] = nil
            filePromiseObjects[handle] = nil
            if stagingURL != nil {
                // The whole per-handle directory goes, not just the file copied into it.
                // Removing only the child would leave an empty directory per promise, cleaned
                // up no earlier than the next launch's sweep.
                let root = stagingRoot(for: handle)
                let snapshotter = snapshotter
                // Deleting a directory tree is blocking I/O and must not run on the main actor.
                Task.detached { await snapshotter.discard(stagingURL: root) }
            }
        case .reservationInvalid:
            // A write started between the claim and this re-check, so the promise is in use
            // after all. It will be released again when that write finishes.
            state.abandonReservation(generation: claim)
        }
    }
}

// MARK: - Registrations

/// A registered lazy data provider and the types it can supply.
@MainActor
final class LazyProviderRegistration {
    let types: [String]
    let provider: LazyDataProvider

    init(types: [String], provider: LazyDataProvider) {
        self.types = types
        self.provider = provider
    }
}

// MARK: - ClipboardPromiseRegistry

extension ClipboardSystemCoordinator: ClipboardPromiseRegistry {

    // MARK: Lazy data providers

    func registerLazyProvider(types: [String],
                              provide: @escaping @Sendable (String) -> Data?) -> PasteboardPromiseHandle {
        Log.d(TAG, "[registerLazyProvider] types: \(ClipboardLog.types(types))")
        let handle = PasteboardPromiseHandle()
        let provider = LazyDataProvider(provide: provide, onFinished: { [weak self] in
            // The callback is nonisolated, so releasing hops back to the main actor.
            Task { @MainActor [weak self] in self?.releaseLazyProvider(handle) }
        })
        lazyProviders[handle] = LazyProviderRegistration(types: types, provider: provider)
        return handle
    }

    func releaseLazyProvider(_ handle: PasteboardPromiseHandle) {
        Log.d(TAG, "[releaseLazyProvider] handle: \(handle.id)")
        lazyProviders[handle] = nil
    }

    // MARK: File promise providers

    func reserveFilePromiseHandle() -> FilePromiseHandle {
        Log.d(TAG, "[reserveFilePromiseHandle]")
        // Nothing is stored yet. The handle only has to be unique so that a staging path can
        // be derived from it before the promise is registered.
        return FilePromiseHandle()
    }

    func stagingRoot(for handle: FilePromiseHandle) -> URL {
        Log.d(TAG, "[stagingRoot] handle: \(handle.id)")
        return stagingBase.appending(path: handle.id.uuidString)
    }

    func registerFilePromise(_ request: FilePromiseRequest,
                             reserved: FilePromiseHandle,
                             stagingURL: URL?) -> FilePromiseHandle {
        Log.d(TAG, "[registerFilePromise] handle: \(reserved.id), "
              + "staging: \(ClipboardLog.url(stagingURL))")
        let state = FilePromiseLifecycleState(stagingURL: stagingURL)
        filePromises[reserved] = state
        let delegate = FilePromiseDelegate(
            fileName: request.fileName,
            source: request.source,
            state: state,
            queue: fulfilmentQueue,
            onReleasable: { [weak self] generation in
                // The delegate runs off the main actor, so the teardown hops back.
                Task { @MainActor [weak self] in
                    guard let self, let state = self.filePromises[reserved] else { return }
                    self.completeRelease(handle: reserved, state: state, claim: generation)
                }
            })
        let provider = NSFilePromiseProvider(fileType: request.fileTypeIdentifier,
                                             delegate: delegate)
        // Both are held here. The provider's delegate reference is weak, so dropping the
        // delegate would leave a promise that looks valid but can never be fulfilled (RK-21).
        filePromiseObjects[reserved] = (provider, delegate)
        return reserved
    }

    func activateFilePromise(_ handle: FilePromiseHandle, ownership: PasteboardOwnership) {
        Log.d(TAG, "[activateFilePromise] handle: \(handle.id), "
              + "changeCount: \(ownership.changeCount)")
        filePromises[handle]?.activate(ownership: ownership)
    }

    func releaseFilePromise(_ handle: FilePromiseHandle) {
        Log.d(TAG, "[releaseFilePromise] handle: \(handle.id)")
        guard let state = filePromises[handle] else {
            // Unknown or already released. Releasing twice has still achieved what the caller
            // wanted, so this is a success (R2-M5).
            return
        }
        guard let claim = state.requestRelease() else {
            // A write is in flight. The release stays requested and the last completion
            // performs it (R6-L11).
            return
        }
        completeRelease(handle: handle, state: state, claim: claim)
    }

    // MARK: Receive sessions

    func reserveReceiptHandle() -> FilePromiseReceiptHandle {
        Log.d(TAG, "[reserveReceiptHandle]")
        return FilePromiseReceiptHandle()
    }

    func registerReceipt(reserved: FilePromiseReceiptHandle,
                         policy: FilePromiseReceiptPolicy,
                         onEvent: @escaping @MainActor (FilePromiseReceiptEvent) -> Void) {
        Log.d(TAG, "[registerReceipt] handle: \(reserved.id), quiet: \(policy.quietInterval)")
        receipts[reserved] = FilePromiseReceiptSession(
            handle: reserved,
            policy: policy,
            onEvent: onEvent,
            onFinished: { [weak self] handle in
                // The terminal event has been delivered, so the session is done (R6-M6).
                self?.receipts[handle] = nil
            })
    }

    func cancelReceipt(_ handle: FilePromiseReceiptHandle) {
        Log.d(TAG, "[cancelReceipt] handle: \(handle.id)")
        guard let session = receipts[handle], !session.finished else {
            // Unknown or already terminal. A second terminal event would break the
            // exactly-once contract, so silence is the correct answer (R2-H2).
            return
        }
        // Cancelling keeps whatever already arrived; it is an ordinary ending, not a failure.
        session.finish(terminatedBy: .cancelled)
    }

    func terminateReceiptWithoutDelivery(_ handle: FilePromiseReceiptHandle) {
        Log.d(TAG, "[terminateReceiptWithoutDelivery] handle: \(handle.id)")
        // The consumer is already gone, so delivering would have nowhere to go (R6-M5).
        receipts[handle]?.terminateWithoutDelivery()
        receipts[handle] = nil
    }

    func discardReceiptAfterStartFailure(_ handle: FilePromiseReceiptHandle) {
        Log.d(TAG, "[discardReceiptAfterStartFailure] handle: \(handle.id)")
        // A session that never started must produce no event at all, not even a cancellation
        // (R5-H4).
        receipts[handle]?.terminateWithoutDelivery()
        receipts[handle] = nil
    }

    func finalizeReceipt(_ handle: FilePromiseReceiptHandle) {
        Log.d(TAG, "[finalizeReceipt] handle: \(handle.id)")
        receipts[handle] = nil
    }
}

// MARK: - PromiseObjectLookup

extension ClipboardSystemCoordinator: PromiseObjectLookup {

    func lazyProvider(for handle: PasteboardPromiseHandle) -> (any NSPasteboardItemDataProvider)? {
        Log.d(TAG, "[lazyProvider] handle: \(handle.id)")
        return lazyProviders[handle]?.provider
    }

    func filePromiseProvider(for handle: FilePromiseHandle) -> NSFilePromiseProvider? {
        Log.d(TAG, "[filePromiseProvider] handle: \(handle.id)")
        return filePromiseObjects[handle]?.provider
    }
}

// MARK: - FilePromiseReceiptSink

extension ClipboardSystemCoordinator: FilePromiseReceiptSink {

    func receiptGeneration(for handle: FilePromiseReceiptHandle) -> UUID? {
        Log.d(TAG, "[receiptGeneration] handle: \(handle.id)")
        return receipts[handle]?.generation
    }

    func deliverReceiptOutcome(_ handle: FilePromiseReceiptHandle,
                               generation: UUID,
                               outcome: Result<URL, ClipboardError>) {
        Log.d(TAG, "[deliverReceiptOutcome] handle: \(handle.id)")
        guard let session = receipts[handle] else {
            // The session ended and was removed. The reader keeps running on its own queue,
            // so this is expected rather than exceptional.
            return
        }
        switch outcome {
        case .success(let url):
            session.recordReceived(url, generation: generation)
        case .failure(let error):
            session.recordFailure(error, generation: generation)
        }
    }

    func receiptDidStart(_ handle: FilePromiseReceiptHandle, promisedTypeCount: Int) {
        Log.d(TAG, "[receiptDidStart] handle: \(handle.id), types: \(promisedTypeCount)")
        receipts[handle]?.start(promisedTypeCount: promisedTypeCount)
    }
}

// MARK: - Test and diagnostics access

extension ClipboardSystemCoordinator {
    var registeredFilePromiseCount: Int { filePromises.count }
    var registeredLazyProviderCount: Int { lazyProviders.count }
    var lazyProviderHandlesForTests: [PasteboardPromiseHandle] { Array(lazyProviders.keys) }
    func lazyProviderTypes(for handle: PasteboardPromiseHandle) -> [String]? {
        lazyProviders[handle]?.types
    }
    var registeredReceiptCount: Int { receipts.count }
    func lifecycleState(for handle: FilePromiseHandle) -> FilePromiseLifecycleState? {
        filePromises[handle]
    }
    func promiseDelegate(for handle: FilePromiseHandle) -> FilePromiseDelegate? {
        filePromiseObjects[handle]?.delegate
    }
    var fulfilmentQueueForTests: OperationQueue { fulfilmentQueue }
    var firstReceiptHandleForTests: FilePromiseReceiptHandle? { receipts.keys.first }
    func receiptSession(for handle: FilePromiseReceiptHandle) -> FilePromiseReceiptSession? {
        receipts[handle]
    }
    var isStaleTimerRunning: Bool { staleTask != nil }
}
