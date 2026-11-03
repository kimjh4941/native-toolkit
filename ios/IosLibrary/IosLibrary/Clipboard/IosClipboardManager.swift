//
//  IosClipboardManager.swift
//  IosLibrary
//

import Foundation
import os
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "IosClipboardManager")

/// # IosClipboardManager
///
/// Central entry point for `UIPasteboard` operations: copy/append, synchronous read, metadata
/// snapshot, named/unique pasteboard lifecycle, asynchronous `NSItemProvider` loading, pattern
/// detection, change observation, and the `UIPasteControl` paste button.
///
/// ## Threading
/// This type is `@MainActor`-isolated. Call its members from the main actor (e.g. from SwiftUI /
/// UIKit code already on main); from a non-main context, use `await MainActor.run { ... }`, or
/// queue a block on the main queue and call the manager inside it (the C ABI entry points of
/// 2.0.0 do so, with `MainActor.assumeIsolated`). The one exception is ``cancelLoad(_:)``, which
/// is `nonisolated`: call it from any thread. ``shared`` itself is read on the main actor, so to
/// cancel from another thread, keep the manager you got on the main actor (it is `Sendable`) and
/// call ``cancelLoad(_:)`` on it.
///
/// ## API shape
/// - P-1〜P-11 (data-bearing operations) offer both a callback form and an `async throws` native
///   form. `loadItem` also has a callback form that takes a ``RequestBox``
///   (``loadItem(_:scope:requestBox:completion:)``), cancelled with ``cancelLoad(_:)``.
/// - P-12〜P-16 (`cancelAllLoads`, `startObserving`, `stopObserving`, `checkForegroundChange`,
///   `makePasteControl`) and ``cancelLoad(_:)`` complete synchronously and therefore have a
///   single, synchronous form only (see `common.md`'s "同期 control / factory API" exception).
///
/// ## Cancelling a load
///
/// | Way | Cancels | Thread | Result of the cancelled load |
/// |---|---|---|---|
/// | ``cancelLoad(_:)`` | The load of one ``RequestBox`` (also before it starts) | Any | `CLIPBOARD_CANCELLED`, once |
/// | `cancel()` of the ``ClipboardLoadToken`` that ``loadItem(_:scope:completion:)`` returns | That load | Main actor | `CLIPBOARD_CANCELLED`, once |
/// | Cancelling the task of the `async` ``loadItem(_:scope:)`` | That load | Any | Throws `ClipboardError.cancelled` |
/// | ``cancelAllLoads()`` | Every pending load of this manager, of all three forms | Main actor | `CLIPBOARD_CANCELLED` (or `ClipboardError.cancelled`), once each |
///
/// ## Errors
/// Callback completions report `(isSuccess, value?, errorCode?, errorMessage?)` (or
/// `(isSuccess, errorCode?, errorMessage?)` for operations without a return value). `errorCode`
/// matches `ClipboardError.errorCode`; `errorMessage` is a fixed, English, per-case string that
/// never embeds input values. `.cancelled` is reported as `isSuccess == false`; callers may treat
/// `errorCode == "CLIPBOARD_CANCELLED"` as a normal, ignorable outcome.
///
/// ## Named pasteboard lifetime
/// Named/unique pasteboards are **not a persistent store**, but their contents are **not
/// guaranteed to be discarded when the creating process exits** either. Measured on iOS 18.7.2:
/// after force-quitting the app and relaunching it, a named pasteboard written before the quit
/// was still readable. The system does not specify when such a pasteboard is reclaimed.
///
/// Use these scopes only to hand data between live apps, and **delete sensitive data explicitly
/// with `removePasteboard(_:)`** — never rely on app termination to discard it. For sharing that
/// must outlive the creating app by design, use an App Group shared container instead.
///
/// ## append vs copy
/// `append` cannot carry `ClipboardCopyOptions`, and does **not** guarantee that privacy options
/// set by a prior `copy` apply to the appended item. Sensitive data should always use `copy`.
@MainActor
public final class IosClipboardManager: NSObject, @unchecked Sendable {

    /// Shared singleton instance.
    public static let shared = IosClipboardManager()

    private let useCases: ClipboardUseCases

    /// Holds the observer tokens and runs the main-actor cleanup when this manager goes away.
    /// See `ClipboardManagerCleanup` for why the manager itself has no `deinit`.
    private let cleanup: ClipboardManagerCleanup
    private var observingScope: PasteboardScope?
    private var onEvent: ((ClipboardChangeEvent) -> Void)?
    /// Incremented on every start/stop so a notification block queued for an older subscription
    /// can be identified and dropped (see `startObserving`).
    private var observingGeneration: UInt64 = 0

