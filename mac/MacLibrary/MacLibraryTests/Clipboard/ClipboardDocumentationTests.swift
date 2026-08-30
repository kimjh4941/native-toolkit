//
//  ClipboardDocumentationTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

/// Checks that the public surface is documented, and that the specific caveats the design
/// requires are actually stated.
///
/// The caveats are the point. Each one is a place where the platform behaves differently from
/// what the API name suggests, and every one of them was found by measurement rather than
/// assumed. A caller who does not read them will write code that looks correct.
@Suite("Clipboard documentation")
struct ClipboardDocumentationTests {

    private static let sourceRoot: URL = {
        var url = URL(filePath: #filePath)
        while url.pathComponents.count > 1, url.lastPathComponent != "MacLibrary" {
            url.deleteLastPathComponent()
        }
        return url.appending(path: "MacLibrary/Clipboard")
    }()

    private static let sources: [(name: String, lines: [String])] = {
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot, includingPropertiesForKeys: nil) else { return [] }
        var result: [(String, [String])] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            result.append((url.lastPathComponent, text.components(separatedBy: "\n")))
        }
        return result
    }()

    /// The manager's doc comments as one normalised string.
    ///
    /// Markers and line breaks are removed so a phrase can be matched regardless of where it
    /// happens to wrap. Otherwise these tests would fail on reformatting rather than on a
    /// missing caveat.
    private var managerDoc: String {
        let lines = Self.sources.first { $0.name == "MacClipboardManager.swift" }?.lines ?? []
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("///") }
            .map { $0.dropFirst(3).trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
            // Emphasis markers are presentation, not content.
            .replacingOccurrences(of: "**", with: "")
    }

    @Test("the source tree was found")
    func sourcesAreReadable() {
        #expect(Self.sources.count > 20)
    }

    @Test("every public symbol carries a doc comment")
    func everyPublicSymbolIsDocumented() {
        var undocumented: [String] = []
        let declaration = /^\s*(public|open)\s+(?!override)(final\s+)?(func|var|let|class|struct|enum|protocol|typealias|init|case|static)/
        for (name, lines) in Self.sources {
            for (index, line) in lines.enumerated() where line.firstMatch(of: declaration) != nil {
                var previous = index - 1
                while previous >= 0 && lines[previous].trimmingCharacters(in: .whitespaces).hasPrefix("@") {
                    previous -= 1
                }
                let doc = previous >= 0
                    && lines[previous].trimmingCharacters(in: .whitespaces).hasPrefix("///")
                if !doc {
                    undocumented.append("\(name):\(index + 1)")
                }
            }
        }
        #expect(undocumented.isEmpty, "undocumented: \(undocumented.prefix(10))")
    }

    @Test("doc comments are in English")
    func documentationIsEnglish() {
        // mac.md requires English for every comment. A stray Japanese line would ship in the
        // generated DocC.
        var offenders: [String] = []
        for (name, lines) in Self.sources {
            for (index, line) in lines.enumerated()
            where line.trimmingCharacters(in: .whitespaces).hasPrefix("///") {
                if line.unicodeScalars.contains(where: { $0.value > 0x2100 }) {
                    offenders.append("\(name):\(index + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "non-English doc comments: \(offenders.prefix(5))")
    }

    @Test("RK-01, RK-02 and RK-22: no operation is documented as silent")
    func doesNotPromiseSilence() {
        #expect(managerDoc.contains("does not guarantee"))
        #expect(managerDoc.contains("not evidence it will not appear"))
        // The optimisation must not be sold as a privacy contract.
        #expect(managerDoc.contains("not a privacy contract"))
    }

    @Test("RK-24: the read and write asymmetry is stated")
    func documentsReadSuperset() {
        #expect(managerDoc.contains("A read can report more than was written"))
        #expect(managerDoc.contains("public.rtf"))
    }

    @Test("RK-23: append's contract difference from iOS is stated")
    func documentsAppendOwnership() {
        #expect(managerDoc.contains("Appending needs ownership"))
        #expect(managerDoc.contains("does not silently do nothing"))
    }

    @Test("RK-06: pasteboard lifetime beyond the process is stated")
    func documentsPasteboardLifetime() {
        #expect(managerDoc.contains("outlive this process"))
        #expect(managerDoc.contains("never place confidential data"))
    }

    @Test("V-8: localOnly is documented as unverified")
    func documentsLocalOnlyUnverified() {
        #expect(managerDoc.contains("`localOnly` is unverified"))
    }

    @Test("H-3: the receive terminal event is documented as an estimate")
    func documentsReceiveHeuristic() {
        #expect(managerDoc.contains("end is an estimate"))
        #expect(managerDoc.contains("does not report how many files"))
    }

    @Test("RK-16: the paste button's lack of validation is stated")
    func documentsPasteButtonValidation() {
        #expect(managerDoc.contains("does not validate itself"))
    }

    @Test("RK-25: metadata detection failing on plain text is stated")
    func documentsMetadataFailure() {
        #expect(managerDoc.contains("Metadata detection can fail"))
        #expect(managerDoc.contains("not distinguishable"))
    }

    @Test("every error case has a message and a code in its own band")
    func errorContractIsComplete() {
        // 1501-1599 for the clipboard; 1301/1302 belong to the bridge.
        for error in ClipboardErrorSamples.all {
            #expect((1501...1599).contains(error.errorCode), "\(error)")
            #expect(!error.errorMessage.isEmpty, "\(error)")
            #expect(error.errorMessage.hasSuffix("."), "\(error) should read as a sentence")
        }
    }
}

/// One value per ``ClipboardError`` case, so the contract can be checked exhaustively.
enum ClipboardErrorSamples {
    static let all: [ClipboardError] = [
        .emptyContent, .emptyRepresentations(itemIndex: 0), .emptyDetectionPatterns,
        .invalidTypeIdentifier("x"), .invalidPasteboardName("x"),
        .contentTooLarge(bytes: 1, limit: 0), .pasteboardUnavailable(name: "x"),
        .cannotReleaseStandardPasteboard(name: "x"), .writeRejected, .appendRejected,
        .ownershipLost(expected: 1, actual: 2), .emptyTypeFilter,
        .detectionUnavailable(minimumOS: "15.4"), .detectionDenied, .detectionFailed("x"),
        .filePromiseTypeInvalid("x"), .invalidFileName("x"), .filePromiseWriteFailed("x"),
        .filePromiseReceiveFailed("x"), .destinationNotWritable("x"), .pasteLoadFailed("x"),
        .pasteLoadTimedOut(seconds: 1), .invalidConfiguration("x"), .cancelled, .unknown("x"),
    ]
}
