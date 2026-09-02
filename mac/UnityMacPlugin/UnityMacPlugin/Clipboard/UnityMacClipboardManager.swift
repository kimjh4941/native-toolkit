//
//  UnityMacClipboardManager.swift
//  UnityMacPlugin
//

import Foundation
import MacLibrary

/// Swift façade exposing the clipboard API to Unity through the Objective-C bridge.
///
/// ## Threading
/// Callable from any thread. `MacClipboardManager` is main actor isolated, so every operation
/// hops internally and **every handler is invoked on the main thread**, on every path
/// including a malformed JSON argument.
///
/// ## Handler types
/// Handler parameters are `@Sendable`. The façade is `nonisolated` and passes handlers into
/// `Task { @MainActor }`, which without the annotation is a strict-concurrency violation. The
/// blocks the Objective-C bridge passes capture nothing but C function pointers, so the
/// annotation states a fact rather than papering over one (`MIGRATION.md` section 6, plan C).
/// `@Sendable` says a closure can be moved safely; it does not pin where it runs, so main
/// thread delivery is guaranteed separately by routing every path through the hop below.
///
/// ## Error contract
/// Error codes and messages come from `MacClipboardManager`'s callback form unchanged. Only
/// bridge-level failures — malformed JSON, a missing required argument — use `BridgeError`
/// here. Nothing is translated twice.
///
/// The type holds no mutable state: its only stored property is a stateless value-type parser.
/// That is what lets it be reached from any thread safely, and it is asserted rather than
/// inferred because `NSObject` subclasses never get `Sendable` automatically.
@objcMembers
public final class UnityMacClipboardManager: NSObject, @unchecked Sendable {

    private let TAG = "UnityMacClipboardManager"

    /// Shared singleton used by the Objective-C bridge.
    public static let shared = UnityMacClipboardManager()

    private let parser = UnityMacClipboardJsonParser()

    private override init() {
        Log.d("UnityMacClipboardManager", "[init]")
        super.init()
    }

    // MARK: - Delivery helpers

    /// Runs `body` on the main actor and reports its result through `handler`.
    ///
    /// The single delivery path for value-returning operations, so no early return can escape
    /// the main-thread guarantee.
    private func run<T>(_ handler: (@Sendable (Bool, String?, Int, String?) -> Void)?,
                        encode: @escaping @Sendable (T) -> String?,
                        body: @escaping @Sendable @MainActor (
                            @escaping @MainActor (Bool, T?, Int, String?) -> Void) -> Void) {
        Task { @MainActor in
            body { isSuccess, value, errorCode, errorMessage in
                guard isSuccess, let value else {
                    handler?(false, nil, errorCode, errorMessage)
                    return
                }
                guard let json = encode(value) else {
                    // A NULL payload alongside isSuccess=YES is indistinguishable from
                    // readData's legitimate `{"data":null}`, so Unity would read through it
                    // as a success (R11-L6).
                    Log.e("UnityMacClipboardManager", "[run] the result could not be encoded")
                    let failure = ClipboardError.unknown("The result could not be encoded.")
                    handler?(false, nil, failure.errorCode, failure.errorMessage)
                    return
                }
                handler?(true, json, 0, nil)
            }
        }
    }

    /// Reports a bridge-level failure without reaching the manager.
    /// Classifies a failed argument.
    ///
    /// §8.4.1 separates the two cases: a missing required argument is a contract violation
    /// (1302), a malformed one is a parse failure (1301). Reporting both as 1301 told Unity
    /// that the JSON it sent was bad when it had sent nothing at all (R11-H3).
    private func argumentError(_ raw: String?) -> BridgeError {
        guard let raw, !raw.isEmpty else {
            return .contractViolation(reason: "A required argument was missing.")
        }
        return .parseFailed(reason: "Invalid clipboard JSON argument.")
    }

    private func fail(_ handler: (@Sendable (Bool, String?, Int, String?) -> Void)?,
                      _ error: BridgeError) {
        Log.e(TAG, "[fail] code: \(error.errorCode)")
        Task { @MainActor in
            handler?(false, nil, error.errorCode, error.errorMessage)
        }
    }

