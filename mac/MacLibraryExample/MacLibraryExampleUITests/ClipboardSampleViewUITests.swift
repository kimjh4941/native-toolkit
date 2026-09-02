//
//  ClipboardSampleViewUITests.swift
//  MacLibraryExampleUITests
//

import XCTest

/// Drives `ClipboardSampleView` through real clicks.
///
/// These cover the observations that do not need a second app or a second machine: MS-01
/// (every button reports something), MS-02 (an expectation that does not hold is shown as a
/// failure), MS-03 (the scope argument follows the picker), MS-05 (observation stops when the
/// screen is left) and MS-07 (a caller supplied pasteboard name never appears on screen).
///
/// MT-01 / MT-02 need a second app, MT-07 needs two OS versions and MT-08 needs a second
/// device, so those stay manual (sample plan section 8).
///
/// - Note: The screen scrolls, and a button that has scrolled out of the scroll view is still
///   reported as existing and sometimes as hittable, so a click on it lands on whatever sits
///   at those coordinates instead. `scrollIntoView` puts the button inside the viewport before
///   every click.
final class ClipboardSampleViewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Navigation

    @MainActor
    private func openClipboardExample() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        openMenuCard(app, titled: "Clipboard Example")
        XCTAssertTrue(app.staticTexts["clipboard.result"].waitForExistence(timeout: 10),
                      "the clipboard screen did not appear")
        return app
    }

    /// Clicks a menu card on the main screen.
    ///
    /// A `NavigationLink` with a custom label is not always published as a button, so the
    /// card is looked up by the text it contains and clicked through its ancestor.
    @MainActor
    private func openMenuCard(_ app: XCUIApplication, titled title: String) {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        if button.waitForExistence(timeout: 3) {
            button.click()
            return
        }
        let text = app.staticTexts[title]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "no menu card titled \(title)")
        text.click()
    }

    // MARK: - Reading the screen

    /// The counter and the text, taken together.
    ///
    /// The screen puts both in one value. Read from two elements they could come from either
    /// side of a new result, and the pair that slipped through was the one the counter exists
    /// to reject (レビュー v4 M-04). One read leaves no order to get wrong (R-SA24).
    private func shown(_ app: XCUIApplication) -> (sequence: Int, text: String) {
        let raw = app.staticTexts["clipboard.result"].value as? String ?? ""
        guard raw.hasPrefix("#"), let space = raw.firstIndex(of: " ") else { return (-1, raw) }
        return (Int(raw[raw.index(after: raw.startIndex)..<space]) ?? -1,
                String(raw[raw.index(after: space)...]))
    }

    private func result(_ app: XCUIApplication) -> String { shown(app).text }

    private func activeScope(_ app: XCUIApplication) -> String {
        app.staticTexts["clipboard.activeScope"].value as? String ?? ""
    }

    private func button(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons["clipboard.button.\(name)"]
    }

    // MARK: - Acting on the screen

    /// Clicks a button and waits for the result that click produced.
    ///
    /// Two things have to be true before the result belongs to this click: the counter must
    /// have moved, and the text must name the operation. Waiting on the text alone accepted
    /// the previous button's result (R-SA1) and, for a repeated button, its own previous one
    /// (R-SA11).
    @discardableResult
    private func tap(_ app: XCUIApplication, _ name: String,
                     timeout: TimeInterval = 10) -> String {
        let button = button(app, name)
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "\(name) was not found")
        scrollIntoView(app, button, named: name)
        let before = shown(app).sequence
        button.click()

        let expected = name.prefix(1).lowercased() + name.dropFirst()
        let deadline = Date().addingTimeInterval(timeout)
        var lastText = ""
        while Date() < deadline {
            let now = shown(app)
            lastText = now.text
            if Self.isResultOfThisClick(text: now.text, sequence: now.sequence,
                                        before: before, expecting: expected) {
                return now.text
            }
            usleep(100_000)
        }
        XCTFail("\(name) did not report. sequence stayed at \(before), text: \(lastText)")
        return lastText
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

    /// Selects a scope with the picker.
    @MainActor
    private func selectScope(_ app: XCUIApplication, _ name: String) {
        let option = app.radioGroups["clipboard.scopePicker"].radioButtons[name]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "no \(name) option in the scope picker")
        option.click()
    }

    /// Scrolls until the button is inside the scroll view, so that clicking it hits it.
    ///
    /// A button that has scrolled past the top of the viewport keeps a frame and can report
    /// itself hittable; the click then lands on the header that occupies those coordinates,
    /// the operation never runs, and the previous result stays on screen (R-SA6).
    private func scrollIntoView(_ app: XCUIApplication, _ element: XCUIElement, named name: String) {
        let scrollView = app.scrollViews.firstMatch
        guard scrollView.exists else { return }
        var direction: CGFloat = -1
        var distances: [CGFloat] = []
        for _ in 0..<16 {
            let viewport = scrollView.frame
            let frame = element.frame
            if viewport.minY <= frame.minY && frame.maxY <= viewport.maxY { return }
            let offset = frame.midY - viewport.midY
            distances.append(abs(offset))
            // The sign of a scroll delta is not the sign of the movement on every input
            // device, and a boundary can absorb a scroll entirely. Judging each attempt by
            // whether it got closer covers both, where reading the first move alone did not.
            if distances.count >= 2, distances.last! >= distances[distances.count - 2] {
                direction = -direction
            }
            scrollView.scroll(byDeltaX: 0, deltaY: direction * min(abs(offset), 200))
        }
        XCTFail("""
            \(name) could not be scrolled into view. \
            viewport: \(scrollView.frame), element: \(element.frame), \
            distances: \(distances)
            """)
    }

    // MARK: - MS-01

    @MainActor
    func testEveryButtonReportsAResult() throws {
        let app = openClipboardExample()

        // The list comes from the screen's own source, so a section added later is covered
        // without editing this test, and a button that stops reporting cannot hide by being
        // left out of a hand written list (R-SA13).
        let names = try buttonNames()
        XCTAssertGreaterThanOrEqual(names.count, 30, "found \(names.count) buttons in the source")

        for name in names {
            let text = tap(app, name)
            XCTAssertFalse(text.hasPrefix("Result will be displayed"), "\(name) produced no result")
        }
    }

    // MARK: - MS-02

    @MainActor
    func testAnExpectationThatDoesNotHoldIsShownAsAFailure() throws {
        let app = openClipboardExample()

        // RemoveGeneral must fail with 1508. The screen shows a met expectation as a success.
        let met = tap(app, "RemoveGeneral")
        XCTAssertTrue(met.contains("1508"), "RemoveGeneral did not report 1508: \(met)")
        XCTAssertTrue(met.contains("✅"), "a met expectation should read as success")

        // ExpectFailureThatSucceeds copies successfully while declaring that it must fail.
        // Succeeding is the failure, and the screen has to say so.
        let unmet = tap(app, "ExpectFailureThatSucceeds")
        XCTAssertTrue(unmet.contains("❌"),
                      "an expectation that did not hold should read as a failure: \(unmet)")

        // The same button again. Its result is word for word the previous one, so this is the
        // case the counter exists for: waiting on the text alone would accept the old result,
        // and waiting on the text having changed would never finish.
        let before = shown(app).sequence
        let repeated = tap(app, "ExpectFailureThatSucceeds")
        XCTAssertEqual(repeated, unmet, "the repeat produced different text")
        XCTAssertGreaterThan(shown(app).sequence, before,
                             "the repeated click produced no new result")
    }

    // MARK: - MS-03

    @MainActor
    func testTheScopeArgumentFollowsThePicker() throws {
        let app = openClipboardExample()

        // A scope nothing has created cannot be selected, and saying so is the picker's whole
        // behaviour: it selects, it does not create (R-SA9).
        selectScope(app, "unique")
        XCTAssertTrue(result(app).contains("no unique pasteboard exists yet"),
                      "selecting an uncreated scope was not refused: \(result(app))")
        XCTAssertTrue(activeScope(app).contains("general"),
                      "the refused selection moved the scope: \(activeScope(app))")

        tap(app, "CreateNamedPasteboard")
        XCTAssertTrue(activeScope(app).contains("named"), "creating did not move the scope")

        // Put something in the named pasteboard, then clear the general one through the
        // picker. If the scope argument did not follow the picker, this would clear what was
        // just copied.
        tap(app, "CopyText")
        selectScope(app, "general")
        XCTAssertTrue(activeScope(app).contains("general"), "the picker did not move the scope")
        tap(app, "Clear")

        selectScope(app, "named")
        XCTAssertTrue(activeScope(app).contains("named"), "the picker did not return to named")
        let read = tap(app, "Read")
        XCTAssertTrue(read.contains("items=1"),
                      "clearing general emptied the named pasteboard: \(read)")

        tap(app, "RemoveCurrentPasteboard")
        XCTAssertTrue(activeScope(app).contains("general"),
                      "removing did not return the scope to general")
    }

    // MARK: - Error Cases list

    @MainActor
    func testAnOrdinaryFailureIsRecordedInTheReachedList() throws {
        let app = openClipboardExample()
        XCTAssertTrue(app.staticTexts["clipboard.reachedCodes"].waitForExistence(timeout: 5))

        // Removing the general pasteboard fails with 1508 through the ordinary runner, not
        // through an expected-failure button. Section 10 says it lists the codes the run has
        // reached, so a code met this way belongs there too (R-SA10).
        let text = tap(app, "RemoveCurrentPasteboard")
        XCTAssertTrue(text.contains("1508"), "expected 1508 from the general scope: \(text)")

        let reached = app.staticTexts["clipboard.reachedCodes"].value as? String ?? ""
        XCTAssertTrue(reached.contains("1508"),
                      "an ordinary failure was not recorded as reached: \(reached)")
    }

    // MARK: - Scope lifecycle

    @MainActor
    func testCreatingANamedPasteboardAgainKeepsItsContents() throws {
        let app = openClipboardExample()

        // `createPasteboard` creates *or fetches*. A named pasteboard is addressed by a name
        // the sample chooses, so asking again must hand back the same one, contents and all.
        // Releasing it first threw the contents away without saying so, and nothing here
        // would have noticed (レビュー v5 MU-6).
        tap(app, "CreateNamedPasteboard")
        tap(app, "CopyText")
        tap(app, "CreateNamedPasteboard")
        let read = tap(app, "Read")
        XCTAssertTrue(read.contains("items=1"),
                      "creating the named pasteboard again emptied it: \(read)")

        tap(app, "RemoveCurrentPasteboard")
    }

    @MainActor
    func testCreatingAUniquePasteboardAgainReleasesThePreviousOne() throws {
        let app = openClipboardExample()

        // A unique one gets a new system name every time, so the previous handle would be
        // lost. The screen says it released it; that sentence is the contract.
        tap(app, "CreateUniquePasteboard")
        let again = tap(app, "CreateUniquePasteboard")
        XCTAssertTrue(again.contains("released the previous unique pasteboard"),
                      "the previous unique pasteboard was left with no handle: \(again)")

        tap(app, "RemoveCurrentPasteboard")
    }

    // MARK: - MS-05

    @MainActor
    func testObservationStopsWhenTheScreenIsLeft() throws {
        let app = openClipboardExample()

        tap(app, "StartObserving")
        // Read the status, not the result text: an observation event overwrites the result.
        XCTAssertEqual(app.staticTexts["clipboard.observeStatus"].value as? String, "Observing")

        // Leave and come back. The manager is shared, so the state would survive without the
        // teardown on disappear. The macOS NavigationStack back control carries the chevron as
        // its identifier and "Back" as its label; it is not named after the screen it returns to.
        app.buttons["chevron.backward"].firstMatch.click()
        openMenuCard(app, titled: "Clipboard Example")

        XCTAssertTrue(app.staticTexts["clipboard.observeStatus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["clipboard.observeStatus"].value as? String,
                       "Not observing", "observation survived leaving the screen")
    }

    // MARK: - MS-07

    @MainActor
    func testACallerSuppliedPasteboardNameIsNotShown() throws {
        let app = openClipboardExample()

        // The name has to actually reach the library for its absence to mean anything. The
        // empty name of CreateEmptyNamedPasteboard cannot be shown whatever the code does, so
        // checking that one proves nothing (R-SA14). CreateNamedPasteboard passes the real one.
        let name = try callerSuppliedName()
        XCTAssertFalse(name.isEmpty)

        let created = tap(app, "CreateNamedPasteboard")
        XCTAssertFalse(created.contains(name),
                       "the pasteboard name '\(name)' reached the screen: \(created)")

        // The failing path carries the name in the library's own message, which is where it
        // would leak from.
        selectScope(app, "general")
        let refused = tap(app, "CreateEmptyNamedPasteboard")
        XCTAssertTrue(refused.contains("1505"), "expected 1505: \(refused)")
        XCTAssertFalse(refused.contains(name), "the name reached the screen: \(refused)")

        // A standard name *may* be shown; the rule permits it, it does not require it. This
        // path prints the verdict rather than the library's message, so no name appears here
        // either. ST-04 checks the permitted half where the message is actually rendered.
        let standard = tap(app, "RemoveGeneral")
        XCTAssertTrue(standard.contains("1508"), "expected 1508: \(standard)")
    }

    // MARK: - Source reading

    private func sampleViewSource() throws -> String { try Self.sampleViewSource() }

    static func sampleViewSource() throws -> String {
        var url = URL(filePath: #filePath)
        while url.pathComponents.count > 1, url.lastPathComponent != "mac" {
            url.deleteLastPathComponent()
        }
        return try String(
            contentsOf: url.appending(
                path: "MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift"),
            encoding: .utf8)
    }

    /// The pasteboard name the sample passes to `createPasteboard`.
    private func callerSuppliedName() throws -> String {
        let match = try XCTUnwrap(sampleViewSource().firstMatch(of: /let sampleName = "([^"]+)"/),
                                  "the sample no longer declares sampleName")
        return String(match.output.1)
    }

    /// Every button the sample declares, in the order the screen shows them.
    private func buttonNames() throws -> [String] {
        try Self.buttonNames()
    }

    static func buttonNames() throws -> [String] {
        try sampleViewSource().matches(of: /sampleButton\("(\w+)"\)/).map { String($0.output.1) }
    }

    /// The label each button reports under: its name with a lower case first letter.
    static func buttonLabels() throws -> [String] {
        try buttonNames().map { $0.prefix(1).lowercased() + $0.dropFirst() }
    }
}
