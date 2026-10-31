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

    /// Validates and presents the share sheet from the view controller
    /// ``PresenterSelection/firstActiveScene`` selects (the search used before
    /// ``PresenterSelection`` existed).
    /// - Parameter content: The content to share.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError.noValidItems` if `content.items` is empty; otherwise the error the
    ///   repository throws, unchanged (a `ShareError` with the library's repository).
    public func execute(content: ShareContent) async throws -> ShareResult {
        logger.log(level: .libraryDebug, "[execute] \(content.logSummary, privacy: .public)")
        return try await execute(content: content, presenter: .firstActiveScene)
    }

    /// Validates and presents the share sheet from the view controller `presenter` selects.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - presenter: How to choose the view controller to present from.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError.noValidItems` if `content.items` is empty (the repository is not
    ///   called); otherwise the error the repository throws, unchanged (a `ShareError` with the
    ///   library's repository).
    public func execute(content: ShareContent, presenter: PresenterSelection) async throws -> ShareResult {
        logger.log(level: .libraryDebug, "[execute] \(content.logSummary, privacy: .public), presenter: \(presenter.logName, privacy: .public)")
        guard !content.items.isEmpty else {
            throw ShareError.noValidItems
        }
        return try await repository.present(content: content, presenter: presenter)
    }
}
