//
//  DialogReceiver.swift
//  IosLibraryCApi
//

import IosLibrary

/// What the functions of Dialog.h do (part 2, 5.1, 6.2): the entry's checks and copies in `DialogMapping`,
/// the accepted request to the main thread, the manager with `.foreground` and the request's box (P2-1), the
/// result handle and the completion.
enum DialogReceiver {
    /// A Dialog request closes its box through the manager (part 2, 5.3; OP-24).
    static let cancelKind = CancellableKind(name: "dialog") { IosDialogManager.shared.cancel($0) }

    private static let none = ntk_dialog_error(NTK_DIALOG_ERROR_NONE)
    private static let systemCode: UInt32 = 0

    /// Steps 2 to 7 of acceptance (part 1, 5.7). What `request` returns holds no pointer of the caller.
    private static func show(_ callback: ntk_dialog_result_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                             _ outRequestID: UnsafeMutablePointer<UInt64>?, function: String = #function,
                             request: () throws(EntryError) -> DialogRequest) -> ntk_dialog_error {
        guard let callback else {
            CApiLog.dialog.error("[show] \(function, privacy: .public): the callback is NULL")
            return Entry.reject(.invalidParameter, userData: userData, release: release, function: function)
        }
        do throws(EntryError) {
            let value = try request()
            return Registry.accept(callback: callback, userData: userData, release: release, cancellable: cancelKind,
                                   canceled: { callback, userData, id in callback(userData, id, ntk_dialog_error(NTK_DIALOG_ERROR_CANCELED), systemCode, nil) },
                                   outRequestID: outRequestID, start: { start(value, $0) })
        } catch {
            return Entry.reject(error, userData: userData, release: release, function: function)
        }
    }

    @MainActor
    private static func start(_ request: DialogRequest, _ registration: Registration<ntk_dialog_result_fn>) {
        CApiLog.dialog.debug("[start] id: \(registration.id, privacy: .public)")
        // A request that can be cancelled has its box from the moment it is registered.
        guard let box = registration.requestBox else {
            CApiLog.dialog.error("[start] no request box")
            registration.complete { callback, userData, id in callback(userData, id, ntk_dialog_error(NTK_DIALOG_ERROR_UNKNOWN), systemCode, nil) }
            return
        }
        IosDialogManager.shared.show(request, presenter: .foreground, requestBox: box) { finish(registration, $0) }
    }

    @MainActor
    static func finish(_ registration: Registration<ntk_dialog_result_fn>, _ result: Result<DialogAnswer, DialogError>) {
        CApiLog.dialog.debug("[finish] id: \(registration.id, privacy: .public)")
        switch result {
        case .success(let answer):
            guard let value = DialogMapping.result(of: answer) else {
                registration.complete { callback, userData, id in callback(userData, id, ntk_dialog_error(NTK_DIALOG_ERROR_UNKNOWN), systemCode, nil) }
                return
            }
            registration.complete { callback, userData, id in callback(userData, id, none, systemCode, DialogHandles.makeResult(value)) }
        case .failure(let failure):
            let error = DialogMapping.error(for: failure)
            CApiLog.dialog.error("[finish] error: \(error, privacy: .public), failure: \(String(describing: failure), privacy: .public)")
            registration.complete { callback, userData, id in callback(userData, id, error, systemCode, nil) }
        }
    }

    // MARK: - OP-18 to OP-23

    static func alert(_ request: UnsafePointer<ntk_dialog_alert_request>?, _ callback: ntk_dialog_result_fn?, _ userData: UnsafeMutableRawPointer?,
                    _ release: ntk_release_fn?, _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
        CApiLog.dialog.debug("[alert] request: \(request == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), outRequestID: \(outRequestID == nil ? "nil" : "provided", privacy: .public)")
        return show(callback, userData, release, outRequestID) { () throws(EntryError) in try DialogMapping.alert(request) }
    }

    static func confirm(_ request: UnsafePointer<ntk_dialog_confirm_request>?, _ callback: ntk_dialog_result_fn?, _ userData: UnsafeMutableRawPointer?,
                    _ release: ntk_release_fn?, _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
        CApiLog.dialog.debug("[confirm] request: \(request == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), outRequestID: \(outRequestID == nil ? "nil" : "provided", privacy: .public)")
        return show(callback, userData, release, outRequestID) { () throws(EntryError) in try DialogMapping.confirm(request) }
    }

    static func destructive(_ request: UnsafePointer<ntk_dialog_destructive_request>?, _ callback: ntk_dialog_result_fn?, _ userData: UnsafeMutableRawPointer?,
                    _ release: ntk_release_fn?, _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
        CApiLog.dialog.debug("[destructive] request: \(request == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), outRequestID: \(outRequestID == nil ? "nil" : "provided", privacy: .public)")
        return show(callback, userData, release, outRequestID) { () throws(EntryError) in try DialogMapping.destructive(request) }
    }

    static func actionSheet(_ request: UnsafePointer<ntk_dialog_action_sheet_request>?, _ callback: ntk_dialog_result_fn?, _ userData: UnsafeMutableRawPointer?,
                    _ release: ntk_release_fn?, _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
        CApiLog.dialog.debug("[actionSheet] request: \(request == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), outRequestID: \(outRequestID == nil ? "nil" : "provided", privacy: .public)")
        return show(callback, userData, release, outRequestID) { () throws(EntryError) in try DialogMapping.actionSheet(request) }
    }

    static func textInput(_ request: UnsafePointer<ntk_dialog_text_input_request>?, _ callback: ntk_dialog_result_fn?, _ userData: UnsafeMutableRawPointer?,
                    _ release: ntk_release_fn?, _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
        CApiLog.dialog.debug("[textInput] request: \(request == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), outRequestID: \(outRequestID == nil ? "nil" : "provided", privacy: .public)")
        return show(callback, userData, release, outRequestID) { () throws(EntryError) in try DialogMapping.textInput(request) }
    }

    static func login(_ request: UnsafePointer<ntk_dialog_login_request>?, _ callback: ntk_dialog_result_fn?, _ userData: UnsafeMutableRawPointer?,
                    _ release: ntk_release_fn?, _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
        CApiLog.dialog.debug("[login] request: \(request == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), outRequestID: \(outRequestID == nil ? "nil" : "provided", privacy: .public)")
        return show(callback, userData, release, outRequestID) { () throws(EntryError) in try DialogMapping.login(request) }
    }

    // MARK: - OP-24

    /// From any thread; does not wait. An id that is unknown, finished or not a Dialog's does nothing (part 2, 5.3).
    static func cancel(_ requestID: UInt64) -> ntk_dialog_error {
        CApiLog.dialog.debug("[cancel] requestID: \(requestID, privacy: .public)")
        Registry.cancel(id: requestID, request: cancelKind)
        return none
    }
}
