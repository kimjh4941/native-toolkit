//
//  ClipboardRepository.swift
//  MacLibrary
//

import Foundation

/// Converts between domain types and `NSPasteboard`.
///
/// Every method that maps to a synchronous `NSPasteboard` call stays synchronous; only the
/// detection APIs, which are `async throws` on the system side, are asynchronous here. The
/// whole protocol is main actor isolated because `NSPasteboard` and `NSPasteboardItem` are
/// not `Sendable` and must not cross an isolation boundary.
///
/// Arguments and results are domain value types only. Platform objects never appear, and
/// registered platform objects are referred to by opaque handles.
@MainActor
public protocol ClipboardRepository {

    // MARK: Pasteboard lifetime

    /// Creates or fetches a pasteboard and returns the scope that names it.
    func createPasteboard(_ request: PasteboardCreationRequest) throws -> PasteboardScope

    /// Releases a pasteboard's server side resources.
    ///
    /// - Throws: ``ClipboardError/cannotReleaseStandardPasteboard(name:)`` for the general
    ///   pasteboard and the other standard names, which must never be released.
    func removePasteboard(_ scope: PasteboardScope) throws

    // MARK: Writing

    /// Takes ownership and writes `content`, returning proof of ownership.
    func write(_ content: ClipboardContent,
               options: ClipboardCopyOptions,
               scope: PasteboardScope) throws -> PasteboardOwnership

    /// Takes ownership and writes a lazily provided item for the registered handle.
    func writePromised(handle: PasteboardPromiseHandle,
                       types: [String],
                       options: ClipboardCopyOptions,
                       scope: PasteboardScope) throws -> PasteboardOwnership

    /// Appends to a pasteboard this app still owns.
    ///
    /// - Throws: ``ClipboardError/ownershipLost(expected:actual:)`` when the change count no
    ///   longer matches, before attempting the write.
    func append(_ content: ClipboardContent,
                ownership: PasteboardOwnership) throws -> PasteboardOwnership

    // MARK: Reading

    /// Reads every item and every representation.
    func read(scope: PasteboardScope) throws -> ClipboardReadResult

    /// Reads the bytes for one uniform type identifier. A missing type is `nil`, not an error.
    func readData(utType: String, scope: PasteboardScope) throws -> Data?

    /// Reads type information without reading any payload.
    ///
    /// - Parameter matchingTypes: `nil` disables filtering. An empty array is rejected with
    ///   ``ClipboardError/emptyTypeFilter``.
    func snapshot(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot

    // MARK: Clearing and observing

    /// Clears the pasteboard and returns the new change count.
    func clear(scope: PasteboardScope) throws -> Int

    /// Current change count, used for observation and stale detection.
    func changeCount(scope: PasteboardScope) throws -> Int

    // MARK: Detection

    /// Reports which patterns match without reading the contents.
    func detectPatterns(_ patterns: Set<ClipboardDetectionPattern>,
                        scope: PasteboardScope) async throws -> Set<ClipboardDetectionPattern>

    /// Reads the matching values. The system notifies the user and may deny access.
    func detectValues(_ patterns: Set<ClipboardDetectionPattern>,
                      scope: PasteboardScope) async throws -> ClipboardDetectedValues

    /// Reads limited metadata without reading the contents.
    func detectMetadata(scope: PasteboardScope) async throws -> ClipboardDetectedMetadata

    /// Current access behaviour, or ``ClipboardAccessBehavior/unavailable`` below macOS 15.4.
    func accessBehavior(scope: PasteboardScope) throws -> ClipboardAccessBehavior

    // MARK: File promises

    /// Writes a registered file promise provider onto a pasteboard.
    ///
    /// - Returns: Ownership to hand to the registry so stale detection has a baseline.
    func writeFilePromise(handle: FilePromiseHandle,
                          scope: PasteboardScope) throws -> PasteboardOwnership

    /// Starts receiving promised files for a registered receipt session.
    func startReceivingFilePromises(handle: FilePromiseReceiptHandle,
                                    destinationDirectory: URL,
                                    scope: PasteboardScope) throws
}
