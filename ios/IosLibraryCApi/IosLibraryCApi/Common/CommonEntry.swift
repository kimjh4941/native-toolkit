//
//  CommonEntry.swift
//  IosLibraryCApi
//

// The entry points of Common.h (C ABI design part 1, 5.3). Only @c @implementation functions, whose
// types the compiler checks against the header; what they do is in Handle.swift.

@c @implementation
public func ntk_version() -> UInt32 {
    UInt32(NTK_VERSION)
}

// D-13: nothing on iOS reports a system code here; the details of a failure go to os_log.
@c @implementation
public func ntk_last_system_code() -> UInt32 {
    0
}

@c @implementation
public func ntk_string_data(_ s: OpaquePointer?) -> UnsafePointer<CChar>? {
    Handle.stringData(s)
}

@c @implementation
public func ntk_string_size(_ s: OpaquePointer?) -> Int {
    Handle.stringSize(s)
}

@c @implementation
public func ntk_string_free(_ s: OpaquePointer?) {
    Handle.free(s)
}

@c @implementation
public func ntk_bytes_data(_ b: OpaquePointer?) -> UnsafePointer<UInt8>? {
    Handle.bytesData(b)
}

@c @implementation
public func ntk_bytes_size(_ b: OpaquePointer?) -> Int {
    Handle.bytesSize(b)
}

@c @implementation
public func ntk_bytes_free(_ b: OpaquePointer?) {
    Handle.free(b)
}

@c @implementation
public func ntk_string_list_count(_ list: OpaquePointer?) -> Int {
    Handle.stringListCount(list)
}

@c @implementation
public func ntk_string_list_at(_ list: OpaquePointer?, _ index: Int,
                               _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    Handle.stringListAt(list, index, outSize)
}

@c @implementation
public func ntk_string_list_free(_ list: OpaquePointer?) {
    Handle.free(list)
}
