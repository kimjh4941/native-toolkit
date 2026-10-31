//
//  PresentationProcedureTests.swift
//  IosLibraryTests
//

import Foundation
import Testing
import UIKit
@testable import IosLibrary

/// UT-04: the steps of part 1 5.13.2 for each presenter (design 6.3.3), over a fake UIKit.
/// Also UT-01's check that the closure of `.viewController` is called once, on main.
@MainActor
struct PresentationProcedureTests {

    private let environment = FakePresentationEnvironment()
    private let box = RequestBox()
    private let presented = FakeViewController("presented")

    private func run(
        _ presenter: PresenterSelection,
        policy: PresentationProcedure.FirstActiveScenePolicy = .presentAnyway,
        onPresented: @escaping @MainActor () -> Void = {}
    ) {
        PresentationProcedure.present(
            presented,
            presenter: presenter,
            box: box,
            firstActiveScenePolicy: policy,
            environment: environment,
            onPresented: onPresented
        )
    }

    private var presentationNames: [String] {
        environment.presentations.map { "\($0.presented)@\($0.on)" }
    }

    // MARK: - .foreground (steps 1 to 6)

    @Test func notInTheForegroundClosesTheBoxAsNotForeground() {
        run(.foreground)

        #expect(box.outcome?.testName == "notForeground")
        #expect(environment.presentations.isEmpty)
        #expect(environment.transitionWaits.isEmpty)
    }

    @Test func aSettledForegroundIsPresentedAtOnceWithAnAnchor() {
        environment.foreground = FakeViewController("top")
        var presentedCalls = 0
        run(.foreground, onPresented: { presentedCalls += 1 })

        #expect(presentationNames == ["presented@top"])
        #expect(environment.anchored.map { "\($0.presented)@\($0.at)" } == ["presented@top"])
        #expect(environment.transitionWaits.isEmpty)
        #expect(!box.isClosed)
        #expect(presentedCalls == 0)
        environment.finishPresentations()
        #expect(presentedCalls == 1)
        #expect(!box.isClosed)
    }

    @Test func aTransitionIsWaitedForOnceAndTheForegroundIsSearchedAgainOnTheNextTurn() {
        let moving = FakeViewController("moving")
        moving.isSettled = false
        moving.hasTransition = true
        environment.foreground = moving
        run(.foreground)

        #expect(environment.transitionWaits == ["moving"])
        #expect(environment.presentations.isEmpty)
        #expect(environment.pendingTurns == 0)

        // The completion of the transition does not present: it queues the next turn.
        environment.foreground = FakeViewController("settled")
        environment.endTransitions()
        #expect(environment.presentations.isEmpty)
        #expect(environment.pendingTurns == 1)

        environment.runTurns()
        #expect(environment.foregroundSearches == 2)
        #expect(presentationNames == ["presented@settled"])
        #expect(!box.isClosed)
    }

    @Test func withoutATransitionToWaitForTheNextTurnChecksAgain() {
        let busy = FakeViewController("busy")
        busy.isSettled = false
        environment.foreground = busy
        run(.foreground)

        #expect(environment.transitionWaits == ["busy"])
        #expect(environment.pendingTurns == 1)
        busy.isSettled = true
        environment.runTurns()

        #expect(presentationNames == ["presented@busy"])
    }

    @Test func stillNotSettledAfterTheOneWaitFailsThePresentation() {
        let moving = FakeViewController("moving")
        moving.isSettled = false
        moving.hasTransition = true
        environment.foreground = moving
        run(.foreground)

        environment.endTransitions()
        environment.runTurns()
        // The second check fails at once: no second wait.
        environment.endTransitions()
        environment.runTurns()

        #expect(environment.transitionWaits == ["moving"])
        #expect(environment.foregroundSearches == 2)
        #expect(environment.presentations.isEmpty)
        #expect(box.outcome?.testName == "presentationFailed")
    }

    @Test func notInTheForegroundOnTheSecondCheckIsNotForeground() {
        let moving = FakeViewController("moving")
        moving.isSettled = false
        environment.foreground = moving
        run(.foreground)

        environment.foreground = nil
        environment.runTurns()

        #expect(box.outcome?.testName == "notForeground")
        #expect(environment.presentations.isEmpty)
    }

    @Test func aTransitionEndReportedTwiceStillChecksOnlyOnce() {
        let moving = FakeViewController("moving")
        moving.isSettled = false
        moving.hasTransition = true
        environment.foreground = moving
        run(.foreground)

        environment.endTransitions(times: 2)
        #expect(environment.pendingTurns == 1)
        environment.runTurns()
        #expect(environment.foregroundSearches == 2)
        #expect(box.outcome?.testName == "presentationFailed")
    }

