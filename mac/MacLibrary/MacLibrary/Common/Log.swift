//
//  Log.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
import Foundation
import os.log

@objcMembers
public class Log: NSObject {
    private static let logger = Logger(subsystem: "com.unity.native.toolkit", category: "NativeToolkit")

    private static func out(_ level: String, _ tag: String, _ message: String) {
        let logMessage = "[\(level)] \(tag): \(message)"
        
        // Unified Logging（Console.app / `log stream` で確認）
        switch level {
        case "DEBUG": logger.debug("\(logMessage, privacy: .public)")
        case "INFO":  logger.info("\(logMessage, privacy: .public)")
        case "WARNING": logger.warning("\(logMessage, privacy: .public)")
        case "ERROR": logger.error("\(logMessage, privacy: .public)")
        default: logger.log("\(logMessage, privacy: .public)")
        }
    }

    public static func d(_ tag: String, _ message: String) { out("DEBUG", tag, message) }
    public static func i(_ tag: String, _ message: String) { out("INFO", tag, message) }
    public static func w(_ tag: String, _ message: String) { out("WARNING", tag, message) }
    public static func e(_ tag: String, _ message: String) { out("ERROR", tag, message) }
}
