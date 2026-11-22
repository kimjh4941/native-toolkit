//
//  LaunchShape.swift
//  IosLibraryCApiUITestApp
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp", category: "LaunchShape")

/// The test shape of a launch (part 2, TB-8): the section to draw and whether the notification listeners are
/// registered inside the launch. A UI test sets it in the launch environment; the app writes it to a file in
/// Application Support and reads the file when it is launched without it, which is how the system starts the
/// app for a notification tap (a cold start gets no environment). As the sample's SA-18; a file and not
/// `UserDefaults` (no required-reason API).
struct LaunchShape: Equatable, Sendable {
    static let sectionVariable = "NTK_CAPI_SECTION"
    static let listenVariable = "NTK_CAPI_LISTEN_AT_LAUNCH"
    static let fileName = "ntk-capi-ui-launch-shape.txt"

    /// nil draws every section.
    var section: String?
    var listensAtLaunch = false

    /// Where this launch's shape came from, for a result line: `environment`, `file` or `defaults`.
    enum Source: String, Sendable {
        case environment
        case file
        case defaults
    }

    static let current = resolve()

    /// `saved` is whether the file now holds this launch's shape; nil when the shape came from no environment.
    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        directory: URL = URL.applicationSupportDirectory) -> (shape: LaunchShape, source: Source, saved: Bool?) {
        logger.debug("[resolve] environment: \(environment.count, privacy: .public)")
        let file = directory.appending(path: fileName)
        if let section = environment[sectionVariable] {
            let shape = LaunchShape(section: section, listensAtLaunch: environment[listenVariable] == "1")
            return (shape, .environment, write(shape, to: file))
        }
        if let text = try? String(contentsOf: file, encoding: .utf8), let shape = parse(text) {
            return (shape, .file, nil)
        }
        return (LaunchShape(), .defaults, nil)
    }

    /// The `launch.shape` line: where the shape came from, its two values and, from the environment, whether it was
    /// saved for a later cold start.
    static var line: String {
        let (shape, source, saved) = current
        let savedText = saved.map { $0 ? "1" : "0" } ?? "-"
        return "source=\(source.rawValue) section=\(shape.section ?? "all") listen=\(shape.listensAtLaunch ? 1 : 0) saved=\(savedText)"
    }

    /// `section=<id>` and `listen=<0|1>`, one per line.
    var fileText: String {
        "section=\(section ?? "")\nlisten=\(listensAtLaunch ? "1" : "0")\n"
    }

    static func parse(_ text: String) -> LaunchShape? {
        logger.debug("[parse] length: \(text.utf8.count, privacy: .public)")
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            fields[String(parts[0])] = String(parts[1])
        }
        guard let section = fields["section"], let listen = fields["listen"] else { return nil }
        return LaunchShape(section: section.isEmpty ? nil : section, listensAtLaunch: listen == "1")
    }

    /// The old file goes first, and goes again when the new one cannot be written, so that a later cold start takes
    /// the defaults instead of an older test's shape. When both removals fail too, the old file can stay; the launch
    /// then reports `saved=0`, and the cold-start UI test, which checks `saved=1` before it terminates the app, fails.
    private static func write(_ shape: LaunchShape, to file: URL) -> Bool {
        logger.debug("[write] listensAtLaunch: \(shape.listensAtLaunch, privacy: .public)")
        let manager = FileManager.default
        do {
            if manager.fileExists(atPath: file.path) {
                try manager.removeItem(at: file)
            }
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(shape.fileText.utf8).write(to: file, options: .atomic)
            return true
        } catch {
            let failure = error as NSError
            logger.error("[write] could not write the shape: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")
            try? manager.removeItem(at: file)
            return false
        }
    }
}
