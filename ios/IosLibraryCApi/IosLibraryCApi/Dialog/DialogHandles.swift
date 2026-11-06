//
//  DialogHandles.swift
//  IosLibraryCApi
//

/// What an `ntk_dialog_result*` points to.
final class DialogResultHandle {
    let button: ntk_dialog_button
    let optionIndex: Int64
    let buttonText: HandleBuffer?
    let text: HandleBuffer?
    let username: HandleBuffer?
    let password: HandleBuffer?

    init(_ value: DialogResultValue) {
        button = value.button
        optionIndex = value.optionIndex
        buttonText = value.buttonText.map(DialogHandles.buffer)
        text = value.text.map(DialogHandles.buffer)
        username = value.username.map(DialogHandles.buffer)
        password = value.password.map(DialogHandles.buffer)
    }
}

/// The readers of the result. NULL and a handle of another type read as nothing. Reads and frees are not
/// logged (part 1, 5.15), and the values themselves never are.
enum DialogHandles {
    fileprivate static func buffer(_ value: String) -> HandleBuffer {
        HandleBuffer(CApiString.outputUTF8(value))
    }

    static func makeResult(_ value: DialogResultValue) -> OpaquePointer {
        CApiLog.dialog.debug("[makeResult] button: \(value.button, privacy: .public)")
        return Handle.retained(DialogResultHandle(value))
    }

    private static func result(_ handle: OpaquePointer?) -> DialogResultHandle? {
        Handle.borrow(handle, as: DialogResultHandle.self)
    }

    /// -1 for NULL: 0 is POSITIVE (P2-29).
    static func button(_ handle: OpaquePointer?) -> ntk_dialog_button {
        result(handle)?.button ?? -1
    }

    /// -1 for NULL: 0 is the first option (P2-29).
    static func optionIndex(_ handle: OpaquePointer?) -> Int64 {
        result(handle)?.optionIndex ?? -1
    }

    static func buttonText(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: result(handle)?.buttonText, outSize)
    }

    static func text(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: result(handle)?.text, outSize)
    }

    static func username(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: result(handle)?.username, outSize)
    }

    static func password(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: result(handle)?.password, outSize)
    }
}
