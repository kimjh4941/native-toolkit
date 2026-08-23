//
//  ClipboardTimeouts.swift
//  IosLibrary
//

import Foundation

/// Timeouts applied to asynchronous clipboard operations.
///
/// Each timeout is owned by the layer that starts the corresponding operation and is measured
/// from the moment the underlying system API call is issued.
public struct ClipboardTimeouts: Equatable, Sendable {
    /// Timeout for `detectedPatterns(for:)` / `detectedValues(for:)` (P-9 / P-10).
    public let detection: TimeInterval
    /// Timeout for a single `NSItemProvider` load (P-11 / P-16), per provider.
    public let providerLoad: TimeInterval
    /// Timeout for background image encode/decode.
    public let imageCoding: TimeInterval

    /// Returns nil unless every timeout is finite and greater than zero.
    public init?(detection: TimeInterval, providerLoad: TimeInterval, imageCoding: TimeInterval) {
        guard detection.isFinite, detection > 0,
              providerLoad.isFinite, providerLoad > 0,
              imageCoding.isFinite, imageCoding > 0 else {
            return nil
        }
        self.detection = detection
        self.providerLoad = providerLoad
        self.imageCoding = imageCoding
    }

    private init(uncheckedDetection: TimeInterval, providerLoad: TimeInterval, imageCoding: TimeInterval) {
        self.detection = uncheckedDetection
        self.providerLoad = providerLoad
        self.imageCoding = imageCoding
    }

    public static let `default` = ClipboardTimeouts(
        uncheckedDetection: 5.0,
        providerLoad: 15.0,
        imageCoding: 10.0
    )
}
