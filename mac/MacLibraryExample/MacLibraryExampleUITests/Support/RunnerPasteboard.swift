//
//  RunnerPasteboard.swift
//  MacLibraryExampleUITests
//
//  The only place the new tests touch the general pasteboard from the runner (UI test design U-10).
//  Needs a `ClipboardToken`. The user's content is never read, saved or restored: the runner first
//  writes its own synthetic text, and reads only after that (S2, S4).
//  Trusted Support file.
//

import AppKit
import Foundation

struct RunnerPasteboard {

    private let session: UITestSession

    init(_ token: ClipboardToken) {
        session = token.session
    }

    /// Replaces the general pasteboard with `text` and returns the change count right after.
    func write(_ text: String) throws -> Int {
        let board = NSPasteboard.general
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            throw SampleUITestError(.pasteboard, "the runner could not write the pasteboard")
        }
        return board.changeCount
    }

    /// Throws unless the change count is still `expected` (nothing else wrote in between).
    func requireUnchanged(since expected: Int) throws {
        guard NSPasteboard.general.changeCount == expected else {
            throw SampleUITestError(.pasteboard, "the general pasteboard changed after the runner's write")
        }
    }

    var changeCount: Int { NSPasteboard.general.changeCount }

    /// The text now on the pasteboard. Call only after `write` (the runner's own content was there).
    func readAfterWrite(since written: Int) throws -> String? {
        guard NSPasteboard.general.changeCount > written else {
            throw SampleUITestError(.pasteboard, "nothing replaced the runner's content")
        }
        return NSPasteboard.general.string(forType: .string)
    }
}
