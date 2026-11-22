//
//  DialogRows.swift
//  IosLibraryCApiUITestApp
//

import Foundation
import IosLibraryCApi
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp", category: "DialogRows")

/// What a C completion reports through: `user_data` is this object, retained until `release`.
private final class RowCompletion {
    let report: RowReport

    init(_ report: RowReport) {
        self.report = report
    }

    static func userData(_ report: RowReport) -> UnsafeMutableRawPointer {
        logger.debug("[userData] rowId: \(report.rowId, privacy: .public)")
        return Unmanaged.passRetained(RowCompletion(report)).toOpaque()
    }

    static func from(_ userData: UnsafeMutableRawPointer?) -> RowCompletion {
        Unmanaged<RowCompletion>.fromOpaque(userData!).takeUnretainedValue()
    }
}

private func releaseRow(_ userData: UnsafeMutableRawPointer?) {
    Unmanaged<RowCompletion>.fromOpaque(userData!).release()
}

private func optionalText(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? "NULL"
}

/// `<error> <system code> hasId=... button=... option=... label=... text=... user=... pass=...`. The values are
/// the test's own: these rows run on the simulator only.
private func describe(_ requestID: UInt64, _ error: Int32, _ systemCode: UInt32, _ result: OpaquePointer?) -> String {
    "\(error) \(systemCode) hasId=\(requestID != 0) button=\(ntk_dialog_result_button(result)) option=\(ntk_dialog_result_option_index(result)) label=\(optionalText(ntk_dialog_result_button_text(result, nil))) text=\(optionalText(ntk_dialog_result_text(result, nil))) user=\(optionalText(ntk_dialog_result_username(result, nil))) pass=\(optionalText(ntk_dialog_result_password(result, nil)))"
}

private func resultRow(_ userData: UnsafeMutableRawPointer?, _ requestID: UInt64, _ error: Int32, _ systemCode: UInt32, _ result: OpaquePointer?) {
    defer { ntk_dialog_result_free(result) }
    RowCompletion.from(userData).report(describe(requestID, error, systemCode, result))
}

/// The completion cancels its own request, which brings no second completion, and starts the next dialog.
/// Neither call runs anything inside it.
private func chainRow(_ userData: UnsafeMutableRawPointer?, _ requestID: UInt64, _ error: Int32, _ systemCode: UInt32, _ result: OpaquePointer?) {
    defer { ntk_dialog_result_free(result) }
    let report = RowCompletion.from(userData).report
    let cancel = ntk_dialog_cancel(requestID)
    let next = withAlert(title: "Chained", message: nil, button: "Chained OK") {
        ntk_dialog_show_alert_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil)
    }
    report("\(describe(requestID, error, systemCode, result)) cancel=\(cancel) next=\(next)")
}

private func reportRejection(_ error: Int32, _ report: RowReport) {
    logger.debug("[reportRejection] rowId: \(report.rowId, privacy: .public), error: \(error, privacy: .public)")
    if error != 0 {
        report("rejected \(error)")
    }
}

/// Calls `body` with C strings that end with the call: the library has to copy them.
private func withCStrings<Result>(_ strings: [String?], _ pointers: [UnsafePointer<CChar>?] = [], _ body: ([UnsafePointer<CChar>?]) -> Result) -> Result {
    guard let first = strings.first else { return body(pointers) }
    let rest = Array(strings.dropFirst())
    guard let first else { return withCStrings(rest, pointers + [nil], body) }
    return first.withCString { withCStrings(rest, pointers + [$0], body) }
}

private func withAlert<Result>(title: String?, message: String?, button: String?, _ body: (UnsafePointer<ntk_dialog_alert_request>) -> Result) -> Result {
    withCStrings([title, message, button]) { texts in
        var request = ntk_dialog_alert_request()
        request.struct_size = UInt32(MemoryLayout<ntk_dialog_alert_request>.size)
        request.title = texts[0]
        request.message = texts[1]
        request.button_text = texts[2]
        return withUnsafePointer(to: &request, body)
    }
}

