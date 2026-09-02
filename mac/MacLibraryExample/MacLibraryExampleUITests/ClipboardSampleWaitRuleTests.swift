//
//  ClipboardSampleWaitRuleTests.swift
//  MacLibraryExampleUITests
//

import XCTest

/// Checks the rule `tap` waits on, without launching anything.
///
/// The rule is what stops a click that produced nothing from being read as a result, and the
/// only shape of that failure -- the same button, twice, with word for word the same text --
/// cannot be produced by breaking the app (レビュー v3 M-02).
final class ClipboardSampleWaitRuleTests: XCTestCase {

    private typealias Rule = ClipboardSampleViewUITests

    func testTheSameTextFromAnEarlierClickIsNotAccepted() {
        // The button was clicked again and nothing happened: the words still match, and the
        // counter has not moved. This is the case the counter exists for.
        XCTAssertFalse(Rule.isResultOfThisClick(text: "✅ [clear] removed=3",
                                                sequence: 7, before: 7, expecting: "clear"))
    }

    func testAResultFromAnotherButtonIsNotAccepted() {
        XCTAssertFalse(Rule.isResultOfThisClick(text: "✅ [copyText] changeCount=1",
                                                sequence: 8, before: 7, expecting: "clear"))
    }

    func testTheResultOfThisClickIsAccepted() {
        XCTAssertTrue(Rule.isResultOfThisClick(text: "✅ [clear] removed=3",
                                               sequence: 8, before: 7, expecting: "clear"))
    }

    func testALongerButtonNameDoesNotStandInForTheShorterOne() throws {
        // The pairs come from the sample's own button names, not from a list written here: a
        // button added later whose name contains another's is covered without editing this
        // (レビュー v5 B-05).
        let labels = try ClipboardSampleViewUITests.buttonLabels()
        let pairs = labels.flatMap { short in
            labels.filter { $0 != short && $0.hasPrefix(short) }.map { (short, $0) }
        }
        XCTAssertFalse(pairs.isEmpty, "no button name contains another; the case is untested")

        for (short, long) in pairs {
            XCTAssertFalse(Rule.isResultOfThisClick(text: "✅ [\(long)] done",
                                                    sequence: 8, before: 7, expecting: short),
                           "\(long) stood in for \(short)")
        }
    }

    func testADetailWordDoesNotStandInForALabel() {
        // `clear` appears inside the detail of another operation's result.
        XCTAssertFalse(Rule.isResultOfThisClick(text: "✅ [resetReachedCodes] cleared",
                                                sequence: 8, before: 7, expecting: "clear"))
    }

    func testARepeatWithIdenticalTextIsAccepted() {
        // The same button, the same words, one more result: a real repeat must not be
        // rejected either, or the rule would trade a false pass for a false failure.
        XCTAssertTrue(Rule.isResultOfThisClick(text: "❌ [expectFailureThatSucceeds] it succeeded",
                                               sequence: 9, before: 8,
                                               expecting: "expectFailureThatSucceeds"))
    }
}