    private override init() {
        logger.log(level: .libraryDebug, "[init]")
        let useCases = Self.makeUseCases(timeouts: .default, limits: .default)
        self.useCases = useCases
        self.cleanup = ClipboardManagerCleanup(cancelAllLoads: useCases.cancelAllLoads)
        super.init()
    }

    /// Creates an instance with custom timeouts and size limits.
    ///
    /// Use this when the defaults (`ClipboardTimeouts.default` / `ClipboardLimits.default`) do not
    /// suit your workload — for example to shorten timeouts in tests, or to tighten the accepted
    /// payload size. Prefer ``shared`` for ordinary use.
    public convenience init(timeouts: ClipboardTimeouts, limits: ClipboardLimits) {
        self.init(useCases: Self.makeUseCases(timeouts: timeouts, limits: limits))
    }

    /// Internal initializer for tests to inject use cases built from mock repositories/loaders.
    init(useCases: ClipboardUseCases) {
        logger.log(level: .libraryDebug, "[init:test]")
        self.useCases = useCases
        self.cleanup = ClipboardManagerCleanup(cancelAllLoads: useCases.cancelAllLoads)
        super.init()
    }

    private static func makeUseCases(timeouts: ClipboardTimeouts, limits: ClipboardLimits) -> ClipboardUseCases {
        let repository = ClipboardRepositoryImpl(limits: limits, timeouts: timeouts)
        let loader = ClipboardItemLoaderImpl(limits: limits, timeouts: timeouts)
        let typeValidator = ClipboardTypeIdentifierValidator()
        return ClipboardUseCases(
            repository: repository,
            loader: loader,
            typeValidator: typeValidator,
            contentValidator: ClipboardContentValidator(limits: limits),
            timeouts: timeouts
        )
    }

    // MARK: - P-1 copy

    /// Replaces the contents of the pasteboard of `scope` with `content`, with `options`.
    /// - Parameter completion: `(isSuccess, errorCode, errorMessage)` on the main actor, once (see "Errors" above). Optional.
    public func copy(
        _ content: ClipboardContent,
        options: ClipboardCopyOptions = .default,
        scope: PasteboardScope = .general,
        completion: ((Bool, String?, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "[copy] scope: \(scope.redactedDescription, privacy: .public), localOnly: \(options.localOnly, privacy: .public)")
        runVoid({ try await self.useCases.copyContent.execute(content, options: options, scope: scope) }, completion: completion)
    }

    /// Replaces the contents of the pasteboard of `scope` with `content`, with `options`.
    /// - Throws: A `ClipboardError`.
    public func copy(
        _ content: ClipboardContent,
        options: ClipboardCopyOptions = .default,
        scope: PasteboardScope = .general
    ) async throws -> Void {
        logger.log(level: .libraryDebug, "[copy] scope: \(scope.redactedDescription, privacy: .public), localOnly: \(options.localOnly, privacy: .public)")
        try await useCases.copyContent.execute(content, options: options, scope: scope)
    }

    // MARK: - P-2 append

    /// Adds `content` as a new item after the items of the pasteboard of `scope` (no copy options:
    /// see "append vs copy" above).
    /// - Parameter completion: `(isSuccess, errorCode, errorMessage)` on the main actor, once (see "Errors" above). Optional.
    public func append(
        _ content: ClipboardContent,
        scope: PasteboardScope = .general,
        completion: ((Bool, String?, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "[append] scope: \(scope.redactedDescription, privacy: .public)")
        runVoid({ try await self.useCases.appendContent.execute(content, scope: scope) }, completion: completion)
    }

    /// Adds `content` as a new item after the items of the pasteboard of `scope`.
    /// - Throws: A `ClipboardError`.
    public func append(_ content: ClipboardContent, scope: PasteboardScope = .general) async throws -> Void {
        logger.log(level: .libraryDebug, "[append] scope: \(scope.redactedDescription, privacy: .public)")
        try await useCases.appendContent.execute(content, scope: scope)
    }

    // MARK: - P-3 read

    /// Reads the items of the pasteboard of `scope` synchronously (the text, URL and type
    /// identifiers of each item). iOS can ask the user to allow the paste when another app wrote
    /// the content; the read then waits for the answer on the main thread, also while the app is in
    /// the background (measured on the iOS 26.2 simulator, stage 1b MS-08). To read without blocking,
    /// use `loadItem`.
    /// - Parameter completion: `(isSuccess, result, errorCode, errorMessage)` on the main actor, once.
    public func read(
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, ClipboardReadResult?, String?, String?) -> Void
    ) {
        logger.log(level: .libraryDebug, "[read] scope: \(scope.redactedDescription, privacy: .public)")
        runValue({ try self.useCases.readContent.execute(scope: scope) }, completion: completion)
    }

    /// Reads the items of the pasteboard of `scope`.
    /// - Throws: A `ClipboardError`.
    public func read(scope: PasteboardScope = .general) async throws -> ClipboardReadResult {
        logger.log(level: .libraryDebug, "[read] scope: \(scope.redactedDescription, privacy: .public)")
        return try useCases.readContent.execute(scope: scope)
    }

    // MARK: - P-4 readData

    /// Reads the data of type `utType` from the pasteboard of `scope` (`nil` when no item has it).
    /// Like ``read(scope:completion:)``, it can wait on the main thread for the user to allow the paste.
    /// - Parameter completion: `(isSuccess, data, errorCode, errorMessage)` on the main actor, once.
    public func readData(
        utType: String,
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, Data?, String?, String?) -> Void
    ) {
        logger.log(level: .libraryDebug, "[readData] utType: \(utType, privacy: .private), scope: \(scope.redactedDescription, privacy: .public)")
        Task { @MainActor in
            do {
                let data = try self.useCases.readData.execute(utType: utType, scope: scope)
                completion(true, data, nil, nil)
            } catch let error as ClipboardError {
                completion(false, nil, error.errorCode, error.errorDescription)
            } catch {
                completion(false, nil, ClipboardError.unknownErrorCode, ClipboardError.unknownMessage)
            }
        }
    }

