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
    /// `node.present(presented, animated: animated, completion:)`.
    func present(_ presented: Node, on node: Node, animated: Bool, completion: @escaping @MainActor () -> Void)
    /// Whether UIKit took the presentation (`presented.presentingViewController != nil`).
    func isPresentationAccepted(_ presented: Node) -> Bool
    /// The records of the share sheets still being presented (SH-13). Every request must see the
    /// same instance: UIKit's is ``PresentationRecords/shared``.
    var records: PresentationRecords { get }
    /// The window `node` is in, as the scope of a record (`nil` when it is in none).
    func window(of node: Node) -> AnyObject?
    /// Whether `node` is a share sheet (`UIActivityViewController`): a share sheet is never
    /// presented on one (SH-13, D-2).
    func isShareSheet(_ node: Node) -> Bool
    /// Runs `body` on the main queue after `seconds`.
    func after(seconds: Double, _ body: @escaping @MainActor () -> Void)
}

/// The UIKit parts of ``PresentationEnvironment`` that the environments over UIKit (the real one
/// and the tests' wrappers of it) share.
extension PresentationEnvironment where Node == UIViewController {
    var records: PresentationRecords { PresentationRecords.shared }

    func window(of node: UIViewController) -> AnyObject? {
        logger.log(level: .libraryDebug, "[UIKit.window] node: \(String(describing: type(of: node)), privacy: .public)")
        return node.viewIfLoaded?.window
    }

    func isShareSheet(_ node: UIViewController) -> Bool {
        logger.log(level: .libraryDebug, "[UIKit.isShareSheet] node: \(String(describing: type(of: node)), privacy: .public)")
        return node is UIActivityViewController
    }

    func after(seconds: Double, _ body: @escaping @MainActor () -> Void) {
        logger.log(level: .libraryDebug, "[UIKit.after] seconds: \(seconds, privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { body() }
        }
    }
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
///
/// A share sheet (`releaseWatchOnly`) is recorded in ``PresentationRecords`` until its `present`
/// completes: UIKit shows nothing of it before then and declines (and keeps) a sheet presented on
/// the same view controller meanwhile (SH-13). A request on the same window counts as not settled
/// until the record ends, and waits for it in step 4. A share sheet is never presented on a share
/// sheet.
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

    /// How a presentation that UIKit declines is noticed (part 1, 5.13.1). The release watch
    /// notices it in both cases, once UIKit has let the declined view controller go.
    enum DeclineCheck {
        /// Also check `presentingViewController` right after `present` (the supplement of 6.3.3):
        /// UIKit sets it inside `present` for an alert (MS-01).
        case rightAfterPresent
        /// The release watch only: UIKit sets `presentingViewController` of a share sheet only
        /// later (MS-03, stage 1b C3), so the supplement would fail every share.
        case releaseWatchOnly
    }

    /// How long a share sheet's record holds the requests on its window, and so the longest a
    /// request waits for a pending sheet (SH-13, D-3): seconds.
    static let pendingSheetLimit: Double = 10

