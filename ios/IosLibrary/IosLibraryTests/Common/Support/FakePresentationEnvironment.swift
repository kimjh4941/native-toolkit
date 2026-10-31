//
//  FakePresentationEnvironment.swift
//  IosLibraryTests
//

import Foundation
@testable import IosLibrary

/// A view controller for `PresentationProcedure`: an `NSObject`, so that the release watch can
/// be attached to it as to a real view controller.
@MainActor
final class FakeViewController: NSObject {
    let name: String
    var isSettled = true
    var isStableForLegacyPresentation = true
    var isInWindow = true
    /// Whether a transition is running that `waitForTransition` can wait for.
    var hasTransition = false
    /// A misbehaving UIKit: the wait is refused (`waitForTransition` returns `false`) and the
    /// completion is still called, at once (`.callsAtOnce`) or when the transitions end
    /// (`.callsLater`).
    var refusedWaitStillCalls: RefusedWaitCall?

    enum RefusedWaitCall {
        case callsAtOnce
        case callsLater
    }

    init(_ name: String) {
        self.name = name
    }
}

/// `PresentationEnvironment` whose UIKit work the test drives by hand: transitions end and
/// main-queue turns run only when the test says so.
@MainActor
final class FakePresentationEnvironment: PresentationEnvironment {
    var firstActive: FakeViewController?
    var foreground: FakeViewController?
    /// Whether UIKit takes a presentation (`presentingViewController` is set).
    var acceptsPresentation = true

    private(set) var firstActiveSearches = 0
    private(set) var foregroundSearches = 0
    private(set) var transitionWaits: [String] = []
    private(set) var anchored: [(presented: String, at: String)] = []
    private(set) var presentations: [(presented: String, on: String)] = []

    private var transitionEnds: [@MainActor () -> Void] = []
    private var turns: [@MainActor () -> Void] = []
    private var presentCompletions: [@MainActor () -> Void] = []

    var pendingTurns: Int { turns.count }
    var pendingTransitionEnds: Int { transitionEnds.count }
    var pendingPresentCompletions: Int { presentCompletions.count }

    func firstActiveSceneTop() -> FakeViewController? {
        firstActiveSearches += 1
        return firstActive
    }

    func foregroundTop() -> FakeViewController? {
        foregroundSearches += 1
        return foreground
    }

    func isSettled(_ node: FakeViewController) -> Bool { node.isSettled }

    func isStableForLegacyPresentation(_ node: FakeViewController) -> Bool { node.isStableForLegacyPresentation }

    func isInWindow(_ node: FakeViewController) -> Bool { node.isInWindow }

    func waitForTransition(of node: FakeViewController, then: @escaping @MainActor () -> Void) -> Bool {
        transitionWaits.append(node.name)
        switch node.refusedWaitStillCalls {
        case .callsAtOnce:
            then()
            return false
        case .callsLater:
            transitionEnds.append(then)
            return false
        case nil:
            break
        }
        guard node.hasTransition else { return false }
        transitionEnds.append(then)
        return true
    }

    func nextTurn(_ body: @escaping @MainActor () -> Void) {
        turns.append(body)
    }

    func anchorPopover(of presented: FakeViewController, at node: FakeViewController) {
        anchored.append((presented.name, node.name))
    }

    func present(_ presented: FakeViewController, on node: FakeViewController, completion: @escaping @MainActor () -> Void) {
        presentations.append((presented.name, node.name))
        presentCompletions.append(completion)
    }

    func isPresentationAccepted(_ presented: FakeViewController) -> Bool { acceptsPresentation }

    /// Ends every running transition (calls the waits' completions). `times` calls each one
    /// that many times, as a misbehaving UIKit might.
    func endTransitions(times: Int = 1) {
        let ends = transitionEnds
        transitionEnds = []
        for end in ends {
            for _ in 0..<times { end() }
        }
    }

    /// Runs the queued main-queue turns, including the ones they queue.
    func runTurns() {
        while !turns.isEmpty {
            turns.removeFirst()()
        }
    }

    /// Calls `present`'s completions.
    func finishPresentations() {
        let completions = presentCompletions
        presentCompletions = []
        completions.forEach { $0() }
    }
}
