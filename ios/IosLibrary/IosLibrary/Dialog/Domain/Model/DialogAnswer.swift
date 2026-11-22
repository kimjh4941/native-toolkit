//
//  DialogAnswer.swift
//  IosLibrary
//

/// How the user answered a dialog: the button they pressed and, for a text input or a login
/// dialog, what they entered.
public struct DialogAnswer: Sendable, Equatable {
    /// A button of a dialog, by its role in the ``DialogRequest``.
    public enum Button: Sendable, Equatable {
        /// The main button: the alert's button, the confirm button, the text input's confirm
        /// button or the login button.
        case primary
        /// The cancel button (also chosen by tapping outside an action sheet's popover).
        case cancel
        /// The destructive button of ``DialogRequest/destructive(title:message:destructiveTitle:cancelTitle:)``.
        case destructive
        /// An option of ``DialogRequest/actionSheet(title:message:options:cancelTitle:)``.
        /// - Parameter index: The index of the option in the request's `options`.
        case option(index: Int)
    }

    /// The button that was pressed.
    public let button: Button
    /// The text of the button that was pressed, as given in the request.
    public let title: String?
    /// What was entered, for the ``Button/primary`` button of a text input or a login dialog.
    /// `nil` for every other button, including the cancel button of those dialogs.
    public let input: DialogInput?

    /// Creates an answer, for example in your own ``DialogPresenting`` or in a test.
    ///
    /// - Parameters:
    ///   - button: The button that was pressed.
    ///   - title: The text of that button, as given in the request.
    ///   - input: What was entered, for the primary button of a text input or a login dialog;
    ///     otherwise `nil`.
    public init(button: Button, title: String?, input: DialogInput?) {
        self.button = button
        self.title = title
        self.input = input
    }
}

extension DialogAnswer.Button {
    /// The button's name for the log.
    var logName: String {
        switch self {
        case .primary: return "primary"
        case .cancel: return "cancel"
        case .destructive: return "destructive"
        case .option(let index): return "option(\(index))"
        }
    }
}
