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
        /// A change detected by comparing `changeCount` on foreground return, without a
        /// corresponding notification.
        ///
        /// Not delivered in 2.0.0: ``IosClipboardManager/startObserving(scope:onEvent:)`` reports
        /// only ``changed(typesAdded:typesRemoved:)`` and ``removed``. Call
        /// ``IosClipboardManager/checkForegroundChange(scope:)`` on foreground return instead; it
        /// returns whether the pasteboard changed. The case is kept for source compatibility.
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
