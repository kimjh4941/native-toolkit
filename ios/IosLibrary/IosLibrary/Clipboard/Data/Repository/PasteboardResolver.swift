//
//  PasteboardResolver.swift
//  IosLibrary
//

import UIKit

/// Resolves a `PasteboardScope` / `PasteboardCreationRequest` to a `UIPasteboard` instance.
///
/// Named and unique pasteboards are non-persistent: they exist only while the app that created
/// them is running. `App Group` entitlements are required for cross-app access, but do not make
/// the pasteboard persistent — see `PasteboardScope`.
@MainActor
final class PasteboardResolver {
    private let TAG = "PasteboardResolver"

    nonisolated init() {}

    /// Resolves an existing pasteboard. Throws `.pasteboardUnavailable` for a named/unique scope
    /// that cannot be resolved (e.g. its creating app has quit).
    func resolve(_ scope: PasteboardScope) throws -> UIPasteboard {
        Log.d(TAG, "[resolve] scope: \(scope.redactedDescription)")
        switch scope {
        case .general:
            return .general
        case .named(let name), .unique(let name):
            guard let pasteboard = UIPasteboard(name: UIPasteboard.Name(name), create: false) else {
                throw ClipboardError.pasteboardUnavailable(name: name)
            }
            return pasteboard
        }
    }

    /// Creates (or resolves an existing) named pasteboard, or a fresh unique-named pasteboard.
    func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope {
        Log.d(TAG, "[createPasteboard] request: \(request.redactedDescription)")
        switch request {
        case .named(let name):
            guard UIPasteboard(name: UIPasteboard.Name(name), create: true) != nil else {
                throw ClipboardError.pasteboardUnavailable(name: name)
            }
            return .named(name)
        case .unique:
            let pasteboard = UIPasteboard.withUniqueName()
            return .unique(pasteboard.name.rawValue)
        }
    }

    /// Invalidates a named/unique pasteboard. Rejects `.general` (callers must not reach here
    /// with `.general`; see `RemovePasteboardUseCase`).
    func removePasteboard(_ scope: PasteboardScope) throws {
        Log.d(TAG, "[removePasteboard] scope: \(scope.redactedDescription)")
        switch scope {
        case .general:
            throw ClipboardError.cannotRemoveGeneralPasteboard
        case .named(let name), .unique(let name):
            UIPasteboard.remove(withName: UIPasteboard.Name(name))
        }
    }
}
