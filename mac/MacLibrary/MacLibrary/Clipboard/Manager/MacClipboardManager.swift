//
//  MacClipboardManager.swift
//  MacLibrary
//

import AppKit
import Foundation

/// Callback for an operation that produces a value.
///
/// The four argument shape is uniform across every operation so the Unity bridge can forward
/// results without knowing which one it is handling. Success is
/// `(true, value, 0, nil)`; failure is `(false, nil, code, message)`.
public typealias ClipboardCallbackResult<T> =
    @MainActor (_ isSuccess: Bool, _ value: T?, _ errorCode: Int, _ errorMessage: String?) -> Void

/// Callback for an operation that produces no value.
public typealias ClipboardVoidCallback =
    @MainActor (_ isSuccess: Bool, _ errorCode: Int, _ errorMessage: String?) -> Void

/// Clipboard entry point for macOS.
///
/// Every operation has a native `async throws` form. Operations that can fail asynchronously
/// also have a callback form for the Unity bridge, which cannot cross the C ABI with Swift
/// error handling. Immediate control operations are synchronous in both forms.
///
/// - Important: The whole type is main actor isolated because `NSPasteboard` is not
///   `Sendable`. Callbacks are therefore always delivered on the main actor.
///
/// ## What this API does not guarantee
///
/// These are limits of the platform, not of this wrapper. Each was measured rather than
/// assumed, and none of them can be worked around from here.
///
/// - **No operation guarantees the person using the app is not told.** macOS may show a
///   pasteboard access alert for any read. ``snapshot(matchingTypes:scope:)`` and
///   ``detectPatterns(_:scope:)`` avoid reading the payload, which is an optimisation and not
///   a privacy contract. The alert could not be reproduced in any tested configuration, and
///   that absence is **not** evidence it will not appear.
/// - **A read can report more than was written.** The pasteboard derives convertible types:
///   writing `public.rtf` alone makes plain text readable as well. Do not assume
///   ``read(scope:)`` mirrors ``copy(_:options:scope:)``.
/// - **Appending needs ownership.** Unlike the iOS clipboard of the same name,
///   ``append(_:ownership:)`` fails with ``ClipboardError/ownershipLost(expected:actual:)``
///   once another app has taken the pasteboard. It does not silently do nothing.
/// - **Named and unique pasteboards outlive this process.** They live in the pasteboard
///   server. Release a unique one with ``removePasteboard(_:)`` and never place confidential
///   data on a named one.
/// - **`localOnly` is unverified.** ``ClipboardCopyOptions/localOnly`` expresses the intent
///   through `NSPasteboard.ContentsOptions`, but its effect on Universal Clipboard has not
///   been confirmed on real hardware.
/// - **A receive session's end is an estimate.** The system does not report how many files
///   are coming, so ``receiveFilePromises(destinationDirectory:scope:policy:)`` ends after a
///   quiet interval or at an overall deadline. A slow provider can be cut short.
/// - **The paste button does not validate itself.** ``makePasteButton(acceptedTypes:timeout:onPaste:)``
///   stays enabled whether or not the pasteboard holds an accepted type, unlike its iOS
///   counterpart.
/// - **Metadata detection can fail where you would expect an empty answer.**
///   ``detectMetadata(scope:)`` reports a failure for a pasteboard the system cannot
///   describe, which includes plain text. "Nothing to report" and "could not report" are not
///   distinguishable.
@MainActor
public final class MacClipboardManager {

    private let TAG = "MacClipboardManager"

    /// Shared instance using the real pasteboard.
    public static let shared = MacClipboardManager()

    /// Default poll interval for ``startObserving(scope:interval:onEvent:)``.
    ///
    /// Half a second is fast enough to feel immediate for a paste affordance without
    /// waking the process constantly.
    ///
    /// Declared `nonisolated` because it is the default argument of
    /// ``startObserving(scope:interval:onEvent:)``: a default argument is evaluated in the
    /// caller's context, which is not the main actor. Without this the reference is a
    /// warning under Swift 5 and an error under the Swift 6 language mode.
    nonisolated public static let defaultObservationInterval: TimeInterval = 0.5

