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
/// Reading and writing are `async throws`, and each also has a callback form for the Unity
/// bridge, which cannot cross the C ABI with Swift error handling. Operations that complete
/// immediately are synchronous and have no callback form: ``accessBehavior(scope:)``,
/// ``startObserving(scope:interval:onEvent:)``, ``stopObserving()``,
/// ``checkForegroundChange(scope:)`` and ``makePasteButton(acceptedTypes:timeout:onPaste:)``.
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
    /// Injected rather than constructed here. `common.md` keeps the manager layer off the data
    /// layer's concrete types, and a hard coded one cannot be replaced by a test (R11-M5).
    private let typeValidator: any ClipboardTypeIdentifierValidating
    private let useCases: ClipboardUseCases
    private let monitor: ClipboardChangeMonitor

    /// Builds the default object graph.
    ///
    /// The order matters and is fixed here rather than left to callers: the coordinator has to
    /// exist before the repository that resolves handles through it.
    public convenience init(limits: ClipboardLimits = .default) {
        // 1. The coordinator owns every registered system object.
        let coordinator = ClipboardSystemCoordinator()
        // 2. The repository converts domain values to pasteboard calls and resolves handles
        //    through the coordinator without owning anything.
        let repository = ClipboardRepositoryImpl(validator: ClipboardTypeIdentifierValidator(),
                                                 lookup: coordinator)
        // 3. The use cases take the repository and the coordinator as the registry port.
        let typeValidator = ClipboardTypeIdentifierValidator()
        let useCases = ClipboardUseCases(repository: repository,
                                         registry: coordinator,
                                         typeValidator: typeValidator,
                                         limits: limits)
        self.init(coordinator: coordinator, useCases: useCases, typeValidator: typeValidator)
    }

    /// Injecting initializer, used by tests and by the convenience initializer above.
    init(coordinator: ClipboardSystemCoordinator,
         useCases: ClipboardUseCases,
         typeValidator: any ClipboardTypeIdentifierValidating) {
        Log.d("MacClipboardManager", "[init]")
        self.coordinator = coordinator
        self.useCases = useCases
        self.typeValidator = typeValidator
        // Shares the aggregate's tracker, so a change already seen by the one-shot foreground
        // check is not reported again by the poller.
        // Through the use case, never the repository: `common.md` forbids a manager reaching
        // the data layer directly, because logic added on that path is unreachable by tests.
        self.monitor = ClipboardChangeMonitor(
            readChangeCount: { [useCases] scope in try useCases.changeCount(scope: scope) },
            tracker: useCases.changeTracker)
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
            validator: typeValidator,
            register: { [coordinator] loader in coordinator.registerPasteLoader(loader) },
            cancel: { [coordinator] handle in coordinator.cancelPaste(handle) },
            onPaste: onPaste)
    }

}
