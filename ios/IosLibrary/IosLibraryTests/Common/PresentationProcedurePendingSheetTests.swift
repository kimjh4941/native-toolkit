//
//  PresentationProcedurePendingSheetTests.swift
//  IosLibraryTests
//

import Foundation
import Testing
@testable import IosLibrary

/// SH-13 (the design memo `2026-11-21-ios-c-abi-share-same-turn-design.md`, 4.2 to 4.4, 6.1): a
/// share sheet whose `present` has not completed holds the other requests on its window, because
/// UIKit shows nothing of it yet and declines (and keeps) a second sheet presented then.
@MainActor
struct PresentationProcedurePendingSheetTests {

    private let environment = FakePresentationEnvironment()
    private let top = FakeViewController("top")
    private let limit = PresentationProcedure.pendingSheetLimit
    /// Holds the sheets a test makes in place: the procedure and the fake UIKit hold a presented
    /// view controller only weakly, as UIKit does not hold a sheet it is still preparing.
    private let kept = KeptViewControllers()

    private func keep(_ name: String) -> FakeViewController {
        kept.keep(FakeViewController(name))
    }

    init() {
        environment.foreground = top
        environment.firstActive = top
    }

    /// Presents `presented` as a share sheet (the release watch only).
    private func share(_ presented: FakeViewController, _ box: RequestBox,
                       _ presenter: PresenterSelection = .foreground,
                       policy: PresentationProcedure.FirstActiveScenePolicy = .requireLegacyStability,
                       onPresented: @escaping @MainActor () -> Void = {}) {
        PresentationProcedure.present(presented, presenter: presenter, box: box, firstActiveScenePolicy: policy,
                                      environment: environment, declineCheck: .releaseWatchOnly, onPresented: onPresented)
    }

    /// Presents `presented` as an alert (the check right after `present`).
    private func alert(_ presented: FakeViewController, _ box: RequestBox, _ presenter: PresenterSelection = .foreground) {
        PresentationProcedure.present(presented, presenter: presenter, box: box, firstActiveScenePolicy: .presentAnyway,
                                      environment: environment)
    }

    private var presentationNames: [String] {
        environment.presentations.map { "\($0.presented)@\($0.on)" }
    }

    // MARK: - Waiting for the first sheet

    @Test func aSecondSheetWaitsForTheFirstAndIsPresentedAfterItsCompletion() {
        let first = FakeViewController("first"), second = FakeViewController("second")
        let firstBox = RequestBox(), secondBox = RequestBox()
        share(first, firstBox)
        share(second, secondBox)
        #expect(presentationNames == ["first@top"], "the second waits")
        #expect(environment.transitionWaits.isEmpty, "it waits for the sheet, not for a transition")

        environment.finishPresentation(of: "first")
        #expect(presentationNames == ["first@top"], "the check is on the next turn")
        environment.runTurns()
        #expect(presentationNames == ["first@top", "second@top"])
        #expect(!firstBox.isClosed)
        #expect(!secondBox.isClosed)

        environment.finishPresentation(of: "second")
        #expect(environment.records.counts.records == 0)
        #expect(environment.records.counts.waiters == 0)
    }

    /// As with UIKit, the first sheet is the foreground once presented: the second share waits for
    /// it, then fails instead of being presented on it (D-2).
    @Test func aSecondShareWaitsThenFailsOnTheFirstSheet() {
        let first = keep("first")
        first.isShareSheet = true
        let firstBox = RequestBox(), secondBox = RequestBox()
        share(first, firstBox)
        share(keep("second"), secondBox)
        environment.finishPresentation(of: "first")
        environment.foreground = first
        environment.runTurns()
        #expect(presentationNames == ["first@top"])
        #expect(secondBox.outcome?.testName == "presentationFailed")
        #expect(!firstBox.isClosed)
        #expect(environment.records.counts.waiters == 0)
    }

    /// A dialog made in the same turn as a share waits for the sheet and is stacked on it.
    @Test func aDialogWaitsForThePendingSheetAndIsPresentedOnIt() {
        let sheet = keep("sheet")
        sheet.isShareSheet = true
        let alertBox = RequestBox()
        share(sheet, RequestBox())
        alert(keep("alert"), alertBox)
        #expect(presentationNames == ["sheet@top"], "the dialog waits")
        environment.finishPresentation(of: "sheet")
        environment.foreground = sheet
        environment.runTurns()
        #expect(presentationNames == ["sheet@top", "alert@sheet"])
        #expect(!alertBox.isClosed)
    }

