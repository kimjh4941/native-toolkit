//
//  ClipboardChangeEvent.swift
//  IosLibrary
//

import Foundation

/// An event describing a clipboard change or a pasteboard's removal.
public struct ClipboardChangeEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// `UIPasteboard.changedNotification` was received.
        case changed(typesAdded: [String], typesRemoved: [String])
        /// A change was detected by comparing `changeCount` on foreground return, without a
        /// corresponding notification.
        case changedDetectedOnForeground
        /// `UIPasteboard.removedNotification` was received (named pasteboards only).
        case removed
    }

    public let kind: Kind
    public let scope: PasteboardScope

    public init(kind: Kind, scope: PasteboardScope) {
        self.kind = kind
        self.scope = scope
    }
}
