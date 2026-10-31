//
//  CreatePasteboardUseCase.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "CreatePasteboardUseCase")

/// Creates (or resolves an existing) named pasteboard, or a new unique-named pasteboard (P-7).
@MainActor
public struct CreatePasteboardUseCase {
    private let repository: ClipboardRepository

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    public func execute(_ request: PasteboardCreationRequest) throws -> PasteboardScope {
        logger.log(level: .libraryDebug, "[execute] request: \(request.redactedDescription, privacy: .public)")
        if case .named(let name) = request {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ClipboardError.invalidPasteboardName(name)
            }
        }
        return try repository.createPasteboard(request)
    }
}
