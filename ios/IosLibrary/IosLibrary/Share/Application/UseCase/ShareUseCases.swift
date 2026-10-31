//
//  ShareUseCases.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ShareContentUseCase")

/// Presents the system share sheet for the given content.
public struct ShareContentUseCase: Sendable {
    private let repository: ShareRepository

    public init(repository: ShareRepository) {
        self.repository = repository
    }

    /// Validates and presents the share sheet.
    /// - Parameter content: The content to share.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError.noValidItems` if `content.items` is empty; otherwise
    ///   whatever `ShareError` the repository throws.
    public func execute(content: ShareContent) async throws -> ShareResult {
        logger.log(level: .libraryDebug, "[execute] items: \(content.items.count, privacy: .public)")
        guard !content.items.isEmpty else {
            throw ShareError.noValidItems
        }
        return try await repository.present(content: content)
    }
}
