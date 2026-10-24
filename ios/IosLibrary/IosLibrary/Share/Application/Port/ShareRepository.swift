//
//  ShareRepository.swift
//  IosLibrary
//

import Foundation

/// Defines the contract for presenting the system share sheet.
/// Implemented by `ShareRepositoryImpl` in the Data layer.
///
/// Conforming types are `Sendable`: `IosShareManager` (a `Sendable` singleton) holds one and calls it
/// from any thread.
public protocol ShareRepository: Sendable {
    /// Presents the share sheet for the given content.
    /// - Parameter content: The content to share.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError` on failure before or during presentation.
    func present(content: ShareContent) async throws -> ShareResult
}
