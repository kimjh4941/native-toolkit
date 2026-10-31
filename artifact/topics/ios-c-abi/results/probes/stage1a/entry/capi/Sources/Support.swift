// Stage 1a prototype: the Swift receivers' common parts (handles, strings, request bookkeeping).
// Shared by the @c @implementation entry (Entry.swift) and the fallback table (fallback/Table.swift).
import Foundation
import Synchronization

/// Storage behind ntk_string / ntk_bytes: NUL-terminated bytes owned by the box.
final class NTKBuffer {
    let storage: UnsafeMutablePointer<UInt8>
    let count: Int

    init(bytes: some Collection<UInt8>) {
        count = bytes.count
        storage = .allocate(capacity: count + 1)
        _ = UnsafeMutableBufferPointer(start: storage, count: count).initialize(from: bytes)
        storage[count] = 0
    }

    deinit { storage.deallocate() }
}

final class NTKStringList {
    let items: [NTKBuffer]
    init(_ strings: [String]) { items = strings.map { NTKBuffer(bytes: CApiString.outputUTF8($0)) } }
}

enum Handle {
    static func make(_ object: AnyObject) -> OpaquePointer {
        OpaquePointer(Unmanaged.passRetained(object).toOpaque())
    }

    static func borrow<T: AnyObject>(_ handle: OpaquePointer?, as type: T.Type) -> T? {
        guard let handle else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(handle)).takeUnretainedValue() as? T
    }

    static func free(_ handle: OpaquePointer?) {
        guard let handle else { return }
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(handle)).release()
    }
}

enum CApiString {
    /// Strict input rule (E-7): NULL is .some(nil), invalid UTF-8 is nil (rejected).
    static func input(_ pointer: UnsafePointer<CChar>?) -> String?? {
        guard let pointer else { return .some(nil) }
        guard let value = String(validatingCString: pointer) else { return nil }
        return .some(value)
    }

    /// Output rule (E-16 / AC-19): never fails; U+0000 and ill-formed UTF-16 become U+FFFD.
    /// Swift's String already repairs unpaired surrogates of a bridged NSString while it
    /// transcodes to UTF-8; U+0000 is replaced here so that the C string is not cut short.
    static func outputUTF8(_ value: String) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            let s = scalar.value == 0 ? Unicode.Scalar(0xFFFD)! : scalar
            bytes.append(contentsOf: UTF8.encode(s)!)
        }
        return bytes
    }

    static func makeHandle(_ value: String) -> OpaquePointer {
        Handle.make(NTKBuffer(bytes: outputUTF8(value)))
    }
}

/// The receivers of Common.h's handle functions.
enum Receivers {
    static func stringData(_ s: OpaquePointer?) -> UnsafePointer<CChar>? {
        guard let buffer = Handle.borrow(s, as: NTKBuffer.self) else { return nil }
        return UnsafeRawPointer(buffer.storage).assumingMemoryBound(to: CChar.self)
    }

    static func bytesData(_ b: OpaquePointer?) -> UnsafePointer<UInt8>? {
        Handle.borrow(b, as: NTKBuffer.self).map { UnsafePointer($0.storage) }
    }

    static func stringSize(_ s: OpaquePointer?) -> Int {
        Handle.borrow(s, as: NTKBuffer.self)?.count ?? 0
    }

    static func listCount(_ list: OpaquePointer?) -> Int {
        Handle.borrow(list, as: NTKStringList.self)?.items.count ?? 0
    }

    static func listAt(_ list: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        guard let items = Handle.borrow(list, as: NTKStringList.self)?.items, index >= 0, index < items.count else { return nil }
        outSize?.pointee = items[index].count
        return UnsafeRawPointer(items[index].storage).assumingMemoryBound(to: CChar.self)
    }
}

private let requestIds = Atomic<UInt64>(0)

func nextRequestId() -> UInt64 {
    requestIds.wrappingAdd(1, ordering: .relaxed).newValue
}

/// What a queued block needs from the caller. C function pointers and user_data cross to the
/// main thread unchanged; the caller owns their thread safety (C ABI contract).
struct Pending<Callback>: @unchecked Sendable {
    let callback: Callback
    let userData: UnsafeMutableRawPointer?
    let release: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    let requestId: UInt64

    /// Ends the request: release exactly once, after the callback, on the main thread.
    func finish(_ body: (Callback, UnsafeMutableRawPointer?, UInt64) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        body(callback, userData, requestId)
        release?(userData)
    }
}
