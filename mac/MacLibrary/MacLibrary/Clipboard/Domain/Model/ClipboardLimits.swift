//
//  ClipboardLimits.swift
//  MacLibrary
//

import Foundation

/// Size thresholds applied before writing to a pasteboard.
///
/// Two levels are kept apart on purpose. Crossing the warn threshold only produces a log
/// entry, because every `NSPasteboard` write is a synchronous IPC on the main actor and the
/// caller should know it is getting expensive. Crossing the hard limit fails the operation.
public struct ClipboardLimits: Sendable, Equatable {
    /// Logged, but not rejected, when a single representation is larger than this.
    public let warnBytesPerRepresentation: Int
    /// Rejected with ``ClipboardError/contentTooLarge(bytes:limit:)`` beyond this.
    public let maxBytesPerRepresentation: Int
    /// Rejected when every representation of every item adds up beyond this.
    public let maxTotalBytes: Int

    /// Creates limits after validating their relationships.
    ///
    /// - Throws: ``ClipboardError/invalidConfiguration(_:)`` when a value is not positive or
    ///   the thresholds are not ordered `warn <= max <= total`.
    public init(warnBytesPerRepresentation: Int,
                maxBytesPerRepresentation: Int,
                maxTotalBytes: Int) throws {
        guard warnBytesPerRepresentation > 0,
              maxBytesPerRepresentation > 0,
              maxTotalBytes > 0 else {
            throw ClipboardError.invalidConfiguration("Clipboard limits must be positive.")
        }
        guard warnBytesPerRepresentation <= maxBytesPerRepresentation else {
            throw ClipboardError.invalidConfiguration(
                "warnBytesPerRepresentation must not exceed maxBytesPerRepresentation.")
        }
        guard maxBytesPerRepresentation <= maxTotalBytes else {
            throw ClipboardError.invalidConfiguration(
                "maxBytesPerRepresentation must not exceed maxTotalBytes.")
        }
        self.warnBytesPerRepresentation = warnBytesPerRepresentation
        self.maxBytesPerRepresentation = maxBytesPerRepresentation
        self.maxTotalBytes = maxTotalBytes
    }

    /// Non-validating initializer for values known to satisfy the constraints.
    private init(warn: Int, max: Int, total: Int) {
        self.warnBytesPerRepresentation = warn
        self.maxBytesPerRepresentation = max
        self.maxTotalBytes = total
    }

    /// Warn at 10 MiB, reject a representation at 100 MiB, reject a payload at 200 MiB.
    ///
    /// - Note: These defaults are provisional and still need measuring on real hardware.
    public static let `default` = ClipboardLimits(warn: 10 * 1024 * 1024,
                                                  max: 100 * 1024 * 1024,
                                                  total: 200 * 1024 * 1024)
}
