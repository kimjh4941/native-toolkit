//
//  NotificationAction.swift
//  IosLibrary
//

import Foundation

/// Options that modify the behavior of a notification action button.
public struct NotificationActionOptions: OptionSet {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// The action requires the device to be unlocked to perform.
    public static let authenticationRequired = NotificationActionOptions(rawValue: 1 << 0)
    /// The action is destructive and displays with a red color.
    public static let destructive = NotificationActionOptions(rawValue: 1 << 1)
    /// The action causes the app to launch in the foreground.
    public static let foreground = NotificationActionOptions(rawValue: 1 << 2)
}

/// A tappable button in a notification action area.
public struct NotificationAction {
    /// A unique identifier for the action.
    public let identifier: String
    /// The title displayed on the action button.
    public let title: String
    /// An optional SF Symbol name for the action icon.
    public let sfSymbolName: String?
    /// Options that modify the action behavior.
    public let options: NotificationActionOptions

    /// Creates a notification action.
    /// - Parameters:
    ///   - identifier: A unique identifier for the action.
    ///   - title: The title displayed on the action button.
    ///   - sfSymbolName: An optional SF Symbol name for the action icon.
    ///   - options: Options that modify the action behavior.
    public init(
        identifier: String,
        title: String,
        sfSymbolName: String? = nil,
        options: NotificationActionOptions = []
    ) {
        self.identifier = identifier
        self.title = title
        self.sfSymbolName = sfSymbolName
        self.options = options
    }
}
