//
//  CApiRow.swift
//  IosLibraryCApiUITestApp
//

import Foundation
import UIKit
import os

private let subsystem = "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp"
private let catalogLogger = Logger(subsystem: subsystem, category: "CApiRowCatalog")
private let reportLogger = Logger(subsystem: subsystem, category: "RowReport")
private let runnerLogger = Logger(subsystem: subsystem, category: "RowRunner")
private let sceneStateLogger = Logger(subsystem: subsystem, category: "SceneState")

/// One call of the C ABI a UI test can start. To add one: a value in a section of `Rows/`. The list
/// on the screen, both ways of starting it and the result line come from this value.
struct CApiRow: Identifiable, Sendable {
    /// `<feature>.<name>`. The UI tests find the row's buttons by it (`row.<id>.run`).
    let id: String
    /// Called on the main thread. It may report at any time, from any thread, any number of times
    /// (a C completion or a C event reports later).
    let call: @MainActor @Sendable (RowReport) -> Void
}

struct CApiRowSection: Identifiable, Sendable {
    let id: String
    let rows: [CApiRow]
}

/// The sections of the app and the ones on the screen.
enum CApiRowCatalog {
    /// A UI test names the section it uses in the launch environment (`LaunchShape`), because the cost
    /// of every tap grows with what is drawn (working notes 5.10). A launch without it (a person, or a
    /// process the system starts for a notification) takes the section the last launch with it wrote,
    /// or draws them all.

    static let sections = [CommonRows.section, NotificationRows.section, ClipboardRows.section, DialogRows.section, ShareRows.section]

    static let drawn = drawn(selected: LaunchShape.current.shape.section)

    /// What this launch drew, in a result line, because a test may read no row at all: the section,
    /// `all` without a selection, or `unknown`, on which `CApiUITestApp.launch` fails.
    static let drawnDescription = description(selected: LaunchShape.current.shape.section)

    static func description(selected: String?) -> String {
        catalogLogger.debug("[description] selected: \(selected ?? "nil", privacy: .public)")
        guard let selected else {
            return "all"
        }
        return sections.contains { $0.id == selected } ? selected : "unknown"
    }

    /// Nothing for an unknown section.
    static func drawn(selected: String?) -> [CApiRowSection] {
        catalogLogger.debug("[drawn] selected: \(selected ?? "nil", privacy: .public)")
        guard let selected else {
            return sections
        }
        return sections.filter { $0.id == selected }
    }
}

/// Writes the result lines of one call: `[<row id>@<scene state when the call was made>] <value>`.
struct RowReport: Sendable {
    let rowId: String
    let sceneState: String

    func callAsFunction(_ value: String) {
        reportLogger.debug("[report] rowId: \(rowId, privacy: .public), sceneState: \(sceneState, privacy: .public), value length: \(value.utf8.count, privacy: .public)")
        ResultLog.add("[\(rowId)@\(sceneState)] \(value)")
    }
}

/// How a row is started.
enum RowRunner {
    /// Long enough for a UI test to move the app to the background or pull Control Center over it
    /// (part 1, chapter 6, "テストの口"), as `showAfter3Seconds` of the sample.
    static let delay: TimeInterval = 3

    /// The call in this main turn.
    @MainActor
    static func run(_ row: CApiRow) {
        runnerLogger.debug("[run] id: \(row.id, privacy: .public)")
        row.call(RowReport(rowId: row.id, sceneState: SceneState.current()))
    }

    /// The call `delay` seconds later, in whatever state the app is then. The result line says which.
    @MainActor
    static func runAfterDelay(_ row: CApiRow) {
        runnerLogger.debug("[runAfterDelay] id: \(row.id, privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                run(row)
            }
        }
    }
}

/// The activation state of the app's scenes, so that a UI test can tell it reached the state it
/// wanted (the sample's MS-02).
enum SceneState {
    @MainActor
    static func current() -> String {
        sceneStateLogger.debug("[current]")
        let states = UIApplication.shared.connectedScenes.map { scene -> String in
            switch scene.activationState {
            case .foregroundActive: return "foregroundActive"
            case .foregroundInactive: return "foregroundInactive"
            case .background: return "background"
            case .unattached: return "unattached"
            @unknown default: return "unknown"
            }
        }
        return states.isEmpty ? "none" : states.sorted().joined(separator: ",")
    }
}
