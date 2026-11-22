//
//  CApiBytes.swift
//  IosLibraryCApi
//

import Foundation

/// The bytes of the C ABI, in (part 1, 5.9).
enum CApiBytes {
    /// A copy of `const uint8_t*` and `size_t`. A size above `Int.max` arrives negative. What fails is
    /// `EntryError.invalidParameter`. The bytes may be a secret, so only the size is logged.
    static func copied(_ bytes: UnsafePointer<UInt8>?, count: Int) throws(EntryError) -> Data {
        CApiLog.common.debug("[copied] bytes: \(bytes == nil ? "nil" : "provided", privacy: .public), count: \(count, privacy: .public)")
        guard count >= 0 else {
            CApiLog.common.error("[copied] rejected: count \(count, privacy: .public)")
            throw .invalidParameter
        }
        guard count > 0 else { return Data() }
        guard let bytes else {
            CApiLog.common.error("[copied] rejected: NULL with count \(count, privacy: .public)")
            throw .invalidParameter
        }
        return Data(bytes: bytes, count: count)
    }
}
