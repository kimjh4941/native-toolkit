//
//  StructReader.swift
//  IosLibraryCApi
//

/// Reads the input structs that start with `struct_size` (part 1, 1.1; the Windows C ABI design, 7.8):
///
/// 1. `struct_size`, `reserved0`, and every other reserved field: a reserved field that is not 0 is
///    `invalidParameter`.
/// 2. The minimum is the size of 2.0.0 and the maximum is 4096 bytes: outside them is `invalidParameter`,
///    found before anything else of the struct is read.
/// 3. A field is read only when `struct_size` covers it; the others are 0. A struct grows by 8 bytes at a
///    time (rule 5), so a `struct_size` below the size known here counts in whole 8-byte units: a field
///    that it covers only in part stays 0.
/// 4. The part beyond the size known here: all 0 is accepted, any other byte is `notSupported`, so that
///    a newer field is never dropped silently.
/// 5. A struct grows by multiples of 8 bytes, so that its `sizeof` changes. That is for whoever adds a
///    field: `struct_size` itself is not checked for it.
///
/// Nothing here reads past `struct_size`, and every read may be unaligned: in an array the elements are
/// as far apart as the caller says. The caller maps the thrown value to its feature's error, and calls
/// release (`Entry.reject`).
enum StructReader {
    static let maximumSize = 4096

    private static let reserved0Offset = 4
    private static let headerSize = 8
    private static let growthUnit = 8

    /// The struct at `pointer`; NULL is `invalidParameter`. `minimumSize` is the 2.0.0 `sizeof`, which a
    /// `T` that gained fields passes on (rule 2). `reserved` names the reserved fields other than
    /// `reserved0`, or is empty: it is required, since one left out would not be checked (rule 1).
    static func read<T>(_ pointer: UnsafePointer<T>?, minimumSize: Int = MemoryLayout<T>.size,
                        reserved: [KeyPath<T, UInt32>]) throws(EntryError) -> T {
        CApiLog.common.debug("[read] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public), minimumSize: \(minimumSize, privacy: .public), reserved: \(reserved.count, privacy: .public)")
        guard let pointer else {
            CApiLog.common.error("[read] rejected: NULL")
            throw .invalidParameter
        }
        let raw = UnsafeRawPointer(pointer)
        return try element(at: raw, size: checkedSize(at: raw, minimumSize: minimumSize), reserved: reserved)
    }

    /// The same for a struct that may be left out: NULL is nil, for the caller's defaults.
    static func readIfPresent<T>(_ pointer: UnsafePointer<T>?, minimumSize: Int = MemoryLayout<T>.size,
                                 reserved: [KeyPath<T, UInt32>]) throws(EntryError) -> T? {
        CApiLog.common.debug("[readIfPresent] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public), minimumSize: \(minimumSize, privacy: .public), reserved: \(reserved.count, privacy: .public)")
        guard let pointer else { return nil }
        return try read(pointer, minimumSize: minimumSize, reserved: reserved)
    }

    /// The array at `pointer` (P2-5): the rules above for each element. The first element's `struct_size`
    /// is the step to the next one, and an element of another size is `invalidParameter`.
    ///
    /// `count` is a `size_t` as Swift imports it, so above `Int.max` it is negative. No element means no
    /// read, also for NULL: whether an empty array is allowed is the caller's (`EMPTY_ITEMS` and the like).
    static func readArray<T>(_ pointer: UnsafePointer<T>?, count: Int, minimumSize: Int = MemoryLayout<T>.size,
                             reserved: [KeyPath<T, UInt32>]) throws(EntryError) -> [T] {
        CApiLog.common.debug("[readArray] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public), count: \(count, privacy: .public), minimumSize: \(minimumSize, privacy: .public), reserved: \(reserved.count, privacy: .public)")
        guard count >= 0 else {
            CApiLog.common.error("[readArray] rejected: count \(count, privacy: .public)")
            throw .invalidParameter
        }
        guard count > 0 else { return [] }
        guard let pointer else {
            CApiLog.common.error("[readArray] rejected: NULL with count \(count, privacy: .public)")
            throw .invalidParameter
        }
        let first = UnsafeRawPointer(pointer)
        let step = try checkedSize(at: first, minimumSize: minimumSize)
        // With this in range, no offset below overflows.
        guard !count.multipliedReportingOverflow(by: step).overflow else {
            CApiLog.common.error("[readArray] rejected: count \(count, privacy: .public) with step \(step, privacy: .public)")
            throw .invalidParameter
        }
        var elements: [T] = []
        for index in 0..<count {
            let raw = first + index * step
            guard try checkedSize(at: raw, minimumSize: minimumSize) == step else {
                CApiLog.common.error("[readArray] rejected: element \(index, privacy: .public) is not of size \(step, privacy: .public)")
                throw .invalidParameter
            }
            elements.append(try element(at: raw, size: step, reserved: reserved))
        }
        return elements
    }

    /// Rule 2. Only the 4 bytes of `struct_size` are read.
    private static func checkedSize(at raw: UnsafeRawPointer, minimumSize: Int) throws(EntryError) -> Int {
        let size = Int(raw.loadUnaligned(as: UInt32.self))
        guard size >= max(minimumSize, headerSize), size <= maximumSize else {
            CApiLog.common.error("[checkedSize] rejected: struct_size \(size, privacy: .public), minimum \(minimumSize, privacy: .public)")
            throw .invalidParameter
        }
        return size
    }

    /// Rules 1, 3 and 4, for a `size` that passed `checkedSize`.
    private static func element<T>(at raw: UnsafeRawPointer, size: Int, reserved: [KeyPath<T, UInt32>]) throws(EntryError) -> T {
        guard raw.loadUnaligned(fromByteOffset: reserved0Offset, as: UInt32.self) == 0 else {
            CApiLog.common.error("[element] rejected: reserved0")
            throw .invalidParameter
        }
        let known = MemoryLayout<T>.size
        let covered = size < known ? size - size % growthUnit : known
        let value = withUnsafeTemporaryAllocation(byteCount: known, alignment: MemoryLayout<T>.alignment) { memory -> T in
            memory.initializeMemory(as: UInt8.self, repeating: 0)
            memory.copyMemory(from: UnsafeRawBufferPointer(start: raw, count: covered))
            return memory.load(as: T.self)
        }
        guard reserved.allSatisfy({ value[keyPath: $0] == 0 }) else {
            CApiLog.common.error("[element] rejected: a reserved field")
            throw .invalidParameter
        }
        if size > known {
            for offset in known..<size where raw.load(fromByteOffset: offset, as: UInt8.self) != 0 {
                CApiLog.common.error("[element] not supported: byte \(offset, privacy: .public) of \(size, privacy: .public) is not 0")
                throw .notSupported
            }
        }
        return value
    }
}
