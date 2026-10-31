// Hand-off 1 probe: Probe.h entry points.
import Foundation

@c @implementation
public func ntk_probe_echo(_ request: UnsafePointer<ntk_probe_echo_request>?,
                           _ outText: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_probe_error {
    ProbeReceiver.echo(request, outText)
}

@c @implementation
public func ntk_probe_clipboard_read_text_async(_ callback: ntk_probe_text_fn?, _ userData: UnsafeMutableRawPointer?,
                                                _ release: ntk_release_fn?,
                                                _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_probe_error {
    ProbeReceiver.clipboardReadTextAsync(callback, userData, release, outRequestId)
}

@c @implementation
public func ntk_probe_raise_uikit_exception_async(_ kind: ntk_probe_exception_kind, _ callback: ntk_probe_done_fn?,
                                                  _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                                  _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_probe_error {
    ProbeReceiver.raiseUIKitExceptionAsync(kind, callback, userData, release, outRequestId)
}
