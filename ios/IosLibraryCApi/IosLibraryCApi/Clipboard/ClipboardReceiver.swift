//
//  ClipboardReceiver.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary

/// What the functions of Clipboard.h do (part 2, 5.1, 5.2): the entry's checks and copies in
/// `ClipboardMapping`, the accepted request to the main thread, the call of the manager, the handle and
/// the completion.
enum ClipboardReceiver {
    /// A load closes its box through the manager, from any thread (part 2, 5.3; OP-12, P2-12).
    static let loadCancelKind = CancellableKind(name: "clipboardLoad") { IosClipboardManager.cancelLoad($0) }

    /// How a completion of one callback type carries an error, with no value: a handle is NULL and a value 0.
    /// The id is the request's; only a load's callback takes it.
    private typealias Failure<Callback> = @MainActor @Sendable (Callback, UnsafeMutableRawPointer?, UInt64, ntk_clipboard_error) -> Void

    private static let none = ntk_clipboard_error(NTK_CLIPBOARD_ERROR_NONE)
    private static let systemCode: UInt32 = 0

    private static let doneFailure: Failure<ntk_clipboard_done_fn> = { callback, userData, _, error in callback(userData, error, systemCode) }
    private static let readFailure: Failure<ntk_clipboard_read_fn> = { callback, userData, _, error in callback(userData, error, systemCode, nil) }
    private static let dataFailure: Failure<ntk_clipboard_data_fn> = { callback, userData, _, error in callback(userData, error, systemCode, nil) }
    private static let snapshotFailure: Failure<ntk_clipboard_snapshot_fn> = { callback, userData, _, error in callback(userData, error, systemCode, nil) }
    private static let nameFailure: Failure<ntk_clipboard_name_fn> = { callback, userData, _, error in callback(userData, error, systemCode, nil) }
    private static let patternsFailure: Failure<ntk_clipboard_patterns_fn> = { callback, userData, _, error in callback(userData, error, systemCode, 0) }
    private static let valuesFailure: Failure<ntk_clipboard_values_fn> = { callback, userData, _, error in callback(userData, error, systemCode, nil) }
    private static let foregroundFailure: Failure<ntk_clipboard_foreground_change_fn> = { callback, userData, _, error in callback(userData, error, systemCode, 0) }
    private static let loadFailure: Failure<ntk_clipboard_load_fn> = { callback, userData, id, error in callback(userData, id, error, systemCode, nil) }

    /// The ledger of the change listeners. Nothing is held for a later registration (part 2, 5.4), and each
    /// registration gets a handle of its own.
    static let changeLedger = EventLedger<ClipboardChange, ntk_clipboard_change_fn>(holdLimit: 0) { callback, userData, change in
        callback(userData, ClipboardHandles.makeChange(change))
    }

    /// An event from the library. One the C ABI cannot say is logged where it is mapped, and goes nowhere.
    @MainActor
    static func receive(_ event: ClipboardChangeEvent) {
        CApiLog.clipboard.debug("[receive] event: provided")
        guard let change = ClipboardMapping.change(of: event) else { return }
        changeLedger.receive(change)
    }

    // MARK: - Accepting

    /// Steps 2 to 7 of acceptance (part 1, 5.7): a NULL callback and what `input` throws are rejected, with
    /// `release` on this thread. What `input` returns holds no pointer of the caller.
    private static func accept<Input: Sendable, Callback>(
        _ callback: Callback?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
        failure: @escaping Failure<Callback>, cancellable: CancellableKind? = nil,
        outRequestID: UnsafeMutablePointer<UInt64>? = nil, function: String = #function,
        input: () throws(ClipboardRejection) -> Input,
        start: @escaping @MainActor @Sendable (Input, Registration<Callback>) -> Void
    ) -> ntk_clipboard_error {
        guard let callback else {
            CApiLog.clipboard.error("[accept] \(function, privacy: .public): the callback is NULL")
            return Entry.reject(.invalidParameter, userData: userData, release: release, function: function)
        }
        do throws(ClipboardRejection) {
            let value = try input()
            return Registry.accept(callback: callback, userData: userData, release: release, cancellable: cancellable,
                                   canceled: { callback, userData, id in failure(callback, userData, id, ntk_clipboard_error(NTK_CLIPBOARD_ERROR_CANCELED)) },
                                   outRequestID: outRequestID, start: { start(value, $0) })
        } catch {
            return Entry.reject(error.value, userData: userData, release: release, function: function)
        }
    }