    private func failVoid(_ handler: (@Sendable (Bool, Int, String?) -> Void)?,
                          _ error: BridgeError) {
        Log.e(TAG, "[failVoid] code: \(error.errorCode)")
        Task { @MainActor in
            handler?(false, error.errorCode, error.errorMessage)
        }
    }

    // MARK: - OP-01 copy

    /// Writes content to a pasteboard. Reports `OwnershipJson`.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func copy(contentJson: String?,
                     optionsJson: String?,
                     scopeJson: String?,
                     handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[copy] content length: \(contentJson?.count ?? 0), scope: \(ClipboardLog.scopeJson(scopeJson))")
        guard let content = parser.parseContent(contentJson) else {
            return fail(handler, argumentError(contentJson))
        }
        guard let scope = parser.parseScope(scopeJson) else {
            return fail(handler, argumentError(scopeJson))
        }
        // A malformed options payload is a caller bug, not a request for the defaults.
        guard let options = parser.parseOptions(optionsJson) else {
            return fail(handler, argumentError(optionsJson))
        }
        let parser = self.parser
        run(handler, encode: { parser.encodeOwnership($0) }) { completion in
            MacClipboardManager.shared.copy(content, options: options, scope: scope,
                                            completion: completion)
        }
    }

    // MARK: - OP-02 append

    /// Appends to a pasteboard this app still owns. Reports `OwnershipJson`.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func append(contentJson: String?,
                       ownershipJson: String?,
                       handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[append] content length: \(contentJson?.count ?? 0)")
        guard let content = parser.parseContent(contentJson) else {
            return fail(handler, argumentError(contentJson))
        }
        guard let ownership = parser.parseOwnership(ownershipJson) else {
            return fail(handler, argumentError(ownershipJson))
        }
        let parser = self.parser
        run(handler, encode: { parser.encodeOwnership($0) }) { completion in
            MacClipboardManager.shared.append(content, ownership: ownership, completion: completion)
        }
    }

    // MARK: - OP-03 read

    /// Reads every item of a pasteboard. Reports `ReadResultJson`.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func read(scopeJson: String?,
                     handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[read] scope: \(ClipboardLog.scopeJson(scopeJson))")
        guard let scope = parser.parseScope(scopeJson) else { return fail(handler, argumentError(scopeJson)) }
        let parser = self.parser
        run(handler, encode: { parser.encodeReadResult($0) }) { completion in
            MacClipboardManager.shared.read(scope: scope, completion: completion)
        }
    }

    // MARK: - OP-04 readData

    /// Reads one representation. Reports `ReadDataJson`, whose payload is null when the type is absent.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func readData(utType: String?,
                         scopeJson: String?,
                         handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[readData] utType: \(utType ?? "nil")")
        guard let utType, !utType.isEmpty else { return fail(handler, .contractViolation(reason: "A required argument was missing.")) }
        guard let scope = parser.parseScope(scopeJson) else { return fail(handler, argumentError(scopeJson)) }
        let parser = self.parser
        // A missing type is success with a null payload, so the encoder takes an optional and
        // the delivery path must not treat nil as failure.
        Task { @MainActor in
            MacClipboardManager.shared.readData(utType: utType, scope: scope) { isSuccess, data, code, message in
                guard isSuccess else {
                    handler?(false, nil, code, message)
                    return
                }
                guard let json = parser.encodeData(data) else {
                    Log.e("UnityMacClipboardManager", "[encode] the result could not be encoded")
                    let failure = ClipboardError.unknown("The result could not be encoded.")
                    handler?(false, nil, failure.errorCode, failure.errorMessage)
                    return
                }
                handler?(true, json, 0, nil)
            }
        }
    }

    // MARK: - OP-05 snapshot

    /// Describes a pasteboard without reading its payload. Reports `SnapshotJson`.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func snapshot(matchingTypesJson: String?,
                         scopeJson: String?,
                         handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[snapshot] matchingTypes: \(ClipboardLog.json(matchingTypesJson))")
        guard let scope = parser.parseScope(scopeJson) else { return fail(handler, argumentError(scopeJson)) }
        guard let matchingTypes = parser.parseMatchingTypes(matchingTypesJson) else {
            return fail(handler, argumentError(matchingTypesJson))
        }
        let parser = self.parser
        run(handler, encode: { parser.encodeSnapshot($0) }) { completion in
            MacClipboardManager.shared.snapshot(matchingTypes: matchingTypes, scope: scope,
                                                completion: completion)
        }
    }

    // MARK: - OP-06 clear

    /// Empties a pasteboard. Reports `ChangeCountJson`.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func clear(scopeJson: String?,
                      handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[clear] scope: \(ClipboardLog.scopeJson(scopeJson))")
        guard let scope = parser.parseScope(scopeJson) else { return fail(handler, argumentError(scopeJson)) }
        let parser = self.parser
        run(handler, encode: { parser.encodeChangeCount($0) }) { completion in
            MacClipboardManager.shared.clear(scope: scope, completion: completion)
        }
    }

    // MARK: - OP-07 createPasteboard

    /// Creates or fetches a pasteboard. Reports `ScopeResultJson`.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func createPasteboard(requestJson: String?,
                                 handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[createPasteboard] request: \(ClipboardLog.json(requestJson))")
        // A caller that cannot receive the scope cannot release the pasteboard it just made,
        // so the handler is required here (R3-M4 / R4-M6).
        guard let handler else {
            Log.e(TAG, "[createPasteboard] handler is required")
            return
        }
        guard let request = parser.parseCreateRequest(requestJson) else {
            return fail(handler, argumentError(requestJson))
        }
        let parser = self.parser
        run(handler, encode: { parser.encodeScope($0) }) { completion in
            MacClipboardManager.shared.createPasteboard(request, completion: completion)
        }
    }

    // MARK: - OP-08 removePasteboard

    /// Releases a pasteboard created by this app. Standard pasteboards are refused.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func removePasteboard(scopeJson: String?,
                                 handler: (@Sendable (Bool, Int, String?) -> Void)?) {
        Log.d(TAG, "[removePasteboard] scope: \(ClipboardLog.scopeJson(scopeJson))")
        guard let scope = parser.parseScope(scopeJson) else {
            return failVoid(handler, argumentError(scopeJson))
        }
        Task { @MainActor in
            MacClipboardManager.shared.removePasteboard(scope, completion: handler)
        }
    }

    // MARK: - OP-09 detectPatterns

    /// Reports which patterns the pasteboard contains, without reading values.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func detectPatterns(patternsJson: String?,
                               scopeJson: String?,
                               handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[detectPatterns] patterns: \(ClipboardLog.json(patternsJson))")
        guard let patterns = parser.parsePatterns(patternsJson),
              let scope = parser.parseScope(scopeJson) else {
            return fail(handler, argumentError(scopeJson))
        }
        let parser = self.parser
        run(handler, encode: { parser.encodePatterns($0) }) { completion in
            MacClipboardManager.shared.detectPatterns(patterns, scope: scope, completion: completion)
        }
    }

    // MARK: - OP-10 detectValues

    /// Reports the detected values themselves. Requires macOS 15.4 or later.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func detectValues(patternsJson: String?,
                             scopeJson: String?,
                             handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[detectValues] patterns: \(ClipboardLog.json(patternsJson))")
        guard let patterns = parser.parsePatterns(patternsJson),
              let scope = parser.parseScope(scopeJson) else {
            return fail(handler, argumentError(scopeJson))
        }
        let parser = self.parser
        run(handler, encode: { parser.encodeDetectedValues($0) }) { completion in
            MacClipboardManager.shared.detectValues(patterns, scope: scope, completion: completion)
        }
    }

    // MARK: - OP-11 detectMetadata

    /// Reports the pasteboard's metadata. Fails for content the system cannot describe.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func detectMetadata(scopeJson: String?,
                               handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[detectMetadata] scope: \(ClipboardLog.scopeJson(scopeJson))")
        guard let scope = parser.parseScope(scopeJson) else { return fail(handler, argumentError(scopeJson)) }
        let parser = self.parser
        run(handler, encode: { parser.encodeDetectedMetadata($0) }) { completion in
            MacClipboardManager.shared.detectMetadata(scope: scope, completion: completion)
        }
    }

    // MARK: - OP-12 accessBehavior

    /// Reports whether reading would prompt the person using the app.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func accessBehavior(scopeJson: String?,
                               handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[accessBehavior] scope: \(ClipboardLog.scopeJson(scopeJson))")
        guard let scope = parser.parseScope(scopeJson) else { return fail(handler, argumentError(scopeJson)) }
        let parser = self.parser
        // Synchronous natively, but the bridge reports through a callback: an arbitrary-thread
        // C function cannot return a value that only exists on the main actor (H-7).
        Task { @MainActor in
            do {
                let behavior = try MacClipboardManager.shared.accessBehavior(scope: scope)
                guard let json = parser.encodeAccessBehavior(behavior) else {
                    Log.e("UnityMacClipboardManager", "[encode] the result could not be encoded")
                    let failure = ClipboardError.unknown("The result could not be encoded.")
                    handler?(false, nil, failure.errorCode, failure.errorMessage)
                    return
                }
                handler?(true, json, 0, nil)
            } catch let error as ClipboardError {
                handler?(false, nil, error.errorCode, error.errorMessage)
            } catch {
                let wrapped = ClipboardError.unknown(String(describing: error))
                handler?(false, nil, wrapped.errorCode, wrapped.errorMessage)
            }
        }
    }
}

