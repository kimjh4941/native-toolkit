//
//  ShareRepository.swift
//  MacLibrary
//

import Foundation

/// Contract for presenting the macOS sharing UI / performing services.
/// Implemented by `ShareRepositoryImpl` in the Data layer.
public protocol ShareRepository {
    /// Presents the sharing service picker for the given content.
    /// - Parameter content: The content to share.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError` on failure before or during presentation.
    func presentPicker(content: ShareContent) async throws -> ShareResult

    /// Performs a single named sharing service directly.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - serviceName: Raw `NSSharingService.Name` value (e.g. "com.apple.share.Mail.compose").
    /// - Returns: The interaction result.
    /// - Throws: `ShareError` (`.serviceUnavailable` when the service is unknown or cannot perform).
    func performService(content: ShareContent, serviceName: String) async throws -> ShareResult

    /// Reports whether a named service can share the given content.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - serviceName: Raw `NSSharingService.Name` value.
    /// - Returns: `true` if the service exists and `canPerform(withItems:)` is true.
    /// - Throws: `ShareError` on conversion failure.
    func canPerformService(content: ShareContent, serviceName: String) async throws -> Bool
}
