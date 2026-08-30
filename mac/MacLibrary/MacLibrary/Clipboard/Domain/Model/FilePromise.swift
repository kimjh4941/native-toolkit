//
//  FilePromise.swift
//  MacLibrary
//

import Foundation

/// Where the bytes of a promised file come from.
///
/// The two cases exist because the Unity bridge cannot carry a Swift closure across the C
/// ABI. Native callers supply a writer; the bridge supplies a path that is snapshotted into
/// app-owned staging at registration time, so the promise still succeeds if the original
/// file is later moved or deleted.
public enum FilePromiseSource: Sendable {
    /// Native callers. The argument is the destination **file** URL, not a directory.
    case writer(@Sendable (URL) throws -> Void)
    /// Path based callers. The contents are snapshotted at registration time.
    case snapshot(URL)
}

/// A file the app promises to produce on demand.
public struct FilePromiseRequest: Sendable {
    /// Uniform type identifier of the promised file. Must conform to `public.data`
    /// or `public.directory`.
    public let fileTypeIdentifier: String
    /// Base file name. Must not be empty, contain a path separator, or be `.` or `..`.
    public let fileName: String
    /// Where the bytes come from.
    public let source: FilePromiseSource

    public init(fileTypeIdentifier: String, fileName: String, source: FilePromiseSource) {
        self.fileTypeIdentifier = fileTypeIdentifier
        self.fileName = fileName
        self.source = source
    }
}

/// One event from a file promise receive session.
public enum FilePromiseReceiptEvent: Sendable {
    /// A promised file finished arriving.
    case received(URL)
    /// One promised file failed. Other files in the same session continue.
    case failed(ClipboardError)
    /// The session ended. Delivered at most once.
    case finished(FilePromiseReceipt)
}

/// Summary of a completed file promise receive session.
public struct FilePromiseReceipt: Sendable, Equatable {
    /// Why the session ended.
    public enum Termination: Sendable, Equatable {
        /// No new file arrived within the quiet interval.
        case quiescence
        /// The overall timeout elapsed.
        case overallTimeout
        /// The caller cancelled explicitly.
        case cancelled
    }

    public let urls: [URL]
    public let failures: [ClipboardError]
    public let terminatedBy: Termination

    public init(urls: [URL], failures: [ClipboardError], terminatedBy: Termination) {
        self.urls = urls
        self.failures = failures
        self.terminatedBy = terminatedBy
    }
}

/// Timing policy for deciding when a receive session has ended.
///
/// - Important: `NSFilePromiseReceiver` does not guarantee that `fileTypes.count` equals the
///   number of promised files, so there is no reliable total to count down from. Termination
///   is therefore a heuristic: quiet for long enough, or the overall timeout.
public struct FilePromiseReceiptPolicy: Sendable, Equatable {
    /// End the session when no file has arrived for this long.
    public let quietInterval: TimeInterval
    /// End the session after this long regardless of activity.
    public let overallTimeout: TimeInterval

    /// Creates a policy after validating it.
    ///
    /// - Throws: ``ClipboardError/invalidConfiguration(_:)`` when a value is not positive,
    ///   `quietInterval` is not shorter than `overallTimeout`, or `overallTimeout` exceeds
    ///   one hour.
    public init(quietInterval: TimeInterval, overallTimeout: TimeInterval) throws {
        guard quietInterval > 0, overallTimeout > 0 else {
            throw ClipboardError.invalidConfiguration("Receipt policy intervals must be positive.")
        }
        guard quietInterval < overallTimeout else {
            throw ClipboardError.invalidConfiguration(
                "quietInterval must be shorter than overallTimeout.")
        }
        guard overallTimeout <= 3600 else {
            throw ClipboardError.invalidConfiguration("overallTimeout must not exceed 3600 seconds.")
        }
        self.quietInterval = quietInterval
        self.overallTimeout = overallTimeout
    }

    private init(quiet: TimeInterval, overall: TimeInterval) {
        self.quietInterval = quiet
        self.overallTimeout = overall
    }

    /// Two second quiet interval, sixty second overall timeout.
    public static let `default` = FilePromiseReceiptPolicy(quiet: 2, overall: 60)
}
