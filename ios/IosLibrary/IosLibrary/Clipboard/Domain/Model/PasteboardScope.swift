//
//  PasteboardScope.swift
//  IosLibrary
//

import Foundation

/// A reference to an existing pasteboard.
///
/// - Note: Named and unique pasteboards are non-persistent: they exist only while the app that
///   created them is running. They are suitable only for transferring data while both sides are
///   alive, never for persistent sharing (use an App Group shared container for that).
public enum PasteboardScope: Equatable, Hashable, Sendable {
    /// The systemwide general pasteboard. The only persistent pasteboard.
    case general
    /// A named pasteboard shared with apps of the same Team ID (e.g. an App Group identifier).
    case named(String)
    /// A pasteboard created via `withUniqueName()`, identified by its generated name.
    case unique(String)
}
