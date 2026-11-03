//
//  ClipboardRows.swift
//  IosLibraryCApiUITestApp
//

import Foundation
import IosLibraryCApi
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp", category: "ClipboardRows")

/// The name of the pasteboard the rows that say `Named` use.
private let pasteboardName = "com.jonghyunkim.nativetoolkit.capi.ui"
private let text = "ntk-capi-ui-text"
private let plainTextType = "public.plain-text"

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

/// Every line starts with the error and the system code of the completion. A value of a handle follows.
private func doneRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32) {
    RowCompletion.from(userData).report("\(error) \(systemCode)")
}

private func readRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ result: OpaquePointer?) {
    defer { ntk_clipboard_read_result_free(result) }
    let count = ntk_clipboard_read_result_item_count(result)
    let types = ntk_clipboard_read_result_item_type_count(result, 0)
    let value = ntk_clipboard_read_result_item_text_at(result, 0, nil).map { String(cString: $0) } ?? "NULL"
    RowCompletion.from(userData).report("\(error) \(systemCode) items=\(count) hasTypes=\(types > 0) text=\(value)")
}

private func dataRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ data: OpaquePointer?) {
    defer { ntk_bytes_free(data) }
    let value = data.flatMap { handle in
        ntk_bytes_data(handle).map { String(decoding: UnsafeBufferPointer(start: $0, count: ntk_bytes_size(handle)), as: UTF8.self) }
    } ?? "NULL"
    RowCompletion.from(userData).report("\(error) \(systemCode) data=\(value)")
}

private func snapshotRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ snapshot: OpaquePointer?) {
    defer { ntk_clipboard_snapshot_free(snapshot) }
    RowCompletion.from(userData).report("\(error) \(systemCode) strings=\(ntk_clipboard_snapshot_has_strings(snapshot)) items=\(ntk_clipboard_snapshot_number_of_items(snapshot)) matching=\(ntk_clipboard_snapshot_has_matching(snapshot)) first=\(ntk_clipboard_snapshot_matching_at(snapshot, 0))")
}

private func nameRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ name: OpaquePointer?) {
    defer { ntk_string_free(name) }
    let value = ntk_string_data(name).map { String(cString: $0) } ?? "NULL"
    RowCompletion.from(userData).report("\(error) \(systemCode) name=\(value)")
}

private func patternsRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ patterns: UInt32) {
    RowCompletion.from(userData).report("\(error) \(systemCode) patterns=\(patterns)")
}

private func valuesRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ values: OpaquePointer?) {
    defer { ntk_string_free(values) }
    let value = ntk_string_data(values).map { String(cString: $0) } ?? "NULL"
    RowCompletion.from(userData).report("\(error) \(systemCode) json=\(value)")
}

private func changeRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ changed: Int32) {
    RowCompletion.from(userData).report("\(error) \(systemCode) changed=\(changed)")
}

/// `.file` belongs to the caller, so the row deletes the file and its folder after saying what it saw.
private func loadRow(_ userData: UnsafeMutableRawPointer?, _ requestID: UInt64, _ error: Int32, _ systemCode: UInt32, _ item: OpaquePointer?) {
    defer { ntk_clipboard_loaded_item_free(item) }
    let value = ntk_clipboard_loaded_item_text(item, nil).map { String(cString: $0) } ?? "NULL"
    var description = "\(error) \(systemCode) hasId=\(requestID != 0) kind=\(ntk_clipboard_loaded_item_kind(item)) text=\(value)"
    if let path = ntk_clipboard_loaded_item_file_path(item, nil).map({ String(cString: $0) }) {
        let bytes = FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) } ?? "NULL"
        description += " file=\(bytes)"
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
    }
    RowCompletion.from(userData).report(description)
}

private func listenerRow(_ userData: UnsafeMutableRawPointer?, _ change: OpaquePointer?) {
    defer { ntk_clipboard_change_free(change) }
    let name = ntk_clipboard_change_scope_name(change, nil).map { String(cString: $0) } ?? "NULL"
    RowCompletion.from(userData).report("change kind=\(ntk_clipboard_change_kind(change)) scope=\(ntk_clipboard_change_scope_kind(change)) name=\(name) hasAdded=\(ntk_clipboard_change_types_added_count(change) > 0)")
}

