//
//  PasteboardResolver.swift
//  IosLibrary
//

import os
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "PasteboardResolver")

/// Resolves a `PasteboardScope` / `PasteboardCreationRequest` to a `UIPasteboard` instance.
///
/// Named and unique pasteboards are not a persistent store, but are not guaranteed to be
/// reclaimed when the creating process exits either — see `PasteboardScope`. `App Group`
/// entitlements are required for cross-app access.
@MainActor
final class PasteboardResolver {

    nonisolated init() {}

    /// Resolves an existing pasteboard. Throws `.pasteboardUnavailable` for a named/unique scope
    /// that cannot be resolved (e.g. it was removed, or the system reclaimed it).
    func resolve(_ scope: PasteboardScope) throws -> UIPasteboard {
        logger.log(level: .libraryDebug, "[resolve] scope: \(scope.redactedDescription, privacy: .public)")
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
        logger.log(level: .libraryDebug, "[createPasteboard] request: \(request.redactedDescription, privacy: .public)")
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
        logger.log(level: .libraryDebug, "[removePasteboard] scope: \(scope.redactedDescription, privacy: .public)")
        switch scope {
        case .general:
            throw ClipboardError.cannotRemoveGeneralPasteboard
        case .named(let name), .unique(let name):
            UIPasteboard.remove(withName: UIPasteboard.Name(name))
        }
    }
}
