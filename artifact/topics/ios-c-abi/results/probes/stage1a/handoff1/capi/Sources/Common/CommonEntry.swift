// Hand-off 1 probe: Common.h entry points (@c @implementation, P1-1). Only these files are public.
import Foundation

@c @implementation public func ntk_version() -> UInt32 { UInt32(NTK_VERSION) }
/// Always 0 on iOS (D-13, DF-6): no thread-local storage.
@c @implementation public func ntk_last_system_code() -> UInt32 { 0 }

@c @implementation public func ntk_string_data(_ s: OpaquePointer?) -> UnsafePointer<CChar>? { CommonReceiver.stringData(s) }
@c @implementation public func ntk_string_size(_ s: OpaquePointer?) -> Int { CommonReceiver.stringSize(s) }
@c @implementation public func ntk_string_free(_ s: OpaquePointer?) { Handle.free(s) }
@c @implementation public func ntk_bytes_data(_ b: OpaquePointer?) -> UnsafePointer<UInt8>? { CommonReceiver.bytesData(b) }
@c @implementation public func ntk_bytes_size(_ b: OpaquePointer?) -> Int { CommonReceiver.bytesSize(b) }
@c @implementation public func ntk_bytes_free(_ b: OpaquePointer?) { Handle.free(b) }
@c @implementation public func ntk_string_list_count(_ list: OpaquePointer?) -> Int { CommonReceiver.listCount(list) }
@c @implementation public func ntk_string_list_at(_ list: OpaquePointer?, _ index: Int,
                                                  _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    CommonReceiver.listAt(list, index, outSize)
}
@c @implementation public func ntk_string_list_free(_ list: OpaquePointer?) { Handle.free(list) }