    /// Reads the data of type `utType` from the pasteboard of `scope` (`nil` when no item has it).
    /// - Throws: A `ClipboardError`.
    public func readData(utType: String, scope: PasteboardScope = .general) async throws -> Data? {
        logger.log(level: .libraryDebug, "[readData] utType: \(utType, privacy: .private), scope: \(scope.redactedDescription, privacy: .public)")
        return try useCases.readData.execute(utType: utType, scope: scope)
    }

    // MARK: - P-5 snapshot

    /// Reads the metadata of the pasteboard of `scope` (counts, kinds and type identifiers; no
    /// contents), and the indexes of the items that have one of `matchingTypes`.
    /// - Parameter completion: `(isSuccess, snapshot, errorCode, errorMessage)` on the main actor, once.
    public func snapshot(
        matchingTypes: [String]? = nil,
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, ClipboardSnapshot?, String?, String?) -> Void
    ) {
        logger.log(level: .libraryDebug, "[snapshot] scope: \(scope.redactedDescription, privacy: .public)")
        runValue({ try self.useCases.getSnapshot.execute(matchingTypes: matchingTypes, scope: scope) }, completion: completion)
    }

    /// Reads the metadata of the pasteboard of `scope`.
    /// - Throws: A `ClipboardError`.
    public func snapshot(matchingTypes: [String]? = nil, scope: PasteboardScope = .general) async throws -> ClipboardSnapshot {
        logger.log(level: .libraryDebug, "[snapshot] scope: \(scope.redactedDescription, privacy: .public)")
        return try useCases.getSnapshot.execute(matchingTypes: matchingTypes, scope: scope)
    }

    // MARK: - P-6 clear

    /// Removes every item of the pasteboard of `scope`.
    /// - Parameter completion: `(isSuccess, errorCode, errorMessage)` on the main actor, once (see "Errors" above). Optional.
    public func clear(scope: PasteboardScope = .general, completion: ((Bool, String?, String?) -> Void)? = nil) {
        logger.log(level: .libraryDebug, "[clear] scope: \(scope.redactedDescription, privacy: .public)")
        runVoid({ try self.useCases.clearClipboard.execute(scope: scope) }, completion: completion)
    }

    /// Removes every item of the pasteboard of `scope`.
    /// - Throws: A `ClipboardError`.
    public func clear(scope: PasteboardScope = .general) async throws -> Void {
        logger.log(level: .libraryDebug, "[clear] scope: \(scope.redactedDescription, privacy: .public)")
        try useCases.clearClipboard.execute(scope: scope)
    }

    // MARK: - P-7 createPasteboard

    /// Creates (or opens) a named pasteboard, or creates a unique one, and returns its scope (see
    /// "Named pasteboard lifetime" above).
    /// - Parameter completion: `(isSuccess, scope, errorCode, errorMessage)` on the main actor, once.
    public func createPasteboard(
        _ request: PasteboardCreationRequest,
        completion: @escaping (Bool, PasteboardScope?, String?, String?) -> Void
    ) {
        logger.log(level: .libraryDebug, "[createPasteboard] request: \(request.redactedDescription, privacy: .public)")
        runValue({ try self.useCases.createPasteboard.execute(request) }, completion: completion)
    }

    /// Creates (or opens) a named pasteboard, or creates a unique one, and returns its scope.
    /// - Throws: A `ClipboardError`.
    public func createPasteboard(_ request: PasteboardCreationRequest) async throws -> PasteboardScope {
        logger.log(level: .libraryDebug, "[createPasteboard] request: \(request.redactedDescription, privacy: .public)")
        return try useCases.createPasteboard.execute(request)
    }

    // MARK: - P-8 removePasteboard

    /// Removes a named or unique pasteboard and its contents (the general pasteboard cannot be
    /// removed).
    /// - Parameter completion: `(isSuccess, errorCode, errorMessage)` on the main actor, once (see "Errors" above). Optional.
    public func removePasteboard(_ scope: PasteboardScope, completion: ((Bool, String?, String?) -> Void)? = nil) {
        logger.log(level: .libraryDebug, "[removePasteboard] scope: \(scope.redactedDescription, privacy: .public)")
        runVoid({ try self.useCases.removePasteboard.execute(scope) }, completion: completion)
    }

    /// Removes a named or unique pasteboard and its contents.
    /// - Throws: A `ClipboardError`.
    public func removePasteboard(_ scope: PasteboardScope) async throws -> Void {
        logger.log(level: .libraryDebug, "[removePasteboard] scope: \(scope.redactedDescription, privacy: .public)")
        try useCases.removePasteboard.execute(scope)
    }

    // MARK: - P-9 detectPatterns

    /// Reports which of `patterns` the pasteboard of `scope` probably holds, without reading its
    /// contents (no paste prompt).
    /// - Parameter completion: `(isSuccess, patterns, errorCode, errorMessage)` on the main actor, once.
    public func detectPatterns(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, Set<ClipboardDetectionPattern>?, String?, String?) -> Void
    ) {
        logger.log(level: .libraryDebug, "[detectPatterns] scope: \(scope.redactedDescription, privacy: .public), count: \(patterns.count, privacy: .public)")
        runValue({ try await self.useCases.detectPatterns.execute(patterns, scope: scope) }, completion: completion)
    }

    /// Reports which of `patterns` the pasteboard of `scope` probably holds.
    /// - Throws: A `ClipboardError`.
    public func detectPatterns(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope = .general
    ) async throws -> Set<ClipboardDetectionPattern> {
        logger.log(level: .libraryDebug, "[detectPatterns] scope: \(scope.redactedDescription, privacy: .public), count: \(patterns.count, privacy: .public)")
        return try await useCases.detectPatterns.execute(patterns, scope: scope)
    }

    // MARK: - P-10 detectValues

    /// Detects the values of `patterns` in the pasteboard of `scope` (reads the contents: iOS can
    /// ask the user to allow the paste).
    /// - Parameter completion: `(isSuccess, values, errorCode, errorMessage)` on the main actor, once.
    public func detectValues(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, ClipboardDetectedValues?, String?, String?) -> Void
    ) {
        logger.log(level: .libraryDebug, "[detectValues] scope: \(scope.redactedDescription, privacy: .public), count: \(patterns.count, privacy: .public)")
        runValue({ try await self.useCases.detectValues.execute(patterns, scope: scope) }, completion: completion)
    }

    /// Detects the values of `patterns` in the pasteboard of `scope`.
    /// - Throws: A `ClipboardError`.
    public func detectValues(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope = .general
    ) async throws -> ClipboardDetectedValues {
        logger.log(level: .libraryDebug, "[detectValues] scope: \(scope.redactedDescription, privacy: .public), count: \(patterns.count, privacy: .public)")
        return try await useCases.detectValues.execute(patterns, scope: scope)
    }

    // MARK: - P-11 loadItem

    /// Loads the first item of the pasteboard of `scope` that matches `request`, and returns a
    /// token that cancels the load.
    ///
    /// The load reads the pasteboard's item providers, so iOS can ask the user to allow the paste
    /// when another app wrote the content. The load's timeout (``ClipboardTimeouts/providerLoad``,
    /// 15 seconds by default) includes the time the user takes to answer: without an answer by
    /// then, the load fails with `CLIPBOARD_TIMED_OUT`, and a later answer delivers nothing.
    ///
    /// - Parameters:
    ///   - request: What to load (text, URL, image, or a file of a type identifier).
    ///   - scope: The pasteboard to load from.
    ///   - completion: `(isSuccess, item, errorCode, errorMessage)`, exactly once, on the main
    ///     actor. A cancelled load reports `(false, nil, "CLIPBOARD_CANCELLED", <fixed text>)`.
    ///     For a `.file` item, you own the file and its parent directory: delete them when done.
    /// - Returns: A token whose `cancel()` (main actor) cancels this load. To cancel from another
    ///   thread, or before the load starts, use ``loadItem(_:scope:requestBox:completion:)`` and
    ///   ``cancelLoad(_:)`` instead.
    @discardableResult
    public func loadItem(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, ClipboardLoadedItem?, String?, String?) -> Void
    ) -> any ClipboardLoadToken {
        logger.log(level: .libraryDebug, "[loadItem] request: \(request.logKind, privacy: .public), utType: \(request.logTypeIdentifier, privacy: .private), scope: \(scope.redactedDescription, privacy: .public), completion: provided")
        return useCases.loadItem.execute(request, scope: scope) { result in
            switch result {
            case .success(let item):
                completion(true, item, nil, nil)
            case .failure(let error):
                completion(false, nil, error.errorCode, error.errorDescription)
            }
        }
    }

    /// Loads the first item of the pasteboard of `scope` that matches `request`.
    ///
    /// The same load as ``loadItem(_:scope:completion:)``. Cancelling the calling task cancels
    /// the load, and this throws `ClipboardError.cancelled`.
    ///
    /// - Parameters:
    ///   - request: What to load.
    ///   - scope: The pasteboard to load from.
    /// - Returns: The item. For a `.file` item, you own the file and its parent directory.
    /// - Throws: A `ClipboardError`.
    public func loadItem(_ request: ClipboardLoadRequest, scope: PasteboardScope = .general) async throws -> ClipboardLoadedItem {
        logger.log(level: .libraryDebug, "[loadItem async] request: \(request.logKind, privacy: .public), utType: \(request.logTypeIdentifier, privacy: .private), scope: \(scope.redactedDescription, privacy: .public)")
        let box = ClipboardCancellationBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let token = self.useCases.loadItem.execute(request, scope: scope) { result in
                    continuation.resume(with: result.mapError { $0 as Error })
                }
                box.attach(token)
            }
        } onCancel: {
            box.cancel()
        }
    }

    // MARK: - P-11 loadItem with a request box (stage 1b, S-P22)

    /// Loads the first item of the pasteboard of `scope` that matches `request`, in the request
    /// of `requestBox`, which ``cancelLoad(_:)`` cancels from any thread.
    ///
    /// The same load as ``loadItem(_:scope:completion:)``; the box takes the place of the token.
    /// Create the box before the call, so that the request can be cancelled from the moment you
    /// make it.
    ///
    /// | Completion | When |
    /// |---|---|
    /// | `(true, item, nil, nil)` | The item was loaded |
    /// | `(false, nil, "CLIPBOARD_CANCELLED", <fixed text>)` | ``cancelLoad(_:)`` closed the box before the result: during the load, or before this call (then nothing is read). Also ``cancelAllLoads()`` or the manager going away during the load |
    /// | `(false, nil, "CLIPBOARD_INVALID_REQUEST", <fixed text>)` | Another request already uses `requestBox` (a box is used once). That request is not affected, and nothing is read |
    /// | `(false, nil, <errorCode>, <fixed text>)` | The load failed as in ``loadItem(_:scope:completion:)`` (`errorCode` is `ClipboardError.errorCode`) |
    ///
    /// The first of the result and the cancellation closes the box, and only it is reported. A
    /// result that arrives after the box was cancelled is dropped; a `.file` item dropped so is
    /// deleted (nobody else would own it). A cancellation after the result changes nothing.
    ///
    /// - Parameters:
    ///   - request: What to load.
    ///   - scope: The pasteboard to load from.
    ///   - requestBox: A new ``RequestBox`` for this request. Pass the same box to
    ///     ``cancelLoad(_:)`` to cancel the request.
    ///   - completion: `(isSuccess, item, errorCode, errorMessage)`, exactly once, on the main
    ///     thread, never inside this call. For a `.file` item, you own the file and its parent
    ///     directory: delete them when done.
    public func loadItem(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope = .general,
        requestBox: RequestBox,
        completion: @escaping (Bool, ClipboardLoadedItem?, String?, String?) -> Void
    ) {
        logger.log(level: .libraryDebug, "[loadItem box] request: \(request.logKind, privacy: .public), utType: \(request.logTypeIdentifier, privacy: .private), scope: \(scope.redactedDescription, privacy: .public), requestBox closed: \(requestBox.isClosed, privacy: .public), completion: provided")
        ClipboardBoxedLoad.start(request, scope: scope, box: requestBox, loadItem: useCases.loadItem, completion: completion)
    }

    /// Cancels the load of `box`: its completion reports `CLIPBOARD_CANCELLED`, and the load is
    /// stopped.
    ///
    /// The request ends at once: the box is closed in this call, so a result that arrives later
    /// is dropped. The completion and stopping the load follow on the main thread.
    ///
    /// | `box` | Effect |
    /// |---|---|
    /// | Its load is in progress | The completion reports `CLIPBOARD_CANCELLED`, once |
    /// | No request uses it yet | The box is closed: a ``loadItem(_:scope:requestBox:completion:)`` made with it later reads nothing and reports `CLIPBOARD_CANCELLED` |
    /// | Its request has ended (or was already cancelled) | Nothing changes: the reported result stands |
    ///
    /// Any thread, also from inside a completion; never waits for the main thread. The box
    /// stays closed: a cancelled request cannot be started again with it.
    ///
    /// - Note: ``shared`` is read on the main actor. To call this method from another thread,
    ///   keep the manager you got on the main actor (it is `Sendable`) and call it on that
    ///   reference.
    /// - Note: This method closes whatever box it is given. Pass only a box of a Clipboard load:
    ///   a box that another library request uses (for example a Dialog's) ends that request.
    /// - Parameter box: The box you passed to ``loadItem(_:scope:requestBox:completion:)``.
    nonisolated public func cancelLoad(_ box: RequestBox) {
        logger.log(level: .libraryDebug, "[cancelLoad] box closed: \(box.isClosed, privacy: .public)")
        let closed = box.close(.canceled)
        logger.log(level: .libraryDebug, "[cancelLoad] closed by this call: \(closed, privacy: .public)")
    }

    // MARK: - P-12 cancelAllLoads (synchronous control)

    /// Cancels every pending load of this manager: each one's completion reports
    /// `CLIPBOARD_CANCELLED` (the `async` form throws `ClipboardError.cancelled`), once.
    ///
    /// It covers the loads of all three `loadItem` forms. A load of
    /// ``loadItem(_:scope:requestBox:completion:)`` cancelled so leaves its box closed. Loads that
    /// have already reported are not affected, and loads started later are not cancelled.
    public func cancelAllLoads() {
        logger.log(level: .libraryDebug, "[cancelAllLoads]")
        useCases.cancelAllLoads.execute()
    }

    // MARK: - P-13 / P-14 change observation (synchronous control; event delivery is async)

    /// Starts observing clipboard changes for `scope`. A second call (for the same or a
    /// different scope) first stops the previous observation, so there is never more than one
    /// active subscription.
    ///
    /// - Throws: `ClipboardError.pasteboardUnavailable` if `scope` cannot be resolved (e.g. a
    ///   named pasteboard whose creating app has quit). Observation is not started in that case.
    public func startObserving(
        scope: PasteboardScope = .general,
        onEvent: @escaping (ClipboardChangeEvent) -> Void
    ) throws {
        logger.log(level: .libraryDebug, "[startObserving] scope: \(scope.redactedDescription, privacy: .public)")
        stopObservingInternal()
        guard let pasteboard = Self.resolvePasteboardForObserving(scope) else {
            logger.error("[startObserving] pasteboard unavailable")
            throw ClipboardError.pasteboardUnavailable(name: Self.scopeName(of: scope))
        }
        useCases.checkForegroundChange.resync(scope: scope)

        // Generation gate: a notification block already queued for a previous subscription must
        // never deliver into the new subscriber, even when both use the same scope.
        observingGeneration &+= 1
        let generation = observingGeneration
        observingScope = scope
        self.onEvent = onEvent

        cleanup.changedToken = NotificationCenter.default.addObserver(
            forName: UIPasteboard.changedNotification, object: pasteboard, queue: .main
        ) { [weak self] note in
            // `Notification` is not `Sendable`, so its payload is extracted *before* the
            // main-actor boundary; only the resulting `[String]` values cross it.
            let added = note.userInfo?[UIPasteboard.changedTypesAddedUserInfoKey] as? [String] ?? []
            let removed = note.userInfo?[UIPasteboard.changedTypesRemovedUserInfoKey] as? [String] ?? []
            // Registered with `queue: .main`, so this always runs on the main thread; asserting
            // main-actor isolation here (rather than hopping via `Task`) keeps event delivery
            // synchronous and preserves ordering.
            MainActor.assumeIsolated {
                guard let self, self.observingGeneration == generation else { return }
                self.useCases.checkForegroundChange.markReported(scope: scope)
                self.onEvent?(
                    ClipboardChangeEvent(kind: .changed(typesAdded: added, typesRemoved: removed), scope: scope)
                )
            }
        }
        cleanup.removedToken = NotificationCenter.default.addObserver(
            forName: UIPasteboard.removedNotification, object: pasteboard, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.observingGeneration == generation else { return }
                self.onEvent?(ClipboardChangeEvent(kind: .removed, scope: scope))
            }
        }
    }

    /// Stops the observation started by ``startObserving(scope:onEvent:)``; no event is delivered
    /// after this call, also one already queued. Does nothing when not observing.
    public func stopObserving() {
        logger.log(level: .libraryDebug, "[stopObserving]")
        stopObservingInternal()
    }

    private func stopObservingInternal() {
        cleanup.removeObservers()
        observingScope = nil
        onEvent = nil
        // Invalidate any notification block already queued for the subscription being stopped.
        observingGeneration &+= 1
    }

    private static func resolvePasteboardForObserving(_ scope: PasteboardScope) -> UIPasteboard? {
        switch scope {
        case .general:
            return .general
        case .named(let name), .unique(let name):
            return UIPasteboard(name: UIPasteboard.Name(name), create: false)
        }
    }

    private static func scopeName(of scope: PasteboardScope) -> String {
        switch scope {
        case .general: return "general"
        case .named(let name), .unique(let name): return name
        }
    }

    // MARK: - P-15 checkForegroundChange (synchronous control)

    /// Whether the pasteboard of `scope` changed since it was last checked or observed (compares
    /// `changeCount`; reads no contents). Call it when the app comes to the foreground. The first
    /// check of a scope that was never checked or observed reports `false` (it only records the
    /// count).
    public func checkForegroundChange(scope: PasteboardScope = .general) -> Bool {
        logger.log(level: .libraryDebug, "[checkForegroundChange] scope: \(scope.redactedDescription, privacy: .public)")
        return useCases.checkForegroundChange.execute(scope: scope)
    }

    // MARK: - P-16 makePasteControl (synchronous factory; not exposed to the Unity Bridge)

    /// Creates a ready-to-place `UIPasteControl` + receiver container.
    /// - Throws: `ClipboardError.invalidRequest` if `acceptedTypes` is empty, or
    ///   `ClipboardError.invalidTypeIdentifier` if any entry is invalid.
    public func makePasteControl(
        acceptedTypes: [String],
        displayMode: UIPasteControl.DisplayMode = .iconAndLabel,
        onPaste: @escaping ([ClipboardLoadedItem]) -> Void,
        onPartialFailure: (([ClipboardError]) -> Void)? = nil,
        onPasteFailure: ((ClipboardError) -> Void)? = nil
    ) throws -> ClipboardPasteControlContainerView {
        logger.log(level: .libraryDebug, "[makePasteControl] acceptedTypesCount: \(acceptedTypes.count, privacy: .public)")
        let container = try ClipboardPasteControlContainerView(acceptedTypes: acceptedTypes, displayMode: displayMode)
        container.onPaste = onPaste
        container.onPartialFailure = onPartialFailure
        container.onPasteFailure = onPasteFailure
        return container
    }

    // MARK: - Private helpers

    private func runVoid(
        _ operation: @escaping () async throws -> Void,
        completion: ((Bool, String?, String?) -> Void)?
    ) {
        Task { @MainActor in
            do {
                try await operation()
                completion?(true, nil, nil)
            } catch let error as ClipboardError {
                logger.error("[runVoid] errorCode: \(error.errorCode, privacy: .public)")
                completion?(false, error.errorCode, error.errorDescription)
            } catch {
                logger.error("[runVoid] unknown error")
                completion?(false, ClipboardError.unknownErrorCode, ClipboardError.unknownMessage)
            }
        }
    }

    private func runValue<T>(
        _ operation: @escaping () async throws -> T,
        completion: @escaping (Bool, T?, String?, String?) -> Void
    ) {
        Task { @MainActor in
            do {
                let value = try await operation()
                completion(true, value, nil, nil)
            } catch let error as ClipboardError {
                logger.error("[runValue] errorCode: \(error.errorCode, privacy: .public)")
                completion(false, nil, error.errorCode, error.errorDescription)
            } catch {
                logger.error("[runValue] unknown error")
                completion(false, nil, ClipboardError.unknownErrorCode, ClipboardError.unknownMessage)
            }
        }
    }
}

