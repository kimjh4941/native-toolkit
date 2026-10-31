//
//  Log.swift
//  IosLibrary
//
//  Created by Kim Jong Hyun on 2025/04/19.
//


import Foundation

/// # Log
/// Lightweight logging utility that prints tagged messages with a severity prefix.
///
/// - Important: Deprecated. `IosLibrary` itself no longer uses `Log`: it logs through
///   `os.Logger` (subsystem `com.jonghyunkim.nativetoolkit.IosLibrary`, one category per type),
///   with a privacy level for every interpolated value, so that values are redacted in the
///   unified log unless they are safe to show. Use your own `os.Logger` instead.
///   `Log` is kept so that existing callers still build, and it behaves as before: every call
///   is a `print`, in Debug and in Release builds, and nothing is redacted. Do not pass secret
///   values (passwords, input text, message contents) to it.
///
/// ## Thread Safety
/// Methods are static and perform a simple `print`, which is thread-safe for individual lines.
/// Ordering across threads is not guaranteed.
///
/// ## Severity Mapping
/// - `d` – Debug (verbose, development only insight)
/// - `i` – Info (normal operational messages)
/// - `w` – Warning (recoverable or suspicious conditions)
/// - `e` – Error (failures requiring attention)
///
/// ## Migration
/// ```swift
/// import os
///
/// private let logger = Logger(subsystem: "com.example.app", category: "Networking")
///
/// logger.debug("Request started, id: \(requestID, privacy: .public)")
/// ```
@available(*, deprecated, message: "Use os.Logger")
@objcMembers
public class Log: NSObject {
    /// Logs a debug (verbose) message.
    /// - Parameters:
    ///   - tag: Logical component or category (e.g. "Networking").
    ///   - message: Human-readable detail.
    public static func d(_ tag: String, _ message: String) {
        print("[DEBUG] \(tag): \(message)")
    }

    /// Logs an informational message.
    /// - Parameters:
    ///   - tag: Component / category.
    ///   - message: Descriptive text.
    public static func i(_ tag: String, _ message: String) {
        print("[INFO] \(tag): \(message)")
    }

    /// Logs a warning indicating a non-fatal, notable condition.
    /// - Parameters:
    ///   - tag: Component / category.
    ///   - message: Warning description.
    public static func w(_ tag: String, _ message: String) {
        print("[WARNING] \(tag): \(message)")
    }

    /// Logs an error describing a failure scenario.
    /// - Parameters:
    ///   - tag: Component / category.
    ///   - message: Error details (avoid sensitive data).
    public static func e(_ tag: String, _ message: String) {
        print("[ERROR] \(tag): \(message)")
    }
}