/// The listener of the `addListener` row, until the `removeListener` row.
@MainActor private var listener: OpaquePointer?

/// What the function returned, when it rejected the call: the completion will not come.
private func reportRejection(_ error: Int32, _ report: RowReport) {
    logger.debug("[reportRejection] rowId: \(report.rowId, privacy: .public), error: \(error, privacy: .public)")
    if error != 0 {
        report("rejected \(error)")
    }
}

/// Calls `body` with the scope that names the rows' pasteboard.
private func withNamedScope<Result>(_ body: (UnsafePointer<ntk_clipboard_scope>) -> Result) -> Result {
    pasteboardName.withCString { name in
        var scope = ntk_clipboard_scope()
        scope.struct_size = UInt32(MemoryLayout<ntk_clipboard_scope>.size)
        scope.kind = Int32(NTK_CLIPBOARD_SCOPE_NAMED)
        scope.name = name
        return withUnsafePointer(to: &scope, body)
    }
}

/// Calls `body` with a PLAIN_TEXT content.
private func withPlainText<Result>(_ value: String, _ body: (UnsafePointer<ntk_clipboard_write_content>) -> Result) -> Result {
    value.withCString { pointer in
        var content = ntk_clipboard_write_content()
        content.struct_size = UInt32(MemoryLayout<ntk_clipboard_write_content>.size)
        content.kind = Int32(NTK_CLIPBOARD_CONTENT_PLAIN_TEXT)
        content.text = pointer
        return withUnsafePointer(to: &content, body)
    }
}

/// Calls `body` with a content of `kind` and only `html` set, or none.
private func withContent<Result>(kind: Int, html: String? = nil, _ body: (UnsafePointer<ntk_clipboard_write_content>) -> Result) -> Result {
    (html ?? "").withCString { pointer in
        var content = ntk_clipboard_write_content()
        content.struct_size = UInt32(MemoryLayout<ntk_clipboard_write_content>.size)
        content.kind = Int32(kind)
        content.html = html == nil ? nil : pointer
        return withUnsafePointer(to: &content, body)
    }
}

/// Clipboard.h. A row is one call. The rows without `Named` use the
/// general pasteboard, which is the simulator's: these tests never run on a device.
enum ClipboardRows {
    private static let url = "https://example.com/ntk"
    private static let urlPattern = UInt32(NTK_CLIPBOARD_PATTERN_PROBABLE_WEB_URL)

