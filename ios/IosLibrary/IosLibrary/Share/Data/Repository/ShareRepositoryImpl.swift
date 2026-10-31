//
//  ShareRepositoryImpl.swift
//  IosLibrary
//

import Foundation
import os
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ShareRepositoryImpl")

/// Concrete implementation of `ShareRepository` backed by `UIActivityViewController`.
///
/// - Note: Not `public` because its `presenter` parameter type (`ShareSheetPresenting`) is an
///   internal Presentation-layer abstraction (UIKit dependency is intentionally confined there).
///   `IosShareManager` constructs and stores this behind the public `ShareRepository` protocol.
final class ShareRepositoryImpl: ShareRepository {

    private let presenter: ShareSheetPresenting

    /// Creates an instance with a custom presenter (for testability).
    ///
    /// File-existence checks use `FileManager.default`, which is thread-safe. It is not stored:
    /// `FileManager` is not `Sendable`, and this class must be (`ShareRepository: Sendable`).
    /// - Parameter presenter: The share sheet presenter to use. Defaults to `ShareSheetPresenter()`.
    init(presenter: ShareSheetPresenting = ShareSheetPresenter()) {
        logger.log(level: .libraryDebug, "[init] presenter: \(String(describing: type(of: presenter)), privacy: .public)")
        self.presenter = presenter
    }

    func present(content: ShareContent) async throws -> ShareResult {
        logger.log(level: .libraryDebug, "[present] items: \(content.items.count, privacy: .public), subject: \(LogRedaction.redact(content.subject), privacy: .public)")
        let items = try buildActivityItems(from: content)
        let excluded = content.excludedActivityTypes.map { UIActivity.ActivityType($0) }
        return try await presenter.present(items: items, excluded: excluded)
    }

    /// Converts `ShareContent` into `UIActivityViewController` activation items.
    ///
    /// If `subject` or `previewTitle` is provided, the first converted item is REPLACED
    /// (not appended) by a `ShareItemSource` wrapping it, so the content is shared exactly once.
    /// - Throws: `ShareError` on invalid URL, missing file, or unreadable image.
    func buildActivityItems(from content: ShareContent) throws -> [Any] {
        logger.log(level: .libraryDebug, "[buildActivityItems] items: \(content.items.count, privacy: .public)")
        var activityItems: [Any] = try content.items.map { try convert($0) }

        let hasMetadata = content.subject != nil || content.previewTitle != nil
        if hasMetadata, let first = activityItems.first {
            activityItems[0] = ShareItemSource(primaryItem: first,
                                               subject: content.subject,
                                               previewTitle: content.previewTitle)
        }
        return activityItems
    }

    private func convert(_ item: ShareItem) throws -> Any {
        switch item {
        case .text(let value):
            return value
        case .url(let value):
            return try makeURL(from: value)
        case .imageFile(let path):
            guard let image = UIImage(contentsOfFile: path) else {
                throw ShareError.imageLoadFailed(path: path)
            }
            return image
        case .file(let path):
            guard FileManager.default.fileExists(atPath: path) else {
                throw ShareError.fileNotFound(path: path)
            }
            return URL(fileURLWithPath: path)
        }
    }

    /// Validates and parses a URL string. `URL(string:)` succeeding is not sufficient
    /// (it also accepts relative / scheme-less strings), so scheme and host are checked explicitly.
    private func makeURL(from string: String) throws -> URL {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            throw ShareError.invalidURL(string)
        }
        switch scheme {
        case "http", "https":
            guard let host = url.host, !host.isEmpty else {
                throw ShareError.invalidURL(string)
            }
        case "file":
            guard url.isFileURL else {
                throw ShareError.invalidURL(string)
            }
        default:
            throw ShareError.invalidURL(string)
        }
        return url
    }
}
