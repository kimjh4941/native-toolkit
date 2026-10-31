//
//  PresentationProcedure.swift
//  IosLibrary
//

import os
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "PresentationProcedure")

/// The UIKit work of ``PresentationProcedure``, behind a protocol so that the unit tests can
/// replace it (UT-04). ``UIKitPresentationEnvironment`` is the real one.
@MainActor
protocol PresentationEnvironment {
    /// A view controller (`UIViewController` in the app, a fake in the tests).
    associatedtype Node: AnyObject

    /// The current search (`.firstActiveScene`).
    func firstActiveSceneTop() -> Node?
    /// The foreground (`.foreground`).
    func foregroundTop() -> Node?
    /// Settled (part 1, 5.13.2): in a window, not being presented or dismissed, presenting
    /// nothing, and without a transition coordinator.
    func isSettled(_ node: Node) -> Bool
    /// The check the Share sheet made before ``PresentationProcedure`` existed: not being
    /// dismissed or presented, and presenting nothing (`.firstActiveScene` only).
    func isStableForLegacyPresentation(_ node: Node) -> Bool
    /// Whether the view controller is in a window (the non-presenting operations).
    func isInWindow(_ node: Node) -> Bool
    /// Calls `then` once when the transition that keeps `node` from being settled ends.
    /// - Returns: `false` when there is no transition to wait for; `then` is not called.
    func waitForTransition(of node: Node, then: @escaping @MainActor () -> Void) -> Bool
    /// Runs `body` on a later turn of the main queue.
    func nextTurn(_ body: @escaping @MainActor () -> Void)
    /// Anchors a popover (action sheets and share sheets on iPad) at the centre of `node`'s view
    /// when the presented view controller has a popover without an anchor (P1-13).
    func anchorPopover(of presented: Node, at node: Node)
    /// `node.present(presented, animated: true, completion:)`.
    func present(_ presented: Node, on node: Node, completion: @escaping @MainActor () -> Void)
    /// Whether UIKit took the presentation (`presented.presentingViewController != nil`).
    func isPresentationAccepted(_ presented: Node) -> Bool
}

/// The steps of the C ABI design part 1, 5.13.2, for each ``PresenterSelection``.
///
/// | Presenter | Presenting (Dialog, Share) | Not presenting (permission request, settings) |
/// |---|---|---|
/// | `.firstActiveScene` | Steps 2 and 3 once, no waiting (the behavior before 1b) | Nothing to check |
/// | `.foreground` | Steps 1 to 6 | Steps 1 and 2 |
/// | `.viewController` | Steps 1 and 3 to 6, with the one view controller the closure returned | In a window |
///
/// Every failure closes the request box (``RequestBoxOutcome/notForeground`` or
/// ``RequestBoxOutcome/presentationFailed``); a closed box stops the steps, so a request
/// cancelled while waiting is never presented. Presenting attaches a ``ReleaseWatch``.
@MainActor
enum PresentationProcedure {
    /// What a presenting operation does when `.firstActiveScene` finds a view controller that is
    /// not settled. Both keep the behavior from before 1b.
    enum FirstActiveScenePolicy {
        /// Present anyway (Dialog).
        case presentAnyway
        /// Fail as ``RequestBoxOutcome/presentationFailed`` unless the legacy check passes (Share).
        case requireLegacyStability
    }

    /// Presents `presented` from the view controller `presenter` selects, following the steps.
    ///
    /// - Parameters:
    ///   - presented: The view controller to present, made for this request only.
    ///   - presenter: How to choose the view controller to present from.
    ///   - box: The request's box. Closed boxes are not presented.
    ///   - firstActiveScenePolicy: What `.firstActiveScene` does when not settled.
    ///   - environment: UIKit, or a fake in the tests.
    ///   - onPresented: Called in `present`'s completion, after the release watch has noted it.
    static func present<Environment: PresentationEnvironment>(
        _ presented: Environment.Node,
        presenter: PresenterSelection,
        box: RequestBox,
        firstActiveScenePolicy: FirstActiveScenePolicy,
        environment: Environment,
        onPresented: @escaping @MainActor () -> Void = {}
    ) {
        logger.log(level: .libraryDebug, "[present] presented: \(String(describing: type(of: presented)), privacy: .public), presenter: \(presenter.logName, privacy: .public), policy: \(String(describing: firstActiveScenePolicy), privacy: .public)")
        // Step 1.
        guard !box.isClosed else {
            logger.log(level: .libraryDebug, "[present] the box is already closed")
            return
        }
        switch presenter.kind {
        case .firstActiveScene:
            guard let top = environment.firstActiveSceneTop() else {
                box.close(.notForeground)
                return
            }
            if firstActiveScenePolicy == .requireLegacyStability, !environment.isStableForLegacyPresentation(top) {
                logger.error("[present] the view controller is not in a stable state")
                box.close(.presentationFailed)
                return
            }
            show(presented, on: top, box: box, environment: environment, onPresented: onPresented)
        case .foreground:
            attempt(presented, retried: false, box: box, environment: environment, onPresented: onPresented) {
                environment.foregroundTop()
            }
        case .provided(let provider):
            // The closure is called once; the retry uses the same view controller (step 5).
            // A closure that returns nil, or (in the tests only) an object that is not the
            // environment's view controller type, means no view controller: not in the
            // foreground (`viewController(_:)` only produces `UIViewController?`).
            let provided = provider() as? Environment.Node
            attempt(presented, retried: false, box: box, environment: environment, onPresented: onPresented) {
                provided
            }
        }
    }

