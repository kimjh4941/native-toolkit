//
//  DialogMapping.swift
//  IosLibraryCApi
//

import IosLibrary

/// What `ntk_dialog_result` says: the answer as the C ABI can say it. The input may be a secret, so
/// nothing here is logged.
struct DialogResultValue: Sendable, Equatable {
    let button: ntk_dialog_button
    let optionIndex: Int64
    let buttonText: String?
    let text: String?
    let username: String?
    let password: String?
}

/// The pure conversions of Dialog.h (part 2, 6.2; P2-22): C values to Swift values on the calling thread,
/// before anything is registered, and back. Every struct is read with `reserved:` naming all its reserved
/// fields but `reserved0`. A NULL title, message or placeholder is "none", and a NULL button text the
/// library's own text.
enum DialogMapping {
    static func alert(_ pointer: UnsafePointer<ntk_dialog_alert_request>?) throws(EntryError) -> DialogRequest {
        CApiLog.dialog.debug("[alert] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        let raw = try StructReader.read(pointer, reserved: [])
        return .alert(title: try CApiString.optional(raw.title), message: try CApiString.optional(raw.message),
                      buttonTitle: try CApiString.optional(raw.button_text) ?? "OK")
    }

    static func confirm(_ pointer: UnsafePointer<ntk_dialog_confirm_request>?) throws(EntryError) -> DialogRequest {
        CApiLog.dialog.debug("[confirm] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        let raw = try StructReader.read(pointer, reserved: [])
        return .confirm(title: try CApiString.optional(raw.title), message: try CApiString.optional(raw.message),
                        confirmTitle: try CApiString.optional(raw.confirm_text) ?? "OK",
                        cancelTitle: try CApiString.optional(raw.cancel_text) ?? "Cancel")
    }

    static func destructive(_ pointer: UnsafePointer<ntk_dialog_destructive_request>?) throws(EntryError) -> DialogRequest {
        CApiLog.dialog.debug("[destructive] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        let raw = try StructReader.read(pointer, reserved: [])
        return .destructive(title: try CApiString.optional(raw.title), message: try CApiString.optional(raw.message),
                            destructiveTitle: try CApiString.optional(raw.destructive_text) ?? "Delete",
                            cancelTitle: try CApiString.optional(raw.cancel_text) ?? "Cancel")
    }

    /// No option is allowed: only the cancel button (part 2, 6.2).
    static func actionSheet(_ pointer: UnsafePointer<ntk_dialog_action_sheet_request>?) throws(EntryError) -> DialogRequest {
        CApiLog.dialog.debug("[actionSheet] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        let raw = try StructReader.read(pointer, reserved: [])
        return .actionSheet(title: try CApiString.optional(raw.title), message: try CApiString.optional(raw.message),
                            options: try CApiString.requiredArray(raw.options, count: raw.option_count),
                            cancelTitle: try CApiString.optional(raw.cancel_text) ?? "Cancel")
    }

    /// E-9: the C name is the inverse, so that 0 is the default.
    static func textInput(_ pointer: UnsafePointer<ntk_dialog_text_input_request>?) throws(EntryError) -> DialogRequest {
        CApiLog.dialog.debug("[textInput] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        let raw = try StructReader.read(pointer, reserved: [\.reserved1])
        return .textInput(title: try CApiString.optional(raw.title), message: try CApiString.optional(raw.message),
                          placeholder: try CApiString.optional(raw.placeholder),
                          confirmTitle: try CApiString.optional(raw.confirm_text) ?? "OK",
                          cancelTitle: try CApiString.optional(raw.cancel_text) ?? "Cancel",
                          enableConfirmWhenEmpty: raw.confirm_disabled_when_empty == 0)
    }

    /// E-9: as above.
    static func login(_ pointer: UnsafePointer<ntk_dialog_login_request>?) throws(EntryError) -> DialogRequest {
        CApiLog.dialog.debug("[login] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        let raw = try StructReader.read(pointer, reserved: [\.reserved1])
        return .login(title: try CApiString.optional(raw.title), message: try CApiString.optional(raw.message),
                      usernamePlaceholder: try CApiString.optional(raw.username_placeholder) ?? "Username",
                      passwordPlaceholder: try CApiString.optional(raw.password_placeholder) ?? "Password",
                      loginTitle: try CApiString.optional(raw.login_text) ?? "Login",
                      cancelTitle: try CApiString.optional(raw.cancel_text) ?? "Cancel",
                      enableLoginWhenEmpty: raw.login_disabled_when_empty == 0)
    }

    /// Nil for a button or an input this version does not know: the C ABI has no value for it, and the
    /// receiver completes with UNKNOWN rather than with an answer that looks like another one.
    static func result(of answer: DialogAnswer) -> DialogResultValue? {
        CApiLog.dialog.debug("[result] answer: provided")
        let button: ntk_dialog_button
        var optionIndex: Int64 = -1
        switch answer.button {
        case .primary:
            button = ntk_dialog_button(NTK_DIALOG_BUTTON_POSITIVE)
        case .cancel:
            button = ntk_dialog_button(NTK_DIALOG_BUTTON_NEGATIVE)
        case .destructive:
            button = ntk_dialog_button(NTK_DIALOG_BUTTON_DESTRUCTIVE)
        case .option(let index):
            button = ntk_dialog_button(NTK_DIALOG_BUTTON_OPTION)
            optionIndex = Int64(index)
        @unknown default:
            CApiLog.dialog.error("[result] a button this version does not know")
            return nil
        }
        var text: String?
        var username: String?
        var password: String?
        switch answer.input {
        case .none:
            break
        case .text(let value):
            text = value
        case .login(let user, let secret):
            username = user
            password = secret
        @unknown default:
            CApiLog.dialog.error("[result] an input this version does not know")
            return nil
        }
        return DialogResultValue(button: button, optionIndex: optionIndex, buttonText: answer.title, text: text, username: username, password: password)
    }

    /// Part 2, 11.1: every case. `invalidRequest` is a box used twice, which C does not do.
    static func error(for error: DialogError) -> ntk_dialog_error {
        CApiLog.dialog.debug("[error] error: \(String(describing: error), privacy: .public)")
        switch error {
        case .canceled: return ntk_dialog_error(NTK_DIALOG_ERROR_CANCELED)
        case .dismissedBySystem: return ntk_dialog_error(NTK_DIALOG_ERROR_CANCELED_BY_SYSTEM)
        case .notForeground: return ntk_dialog_error(NTK_DIALOG_ERROR_NOT_FOREGROUND)
        case .presentationFailed: return ntk_dialog_error(NTK_DIALOG_ERROR_SHOW_FAILED)
        case .invalidRequest: return ntk_dialog_error(NTK_DIALOG_ERROR_INVALID_PARAMETER)
        @unknown default:
            CApiLog.dialog.error("[error] a case this version does not know")
            return ntk_dialog_error(NTK_DIALOG_ERROR_UNKNOWN)
        }
    }
}