private func withConfirm<Result>(_ body: (UnsafePointer<ntk_dialog_confirm_request>) -> Result) -> Result {
    withCStrings(["Confirm", "Sure?", "Yes", "No"]) { texts in
        var request = ntk_dialog_confirm_request()
        request.struct_size = UInt32(MemoryLayout<ntk_dialog_confirm_request>.size)
        request.title = texts[0]
        request.message = texts[1]
        request.confirm_text = texts[2]
        request.cancel_text = texts[3]
        return withUnsafePointer(to: &request, body)
    }
}

private func withDestructive<Result>(_ body: (UnsafePointer<ntk_dialog_destructive_request>) -> Result) -> Result {
    withCStrings(["Destructive", "Really?", "Erase", "Keep"]) { texts in
        var request = ntk_dialog_destructive_request()
        request.struct_size = UInt32(MemoryLayout<ntk_dialog_destructive_request>.size)
        request.title = texts[0]
        request.message = texts[1]
        request.destructive_text = texts[2]
        request.cancel_text = texts[3]
        return withUnsafePointer(to: &request, body)
    }
}

private func withActionSheet<Result>(_ body: (UnsafePointer<ntk_dialog_action_sheet_request>) -> Result) -> Result {
    withCStrings(["Sheet", "Choose", "Alpha", "Beta", "Dismiss"]) { texts in
        let options = [texts[2], texts[3]]
        return options.withUnsafeBufferPointer { buffer in
            var request = ntk_dialog_action_sheet_request()
            request.struct_size = UInt32(MemoryLayout<ntk_dialog_action_sheet_request>.size)
            request.title = texts[0]
            request.message = texts[1]
            request.options = buffer.baseAddress
            request.option_count = buffer.count
            request.cancel_text = texts[4]
            return withUnsafePointer(to: &request, body)
        }
    }
}

private func withTextInput<Result>(required: Bool, _ body: (UnsafePointer<ntk_dialog_text_input_request>) -> Result) -> Result {
    withCStrings(["Input", "Type", "Your text", "Send", "Back"]) { texts in
        var request = ntk_dialog_text_input_request()
        request.struct_size = UInt32(MemoryLayout<ntk_dialog_text_input_request>.size)
        request.title = texts[0]
        request.message = texts[1]
        request.placeholder = texts[2]
        request.confirm_text = texts[3]
        request.cancel_text = texts[4]
        request.confirm_disabled_when_empty = required ? 1 : 0
        return withUnsafePointer(to: &request, body)
    }
}

private func withLogin<Result>(required: Bool, _ body: (UnsafePointer<ntk_dialog_login_request>) -> Result) -> Result {
    withCStrings(["Sign in", "Who?", "Account", "Secret", "Enter", "Leave"]) { texts in
        var request = ntk_dialog_login_request()
        request.struct_size = UInt32(MemoryLayout<ntk_dialog_login_request>.size)
        request.title = texts[0]
        request.message = texts[1]
        request.username_placeholder = texts[2]
        request.password_placeholder = texts[3]
        request.login_text = texts[4]
        request.cancel_text = texts[5]
        request.login_disabled_when_empty = required ? 1 : 0
        return withUnsafePointer(to: &request, body)
    }
}

/// The time a dialog stays on the screen before a timed row goes on, for a UI test to see it.
private let shownFor: TimeInterval = 2

/// The id of a request of the `lastId` rows.
@MainActor private var lastRequestID: UInt64 = 0