    /// What the callback forms of the manager report: a value, or an `errorCode` (P2-13). The handle is made in
    /// `deliver`, so that one that nobody would receive is not made.
    @MainActor
    private static func finish<Value, Callback>(
        _ registration: Registration<Callback>, succeeded: Bool, value: Value?, errorCode: String?,
        failure: @escaping Failure<Callback>, function: String = #function,
        deliver: @MainActor (Callback, UnsafeMutableRawPointer?, Value) -> Void
    ) {
        CApiLog.clipboard.debug("[finish] function: \(function, privacy: .public), succeeded: \(succeeded, privacy: .public), errorCode: \(errorCode ?? "nil", privacy: .public)")
        guard succeeded, let value else {
            let error = ClipboardMapping.error(forCode: errorCode)
            CApiLog.clipboard.error("[finish] function: \(function, privacy: .public), error: \(error, privacy: .public), errorCode: \(errorCode ?? "nil", privacy: .public)")
            registration.complete { callback, userData, id in failure(callback, userData, id, error) }
            return
        }
        registration.complete { callback, userData, _ in deliver(callback, userData, value) }
    }

    /// `finish` for an operation that gives no value.
    @MainActor
    private static func finishDone(_ registration: Registration<ntk_clipboard_done_fn>, succeeded: Bool, errorCode: String?,
                                   function: String = #function) {
        finish(registration, succeeded: succeeded, value: succeeded ? () : nil, errorCode: errorCode,
               failure: doneFailure, function: function) { callback, userData, _ in
            callback(userData, none, systemCode)
        }
    }

    // MARK: - OP-01, OP-02

