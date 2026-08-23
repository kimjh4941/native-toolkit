//
//  ClipboardLimits.swift
//  IosLibrary
//

import Foundation

/// Size limits applied to clipboard content and loaded items.
public struct ClipboardLimits: Equatable, Sendable {
    /// Maximum total byte count for a single `copy` / `append` item (see the per-kind sizing rules).
    public let maxCopyByteCount: Int
    /// Maximum accepted byte count when loading an item via `loadItem`.
    public let maxLoadByteCount: Int
    /// Maximum accepted pixel count (`width * height`) for image content.
    public let maxImagePixelCount: Int

    /// Returns nil unless every limit is greater than zero.
    public init?(maxCopyByteCount: Int, maxLoadByteCount: Int, maxImagePixelCount: Int) {
        guard maxCopyByteCount > 0, maxLoadByteCount > 0, maxImagePixelCount > 0 else {
            return nil
        }
        self.maxCopyByteCount = maxCopyByteCount
        self.maxLoadByteCount = maxLoadByteCount
        self.maxImagePixelCount = maxImagePixelCount
    }

    private init(uncheckedMaxCopyByteCount: Int, maxLoadByteCount: Int, maxImagePixelCount: Int) {
        self.maxCopyByteCount = uncheckedMaxCopyByteCount
        self.maxLoadByteCount = maxLoadByteCount
        self.maxImagePixelCount = maxImagePixelCount
    }

    public static let `default` = ClipboardLimits(
        uncheckedMaxCopyByteCount: 64 * 1024 * 1024,
        maxLoadByteCount: 64 * 1024 * 1024,
        maxImagePixelCount: 100_000_000
    )
}
