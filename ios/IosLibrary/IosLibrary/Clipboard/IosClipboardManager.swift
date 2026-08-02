//
//  IosClipboardManager.swift
//  IosLibrary
//

import Foundation
import UIKit

/// # IosClipboardManager
///
/// Central entry point for `UIPasteboard` operations: copy/append, synchronous read, metadata
/// snapshot, named/unique pasteboard lifecycle, asynchronous `NSItemProvider` loading, pattern
/// detection, change observation, and the `UIPasteControl` paste button.
///
/// ## Threading
/// This type is `@MainActor`-isolated. Call its members from the main actor (e.g. from SwiftUI /
/// UIKit code already on main); from a non-main context, use `await MainActor.run { ... }`. The
/// Unity Bridge facade (`UnityIosClipboardManager`) is the sole entry point designed to be called
/// from an arbitrary thread; it hops to the main actor internally.
///
/// ## API shape
/// - P-1〜P-11 (data-bearing operations) offer both a callback form (Bridge-friendly) and an
///   `async throws` native form.
/// - P-12〜P-16 (`cancelAllLoads`, `startObserving`, `stopObserving`, `checkForegroundChange`,
///   `makePasteControl`) complete synchronously and therefore have a single, synchronous form
///   only (see `common.md`'s "同期 control / factory API" exception).
///
/// ## Errors
/// Callback completions report `(isSuccess, value?, errorCode?, errorMessage?)` (or
/// `(isSuccess, errorCode?, errorMessage?)` for operations without a return value). `errorCode`
/// matches `ClipboardError.errorCode`; `errorMessage` is a fixed, English, per-case string that
/// never embeds input values. `.cancelled` is reported as `isSuccess == false`; callers may treat
/// `errorCode == "CLIPBOARD_CANCELLED"` as a normal, ignorable outcome.
///
/// ## Named pasteboard lifetime
/// Named/unique pasteboards are **not persistent**: they exist only while the app that created
/// them is running. They are suitable only for transferring data while both sides are alive —
/// never for persistent sharing (use an App Group shared container for that instead).
///
/// ## append vs copy
/// `append` cannot carry `ClipboardCopyOptions`, and does **not** guarantee that privacy options
/// set by a prior `copy` apply to the appended item. Sensitive data should always use `copy`.
@MainActor
public final class IosClipboardManager: NSObject, @unchecked Sendable {

    private let TAG = "IosClipboardManager"

    /// Shared singleton instance.
    public static let shared = IosClipboardManager()

    private let useCases: ClipboardUseCases

    private var changedToken: NSObjectProtocol?
    private var removedToken: NSObjectProtocol?
    private var observingScope: PasteboardScope?
    private var onEvent: ((ClipboardChangeEvent) -> Void)?

    private override init() {
        Log.d(TAG, "[init]")
        let repository = ClipboardRepositoryImpl()
        let loader = ClipboardItemLoaderImpl()
        let typeValidator = ClipboardTypeIdentifierValidator()
        self.useCases = ClipboardUseCases(repository: repository, loader: loader, typeValidator: typeValidator)
        super.init()
    }

    /// Internal initializer for tests to inject use cases built from mock repositories/loaders.
    init(useCases: ClipboardUseCases) {
        Log.d(TAG, "[init:test]")
        self.useCases = useCases
        super.init()
    }

    isolated deinit {
        stopObservingInternal()
        useCases.cancelAllLoads.execute()
    }

    // MARK: - P-1 copy