/// Dialog.h. A row is one request, and its line comes when the dialog is answered.
enum DialogRows {
    static let section = CApiRowSection(id: "dialog", rows: [
        // The six kinds.
        CApiRow(id: "dialog.alert") { report in
            reportRejection(withAlert(title: "Alert", message: "Note", button: "Got it") {
                ntk_dialog_show_alert_async($0, resultRow, RowCompletion.userData(report), releaseRow, &lastRequestID)
            }, report)
        },
        CApiRow(id: "dialog.confirm") { report in
            reportRejection(withConfirm { ntk_dialog_show_confirm_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil) }, report)
        },
        CApiRow(id: "dialog.destructive") { report in
            reportRejection(withDestructive { ntk_dialog_show_destructive_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil) }, report)
        },
        CApiRow(id: "dialog.actionSheet") { report in
            reportRejection(withActionSheet { ntk_dialog_show_action_sheet_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil) }, report)
        },
        CApiRow(id: "dialog.textInput") { report in
            reportRejection(withTextInput(required: false) { ntk_dialog_show_text_input_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil) }, report)
        },
        CApiRow(id: "dialog.textInputRequired") { report in
            reportRejection(withTextInput(required: true) { ntk_dialog_show_text_input_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil) }, report)
        },
        CApiRow(id: "dialog.login") { report in
            reportRejection(withLogin(required: false) { ntk_dialog_show_login_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil) }, report)
        },
        CApiRow(id: "dialog.loginRequired") { report in
            reportRejection(withLogin(required: true) { ntk_dialog_show_login_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil) }, report)
        },
        // Zero-filled: the library's texts.
        CApiRow(id: "dialog.alertDefault") { report in
            reportRejection(withAlert(title: nil, message: nil, button: nil) {
                ntk_dialog_show_alert_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil)
            }, report)
        },
        // Rejected.
        CApiRow(id: "dialog.alertOfNull") { report in
            reportRejection(ntk_dialog_show_alert_async(nil, resultRow, RowCompletion.userData(report), releaseRow, nil), report)
        },
        // Cancelling.
        CApiRow(id: "dialog.alertAndCancel") { report in
            var requestID: UInt64 = 0
            let error = withAlert(title: "Never", message: nil, button: "OK") {
                ntk_dialog_show_alert_async($0, resultRow, RowCompletion.userData(report), releaseRow, &requestID)
            }
            reportRejection(error, report)
            reportRejection(ntk_dialog_cancel(requestID), report)
        },
        CApiRow(id: "dialog.alertThenCancelLater") { report in
            var requestID: UInt64 = 0
            let error = withAlert(title: "Cancelled later", message: nil, button: "OK") {
                ntk_dialog_show_alert_async($0, resultRow, RowCompletion.userData(report), releaseRow, &requestID)
            }
            reportRejection(error, report)
            let id = requestID
            DispatchQueue.global().asyncAfter(deadline: .now() + shownFor) {
                _ = ntk_dialog_cancel(id)
            }
        },
        // A second dialog over the first, and the first cancelled while it is covered (P1-24).
        CApiRow(id: "dialog.coveredThenCancel") { report in
            var requestID: UInt64 = 0
            let error = withAlert(title: "Covered", message: nil, button: "Covered OK") {
                ntk_dialog_show_alert_async($0, resultRow, RowCompletion.userData(report), releaseRow, &requestID)
            }
            reportRejection(error, report)
            let id = requestID
            DispatchQueue.main.asyncAfter(deadline: .now() + shownFor) {
                let cover = withAlert(title: "Cover", message: nil, button: "Cover OK") {
                    ntk_dialog_show_alert_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil)
                }
                reportRejection(cover, report)
                DispatchQueue.main.asyncAfter(deadline: .now() + shownFor) {
                    _ = ntk_dialog_cancel(id)
                }
            }
        },
        CApiRow(id: "dialog.twoInOneTurn") { report in
            reportRejection(withAlert(title: "First", message: nil, button: "First OK") {
                ntk_dialog_show_alert_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil)
            }, report)
            reportRejection(withAlert(title: "Second", message: nil, button: "Second OK") {
                ntk_dialog_show_alert_async($0, resultRow, RowCompletion.userData(report), releaseRow, nil)
            }, report)
        },
        CApiRow(id: "dialog.chain") { report in
            reportRejection(withAlert(title: "Chain", message: nil, button: "Chain OK") {
                ntk_dialog_show_alert_async($0, chainRow, RowCompletion.userData(report), releaseRow, nil)
            }, report)
        },
        CApiRow(id: "dialog.cancelLast") { report in
            report("cancel \(ntk_dialog_cancel(lastRequestID)) hadId=\(lastRequestID != 0)")
        },
        CApiRow(id: "dialog.cancelUnknown") { report in
            report("cancel \(ntk_dialog_cancel(UInt64.max))")
        },
    ])
}