    private let coordinator: ClipboardSystemCoordinator
    private let useCases: ClipboardUseCases
    private let monitor: ClipboardChangeMonitor

    /// Builds the default object graph.
    ///
    /// The order matters and is fixed here rather than left to callers. The coordinator has to
    /// exist before the repository that resolves handles through it, and the change count
    /// query can only be attached once the use cases that answer it exist. That last step
    /// closes what would otherwise be a construction cycle (R6-H3).
    public convenience init(limits: ClipboardLimits = .default) {
        // 1. The snapshotter owns its serial queue and depends on nothing.
        let snapshotter = FilePromiseSnapshotter()
        // 2. The coordinator holds the snapshotter; its stale query is still unset.
        let coordinator = ClipboardSystemCoordinator(snapshotter: snapshotter)
        // 3. The repository converts domain values to pasteboard calls and resolves handles
        //    through the coordinator without owning anything.
        let repository = ClipboardRepositoryImpl(validator: ClipboardTypeIdentifierValidator(),
                                                 lookup: coordinator,
                                                 receiptSink: coordinator)
        // 4. The use cases take the repository and the coordinator as the registry port.
        let useCases = ClipboardUseCases(repository: repository,
                                         registry: coordinator,
                                         snapshotter: snapshotter,
                                         typeValidator: ClipboardTypeIdentifierValidator(),
                                         limits: limits)
        self.init(coordinator: coordinator, useCases: useCases)
    }

    /// Injecting initializer, used by tests and by the convenience initializer above.
    init(coordinator: ClipboardSystemCoordinator,
         useCases: ClipboardUseCases) {
        Log.d("MacClipboardManager", "[init]")
        self.coordinator = coordinator
        self.useCases = useCases
        // Shares the aggregate's tracker, so a change already seen by the one-shot foreground
        // check is not reported again by the poller.
        // Through the use case, never the repository: `common.md` forbids a manager reaching
        // the data layer directly, because logic added on that path is unreachable by tests.
        self.monitor = ClipboardChangeMonitor(
            readChangeCount: { [useCases] scope in try useCases.changeCount(scope: scope) },
            tracker: useCases.changeTracker)
        // 5. Closing the cycle. Until this runs the stale check does nothing at all.
        coordinator.attachStaleQuery { [useCases] scope in
            try useCases.changeCount(scope: scope)
        }
        // Staging left behind by a crashed run is nobody else's job to remove. Runs once per
        // process and never touches a directory belonging to a live promise (R4-L10).
        coordinator.sweepOrphanedStagingDirectories()
    }

    // MARK: - Error conversion

    /// The one place a `ClipboardError` becomes a numeric code (R6-M7).
    ///
    /// Everything below this layer propagates typed errors, and the Unity facade forwards what
    /// it receives without translating again.
    private func complete<T>(_ completion: ClipboardCallbackResult<T>?,
                             _ work: () throws -> T) {
        do {
            completion?(true, try work(), 0, nil)
        } catch let error as ClipboardError {
            completion?(false, nil, error.errorCode, error.errorMessage)
        } catch {
            let wrapped = ClipboardError.unknown(String(describing: error))
            completion?(false, nil, wrapped.errorCode, wrapped.errorMessage)
        }
    }

    /// Variant for an operation whose value is itself optional.
    ///
    /// ``readData(utType:scope:)`` returns `Data?`, where `nil` means the type was absent.
    /// That has to arrive as `(true, nil, 0, nil)` rather than as a failure, so the success
    /// path must accept a `nil` value instead of treating it as a missing result.
    private func completeOptional<T>(_ completion: ClipboardCallbackResult<T>?,
                                     _ work: () throws -> T?) {
        do {
            completion?(true, try work(), 0, nil)
        } catch let error as ClipboardError {
            completion?(false, nil, error.errorCode, error.errorMessage)
        } catch {
            let wrapped = ClipboardError.unknown(String(describing: error))
            completion?(false, nil, wrapped.errorCode, wrapped.errorMessage)
        }
    }