    public func copy(
        _ content: ClipboardContent,
        options: ClipboardCopyOptions = .default,
        scope: PasteboardScope = .general,
        completion: ((Bool, String?, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "[copy] scope: \(scope), localOnly: \(options.localOnly)")
        runVoid({ try await self.useCases.copyContent.execute(content, options: options, scope: scope) }, completion: completion)
    }

    @discardableResult
    public func copy(
        _ content: ClipboardContent,
        options: ClipboardCopyOptions = .default,
        scope: PasteboardScope = .general
    ) async throws -> Void {
        Log.d(TAG, "[copy] scope: \(scope), localOnly: \(options.localOnly)")
        try await useCases.copyContent.execute(content, options: options, scope: scope)
    }

    // MARK: - P-2 append

    public func append(
        _ content: ClipboardContent,
        scope: PasteboardScope = .general,
        completion: ((Bool, String?, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "[append] scope: \(scope)")
        runVoid({ try await self.useCases.appendContent.execute(content, scope: scope) }, completion: completion)
    }

    @discardableResult
    public func append(_ content: ClipboardContent, scope: PasteboardScope = .general) async throws -> Void {
        Log.d(TAG, "[append] scope: \(scope)")
        try await useCases.appendContent.execute(content, scope: scope)
    }

    // MARK: - P-3 read

    public func read(
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, ClipboardReadResult?, String?, String?) -> Void
    ) {
        Log.d(TAG, "[read] scope: \(scope)")
        runValue({ try self.useCases.readContent.execute(scope: scope) }, completion: completion)
    }

    public func read(scope: PasteboardScope = .general) async throws -> ClipboardReadResult {
        Log.d(TAG, "[read] scope: \(scope)")
        return try useCases.readContent.execute(scope: scope)
    }

    // MARK: - P-4 readData

    public func readData(
        utType: String,
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, Data?, String?, String?) -> Void
    ) {
        Log.d(TAG, "[readData] utType: \(utType), scope: \(scope)")
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

    public func readData(utType: String, scope: PasteboardScope = .general) async throws -> Data? {
        Log.d(TAG, "[readData] utType: \(utType), scope: \(scope)")
        return try useCases.readData.execute(utType: utType, scope: scope)
    }

    // MARK: - P-5 snapshot

    public func snapshot(
        matchingTypes: [String]? = nil,
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, ClipboardSnapshot?, String?, String?) -> Void
    ) {
        Log.d(TAG, "[snapshot] scope: \(scope)")
        runValue({ try self.useCases.getSnapshot.execute(matchingTypes: matchingTypes, scope: scope) }, completion: completion)
    }

    public func snapshot(matchingTypes: [String]? = nil, scope: PasteboardScope = .general) async throws -> ClipboardSnapshot {
        Log.d(TAG, "[snapshot] scope: \(scope)")
        return try useCases.getSnapshot.execute(matchingTypes: matchingTypes, scope: scope)
    }

    // MARK: - P-6 clear

    public func clear(scope: PasteboardScope = .general, completion: ((Bool, String?, String?) -> Void)? = nil) {
        Log.d(TAG, "[clear] scope: \(scope)")
        runVoid({ try self.useCases.clearClipboard.execute(scope: scope) }, completion: completion)
    }

    public func clear(scope: PasteboardScope = .general) async throws -> Void {
        Log.d(TAG, "[clear] scope: \(scope)")
        try useCases.clearClipboard.execute(scope: scope)
    }

    // MARK: - P-7 createPasteboard

    public func createPasteboard(
        _ request: PasteboardCreationRequest,
        completion: @escaping (Bool, PasteboardScope?, String?, String?) -> Void
    ) {
        Log.d(TAG, "[createPasteboard] request: \(request)")
        runValue({ try self.useCases.createPasteboard.execute(request) }, completion: completion)
    }

    public func createPasteboard(_ request: PasteboardCreationRequest) async throws -> PasteboardScope {
        Log.d(TAG, "[createPasteboard] request: \(request)")
        return try useCases.createPasteboard.execute(request)
    }

    // MARK: - P-8 removePasteboard

    public func removePasteboard(_ scope: PasteboardScope, completion: ((Bool, String?, String?) -> Void)? = nil) {
        Log.d(TAG, "[removePasteboard] scope: \(scope)")
        runVoid({ try self.useCases.removePasteboard.execute(scope) }, completion: completion)
    }

    public func removePasteboard(_ scope: PasteboardScope) async throws -> Void {
        Log.d(TAG, "[removePasteboard] scope: \(scope)")
        try useCases.removePasteboard.execute(scope)
    }

    // MARK: - P-9 detectPatterns

