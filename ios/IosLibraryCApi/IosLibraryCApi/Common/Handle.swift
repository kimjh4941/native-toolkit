//
//  Handle.swift
//  IosLibraryCApi
//

/// The bytes behind an output handle: owned by it, immutable, always followed by a NUL, so that the
/// pointer is not NULL for an empty value (part 1, 5.9).
final class HandleBuffer {
    let storage: UnsafeMutablePointer<UInt8>
    let count: Int

    init(_ bytes: some Collection<UInt8>) {
        count = bytes.count
        storage = .allocate(capacity: count + 1)
        _ = UnsafeMutableBufferPointer(start: storage, count: count).initialize(from: bytes)
        storage[count] = 0
    }

    deinit {
        storage.deallocate()
    }

    var text: UnsafePointer<CChar> {
        UnsafeRawPointer(storage).assumingMemoryBound(to: CChar.self)
    }
}

// One class per handle type, so that reading a handle as another type gives NULL or 0 although the
// contract leaves that undefined (part 1, chapter 6).

/// What an `ntk_string*` points to.
final class StringHandle {
    let buffer: HandleBuffer

    init(_ value: String) {
        buffer = HandleBuffer(CApiString.outputUTF8(value))
    }
}

/// What an `ntk_bytes*` points to.
final class BytesHandle {
    let buffer: HandleBuffer

    init(_ value: some Collection<UInt8>) {
        buffer = HandleBuffer(value)
    }
}

/// What an `ntk_string_list*` points to.
final class StringListHandle {
    let items: [HandleBuffer]

    init(_ values: [String]) {
        items = values.map { HandleBuffer(CApiString.outputUTF8($0)) }
    }
}

/// The output handles of Common.h. A handle is an object retained for the caller until its `_free`.
/// Reads and frees are not logged (part 1, 5.15); the values themselves are never logged.
enum Handle {
    static func makeString(_ value: String) -> OpaquePointer {
        CApiLog.common.debug("[makeString] length: \(value.utf8.count, privacy: .public)")
        return retained(StringHandle(value))
    }

    static func makeBytes(_ value: some Collection<UInt8>) -> OpaquePointer {
        CApiLog.common.debug("[makeBytes] count: \(value.count, privacy: .public)")
        return retained(BytesHandle(value))
    }

    static func makeStringList(_ values: [String]) -> OpaquePointer {
        CApiLog.common.debug("[makeStringList] count: \(values.count, privacy: .public)")
        return retained(StringListHandle(values))
    }

    /// The object of a handle without changing who owns it, or nil for NULL and for a handle of another type.
    static func borrow<T: AnyObject>(_ handle: OpaquePointer?, as type: T.Type) -> T? {
        guard let handle else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(handle)).takeUnretainedValue() as? T
    }

    static func free(_ handle: OpaquePointer?) {
        guard let handle else { return }
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(handle)).release()
    }

    static func stringData(_ handle: OpaquePointer?) -> UnsafePointer<CChar>? {
        borrow(handle, as: StringHandle.self)?.buffer.text
    }

    static func stringSize(_ handle: OpaquePointer?) -> Int {
        borrow(handle, as: StringHandle.self)?.buffer.count ?? 0
    }

    static func bytesData(_ handle: OpaquePointer?) -> UnsafePointer<UInt8>? {
        borrow(handle, as: BytesHandle.self).map { UnsafePointer($0.buffer.storage) }
    }

    static func bytesSize(_ handle: OpaquePointer?) -> Int {
        borrow(handle, as: BytesHandle.self)?.buffer.count ?? 0
    }

    static func stringListCount(_ handle: OpaquePointer?) -> Int {
        borrow(handle, as: StringListHandle.self)?.items.count ?? 0
    }

    /// `size_t` arrives as `Int`: an index above `Int.max` is negative here, and out of range like any other.
    /// With no item, `outSize` becomes 0 as on Windows and Android: a caller may use it without looking
    /// at the pointer.
    static func stringListAt(_ handle: OpaquePointer?, _ index: Int,
                             _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        guard let items = borrow(handle, as: StringListHandle.self)?.items, items.indices.contains(index) else {
            return text(of: nil, outSize)
        }
        return text(of: items[index], outSize)
    }

    /// What a reader with an `out_size` returns for a value of a handle, or for no value (NULL and 0).
    static func text(of buffer: HandleBuffer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        outSize?.pointee = buffer?.count ?? 0
        return buffer?.text
    }

    /// A handle for `object`, which the caller owns until its `_free`. A feature's handle is a class of its own.
    static func retained(_ object: AnyObject) -> OpaquePointer {
        CApiLog.common.debug("[retained] object: provided")
        return OpaquePointer(Unmanaged.passRetained(object).toOpaque())
    }
}
