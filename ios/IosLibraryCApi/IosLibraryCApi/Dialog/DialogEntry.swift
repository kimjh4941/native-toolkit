//
//  DialogEntry.swift
//  IosLibraryCApi
//

// The entry points of Dialog.h (C ABI design part 1, 5.3). Only @c @implementation functions, whose types
// the compiler checks against the header; what they do is in DialogReceiver.swift and DialogHandles.swift.

@c @implementation
public func ntk_dialog_show_alert_async(_ request: UnsafePointer<ntk_dialog_alert_request>?, _ callback: ntk_dialog_result_fn?,
                                       _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                       _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
    DialogReceiver.alert(request, callback, userData, release, outRequestID)
}

@c @implementation
public func ntk_dialog_show_confirm_async(_ request: UnsafePointer<ntk_dialog_confirm_request>?, _ callback: ntk_dialog_result_fn?,
                                       _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                       _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
    DialogReceiver.confirm(request, callback, userData, release, outRequestID)
}

@c @implementation
public func ntk_dialog_show_destructive_async(_ request: UnsafePointer<ntk_dialog_destructive_request>?, _ callback: ntk_dialog_result_fn?,
                                       _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                       _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
    DialogReceiver.destructive(request, callback, userData, release, outRequestID)
}

@c @implementation
public func ntk_dialog_show_action_sheet_async(_ request: UnsafePointer<ntk_dialog_action_sheet_request>?, _ callback: ntk_dialog_result_fn?,
                                       _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                       _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
    DialogReceiver.actionSheet(request, callback, userData, release, outRequestID)
}

@c @implementation
public func ntk_dialog_show_text_input_async(_ request: UnsafePointer<ntk_dialog_text_input_request>?, _ callback: ntk_dialog_result_fn?,
                                       _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                       _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
    DialogReceiver.textInput(request, callback, userData, release, outRequestID)
}

@c @implementation
public func ntk_dialog_show_login_async(_ request: UnsafePointer<ntk_dialog_login_request>?, _ callback: ntk_dialog_result_fn?,
                                       _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                       _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
    DialogReceiver.login(request, callback, userData, release, outRequestID)
}

@c @implementation
public func ntk_dialog_cancel(_ requestID: UInt64) -> ntk_dialog_error {
    DialogReceiver.cancel(requestID)
}

@c @implementation
public func ntk_dialog_result_button(_ result: OpaquePointer?) -> ntk_dialog_button {
    DialogHandles.button(result)
}

@c @implementation
public func ntk_dialog_result_option_index(_ result: OpaquePointer?) -> Int64 {
    DialogHandles.optionIndex(result)
}

@c @implementation
public func ntk_dialog_result_button_text(_ result: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    DialogHandles.buttonText(result, outSize)
}

@c @implementation
public func ntk_dialog_result_text(_ result: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    DialogHandles.text(result, outSize)
}

@c @implementation
public func ntk_dialog_result_username(_ result: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    DialogHandles.username(result, outSize)
}

@c @implementation
public func ntk_dialog_result_password(_ result: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    DialogHandles.password(result, outSize)
}

@c @implementation
public func ntk_dialog_result_free(_ result: OpaquePointer?) {
    Handle.free(result)
}
