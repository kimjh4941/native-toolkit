//
//  PasteboardResolver.swift
//  MacLibrary
//

import AppKit
import Foundation

/// Turns a ``PasteboardScope`` into the `NSPasteboard` it names.
///
/// This is the only place that maps domain scopes onto AppKit pasteboards, so the rule that
/// standard pasteboards can never be released lives here rather than in each caller.
@MainActor
enum PasteboardResolver {

    // nonisolated so that `resolve` can log from any isolation domain.
    private nonisolated static let TAG = "PasteboardResolver"

    /// Pasteboards owned by the system. Releasing any of these would break other apps, so the
    /// remove operation refuses them (RK-07).
    static let standardNames: Set<String> = [
        NSPasteboard.Name.general.rawValue,
        NSPasteboard.Name.font.rawValue,
        NSPasteboard.Name.ruler.rawValue,
        NSPasteboard.Name.find.rawValue,
        NSPasteboard.Name.drag.rawValue,
    ]

    /// Returns the pasteboard the scope names.
    ///
    /// - Throws: ``ClipboardError/invalidPasteboardName(_:)`` when a named or unique scope
    ///   carries an empty name.
    ///
    /// `nonisolated` so that a caller which is itself nonisolated can resolve and use a
    /// pasteboard entirely within its own isolation domain. The detection APIs are
    /// `nonisolated async`, and resolving there rather than handing a main actor isolated
    /// instance across a boundary avoids the crossing instead of asserting it is safe. The
    /// function touches no actor state; it only constructs or returns an `NSPasteboard`.
    nonisolated static func resolve(_ scope: PasteboardScope) throws -> NSPasteboard {
        Log.d(TAG, "[resolve] scope: \(ClipboardLog.scope(scope))")
        switch scope {
        case .general:
            return .general
        case .named(let name), .unique(let name):
            guard !name.isEmpty else {
                throw ClipboardError.invalidPasteboardName(name)
            }
            return NSPasteboard(name: NSPasteboard.Name(name))
        }
    }

    /// Creates the pasteboard described by the request and returns it with the scope that
    /// names it. The scope carries the resolved name so that later calls address the same
    /// pasteboard, which matters for ``PasteboardCreationRequest/unique`` where the name is
    /// chosen by the system.
    ///
    /// - Throws: ``ClipboardError/invalidPasteboardName(_:)`` for an empty name.
    static func create(_ request: PasteboardCreationRequest) throws -> (NSPasteboard, PasteboardScope) {
        Log.d(TAG, "[create] request: \(request)")
        switch request {
        case .named(let name):
            guard !name.isEmpty else {
                throw ClipboardError.invalidPasteboardName(name)
            }
            let pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
            return (pasteboard, .named(pasteboard.name.rawValue))
        case .unique:
            let pasteboard = NSPasteboard.withUniqueName()
            return (pasteboard, .unique(pasteboard.name.rawValue))
        }
    }

    /// Whether the scope refers to a system owned pasteboard that must never be released.
    ///
    /// ``PasteboardScope/general`` always qualifies. A named scope qualifies when its name
    /// matches one of the standard names, which is possible because a caller can construct
    /// ``PasteboardScope/named(_:)`` with any string.
    static func isStandard(_ scope: PasteboardScope) -> Bool {
        Log.d(TAG, "[isStandard] scope: \(ClipboardLog.scope(scope))")
        switch scope {
        case .general:
            return true
        case .named(let name), .unique(let name):
            return standardNames.contains(name)
        }
    }
}