    /// UIKit refuses the wait but calls the completion anyway, inside the call or later: still
    /// exactly one re-check and one presentation.
    @Test(arguments: [FakeViewController.RefusedWaitCall.callsAtOnce, .callsLater])
    func aRefusedWaitWhoseCompletionStillComesChecksOnce(_ call: FakeViewController.RefusedWaitCall) {
        let moving = FakeViewController("moving")
        moving.isSettled = false
        moving.refusedWaitStillCalls = call
        environment.foreground = moving
        run(.foreground)

        moving.isSettled = true
        environment.endTransitions()
        #expect(environment.pendingTurns == 1)
        environment.runTurns()
        environment.endTransitions()
        environment.runTurns()

        #expect(environment.transitionWaits == ["moving"])
        #expect(environment.foregroundSearches == 2)
        #expect(presentationNames == ["presented@moving"])
        #expect(!box.isClosed)
    }

    @Test func aRequestCancelledWhileWaitingIsNotPresented() {
        let moving = FakeViewController("moving")
        moving.isSettled = false
        moving.hasTransition = true
        environment.foreground = moving
        run(.foreground)

        box.close(.canceled)
        moving.isSettled = true
        environment.endTransitions()
        environment.runTurns()

        #expect(environment.presentations.isEmpty)
        #expect(environment.foregroundSearches == 1)
        #expect(box.outcome?.testName == "canceled")
    }

    @Test func aBoxClosedBeforeTheStartIsNeverLookedAt() {
        environment.foreground = FakeViewController("top")
        environment.firstActive = FakeViewController("top")
        box.close(.canceled)

        run(.foreground)
        run(.firstActiveScene)
        var providerCalls = 0
        run(.viewController { providerCalls += 1; return nil })

        #expect(environment.foregroundSearches == 0)
        #expect(environment.firstActiveSearches == 0)
        #expect(providerCalls == 0)
        #expect(environment.presentations.isEmpty)
        #expect(box.outcome?.testName == "canceled")
    }

    @Test func aPresentationUIKitDoesNotTakeFails() {
        environment.foreground = FakeViewController("top")
        environment.acceptsPresentation = false
        run(.foreground)

        #expect(presentationNames == ["presented@top"])
        #expect(box.outcome?.testName == "presentationFailed")
    }

    // MARK: - .firstActiveScene (steps 2 and 3 once)

    @Test func firstActiveScenePresentsWithoutWaitingWhenThePolicyIsToPresentAnyway() {
        let busy = FakeViewController("busy")
        busy.isSettled = false
        busy.hasTransition = true
        environment.firstActive = busy
        run(.firstActiveScene, policy: .presentAnyway)

        #expect(presentationNames == ["presented@busy"])
        #expect(environment.transitionWaits.isEmpty)
        #expect(environment.foregroundSearches == 0)
    }

    @Test func firstActiveSceneFailsAnUnstableViewControllerUnderTheLegacyCheck() {
        let busy = FakeViewController("busy")
        busy.isStableForLegacyPresentation = false
        environment.firstActive = busy
        run(.firstActiveScene, policy: .requireLegacyStability)

        #expect(environment.presentations.isEmpty)
        #expect(environment.transitionWaits.isEmpty)
        #expect(box.outcome?.testName == "presentationFailed")
    }

    @Test func firstActiveSceneUsesOnlyTheLegacyCheck() {
        // Not settled by the new definition (for example not in a window), but the legacy
        // check passes: presented, as before 1b.
        let top = FakeViewController("top")
        top.isSettled = false
        environment.firstActive = top
        run(.firstActiveScene, policy: .requireLegacyStability)

        #expect(presentationNames == ["presented@top"])
    }

    @Test func firstActiveSceneWithoutAViewControllerIsNotForeground() {
        run(.firstActiveScene)

        #expect(environment.firstActiveSearches == 1)
        #expect(box.outcome?.testName == "notForeground")
    }

    // MARK: - .viewController (steps 1 and 3 to 6) and UT-01

    @Test func theProvidedViewControllerIsAskedForOnceOnMainAndUsedForTheRetry() {
        let provided = FakeViewController("provided")
        provided.isSettled = false
        provided.hasTransition = true
        var calls = 0
        var calledOnMain = true
        run(.viewController {
            calls += 1
            calledOnMain = calledOnMain && Thread.isMainThread
            return nil
        })
        // `.viewController` takes a UIViewController; the fake environment uses its own node
        // type, so the closure is wrapped the way `viewController(_:)` wraps it.
        #expect(calls == 1)
        #expect(calledOnMain)
        #expect(box.outcome?.testName == "notForeground")

        let box2 = RequestBox()
        var calls2 = 0
        PresentationProcedure.present(
            presented,
            presenter: PresenterSelection(kind: .provided { calls2 += 1; return provided }),
            box: box2,
            firstActiveScenePolicy: .presentAnyway,
            environment: environment
        )
        #expect(environment.transitionWaits == ["provided"])
        provided.isSettled = true
        environment.endTransitions()
        environment.runTurns()

        #expect(calls2 == 1)
        #expect(presentationNames == ["presented@provided"])
        #expect(environment.foregroundSearches == 0)
        #expect(environment.firstActiveSearches == 0)
    }

