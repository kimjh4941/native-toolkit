//
//  CApiLog.swift
//  IosLibraryCApi
//

import os

/// The loggers of the C ABI: one category per feature (part 1, 5.15, P1-18). `IosLibrary`'s log level
/// is internal to it, so the capi logs at `.debug`, which the OS does not keep.
enum CApiLog {
    private static let subsystem = "com.jonghyunkim.nativetoolkit.IosLibraryCApi"

    static let common = Logger(subsystem: subsystem, category: "Common")
    static let clipboard = Logger(subsystem: subsystem, category: "Clipboard")
    static let notification = Logger(subsystem: subsystem, category: "Notification")
}