    /// For the operations that may show a system prompt but present nothing themselves: calls
    /// `proceed` when `presenter` finds the app in the foreground, otherwise closes `box` with
    /// ``RequestBoxOutcome/notForeground``. Settling is not required.
    static func requireForeground<Environment: PresentationEnvironment>(
        presenter: PresenterSelection,
        box: RequestBox,
        environment: Environment,
        proceed: @MainActor () -> Void
    ) {
        logger.log(level: .libraryDebug, "[requireForeground] presenter: \(presenter.logName, privacy: .public)")
        guard !box.isClosed else {
            logger.log(level: .libraryDebug, "[requireForeground] the box is already closed")
            return
        }
        let isForeground: Bool
        switch presenter.kind {
        case .firstActiveScene:
            isForeground = true
        case .foreground:
            isForeground = environment.foregroundTop() != nil
        case .provided(let provider):
            // nil (or another type, as above) means not in the foreground.
            isForeground = (provider() as? Environment.Node).map(environment.isInWindow) ?? false
        }
        guard isForeground else {
            box.close(.notForeground)
            return
        }
        proceed()
    }

    /// Steps 2 to 6. `locate` is step 2 (or the provided view controller).
    private static func attempt<Environment: PresentationEnvironment>(
        _ presented: Environment.Node,
        retried: Bool,
        box: RequestBox,
        environment: Environment,
        onPresented: @escaping @MainActor () -> Void,
        locate: @escaping @MainActor () -> Environment.Node?
    ) {
        logger.log(level: .libraryDebug, "[attempt] retried: \(retried, privacy: .public)")
        // Steps 1 and 5: a box closed while waiting (cancelled) is not presented.
        guard !box.isClosed else {
            logger.log(level: .libraryDebug, "[attempt] the box was closed while waiting")
            return
        }
        // Step 2.
        guard let top = locate() else {
            box.close(.notForeground)
            return
        }
        // Step 3.
        if environment.isSettled(top) {
            show(presented, on: top, box: box, environment: environment, onPresented: onPresented)
            return
        }
        // Step 6.
        guard !retried else {
            logger.error("[attempt] still not settled after waiting once")
            box.close(.presentationFailed)
            return
        }
        // Steps 4 and 5: wait once for the transition (if any), then check again on the next
        // turn of the main queue. `again` runs once even if UIKit both declines the wait and
        // calls the completion.
        var hasRetried = false
        let again: @MainActor () -> Void = {
            guard !hasRetried else { return }
            hasRetried = true
            environment.nextTurn {
                attempt(presented, retried: true, box: box, environment: environment, onPresented: onPresented, locate: locate)
            }
        }
        if !environment.waitForTransition(of: top, then: again) {
            again()
        }
    }

    /// Step 3 once settled: anchor, watch, present, and the check that UIKit took it.
    private static func show<Environment: PresentationEnvironment>(
        _ presented: Environment.Node,
        on top: Environment.Node,
        box: RequestBox,
        environment: Environment,
        onPresented: @escaping @MainActor () -> Void
    ) {
        logger.log(level: .libraryDebug, "[show]")
        guard !box.isClosed else {
            logger.log(level: .libraryDebug, "[show] the box is already closed")
            return
        }
        environment.anchorPopover(of: presented, at: top)
        let watch = ReleaseWatch(box: box)
        watch.attach(to: presented)
        environment.present(presented, on: top) {
            watch.markPresented()
            onPresented()
        }
        // The supplement of part 1, 5.13.1: UIKit sets `presentingViewController` inside
        // `present` when it takes the presentation (to be confirmed by MS-01).
        if !environment.isPresentationAccepted(presented) {
            logger.error("[show] UIKit did not take the presentation")
            box.close(.presentationFailed)
        }
    }
}