    public func detectPatterns(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, Set<ClipboardDetectionPattern>?, String?, String?) -> Void
    ) {
        Log.d(TAG, "[detectPatterns] scope: \(scope), count: \(patterns.count)")
        runValue({ try await self.useCases.detectPatterns.execute(patterns, scope: scope) }, completion: completion)
    }

    public func detectPatterns(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope = .general
    ) async throws -> Set<ClipboardDetectionPattern> {
        Log.d(TAG, "[detectPatterns] scope: \(scope), count: \(patterns.count)")
        return try await useCases.detectPatterns.execute(patterns, scope: scope)
    }

    // MARK: - P-10 detectValues

    public func detectValues(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, ClipboardDetectedValues?, String?, String?) -> Void
    ) {
        Log.d(TAG, "[detectValues] scope: \(scope), count: \(patterns.count)")
        runValue({ try await self.useCases.detectValues.execute(patterns, scope: scope) }, completion: completion)
    }

    public func detectValues(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope = .general
    ) async throws -> ClipboardDetectedValues {
        Log.d(TAG, "[detectValues] scope: \(scope), count: \(patterns.count)")
        return try await useCases.detectValues.execute(patterns, scope: scope)
    }

    // MARK: - P-11 loadItem

    @discardableResult
    public func loadItem(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope = .general,
        completion: @escaping (Bool, ClipboardLoadedItem?, String?, String?) -> Void
    ) -> any ClipboardLoadToken {
        Log.d(TAG, "[loadItem] scope: \(scope)")
        return useCases.loadItem.execute(request, scope: scope) { result in
            switch result {
            case .success(let item):
                completion(true, item, nil, nil)
            case .failure(let error):
                completion(false, nil, error.errorCode, error.errorDescription)
            }
        }
    }

    public func loadItem(_ request: ClipboardLoadRequest, scope: PasteboardScope = .general) async throws -> ClipboardLoadedItem {
        Log.d(TAG, "[loadItem] scope: \(scope)")
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

    // MARK: - P-12 cancelAllLoads (synchronous control)

    public func cancelAllLoads() {
        Log.d(TAG, "[cancelAllLoads]")
        useCases.cancelAllLoads.execute()
    }

    // MARK: - P-13 / P-14 change observation (synchronous control; event delivery is async)

    /// Starts observing clipboard changes for `scope`. A second call (for the same or a
    /// different scope) first stops the previous observation, so there is never more than one
    /// active subscription.
    public func startObserving(scope: PasteboardScope = .general, onEvent: @escaping (ClipboardChangeEvent) -> Void) {
        Log.d(TAG, "[startObserving] scope: \(scope)")
        stopObservingInternal()
        guard let pasteboard = Self.resolvePasteboardForObserving(scope) else {
            Log.e(TAG, "[startObserving] pasteboard unavailable")
            return
        }
        useCases.checkForegroundChange.resync(scope: scope)
        observingScope = scope
        self.onEvent = onEvent

        changedToken = NotificationCenter.default.addObserver(
            forName: UIPasteboard.changedNotification, object: pasteboard, queue: .main
        ) { [weak self] note in
            guard let self, self.observingScope == scope else { return }
            self.useCases.checkForegroundChange.markReported(scope: scope)
            let added = note.userInfo?[UIPasteboard.changedTypesAddedUserInfoKey] as? [String] ?? []
            let removed = note.userInfo?[UIPasteboard.changedTypesRemovedUserInfoKey] as? [String] ?? []
            self.onEvent?(ClipboardChangeEvent(kind: .changed(typesAdded: added, typesRemoved: removed), scope: scope))
        }
        removedToken = NotificationCenter.default.addObserver(
            forName: UIPasteboard.removedNotification, object: pasteboard, queue: .main
        ) { [weak self] _ in
            guard let self, self.observingScope == scope else { return }
            self.onEvent?(ClipboardChangeEvent(kind: .removed, scope: scope))
        }
    }

    public func stopObserving() {
        Log.d(TAG, "[stopObserving]")
        stopObservingInternal()
    }

    private func stopObservingInternal() {
        if let changedToken { NotificationCenter.default.removeObserver(changedToken) }
        if let removedToken { NotificationCenter.default.removeObserver(removedToken) }
        changedToken = nil
        removedToken = nil
        observingScope = nil
        onEvent = nil
    }

    private static func resolvePasteboardForObserving(_ scope: PasteboardScope) -> UIPasteboard? {
        switch scope {
        case .general:
            return .general
        case .named(let name), .unique(let name):
            return UIPasteboard(name: UIPasteboard.Name(name), create: false)
        }
    }

    // MARK: - P-15 checkForegroundChange (synchronous control)

    public func checkForegroundChange(scope: PasteboardScope = .general) -> Bool {
        Log.d(TAG, "[checkForegroundChange] scope: \(scope)")
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
        Log.d(TAG, "[makePasteControl] acceptedTypesCount: \(acceptedTypes.count)")
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
                Log.e(TAG, "[runVoid] errorCode: \(error.errorCode)")
                completion?(false, error.errorCode, error.errorDescription)
            } catch {
                Log.e(TAG, "[runVoid] unknown error")
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
                Log.e(TAG, "[runValue] errorCode: \(error.errorCode)")
                completion(false, nil, error.errorCode, error.errorDescription)
            } catch {
                Log.e(TAG, "[runValue] unknown error")
                completion(false, nil, ClipboardError.unknownErrorCode, ClipboardError.unknownMessage)
            }
        }
    }
}
