//
//  ClipboardSampleTests.swift
//  MacLibraryExampleTests
//

import Testing
import Foundation
@testable import MacLibraryExample

/// Checks the parts of the clipboard sample that can be verified without running the UI.
///
/// ST-05 and ST-06 are the mechanical form of T-18's completion condition. Both read their
/// subject out of the sources rather than comparing two hand written lists, which is how an
/// earlier revision of this suite passed while proving nothing (sample plan section 7.1).
@Suite("Clipboard sample")
struct ClipboardSampleTests {

    // MARK: - Fixtures

    @Test("ST-01: each fixture carries the type and the bytes it claims")
    func fixturesAreWellFormed() {
        let text = ClipboardSampleFixtures.text()
        #expect(text.items.count == 1)
        #expect(text.items[0].representations[ClipboardSampleFixtures.plainTextType] != nil)
        #expect(text.items[0].totalBytes == ClipboardSampleFixtures.plainText.utf8.count)

        #expect(ClipboardSampleFixtures.url().items[0]
            .representations[ClipboardSampleFixtures.urlType] != nil)
        #expect(ClipboardSampleFixtures.png().items[0]
            .representations[ClipboardSampleFixtures.pngType]?.isEmpty == false)

        #expect(ClipboardSampleFixtures.multipleItems().items.count == 2)
        #expect(ClipboardSampleFixtures.multipleRepresentations().items[0].representations.count == 2)

        // The two error fixtures have to be genuinely empty or the codes never appear.
        #expect(ClipboardSampleFixtures.empty().items.isEmpty)
        #expect(ClipboardSampleFixtures.emptyRepresentations().items[0].representations.isEmpty)
    }

    @Test("ST-01: the partial paste fixture mixes an accepted type with an unaccepted one")
    func partialPasteFixtureIsMixed() {
        let content = ClipboardSampleFixtures.partialPasteContent()
        #expect(content.items.count == 2)
        let types = content.items.flatMap { $0.representations.keys }
        #expect(types.contains(ClipboardSampleFixtures.plainTextType))
        #expect(types.contains { $0 != ClipboardSampleFixtures.plainTextType })
    }

    @Test("ST-02: the detection fixture contains a URL and an email address")
    func detectionFixtureHasSubjects() {
        let text = ClipboardSampleFixtures.detectionText
        #expect(text.contains("https://"))
        #expect(text.contains("@"))
        #expect(!ClipboardSampleFixtures.detectionPatterns.isEmpty)
    }

    // MARK: - Result formatting

    @Test("ST-03: each outcome becomes the text its kind calls for")
    func outcomesFormat() {
        let ok = SampleOutcome.success(label: "read", detail: "items=2")
        #expect(ok.isSuccess)
        #expect(ok.displayText.contains("read"))
        #expect(ok.displayText.contains("items=2"))

        let failure = SampleOutcome.clipboardFailure(label: "clear", code: 1512,
                                                     message: "The type filter must not be empty.")
        #expect(!failure.isSuccess)
        #expect(failure.displayText.contains("1512"))
        #expect(failure.displayText.contains("must not be empty"))

        let other = SampleOutcome.otherFailure(label: "x", description: "boom")
        #expect(other.displayText.contains("boom"))
    }

    @Test("ST-04: a caller supplied pasteboard name never reaches the screen or the log",
          arguments: [1505, 1507])
    func callerSuppliedNamesAreWithheld(code: Int) {
        // The library's message embeds the name the caller passed.
        let outcome = SampleOutcome.clipboardFailure(
            label: "createPasteboard", code: code,
            message: "Invalid pasteboard name: com.myapp.secret-session.")

        #expect(!outcome.displayText.contains("com.myapp.secret-session"))
        #expect(outcome.displayText.contains("\(code)"))
        #expect(!outcome.logText.contains("com.myapp.secret-session"))
    }

    @Test("ST-04: a standard pasteboard name may be shown")
    func standardNamesAreShown() {
        // 1508 can only ever name a standard pasteboard, which is public vocabulary.
        let outcome = SampleOutcome.clipboardFailure(
            label: "removePasteboard", code: 1508,
            message: "Standard pasteboard cannot be released: general.")
        #expect(outcome.displayText.contains("general"))
    }

    @Test("ST-04: no log line carries a message or a payload")
    func logsCarryNeitherMessageNorPayload() {
        let outcomes: [SampleOutcome] = [
            .success(label: "copy", detail: "the quick brown fox"),
            .clipboardFailure(label: "copy", code: 1501, message: "No clipboard content."),
            .otherFailure(label: "copy", description: "unexpected value 42"),
        ]
        for outcome in outcomes {
            #expect(!outcome.logText.contains("quick brown fox"))
            #expect(!outcome.logText.contains("No clipboard content"))
            #expect(!outcome.logText.contains("unexpected value"))
        }
    }

    // MARK: - Expected error judgement

    @Test("ST-07: the three outcomes of an expected failure are told apart")
    func expectedErrorVerdicts() {
        #expect(ExpectedErrorJudge.verdict(expected: 1508, actualCode: 1508) == .matched(1508))
        #expect(ExpectedErrorJudge.verdict(expected: 1508, actualCode: nil)
                == .succeededUnexpectedly)
        #expect(ExpectedErrorJudge.verdict(expected: 1508, actualCode: 1512)
                == .differentCode(expected: 1508, actual: 1512))

        // MS-02 turns on this one: a call that should have failed and did not is a failure.
        #expect(!ExpectedErrorJudge.verdict(expected: 1508, actualCode: nil).isSuccess)
        #expect(ExpectedErrorJudge.verdict(expected: 1508, actualCode: 1508).isSuccess)
    }

    // MARK: - T-18 completion condition

    @Test("ST-05: the sample calls every public operation of MacClipboardManager")
    func sampleExercisesEveryPublicOperation() throws {
        let published = try Self.publicOperations()
        let called = try Self.calledOperations()

        // Neither side is written by hand; an empty side would make this vacuous.
        #expect(published.count >= 16, "found \(published.count) public operations")
        #expect(!called.isEmpty, "found no calls in the sample")

        let missing = published.subtracting(called).sorted()
        #expect(missing.isEmpty, "never called from the sample: \(missing)")
    }

    @Test("ST-06: the sample does not import the Unity plugin")
    func sampleDoesNotDependOnTheUnityPlugin() throws {
        let files = try Self.sampleSources()
        #expect(files.count >= 4, "found \(files.count) sample sources")
        for (name, text) in files {
            #expect(!text.contains("import UnityMacPlugin"), "\(name) imports the Unity plugin")
        }
    }

    @Test("ST-08: every button reports under the label its own name predicts")
    func buttonNamesMatchTheirReportedLabels() throws {
        let source = try Self.sampleViewSource()
        let names = source.matches(of: /sampleButton\("(\w+)"\)/).map { String($0.output.1) }
        #expect(names.count >= 30, "found \(names.count) buttons")
        #expect(Set(names).count == names.count, "two buttons share a name")

        // The UI tests wait for the operation's own label to appear in the result, and they
        // derive that label from the button name. If the two ever part, the wait would be
        // looking for a word the screen never prints.
        let bodies = Array(source.components(separatedBy: "sampleButton(\"").dropFirst())
        #expect(bodies.count == names.count,
                "\(bodies.count) bodies for \(names.count) buttons")
        for (name, body) in zip(names, bodies) {
            let expected = name.prefix(1).lowercased() + name.dropFirst()
            // Some buttons name their operation through a helper's first argument rather
            // than a `label:`, so the check is that the name is there, not how it is passed.
            #expect(body.contains("\"\(expected)\""),
                    "\(name) does not report under \(expected)")
        }
    }

    @Test("ST-09: no button body reaches for the screen's state")
    func buttonsTakeTheirInputsFromTheClick() throws {
        let source = try Self.sampleViewSource()
        let names = source.matches(of: /sampleButton\("(\w+)"\)/).map { String($0.output.1) }
        let bodies = Self.buttonBodies(in: Self.codeOnly(source))
        #expect(bodies.count == names.count, "\(bodies.count) bodies for \(names.count) buttons")

        // `sampleButton` takes the state once, at the click, and hands the values to the body.
        // So the property is no longer "read it early enough" -- which a scan could only check
        // for the names it was told about, and which one computed property put out of reach
        // (レビュー v5 MU-1) -- but "do not read it at all".
        //
        // The subject is closed over indirection: anything that reads the state counts as the
        // state. Adding `var currentScope: PasteboardScope { activeScope }` puts
        // `currentScope` in the set, so reading it from a body is caught too.
        let state = source.matches(of: /@State private var (\w+)/).map { String($0.output.1) }
        #expect(state.count >= 5, "found \(state.count) pieces of screen state")
        let reachers = Self.namesReaching(state, in: source)

        for (name, body) in zip(names, bodies) {
            for reacher in reachers {
                for use in Self.reads(of: reacher, in: body) {
                    Issue.record("\(name) reads \(reacher) (\(use)) instead of taking it from the click")
                }
            }
        }
    }

    @Test("ST-10: no log line in the sample carries the caller supplied pasteboard name")
    func theSampleNeverLogsTheCallerSuppliedName() throws {
        let files = try Self.sampleSources()
        let name = try Self.callerSuppliedName()

        // MS-07 covers the screen and the log. The screen is checked by the UI test and by
        // ST-04; the sample's own log lines had nothing checking them, and the library's log
        // audit does not walk this target (レビュー v3 M-04).
        // Closed over indirection for the same reason as ST-09: a helper that returns the
        // name is the name. `func boardLabel() -> String { sampleName }` used to slip a log
        // line past this audit (レビュー v5 MU-3).
        let source = try Self.sampleViewSource()
        let carriers = Self.namesReaching(["sampleName"], in: source)

        var perFile: [String: Int] = [:]
        for (file, text) in files {
            for call in Self.logCalls(in: text) {
                perFile[file, default: 0] += 1
                #expect(!call.contains(name), "\(file) logs \(name): \(call)")
                for carrier in carriers where !Self.reads(of: carrier, in: call).isEmpty {
                    Issue.record("\(file) logs \(carrier), which carries the pasteboard name: \(call)")
                }
            }
        }

        // The floor counts only the clipboard sample. A floor over every sample source was
        // met many times over by the other screens, so deleting every log line in the
        // clipboard screen still passed (レビュー v4 M-02): the audit's subject and the
        // audit's evidence have to be the same files.
        let clipboardCalls = perFile
            .filter { $0.key.hasPrefix("ClipboardSample") }
            .values.reduce(0, +)
        #expect(clipboardCalls >= 5,
                "the clipboard sample contributed \(clipboardCalls) log calls; the audit read nothing")
        #expect(files.contains { $0.name == "ClipboardSampleView.swift" },
                "the clipboard screen was not among the files read")
    }

    // MARK: - ST-05 の走査そのもの

    @Test("ST-05: a nested block comment hides everything it contains")
    func nestedBlockCommentsAreRemoved() {
        let source = """
        /* outer /* inner */ MacClipboardManager.shared.copy() */
        """
        #expect(!ClipboardSampleTests.codeOnly(source).contains("copy"))
    }

    @Test("ST-05: a comment delimiter inside a literal does not start a comment")
    func commentDelimitersInsideLiteralsAreNotComments() {
        let source = """
        let note = "/* not a comment */"
        MacClipboardManager.shared.read()
        """
        #expect(ClipboardSampleTests.codeOnly(source).contains("read"))
    }

    @Test("ST-05: a call inside an interpolation is code")
    func interpolatedCallsSurvive() {
        let source = #"let text = "items=\(MacClipboardManager.shared.snapshot())""#
        #expect(ClipboardSampleTests.codeOnly(source).contains("snapshot"))
    }

    @Test("ST-05: the literal around an interpolation is not code")
    func literalTextIsRemoved() {
        let source = #"let text = "MacClipboardManager.shared.clear()""#
        #expect(!ClipboardSampleTests.codeOnly(source).contains("clear"))
    }

    @Test("ST-05: a line comment delimiter inside a literal does not end the line")
    func lineCommentDelimitersInsideLiteralsAreNotComments() {
        let source = """
        let site = "https://example.com" ; MacClipboardManager.shared.append()
        """
        #expect(ClipboardSampleTests.codeOnly(source).contains("append"))
    }

    @Test("ST-05: an escaped quote does not end the literal")
    func escapedQuotesDoNotEndLiterals() {
        let source = #"let quoted = "a \" MacClipboardManager.shared.copy() " ; let x = 1"#
        #expect(!ClipboardSampleTests.codeOnly(source).contains("copy"))
    }

    // MARK: - Source reading

    private static func macRoot() -> URL {
        var url = URL(filePath: #filePath)
        while url.pathComponents.count > 1, url.lastPathComponent != "mac" {
            url.deleteLastPathComponent()
        }
        return url
    }

    /// The names that can reach any of `seeds`, directly or through another declaration.
    ///
    /// A check written as a scan has to decide what to look for *and* where to look. Every
    /// round so far fixed the first and left the second, and each time one hop of indirection
    /// -- a computed property, a small helper -- carried the subject out of the scan
    /// (レビュー v5 §8). Closing the set over declarations is what makes the hop pointless:
    /// whatever reads the subject becomes the subject.
    static func namesReaching(_ seeds: [String], in source: String) -> Set<String> {
        var reached = Set(seeds)
        let declarations = Self.declarations(in: Self.codeOnly(source))
        var changed = true
        while changed {
            changed = false
            for (name, body) in declarations where !reached.contains(name) {
                if reached.contains(where: { !Self.reads(of: $0, in: body).isEmpty }) {
                    reached.insert(name)
                    changed = true
                }
            }
        }
        return reached
    }

    /// Declarations that hand a value back: computed properties and returning functions.
    ///
    /// Only these can carry a subject out of a scan. A function that returns nothing may
    /// touch the state all it likes -- that is what the operations do -- and treating those
    /// as carriers made every button that calls a runner look like a reader of the screen.
    static func declarations(in code: String) -> [(name: String, body: String)] {
        var found: [(String, String)] = []
        let characters = Array(code)
        for match in code.matches(of: /(?:var|func) (\w+)/) {
            let name = String(match.output.1)
            guard var index = code.distance(from: code.startIndex, to: match.range.upperBound)
                    as Int? else { continue }
            let signatureStart = index
            while index < characters.count, characters[index] != "{", characters[index] != "\n" {
                index += 1
            }
            guard index < characters.count, characters[index] == "{" else { continue }
            let signature = String(characters[signatureStart..<index])
            // A computed property has no parameter list. A function returns something only
            // if the arrow is after the parameters: `run(_ body: () async throws -> String)`
            // takes a returning closure and returns nothing itself.
            let returns: Bool
            if let lastParenthesis = signature.lastIndex(of: ")") {
                returns = signature[lastParenthesis...].contains("->")
            } else {
                returns = true
            }
            guard returns else { continue }
            var depth = 1
            var close = index + 1
            while close < characters.count, depth > 0 {
                if characters[close] == "{" { depth += 1 }
                if characters[close] == "}" { depth -= 1 }
                close += 1
            }
            found.append((name, String(characters[(index + 1)..<max(index + 1, close - 1)])))
        }
        return found
    }

    /// Where `name` is read in `text`: whole identifier, not a member and not an assignment.
    static func reads(of name: String, in text: String) -> [String] {
        var uses: [String] = []
        var searched = text.startIndex
        while let use = text.range(of: name, range: searched..<text.endIndex) {
            searched = use.upperBound
            let before = use.lowerBound == text.startIndex
                ? " " : text[text.index(before: use.lowerBound)]
            let after = String(text[use.upperBound...].prefix(3))
            let partOfALongerName = before.isLetter || before.isNumber || before == "_"
                || (after.first.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false)
            if before == "." || partOfALongerName { continue }
            if after.hasPrefix(" =") || after.hasPrefix(" +=") { continue }
            uses.append(String(text[use]))
        }
        return uses
    }

    /// Every `Log.` call, gathered across the lines it is written over.
    ///
    /// A per-line filter misses a call whose value sits on a continuation line, which is the
    /// shape the defect would take.
    static func logCalls(in text: String) -> [String] {
        var calls: [String] = []
        var current: String?
        var depth = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if current == nil, let start = line.range(of: "Log.") {
                current = String(line[start.lowerBound...])
                depth = 0
            } else if current != nil {
                current! += " " + line.trimmingCharacters(in: .whitespaces)
            }
            guard var call = current else { continue }
            depth = call.reduce(0) { $1 == "(" ? $0 + 1 : ($1 == ")" ? $0 - 1 : $0) }
            if depth <= 0 {
                if let end = call.range(of: ")", options: .backwards) {
                    call = String(call[..<end.upperBound])
                }
                calls.append(call)
                current = nil
            }
        }
        return calls
    }

    /// The pasteboard name the sample passes to `createPasteboard`.
    static func callerSuppliedName() throws -> String {
        let source = try sampleViewSource()
        guard let match = source.firstMatch(of: /let sampleName = "([^"]+)"/) else {
            Issue.record("the sample no longer declares sampleName")
            return ""
        }
        return String(match.output.1)
    }

    /// The body of every `sampleButton(...)` trailing closure.
    ///
    /// The declaration of `sampleButton` itself matches the same marker, so it is skipped by
    /// name. Without that, the list held one more entry than there are buttons and `zip` threw
    /// the extra away: the pairing was correct only because the declaration happens to sit
    /// after every call. A helper added above the sections would have shifted every pair by
    /// one, and a shifted pair mostly passes (レビュー v4 M-03).
    static func buttonBodies(in code: String) -> [String] {
        let characters = Array(code)
        let marker = Array("sampleButton(")
        var bodies: [String] = []
        var index = 0
        while index + marker.count <= characters.count {
            guard Array(characters[index..<(index + marker.count)]) == marker else {
                index += 1
                continue
            }
            // The declaration is the one with a parameter list; a call passes a literal,
            // which `codeOnly` has already blanked, so its parentheses hold nothing. Keying
            // on the parameter's spelling would break when it is renamed (レビュー v5 C-06).
            var scan = index + marker.count
            var isDeclaration = false
            while scan < characters.count, characters[scan] != ")" {
                if characters[scan] == ":" { isDeclaration = true }
                scan += 1
            }
            if isDeclaration { index += marker.count; continue }
            var open = index + marker.count
            while open < characters.count, characters[open] != "{" { open += 1 }
            guard open < characters.count else { break }
            var depth = 1
            var close = open + 1
            while close < characters.count, depth > 0 {
                if characters[close] == "{" { depth += 1 }
                if characters[close] == "}" { depth -= 1 }
                close += 1
            }
            bodies.append(String(characters[(open + 1)..<max(open + 1, close - 1)]))
            index = close
        }
        return bodies
    }

    static func sampleViewSource() throws -> String {
        let url = macRoot().appending(
            path: "MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Public operation names, read off the manager.
    private static func publicOperations() throws -> Set<String> {
        let url = macRoot().appending(
            path: "MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let excluded: Set<String> = ["init"]
        let names = text.matches(of: /public func (\w+)\(/).map { String($0.output.1) }
        return Set(names).subtracting(excluded)
    }

    /// Operation names the sample actually calls, with comments and string literals removed.
    ///
    /// Without that removal a commented out call, or the name inside a message, would satisfy
    /// the check without the sample doing anything.
    private static func calledOperations() throws -> Set<String> {
        var found: Set<String> = []
        for (_, text) in try sampleSources() {
            let code = codeOnly(text)
            for match in code.matches(of: /MacClipboardManager\.shared\.(\w+)\(/) {
                found.insert(String(match.output.1))
            }
        }
        return found
    }

    /// Every Swift file of the sample app target.
    private static func sampleSources() throws -> [(name: String, text: String)] {
        let root = macRoot().appending(path: "MacLibraryExample/MacLibraryExample")
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        var result: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            result.append((url.lastPathComponent, text))
        }
        return result
    }

    /// Source with comments removed and string literals reduced to their interpolations.
    ///
    /// A regular expression cannot do this. Swift block comments nest, so a non-greedy
    /// `/* ... */` ends at the first inner `*/` and leaves the rest of the comment as code;
    /// removing comments before strings turns a `/*` inside a literal into a comment and eats
    /// the real calls that follow it (R-SA12). This walks the text once, in the states the
    /// language actually has.
    static func codeOnly(_ text: String) -> String {
        enum Frame {
            /// Inside `\(...)`. The count is the parentheses opened since it started.
            case interpolation(parens: Int)
            /// Inside a literal. `hashes` is the `#` count of a raw string.
            case string(hashes: Int, multiline: Bool)
        }

        let characters = Array(text)
        var output = ""
        var stack: [Frame] = []
        var blockDepth = 0
        var index = 0

        func matches(_ token: String, at position: Int) -> Bool {
            let token = Array(token)
            guard position + token.count <= characters.count else { return false }
            return Array(characters[position..<(position + token.count)]) == token
        }

        func hashRun(from position: Int) -> Int {
            var count = 0
            while position + count < characters.count, characters[position + count] == "#" {
                count += 1
            }
            return count
        }

        while index < characters.count {
            if blockDepth > 0 {
                if matches("/*", at: index) { blockDepth += 1; index += 2; continue }
                if matches("*/", at: index) { blockDepth -= 1; index += 2; continue }
                index += 1
                continue
            }

            if case .string(let hashes, let multiline) = stack.last {
                let escape = "\\" + String(repeating: "#", count: hashes)
                if matches(escape + "(", at: index) {
                    stack.append(.interpolation(parens: 0))
                    output.append(" ")
                    index += escape.count + 1
                    continue
                }
                if matches(escape, at: index) {
                    index += escape.count + 1   // the escaped character cannot end the literal
                    continue
                }
                let terminator = (multiline ? "\"\"\"" : "\"") + String(repeating: "#", count: hashes)
                if matches(terminator, at: index) {
                    stack.removeLast()
                    output.append(" ")
                    index += terminator.count
                    continue
                }
                index += 1
                continue
            }

            // Code: at the top level, or inside an interpolation.
            if matches("//", at: index) {
                while index < characters.count, characters[index] != "\n" { index += 1 }
                continue
            }
            if matches("/*", at: index) { blockDepth = 1; index += 2; continue }

            let hashes = hashRun(from: index)
            if matches(String(repeating: "#", count: hashes) + "\"\"\"", at: index) {
                stack.append(.string(hashes: hashes, multiline: true))
                output.append(" ")
                index += hashes + 3
                continue
            }
            if matches(String(repeating: "#", count: hashes) + "\"", at: index) {
                stack.append(.string(hashes: hashes, multiline: false))
                output.append(" ")
                index += hashes + 1
                continue
            }

            let character = characters[index]
            if case .interpolation(let parens) = stack.last {
                if character == "(" {
                    stack[stack.count - 1] = .interpolation(parens: parens + 1)
                } else if character == ")" {
                    if parens == 0 {
                        stack.removeLast()      // back into the literal
                        output.append(" ")
                        index += 1
                        continue
                    }
                    stack[stack.count - 1] = .interpolation(parens: parens - 1)
                }
            }
            output.append(character)
            index += 1
        }
        return output
    }
}