    static func copy(_ content: UnsafePointer<ntk_clipboard_write_content>?, _ options: UnsafePointer<ntk_clipboard_copy_options>?,
                     _ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_done_fn?,
                     _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[copy] content: \(content == nil ? "nil" : "provided", privacy: .public), options: \(options == nil ? "nil" : "provided", privacy: .public), scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(ClipboardRejection) in
            (try ClipboardMapping.content(content), try ClipboardMapping.options(options), try ClipboardMapping.scope(scope))
        }, start: { input, registration in
            IosClipboardManager.shared.copy(input.0, options: input.1, scope: input.2) { succeeded, errorCode, _ in
                finishDone(registration, succeeded: succeeded, errorCode: errorCode)
            }
        })
    }

    static func append(_ content: UnsafePointer<ntk_clipboard_write_content>?, _ scope: UnsafePointer<ntk_clipboard_scope>?,
                       _ callback: ntk_clipboard_done_fn?, _ userData: UnsafeMutableRawPointer?,
                       _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[append] content: \(content == nil ? "nil" : "provided", privacy: .public), scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(ClipboardRejection) in
            (try ClipboardMapping.content(content), try ClipboardMapping.scope(scope))
        }, start: { input, registration in
            IosClipboardManager.shared.append(input.0, scope: input.1) { succeeded, errorCode, _ in
                finishDone(registration, succeeded: succeeded, errorCode: errorCode)
            }
        })
    }

    // MARK: - OP-03, OP-04, OP-05

    static func read(_ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_read_fn?,
                     _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[read] scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: readFailure, input: { () throws(ClipboardRejection) in
            try ClipboardMapping.scope(scope)
        }, start: { scope, registration in
            IosClipboardManager.shared.read(scope: scope) { succeeded, result, errorCode, _ in
                finish(registration, succeeded: succeeded, value: result, errorCode: errorCode, failure: readFailure) { callback, userData, result in
                    callback(userData, none, systemCode, ClipboardHandles.makeReadResult(result))
                }
            }
        })
    }

    static func readData(_ utType: UnsafePointer<CChar>?, _ scope: UnsafePointer<ntk_clipboard_scope>?,
                         _ callback: ntk_clipboard_data_fn?, _ userData: UnsafeMutableRawPointer?,
                         _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[readData] utType: \(utType == nil ? "nil" : "provided", privacy: .public), scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: dataFailure, input: { () throws(ClipboardRejection) in
            (try ClipboardMapping.utType(utType), try ClipboardMapping.scope(scope))
        }, start: { input, registration in
            IosClipboardManager.shared.readData(utType: input.0, scope: input.1) { succeeded, data, errorCode, _ in
                // Success with no data is a value here: NULL, with NONE (no item of the type, or a denied paste).
                finish(registration, succeeded: succeeded, value: succeeded ? .some(data) : nil, errorCode: errorCode, failure: dataFailure) { callback, userData, data in
                    callback(userData, none, systemCode, data.map { Handle.makeBytes($0) })
                }
            }
        })
    }

    static func snapshot(_ matchingTypes: UnsafePointer<UnsafePointer<CChar>?>?, _ matchingTypeCount: Int,
                         _ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_snapshot_fn?,
                         _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[snapshot] matchingTypes: \(matchingTypes == nil ? "nil" : "provided", privacy: .public), matchingTypeCount: \(matchingTypeCount, privacy: .public), scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: snapshotFailure, input: { () throws(ClipboardRejection) in
            (try ClipboardMapping.matchingTypes(matchingTypes, count: matchingTypeCount), try ClipboardMapping.scope(scope))
        }, start: { input, registration in
            IosClipboardManager.shared.snapshot(matchingTypes: input.0, scope: input.1) { succeeded, snapshot, errorCode, _ in
                finish(registration, succeeded: succeeded, value: snapshot, errorCode: errorCode, failure: snapshotFailure) { callback, userData, snapshot in
                    callback(userData, none, systemCode, ClipboardHandles.makeSnapshot(snapshot))
                }
            }
        })
    }

    // MARK: - OP-06, OP-07, OP-08

    static func clear(_ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_done_fn?,
                      _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[clear] scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(ClipboardRejection) in
            try ClipboardMapping.scope(scope)
        }, start: { scope, registration in
            IosClipboardManager.shared.clear(scope: scope) { succeeded, errorCode, _ in
                finishDone(registration, succeeded: succeeded, errorCode: errorCode)
            }
        })
    }

    static func createPasteboard(_ kind: ntk_clipboard_scope_kind, _ name: UnsafePointer<CChar>?, _ callback: ntk_clipboard_name_fn?,
                                 _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[createPasteboard] kind: \(kind, privacy: .public), name: \(name == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: nameFailure, input: { () throws(ClipboardRejection) in
            try ClipboardMapping.creationRequest(kind: kind, name: name)
        }, start: { request, registration in
            IosClipboardManager.shared.createPasteboard(request) { succeeded, scope, errorCode, _ in
                finish(registration, succeeded: succeeded, value: scope.flatMap(ClipboardMapping.name), errorCode: errorCode, failure: nameFailure) { callback, userData, name in
                    callback(userData, none, systemCode, Handle.makeString(name))
                }
            }
        })
    }

    static func removePasteboard(_ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_done_fn?,
                                 _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[removePasteboard] scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(ClipboardRejection) in
            try ClipboardMapping.requiredScope(scope)
        }, start: { scope, registration in
            IosClipboardManager.shared.removePasteboard(scope) { succeeded, errorCode, _ in
                finishDone(registration, succeeded: succeeded, errorCode: errorCode)
            }
        })
    }

    // MARK: - OP-09, OP-10

    static func detectPatterns(_ patterns: ntk_clipboard_patterns, _ scope: UnsafePointer<ntk_clipboard_scope>?,
                               _ callback: ntk_clipboard_patterns_fn?, _ userData: UnsafeMutableRawPointer?,
                               _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[detectPatterns] patterns: \(patterns, privacy: .public), scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: patternsFailure, input: { () throws(ClipboardRejection) in
            (try ClipboardMapping.patterns(patterns), try ClipboardMapping.scope(scope))
        }, start: { input, registration in
            IosClipboardManager.shared.detectPatterns(input.0, scope: input.1) { succeeded, patterns, errorCode, _ in
                finish(registration, succeeded: succeeded, value: patterns, errorCode: errorCode, failure: patternsFailure) { callback, userData, patterns in
                    callback(userData, none, systemCode, ClipboardMapping.bits(of: patterns))
                }
            }
        })
    }

    static func detectValues(_ patterns: ntk_clipboard_patterns, _ scope: UnsafePointer<ntk_clipboard_scope>?,
                             _ callback: ntk_clipboard_values_fn?, _ userData: UnsafeMutableRawPointer?,
                             _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[detectValues] patterns: \(patterns, privacy: .public), scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: valuesFailure, input: { () throws(ClipboardRejection) in
            (try ClipboardMapping.patterns(patterns), try ClipboardMapping.scope(scope))
        }, start: { input, registration in
            IosClipboardManager.shared.detectValues(input.0, scope: input.1) { succeeded, values, errorCode, _ in
                let text = values.flatMap(ClipboardValuesJson.text)
                finish(registration, succeeded: succeeded && text != nil, value: text, errorCode: errorCode, failure: valuesFailure) { callback, userData, text in
                    callback(userData, none, systemCode, Handle.makeString(text))
                }
            }
        })
    }

    // MARK: - OP-15

    static func checkForegroundChange(_ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_foreground_change_fn?,
                                      _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[checkForegroundChange] scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: foregroundFailure, input: { () throws(ClipboardRejection) in
            try ClipboardMapping.scope(scope)
        }, start: { scope, registration in
            let changed = IosClipboardManager.shared.checkForegroundChange(scope: scope)
            registration.complete { callback, userData, _ in
                callback(userData, none, systemCode, changed ? 1 : 0)
            }
        })
    }

    // MARK: - OP-11, OP-12

    static func loadItem(_ kind: ntk_clipboard_item_kind, _ utType: UnsafePointer<CChar>?, _ scope: UnsafePointer<ntk_clipboard_scope>?,
                         _ callback: ntk_clipboard_load_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                         _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[loadItem] kind: \(kind, privacy: .public), utType: \(utType == nil ? "nil" : "provided", privacy: .public), scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), outRequestID: \(outRequestID == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: loadFailure, cancellable: loadCancelKind, outRequestID: outRequestID,
                      input: { () throws(ClipboardRejection) in
            (try ClipboardMapping.loadRequest(kind: kind, utType: utType), try ClipboardMapping.scope(scope))
        }, start: { input, registration in
            // A request that can be cancelled has its box from the moment it is registered.
            guard let box = registration.requestBox else {
                CApiLog.clipboard.error("[loadItem] no request box")
                registration.complete { callback, userData, id in loadFailure(callback, userData, id, ntk_clipboard_error(NTK_CLIPBOARD_ERROR_UNKNOWN)) }
                return
            }
            IosClipboardManager.shared.loadItem(input.0, scope: input.1, requestBox: box) { succeeded, item, errorCode, _ in
                finishLoad(registration, succeeded: succeeded, item: item, errorCode: errorCode)
            }
        })
    }

    /// A `.file` that does not reach the caller is deleted with its folder, whatever the reason (part 2, 5.3).
    @MainActor
    private static func finishLoad(_ registration: Registration<ntk_clipboard_load_fn>, succeeded: Bool, item: ClipboardLoadedItem?, errorCode: String?) {
        CApiLog.clipboard.debug("[finishLoad] succeeded: \(succeeded, privacy: .public), item: \(item == nil ? "nil" : "provided", privacy: .public), errorCode: \(errorCode ?? "nil", privacy: .public)")
        guard succeeded, let item else {
            let error = ClipboardMapping.error(forCode: errorCode)
            CApiLog.clipboard.error("[finishLoad] error: \(error, privacy: .public), errorCode: \(errorCode ?? "nil", privacy: .public)")
            registration.complete { callback, userData, id in loadFailure(callback, userData, id, error) }
            return
        }
        var owned: OwnedResult?
        if case .file(let url) = item {
            owned = loadedFile(at: url)
        }
        registration.complete(result: owned) { callback, userData, id in
            callback(userData, id, none, systemCode, ClipboardHandles.makeLoadedItem(item))
        }
    }

    /// From any thread; does not wait. An id that is unknown or finished does nothing (part 2, 5.3).
    static func cancelLoad(_ requestID: UInt64) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[cancelLoad] requestID: \(requestID, privacy: .public)")
        Registry.cancel(id: requestID, request: loadCancelKind)
        return none
    }

    // MARK: - OP-13, OP-14

    static func startObserving(_ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_done_fn?,
                               _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[startObserving] scope: \(scope == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(ClipboardRejection) in
            try ClipboardMapping.scope(scope)
        }, start: { scope, registration in
            // A new start stops the previous observation, also when it fails (part 2, 6.1): as with a stop, nothing
            // of that one comes afterwards. The library's own generation gate says the same for what it has queued.
            changeLedger.discardUndelivered()
            do {
                try IosClipboardManager.shared.startObserving(scope: scope) { receive($0) }
                finishDone(registration, succeeded: true, errorCode: nil)
            } catch {
                finishDone(registration, succeeded: false, errorCode: (error as? ClipboardError)?.errorCode)
            }
        })
    }

    static func stopObserving(_ callback: ntk_clipboard_done_fn?, _ userData: UnsafeMutableRawPointer?,
                              _ release: ntk_release_fn?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[stopObserving] callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(ClipboardRejection) in
        }, start: { _, registration in
            IosClipboardManager.shared.stopObserving()
            // "Queued deliveries do not come either" (part 2, 6.1): what waits for a delivery in progress goes too.
            changeLedger.discardUndelivered()
            finishDone(registration, succeeded: true, errorCode: nil)
        })
    }

    // MARK: - OP-16, OP-17

    /// Registering does not start observing (P2-16). The output is NULL on every path but acceptance (R-8).
    static func addChangeListener(_ callback: ntk_clipboard_change_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                  _ outListener: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[addChangeListener] callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), outListener: \(outListener == nil ? "nil" : "provided", privacy: .public)")
        outListener?.pointee = nil
        guard let callback, let outListener else {
            CApiLog.clipboard.error("[addChangeListener] rejected: the callback or the output is NULL")
            return Entry.reject(.invalidParameter, userData: userData, release: release)
        }
        return changeLedger.add(callback: callback, userData: userData, release: release, outListener: outListener)
    }

    /// Observing goes on (P2-17). From any thread; does not wait.
    static func removeListener(_ listener: OpaquePointer?) {
        CApiLog.clipboard.debug("[removeListener] listener: \(listener == nil ? "nil" : "provided", privacy: .public)")
        Registry.removeListener(listener)
    }

    // MARK: - The load's result

    /// The result of a `.file` load: `IosLibrary` gives away the file and its parent folder (part 2, 5.3).
    /// The path may name what the user copied, so it is not logged.
    @MainActor
    static func loadedFile(at url: URL) -> OwnedResult {
        CApiLog.clipboard.debug("[loadedFile] url: provided")
        return OwnedResult {
            do {
                try FileManager.default.removeItem(at: url.deletingLastPathComponent())
            } catch {
                let failure = error as NSError
                CApiLog.clipboard.error("[loadedFile] not deleted: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")
            }
        }
    }
}
