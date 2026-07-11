//
//  ShareUseCases.swift
//  MacLibrary
//

import Foundation

/// Presents the sharing service picker for the given content.
public struct SharePickerUseCase {
    private let TAG = "SharePickerUseCase"
    private let repository: ShareRepository

    public init(repository: ShareRepository) {
        self.repository = repository
    }

    /// Validates and presents the sharing service picker.
    /// - Parameter content: The content to share.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError.noValidItems` if `content.items` is empty; otherwise
    ///   whatever `ShareError` the repository throws.
    public func execute(content: ShareContent) async throws -> ShareResult {
        Log.d(TAG, "[execute] items: \(content.items.count)")
        guard !content.items.isEmpty else {
            throw ShareError.noValidItems
        }
        return try await repository.presentPicker(content: content)
    }
}

/// Performs a named sharing service directly.
public struct ShareServiceUseCase {
    private let TAG = "ShareServiceUseCase"
    private let repository: ShareRepository

    public init(repository: ShareRepository) {
        self.repository = repository
    }

    /// Validates and performs the named sharing service.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - serviceName: Raw `NSSharingService.Name` value.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError.noValidItems` (empty items) / `.serviceUnavailable` (empty name),
    ///   otherwise whatever `ShareError` the repository throws.
    public func execute(content: ShareContent, serviceName: String) async throws -> ShareResult {
        Log.d(TAG, "[execute] serviceName: \(serviceName), items: \(content.items.count)")
        guard !content.items.isEmpty else {
            throw ShareError.noValidItems
        }
        guard !serviceName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ShareError.serviceUnavailable(name: serviceName)
        }
        return try await repository.performService(content: content, serviceName: serviceName)
    }
}

/// Queries whether a named service can share the content (for button enable/disable).
public struct ShareServiceQueryUseCase {
    private let TAG = "ShareServiceQueryUseCase"
    private let repository: ShareRepository

    public init(repository: ShareRepository) {
        self.repository = repository
    }

    /// Reports whether the named service can share the content.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - serviceName: Raw `NSSharingService.Name` value.
    /// - Returns: `true` if the service can share the content; `false` if items is empty.
    /// - Throws: Whatever `ShareError` the repository throws.
    public func canPerform(content: ShareContent, serviceName: String) async throws -> Bool {
        Log.d(TAG, "[canPerform] serviceName: \(serviceName), items: \(content.items.count)")
        guard !content.items.isEmpty else { return false }
        return try await repository.canPerformService(content: content, serviceName: serviceName)
    }
}
