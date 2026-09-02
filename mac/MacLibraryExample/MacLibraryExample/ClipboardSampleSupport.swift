//
//  ClipboardSampleSupport.swift
//  MacLibraryExample
//

import SwiftUI
import AppKit
import MacLibrary

// MARK: - Result formatting

/// The one place a result becomes text.
///
/// Split from the view so the display and log rules can be tested without running the UI, and
/// so the two are never written twice. `displayText` and `logText` deliberately differ:
/// `ClipboardError.errorMessage` can carry an input value, and a log is copied wherever logs
/// are collected (sample plan section 3.4 / 7.1).
enum SampleOutcome: Equatable {
    case success(label: String, detail: String)
    case clipboardFailure(label: String, code: Int, message: String)
    case otherFailure(label: String, description: String)

    /// Codes whose message embeds a name the caller chose.
    ///
    /// 1508 is not here: `cannotReleaseStandardPasteboard` can only ever name a standard
    /// pasteboard, which is public vocabulary rather than the caller's data.
    static let codesWithACallerSuppliedName: Set<Int> = [1505, 1507]

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// What the screen shows.
    var displayText: String {
        switch self {
        case .success(let label, let detail):
            return "✅ \n[\(label)] \(detail)"
        case .clipboardFailure(let label, let code, let message):
            guard !Self.codesWithACallerSuppliedName.contains(code) else {
                return "❌ \n[\(label)] errorCode=\(code) "
                    + "(the requested pasteboard name is not shown)"
            }
            return "❌ \n[\(label)] errorCode=\(code), errorMessage=\(message)"
        case .otherFailure(let label, let description):
            return "❌ \n[\(label)] error=\(description)"
        }
    }

    /// What the log records. Never the payload, and never a message.
    var logText: String {
        switch self {
        case .success(let label, _):
            return "[\(label)] ok"
        case .clipboardFailure(let label, let code, _):
            return "[\(label)] failed code: \(code)"
        case .otherFailure(let label, _):
            return "[\(label)] failed"
        }
    }
}

/// How an operation that was expected to fail actually behaved.
enum ExpectedErrorVerdict: Equatable {
    case matched(Int)
    case succeededUnexpectedly
    case differentCode(expected: Int, actual: Int)

    var isSuccess: Bool {
        if case .matched = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .matched(let code):
            return "expected \(code) as designed"
        case .succeededUnexpectedly:
            return "the call succeeded, but a failure was expected"
        case .differentCode(let expected, let actual):
            return "expected \(expected), got \(actual)"
        }
    }
}

enum ExpectedErrorJudge {
    /// Decides the verdict from what the call produced.
    ///
    /// Separated from the view so MS-02 has something to test: the screen has to show a
    /// failure when a call that should have failed succeeded (sample plan ST-07).
    static func verdict(expected: Int, actualCode: Int?) -> ExpectedErrorVerdict {
        guard let actualCode else { return .succeededUnexpectedly }
        return actualCode == expected ? .matched(expected) : .differentCode(expected: expected,
                                                                            actual: actualCode)
    }
}

// MARK: - Fixtures

/// Fixed inputs, so a result depends on the button and not on what happens to be on the
/// pasteboard.
enum ClipboardSampleFixtures {

    static let plainTextType = "public.utf8-plain-text"
    static let urlType = "public.url"
    static let pngType = "public.png"
    static let rtfType = "public.rtf"

    static let plainText = "Copied from MacLibraryExample."
    static let urlString = "https://www.apple.com"

    /// Carries a URL and an email address, so detection has something to find.
    static let detectionText = "See https://www.apple.com or write to support@example.com."

    static func text(_ value: String = plainText) -> ClipboardContent {
        ClipboardContent(items: [ClipboardItemData(representations: [plainTextType: data(value)])])
    }

    static func url(_ value: String = urlString) -> ClipboardContent {
        ClipboardContent(items: [ClipboardItemData(representations: [urlType: data(value)])])
    }

    static func png() -> ClipboardContent {
        ClipboardContent(items: [ClipboardItemData(representations: [pngType: pngData()])])
    }

    static func multipleItems() -> ClipboardContent {
        ClipboardContent(items: [
            ClipboardItemData(representations: [plainTextType: data("first")]),
            ClipboardItemData(representations: [plainTextType: data("second")]),
        ])
    }

    /// One item carrying the same content twice, as plain text and as RTF.
    static func multipleRepresentations() -> ClipboardContent {
        let rtf = "{\\rtf1\\ansi \(plainText)}"
        return ClipboardContent(items: [ClipboardItemData(representations: [
            plainTextType: data(plainText),
            rtfType: data(rtf),
        ])])
    }

    /// An item the paste button accepts next to one it does not, for MT-06.
    static func partialPasteContent() -> ClipboardContent {
        ClipboardContent(items: [
            ClipboardItemData(representations: [plainTextType: data(plainText)]),
            ClipboardItemData(representations: ["com.example.unaccepted": data("opaque")]),
        ])
    }

    /// An item with no representations at all, which the validator rejects with 1502.
    static func emptyRepresentations() -> ClipboardContent {
        ClipboardContent(items: [ClipboardItemData(representations: [:])])
    }

    static func empty() -> ClipboardContent {
        ClipboardContent(items: [])
    }

    /// The patterns the Detect section asks for. Fixed, so the answer is comparable run to run.
    static let detectionPatterns: Set<ClipboardDetectionPattern> = [.probableWebURL, .links,
                                                                    .emailAddresses]

    static func data(_ value: String) -> Data { Data(value.utf8) }

    /// A small solid image, generated rather than shipped as a resource.
    static func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemBlue.drawSwatch(in: NSRect(x: 0, y: 0, width: 8, height: 8))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return Data()
        }
        return png
    }
}

// MARK: - Paste button hosting

/// Puts the `NSView` that OP-19 returns into SwiftUI.
///
/// The view is built before this value exists. `makeNSView` cannot throw, and
/// `makePasteButton` both throws and registers a loader with the coordinator, so calling it
/// from `makeNSView` would either lose the error or register a loader on every re-evaluation
/// (sample plan section 5.4).
struct PasteButtonHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