private let boxedLoadLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ClipboardBoxedLoad")

/// One request of `IosClipboardManager.loadItem(_:scope:requestBox:completion:)`: ties a
/// `RequestBox` to one load of `LoadItemUseCase`.
///
/// The box decides the outcome: the load's result and `cancelLoad(_:)` (any thread) both close
/// it, and only the first close counts. The box's close handler (queued on the main queue by the
/// box) reports that outcome to the caller once and, for a cancellation, cancels the load's token
/// on the main actor. A plain Swift class on the main actor, so it holds the caller's
/// non-`Sendable` completion while the box's `@Sendable` handler holds it.
@MainActor
private final class ClipboardBoxedLoad {
    private var completion: ((Bool, ClipboardLoadedItem?, String?, String?) -> Void)?
    private var token: (any ClipboardLoadToken)?

    private init(completion: @escaping (Bool, ClipboardLoadedItem?, String?, String?) -> Void) {
        boxedLoadLogger.log(level: .libraryDebug, "[init] completion: provided")
        self.completion = completion
    }

    static func start(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope,
        box: RequestBox,
        loadItem: LoadItemUseCase,
        completion: @escaping (Bool, ClipboardLoadedItem?, String?, String?) -> Void
    ) {
        boxedLoadLogger.log(level: .libraryDebug, "[start] request: \(request.logKind, privacy: .public), utType: \(request.logTypeIdentifier, privacy: .private), scope: \(scope.redactedDescription, privacy: .public), box closed: \(box.isClosed, privacy: .public), completion: provided")
        let load = ClipboardBoxedLoad(completion: completion)
        guard box.attach({ outcome in load.finish(outcome) }) else {
            // The box belongs to another request, which is left alone. Reported on a later turn,
            // as every other outcome (never inside the call).
            boxedLoadLogger.error("[start] the request box is already used by another request")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    load.report(.failure(.invalidRequest("requestBox is already used by another request")))
                }
            }
            return
        }
        // Closed before the load started (cancelLoad before the call, or from another thread right
        // now): the box has queued the cancellation; read nothing.
        guard !box.isClosed else {
            boxedLoadLogger.log(level: .libraryDebug, "[start] the box is already closed, not loading")
            return
        }
        // A cancellation from another thread from here on queues its handler behind this turn, so
        // the token is set when the handler runs.
        load.token = loadItem.execute(request, scope: scope) { result in
            if !box.close(.completed(result)) {
                load.dropLateResult(result)
            }
        }
    }

    /// The box's close handler: on the main thread, once.
    private func finish(_ outcome: RequestBoxOutcome) {
        boxedLoadLogger.log(level: .libraryDebug, "[finish] outcome: \(outcome.logName, privacy: .public)")
        let pending = token
        token = nil
        switch outcome {
        case .completed(let value):
            guard let result = value as? Result<ClipboardLoadedItem, ClipboardError> else {
                boxedLoadLogger.error("[finish] unexpected result type")
                report(.failure(.unknown(ClipboardFailureDetail(
                    domain: "IosClipboardManager", code: -1, debugMessage: "unexpected request box result"))))
                return
            }
            report(result)
        case .canceled:
            // The loader reports `.cancelled` into the closed box, where it is dropped.
            pending?.cancel()
            report(.failure(.cancelled))
        case .notForeground, .presentationFailed, .dismissedBySystem:
            // Only presenting operations close a box so, and they attach it first, so a box that
            // reaches here cannot carry these. Stop the load and report the cancellation anyway.
            boxedLoadLogger.error("[finish] unexpected outcome: \(outcome.logName, privacy: .public)")
            pending?.cancel()
            report(.failure(.cancelled))
        }
    }

    /// A result that lost to the cancellation: nobody receives it, so a loaded file is deleted.
    private func dropLateResult(_ result: Result<ClipboardLoadedItem, ClipboardError>) {
        boxedLoadLogger.log(level: .libraryDebug, "[dropLateResult] result: \(result.logKind, privacy: .public)")
        if case .success(.file(let url)) = result {
            ClipboardTemporaryFileStore.discardUndelivered(url)
        }
    }

    private func report(_ result: Result<ClipboardLoadedItem, ClipboardError>) {
        boxedLoadLogger.log(level: .libraryDebug, "[report] result: \(result.logKind, privacy: .public)")
        guard let completion else { return }
        self.completion = nil
        switch result {
        case .success(let item):
            completion(true, item, nil, nil)
        case .failure(let error):
            completion(false, nil, error.errorCode, error.errorDescription)
        }
    }
}

/// Cleanup that must run on the main actor when an `IosClipboardManager` goes away: remove the
/// change observers and cancel pending loads.
///
/// The manager is an `NSObject` subclass. In the Swift 6 language mode, the Objective-C `dealloc`
/// entry of an `NSObject` subclass with an `isolated deinit` checks that it runs on the main actor
/// and stops the process otherwise, so an instance released off the main thread would trap
/// (stage 0f of `ios-c-abi`). This holder is a plain Swift class, whose `isolated deinit` hops to
/// the main actor instead, so the manager needs no `deinit` and may be released on any thread.
@MainActor
private final class ClipboardManagerCleanup {
    var changedToken: NSObjectProtocol?
    var removedToken: NSObjectProtocol?
    private let cancelAllLoads: CancelAllLoadsUseCase

    init(cancelAllLoads: CancelAllLoadsUseCase) {
        self.cancelAllLoads = cancelAllLoads
    }

    func removeObservers() {
        if let changedToken { NotificationCenter.default.removeObserver(changedToken) }
        if let removedToken { NotificationCenter.default.removeObserver(removedToken) }
        changedToken = nil
        removedToken = nil
    }

    isolated deinit {
        removeObservers()
        cancelAllLoads.execute()
    }
}
