//
//  FakePresentationEnvironment.swift
//  IosLibraryTests
//

import Foundation
import Testing
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
    /// The window the view controller is in: the scope of the share sheets' records. Every fake
    /// view controller is in the same one unless a test moves it.
    var window: AnyObject? = FakeViewController.mainWindow
    /// Whether it stands for a share sheet (`UIActivityViewController`).
    var isShareSheet = false

    /// The window of the fake view controllers.
    static let mainWindow = NSObject()

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
    let records: PresentationRecords
    var firstActive: FakeViewController?
    var foreground: FakeViewController?
    /// Whether UIKit takes a presentation (`presentingViewController` is set).
    var acceptsPresentation = true

    private(set) var firstActiveSearches = 0
    private(set) var foregroundSearches = 0
    private(set) var transitionWaits: [String] = []
    private(set) var anchored: [(presented: String, at: String)] = []
    private(set) var presentations: [(presented: String, on: String)] = []
    /// The `animated` argument of each presentation.
    private(set) var presentationAnimations: [Bool] = []

    private var transitionEnds: [@MainActor () -> Void] = []
    private var turns: [@MainActor () -> Void] = []
    private var presentCompletions: [(presented: String, completion: @MainActor () -> Void)] = []
    private var timers: [(due: Double, body: @MainActor () -> Void)] = []
    /// The fake clock, in seconds; it moves only with ``advanceClock(by:)``.
    private(set) var now: Double = 0

    /// `records` is the instance every request made with this environment sees.
    init(records: PresentationRecords = PresentationRecords()) {
        self.records = records
    }

    var pendingTurns: Int { turns.count }
    var pendingTransitionEnds: Int { transitionEnds.count }
    var pendingPresentCompletions: Int { presentCompletions.count }
    var pendingTimers: Int { timers.count }

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

    func present(_ presented: FakeViewController, on node: FakeViewController, animated: Bool, completion: @escaping @MainActor () -> Void) {
        presentations.append((presented.name, node.name))
        presentationAnimations.append(animated)
        presentCompletions.append((presented.name, completion))
    }

    func isPresentationAccepted(_ presented: FakeViewController) -> Bool { acceptsPresentation }

    func window(of node: FakeViewController) -> AnyObject? { node.window }

    func isShareSheet(_ node: FakeViewController) -> Bool { node.isShareSheet }

    func after(seconds: Double, _ body: @escaping @MainActor () -> Void) {
        timers.append((now + seconds, body))
    }

    /// Moves the clock and runs the timers that are due, in the order they are due.
    func advanceClock(by seconds: Double) {
        now += seconds
        while let index = timers.indices.filter({ timers[$0].due <= now }).min(by: { timers[$0].due < timers[$1].due }) {
            timers.remove(at: index).body()
        }
    }

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
        completions.forEach { $0.completion() }
    }

    /// Calls the completion of the presentation of the view controller named `name` only.
    func finishPresentation(of name: String) {
        guard let index = presentCompletions.firstIndex(where: { $0.presented == name }) else {
            Issue.record("no presentation of \(name) is waiting for its completion")
            return
        }
        presentCompletions.remove(at: index).completion()
    }
}