    @Test func aShareIsNeverPresentedOnAShareSheet() {
        let sheet = keep("hostSheet")
        sheet.isShareSheet = true
        environment.foreground = sheet
        environment.firstActive = sheet
        let boxes = [RequestBox(), RequestBox(), RequestBox()]
        share(keep("a"), boxes[0])
        share(keep("b"), boxes[1], .firstActiveScene)
        share(keep("c"), boxes[2], PresenterSelection(kind: .provided { sheet }))
        #expect(boxes.map { $0.outcome?.testName } == ["presentationFailed", "presentationFailed", "presentationFailed"])
        #expect(environment.presentations.isEmpty)
        #expect(environment.pendingTurns == 0, "no waiting")
        alert(keep("alert"), RequestBox())
        #expect(presentationNames == ["alert@hostSheet"], "a dialog still is")
    }

    /// The first's completion and then its record's expiry: the second is checked once.
    @Test func theExpiryAfterTheCompletionDoesNothing() {
        let first = FakeViewController("first"), second = FakeViewController("second")
        let secondBox = RequestBox()
        share(first, RequestBox())
        share(second, secondBox)
        environment.finishPresentation(of: "first")
        environment.advanceClock(by: limit)
        environment.runTurns()
        #expect(presentationNames == ["first@top", "second@top"])
        #expect(!secondBox.isClosed)
    }

    @Test func aFirstSheetNotClearedWithinTheLimitFailsTheWaitingOne() {
        let first = FakeViewController("first"), second = FakeViewController("second")
        let firstBox = RequestBox(), secondBox = RequestBox()
        share(first, firstBox)
        share(second, secondBox)
        environment.advanceClock(by: limit)
        environment.runTurns()
        #expect(secondBox.outcome?.testName == "presentationFailed")
        #expect(presentationNames == ["first@top"], "the second is never presented")
        #expect(!firstBox.isClosed, "a presented sheet is never failed by the clock")

        // The first's completion, late, changes nothing.
        environment.finishPresentation(of: "first")
        environment.runTurns()
        #expect(presentationNames == ["first@top"])
        #expect(secondBox.outcome?.testName == "presentationFailed")
    }

    /// The first's record expires while the second waits (the second started later): the second
    /// fails instead of being checked again, since the expired sheet may still be pending in UIKit
    /// (C2-3).
    @Test func aRequestWokenByAnExpiredRecordFailsAndIsNotCheckedAgain() {
        let first = FakeViewController("first"), second = FakeViewController("second")
        let secondBox = RequestBox()
        share(first, RequestBox())
        environment.advanceClock(by: limit / 2)
        share(second, secondBox)
        environment.advanceClock(by: limit / 2)
        environment.runTurns()
        #expect(secondBox.outcome?.testName == "presentationFailed")
        #expect(presentationNames == ["first@top"])
        environment.advanceClock(by: limit)
        environment.runTurns()
        #expect(presentationNames == ["first@top"], "nothing later changes it")
    }

    @Test func aFreedFirstSheetWakesTheWaitingOneWithoutTheClock() async {
        let firstBox = RequestBox(), secondBox = RequestBox()
        let second = FakeViewController("second")
        var first: FakeViewController? = FakeViewController("first")
        share(first!, firstBox)
        share(second, secondBox)
        #expect(presentationNames == ["first@top"], "the second waits")
        // The fake UIKit keeps only the completion (which holds the watch weakly): the first
        // sheet is freed here, and its watch tells the records on the main queue.
        first = nil
        #expect(firstBox.outcome?.testName == "presentationFailed", "the release watch closed it")
        #expect(await waitUntil { environment.pendingTurns > 0 }, "the waiting request is woken")
        environment.runTurns()
        #expect(presentationNames == ["first@top", "second@top"])
        #expect(!secondBox.isClosed)
    }

    @Test func aWaitingRequestWhoseBoxClosesIsNotPresented() {
        let first = FakeViewController("first"), second = FakeViewController("second")
        let secondBox = RequestBox()
        share(first, RequestBox())
        share(second, secondBox)
        secondBox.close(.canceled)
        environment.finishPresentation(of: "first")
        environment.runTurns()
        #expect(presentationNames == ["first@top"])
        #expect(secondBox.outcome?.testName == "canceled")
    }

