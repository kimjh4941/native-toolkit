//
//  ShareItemConverter.swift
//  MacLibrary
//

import AppKit

/// Converts domain `ShareItem` values into AppKit share activation items.
struct ShareItemConverter {
    private let TAG = "ShareItemConverter"
    private let fileManager: FileManager

    /// Creates a converter with a custom file manager (for testability).
    /// - Parameter fileManager: The file manager used for file-existence checks. Defaults to `.default`.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Converts domain items into AppKit activation items (`String` / `URL` / `NSImage`).
    /// - Parameter items: The domain items to convert.
    /// - Returns: Converted activation items, preserving input order.
    /// - Throws: `ShareError` on invalid URL, missing file, or unreadable image.
    func convert(_ items: [ShareItem]) throws -> [Any] {
        Log.d(TAG, "[convert] items: \(items.count)")
        return try items.map { try convert($0) }
    }

    private func convert(_ item: ShareItem) throws -> Any {
        switch item {
        case .text(let value):
            return value
        case .url(let value):
            return try makeURL(from: value)
        case .imageFile(let path):
            guard let image = NSImage(contentsOfFile: path) else {
                throw ShareError.imageLoadFailed(path: path)
            }
            return image
        case .file(let path):
            guard fileManager.fileExists(atPath: path) else {
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
