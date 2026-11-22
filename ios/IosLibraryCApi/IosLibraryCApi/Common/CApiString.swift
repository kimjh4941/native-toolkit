//
//  CApiString.swift
//  IosLibraryCApi
//

/// The text of the C ABI, in and out (part 1, 5.9).
enum CApiString {
    // MARK: - In: NUL-terminated strict UTF-8 (RFC 3629). What fails is `EntryError.invalidParameter`.

    /// A value that must be there: NULL is rejected like invalid UTF-8.
    static func required(_ text: UnsafePointer<CChar>?) throws(EntryError) -> String {
        CApiLog.common.debug("[required] text: \(text == nil ? "nil" : "provided", privacy: .public)")
        guard let text else {
            CApiLog.common.error("[required] rejected: NULL")
            throw .invalidParameter
        }
        return try validated(text)
    }

    /// A value that may be left out: NULL is "no value" and `""` is an empty value (E-15).
    static func optional(_ text: UnsafePointer<CChar>?) throws(EntryError) -> String? {
        CApiLog.common.debug("[optional] text: \(text == nil ? "nil" : "provided", privacy: .public)")
        guard let text else { return nil }
        return try validated(text)
    }

    /// Any other value: NULL is `""` (E-15).
    static func orEmpty(_ text: UnsafePointer<CChar>?) throws(EntryError) -> String {
        CApiLog.common.debug("[orEmpty] text: \(text == nil ? "nil" : "provided", privacy: .public)")
        guard let text else { return "" }
        return try validated(text)
    }

    /// An array of values that must be there (`const char* const*` and `size_t`). A `count` above `Int.max`
    /// arrives negative. No element means no read, also for NULL: whether an empty array is allowed is
    /// the caller's. A NULL element is rejected.
    static func requiredArray(_ texts: UnsafePointer<UnsafePointer<CChar>?>?, count: Int) throws(EntryError) -> [String] {
        CApiLog.common.debug("[requiredArray] texts: \(texts == nil ? "nil" : "provided", privacy: .public), count: \(count, privacy: .public)")
        guard count >= 0 else {
            CApiLog.common.error("[requiredArray] rejected: count \(count, privacy: .public)")
            throw .invalidParameter
        }
        guard count > 0 else { return [] }
        guard let texts else {
            CApiLog.common.error("[requiredArray] rejected: NULL with count \(count, privacy: .public)")
            throw .invalidParameter
        }
        // No array is this long: reading it would walk off the caller's memory.
        let stride = MemoryLayout<UnsafePointer<CChar>?>.stride
        guard !count.multipliedReportingOverflow(by: stride).overflow else {
            CApiLog.common.error("[requiredArray] rejected: count \(count, privacy: .public) with stride \(stride, privacy: .public)")
            throw .invalidParameter
        }
        var values: [String] = []
        for index in 0..<count {
            values.append(try required(texts[index]))
        }
        return values
    }

    /// The text may be a secret: only the fact that it failed is logged.
    private static func validated(_ text: UnsafePointer<CChar>) throws(EntryError) -> String {
        guard let value = String(validatingCString: text) else {
            CApiLog.common.error("[validated] rejected: not UTF-8")
            throw .invalidParameter
        }
        return value
    }

    // MARK: - Out

    /// NUL-terminated UTF-8 without the terminator; it never fails. U+0000 becomes U+FFFD, so that
    /// the C string is not cut short. An unpaired surrogate of a bridged `NSString` has already
    /// become U+FFFD in `unicodeScalars`: `-[NSString UTF8String]` would give NULL for it instead.
    static func outputUTF8(_ value: String) -> [UInt8] {
        CApiLog.common.debug("[outputUTF8] length: \(value.utf8.count, privacy: .public)")
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            bytes.append(contentsOf: (scalar == "\0" ? "\u{FFFD}" : scalar).utf8)
        }
        return bytes
    }
}