    @Test func threeSheetsInOneTurnPresentTheSecondAndFailTheThird() {
        let boxes = [RequestBox(), RequestBox(), RequestBox()]
        for (index, name) in ["first", "second", "third"].enumerated() {
            share(keep(name), boxes[index])
        }
        environment.finishPresentation(of: "first")
        environment.runTurns()
        #expect(presentationNames == ["first@top", "second@top"])
        #expect(!boxes[1].isClosed)
        #expect(boxes[2].outcome?.testName == "presentationFailed", "still a pending sheet on the one retry")
    }

    /// A transition of the host and a pending sheet: the request waits for the sheet; if the
    /// transition is still running on the one retry, it fails.
    @Test func withATransitionAndAPendingSheetTheSheetIsWaitedFor() {
        let secondBox = RequestBox()
        share(keep("first"), RequestBox())
        top.isSettled = false
        top.hasTransition = true
        share(keep("second"), secondBox)
        #expect(environment.transitionWaits.isEmpty)
        environment.finishPresentation(of: "first")
        environment.runTurns()
        #expect(secondBox.outcome?.testName == "presentationFailed")
        #expect(presentationNames == ["first@top"])
    }

    // MARK: - What the records hold

    /// A record that outlived its lifetime stays, as stuck, until its sheet clears: UIKit may still
    /// be presenting that sheet. Meanwhile every request on its window fails at once (Codex's
    /// implementation review 1).
    @Test func anExpiredRecordFailsLaterRequestsAtOnceUntilItClears() {
        let firstBox = RequestBox(), laterBox = RequestBox(), alertBox = RequestBox()
        share(keep("first"), firstBox)
        environment.advanceClock(by: limit)
        share(keep("later"), laterBox)
        alert(keep("alert"), alertBox)
        #expect(laterBox.outcome?.testName == "presentationFailed")
        #expect(alertBox.outcome?.testName == "presentationFailed")
        #expect(environment.pendingTurns == 0, "no waiting")
        #expect(presentationNames == ["first@top"])
        #expect(!firstBox.isClosed, "the stuck sheet's own box is left to its handler and watch")

        environment.finishPresentation(of: "first")
        let lastBox = RequestBox()
        share(keep("last"), lastBox)
        #expect(presentationNames == ["first@top", "last@top"])
        #expect(!lastBox.isClosed)
    }

    @Test func aStuckRecordWhoseSheetIsFreedNoLongerHolds() async {
        var first: FakeViewController? = FakeViewController("first")
        share(first!, RequestBox())
        environment.advanceClock(by: limit)
        first = nil
        let laterBox = RequestBox()
        share(keep("later"), laterBox)
        #expect(presentationNames == ["first@top", "later@top"])
        #expect(!laterBox.isClosed)
    }

    @Test func anAlertMakesNoRecord() {
        alert(keep("alert"), RequestBox())
        #expect(environment.records.counts.records == 0)
        share(keep("sheet"), RequestBox())
        #expect(presentationNames == ["alert@top", "sheet@top"])
    }

    @Test func aSheetInAnotherWindowDoesNotHoldTheRequest() {
        let other = keep("other")
        other.window = NSObject()
        share(keep("first"), RequestBox())
        let secondBox = RequestBox()
        share(keep("second"), secondBox, PresenterSelection(kind: .provided { other }))
        #expect(presentationNames == ["first@top", "second@other"])
        #expect(!secondBox.isClosed)
    }

    /// The end of a sheet wakes only the requests of its own window (the subagent's
    /// implementation review 2): a request woken by another window would spend its one retry.
    @Test func theEndOfASheetWakesOnlyTheRequestsOfItsWindow() {
        let window2 = NSObject()
        let top2 = keep("top2")
        top2.window = window2
        let waitingBox1 = RequestBox(), waitingBox2 = RequestBox()
        share(keep("sheet1"), RequestBox())
        share(keep("sheet2"), RequestBox(), PresenterSelection(kind: .provided { top2 }))
        share(keep("waiting1"), waitingBox1)
        share(keep("waiting2"), waitingBox2, PresenterSelection(kind: .provided { top2 }))
        #expect(environment.records.counts.waiters == 2)

        environment.finishPresentation(of: "sheet1")
        #expect(environment.pendingTurns == 1, "only the first window's request is woken")
        #expect(environment.records.counts.waiters == 1)
        environment.runTurns()
        #expect(presentationNames == ["sheet1@top", "sheet2@top2", "waiting1@top"])
        #expect(!waitingBox2.isClosed, "the second window's request still waits")

        environment.finishPresentation(of: "sheet2")
        environment.runTurns()
        #expect(presentationNames == ["sheet1@top", "sheet2@top2", "waiting1@top", "waiting2@top2"])
    }