    @Test func eachSelectionUsesItsOwnSearch() {
        environment.firstActive = FakeViewController("first")
        environment.foreground = FakeViewController("fore")

        PresentationProcedure.present(FakeViewController("a"), presenter: .firstActiveScene, box: RequestBox(),
                                      firstActiveScenePolicy: .presentAnyway, environment: environment)
        PresentationProcedure.present(FakeViewController("b"), presenter: .foreground, box: RequestBox(),
                                      firstActiveScenePolicy: .presentAnyway, environment: environment)
        let mine = FakeViewController("mine")
        PresentationProcedure.present(FakeViewController("c"), presenter: PresenterSelection(kind: .provided { mine }),
                                      box: RequestBox(), firstActiveScenePolicy: .presentAnyway, environment: environment)

        #expect(presentationNames == ["a@first", "b@fore", "c@mine"])
        #expect(environment.firstActiveSearches == 1)
        #expect(environment.foregroundSearches == 1)
    }

    // MARK: - Not presenting (permission request, settings): steps 1 and 2

    @Test func notPresentingOperationsDoNotRequireSettling() {
        let busy = FakeViewController("busy")
        busy.isSettled = false
        environment.foreground = busy
        var proceeded = 0
        PresentationProcedure.requireForeground(presenter: .foreground, box: box, environment: environment) { proceeded += 1 }

        #expect(proceeded == 1)
        #expect(environment.transitionWaits.isEmpty)
        #expect(!box.isClosed)
    }

    @Test func notPresentingOperationsFailOutsideTheForeground() {
        var proceeded = 0
        PresentationProcedure.requireForeground(presenter: .foreground, box: box, environment: environment) { proceeded += 1 }

        #expect(proceeded == 0)
        #expect(box.outcome?.testName == "notForeground")
    }

    @Test func notPresentingOperationsKeepTheCurrentBehaviorForTheFirstActiveScene() {
        var proceeded = 0
        PresentationProcedure.requireForeground(presenter: .firstActiveScene, box: box, environment: environment) { proceeded += 1 }

        #expect(proceeded == 1)
        #expect(environment.firstActiveSearches == 0)
        #expect(environment.foregroundSearches == 0)
    }

    @Test func notPresentingOperationsNeedTheProvidedViewControllerInAWindow() {
        let outside = FakeViewController("outside")
        outside.isInWindow = false
        let inside = FakeViewController("inside")
        var proceeded = 0
        let insideBox = RequestBox()

        PresentationProcedure.requireForeground(presenter: PresenterSelection(kind: .provided { outside }),
                                                box: box, environment: environment) { proceeded += 1 }
        PresentationProcedure.requireForeground(presenter: PresenterSelection(kind: .provided { inside }),
                                                box: insideBox, environment: environment) { proceeded += 1 }

        #expect(box.outcome?.testName == "notForeground")
        #expect(proceeded == 1)
        #expect(!insideBox.isClosed)
    }

    @Test func notPresentingOperationsDoNothingWithAClosedBox() {
        environment.foreground = FakeViewController("top")
        box.close(.canceled)
        var proceeded = 0
        PresentationProcedure.requireForeground(presenter: .foreground, box: box, environment: environment) { proceeded += 1 }

        #expect(proceeded == 0)
        #expect(environment.foregroundSearches == 0)
    }
}

/// UT-01: the values of `PresenterSelection`.
@MainActor
struct PresenterSelectionTests {

    @Test func theThreeValuesAreDistinct() {
        var provided = false
        let selections: [PresenterSelection] = [.firstActiveScene, .foreground, .viewController { provided = true; return nil }]
        let kinds = selections.map(\.logName)

        #expect(kinds == ["firstActiveScene", "foreground", "viewController"])
        // Making the value does not call the closure.
        #expect(!provided)
    }

    @Test func theViewControllerClosureReturnsWhatTheProviderReturns() {
        let viewController = UIViewController()
        let selection = PresenterSelection.viewController { viewController }
        guard case .provided(let provider) = selection.kind else {
            Issue.record("`.viewController` must be the provided kind")
            return
        }
        #expect(provider() === viewController)
    }

    @Test func theDefaultValuesAreTheStaticOnes() {
        guard case .firstActiveScene = PresenterSelection.firstActiveScene.kind,
              case .foreground = PresenterSelection.foreground.kind else {
            Issue.record("the static values must have their own kinds")
            return
        }
    }
}
