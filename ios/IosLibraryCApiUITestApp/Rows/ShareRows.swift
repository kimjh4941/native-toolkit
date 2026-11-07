//
//  ShareRows.swift
//  IosLibraryCApiUITestApp
//

import Foundation
import IosLibraryCApi
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp", category: "ShareRows")

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

private func reportRejection(_ error: Int32, _ report: RowReport) {
    logger.debug("[reportRejection] rowId: \(report.rowId, privacy: .public), error: \(error, privacy: .public)")
    if error != 0 {
        report("rejected \(error)")
    }
}

/// `<error> <system code> result=NULL` or `result=completed=<0|1>,activity=<id|NULL>`.
private func resultRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ result: OpaquePointer?) {
    defer { ntk_share_result_free(result) }
    let activity = ntk_share_result_activity_type(result, nil).map { String(cString: $0) } ?? "NULL"
    let value = result == nil ? "NULL" : "completed=\(ntk_share_result_completed(result)),activity=\(activity)"
    RowCompletion.from(userData).report("\(error) \(systemCode) result=\(value)")
}

/// A request of one item, for the call only: the library copies it.
private func withRequest<Result>(kind: Int32, value: String, count: Int = 1, _ call: (UnsafePointer<ntk_share_request>) -> Result) -> Result {
    value.withCString { text in
        "C ABI share".withCString { subject in
            var item = ntk_share_item()
            item.struct_size = UInt32(MemoryLayout<ntk_share_item>.size)
            item.kind = kind
            item.value = text
            return withUnsafePointer(to: &item) { items in
                var request = ntk_share_request()
                request.struct_size = UInt32(MemoryLayout<ntk_share_request>.size)
                request.items = count == 0 ? nil : items
                request.item_count = count
                request.subject = subject
                return withUnsafePointer(to: &request, call)
            }
        }
    }
}

/// Share.h. The values are the numbers of `ntk_share_error`. These rows only open the sheet: the tests close it or choose its copy action.
enum ShareRows {
    static let section = CApiRowSection(id: "share", rows: [
        CApiRow(id: "share.text") { report in
            reportRejection(withRequest(kind: Int32(NTK_SHARE_ITEM_TEXT), value: "ntk-capi-share-text") {
                ntk_share_content_async($0, resultRow, RowCompletion.userData(report), releaseRow)
            }, report)
        },
        CApiRow(id: "share.missingFile") { report in
            reportRejection(withRequest(kind: Int32(NTK_SHARE_ITEM_FILE), value: "/nonexistent/ntk-capi-share.txt") {
                ntk_share_content_async($0, resultRow, RowCompletion.userData(report), releaseRow)
            }, report)
        },
        CApiRow(id: "share.empty") { report in
            reportRejection(withRequest(kind: Int32(NTK_SHARE_ITEM_TEXT), value: "unused", count: 0) {
                ntk_share_content_async($0, resultRow, RowCompletion.userData(report), releaseRow)
            }, report)
        },
    ])
}