    private func complete<T>(_ completion: ClipboardCallbackResult<T>?,
                             _ work: () async throws -> T) async {
        do {
            completion?(true, try await work(), 0, nil)
        } catch let error as ClipboardError {
            completion?(false, nil, error.errorCode, error.errorMessage)
        } catch {
            let wrapped = ClipboardError.unknown(String(describing: error))
            completion?(false, nil, wrapped.errorCode, wrapped.errorMessage)
        }
    }

    private func completeVoid(_ completion: ClipboardVoidCallback?,
                              _ work: () throws -> Void) {
        do {
            try work()
            completion?(true, 0, nil)
        } catch let error as ClipboardError {
            completion?(false, error.errorCode, error.errorMessage)
        } catch {
            let wrapped = ClipboardError.unknown(String(describing: error))
            completion?(false, wrapped.errorCode, wrapped.errorMessage)
        }
    }

    // MARK: - OP-01 copy

    /// Replaces the pasteboard contents.
    ///
    /// - Returns: Proof of ownership, needed to ``append(_:ownership:)``.
    @discardableResult
    public func copy(_ content: ClipboardContent,
                     options: ClipboardCopyOptions = .default,
                     scope: PasteboardScope = .general) async throws -> PasteboardOwnership {
        Log.d(TAG, "[copy] content: \(ClipboardLog.content(content)), "
              + "localOnly: \(options.localOnly), scope: \(ClipboardLog.scope(scope))")
        return try useCases.copy(content, options: options, scope: scope)
    }

