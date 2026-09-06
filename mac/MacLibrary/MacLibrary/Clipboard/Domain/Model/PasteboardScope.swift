//
//  PasteboardScope.swift
//  MacLibrary
//

import Foundation

/// Identifies which pasteboard an operation targets.
///
/// - Important: Named and unique pasteboards live in the pasteboard server and **survive the
///   creating app's termination**. Do not place confidential data on them. Unique pasteboards
///   must be released explicitly; see the remove operation.
public enum PasteboardScope: Sendable, Equatable, Hashable {
    /// The system-wide general pasteboard. Also the one synchronised by Universal Clipboard.
    case general
    /// A named pasteboard shared by name.
    case named(String)
    /// A pasteboard created with a system generated unique name.
    case unique(String)

    /// Raw pasteboard name, or `nil` for ``general`` which the platform names itself.
    public var name: String? {
        switch self {
        case .general: return nil
        case .named(let value), .unique(let value): return value
        }
    }
}

/// Describes the pasteboard to create.
public enum PasteboardCreationRequest: Sendable, Equatable {
    /// Create or fetch a pasteboard with the given name.
    case named(String)
    /// Create a pasteboard whose name the system guarantees to be unique.
    case unique
}

/// Proof that this app owned the pasteboard at a point in time.
///
/// Appending is only possible while the app still owns the pasteboard, so the change count
/// captured when ownership was taken is compared before every append.
public struct PasteboardOwnership: Sendable, Equatable {
    /// The pasteboard the ownership refers to.
    public let scope: PasteboardScope
    /// Change count reported when ownership was taken.
    public let changeCount: Int

    /// Creates a value from its parts.
    public init(scope: PasteboardScope, changeCount: Int) {
        self.scope = scope
        self.changeCount = changeCount
    }
}
