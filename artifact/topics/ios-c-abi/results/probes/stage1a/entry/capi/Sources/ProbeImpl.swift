// Stage 1a prototype: the Swift receivers of Probe.h. They call IosLibrary and convert types only.
import Foundation
import IosLibrary
import UIKit
internal import NTKCApiInternal

/// A named pasteboard, so that the probe never syncs with the Mac pasteboard of the simulator host.
/// The caller creates it first (UIPasteboard(name:create: true)); IosLibrary looks it up with create: false.
let probePasteboardName = "com.jonghyunkim.nativetoolkit.stage1a.probe"

/// Probe-only value for ntk_last_system_code, so that the per-thread storage can be observed.
/// The real library keeps it at 0 (D-13).
let probeSystemCodeInvalidUTF8: UInt32 = 0xE0F

private func code(_ value: Int) -> ntk_probe_error { ntk_probe_error(value) }

enum ProbeImpl {
    /// Rejected at the entry: release runs on the calling thread before the function returns (E-12).
    private static func reject(_ error: Int, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_probe_error {
        release?(userData)
        return code(error)
    }

    static func echo(_ request: UnsafePointer<ntk_probe_echo_request>?,
                     _ outText: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_probe_error {
        ntkc_tls_set(0)
        guard let request, let outText else { return code(NTK_PROBE_ERROR_INVALID_PARAMETER) }
        outText.pointee = nil
        // struct_size (Windows design 7.8): at least the size of the first version; larger sizes
        // are accepted and only the known prefix is read.
        let known = MemoryLayout<ntk_probe_echo_request>.size
        let size = Int(UnsafeRawPointer(request).load(as: UInt32.self))
        guard size >= known else { return code(NTK_PROBE_ERROR_INVALID_PARAMETER) }
        var copy = ntk_probe_echo_request()
        withUnsafeMutableBytes(of: &copy) { $0.copyMemory(from: UnsafeRawBufferPointer(start: request, count: known)) }
        guard let text = CApiString.input(copy.text) else {
            ntkc_tls_set(probeSystemCodeInvalidUTF8)
            return code(NTK_PROBE_ERROR_INVALID_PARAMETER)
        }
        let ns = (text ?? "") as NSString
        outText.pointee = CApiString.makeHandle(copy.uppercase != 0 ? ns.uppercased : String(ns))
        return code(NTK_PROBE_ERROR_NONE)
    }

    static func clipboardReadTextAsync(_ callback: ntk_probe_text_fn?, _ userData: UnsafeMutableRawPointer?,
                                       _ release: ntk_release_fn?, _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_probe_error {
        guard let callback else { return reject(NTK_PROBE_ERROR_INVALID_PARAMETER, userData, release) }
        let pending = Pending(callback: callback, userData: userData, release: release, requestId: nextRequestId())
        outRequestId?.pointee = pending.requestId
        // Always queued, also when called on the main thread (D-6 / AC-5).
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                IosClipboardManager.shared.read(scope: .named(probePasteboardName)) { ok, result, _, _ in
                    let deliver: @Sendable () -> Void = {
                        pending.finish { callback, userData, requestId in
                            if ok {
                                let text = result?.items.first(where: { $0.text != nil })?.text ?? ""
                                callback(userData, requestId, code(NTK_PROBE_ERROR_NONE), 0, CApiString.makeHandle(text))
                            } else {
                                callback(userData, requestId, code(NTK_PROBE_ERROR_READ_FAILED), 0, nil)
                            }
                        }
                    }
                    if Thread.isMainThread { deliver() } else { DispatchQueue.main.async(execute: deliver) }
                }
            }
        }
        return code(NTK_PROBE_ERROR_NONE)
    }

    static func raiseUIKitExceptionAsync(_ kind: ntk_probe_exception_kind, _ callback: ntk_probe_done_fn?,
                                         _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                         _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_probe_error {
        guard let callback else { return reject(NTK_PROBE_ERROR_INVALID_PARAMETER, userData, release) }
        let pending = Pending(callback: callback, userData: userData, release: release, requestId: nextRequestId())
        outRequestId?.pointee = pending.requestId
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                switch Int(kind) {
                case NTK_PROBE_EXCEPTION_ALERT_TEXT_FIELD:
                    let sheet = UIAlertController(title: "probe", message: nil, preferredStyle: .actionSheet)
                    sheet.addTextField(configurationHandler: nil)   // UIKit raises NSInternalInconsistencyException
                case NTK_PROBE_EXCEPTION_POPOVER_NO_ANCHOR:
                    let sheet = UIAlertController(title: "probe", message: nil, preferredStyle: .actionSheet)
                    sheet.addAction(UIAlertAction(title: "OK", style: .default))
                    let root = UIApplication.shared.connectedScenes
                        .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
                    root?.present(sheet, animated: false)            // iPad: popover without an anchor
                default:
                    break
                }
                pending.finish { callback, userData, requestId in
                    callback(userData, requestId, code(NTK_PROBE_ERROR_NONE), 0)
                }
            }
        }
        return code(NTK_PROBE_ERROR_NONE)
    }
}
