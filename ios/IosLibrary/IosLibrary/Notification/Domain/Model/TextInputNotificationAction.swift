//
//  TextInputNotificationAction.swift
//  IosLibrary
//

import Foundation

/// A notification action that presents a text input field (e.g. inline reply).
public struct TextInputNotificationAction {
    /// A unique identifier for the action.
    public let identifier: String
    /// The title displayed on the action button.
    public let title: String
    /// The title of the Send button in the text input interface.
    public let buttonTitle: String
    /// Placeholder text shown in the text input field.
    public let textInputPlaceholder: String

    /// Creates a text input notification action.
    /// - Parameters:
    ///   - identifier: A unique identifier for the action.
    ///   - title: The title displayed on the action button.
    ///   - buttonTitle: The title of the Send button in the text input interface.
    ///   - textInputPlaceholder: Placeholder text shown in the text input field.
    public init(
        identifier: String,
        title: String,
        buttonTitle: String,
        textInputPlaceholder: String
    ) {
        self.identifier = identifier
        self.title = title
        self.buttonTitle = buttonTitle
        self.textInputPlaceholder = textInputPlaceholder
    }
}
