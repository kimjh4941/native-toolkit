//
//  SampleLaunchConfiguration.swift
//  IosLibraryExample
//
//  The test shape of a launch (Swift API design 12 SA-18, SA-12): which path the notification
//  events take, and whether a host delegate is set before the library's. A UI test passes it as
//  launch arguments on every launch; the sample writes it to a small file in Application Support
//  and reads the file when it is launched without them (a cold start the system makes from a
//  banner tap). UserDefaults is not used (no new required-reason API in the sample).
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.ios.nativetoolkit.example", category: "SampleLaunchConfiguration")

/// The test shape of the notification events (SA-18).
enum SampleTestMode: String, CaseIterable, Sendable {
    /// The default: `installDelegate()`, then a listener of `responses` at launch.
    case none
    /// The deprecated path: `onActionReceived` / `onTextInputActionReceived`, then `setup()`.
    case legacyReceivers
    /// `installDelegate()`, then the listener of `responses` 3 seconds later (the hub keeps what
    /// arrives before).
    case delayListener
}

/// Where the configuration of this launch came from (shown to the UI tests; MS-14).
enum SampleConfigurationSource: String, Sendable {
    /// The launch arguments of this launch.
    case arguments
    /// The file a previous launch wrote.
    case file
    /// Neither: the defaults.
    case defaults
}

struct SampleLaunchConfiguration: Equatable, Sendable {
    static let modeArgument = "-ntkSampleTestMode"
    static let hostDelegateArgument = "-ntkSampleHostDelegate"
    static let fileName = "ntk-sample-test-mode.txt"

    var mode: SampleTestMode = .none
    /// SA-12: set a host delegate before the library's.
    var hostDelegate = false

    /// The configuration of this process: from the arguments (then written to the file), or from
    /// the file, or the defaults.
    static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        directory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ) -> (configuration: SampleLaunchConfiguration, source: SampleConfigurationSource) {
        logger.debug("[resolve] arguments: \(arguments.count, privacy: .public), directory: \(directory == nil ? "nil" : "provided", privacy: .public)")
        let file = directory?.appendingPathComponent(fileName)
        if let configuration = fromArguments(arguments) {
            if let file {
                write(configuration, to: file)
            }
            return (configuration, .arguments)
        }
        if let file, let configuration = read(file) {
            return (configuration, .file)
        }
        return (SampleLaunchConfiguration(), .defaults)
    }

    /// `-ntkSampleTestMode <mode>` (required for the arguments to count) and the optional flag
    /// `-ntkSampleHostDelegate`.
    static func fromArguments(_ arguments: [String]) -> SampleLaunchConfiguration? {
        logger.debug("[fromArguments] arguments: \(arguments.count, privacy: .public)")
        guard let index = arguments.firstIndex(of: modeArgument), index + 1 < arguments.count,
              let mode = SampleTestMode(rawValue: arguments[index + 1]) else {
            return nil
        }
        return SampleLaunchConfiguration(mode: mode, hostDelegate: arguments.contains(hostDelegateArgument))
    }

    /// The file's form: `mode=<mode>` and `hostDelegate=<on|off>`, one per line.
    var fileText: String {
        "mode=\(mode.rawValue)\nhostDelegate=\(hostDelegate ? "on" : "off")\n"
    }

    static func parse(_ text: String) -> SampleLaunchConfiguration? {
        logger.debug("[parse] length: \(text.utf8.count, privacy: .public)")
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            fields[String(parts[0])] = String(parts[1])
        }
        guard let mode = fields["mode"].flatMap(SampleTestMode.init(rawValue:)),
              let host = fields["hostDelegate"], host == "on" || host == "off" else {
            return nil
        }
        return SampleLaunchConfiguration(mode: mode, hostDelegate: host == "on")
    }

    private static func write(_ configuration: SampleLaunchConfiguration, to file: URL) {
        logger.debug("[write] mode: \(configuration.mode.rawValue, privacy: .public), hostDelegate: \(configuration.hostDelegate, privacy: .public)")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(configuration.fileText.utf8).write(to: file, options: .atomic)
        } catch {
            logger.error("[write] could not write the test shape: \(String(describing: error), privacy: .public)")
        }
    }

    private static func read(_ file: URL) -> SampleLaunchConfiguration? {
        logger.debug("[read] file: \(file.lastPathComponent, privacy: .public)")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }
}