    /// Presents `presented` from the view controller `presenter` selects, following the steps.
    ///
    /// - Parameters:
    ///   - presented: The view controller to present, made for this request only.
    ///   - presenter: How to choose the view controller to present from.
    ///   - box: The request's box. Closed boxes are not presented.
    ///   - firstActiveScenePolicy: What `.firstActiveScene` does when not settled.
    ///   - environment: UIKit, or a fake in the tests.
    ///   - animated: Whether `present` animates (the dialog methods that take `animated`).
    ///   - declineCheck: How a presentation that UIKit declines is noticed.
    ///   - onPresented: Called in `present`'s completion, after the release watch has noted it
    ///     (when the watch is still alive: it is held weakly there).
    static func present<Environment: PresentationEnvironment>(
        _ presented: Environment.Node,
        presenter: PresenterSelection,
        box: RequestBox,
        firstActiveScenePolicy: FirstActiveScenePolicy,
        environment: Environment,
        animated: Bool = true,
        declineCheck: DeclineCheck = .rightAfterPresent,
        onPresented: @escaping @MainActor () -> Void = {}
    ) {
        logger.log(level: .libraryDebug, "[present] presented: \(String(describing: type(of: presented)), privacy: .public), presenter: \(presenter.logName, privacy: .public), policy: \(String(describing: firstActiveScenePolicy), privacy: .public), animated: \(animated, privacy: .public), declineCheck: \(String(describing: declineCheck), privacy: .public)")
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
            if declineCheck == .releaseWatchOnly, environment.isShareSheet(top) {
                logger.error("[present] a share sheet is not presented on a share sheet")
                box.close(.presentationFailed)
                return
            }
            // A share sheet of the library still pending on the window counts as not stable:
            // UIKit would decline (and keep) a sheet presented now (SH-13).
            if firstActiveScenePolicy == .requireLegacyStability,
               !environment.isStableForLegacyPresentation(top)
                || environment.records.state(in: environment.window(of: top)) != .clear {
                logger.error("[present] the view controller is not in a stable state")
                box.close(.presentationFailed)
                return
            }
            show(presented, on: top, box: box, environment: environment, animated: animated, declineCheck: declineCheck, onPresented: onPresented)
        case .foreground:
            attempt(presented, retried: false, box: box, environment: environment, animated: animated, declineCheck: declineCheck,
                    onPresented: onPresented) {
                environment.foregroundTop()
            }
        case .provided(let provider):
            // The closure is called once; the retry uses the same view controller (step 5).
            // A closure that returns nil, or (in the tests only) an object that is not the
            // environment's view controller type, means no view controller: not in the
            // foreground (`viewController(_:)` only produces `UIViewController?`).
            let provided = provider() as? Environment.Node
            attempt(presented, retried: false, box: box, environment: environment, animated: animated, declineCheck: declineCheck,
                    onPresented: onPresented) {
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
        animated: Bool,
        declineCheck: DeclineCheck,
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
        // A share sheet is not presented on a share sheet (SH-13, D-2): on iOS 18, the lower sheet
        // dismissed from outside while the upper one is being presented on it keeps both alive,
        // and neither share would end. This is the usual end of a second share made in the same
        // turn as a first one: it waited for the first, which is now the foreground.
        if declineCheck == .releaseWatchOnly, environment.isShareSheet(top) {
            logger.error("[attempt] a share sheet is not presented on a share sheet")
            box.close(.presentationFailed)
            return
        }
        // Step 3: settled, and no share sheet of the library pending on the same window (UIKit
        // shows nothing of a sheet it is still preparing. SH-13).
        let window = environment.window(of: top)
        let sheets = environment.records.state(in: window)
        // A sheet that outlived its lifetime may still be in UIKit's hands: nothing can be
        // presented on its window until it clears, so the request fails at once.
        guard sheets != .stuck else {
            logger.error("[attempt] a share sheet of the window is stuck")
            box.close(.presentationFailed)
            return
        }
        let sheetPending = sheets == .pending
        if environment.isSettled(top), !sheetPending {
            show(presented, on: top, box: box, environment: environment, animated: animated, declineCheck: declineCheck, onPresented: onPresented)
            return
        }
        // Step 6.
        guard !retried else {
            logger.error("[attempt] still not settled after waiting once, sheetPending: \(sheetPending, privacy: .public)")
            box.close(.presentationFailed)
            return
        }
        // Steps 4 and 5: wait once for the pending sheet or the transition (if any), then check
        // again on the next turn of the main queue. `again` runs once even if UIKit both declines
        // the wait and calls the completion, or the sheet and the time limit both end the wait.
        var hasRetried = false
        let again: @MainActor () -> Void = {
            guard !hasRetried else { return }
            hasRetried = true
            environment.nextTurn {
                attempt(presented, retried: true, box: box, environment: environment, animated: animated, declineCheck: declineCheck,
                        onPresented: onPresented,
                        locate: locate)
            }
        }
        if sheetPending {
            waitForPendingSheet(in: window, environment: environment, again: again)
        } else if !environment.waitForTransition(of: top, then: again) {
            again()
        }
    }

    /// Step 4 for a pending share sheet: waits until a sheet of `window` is cleared or expires, then
    /// checks again (`again`). After an expiry the check finds the record stuck and fails the
    /// request: the expired sheet may still be pending in UIKit (SH-13, 4.3). The wait needs no
    /// clock of its own: the record it waits for started earlier and expires within
    /// ``pendingSheetLimit``. Only the records hold `again` (and with it the request), and they drop
    /// it once it is woken.
    private static func waitForPendingSheet<Environment: PresentationEnvironment>(
        in window: AnyObject?,
        environment: Environment,
        again: @escaping @MainActor () -> Void
    ) {
        logger.log(level: .libraryDebug, "[waitForPendingSheet] hasWindow: \(window != nil, privacy: .public)")
        let records = environment.records
        records.wait(records.makeID(), in: window) { end in
            logger.log(level: .libraryDebug, "[waitForPendingSheet] woken: \(String(describing: end), privacy: .public)")
            again()
        }
    }

    /// Step 3 once settled: anchor, watch, present, and the check that UIKit took it.
    private static func show<Environment: PresentationEnvironment>(
        _ presented: Environment.Node,
        on top: Environment.Node,
        box: RequestBox,
        environment: Environment,
        animated: Bool,
        declineCheck: DeclineCheck,
        onPresented: @escaping @MainActor () -> Void
    ) {
        logger.log(level: .libraryDebug, "[show] animated: \(animated, privacy: .public), declineCheck: \(String(describing: declineCheck), privacy: .public)")
        guard !box.isClosed else {
            logger.log(level: .libraryDebug, "[show] the box is already closed")
            return
        }
        environment.anchorPopover(of: presented, at: top)
        // A share sheet is recorded until `present` completes, it is freed, or its record expires
        // (SH-13). An alert is not: UIKit shows it on the presenting view controller at once.
        let records = environment.records
        let record: PresentationRecords.ID? = declineCheck == .releaseWatchOnly ? records.makeID() : nil
        var onRelease: (@Sendable () -> Void)?
        if let record {
            onRelease = { [weak records] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { records?.end(record, .cleared) }
                }
            }
        }
        let watch = ReleaseWatch(box: box, onRelease: onRelease)
        watch.attach(to: presented)
        if let record {
            records.begin(record, presented: presented, window: environment.window(of: top))
            environment.after(seconds: pendingSheetLimit) { [weak records] in
                records?.end(record, .expired)
            }
        }
        // Weakly: the presented view controller is the watch's only owner (a declined view
        // controller whose completion UIKit kept would otherwise keep the watch, the records and
        // the requests waiting in them alive). `onPresented` comes even when the box is closed:
        // the request and the presentation end apart (R4-2).
        environment.present(presented, on: top, animated: animated) { [weak watch, weak records] in
            watch?.markPresented()
            if let record { records?.end(record, .cleared) }
            onPresented()
        }
        // The supplement of part 1, 5.13.1: UIKit sets `presentingViewController` of an alert
        // inside `present` when it takes the presentation, and calls no completion when it
        // declines (MS-01, iOS 26.2 and 18.3). Not for a share sheet (`releaseWatchOnly`).
        if declineCheck == .rightAfterPresent, !environment.isPresentationAccepted(presented) {
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

    func present(_ presented: UIViewController, on node: UIViewController, animated: Bool, completion: @escaping @MainActor () -> Void) {
        logger.log(level: .libraryDebug, "[UIKit.present] presented: \(String(describing: type(of: presented)), privacy: .public), node: \(String(describing: type(of: node)), privacy: .public), animated: \(animated, privacy: .public)")
        node.present(presented, animated: animated) {
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
