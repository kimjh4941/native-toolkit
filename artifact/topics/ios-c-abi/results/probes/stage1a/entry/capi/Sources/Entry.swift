// Stage 1a prototype: the C entry points, written with @c @implementation (SE-0495, Swift 6.3).
// The compiler checks each signature against the hand-written header. The functions must be
// public: an internal @c function gets a private-external (hidden) symbol and does not leave the
// dylib, whatever the export list says. The Swift name must be the C name.
import Foundation
internal import NTKCApiInternal

@c @implementation public func ntk_version() -> UInt32 { UInt32(NTK_VERSION) }
@c @implementation public func ntk_last_system_code() -> UInt32 { ntkc_tls_get() }

@c @implementation public func ntk_string_data(_ s: OpaquePointer?) -> UnsafePointer<CChar>? { Receivers.stringData(s) }
@c @implementation public func ntk_string_size(_ s: OpaquePointer?) -> Int { Receivers.stringSize(s) }
@c @implementation public func ntk_string_free(_ s: OpaquePointer?) { Handle.free(s) }
@c @implementation public func ntk_bytes_data(_ b: OpaquePointer?) -> UnsafePointer<UInt8>? { Receivers.bytesData(b) }
@c @implementation public func ntk_bytes_size(_ b: OpaquePointer?) -> Int { Receivers.stringSize(b) }
@c @implementation public func ntk_bytes_free(_ b: OpaquePointer?) { Handle.free(b) }
@c @implementation public func ntk_string_list_count(_ list: OpaquePointer?) -> Int { Receivers.listCount(list) }
@c @implementation public func ntk_string_list_at(_ list: OpaquePointer?, _ index: Int,
                                                  _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    Receivers.listAt(list, index, outSize)
}
@c @implementation public func ntk_string_list_free(_ list: OpaquePointer?) { Handle.free(list) }

@c @implementation
public func ntk_probe_echo(_ request: UnsafePointer<ntk_probe_echo_request>?,
                           _ outText: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_probe_error {
    ProbeImpl.echo(request, outText)
}

@c @implementation
public func ntk_probe_clipboard_read_text_async(_ callback: ntk_probe_text_fn?, _ userData: UnsafeMutableRawPointer?,
                                                _ release: ntk_release_fn?,
                                                _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_probe_error {
    ProbeImpl.clipboardReadTextAsync(callback, userData, release, outRequestId)
}

@c @implementation
public func ntk_probe_raise_uikit_exception_async(_ kind: ntk_probe_exception_kind, _ callback: ntk_probe_done_fn?,
                                                  _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                                  _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_probe_error {
    ProbeImpl.raiseUIKitExceptionAsync(kind, callback, userData, release, outRequestId)
}