    @Test func theLegacyStabilityCheckFailsAtOnceWhileASheetIsPending() {
        let secondBox = RequestBox()
        share(keep("first"), RequestBox(), .firstActiveScene)
        share(keep("second"), secondBox, .firstActiveScene)
        #expect(secondBox.outcome?.testName == "presentationFailed")
        #expect(presentationNames == ["first@top"])
        #expect(environment.pendingTurns == 0, "no waiting")
    }

    @Test func presentingAnywayDoesNotLookAtTheRecords() {
        share(keep("sheet"), RequestBox())
        environment.advanceClock(by: limit)
        alert(keep("alert"), RequestBox(), .firstActiveScene)
        #expect(presentationNames == ["sheet@top", "alert@top"], "not even a stuck one")
    }

    /// The end of the request (its box) and the end of the presentation are apart: `onPresented`
    /// comes with `present`'s completion even when the box is already closed (R4-2).
    @Test func onPresentedComesEvenWhenTheBoxIsAlreadyClosed() {
        let box = RequestBox()
        var presentedCalls = 0
        share(keep("sheet"), box, onPresented: { presentedCalls += 1 })
        box.close(.canceled)
        environment.finishPresentation(of: "sheet")
        #expect(presentedCalls == 1)
        #expect(environment.records.counts.records == 0)
    }

    /// A request that failed on the expiry is dropped: nothing keeps its view controller.
    @Test func aRequestThatFailedOnTheExpiryIsLetGo() {
        share(keep("first"), RequestBox())
        weak var weakSecond: FakeViewController?
        do {
            let second = FakeViewController("second")
            weakSecond = second
            share(second, RequestBox())
        }
        #expect(weakSecond != nil, "kept while it waits")
        environment.advanceClock(by: limit)
        environment.runTurns()
        #expect(weakSecond == nil, "let go once it failed")
        #expect(environment.records.counts.waiters == 0)
    }

    // MARK: - The records alone

    @Test func anOldEndDoesNotEndANewRecord() {
        let records = PresentationRecords()
        let window = FakeViewController.mainWindow
        let first = FakeViewController("first"), second = FakeViewController("second")
        let firstID = records.makeID()
        records.begin(firstID, presented: first, window: window)
        records.end(firstID, .cleared)
        records.begin(records.makeID(), presented: second, window: window)
        records.end(firstID, .cleared)
        records.end(firstID, .expired)
        #expect(records.state(in: window) == .pending)
    }

    @Test func aWaiterIsWokenOnceByTheFirstEnd() {
        let records = PresentationRecords()
        let window = FakeViewController.mainWindow
        let first = FakeViewController("first"), second = FakeViewController("second")
        let firstID = records.makeID(), secondID = records.makeID()
        records.begin(firstID, presented: first, window: window)
        records.begin(secondID, presented: second, window: window)
        var wakes: [PresentationRecords.End] = []
        records.wait(records.makeID(), in: window) { wakes.append($0) }
        records.end(firstID, .cleared)
        records.end(secondID, .expired)
        #expect(wakes == [.cleared])
        #expect(records.counts.waiters == 0)
        #expect(records.state(in: window) == .stuck)
    }

    /// A record whose sheet is freed is cleared when the state is read, without the release
    /// watch's notice (the subagent's implementation review 3).
    @Test func aRecordWhoseSheetIsFreedIsClearedWithoutTheNotice() {
        let records = PresentationRecords()
        let window = FakeViewController.mainWindow
        do {
            let sheet = FakeViewController("sheet")
            records.begin(records.makeID(), presented: sheet, window: window)
        }
        #expect(records.state(in: window) == .clear)
        #expect(records.counts.records == 0)
    }

    /// A record whose window is freed is cleared: its window cannot be presented on, and another
    /// window may reuse its address (the subagent's implementation review 5).
    @Test func aRecordWhoseWindowIsFreedIsCleared() {
        let records = PresentationRecords()
        let sheet = FakeViewController("sheet")
        var window: NSObject? = NSObject()
        records.begin(records.makeID(), presented: sheet, window: window)
        #expect(records.state(in: window) == .pending)
        window = nil
        let other = NSObject()
        #expect(records.state(in: other) == .clear)
        #expect(records.counts.records == 0)
    }
}

/// Keeps view controllers alive for the length of a test.
@MainActor
final class KeptViewControllers {
    private var all: [FakeViewController] = []

    func keep(_ viewController: FakeViewController) -> FakeViewController {
        all.append(viewController)
        return viewController
    }
}
