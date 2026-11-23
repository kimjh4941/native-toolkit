//
//  WaitRule.swift
//  MacLibraryExampleUITests
//
//  The waiting rules of the Clipboard screen (UI test design 5.5, 6.1). Trusted Support file.
//
//  `isResultOfThisClick` is the rule the fixed Clipboard tests (C1〜C11) wait on, moved here from
//  `ClipboardSampleViewUITests` unchanged so that C12〜C17 check the one body the tests use (no
//  second copy). `judge` is the stricter rule of the new Clipboard tests (CB1〜CB6): the next result
//  exactly, with the label anchored right after the mark (U-1, U-3).
//
//  The Clipboard screen writes `✅ \n[<label>] <detail>` or `❌ \n[<label>] <detail>`
//  (`SampleOutcome.displayText`), without the `Result: ` of the other screens.
//

import Foundation

enum ClipboardWaitRule {

    /// The label a Clipboard button reports under: its name with a lower case first letter
    /// (`sampleButton("CopyText")` reports `[copyText]`).
    static func label(forButtonNamed name: String) -> String {
        name.prefix(1).lowercased() + name.dropFirst()
    }

    /// Whether what the screen shows now is the result of the click that was just made.
    ///
    /// Kept as a function of its inputs so that it can be checked directly. A mutant of the
    /// waiting rule cannot be built by breaking the app -- "the second click does nothing"
    /// needs a branch no real defect would take -- but it can be built by breaking this
    /// (レビュー v3 M-02).
    static func isResultOfThisClick(text: String, sequence: Int, before: Int,
                                    expecting label: String) -> Bool {
        // Anchored on the brackets the screen puts around the label. A bare substring let one
        // operation stand in for another whose name contains it, and the sample has several
        // such pairs: snapshot / snapshotFiltered, read / readDataPlainText,
        // copyEmpty / copyEmptyRepresentations (レビュー v4 M-05).
        sequence > before && text.contains("[\(label)]")
    }

    /// The full text the Clipboard screen shows for an outcome (U-1).
    static func expected(success: Bool, label: String, _ detail: String) -> String {
        "\(success ? "✅" : "❌") \n[\(label)] \(detail)"
    }

    /// Whether `shown` is the result of the operation started at `before` (U-3), for the new
    /// Clipboard tests. The label is anchored right after the mark, with its closing bracket and
    /// the space, so neither a longer label nor a detail word can stand in for it.
    static func judge(_ shown: ShownResult, before: Int, label: String) -> ResultLine.Verdict {
        if shown.sequence <= before { return .pending }
        if shown.sequence > before + 1 { return .overtaken }
        let anchored = [expected(success: true, label: label, ""), expected(success: false, label: label, "")]
        return anchored.contains(where: { shown.text.hasPrefix($0) }) ? .accepted : .foreign
    }
}
