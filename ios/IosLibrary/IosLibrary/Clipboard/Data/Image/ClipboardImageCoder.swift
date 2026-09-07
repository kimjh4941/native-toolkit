//
//  ClipboardImageCoder.swift
//  IosLibrary
//

import Foundation
import UIKit

/// Performs image decode/encode off the main actor, enforcing `ClipboardLimits.maxImagePixelCount`
/// and a coding timeout via `ClipboardAsyncRaceCoordinator`.
///
/// Every `UIImage` instance is created and consumed entirely within a single detached task's
/// synchronous body and never crosses an `await` boundary as a value — only `Sendable` `Data` /
/// `Int` results are returned — so this is safe regardless of `UIImage`'s own `Sendable` status.
final class ClipboardImageCoder: @unchecked Sendable {
    private let TAG = "ClipboardImageCoder"
    private let limits: ClipboardLimits
    private let timeouts: ClipboardTimeouts

    init(limits: ClipboardLimits = .default, timeouts: ClipboardTimeouts = .default) {
        self.limits = limits
        self.timeouts = timeouts
    }

    /// Validates that `data` decodes as an image within `maxImagePixelCount`. Throws
    /// `.invalidImageData` / `.contentTooLarge` / `.timedOut(.imageCoding)` / `.cancelled`.
    func validateImageData(_ data: Data) async throws {
        Log.d(TAG, "[validateImageData] byteCount: \(ClipboardLog.redactedData(byteCount: data.count))")
        let limits = self.limits
        try await ClipboardAsyncRaceCoordinator.run(timeout: timeouts.imageCoding, operationKind: .imageCoding) {
            try await Task.detached(priority: .userInitiated) {
                guard let image = UIImage(data: data) else {
                    throw ClipboardError.invalidImageData
                }
                let pixelCount = Self.pixelCount(of: image)
                guard pixelCount <= limits.maxImagePixelCount else {
                    throw ClipboardError.contentTooLarge(byteCount: pixelCount, limit: limits.maxImagePixelCount)
                }
            }.value
        }
    }

    /// Loads the file at `path`, validates it decodes as an image within `maxImagePixelCount`,
    /// and returns re-encoded PNG `Data`.
    func loadAndEncodeImageFile(atPath path: String) async throws -> Data {
        Log.d(TAG, "[loadAndEncodeImageFile] path: \(ClipboardLog.redactedPath(path))")
        let limits = self.limits
        return try await ClipboardAsyncRaceCoordinator.run(timeout: timeouts.imageCoding, operationKind: .imageCoding) {
            try await Task.detached(priority: .userInitiated) {
                guard let image = UIImage(contentsOfFile: path) else {
                    throw ClipboardError.imageLoadFailed(path: path)
                }
                let pixelCount = Self.pixelCount(of: image)
                guard pixelCount <= limits.maxImagePixelCount else {
                    throw ClipboardError.contentTooLarge(byteCount: pixelCount, limit: limits.maxImagePixelCount)
                }
                guard let png = image.pngData() else {
                    throw ClipboardError.imageEncodingFailed
                }
                guard png.count <= limits.maxCopyByteCount else {
                    throw ClipboardError.contentTooLarge(byteCount: png.count, limit: limits.maxCopyByteCount)
                }
                return png
            }.value
        }
    }

    /// Re-encodes a pasted image's raw `Data` to PNG, enforcing `maxLoadByteCount` on the output.
    /// Used by the paste path (S6 / S11).
    func encodePastedImage(_ data: Data) async throws -> Data {
        Log.d(TAG, "[encodePastedImage] byteCount: \(ClipboardLog.redactedData(byteCount: data.count))")
        let limits = self.limits
        return try await ClipboardAsyncRaceCoordinator.run(timeout: timeouts.imageCoding, operationKind: .imageCoding) {
            try await Task.detached(priority: .userInitiated) {
                guard let image = UIImage(data: data) else {
                    throw ClipboardError.unexpectedType
                }
                let pixelCount = Self.pixelCount(of: image)
                guard pixelCount <= limits.maxImagePixelCount else {
                    throw ClipboardError.contentTooLarge(byteCount: pixelCount, limit: limits.maxImagePixelCount)
                }
                guard let png = image.pngData() else {
                    throw ClipboardError.imageEncodingFailed
                }
                guard png.count <= limits.maxLoadByteCount else {
                    throw ClipboardError.contentTooLarge(byteCount: png.count, limit: limits.maxLoadByteCount)
                }
                return png
            }.value
        }
    }

    private static func pixelCount(of image: UIImage) -> Int {
        Int(image.size.width * image.scale) * Int(image.size.height * image.scale)
    }
}