/// ``PresentationEnvironment`` over UIKit.
@MainActor
struct UIKitPresentationEnvironment: PresentationEnvironment {
    func firstActiveSceneTop() -> UIViewController? {
        logger.log(level: .libraryDebug, "[UIKit.firstActiveSceneTop]")
        return ForegroundLocator.firstActiveScene()
    }

    func foregroundTop() -> UIViewController? {
        logger.log(level: .libraryDebug, "[UIKit.foregroundTop]")
        return ForegroundLocator.foreground()
    }

    func isSettled(_ node: UIViewController) -> Bool {
        logger.log(level: .libraryDebug, "[UIKit.isSettled] node: \(String(describing: type(of: node)), privacy: .public)")
        return node.viewIfLoaded?.window != nil
            && !node.isBeingPresented
            && !node.isBeingDismissed
            && node.presentedViewController == nil
            && node.transitionCoordinator == nil
    }

    func isStableForLegacyPresentation(_ node: UIViewController) -> Bool {
        logger.log(level: .libraryDebug, "[UIKit.isStableForLegacyPresentation] node: \(String(describing: type(of: node)), privacy: .public)")
        return !node.isBeingDismissed && !node.isBeingPresented && node.presentedViewController == nil
    }

    func isInWindow(_ node: UIViewController) -> Bool {
        logger.log(level: .libraryDebug, "[UIKit.isInWindow] node: \(String(describing: type(of: node)), privacy: .public)")
        return node.viewIfLoaded?.window != nil
    }

    func waitForTransition(of node: UIViewController, then: @escaping @MainActor () -> Void) -> Bool {
        logger.log(level: .libraryDebug, "[UIKit.waitForTransition] node: \(String(describing: type(of: node)), privacy: .public)")
        // The view controller in the transition: the one being dismissed above `node`, or `node`.
        let moving = node.presentedViewController ?? node
        guard let coordinator = moving.transitionCoordinator ?? node.transitionCoordinator else {
            return false
        }
        // UIKit calls the completion on the main thread.
        return coordinator.animate(alongsideTransition: nil) { _ in
            MainActor.assumeIsolated { then() }
        }
    }

    func nextTurn(_ body: @escaping @MainActor () -> Void) {
        logger.log(level: .libraryDebug, "[UIKit.nextTurn]")
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body() }
        }
    }

    func anchorPopover(of presented: UIViewController, at node: UIViewController) {
        logger.log(level: .libraryDebug, "[UIKit.anchorPopover] presented: \(String(describing: type(of: presented)), privacy: .public), node: \(String(describing: type(of: node)), privacy: .public)")
        guard let popover = presented.popoverPresentationController,
              popover.sourceView == nil, popover.barButtonItem == nil, popover.sourceItem == nil else {
            logger.log(level: .libraryDebug, "[UIKit.anchorPopover] no popover without an anchor")
            return
        }
        // `view` loads the view if it is not loaded yet (a view controller in a window always has
        // it). The arrow directions are left as they are: `.any` by default, or what the caller
        // set on the popover.
        let view: UIView = node.view
        logger.log(level: .libraryDebug, "[UIKit.anchorPopover] anchoring at the centre of the presenting view")
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
    }

    func present(_ presented: UIViewController, on node: UIViewController, completion: @escaping @MainActor () -> Void) {
        logger.log(level: .libraryDebug, "[UIKit.present] presented: \(String(describing: type(of: presented)), privacy: .public), node: \(String(describing: type(of: node)), privacy: .public)")
        node.present(presented, animated: true) {
            completion()
        }
    }

    func isPresentationAccepted(_ presented: UIViewController) -> Bool {
        logger.log(level: .libraryDebug, "[UIKit.isPresentationAccepted] presented: \(String(describing: type(of: presented)), privacy: .public)")
        return presented.presentingViewController != nil
    }
}

extension PresenterSelection {
    /// The value's name for the log (the closure of `.viewController` is not shown).
    var logName: String {
        switch kind {
        case .firstActiveScene: return "firstActiveScene"
        case .foreground: return "foreground"
        case .provided: return "viewController"
        }
    }
}
