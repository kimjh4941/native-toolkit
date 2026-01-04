//
//  Log.swift
//  IosLibrary
//
//  Created by Kim Jong Hyun on 2025/04/19.
//


import Foundation

/// # Log
/// Lightweight logging utility providing uniform console output for different severity levels.
///
/// ## Overview
/// The `Log` class offers static helpers (`d`, `i`, `w`, `e`) that print tagged messages
/// prefixed with a severity indicator. It is intentionally minimal so it can be replaced or
/// redirected later (e.g. to OSLog, unified logging, or remote analytics) without touching
/// call sites.
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
/// ## Example
/// ```swift
/// Log.d("Networking", "Request started")
/// Log.i("Auth", "User signed in")
/// Log.w("Cache", "Entry expired, refetching")
/// Log.e("DB", "Migration failed")
/// ```
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
