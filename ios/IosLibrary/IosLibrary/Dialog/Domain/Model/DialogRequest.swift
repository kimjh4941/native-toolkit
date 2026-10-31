//
//  DialogRequest.swift
//  IosLibrary
//

/// One dialog to show: its kind, its texts and its buttons.
///
/// Pass a request to `IosDialogManager.show(_:presenter:requestBox:completion:)` or its `async`
/// form. The result is a ``DialogAnswer`` that says which button was pressed (and, for
/// ``textInput(title:message:placeholder:confirmTitle:cancelTitle:enableConfirmWhenEmpty:)`` and
/// ``login(title:message:usernamePlaceholder:passwordPlaceholder:loginTitle:cancelTitle:enableLoginWhenEmpty:)``,
/// what was entered), or a ``DialogError``.
///
/// | Request | Buttons (``DialogAnswer/Button``) |
/// |---|---|
/// | ``alert(title:message:buttonTitle:)`` | ``DialogAnswer/Button/primary`` |
/// | ``confirm(title:message:confirmTitle:cancelTitle:)`` | ``DialogAnswer/Button/primary``, ``DialogAnswer/Button/cancel`` |
/// | ``destructive(title:message:destructiveTitle:cancelTitle:)`` | ``DialogAnswer/Button/destructive``, ``DialogAnswer/Button/cancel`` |
/// | ``actionSheet(title:message:options:cancelTitle:)`` | ``DialogAnswer/Button/option(index:)``, ``DialogAnswer/Button/cancel`` |
/// | ``textInput(title:message:placeholder:confirmTitle:cancelTitle:enableConfirmWhenEmpty:)`` | ``DialogAnswer/Button/primary`` (with ``DialogInput/text(_:)``), ``DialogAnswer/Button/cancel`` |
/// | ``login(title:message:usernamePlaceholder:passwordPlaceholder:loginTitle:cancelTitle:enableLoginWhenEmpty:)`` | ``DialogAnswer/Button/primary`` (with ``DialogInput/login(username:password:)``), ``DialogAnswer/Button/cancel`` |
///
/// The default texts are the ones of the dialog manager's other `show...` methods. An action
/// sheet cannot have a text field. On iPad an action sheet is shown as a popover anchored at the
/// centre of the view of the view controller it is presented from; use the dialog manager's
/// `showActionSheet(...)` to choose the anchor.
public enum DialogRequest: Sendable, Equatable {
    /// An alert with one button.
    /// - Parameters:
    ///   - title: The title, or `nil` for none.
    ///   - message: The message, or `nil` for none.
    ///   - buttonTitle: The button's text.
    case alert(title: String?, message: String?, buttonTitle: String = "OK")
    /// An alert with a confirm button and a cancel button.
    /// - Parameters:
    ///   - title: The title, or `nil` for none.
    ///   - message: The message, or `nil` for none.
    ///   - confirmTitle: The confirm button's text (``DialogAnswer/Button/primary``).
    ///   - cancelTitle: The cancel button's text (``DialogAnswer/Button/cancel``).
    case confirm(title: String?, message: String?, confirmTitle: String = "OK", cancelTitle: String = "Cancel")
    /// An alert with a destructive button (shown in red) and a cancel button.
    /// - Parameters:
    ///   - title: The title, or `nil` for none.
    ///   - message: The message, or `nil` for none.
    ///   - destructiveTitle: The destructive button's text (``DialogAnswer/Button/destructive``).
    ///   - cancelTitle: The cancel button's text (``DialogAnswer/Button/cancel``).
    case destructive(title: String?, message: String?, destructiveTitle: String = "Delete", cancelTitle: String = "Cancel")
    /// An action sheet with one button per option and a cancel button.
    /// - Parameters:
    ///   - title: The title, or `nil` for none.
    ///   - message: The message, or `nil` for none.
    ///   - options: The options' texts, in order (``DialogAnswer/Button/option(index:)`` gives the
    ///     index in this array).
    ///   - cancelTitle: The cancel button's text (``DialogAnswer/Button/cancel``). On iPad, and on
    ///     iPhone with iOS 26, tapping outside the popover also chooses it.
    case actionSheet(title: String?, message: String?, options: [String], cancelTitle: String = "Cancel")
    /// An alert with one text field, a confirm button and a cancel button.
    /// - Parameters:
    ///   - title: The title, or `nil` for none.
    ///   - message: The message, or `nil` for none.
    ///   - placeholder: The text field's placeholder, or `nil` for none.
    ///   - confirmTitle: The confirm button's text (``DialogAnswer/Button/primary``, with the
    ///     entered text).
    ///   - cancelTitle: The cancel button's text (``DialogAnswer/Button/cancel``, without input).
    ///   - enableConfirmWhenEmpty: When `false`, the confirm button is disabled while the field is
    ///     empty.
    case textInput(title: String?, message: String?, placeholder: String? = nil, confirmTitle: String = "OK",
                   cancelTitle: String = "Cancel", enableConfirmWhenEmpty: Bool = true)
    /// An alert with a username field, a password field (secure entry), a login button and a
    /// cancel button.
    /// - Parameters:
    ///   - title: The title, or `nil` for none.
    ///   - message: The message, or `nil` for none.
    ///   - usernamePlaceholder: The username field's placeholder.
    ///   - passwordPlaceholder: The password field's placeholder.
    ///   - loginTitle: The login button's text (``DialogAnswer/Button/primary``, with the entered
    ///     username and password).
    ///   - cancelTitle: The cancel button's text (``DialogAnswer/Button/cancel``, without input).
    ///   - enableLoginWhenEmpty: When `false`, the login button is disabled until both fields have
    ///     text.
    case login(title: String?, message: String?, usernamePlaceholder: String = "Username", passwordPlaceholder: String = "Password",
               loginTitle: String = "Login", cancelTitle: String = "Cancel", enableLoginWhenEmpty: Bool = true)
}

extension DialogRequest {
    /// The kind's name for the log (no texts).
    var kindName: String {
        switch self {
        case .alert: return "alert"
        case .confirm: return "confirm"
        case .destructive: return "destructive"
        case .actionSheet: return "actionSheet"
        case .textInput: return "textInput"
        case .login: return "login"
        }
    }

    /// The title, for the log (a user value: log it `.private`).
    var logTitle: String? {
        switch self {
        case .alert(let title, _, _), .confirm(let title, _, _, _), .destructive(let title, _, _, _),
             .actionSheet(let title, _, _, _), .textInput(let title, _, _, _, _, _), .login(let title, _, _, _, _, _, _):
            return title
        }
    }

    /// The message, for the log (a user value: log it `.private`).
    var logMessage: String? {
        switch self {
        case .alert(_, let message, _), .confirm(_, let message, _, _), .destructive(_, let message, _, _),
             .actionSheet(_, let message, _, _), .textInput(_, let message, _, _, _, _), .login(_, let message, _, _, _, _, _):
            return message
        }
    }
}
