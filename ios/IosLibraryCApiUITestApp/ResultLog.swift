//
//  ResultLog.swift
//  IosLibraryCApiUITestApp
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp", category: "ResultLog")

/// The result lines of this process, in the order they came. This is what a UI test reads.
@MainActor
final class ResultLog: ObservableObject {
    static let shared = ResultLog()

    @Published private(set) var lines: [String] = []

    /// From any thread. The line may hold a value of the test, so only its length is logged.
    nonisolated static func add(_ line: String) {
        logger.debug("[add] line length: \(line.utf8.count, privacy: .public)")
        DispatchQueue.main.async {
            shared.lines.append(line)
        }
    }
}
