//
//  UnityIosClipboardManager.swift
//  UnityIosPlugin
//

import Foundation
import IosLibrary

/// # UnityIosClipboardManager
///
/// Swift façade exposing the Clipboard API to Unity via the Objective-C bridge
/// (`UnityIosClipboardManagerBridge`). Internally hops to `IosClipboardManager` (main actor) and
/// converts its typed `ClipboardError` into `(errorCode, errorMessage)` in exactly one place —
/// this façade never re-derives error codes by parsing messages.
///
/// ## Threading
/// Safe to call from any thread (this is the sole entry point designed for that); all Manager
/// work is dispatched to the main actor internally. Callbacks are always invoked on the main
/// thread.
///
/// Marked `@unchecked Sendable`: this class holds no mutable state (`parser` is an immutable
/// `let`), and every call site hops to the main actor before touching `IosClipboardManager`.
@objcMembers
public class UnityIosClipboardManager: NSObject, @unchecked Sendable {

    private let TAG = "UnityIosClipboardManager"

    /// Shared singleton instance used by the Objective-C bridge.
    public static let shared = UnityIosClipboardManager()

    private let parser = UnityIosClipboardJsonParser()

    private override init() {
        Log.d(TAG, "[init]")
        super.init()
    }

    // MARK: - P-1 copy

