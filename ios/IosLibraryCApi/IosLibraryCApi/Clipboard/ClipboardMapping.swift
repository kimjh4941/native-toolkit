//
//  ClipboardMapping.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary

/// Why a Clipboard function is rejected at its entry (part 2, chapter 6): the values every feature shares,
/// and the two the entry of this feature also returns (11.3).
enum ClipboardRejection: Error, Equatable {
    case entry(EntryError)
    case emptyItems
    case emptyPatterns

    var value: ntk_clipboard_error {
        switch self {
        case .entry(let error): return error.rawValue
        case .emptyItems: return ntk_clipboard_error(NTK_CLIPBOARD_ERROR_EMPTY_ITEMS)
        case .emptyPatterns: return ntk_clipboard_error(NTK_CLIPBOARD_ERROR_EMPTY_PATTERNS)
        }
    }
}

/// What `ntk_clipboard_change` says. The ledger keeps these, and each listener gets a handle of its own.
struct ClipboardChange: Sendable, Equatable {
    let kind: ntk_clipboard_change_event_kind
    let scopeKind: ntk_clipboard_scope_kind
    let scopeName: String?
    let typesAdded: [String]
    let typesRemoved: [String]
}

/// The pure conversions of Clipboard.h: C values to Swift values (part 2, 6.1) and back, on the calling
/// thread and before anything is registered. Everything is a deep copy, so that no pointer of the caller
/// goes to the main thread. Only what the conversion itself needs is checked here; whether the content
/// is good is `IosLibrary`'s, which says so in the completion (AP-19).
///
/// Every struct is read with `reserved:` naming all its reserved fields but `reserved0` (StructReader's rule 1).
enum ClipboardMapping {
    /// `throws(EntryError)` of the shared parts, in this feature's error.
    private static func entry<Value>(_ body: () throws(EntryError) -> Value) throws(ClipboardRejection) -> Value {
        do throws(EntryError) {
            return try body()
        } catch {
            throw .entry(error)
        }
    }

    private static func rejected<Value>(_ reason: StaticString) throws(ClipboardRejection) -> Value {
        CApiLog.clipboard.error("[rejected] \(reason, privacy: .public)")
        throw .entry(.invalidParameter)
    }

    // MARK: - Scope

    /// `ntk_clipboard_scope`: NULL is the general pasteboard.
    static func scope(_ pointer: UnsafePointer<ntk_clipboard_scope>?) throws(ClipboardRejection) -> PasteboardScope {
        CApiLog.clipboard.debug("[scope] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        guard let raw = try entry({ () throws(EntryError) in try StructReader.readIfPresent(pointer, reserved: [\.reserved1]) }) else {
            return .general
        }
        return try scope(from: raw)
    }

