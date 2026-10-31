//
//  ClearClipboardUseCase.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ClearClipboardUseCase")

/// Clears all items on the pasteboard (P-6).
@MainActor
public struct ClearClipboardUseCase {
    private let repository: ClipboardRepository

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    public func execute(scope: PasteboardScope) throws {
        logger.log(level: .libraryDebug, "[execute] scope: \(scope.redactedDescription, privacy: .public)")
        try repository.clear(scope: scope)
    }
}
