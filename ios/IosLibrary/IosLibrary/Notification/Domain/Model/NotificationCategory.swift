//
//  NotificationCategory.swift
//  IosLibrary
//

import Foundation

/// A group of related notification actions and display options.
public struct NotificationCategory {
    /// A unique identifier for the category.
    public let identifier: String
    /// Tap-to-dismiss or tap-to-open action buttons.
    public let actions: [NotificationAction]
    /// Text-input action buttons (e.g. inline reply).
    public let textInputActions: [TextInputNotificationAction]
    /// Options that modify the category behavior.
    public let options: NotificationCategoryOptions

    /// Creates a notification category.
    /// - Parameters:
    ///   - identifier: A unique identifier for the category.
    ///   - actions: Tap-to-dismiss or tap-to-open action buttons.
    ///   - textInputActions: Text-input action buttons.
    ///   - options: Options that modify the category behavior.
    public init(
        identifier: String,
        actions: [NotificationAction] = [],
        textInputActions: [TextInputNotificationAction] = [],
        options: NotificationCategoryOptions = []
    ) {
        self.identifier = identifier
        self.actions = actions
        self.textInputActions = textInputActions
        self.options = options
    }
}
