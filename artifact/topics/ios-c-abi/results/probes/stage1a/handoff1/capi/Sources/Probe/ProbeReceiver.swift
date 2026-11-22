// Hand-off 1 probe: receivers of Probe.h (the entry prototype's three functions on the 5.7 registry).
import Foundation
import IosLibrary
import UIKit

/// The caller creates it first (UIPasteboard(name:create: true)); IosLibrary looks it up with create: false.
let probePasteboardName = "com.jonghyunkim.nativetoolkit.stage1a.probe"

private func code(_ value: Int) -> ntk_probe_error { ntk_probe_error(value) }

final class TextRegistration: Registration, @unchecked Sendable {
    let callback: ntk_probe_text_fn
    init(_ callback: @escaping ntk_probe_text_fn, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) {
        self.callback = callback
        super.init(id: Registry.nextId(), userData: userData, release: release)
    }
}

final class DoneRegistration: Registration, @unchecked Sendable {
    let callback: ntk_probe_done_fn
    init(_ callback: @escaping ntk_probe_done_fn, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) {
        self.callback = callback
        super.init(id: Registry.nextId(), userData: userData, release: release)
    }
}

enum ProbeReceiver {
    private static func reject(_ error: Int, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_probe_error {
        release?(userData)
        return code(error)
    }

    static func echo(_ request: UnsafePointer<ntk_probe_echo_request>?, _ outText: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_probe_error {
        outText?.pointee = nil
        guard let request, let outText else { return code(NTK_PROBE_ERROR_INVALID_PARAMETER) }
        let known = MemoryLayout<ntk_probe_echo_request>.size
        let size = Int(UnsafeRawPointer(request).load(as: UInt32.self))
        guard size >= known, size <= 4096 else { return code(NTK_PROBE_ERROR_INVALID_PARAMETER) }
        var copy = ntk_probe_echo_request()
        withUnsafeMutableBytes(of: &copy) { $0.copyMemory(from: UnsafeRawBufferPointer(start: request, count: known)) }
        let text: String
        switch CApiString.input(copy.text) {
        case .invalid: return code(NTK_PROBE_ERROR_INVALID_PARAMETER)
        case .absent: text = ""
        case .value(let value): text = value
        }
        outText.pointee = Handle.makeString(copy.uppercase != 0 ? (text as NSString).uppercased : text)
        return code(NTK_PROBE_ERROR_NONE)
    }

    static func clipboardReadTextAsync(_ callback: ntk_probe_text_fn?, _ userData: UnsafeMutableRawPointer?,
                                       _ release: ntk_release_fn?, _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_probe_error {
        CApiLog.probe.debug("clipboard_read_text_async")
        guard let callback else { return reject(NTK_PROBE_ERROR_INVALID_PARAMETER, userData, release) }
        let registration = TextRegistration(callback, userData, release)
        Registry.insert(registration)
        outRequestId?.pointee = registration.id
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard registration.currentState == .active else { return }
                IosClipboardManager.shared.read(scope: .named(probePasteboardName)) { ok, result, _, _ in
                    let finish: @Sendable () -> Void = {
                        Registry.complete(registration) { _ in
                            if ok {
                                let text = result?.items.first(where: { $0.text != nil })?.text ?? ""
                                registration.callback(registration.userData, registration.id, code(NTK_PROBE_ERROR_NONE), 0, Handle.makeString(text))
                            } else {
                                registration.callback(registration.userData, registration.id, code(NTK_PROBE_ERROR_READ_FAILED), 0, nil)
                            }
                        }
                    }
                    if Thread.isMainThread { finish() } else { DispatchQueue.main.async(execute: finish) }
                }
            }
        }
        return code(NTK_PROBE_ERROR_NONE)
    }

    static func raiseUIKitExceptionAsync(_ kind: ntk_probe_exception_kind, _ callback: ntk_probe_done_fn?,
                                         _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                         _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_probe_error {
        CApiLog.probe.debug("raise_uikit_exception_async kind=\(kind, privacy: .public)")
        guard let callback else { return reject(NTK_PROBE_ERROR_INVALID_PARAMETER, userData, release) }
        let registration = DoneRegistration(callback, userData, release)
        Registry.insert(registration)
        outRequestId?.pointee = registration.id
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                switch Int(kind) {
                case NTK_PROBE_EXCEPTION_ALERT_TEXT_FIELD:
                    UIAlertController(title: "probe", message: nil, preferredStyle: .actionSheet).addTextField(configurationHandler: nil)
                case NTK_PROBE_EXCEPTION_POPOVER_NO_ANCHOR:
                    let sheet = UIAlertController(title: "probe", message: nil, preferredStyle: .actionSheet)
                    sheet.addAction(UIAlertAction(title: "OK", style: .default))
                    ForegroundPresenter.topViewController()?.present(sheet, animated: false)
                default:
                    break
                }
                Registry.complete(registration) { _ in
                    registration.callback(registration.userData, registration.id, code(NTK_PROBE_ERROR_NONE), 0)
                }
            }
        }
        return code(NTK_PROBE_ERROR_NONE)
    }
}
