//
//  ClipboardLogAuditTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

/// Audits the clipboard sources for log lines that interpolate a value verbatim.
///
/// `BT-25` does this for the Objective-C bridge. MacLibrary had no equivalent, and five call
/// sites printed `named("secret")` into the log because they interpolated the request itself
/// rather than passing it through ``ClipboardLog`` (R-S2-H1). `Log` publishes at
/// `privacy: .public`, so anything interpolated reaches whatever collects the logs.
@Suite("Clipboard log redaction")
struct ClipboardLogAuditTests {

    /// Values that are safe to log as they are.
    ///
    /// Counts, flags, durations and opaque handle identities carry nothing about the payload.
    /// Uniform type identifiers are public vocabulary, and ``ClipboardLog/types(_:)`` logs them
    /// verbatim by design.
    /// Names that describe shape rather than content.
    ///
    /// Matched by equality, not by suffix. An earlier revision was called `harmlessSuffixes`
    /// while being used with `contains`, so 13 of its 23 entries never matched anything and
    /// renaming the check to what it claimed would have widened it silently (R-S3-L5).
    ///
    /// This list is a judgement, not a derivation, and it is deliberately short. A number, a
    /// flag or an opaque identity says nothing about what was on the pasteboard. Uniform type
    /// identifiers are on it because the design declares them public vocabulary and
    /// ``ClipboardLog/types(_:)`` logs them verbatim by that same rule (mac.md section 4.2).
    /// Every entry is one that currently matches; a dead entry hides how wide the rule is.
    private static let harmlessNames: Set<String> = [
        "count", "changeCount", "maxTotalBytes", "warnBytesPerRepresentation",
        "maxBytesPerRepresentation", "localOnly", "interval", "intervalSeconds", "generation",
        "current", "index", "id", "identifier", "other", "utType", "value",
        "bytes", "timeout", "errorCode",
    ]

    private static let allowed: Set<String> = ["TAG"]

