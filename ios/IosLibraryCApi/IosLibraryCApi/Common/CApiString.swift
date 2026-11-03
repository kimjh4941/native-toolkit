//
//  CApiString.swift
//  IosLibraryCApi
//

/// The text the C ABI hands out (part 1, 5.9). Reading the caller's strings comes with the first
/// function that takes one (TB-2).
enum CApiString {
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
