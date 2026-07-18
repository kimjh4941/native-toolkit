//
//  ShareRepositoryImpl.swift
//  MacLibrary
//

import Foundation

/// Concrete implementation of `ShareRepository` backed by `NSSharingServicePicker` / `NSSharingService`.
///
/// - Note: Not `public` because its `presenter` parameter type (`SharePickerPresenting`) is an
///   internal Presentation-layer abstraction (AppKit dependency is intentionally confined there).
///   `MacShareManager` constructs and stores this behind the public `ShareRepository` protocol.
final class ShareRepositoryImpl: ShareRepository {

    private let TAG = "ShareRepositoryImpl"
    private let presenter: SharePickerPresenting
    private let converter: ShareItemConverter

    /// Creates an instance with a custom presenter and converter (for testability).
    /// - Parameters:
    ///   - presenter: The sharing picker presenter to use. Defaults to `SharePickerPresenter()`.
    ///   - converter: The item converter to use. Defaults to `ShareItemConverter()`.
    init(presenter: SharePickerPresenting = SharePickerPresenter(), converter: ShareItemConverter = ShareItemConverter()) {
        Log.d(TAG, "[init] presenter: \(presenter), converter: \(converter)")
        self.presenter = presenter
        self.converter = converter
    }

    func presentPicker(content: ShareContent) async throws -> ShareResult {
        Log.d(TAG, "[presentPicker] items: \(content.items.count), excluded: \(content.excludedServiceTitles.count)")
        let items = try converter.convert(content.items)
        return try await presenter.presentPicker(items: items,
                                                 excludedServiceTitles: content.excludedServiceTitles)
    }

    func performService(content: ShareContent, serviceName: String) async throws -> ShareResult {
        Log.d(TAG, "[performService] serviceName: \(serviceName), items: \(content.items.count)")
        let items = try converter.convert(content.items)
        return try await presenter.performService(items: items,
                                                  serviceName: serviceName,
                                                  recipients: content.recipients,
                                                  subject: content.subject)
    }

    func canPerformService(content: ShareContent, serviceName: String) async throws -> Bool {
        Log.d(TAG, "[canPerformService] serviceName: \(serviceName), items: \(content.items.count)")
        let items = try converter.convert(content.items)
        return await presenter.canPerform(items: items, serviceName: serviceName)
    }
}