    private static let sources: [(name: String, lines: [String])] = {
        var url = URL(filePath: #filePath)
        while url.pathComponents.count > 1, url.lastPathComponent != "mac" {
            url.deleteLastPathComponent()
        }
        // Both clipboard Swift trees. The plugin's façade logs the same values, and BT-25
        // covers only the Objective-C layer, so its Swift side sat outside every audit
        // (R-S3-M6).
        let roots = [url.appending(path: "MacLibrary/MacLibrary/Clipboard"),
                     url.appending(path: "UnityMacPlugin/UnityMacPlugin/Clipboard")]
        var result: [(String, [String])] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                result.append((url.lastPathComponent, text.components(separatedBy: "\n")))
            }
        }
        return result
    }()


    /// The expressions inside `\(...)`, matching parentheses so a nested call stays whole.
    ///
    /// A regex that stopped at the first `)` cut `ClipboardLog.types(x)` in half and reported
    /// the redacted call as a leak.
    private static func interpolatedExpressions(in line: String) -> [String] {
        var found: [String] = []
        var index = line.startIndex
        while let start = line.range(of: "\\(", range: index..<line.endIndex) {
            var depth = 1
            var cursor = start.upperBound
            while cursor < line.endIndex, depth > 0 {
                if line[cursor] == "(" { depth += 1 }
                if line[cursor] == ")" { depth -= 1; if depth == 0 { break } }
                cursor = line.index(after: cursor)
            }
            guard depth == 0, cursor < line.endIndex else {
                // Unbalanced, most likely a parenthesis inside a string literal. Skip this one
                // and keep scanning: `break` left the rest of the line unexamined (R-S3-L6).
                index = start.upperBound
                continue
            }
            found.append(String(line[start.upperBound..<cursor]))
            index = line.index(after: cursor)
        }
        return found
    }

    /// Every `\(...)` inside a `Log.` call, with the file and line it came from.
    ///
    /// The call is followed across its continuation lines. Selecting lines that contain
    /// "Log." looked equivalent, but a continuation line qualified only because it said
    /// `ClipboardLog.` — so removing the redaction removed the line from the audit as well,
    /// and the leak became invisible to the very check meant to catch it (R-S3-H2).
    private func interpolations() -> [(file: String, line: Int, expression: String)] {
        var found: [(String, Int, String)] = []
        for (name, lines) in Self.sources {
            var inCall = false
            var depth = 0
            for (offset, line) in lines.enumerated() {
                if !inCall, let range = line.range(of: "Log.") {
                    // A call starts here; count parentheses from its opening one.
                    guard let open = line.range(of: "(", range: range.upperBound..<line.endIndex)
                    else { continue }
                    inCall = true
                    depth = 0
                    depth += Self.parenBalance(in: String(line[open.lowerBound...]))
                } else if inCall {
                    depth += Self.parenBalance(in: line)
                } else {
                    continue
                }
                for expression in Self.interpolatedExpressions(in: line) {
                    found.append((name, offset + 1, expression))
                }
                if depth <= 0 { inCall = false }
            }
        }
        return found
    }

    /// Open parentheses minus closed ones, ignoring those inside string literals.
    private static func parenBalance(in line: String) -> Int {
        var depth = 0
        var inString = false
        var previous: Character = " "
        for character in line {
            if character == "\"" && previous != "\\" { inString.toggle() }
            if !inString {
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
            }
            previous = character
        }
        return depth
    }

    @Test("every logged expression is a count, a flag, or goes through ClipboardLog")
    func noValueReachesTheLogVerbatim() {
        let offenders = interpolations().filter { entry in
            let expression = entry.expression.trimmingCharacters(in: .whitespaces)
            if expression.contains("ClipboardLog.") { return false }
            if Self.allowed.contains(expression) { return false }
            if expression.hasSuffix(" != nil") || expression.hasSuffix(".isEmpty")
                || expression.hasSuffix(".rawValue") {
                return false
            }
            // `x?.count ?? 0`, `utType ?? "nil"` and the like describe shape once the
            // defaulting is stripped.
            let core = expression
                .components(separatedBy: "??").first?
                .trimmingCharacters(in: .whitespaces) ?? expression
            if core.hasSuffix(".count") { return false }
            let tail = core.split(separator: ".").last.map(String.init) ?? core
            return !Self.harmlessNames.contains(tail)
        }
        #expect(offenders.isEmpty,
                "these reach the log verbatim: \(offenders.map { "\($0.file):\($0.line) \($0.expression)" })")
    }

    @Test("the audit actually inspects the sources")
    func auditHasSubjects() {
        // A pass that examined nothing would be worthless. This suite exists because the
        // bridge's own audit passed for three rounds while looking at almost nothing.
        // Measured 41 files and 142 expressions. The floor is ~80% of that, so losing a
        // source root or a whole file is noticed; 20 / 40 would not have been (R-S3-L7).
        #expect(Self.sources.count >= 33, "found \(Self.sources.count) source files")
        #expect(interpolations().count >= 110,
                "found \(interpolations().count) logged expressions")
    }

    @Test("a creation request never logs its name")
    func requestIsHashed() {
        #expect(ClipboardLog.request(.named("nt-sample")) != "request(named:nt-sample)")
        #expect(!ClipboardLog.request(.named("nt-sample")).contains("nt-sample"))
        #expect(ClipboardLog.request(.unique) == "request(unique)")
        // The same name hashes the same way through either helper, so logs still correlate.
        let viaRequest = ClipboardLog.request(.named("nt-sample"))
        let viaScope = ClipboardLog.scope(.named("nt-sample"))
        let hash = viaRequest.replacingOccurrences(of: "request(named:", with: "")
            .replacingOccurrences(of: ")", with: "")
        #expect(viaScope.contains(hash))
    }
}