    static let section = CApiRowSection(id: "clipboard", rows: [
        // The general pasteboard.
        CApiRow(id: "clipboard.copy") { report in
            reportRejection(withPlainText(text) { ntk_clipboard_copy_async($0, nil, nil, doneRow, RowCompletion.userData(report), releaseRow) }, report)
        },
        CApiRow(id: "clipboard.copyUrlAsText") { report in
            reportRejection(withPlainText(url) { ntk_clipboard_copy_async($0, nil, nil, doneRow, RowCompletion.userData(report), releaseRow) }, report)
        },
        CApiRow(id: "clipboard.append") { report in
            reportRejection(withPlainText(text) { ntk_clipboard_append_async($0, nil, doneRow, RowCompletion.userData(report), releaseRow) }, report)
        },
        CApiRow(id: "clipboard.read") { report in
            reportRejection(ntk_clipboard_read_async(nil, readRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.readData") { report in
            reportRejection(ntk_clipboard_read_data_async(plainTextType, nil, dataRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.readDataAbsent") { report in
            reportRejection(ntk_clipboard_read_data_async("com.example.absent", nil, dataRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.snapshot") { report in
            reportRejection(ntk_clipboard_get_snapshot_async(nil, 0, nil, snapshotRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.snapshotMatching") { report in
            let error = plainTextType.withCString { type -> Int32 in
                var types: [UnsafePointer<CChar>?] = [type]
                return ntk_clipboard_get_snapshot_async(&types, 1, nil, snapshotRow, RowCompletion.userData(report), releaseRow)
            }
            reportRejection(error, report)
        },
        CApiRow(id: "clipboard.clear") { report in
            reportRejection(ntk_clipboard_clear_async(nil, doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.detectPatterns") { report in
            reportRejection(ntk_clipboard_detect_patterns_async(urlPattern, nil, patternsRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.detectValues") { report in
            reportRejection(ntk_clipboard_detect_values_async(urlPattern, nil, valuesRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.checkChange") { report in
            reportRejection(ntk_clipboard_check_foreground_change_async(nil, changeRow, RowCompletion.userData(report), releaseRow), report)
        },
        // Loading, and cancelling a load.
        CApiRow(id: "clipboard.loadText") { report in
            reportRejection(ntk_clipboard_load_item_async(Int32(NTK_CLIPBOARD_ITEM_TEXT), nil, nil, loadRow, RowCompletion.userData(report), releaseRow, nil), report)
        },
        CApiRow(id: "clipboard.loadFile") { report in
            reportRejection(ntk_clipboard_load_item_async(Int32(NTK_CLIPBOARD_ITEM_FILE), plainTextType, nil, loadRow, RowCompletion.userData(report), releaseRow, nil), report)
        },
        CApiRow(id: "clipboard.loadAndCancel") { report in
            var requestID: UInt64 = 0
            let error = ntk_clipboard_load_item_async(Int32(NTK_CLIPBOARD_ITEM_TEXT), nil, nil, loadRow, RowCompletion.userData(report), releaseRow, &requestID)
            reportRejection(error, report)
            reportRejection(ntk_clipboard_cancel_load(requestID), report)
        },
        // Observing.
        CApiRow(id: "clipboard.startObserving") { report in
            reportRejection(ntk_clipboard_start_observing_async(nil, doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.startObservingNamed") { report in
            reportRejection(withNamedScope { ntk_clipboard_start_observing_async($0, doneRow, RowCompletion.userData(report), releaseRow) }, report)
        },
        CApiRow(id: "clipboard.stopObserving") { report in
            reportRejection(ntk_clipboard_stop_observing_async(doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.addListener") { report in
            let error = ntk_clipboard_add_change_listener(listenerRow, RowCompletion.userData(report), releaseRow, &listener)
            report("added \(error) hasHandle=\(listener != nil)")
        },
        CApiRow(id: "clipboard.removeListener") { report in
            ntk_clipboard_listener_remove(listener)
            listener = nil
            report("removed")
        },
        // A named pasteboard.
        CApiRow(id: "clipboard.createNamed") { report in
            reportRejection(ntk_clipboard_create_pasteboard_async(Int32(NTK_CLIPBOARD_SCOPE_NAMED), pasteboardName, nameRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.copyNamed") { report in
            let error = withNamedScope { scope in
                withPlainText(text) { ntk_clipboard_copy_async($0, nil, scope, doneRow, RowCompletion.userData(report), releaseRow) }
            }
            reportRejection(error, report)
        },
        CApiRow(id: "clipboard.readNamed") { report in
            reportRejection(withNamedScope { ntk_clipboard_read_async($0, readRow, RowCompletion.userData(report), releaseRow) }, report)
        },
        CApiRow(id: "clipboard.removeNamed") { report in
            reportRejection(withNamedScope { ntk_clipboard_remove_pasteboard_async($0, doneRow, RowCompletion.userData(report), releaseRow) }, report)
        },
        // Failures: in the completion, and at the entry.
        CApiRow(id: "clipboard.copyBlankHtml") { report in
            let error = withContent(kind: Int(NTK_CLIPBOARD_CONTENT_HTML), html: "  ") {
                ntk_clipboard_copy_async($0, nil, nil, doneRow, RowCompletion.userData(report), releaseRow)
            }
            reportRejection(error, report)
        },
        CApiRow(id: "clipboard.copyNoItems") { report in
            let error = withContent(kind: Int(NTK_CLIPBOARD_CONTENT_MULTIPLE_TEXT)) {
                ntk_clipboard_copy_async($0, nil, nil, doneRow, RowCompletion.userData(report), releaseRow)
            }
            reportRejection(error, report)
        },
        CApiRow(id: "clipboard.detectNoPatterns") { report in
            reportRejection(ntk_clipboard_detect_patterns_async(0, nil, patternsRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "clipboard.removeGeneral") { report in
            var scope = ntk_clipboard_scope()
            scope.struct_size = UInt32(MemoryLayout<ntk_clipboard_scope>.size)
            reportRejection(ntk_clipboard_remove_pasteboard_async(&scope, doneRow, RowCompletion.userData(report), releaseRow), report)
        },
    ])
}
