//
//  RemovePasteboardUseCase.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "RemovePasteboardUseCase")

/// Invalidates a named pasteboard (P-8). Removing `.general` is rejected: the system silently
/// ignores such a request, which would otherwise hide caller mistakes.
@MainActor
public struct RemovePasteboardUseCase {
    private let repository: ClipboardRepository

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    public func execute(_ scope: PasteboardScope) throws {
        logger.log(level: .libraryDebug, "[execute] scope: \(scope.redactedDescription, privacy: .public)")
        guard scope != .general else {
            throw ClipboardError.cannotRemoveGeneralPasteboard
        }
        try repository.removePasteboard(scope)
    }
}
