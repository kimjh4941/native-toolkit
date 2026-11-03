//
//  FreshInstallMarker.swift
//  IosLibraryCApiUITestApp
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp", category: "FreshInstallMarker")

/// A file that only an uninstall removes, so that a UI test can tell the runner really deleted the
/// app before it. A file and not `UserDefaults`, as the sample (no required-reason API).
enum FreshInstallMarker {
    /// True on the first launch of this install.
    static func consume() -> Bool {
        logger.debug("[consume]")
        let manager = FileManager.default
        let url = URL.applicationSupportDirectory.appending(path: "ntk-capi-ui-launched.txt")
        guard !manager.fileExists(atPath: url.path) else {
            return false
        }
        do {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        } catch {
            // The next launch reports true again, which a UI test catches.
            let failure = error as NSError
            logger.error("[consume] could not write the marker: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")
        }
        return true
    }
}