    public func copy(requestJson: String?, handler: (@Sendable (Bool, String?, String?) -> Void)?) {
        Log.d(TAG, "[copy] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let requestJson, let dict = parser.parseObject(from: requestJson),
              let scope = parser.parseScope(dict),
              let content = parser.parseContent(dict),
              let maybeOptions = parser.parseOptions(dict)
        else {
            deliverInvalidRequest(handler: handler)
            return
        }
        let options = maybeOptions ?? .default
        Task { @MainActor in
            do {
                try await IosClipboardManager.shared.copy(content, options: options, scope: scope)
                handler?(true, nil, nil)
            } catch let error as ClipboardError {
                handler?(false, error.errorCode, error.errorDescription)
            } catch {
                handler?(false, ClipboardError.unknownErrorCode, ClipboardError.unknownMessage)
            }
        }
    }

    // MARK: - P-2 append

    public func append(requestJson: String?, handler: (@Sendable (Bool, String?, String?) -> Void)?) {
        Log.d(TAG, "[append] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let requestJson, let dict = parser.parseObject(from: requestJson),
              let scope = parser.parseScope(dict),
              let content = parser.parseContent(dict)
        else {
            deliverInvalidRequest(handler: handler)
            return
        }
        guard !parser.containsOptionsKey(dict) else {
            let error = ClipboardError.invalidRequest("append does not accept options")
            deliverOnMain(handler, isSuccess: false, errorCode: error.errorCode, errorMessage: error.errorDescription)
            return
        }
        Task { @MainActor in
            do {
                try await IosClipboardManager.shared.append(content, scope: scope)
                handler?(true, nil, nil)
            } catch let error as ClipboardError {
                handler?(false, error.errorCode, error.errorDescription)
            } catch {
                handler?(false, ClipboardError.unknownErrorCode, ClipboardError.unknownMessage)
            }
        }
    }

    // MARK: - P-3 read

    public func read(requestJson: String?, handler: (@Sendable (String) -> Void)?) {
        Log.d(TAG, "[read] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let scope = parser.parseScope(dict) else {
            deliverOnMain(handler, json: invalidRequestJSON())
            return
        }
        Task { @MainActor in
            do {
                let result = try await IosClipboardManager.shared.read(scope: scope)
                self.handler(handler, success: self.parser.serializeReadResult(result))
            } catch {
                self.handler(handler, failure: error)
            }
        }
    }

    // MARK: - P-4 readData

    public func readData(requestJson: String?, handler: (@Sendable (String) -> Void)?) {
        Log.d(TAG, "[readData] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let scope = parser.parseScope(dict),
              let utType = parser.parseUTType(dict)
        else {
            deliverOnMain(handler, json: invalidRequestJSON())
            return
        }
        Task { @MainActor in
            do {
                let data = try await IosClipboardManager.shared.readData(utType: utType, scope: scope)
                self.handler(handler, success: self.parser.serializeReadData(utType: utType, data: data))
            } catch {
                self.handler(handler, failure: error)
            }
        }
    }

    // MARK: - P-5 getSnapshot

    public func getSnapshot(requestJson: String?, handler: (@Sendable (String) -> Void)?) {
        Log.d(TAG, "[getSnapshot] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let scope = parser.parseScope(dict),
              let maybeMatchingTypes = parser.parseMatchingTypes(dict)
        else {
            deliverOnMain(handler, json: invalidRequestJSON())
            return
        }
        Task { @MainActor in
            do {
                let snapshot = try await IosClipboardManager.shared.snapshot(matchingTypes: maybeMatchingTypes, scope: scope)
                self.handler(handler, success: self.parser.serializeSnapshot(snapshot))
            } catch {
                self.handler(handler, failure: error)
            }
        }
    }

    // MARK: - P-6 clear

    public func clear(requestJson: String?, handler: (@Sendable (Bool, String?, String?) -> Void)?) {
        Log.d(TAG, "[clear] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let scope = parser.parseScope(dict) else {
            deliverInvalidRequest(handler: handler)
            return
        }
        Task { @MainActor in
            do {
                try await IosClipboardManager.shared.clear(scope: scope)
                handler?(true, nil, nil)
            } catch let error as ClipboardError {
                handler?(false, error.errorCode, error.errorDescription)
            } catch {
                handler?(false, ClipboardError.unknownErrorCode, ClipboardError.unknownMessage)
            }
        }
    }

    // MARK: - P-7 createPasteboard

    public func createPasteboard(requestJson: String?, handler: (@Sendable (String) -> Void)?) {
        Log.d(TAG, "[createPasteboard] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let request = parser.parseCreationRequest(dict) else {
            deliverOnMain(handler, json: invalidRequestJSON())
            return
        }
        Task { @MainActor in
            do {
                let scope = try await IosClipboardManager.shared.createPasteboard(request)
                self.handler(handler, success: ["scope": self.parser.serializeScope(scope)])
            } catch {
                self.handler(handler, failure: error)
            }
        }
    }

    // MARK: - P-8 removePasteboard

    public func removePasteboard(requestJson: String?, handler: (@Sendable (Bool, String?, String?) -> Void)?) {
        Log.d(TAG, "[removePasteboard] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let scope = parser.parseScope(dict) else {
            deliverInvalidRequest(handler: handler)
            return
        }
        Task { @MainActor in
            do {
                try await IosClipboardManager.shared.removePasteboard(scope)
                handler?(true, nil, nil)
            } catch let error as ClipboardError {
                handler?(false, error.errorCode, error.errorDescription)
            } catch {
                handler?(false, ClipboardError.unknownErrorCode, ClipboardError.unknownMessage)
            }
        }
    }

    // MARK: - P-9 detectPatterns

    public func detectPatterns(requestJson: String?, handler: (@Sendable (String) -> Void)?) {
        Log.d(TAG, "[detectPatterns] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let scope = parser.parseScope(dict),
              let patterns = parser.parsePatterns(dict)
        else {
            deliverOnMain(handler, json: invalidRequestJSON())
            return
        }
        Task { @MainActor in
            do {
                let detected = try await IosClipboardManager.shared.detectPatterns(patterns, scope: scope)
                self.handler(handler, success: self.parser.serializePatterns(detected))
            } catch {
                self.handler(handler, failure: error)
            }
        }
    }

    // MARK: - P-10 detectValues

    public func detectValues(requestJson: String?, handler: (@Sendable (String) -> Void)?) {
        Log.d(TAG, "[detectValues] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let scope = parser.parseScope(dict),
              let patterns = parser.parsePatterns(dict)
        else {
            deliverOnMain(handler, json: invalidRequestJSON())
            return
        }
        Task { @MainActor in
            do {
                let values = try await IosClipboardManager.shared.detectValues(patterns, scope: scope)
                self.handler(handler, success: self.parser.serializeDetectedValues(values))
            } catch {
                self.handler(handler, failure: error)
            }
        }
    }

    // MARK: - P-11 loadItem

    public func loadItem(requestJson: String?, handler: (@Sendable (String) -> Void)?) {
        Log.d(TAG, "[loadItem] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let scope = parser.parseScope(dict),
              let loadRequest = parser.parseLoadRequest(dict)
        else {
            deliverOnMain(handler, json: invalidRequestJSON())
            return
        }
        Task { @MainActor in
            do {
                let item = try await IosClipboardManager.shared.loadItem(loadRequest, scope: scope)
                self.handler(handler, success: self.parser.serializeLoadedItem(item))
            } catch {
                self.handler(handler, failure: error)
            }
        }
    }

    // MARK: - P-12 cancelLoads

    public func cancelLoads(handler: (@Sendable (Bool, String?, String?) -> Void)?) {
        Log.d(TAG, "[cancelLoads]")
        Task { @MainActor in
            IosClipboardManager.shared.cancelAllLoads()
            handler?(true, nil, nil)
        }
    }

    // MARK: - P-13 / P-14 observing

    public func startObserving(
        requestJson: String?,
        changeHandler: (@Sendable (String) -> Void)?,
        startHandler: (@Sendable (Bool, String?, String?) -> Void)?
    ) {
        Log.d(TAG, "[startObserving] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let scope = parser.parseScope(dict) else {
            deliverInvalidRequest(handler: startHandler)
            return
        }
        Task { @MainActor in
            do {
                try IosClipboardManager.shared.startObserving(scope: scope) { [parser] event in
                    changeHandler?(parser.serializeChangeEvent(event))
                }
                startHandler?(true, nil, nil)
            } catch let error as ClipboardError {
                startHandler?(false, error.errorCode, error.errorDescription)
            } catch {
                startHandler?(false, ClipboardError.unknownErrorCode, ClipboardError.unknownMessage)
            }
        }
    }

    public func stopObserving(handler: (@Sendable (Bool, String?, String?) -> Void)?) {
        Log.d(TAG, "[stopObserving]")
        Task { @MainActor in
            IosClipboardManager.shared.stopObserving()
            handler?(true, nil, nil)
        }
    }

    // MARK: - P-15 checkForegroundChange

    public func checkForegroundChange(requestJson: String?, handler: (@Sendable (String) -> Void)?) {
        Log.d(TAG, "[checkForegroundChange] requestJson: \(ClipboardRedaction.json(requestJson ?? ""))")
        guard let dict = parser.parseObject(from: requestJson), let scope = parser.parseScope(dict) else {
            deliverOnMain(handler, json: invalidRequestJSON())
            return
        }
        Task { @MainActor in
            let changed = IosClipboardManager.shared.checkForegroundChange(scope: scope)
            self.handler(handler, success: ["changed": changed])
        }
    }

    // MARK: - Private

    private func handler(_ handler: (@Sendable (String) -> Void)?, success data: Any) {
        handler?(parser.serializeSuccess(data))
    }

    private func handler(_ handler: (@Sendable (String) -> Void)?, failure error: Error) {
        if let clipboardError = error as? ClipboardError {
            Log.e(TAG, "[handler] errorCode: \(clipboardError.errorCode)")
            handler?(parser.serializeError(
                code: clipboardError.errorCode,
                message: clipboardError.errorDescription ?? ClipboardError.unknownMessage,
                detail: clipboardError.diagnosticDetail
            ))
        } else {
            Log.e(TAG, "[handler] unknown error")
            handler?(parser.serializeError(code: ClipboardError.unknownErrorCode, message: ClipboardError.unknownMessage))
        }
    }

    /// Delivers an operation callback from the main actor.
    ///
    /// Unity may call any endpoint from any thread. Early failures (parse/validation) return
    /// before the main-actor hop, so invoking the handler inline would hand it back on the
    /// **caller's** thread and break the documented "callbacks are always invoked on the main
    /// thread" contract. Every callback therefore goes through this helper or an enclosing
    /// `Task { @MainActor in }`.
    ///
    /// Note that `@Sendable` on the handler makes it *safe to transfer* between isolation
    /// domains — it does not by itself pin execution to the main actor. That is this helper's job.
    private func deliverOnMain(
        _ handler: (@Sendable (Bool, String?, String?) -> Void)?,
        isSuccess: Bool,
        errorCode: String?,
        errorMessage: String?
    ) {
        Task { @MainActor in handler?(isSuccess, errorCode, errorMessage) }
    }

    /// Delivers a JSON callback from the main actor. See ``deliverOnMain(_:isSuccess:errorCode:errorMessage:)``.
    /// The payload is serialized by the caller so only a `String` crosses the isolation boundary.
    private func deliverOnMain(_ handler: (@Sendable (String) -> Void)?, json: String) {
        Task { @MainActor in handler?(json) }
    }

    private func deliverInvalidRequest(handler: (@Sendable (Bool, String?, String?) -> Void)?) {
        let error = ClipboardError.invalidRequest("malformed request")
        deliverOnMain(handler, isSuccess: false, errorCode: error.errorCode, errorMessage: error.errorDescription)
    }

    private func invalidRequestJSON() -> String {
        let error = ClipboardError.invalidRequest("malformed request")
        return parser.serializeError(code: error.errorCode, message: error.errorDescription ?? "")
    }
}
