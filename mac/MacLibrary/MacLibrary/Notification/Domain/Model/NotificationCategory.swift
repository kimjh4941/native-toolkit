//
//  NotificationCategory.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

/// An action attached to a notification category.
public struct NotificationAction {
    /// Unique identifier for this action.
    public let id: String
    /// Title displayed on the action button.
    public let title: String
    /// When `true`, the action opens the app in the foreground.
    public let isForeground: Bool
    /// When `true`, the action accepts text input from the user.
    public let isTextInput: Bool
    /// Placeholder text shown in the text input field (only used when `isTextInput == true`).
    public let textInputPlaceholder: String?

    public init(
        id: String,
        title: String,
        isForeground: Bool = false,
        isTextInput: Bool = false,
        textInputPlaceholder: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isForeground = isForeground
        self.isTextInput = isTextInput
        self.textInputPlaceholder = textInputPlaceholder
    }
}

/// A category that groups a set of actions for a notification type.
public struct NotificationCategory {
    /// Unique identifier for this category (1–64 chars).
    public let id: String
    /// Actions available for notifications of this category.
    public let actions: [NotificationAction]

    public init(id: String, actions: [NotificationAction]) {
        self.id = id
        self.actions = actions
    }
}
