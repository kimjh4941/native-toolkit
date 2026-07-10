//
//  ShareUseCases.swift
//  IosLibrary
//

import Foundation

/// Presents the system share sheet for the given content.
public struct ShareContentUseCase {
    private let TAG = "ShareContentUseCase"
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
        Log.d(TAG, "[execute] items: \(content.items.count)")
        guard !content.items.isEmpty else {
            throw ShareError.noValidItems
        }
        return try await repository.present(content: content)
    }
}
