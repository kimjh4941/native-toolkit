// Hand-off 1 probe: ProbeDialog.h entry points.
import Foundation

@c @implementation
public func ntk_probe_dialog_show_alert(_ title: UnsafePointer<CChar>?, _ message: UnsafePointer<CChar>?,
                                        _ positiveText: UnsafePointer<CChar>?, _ negativeText: UnsafePointer<CChar>?,
                                        _ callback: ntk_probe_dialog_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                        _ release: ntk_release_fn?, _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_probe_dialog_error {
    DialogReceiver.showAlert(title, message, positiveText, negativeText, callback, userData, release, outRequestId)
}

@c @implementation
public func ntk_probe_dialog_cancel(_ requestId: UInt64) -> ntk_probe_dialog_error {
    DialogReceiver.cancel(requestId)
}
