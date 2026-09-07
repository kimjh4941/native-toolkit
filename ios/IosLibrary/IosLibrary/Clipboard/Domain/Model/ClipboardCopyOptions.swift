//
//  ClipboardCopyOptions.swift
//  IosLibrary
//

import Foundation

/// Privacy options for `copy`.
///
/// - Important: `append` cannot carry these options: `UIPasteboard.addItems(_:)` has no options
///   overload, and whether privacy options are inherited by appended items is not guaranteed by
///   the system. Sensitive data should always use `copy(_:options:)`.
public struct ClipboardCopyOptions: Equatable, Sendable {
    /// When `true`, the content is not transferred to nearby devices via Universal Clipboard.
    public let localOnly: Bool
    /// When set, the system removes the item after this date.
    public let expirationDate: Date?

    public init(localOnly: Bool, expirationDate: Date?) {
        self.localOnly = localOnly
        self.expirationDate = expirationDate
    }

    /// `localOnly: true`, no expiration — the safe default that avoids Universal Clipboard leakage.
    public static let `default` = ClipboardCopyOptions(localOnly: true, expirationDate: nil)
}
