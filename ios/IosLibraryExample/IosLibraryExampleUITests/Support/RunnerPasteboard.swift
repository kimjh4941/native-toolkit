//
//  RunnerPasteboard.swift
//  IosLibraryExampleUITests
//
//  Writes the general pasteboard from the test runner (UI test design CB1〜CB4, U-10). The runner
//  is a separate app, so the sample reads what it writes as content from another app. Needs a
//  `ClipboardToken`. The user's original pasteboard is never read nor restored. Trusted Support
//  file.
//

import XCTest
import Foundation
import UIKit

struct RunnerPasteboard {

    private let session: UITestSession

    init(_ token: ClipboardToken) {
        session = token.session
    }

    /// Writes `text` and returns the `changeCount` right after the write.
    func write(_ text: String) -> Int {
        UIPasteboard.general.string = text
        return UIPasteboard.general.changeCount
    }

    /// Writes only an image (a 1x1 opaque image) and returns the `changeCount` after the write.
    func writeImageOnly() -> Int {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        UIPasteboard.general.image = image
        return UIPasteboard.general.changeCount
    }

    /// Throws when another writer (for example Universal Clipboard) changed the pasteboard after
    /// the runner wrote it (U-10). Call right before the sample reads.
    func requireUnchanged(since changeCount: Int) throws {
        let now = UIPasteboard.general.changeCount
        guard now == changeCount else {
            throw SampleUITestError("the general pasteboard changed after the runner wrote it (\(changeCount) -> \(now)); not reading it")
        }
    }
}