// MARK: - Observation and foreground

extension UnityMacClipboardManager {

    // MARK: OP-13 startObserving

    /// - Parameter onChange: Required. A session whose events cannot be delivered would be
    ///   invisible to the caller, so a null event callback is rejected with 1302 (R5-M8).
    public func startObserving(scopeJson: String?,
                               intervalSeconds: Double,
                               onChange: (@Sendable (String) -> Void)?,
                               handler: (@Sendable (Bool, Int, String?) -> Void)?) {
        Log.d(TAG, "[startObserving] scope: \(ClipboardLog.scopeJson(scopeJson)), interval: \(intervalSeconds)")
        guard let onChange else {
            return failVoid(handler, .contractViolation(
                reason: "onChange is required; observation would produce no observable result."))
        }
        guard let scope = parser.parseScope(scopeJson) else {
            return failVoid(handler, argumentError(scopeJson))
        }
        let parser = self.parser
        Task { @MainActor in
            do {
                try MacClipboardManager.shared.startObserving(scope: scope,
                                                              interval: intervalSeconds) { event in
                    guard let json = parser.encodeChangeEvent(event) else { return }
                    onChange(json)
                }
                handler?(true, 0, nil)
            } catch let error as ClipboardError {
                handler?(false, error.errorCode, error.errorMessage)
            } catch {
                let wrapped = ClipboardError.unknown(String(describing: error))
                handler?(false, wrapped.errorCode, wrapped.errorMessage)
            }
        }
    }

