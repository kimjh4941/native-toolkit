//
//  ClipboardRepository.swift
//  IosLibrary
//

import Foundation

/// Defines the contract for `UIPasteboard` operations.
///
/// Every member is `@MainActor`-isolated because the implementation touches `UIPasteboard`.
/// `copy` / `append` are `async throws` because their content enum may carry an image, which is
/// encoded/decoded on a background executor before the (synchronous) pasteboard write; non-image
/// content is written in the same actor turn without a background hop (see the design's
/// "System API に合わせた同期・非同期設計" section). All other members mirror synchronous
/// `UIPasteboard` APIs and remain synchronous.
///
/// Note: Clipboard change observation (`changedNotification` / `removedNotification`) is
/// intentionally not part of this Port. The system listener is owned by the Manager layer
/// (`IosClipboardManager`); this Port only covers read/write/metadata/clear/detection operations.
@MainActor
public protocol ClipboardRepository: AnyObject, Sendable {
    /// Creates (or resolves an existing named) pasteboard.
    /// - Returns: The resolved scope (`.unique` carries the generated name).
    func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope

    /// Invalidates a named pasteboard. A no-op (success) for `.general` is not allowed here;
    /// callers must reject `.general` before calling this (see `RemovePasteboardUseCase`).
    func removePasteboard(_ scope: PasteboardScope) throws

    /// Writes `content`, replacing any existing items (`setItems(_:options:)`).
    func copy(_ content: ClipboardContent, options: ClipboardCopyOptions, scope: PasteboardScope) async throws

    /// Appends `content` to the existing items (`addItems(_:)`). Cannot carry privacy options.
    func append(_ content: ClipboardContent, scope: PasteboardScope) async throws

    /// Reads all items synchronously, without their large payloads (see `ClipboardItemData`).
    func read(scope: PasteboardScope) throws -> ClipboardReadResult

    /// Reads the raw `Data` for the given UTI from the first item, or `nil` if absent.
    func readData(utType: String, scope: PasteboardScope) throws -> Data?

    /// Reads metadata only, using system APIs documented to avoid user notifications/prompts.
    /// - Parameter matchingTypes: When non-nil, also computes `matchingItemIndexes` via
    ///   `itemSet(withPasteboardTypes:)`.
    func snapshot(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot

    /// Clears all items (`items = []`).
    func clear(scope: PasteboardScope) throws

    /// The pasteboard's `changeCount`, for foreground-diff detection.
    func changeCount(scope: PasteboardScope) throws -> Int

    /// Detects which patterns are present, without reading matched values.
    func detectPatterns(_ patterns: Set<ClipboardDetectionPattern>, scope: PasteboardScope) async throws -> Set<ClipboardDetectionPattern>

    /// Detects patterns and reads their matched values.
    func detectValues(_ patterns: Set<ClipboardDetectionPattern>, scope: PasteboardScope) async throws -> ClipboardDetectedValues
}
