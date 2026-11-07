//
//  ShareMapping.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary

/// Why a share is rejected at its entry: one of the values every feature shares, or EMPTY_CONTENT (AP-19).
enum ShareRejection: Error, Equatable {
    case entry(EntryError)
    case emptyContent

    var value: ntk_share_error {
        switch self {
        case .entry(let error): return error.rawValue
        case .emptyContent: return ntk_share_error(NTK_SHARE_ERROR_EMPTY_CONTENT)
        }
    }
}

/// What an `ntk_share_result` says.
struct ShareResultValue: Sendable, Equatable {
    let completed: Bool
    let activityType: String?
}

/// The pure conversions of Share.h (part 2, 6.4, 11.4), on the calling thread and before anything is registered.
/// Every struct is read with `reserved:` naming all its reserved fields but `reserved0`. The content is never
/// logged: only counts and kinds.
enum ShareMapping {
    private static func rejected<Value>(_ reason: StaticString) throws(ShareRejection) -> Value {
        CApiLog.share.error("[rejected] \(reason, privacy: .public)")
        throw .entry(.invalidParameter)
    }

    /// The request (6.4): no item is EMPTY_CONTENT, before the items are read; an item of a kind out of range or
    /// with a NULL value, a NULL array with a count, and a NULL excluded type are INVALID_PARAMETER. What the
    /// values mean (an empty text, a URL, whether a file is there) the library decides in the completion.
    static func content(_ pointer: UnsafePointer<ntk_share_request>?) throws(ShareRejection) -> ShareContent {
        CApiLog.share.debug("[content] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        let raw = try entry { () throws(EntryError) in try StructReader.read(pointer, reserved: []) }
        guard raw.item_count != 0 else {
            CApiLog.share.error("[content] EMPTY_CONTENT: no item")
            throw .emptyContent
        }
        let elements = try entry { () throws(EntryError) in try StructReader.readArray(raw.items, count: raw.item_count, reserved: [\.reserved1]) }
        var items: [ShareItem] = []
        for element in elements {
            items.append(try item(element))
        }
        return try entry { () throws(EntryError) in
            ShareContent(items: items, subject: try CApiString.optional(raw.subject), previewTitle: try CApiString.optional(raw.preview_title),
                         excludedActivityTypes: try CApiString.requiredArray(raw.excluded_activity_types, count: raw.excluded_activity_type_count))
        }
    }

    /// A rejection of the values every feature shares.
    private static func entry<Value>(_ body: () throws(EntryError) -> Value) throws(ShareRejection) -> Value {
        do throws(EntryError) {
            return try body()
        } catch {
            throw .entry(error)
        }
    }

    /// The kind first: one out of range is rejected without reading the value.
    static func item(_ raw: ntk_share_item) throws(ShareRejection) -> ShareItem {
        CApiLog.share.debug("[item] kind: \(raw.kind, privacy: .public)")
        let make: (String) -> ShareItem
        switch Int(raw.kind) {
        case Int(NTK_SHARE_ITEM_TEXT): make = { .text($0) }
        case Int(NTK_SHARE_ITEM_URL): make = { .url($0) }
        case Int(NTK_SHARE_ITEM_IMAGE_FILE): make = { .imageFile(path: $0) }
        case Int(NTK_SHARE_ITEM_FILE): make = { .file(path: $0) }
        default: return try rejected("the item kind is out of range")
        }
        return make(try entry { () throws(EntryError) in try CApiString.required(raw.value) })
    }

    static func result(of result: ShareResult) -> ShareResultValue {
        CApiLog.share.debug("[result] completed: \(result.completed, privacy: .public), activityType: \(result.activityType == nil ? "nil" : "provided", privacy: .public)")
        return ShareResultValue(completed: result.completed, activityType: result.activityType)
    }

    /// 11.4. The payloads hold the shared URL or path, so only the value is logged.
    static func error(for failure: ShareError) -> ntk_share_error {
        let error: ntk_share_error
        switch failure {
        case .noValidItems: error = ntk_share_error(NTK_SHARE_ERROR_EMPTY_CONTENT)
        case .invalidURL: error = ntk_share_error(NTK_SHARE_ERROR_INVALID_URI)
        case .imageLoadFailed: error = ntk_share_error(NTK_SHARE_ERROR_IMAGE_LOAD_FAILED)
        case .fileNotFound: error = ntk_share_error(NTK_SHARE_ERROR_FILE_NOT_FOUND)
        case .noRootViewController, .notForeground: error = ntk_share_error(NTK_SHARE_ERROR_NOT_FOREGROUND)
        case .presentationFailed: error = ntk_share_error(NTK_SHARE_ERROR_SHOW_FAILED)
        case .dismissedBySystem: error = ntk_share_error(NTK_SHARE_ERROR_CANCELED_BY_SYSTEM)
        case .activityFailed: error = ntk_share_error(NTK_SHARE_ERROR_ACTIVITY_FAILED)
        @unknown default:
            CApiLog.share.error("[error] a case this version does not know")
            error = ntk_share_error(NTK_SHARE_ERROR_UNKNOWN)
        }
        CApiLog.share.debug("[error] error: \(error, privacy: .public)")
        return error
    }
}
