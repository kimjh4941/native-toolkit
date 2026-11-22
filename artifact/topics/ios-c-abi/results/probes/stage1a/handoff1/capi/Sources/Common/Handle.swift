// Hand-off 1 probe: output handles (part 1, 5.7). One class per handle type (R-30).
import Foundation

/// NUL-terminated bytes owned by the handle.
class NTKStorage {
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

final class NTKString: NTKStorage {}
final class NTKBytes: NTKStorage {}

final class NTKStringList {
    let items: [NTKString]
    init(_ strings: [String]) { items = strings.map { NTKString(bytes: CApiString.outputUTF8($0)) } }
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

    static func makeString(_ value: String) -> OpaquePointer { make(NTKString(bytes: CApiString.outputUTF8(value))) }
}

enum CommonReceiver {
    static func stringData(_ s: OpaquePointer?) -> UnsafePointer<CChar>? {
        Handle.borrow(s, as: NTKString.self).map { UnsafeRawPointer($0.storage).assumingMemoryBound(to: CChar.self) }
    }
    static func stringSize(_ s: OpaquePointer?) -> Int { Handle.borrow(s, as: NTKString.self)?.count ?? 0 }
    static func bytesData(_ b: OpaquePointer?) -> UnsafePointer<UInt8>? { Handle.borrow(b, as: NTKBytes.self).map { UnsafePointer($0.storage) } }
    static func bytesSize(_ b: OpaquePointer?) -> Int { Handle.borrow(b, as: NTKBytes.self)?.count ?? 0 }
    static func listCount(_ list: OpaquePointer?) -> Int { Handle.borrow(list, as: NTKStringList.self)?.items.count ?? 0 }
    static func listAt(_ list: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        guard let items = Handle.borrow(list, as: NTKStringList.self)?.items, index >= 0, index < items.count else { return nil }
        outSize?.pointee = items[index].count
        return UnsafeRawPointer(items[index].storage).assumingMemoryBound(to: CChar.self)
    }
}
