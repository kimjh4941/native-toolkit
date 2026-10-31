//
//  ReadContentUseCase.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ReadContentUseCase")

/// Reads the clipboard's items synchronously (P-3). An empty clipboard is not an error.
@MainActor
public struct ReadContentUseCase {
    private let repository: ClipboardRepository

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    public func execute(scope: PasteboardScope) throws -> ClipboardReadResult {
        logger.log(level: .libraryDebug, "[execute] scope: \(scope.redactedDescription, privacy: .public)")
        return try repository.read(scope: scope)
    }
}
