//
//  NotificationCategoryChange.swift
//  IosLibrary
//

import Foundation

/// One change to the app's notification categories, as queued by
/// ``NotificationRepository/enqueueCategoryChange(_:completion:)`` (design S-P28).
public enum NotificationCategoryChange: Sendable {
    /// Adds the category, replacing a registered category with the same identifier.
    case register(NotificationCategory)
    /// Removes the registered category with this identifier (nothing when there is none).
    case remove(identifier: String)
}

extension NotificationCategoryChange {
    /// `register(<identifier>)` or `remove(<identifier>)`: the category identifier only, for the
    /// log (identifiers may be logged; design 8.7.1).
    var logSummary: String {
        switch self {
        case .register(let category): return "register(\(category.identifier))"
        case .remove(let identifier): return "remove(\(identifier))"
        }
    }
}