    // MARK: OP-14 stopObserving

    /// Stops change observation. Idempotent.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func stopObserving(handler: (@Sendable (Bool, Int, String?) -> Void)?) {
        Log.d(TAG, "[stopObserving]")
        Task { @MainActor in
            MacClipboardManager.shared.stopObserving()
            handler?(true, 0, nil)
        }
    }

    // MARK: OP-15 checkForegroundChange

    /// Reports whether the pasteboard changed since this app last looked.
    ///
    /// `handler` runs exactly once, including on an early failure. Passing `nil` performs
    /// the operation without reporting the result.
    public func checkForegroundChange(scopeJson: String?,
                                      handler: (@Sendable (Bool, String?, Int, String?) -> Void)?) {
        Log.d(TAG, "[checkForegroundChange] scope: \(ClipboardLog.scopeJson(scopeJson))")
        guard let scope = parser.parseScope(scopeJson) else {
            return fail(handler, argumentError(scopeJson))
        }
        let parser = self.parser
        Task { @MainActor in
            do {
                let changed = try MacClipboardManager.shared.checkForegroundChange(scope: scope)
                guard let json = parser.encodeBool(changed) else {
                    Log.e("UnityMacClipboardManager", "[encode] the result could not be encoded")
                    let failure = ClipboardError.unknown("The result could not be encoded.")
                    handler?(false, nil, failure.errorCode, failure.errorMessage)
                    return
                }
                handler?(true, json, 0, nil)
            } catch let error as ClipboardError {
                handler?(false, nil, error.errorCode, error.errorMessage)
            } catch {
                let wrapped = ClipboardError.unknown(String(describing: error))
                handler?(false, nil, wrapped.errorCode, wrapped.errorMessage)
            }
        }
    }
}
