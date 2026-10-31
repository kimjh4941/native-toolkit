// Hand-off 1 probe: ProbeShare.h entry points.
import Foundation

@c @implementation
public func ntk_probe_share_text(_ text: UnsafePointer<CChar>?, _ callback: ntk_probe_share_done_fn?,
                                 _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_probe_share_error {
    ShareReceiver.shareText(text, callback, userData, release)
}
