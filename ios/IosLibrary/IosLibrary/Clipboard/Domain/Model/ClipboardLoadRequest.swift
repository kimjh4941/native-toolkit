//
//  ClipboardLoadRequest.swift
//  IosLibrary
//

import Foundation

/// A request to asynchronously load an item from `NSItemProvider`s on the pasteboard.
public enum ClipboardLoadRequest: Equatable, Sendable {
    case text
    case url
    /// Loaded and re-encoded as PNG on a background executor.
    case image
    case file(utType: String)
}

/// A successfully-loaded clipboard item.
///
/// - Note: For `.file`, the caller owns the returned URL (and its parent directory) and is
///   responsible for deleting it once done.
public enum ClipboardLoadedItem: Sendable, Equatable {
    case text(String)
    case url(String)
    case imageData(Data, utType: String)
    case file(URL)
}