    /// The same for the function that does not take NULL (`ntk_clipboard_remove_pasteboard_async`).
    static func requiredScope(_ pointer: UnsafePointer<ntk_clipboard_scope>?) throws(ClipboardRejection) -> PasteboardScope {
        CApiLog.clipboard.debug("[requiredScope] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        return try scope(from: entry { () throws(EntryError) in try StructReader.read(pointer, reserved: [\.reserved1]) })
    }

    /// `name` is read only for NAMED and UNIQUE.
    static func scope(from raw: ntk_clipboard_scope) throws(ClipboardRejection) -> PasteboardScope {
        CApiLog.clipboard.debug("[scope] kind: \(raw.kind, privacy: .public)")
        switch Int(raw.kind) {
        case Int(NTK_CLIPBOARD_SCOPE_GENERAL): return .general
        case Int(NTK_CLIPBOARD_SCOPE_NAMED): return .named(try requiredName(raw.name))
        case Int(NTK_CLIPBOARD_SCOPE_UNIQUE): return .unique(try requiredName(raw.name))
        default: return try rejected("the scope kind is out of range")
        }
    }

    /// `ntk_clipboard_create_pasteboard_async`: GENERAL is not something to create, and UNIQUE does not read `name`.
    static func creationRequest(kind: ntk_clipboard_scope_kind, name: UnsafePointer<CChar>?) throws(ClipboardRejection) -> PasteboardCreationRequest {
        CApiLog.clipboard.debug("[creationRequest] kind: \(kind, privacy: .public), name: \(name == nil ? "nil" : "provided", privacy: .public)")
        switch Int(kind) {
        case Int(NTK_CLIPBOARD_SCOPE_NAMED): return .named(try requiredName(name))
        case Int(NTK_CLIPBOARD_SCOPE_UNIQUE): return .unique
        default: return try rejected("the kind to create is not NAMED or UNIQUE")
        }
    }

    /// A pasteboard's name must be there and not be empty (part 2, 6.1). A name of only spaces is the library's.
    private static func requiredName(_ name: UnsafePointer<CChar>?) throws(ClipboardRejection) -> String {
        let value = try entry { () throws(EntryError) in try CApiString.required(name) }
        guard !value.isEmpty else { return try rejected("the pasteboard name is empty") }
        return value
    }

    /// The name the completion of `ntk_clipboard_create_pasteboard_async` gives; the general pasteboard
    /// has none, and the library does not create it.
    static func name(of scope: PasteboardScope) -> String? {
        CApiLog.clipboard.debug("[name] scope: provided")
        switch scope {
        case .general: return nil
        case .named(let name), .unique(let name): return name
        @unknown default: return nil
        }
    }

    /// The kind of a scope in an event. Nil for a scope this version does not know: the C ABI has no value for it.
    static func scopeKind(of scope: PasteboardScope) -> ntk_clipboard_scope_kind? {
        CApiLog.clipboard.debug("[scopeKind] scope: provided")
        switch scope {
        case .general: return ntk_clipboard_scope_kind(NTK_CLIPBOARD_SCOPE_GENERAL)
        case .named: return ntk_clipboard_scope_kind(NTK_CLIPBOARD_SCOPE_NAMED)
        case .unique: return ntk_clipboard_scope_kind(NTK_CLIPBOARD_SCOPE_UNIQUE)
        @unknown default: return nil
        }
    }

    // MARK: - Change events

    /// An event as the C ABI can say it, or nil when it cannot: `changedDetectedOnForeground` has no value and
    /// `IosLibrary` does not make it (part 2, 6.1), and a case this version does not know has none either.
    /// Such an event reaches no listener, rather than one as something it is not.
    static func change(of event: ClipboardChangeEvent) -> ClipboardChange? {
        CApiLog.clipboard.debug("[change] event: provided")
        guard let scopeKind = scopeKind(of: event.scope) else {
            CApiLog.clipboard.error("[change] dropped: a scope this version does not know")
            return nil
        }
        let name = name(of: event.scope)
        switch event.kind {
        case .changed(let added, let removed):
            return ClipboardChange(kind: ntk_clipboard_change_event_kind(NTK_CLIPBOARD_CHANGE_CHANGED), scopeKind: scopeKind, scopeName: name,
                                   typesAdded: added, typesRemoved: removed)
        case .removed:
            return ClipboardChange(kind: ntk_clipboard_change_event_kind(NTK_CLIPBOARD_CHANGE_REMOVED), scopeKind: scopeKind, scopeName: name,
                                   typesAdded: [], typesRemoved: [])
        case .changedDetectedOnForeground:
            CApiLog.clipboard.error("[change] dropped: changedDetectedOnForeground has no value in the C ABI")
            return nil
        @unknown default:
            CApiLog.clipboard.error("[change] dropped: a kind of event this version does not know")
            return nil
        }
    }

    // MARK: - Content

    /// `ntk_clipboard_write_content`.
    static func content(_ pointer: UnsafePointer<ntk_clipboard_write_content>?) throws(ClipboardRejection) -> ClipboardContent {
        CApiLog.clipboard.debug("[content] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        return try content(from: entry { () throws(EntryError) in try StructReader.read(pointer, reserved: [\.reserved1]) })
    }

    /// `kind` decides which fields are read; the others are not, whatever they hold (part 2, 6.1).
    static func content(from raw: ntk_clipboard_write_content) throws(ClipboardRejection) -> ClipboardContent {
        CApiLog.clipboard.debug("[content] kind: \(raw.kind, privacy: .public)")
        switch Int(raw.kind) {
        case Int(NTK_CLIPBOARD_CONTENT_PLAIN_TEXT):
            return .plainText(try required(raw.text))
        case Int(NTK_CLIPBOARD_CONTENT_HTML):
            // The plain text may be left out, as on Android: NULL is "" (E-15).
            let plain = try entry { () throws(EntryError) in try CApiString.orEmpty(raw.text) }
            return .htmlText(plain: plain, html: try required(raw.html))
        case Int(NTK_CLIPBOARD_CONTENT_URL):
            return .url(try required(raw.url))
        case Int(NTK_CLIPBOARD_CONTENT_IMAGE_FILE):
            let path = try required(raw.path)
            guard !path.isEmpty else { return try rejected("the image path is empty") }
            return .imageFile(path: path)
        case Int(NTK_CLIPBOARD_CONTENT_IMAGE_DATA):
            let utType = try required(raw.ut_type)
            return .imageData(try bytes(raw.data, raw.data_size), utType: utType)
        case Int(NTK_CLIPBOARD_CONTENT_COLOR):
            return .color(red: raw.red, green: raw.green, blue: raw.blue, alpha: raw.alpha)
        case Int(NTK_CLIPBOARD_CONTENT_CUSTOM_DATA):
            let utType = try required(raw.ut_type)
            return .customData(try bytes(raw.data, raw.data_size), utType: utType)
        case Int(NTK_CLIPBOARD_CONTENT_MULTIPLE_TEXT):
            guard raw.text_count != 0 else { throw .emptyItems }
            return .multipleText(try entry { () throws(EntryError) in try CApiString.requiredArray(raw.texts, count: raw.text_count) })
        case Int(NTK_CLIPBOARD_CONTENT_MULTI_REPRESENTATION):
            guard raw.representation_count != 0 else { throw .emptyItems }
            return .multiRepresentation(try representations(raw.representations, count: raw.representation_count))
        default:
            return try rejected("the content kind is out of range")
        }
    }

    /// Two of one type would be lost silently in the dictionary (part 2, 6.1; P2-15).
    private static func representations(_ pointer: UnsafePointer<ntk_clipboard_representation>?, count: Int) throws(ClipboardRejection) -> [String: Data] {
        let elements = try entry { () throws(EntryError) in try StructReader.readArray(pointer, count: count, reserved: []) }
        var result: [String: Data] = [:]
        for element in elements {
            let utType = try required(element.ut_type)
            guard result[utType] == nil else { return try rejected("a type appears twice in the representations") }
            result[utType] = try bytes(element.data, element.data_size)
        }
        return result
    }

    private static func required(_ text: UnsafePointer<CChar>?) throws(ClipboardRejection) -> String {
        try entry { () throws(EntryError) in try CApiString.required(text) }
    }

    private static func bytes(_ data: UnsafePointer<UInt8>?, _ count: Int) throws(ClipboardRejection) -> Data {
        try entry { () throws(EntryError) in try CApiBytes.copied(data, count: count) }
    }

    // MARK: - Options

    /// `ntk_clipboard_copy_options`: NULL and zero-filled are `.default`, with E-9's inverted name.
    static func options(_ pointer: UnsafePointer<ntk_clipboard_copy_options>?) throws(ClipboardRejection) -> ClipboardCopyOptions {
        CApiLog.clipboard.debug("[options] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        guard let raw = try entry({ () throws(EntryError) in try StructReader.readIfPresent(pointer, reserved: []) }) else {
            return .default
        }
        return try options(from: raw)
    }

    /// The seconds are read only with `has_expiration`. A date in the past is the library's.
    static func options(from raw: ntk_clipboard_copy_options) throws(ClipboardRejection) -> ClipboardCopyOptions {
        CApiLog.clipboard.debug("[options] notLocalOnly: \(raw.not_local_only, privacy: .public), hasExpiration: \(raw.has_expiration, privacy: .public)")
        guard raw.has_expiration != 0 else {
            return ClipboardCopyOptions(localOnly: raw.not_local_only == 0, expirationDate: nil)
        }
        guard raw.expiration_unix_seconds.isFinite else { return try rejected("the expiration is not finite") }
        return ClipboardCopyOptions(localOnly: raw.not_local_only == 0,
                                    expirationDate: Date(timeIntervalSince1970: raw.expiration_unix_seconds))
    }

    // MARK: - Types

    /// `ntk_clipboard_read_data_async`: a type that is not one is the library's.
    static func utType(_ text: UnsafePointer<CChar>?) throws(ClipboardRejection) -> String {
        CApiLog.clipboard.debug("[utType] text: \(text == nil ? "nil" : "provided", privacy: .public)")
        return try required(text)
    }

    /// `ntk_clipboard_get_snapshot_async`: no element means no matching at all.
    static func matchingTypes(_ types: UnsafePointer<UnsafePointer<CChar>?>?, count: Int) throws(ClipboardRejection) -> [String]? {
        CApiLog.clipboard.debug("[matchingTypes] types: \(types == nil ? "nil" : "provided", privacy: .public), count: \(count, privacy: .public)")
        let values = try entry { () throws(EntryError) in try CApiString.requiredArray(types, count: count) }
        return values.isEmpty ? nil : values
    }

    // MARK: - Load

    /// `ntk_clipboard_load_item_async`: `ut_type` is read only for FILE. A type no item has is the library's.
    static func loadRequest(kind: ntk_clipboard_item_kind, utType: UnsafePointer<CChar>?) throws(ClipboardRejection) -> ClipboardLoadRequest {
        CApiLog.clipboard.debug("[loadRequest] kind: \(kind, privacy: .public), utType: \(utType == nil ? "nil" : "provided", privacy: .public)")
        switch Int(kind) {
        case Int(NTK_CLIPBOARD_ITEM_TEXT): return .text
        case Int(NTK_CLIPBOARD_ITEM_URL): return .url
        case Int(NTK_CLIPBOARD_ITEM_IMAGE): return .image
        case Int(NTK_CLIPBOARD_ITEM_FILE): return .file(utType: try required(utType))
        default: return try rejected("the item kind is out of range")
        }
    }

    // MARK: - Patterns

    /// Bit by bit, in the order of the header.
    static let patternBits: [(bit: UInt32, pattern: ClipboardDetectionPattern)] = [
        (UInt32(NTK_CLIPBOARD_PATTERN_PROBABLE_WEB_URL), .probableWebURL),
        (UInt32(NTK_CLIPBOARD_PATTERN_PROBABLE_WEB_SEARCH), .probableWebSearch),
        (UInt32(NTK_CLIPBOARD_PATTERN_NUMBER), .number),
        (UInt32(NTK_CLIPBOARD_PATTERN_LINK), .link),
        (UInt32(NTK_CLIPBOARD_PATTERN_EMAIL_ADDRESS), .emailAddress),
        (UInt32(NTK_CLIPBOARD_PATTERN_PHONE_NUMBER), .phoneNumber),
        (UInt32(NTK_CLIPBOARD_PATTERN_POSTAL_ADDRESS), .postalAddress),
        (UInt32(NTK_CLIPBOARD_PATTERN_CALENDAR_EVENT), .calendarEvent),
        (UInt32(NTK_CLIPBOARD_PATTERN_FLIGHT_NUMBER), .flightNumber),
        (UInt32(NTK_CLIPBOARD_PATTERN_MONEY_AMOUNT), .moneyAmount),
        (UInt32(NTK_CLIPBOARD_PATTERN_SHIPMENT_TRACKING_NUMBER), .shipmentTrackingNumber),
    ]

    /// 0 is `EMPTY_PATTERNS` and an unknown bit is `INVALID_PARAMETER`, at the entry (part 2, 6.1).
    static func patterns(_ bits: ntk_clipboard_patterns) throws(ClipboardRejection) -> Set<ClipboardDetectionPattern> {
        CApiLog.clipboard.debug("[patterns] bits: \(bits, privacy: .public)")
        guard bits != 0 else { throw .emptyPatterns }
        var left = bits
        var patterns: Set<ClipboardDetectionPattern> = []
        for (bit, pattern) in patternBits where bits & bit != 0 {
            patterns.insert(pattern)
            left &= ~bit
        }
        guard left == 0 else { return try rejected("an unknown bit in the patterns") }
        return patterns
    }

    static func bits(of patterns: Set<ClipboardDetectionPattern>) -> ntk_clipboard_patterns {
        CApiLog.clipboard.debug("[bits] count: \(patterns.count, privacy: .public)")
        return patternBits.reduce(0) { patterns.contains($1.pattern) ? $0 | $1.bit : $0 }
    }

    // MARK: - Errors

    /// `errorCode` to the value (part 2, 11.3, P2-13). `IosLibrary` can add a case without the compiler
    /// saying so here; the contract check compares its cases with 11.3.
    static func error(forCode code: String?) -> ntk_clipboard_error {
        CApiLog.clipboard.debug("[error] code: \(code ?? "nil", privacy: .public)")
        guard let code, let value = errorValues[code] else {
            CApiLog.clipboard.error("[error] not in the table: \(code ?? "nil", privacy: .public)")
            return ntk_clipboard_error(NTK_CLIPBOARD_ERROR_UNKNOWN)
        }
        return value
    }

    private static let errorValues: [String: ntk_clipboard_error] = [
        "CLIPBOARD_INVALID_REQUEST": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_INVALID_PARAMETER),
        ClipboardError.unknownErrorCode: ntk_clipboard_error(NTK_CLIPBOARD_ERROR_UNKNOWN),
        "CLIPBOARD_EMPTY_CONTENT": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_EMPTY_CONTENT),
        "CLIPBOARD_EMPTY_ITEMS": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_EMPTY_ITEMS),
        "CLIPBOARD_INVALID_URL": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_INVALID_URI),
        "CLIPBOARD_UNAVAILABLE": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_UNAVAILABLE),
        "CLIPBOARD_EMPTY_PATTERNS": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_EMPTY_PATTERNS),
        "CLIPBOARD_INVALID_TYPE": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_INVALID_TYPE),
        "CLIPBOARD_INVALID_NAME": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_INVALID_NAME),
        "CLIPBOARD_INVALID_COLOR": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_INVALID_COLOR),
        "CLIPBOARD_INVALID_IMAGE_DATA": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_INVALID_IMAGE_DATA),
        "CLIPBOARD_INVALID_EXPIRATION": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_INVALID_EXPIRATION),
        "CLIPBOARD_CONTENT_TOO_LARGE": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_CONTENT_TOO_LARGE),
        "CLIPBOARD_FILE_NOT_FOUND": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_FILE_NOT_FOUND),
        "CLIPBOARD_IMAGE_LOAD_FAILED": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_IMAGE_LOAD_FAILED),
        "CLIPBOARD_IMAGE_ENCODE_FAILED": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_IMAGE_ENCODE_FAILED),
        "CLIPBOARD_CANNOT_REMOVE_GENERAL": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_CANNOT_REMOVE_GENERAL),
        "CLIPBOARD_NO_MATCHING_ITEM": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_NO_MATCHING_ITEM),
        "CLIPBOARD_LOAD_FAILED": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_LOAD_FAILED),
        "CLIPBOARD_UNEXPECTED_TYPE": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_UNEXPECTED_TYPE),
        "CLIPBOARD_FILE_COPY_FAILED": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_FILE_COPY_FAILED),
        "CLIPBOARD_CANCELLED": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_CANCELED),
        "CLIPBOARD_TIMED_OUT": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_TIMED_OUT),
        "CLIPBOARD_DETECTION_FAILED": ntk_clipboard_error(NTK_CLIPBOARD_ERROR_DETECTION_FAILED),
    ]
}
