//
//  Log.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
import Foundation
import os.log

/// A lightweight logging utility that wraps Apple’s Unified Logging system (os.log / Logger).
///
/// This class provides static convenience methods for emitting structured log messages
/// at different severity levels (debug / info / warning / error). All messages are tagged
/// with a caller‑supplied component *tag* to help filter output in Console.app or when
/// using the `log` command line tool.
///
/// Example:
/// ```swift
/// Log.d("Networking", "Request started")
/// Log.e("DB", "Failed to open database: \(error.localizedDescription)")
/// ```
///
/// - Note: Messages are logged with public privacy (no redaction). Do **not** pass
///   sensitive user data directly. Consider adding masking before logging secrets.
@objcMembers
public class Log: NSObject {
    private static let logger = Logger(subsystem: "com.unity.native.toolkit", category: "NativeToolkit")

    /// Internal formatter & dispatcher to the unified logging backend.
    /// - Parameters:
    ///   - level: Upper‑case level string (e.g. DEBUG / INFO / WARNING / ERROR).
    ///   - tag: Component or feature identifier.
    ///   - message: Human readable message body (already interpolated).
    private static func out(_ level: String, _ tag: String, _ message: String) {
        let logMessage = "[\(level)] \(tag): \(message)"
        
        // Unified logging (view in Console.app or via `log stream`)
        switch level {
        case "DEBUG": logger.debug("\(logMessage, privacy: .public)")
        case "INFO":  logger.info("\(logMessage, privacy: .public)")
        case "WARNING": logger.warning("\(logMessage, privacy: .public)")
        case "ERROR": logger.error("\(logMessage, privacy: .public)")
        default: logger.log("\(logMessage, privacy: .public)")
        }
    }

    /// Logs a debug level message (development / verbose diagnostics).
    public static func d(_ tag: String, _ message: String) { out("DEBUG", tag, message) }
    /// Logs an informational message (normal operational events).
    public static func i(_ tag: String, _ message: String) { out("INFO", tag, message) }
    /// Logs a warning indicating a recoverable / non‑fatal issue.
    public static func w(_ tag: String, _ message: String) { out("WARNING", tag, message) }
    /// Logs an error indicating a failure that likely impacted functionality.
    public static func e(_ tag: String, _ message: String) { out("ERROR", tag, message) }
}