    /// Callback form of ``copy(_:options:scope:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func copy(_ content: ClipboardContent,
                     options: ClipboardCopyOptions = .default,
                     scope: PasteboardScope = .general,
                     completion: ClipboardCallbackResult<PasteboardOwnership>?) {
        Log.d(TAG, "[copy:completion] content: \(ClipboardLog.content(content)), "
              + "localOnly: \(options.localOnly), scope: \(ClipboardLog.scope(scope))")
        complete(completion) { try useCases.copy(content, options: options, scope: scope) }
    }

    // MARK: - OP-02 append

    /// Adds items to a pasteboard this app still owns.
    ///
    /// - Important: Unlike iOS, appending requires ownership. If another app has taken the
    ///   pasteboard this throws ``ClipboardError/ownershipLost(expected:actual:)`` rather than
    ///   silently doing nothing (RK-23).
    @discardableResult
    public func append(_ content: ClipboardContent,
                       ownership: PasteboardOwnership) async throws -> PasteboardOwnership {
        Log.d(TAG, "[append] content: \(ClipboardLog.content(content)), "
              + "scope: \(ClipboardLog.scope(ownership.scope))")
        return try useCases.append(content, ownership: ownership)
    }

    /// Callback form of ``append(_:ownership:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func append(_ content: ClipboardContent,
                       ownership: PasteboardOwnership,
                       completion: ClipboardCallbackResult<PasteboardOwnership>?) {
        Log.d(TAG, "[append:completion] content: \(ClipboardLog.content(content)), "
              + "scope: \(ClipboardLog.scope(ownership.scope))")
        complete(completion) { try useCases.append(content, ownership: ownership) }
    }

    // MARK: - OP-03 read

    /// Reads every item and every representation.
    ///
    /// - Important: The result can contain representations that were never written. The
    ///   pasteboard derives convertible types, so text written as `public.rtf` also reads back
    ///   as plain text (RK-24). Do not assume a read mirrors a write.
    @discardableResult
    public func read(scope: PasteboardScope = .general) async throws -> ClipboardReadResult {
        Log.d(TAG, "[read] scope: \(ClipboardLog.scope(scope))")
        return try useCases.read(scope: scope)
    }

    /// Callback form of ``read(scope:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func read(scope: PasteboardScope = .general,
                     completion: ClipboardCallbackResult<ClipboardReadResult>?) {
        Log.d(TAG, "[read:completion] scope: \(ClipboardLog.scope(scope))")
        complete(completion) { try useCases.read(scope: scope) }
    }

    // MARK: - OP-04 readData

    /// Reads the bytes for one uniform type identifier.
    ///
    /// - Returns: `nil` when the pasteboard has no such type. That is a normal outcome, not an
    ///   error, and the callback form reports it as `(true, nil, 0, nil)`.
    @discardableResult
    public func readData(utType: String,
                         scope: PasteboardScope = .general) async throws -> Data? {
        Log.d(TAG, "[readData] utType: \(utType), scope: \(ClipboardLog.scope(scope))")
        return try useCases.readData(utType: utType, scope: scope)
    }

    /// Callback form of ``readData(utType:scope:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func readData(utType: String,
                         scope: PasteboardScope = .general,
                         completion: ClipboardCallbackResult<Data>?) {
        Log.d(TAG, "[readData:completion] utType: \(utType), scope: \(ClipboardLog.scope(scope))")
        completeOptional(completion) { try useCases.readData(utType: utType, scope: scope) }
    }

    // MARK: - OP-05 snapshot

    /// Describes the pasteboard's types without reading any payload.
    ///
    /// - Important: Avoiding a payload read does **not** guarantee the system will refrain
    ///   from telling the user the pasteboard was accessed (RK-01 / RK-22).
    @discardableResult
    public func snapshot(matchingTypes: [String]? = nil,
                         scope: PasteboardScope = .general) async throws -> ClipboardSnapshot {
        Log.d(TAG, "[snapshot] matchingTypes: \(matchingTypes.map(ClipboardLog.types) ?? "nil"), "
              + "scope: \(ClipboardLog.scope(scope))")
        return try useCases.snapshot(matchingTypes: matchingTypes, scope: scope)
    }

    /// Callback form of ``snapshot(matchingTypes:scope:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func snapshot(matchingTypes: [String]? = nil,
                         scope: PasteboardScope = .general,
                         completion: ClipboardCallbackResult<ClipboardSnapshot>?) {
        Log.d(TAG, "[snapshot:completion] "
              + "matchingTypes: \(matchingTypes.map(ClipboardLog.types) ?? "nil"), "
              + "scope: \(ClipboardLog.scope(scope))")
        complete(completion) { try useCases.snapshot(matchingTypes: matchingTypes, scope: scope) }
    }

    // MARK: - OP-06 clear

    /// Empties the pasteboard.
    @discardableResult
    public func clear(scope: PasteboardScope = .general) async throws -> Int {
        Log.d(TAG, "[clear] scope: \(ClipboardLog.scope(scope))")
        return try useCases.clear(scope: scope)
    }

    /// Callback form of ``clear(scope:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func clear(scope: PasteboardScope = .general,
                      completion: ClipboardCallbackResult<Int>?) {
        Log.d(TAG, "[clear:completion] scope: \(ClipboardLog.scope(scope))")
        complete(completion) { try useCases.clear(scope: scope) }
    }

    // MARK: - OP-07 createPasteboard

    /// Creates or fetches a pasteboard.
    ///
    /// - Important: The pasteboard lives in the pasteboard server and outlives this app.
    ///   Release a unique one with ``removePasteboard(_:)``, and never place confidential data
    ///   on a named one (RK-06).
    @discardableResult
    public func createPasteboard(_ request: PasteboardCreationRequest) async throws -> PasteboardScope {
        Log.d(TAG, "[createPasteboard] request: \(request)")
        return try useCases.createPasteboard(request)
    }

    /// Callback form of ``createPasteboard(_:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func createPasteboard(_ request: PasteboardCreationRequest,
                                 completion: ClipboardCallbackResult<PasteboardScope>?) {
        Log.d(TAG, "[createPasteboard:completion] request: \(request)")
        complete(completion) { try useCases.createPasteboard(request) }
    }

    // MARK: - OP-08 removePasteboard

    /// Releases a pasteboard's server side resources.
    ///
    /// - Throws: ``ClipboardError/cannotReleaseStandardPasteboard(name:)`` for the general
    ///   pasteboard and the other standard names (RK-07).
    ///
    /// - Note: No `@discardableResult`, unlike the operations above: this returns `Void`, and
    ///   the attribute would produce a warning there.
    public func removePasteboard(_ scope: PasteboardScope) async throws {
        Log.d(TAG, "[removePasteboard] scope: \(ClipboardLog.scope(scope))")
        try useCases.removePasteboard(scope)
    }

    /// Callback form of ``removePasteboard(_:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func removePasteboard(_ scope: PasteboardScope,
                                 completion: ClipboardVoidCallback?) {
        Log.d(TAG, "[removePasteboard:completion] scope: \(ClipboardLog.scope(scope))")
        completeVoid(completion) { try useCases.removePasteboard(scope) }
    }

    // MARK: - OP-09 detectPatterns

    /// Reports which of the requested patterns the pasteboard contains.
    @discardableResult
    public func detectPatterns(_ patterns: Set<ClipboardDetectionPattern>,
                               scope: PasteboardScope = .general) async throws -> Set<ClipboardDetectionPattern> {
        Log.d(TAG, "[detectPatterns] patterns: \(patterns.count), scope: \(ClipboardLog.scope(scope))")
        return try await useCases.detectPatterns(patterns, scope: scope)
    }

    /// Callback form of ``detectPatterns(_:scope:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func detectPatterns(_ patterns: Set<ClipboardDetectionPattern>,
                               scope: PasteboardScope = .general,
                               completion: ClipboardCallbackResult<Set<ClipboardDetectionPattern>>?) {
        Log.d(TAG, "[detectPatterns:completion] patterns: \(patterns.count), "
              + "scope: \(ClipboardLog.scope(scope))")
        Task { @MainActor in
            await complete(completion) { try await useCases.detectPatterns(patterns, scope: scope) }
        }
    }

    // MARK: - OP-10 detectValues

    /// Reads the detected values themselves.
    ///
    /// - Important: This reads the contents. The system notifies the user on a match and can
    ///   deny access, in which case this throws (RK-03). Call it from a user action.
    @discardableResult
    public func detectValues(_ patterns: Set<ClipboardDetectionPattern>,
                             scope: PasteboardScope = .general) async throws -> ClipboardDetectedValues {
        Log.d(TAG, "[detectValues] patterns: \(patterns.count), scope: \(ClipboardLog.scope(scope))")
        return try await useCases.detectValues(patterns, scope: scope)
    }

    /// Callback form of ``detectValues(_:scope:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func detectValues(_ patterns: Set<ClipboardDetectionPattern>,
                             scope: PasteboardScope = .general,
                             completion: ClipboardCallbackResult<ClipboardDetectedValues>?) {
        Log.d(TAG, "[detectValues:completion] patterns: \(patterns.count), "
              + "scope: \(ClipboardLog.scope(scope))")
        Task { @MainActor in
            await complete(completion) { try await useCases.detectValues(patterns, scope: scope) }
        }
    }

    // MARK: - OP-11 detectMetadata

    /// Reads the limited metadata the system exposes without the contents.
    @discardableResult
    public func detectMetadata(scope: PasteboardScope = .general) async throws -> ClipboardDetectedMetadata {
        Log.d(TAG, "[detectMetadata] scope: \(ClipboardLog.scope(scope))")
        return try await useCases.detectMetadata(scope: scope)
    }

    /// Callback form of ``detectMetadata(scope:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func detectMetadata(scope: PasteboardScope = .general,
                               completion: ClipboardCallbackResult<ClipboardDetectedMetadata>?) {
        Log.d(TAG, "[detectMetadata:completion] scope: \(ClipboardLog.scope(scope))")
        Task { @MainActor in
            await complete(completion) { try await useCases.detectMetadata(scope: scope) }
        }
    }

    // MARK: - OP-12 accessBehavior

    /// Current pasteboard access behaviour for this app.
    ///
    /// Synchronous: an immediate control query, which common.md exempts from the
    /// `async throws` rule.
    ///
    /// - Returns: ``ClipboardAccessBehavior/unavailable`` below macOS 15.4.
    public func accessBehavior(scope: PasteboardScope = .general) throws -> ClipboardAccessBehavior {
        Log.d(TAG, "[accessBehavior] scope: \(ClipboardLog.scope(scope))")
        return try useCases.accessBehavior(scope: scope)
    }

    // MARK: - OP-13 startObserving

    /// Starts reporting pasteboard changes.
    ///
    /// Synchronous: starting is an immediate control operation. Calling it again restarts
    /// observation with the new configuration rather than failing, so a caller never ends up
    /// silently observing an old scope (M-5).
    ///
    /// - Important: Polling is suspended while the app is inactive and catches up on
    ///   reactivation, so a change made by another app is reported when this app returns to
    ///   the foreground rather than as it happens (RK-11).
    /// - Throws: ``ClipboardError/invalidConfiguration(_:)`` for an interval outside
    ///   `0 < interval <= 60`. A scope that cannot be resolved throws and leaves any existing
    ///   observation running.
    public func startObserving(scope: PasteboardScope = .general,
                               interval: TimeInterval = MacClipboardManager.defaultObservationInterval,
                               onEvent: @escaping @MainActor (ClipboardChangeEvent) -> Void) throws {
        Log.d(TAG, "[startObserving] scope: \(ClipboardLog.scope(scope)), interval: \(interval)")
        try monitor.start(scope: scope, interval: interval, onEvent: onEvent)
    }

    // MARK: - OP-14 stopObserving

    /// Stops reporting pasteboard changes. Idempotent and non throwing.
    public func stopObserving() {
        Log.d(TAG, "[stopObserving]")
        monitor.stop()
    }

    // MARK: - OP-15 checkForegroundChange

    /// Whether the pasteboard changed since this app last looked.
    ///
    /// - Returns: `true` on the first call for a scope, because the caller has not seen that
    ///   pasteboard before.
    public func checkForegroundChange(scope: PasteboardScope = .general) throws -> Bool {
        Log.d(TAG, "[checkForegroundChange] scope: \(ClipboardLog.scope(scope))")
        return try useCases.checkForegroundChange(scope: scope)
    }

    // MARK: - OP-16 provideFilePromise

    /// Promises a file to other apps without producing its bytes yet.
    ///
    /// `async` rather than synchronous because a ``FilePromiseSource/snapshot(_:)`` request is
    /// copied into app owned staging first, and that copy has no size bound (R4-H3).
    ///
    /// - Returns: A handle to release with ``releaseFilePromise(_:)`` once the promise is no
    ///   longer offered. Promises whose pasteboard is taken over by another app are released
    ///   automatically.
    /// - Note: Deliberately not `@discardableResult`. Dropping the handle leaks the
    ///   registration and its staging directory, because nothing else can release them.
    public func provideFilePromise(_ request: FilePromiseRequest,
                                   scope: PasteboardScope = .general) async throws -> FilePromiseHandle {
        Log.d(TAG, "[provideFilePromise] fileType: \(request.fileTypeIdentifier), "
              + "fileName: \(ClipboardLog.path(request.fileName)), scope: \(ClipboardLog.scope(scope))")
        return try await useCases.provideFilePromise(request, scope: scope)
    }

    /// Callback form of ``provideFilePromise(_:scope:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func provideFilePromise(_ request: FilePromiseRequest,
                                   scope: PasteboardScope = .general,
                                   completion: ClipboardCallbackResult<FilePromiseHandle>?) {
        Log.d(TAG, "[provideFilePromise:completion] fileType: \(request.fileTypeIdentifier), "
              + "fileName: \(ClipboardLog.path(request.fileName)), scope: \(ClipboardLog.scope(scope))")
        Task { @MainActor in
            await complete(completion) { try await useCases.provideFilePromise(request, scope: scope) }
        }
    }

    // MARK: - OP-17 releaseFilePromise

    /// Releases a file promise registration. Idempotent and non throwing.
    public func releaseFilePromise(_ handle: FilePromiseHandle) {
        Log.d(TAG, "[releaseFilePromise] handle: \(handle.id)")
        useCases.releaseFilePromise(handle)
    }

    // MARK: - OP-18 receiveFilePromises

    /// Starts receiving files another app has promised.
    ///
    /// Synchronous because starting is an immediate control operation: the files arrive later,
    /// through `onEvent`.
    ///
    /// - Parameter onEvent: Called once per file, then exactly once with
    ///   ``FilePromiseReceiptEvent/finished(_:)``. If this method throws, `onEvent` is never
    ///   called at all (R5-H4).
    /// - Returns: A handle for ``cancelReceiveFilePromises(_:)``.
    /// - Important: The terminal event is a **heuristic**. The system does not report how many
    ///   files are coming, so the session ends after `policy.quietInterval` without a new
    ///   arrival, or at `policy.overallTimeout` at the latest (H-3).
    /// - Note: Deliberately not `@discardableResult`. Dropping the handle leaves a session
    ///   that can never be cancelled.
    public func receiveFilePromises(destinationDirectory: URL,
                                    scope: PasteboardScope = .general,
                                    policy: FilePromiseReceiptPolicy = .default,
                                    onEvent: @escaping @MainActor (FilePromiseReceiptEvent) -> Void)
    throws -> FilePromiseReceiptHandle {
        Log.d(TAG, "[receiveFilePromises] destination: \(ClipboardLog.url(destinationDirectory)), "
              + "scope: \(ClipboardLog.scope(scope)), quiet: \(policy.quietInterval)")
        return try useCases.receiveFilePromises(destinationDirectory: destinationDirectory,
                                                scope: scope, policy: policy, onEvent: onEvent)
    }

    /// Callback form of ``receiveFilePromises(destinationDirectory:scope:policy:)``, for the Unity bridge.
    ///
    /// The C ABI cannot carry Swift error handling, so the result arrives as
    /// `(isSuccess, value, errorCode, errorMessage)` instead. `completion` runs
    /// **exactly once** on the main actor, including on an early failure. Passing
    /// `nil` performs the operation without reporting the result.
    public func receiveFilePromises(destinationDirectory: URL,
                                    scope: PasteboardScope = .general,
                                    policy: FilePromiseReceiptPolicy = .default,
                                    onEvent: @escaping @MainActor (FilePromiseReceiptEvent) -> Void,
                                    completion: ClipboardCallbackResult<FilePromiseReceiptHandle>?) {
        Log.d(TAG, "[receiveFilePromises:completion] "
              + "destination: \(ClipboardLog.url(destinationDirectory)), "
              + "scope: \(ClipboardLog.scope(scope))")
        complete(completion) {
            try useCases.receiveFilePromises(destinationDirectory: destinationDirectory,
                                             scope: scope, policy: policy, onEvent: onEvent)
        }
    }

    // MARK: - OP-18 native async forms

    /// Receives promised files as an async sequence.
    ///
    /// - Returns: The handle and the stream together. The handle is needed to cancel the very
    ///   session being consumed (R4-H1).
    /// - Throws: Only if the session cannot be started. Once this returns, the stream itself
    ///   never throws: per-file failures arrive as ``FilePromiseReceiptEvent/failed(_:)`` and
    ///   the session always ends with ``FilePromiseReceiptEvent/finished(_:)`` (R3-H1).
    public func receiveFilePromiseEvents(destinationDirectory: URL,
                                         scope: PasteboardScope = .general,
                                         policy: FilePromiseReceiptPolicy = .default)
    throws -> FilePromiseEventSubscription {
        Log.d(TAG, "[receiveFilePromiseEvents] "
              + "destination: \(ClipboardLog.url(destinationDirectory)), "
              + "scope: \(ClipboardLog.scope(scope))")
        let (stream, continuation) = AsyncStream.makeStream(of: FilePromiseReceiptEvent.self)
        // Start first. A failure must not produce a stream at all, which is why the factory
        // throws instead of yielding an error element (R3-H1).
        let handle = try useCases.receiveFilePromises(
            destinationDirectory: destinationDirectory,
            scope: scope,
            policy: policy,
            onEvent: { event in
                continuation.yield(event)
                if case .finished = event { continuation.finish() }
            })
        continuation.onTermination = { [weak self] _ in
            // Resource release only. onTermination runs *after* the stream has ended, so a
            // terminal event yielded from here would never reach the consumer (R3-H1). The
            // delivering cancel is deliberately not reused (R6-M5).
            Task { @MainActor [weak self] in
                self?.coordinator.terminateReceiptWithoutDelivery(handle)
            }
        }
        return FilePromiseEventSubscription(handle: handle, events: stream)
    }

    /// Receives promised files and returns the whole session's result.
    ///
    /// - Returns: The receipt, including the files that arrived before a timeout or an
    ///   explicit cancel. Neither ending throws: losing a partial result would be worse than
    ///   reporting it (R2-M6).
    /// - Throws: `CancellationError` if the calling task is cancelled, or a
    ///   ``ClipboardError`` if the session cannot be started.
    public func receiveFilePromises(destinationDirectory: URL,
                                    scope: PasteboardScope = .general,
                                    policy: FilePromiseReceiptPolicy = .default) async throws
    -> FilePromiseReceipt {
        Log.d(TAG, "[receiveFilePromises:async] "
              + "destination: \(ClipboardLog.url(destinationDirectory)), "
              + "scope: \(ClipboardLog.scope(scope))")
        // The handle is issued before the cancellation handler is installed, so onCancel can
        // never run while the handle is still undecided (R6-H4).
        let handle = coordinator.reserveReceiptHandle()
        let gate = ReceiptCompletionGate()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.attach { outcome in
                    switch outcome {
                    case .finished(let receipt): continuation.resume(returning: receipt)
                    case .failed(let error): continuation.resume(throwing: error)
                    }
                }
                do {
                    _ = try useCases.receiveFilePromises.start(
                        handle: handle,
                        destinationDirectory: destinationDirectory,
                        scope: scope,
                        policy: policy,
                        onEvent: { [weak self] event in
                            guard case .finished(let receipt) = event else { return }
                            // Whoever claims first wins. A terminal that loses to cancellation
                            // is dropped rather than resuming a second time (R5-M7).
                            guard gate.claim(.finished(receipt)) else { return }
                            self?.coordinator.finalizeReceipt(handle)
                        })
                } catch {
                    gate.claim(.failed(error))
                }
            }
        } onCancel: {
            // Synchronous and nonisolated, so the gate cannot be a main actor flag and the
            // cleanup has to hop (R4-M4 / CT-14). A cancelled task reports the standard
            // CancellationError, not a ClipboardError (R5-M10).
            guard gate.claim(.failed(CancellationError())) else { return }
            Task { @MainActor [weak self] in
                self?.coordinator.terminateReceiptWithoutDelivery(handle)
            }
        }
    }

    // MARK: - OP-19 makePasteButton

    /// Builds a system paste button that loads the pasteboard into domain values.
    ///
    /// Synchronous: creating a view is an immediate factory operation. The load it starts when
    /// pressed is asynchronous and reports through `onPaste`.
    ///
    /// - Parameters:
    ///   - acceptedTypes: Priority order, highest first. The first type a provider can supply
    ///     is the one loaded, so the same pasteboard always yields the same representation.
    ///   - timeout: Overall deadline for the load. Providers still outstanding when it expires
    ///     are reported as ``ClipboardError/pasteLoadTimedOut(seconds:)``.
    ///   - onPaste: Called **exactly once** per press, with successes and failures together.
    ///     Not called at all once the returned view is released.
    /// - Returns: A view to place in the hierarchy. Releasing it cancels a load in progress.
    /// - Important: Unlike iOS, the macOS paste button does not enable or disable itself based
    ///   on the pasteboard contents (RK-16).
    public func makePasteButton(acceptedTypes: [String],
                                timeout: TimeInterval = 15,
                                onPaste: @escaping @MainActor (ClipboardPasteResult) -> Void)
    throws -> NSView {
        Log.d(TAG, "[makePasteButton] acceptedTypes: \(ClipboardLog.types(acceptedTypes)), "
              + "timeout: \(timeout)")
        return try PasteButtonFactory.makePasteButton(
            acceptedTypes: acceptedTypes,
            timeout: timeout,
            validator: ClipboardTypeIdentifierValidator(),
            register: { [coordinator] loader in coordinator.registerPasteLoader(loader) },
            cancel: { [coordinator] handle in coordinator.cancelPaste(handle) },
            onPaste: onPaste)
    }

    // MARK: - OP-20 cancelReceiveFilePromises

    /// Ends a receive session early. Idempotent and non throwing.
    ///
    /// A session still subscribed receives a final
    /// ``FilePromiseReceiptEvent/finished(_:)`` with
    /// ``FilePromiseReceipt/Termination/cancelled`` and keeps the files already received.
    public func cancelReceiveFilePromises(_ handle: FilePromiseReceiptHandle) {
        Log.d(TAG, "[cancelReceiveFilePromises] handle: \(handle.id)")
        useCases.cancelReceiveFilePromises(handle)
    }
}
