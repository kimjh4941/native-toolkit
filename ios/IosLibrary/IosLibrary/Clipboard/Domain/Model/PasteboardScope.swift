//
//  PasteboardScope.swift
//  IosLibrary
//

import Foundation

/// A reference to an existing pasteboard.
///
/// - Note: Named and unique pasteboards are not a persistent store, but their contents are not
///   guaranteed to be discarded when the creating process exits either — a named pasteboard has
///   been observed to survive a force-quit and relaunch. Delete sensitive data explicitly with
///   `removePasteboard(_:)`; see ``IosClipboardManager`` for the measurement.
public enum PasteboardScope: Equatable, Hashable, Sendable {
    /// The systemwide general pasteboard, shared with every app and persisted across launches.
    case general
    /// A named pasteboard shared with apps of the same Team ID (e.g. an App Group identifier).
    case named(String)
    /// A pasteboard created via `withUniqueName()`, identified by its generated name.
    case unique(String)
}
