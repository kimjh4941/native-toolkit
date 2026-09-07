//
//  ClipboardContentValidator.swift
//  MacLibrary
//

import Foundation

/// The single place where clipboard content is checked before it reaches a pasteboard.
///
/// Every write path runs through this type so that the rules cannot drift between copy and
/// append (R2-M9).
@MainActor
public struct ClipboardContentValidator {

    private let TAG = "ClipboardContentValidator"

    private let limits: ClipboardLimits
    private let typeValidator: any ClipboardTypeIdentifierValidating

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(limits: ClipboardLimits, typeValidator: any ClipboardTypeIdentifierValidating) {
        self.limits = limits
        self.typeValidator = typeValidator
    }

    /// Whether this content should be written through a lazy data provider instead of
    /// being handed to the pasteboard up front.
    ///
    /// Worth doing once an item is large enough that the synchronous copy into the pasteboard
    /// server becomes noticeable, which is what the warn threshold marks. Restricted to
    /// single item content: a provider is registered per pasteboard item, so multi-item
    /// content would need one registration each and a rollback across all of them for no
    /// benefit that has been measured.
    public func shouldUseLazyProvision(_ content: ClipboardContent) -> Bool {
        Log.d(TAG, "[shouldUseLazyProvision] content: \(ClipboardLog.content(content))")
        guard content.items.count == 1 else { return false }
        return content.totalBytes > limits.warnBytesPerRepresentation
    }

    /// Checks structure, identifiers and size.
    ///
    /// - Throws: ``ClipboardError/emptyContent``, ``ClipboardError/emptyRepresentations(itemIndex:)``,
    ///   ``ClipboardError/invalidTypeIdentifier(_:)`` or ``ClipboardError/contentTooLarge(bytes:limit:)``.
    public func validate(_ content: ClipboardContent) throws {
        Log.d(TAG, "[validate] content: \(ClipboardLog.content(content))")
        guard !content.items.isEmpty else {
            throw ClipboardError.emptyContent
        }
        for (index, item) in content.items.enumerated() {
            guard !item.representations.isEmpty else {
                throw ClipboardError.emptyRepresentations(itemIndex: index)
            }
            // Sorted so that content with several bad identifiers always reports the same one.
            for identifier in item.representations.keys.sorted() {
                guard typeValidator.isValid(identifier) else {
                    throw ClipboardError.invalidTypeIdentifier(identifier)
                }
                let bytes = item.representations[identifier]?.count ?? 0
                guard bytes <= limits.maxBytesPerRepresentation else {
                    throw ClipboardError.contentTooLarge(bytes: bytes,
                                                         limit: limits.maxBytesPerRepresentation)
                }
                if bytes > limits.warnBytesPerRepresentation {
                    // A warning only. Every pasteboard write is synchronous IPC on the main
                    // actor, so the caller should know it is getting expensive, but a large
                    // payload is not by itself an error.
                    Log.e(TAG, "[validate] representation over warn threshold: "
                          + "\(identifier), bytes: \(bytes), warn: \(limits.warnBytesPerRepresentation)")
                }
            }
        }
        let total = content.totalBytes
        guard total <= limits.maxTotalBytes else {
            throw ClipboardError.contentTooLarge(bytes: total, limit: limits.maxTotalBytes)
        }
    }
}
