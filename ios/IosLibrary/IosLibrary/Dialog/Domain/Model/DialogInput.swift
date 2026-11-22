//
//  DialogInput.swift
//  IosLibrary
//

/// What the user entered in a text input or a login dialog.
///
/// The values can be secret (a password, or whatever the user typed), so ``description`` shows
/// only their lengths: `text(length: 5)`, `login(username: length 4, password: length 7)`. Read the
/// values through the cases. Two inputs are equal when their values are equal.
public enum DialogInput: Sendable, Equatable, CustomStringConvertible {
    /// The text of ``DialogRequest/textInput(title:message:placeholder:confirmTitle:cancelTitle:enableConfirmWhenEmpty:)``.
    case text(String)
    /// The username and password of ``DialogRequest/login(title:message:usernamePlaceholder:passwordPlaceholder:loginTitle:cancelTitle:enableLoginWhenEmpty:)``.
    case login(username: String, password: String)

    /// The kind of input and the length of each value (UTF-8 bytes), never the values.
    public var description: String {
        switch self {
        case .text(let text):
            return "text(length: \(text.utf8.count))"
        case .login(let username, let password):
            return "login(username: length \(username.utf8.count), password: length \(password.utf8.count))"
        }
    }
}
