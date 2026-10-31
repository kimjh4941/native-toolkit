//
//  ShareSheetPresenterTests.swift
//  IosLibraryTests
//

import Foundation
import Testing
import UIKit
@testable import IosLibrary

extension Result where Success == ShareResult, Failure == ShareError {
    /// A comparable name (`ShareResult` is not `Equatable`).
    var testName: String {
        switch self {
        case .success(let result): return "success(completed: \(result.completed), activityType: \(result.activityType ?? "nil"))"
        case .failure(let error): return "failure(\(error))"
        }
    }
}

extension MainRecorder where Value == Result<ShareResult, ShareError> {
    /// The names of the recorded results, in order.
    var names: [String] { values.map(\.testName) }
}

/// The name of a failed share.
func failed(_ error: ShareError) -> String {
    Result<ShareResult, ShareError>.failure(error).testName
}

/// The sheets a ``ShareSheetPresenter`` built, in order, held weakly (as the library holds them),
/// so that a dismissed sheet can be freed and its release watch can close the box.
@MainActor
final class SheetRecorder {
    private final class Entry {
        weak var sheet: UIActivityViewController?

        init(_ sheet: UIActivityViewController) {
            self.sheet = sheet
        }
    }

    private var entries: [Entry] = []

    func record(_ sheet: UIActivityViewController) {
        entries.append(Entry(sheet))
    }

    /// How many sheets were built.
    var count: Int { entries.count }

    /// The latest sheet, while it is alive.
    var last: UIActivityViewController? { entries.last?.sheet }
}

extension ShareSheetPresenter where Environment == UIKitPresentationEnvironment {
    /// The UIKit presenter, with `recorder` seeing each sheet.
    static func recording(into recorder: SheetRecorder) -> ShareSheetPresenter<UIKitPresentationEnvironment> {
        ShareSheetPresenter(makeEnvironment: { UIKitPresentationEnvironment() },
                            observeSheet: { sheet in recorder.record(sheet) })
    }
}

/// Counts and keeps the view controllers an environment presents.
@MainActor
final class PresentationLog {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

/// UIKit, except that every view controller counts as settled, so that the presentation reaches
/// UIKit even when UIKit declines it (a view controller that already presents another one).
@MainActor
struct AlwaysSettledEnvironment: PresentationEnvironment {
    let base = UIKitPresentationEnvironment()

    func firstActiveSceneTop() -> UIViewController? { base.firstActiveSceneTop() }
    func foregroundTop() -> UIViewController? { base.foregroundTop() }
    func isSettled(_ node: UIViewController) -> Bool { true }
    func isStableForLegacyPresentation(_ node: UIViewController) -> Bool { true }
    func isInWindow(_ node: UIViewController) -> Bool { base.isInWindow(node) }
    func waitForTransition(of node: UIViewController, then: @escaping @MainActor () -> Void) -> Bool { false }
    func nextTurn(_ body: @escaping @MainActor () -> Void) { base.nextTurn(body) }
    func anchorPopover(of presented: UIViewController, at node: UIViewController) { base.anchorPopover(of: presented, at: node) }
    func present(_ presented: UIViewController, on node: UIViewController, animated: Bool, completion: @escaping @MainActor () -> Void) {
        base.present(presented, on: node, animated: animated, completion: completion)
    }
    func isPresentationAccepted(_ presented: UIViewController) -> Bool { base.isPresentationAccepted(presented) }
}

/// The popover anchor of each presented view controller when `present` is called (UIKit may
/// replace it afterwards: the iPhone of iOS 26.2 anchors the sheet at its own transition view).
@MainActor
final class AnchorLog {
    struct Anchor {
        let sourceView: UIView?
        let sourceRect: CGRect
        let arrows: UIPopoverArrowDirection
    }

    private(set) var anchors: [Anchor?] = []

    func record(_ presented: UIViewController) {
        anchors.append(presented.popoverPresentationController.map {
            Anchor(sourceView: $0.sourceView, sourceRect: $0.sourceRect, arrows: $0.permittedArrowDirections)
        })
    }
}

/// UIKit, recording the popover anchor at `present`.
@MainActor
struct AnchorRecordingEnvironment: PresentationEnvironment {
    let base = UIKitPresentationEnvironment()
    let log: AnchorLog

    func firstActiveSceneTop() -> UIViewController? { base.firstActiveSceneTop() }
    func foregroundTop() -> UIViewController? { base.foregroundTop() }
    func isSettled(_ node: UIViewController) -> Bool { base.isSettled(node) }
    func isStableForLegacyPresentation(_ node: UIViewController) -> Bool { base.isStableForLegacyPresentation(node) }
    func isInWindow(_ node: UIViewController) -> Bool { base.isInWindow(node) }
    func waitForTransition(of node: UIViewController, then: @escaping @MainActor () -> Void) -> Bool {
        base.waitForTransition(of: node, then: then)
    }
    func nextTurn(_ body: @escaping @MainActor () -> Void) { base.nextTurn(body) }
    func anchorPopover(of presented: UIViewController, at node: UIViewController) { base.anchorPopover(of: presented, at: node) }
    func present(_ presented: UIViewController, on node: UIViewController, animated: Bool, completion: @escaping @MainActor () -> Void) {
        log.record(presented)
        base.present(presented, on: node, animated: animated, completion: completion)
    }
    func isPresentationAccepted(_ presented: UIViewController) -> Bool { base.isPresentationAccepted(presented) }
}

/// UIKit, except that the view controller found by `.firstActiveScene` is never stable in the
/// sense of the share sheet's check from before 1b. Records the presentations.
@MainActor
struct UnstableForLegacyEnvironment: PresentationEnvironment {
    let base = UIKitPresentationEnvironment()
    let log: PresentationLog

    func firstActiveSceneTop() -> UIViewController? { base.firstActiveSceneTop() }
    func foregroundTop() -> UIViewController? { base.foregroundTop() }
    func isSettled(_ node: UIViewController) -> Bool { base.isSettled(node) }
    func isStableForLegacyPresentation(_ node: UIViewController) -> Bool { false }
    func isInWindow(_ node: UIViewController) -> Bool { base.isInWindow(node) }
    func waitForTransition(of node: UIViewController, then: @escaping @MainActor () -> Void) -> Bool {
        base.waitForTransition(of: node, then: then)
    }
    func nextTurn(_ body: @escaping @MainActor () -> Void) { base.nextTurn(body) }
    func anchorPopover(of presented: UIViewController, at node: UIViewController) { base.anchorPopover(of: presented, at: node) }
    func present(_ presented: UIViewController, on node: UIViewController, animated: Bool, completion: @escaping @MainActor () -> Void) {
        log.record()
        base.present(presented, on: node, animated: animated, completion: completion)
    }
    func isPresentationAccepted(_ presented: UIViewController) -> Bool { base.isPresentationAccepted(presented) }
}

/// UT-12: `ShareSheetPresenter` on the host app. Every end closes the request's box once and
/// resumes the call once (the handler, a failure of the procedure, the release watch).
@MainActor
struct ShareSheetPresenterTests {

    nonisolated private static let copy = UIActivity.ActivityType.copyToPasteboard

    /// Starts a share and records its result (or the error it threw).
    private func start(_ presenter: some ShareSheetPresenting, _ selection: PresenterSelection = .foreground,
                       excluded: [UIActivity.ActivityType] = [],
                       into results: MainRecorder<Result<ShareResult, ShareError>>) -> Task<Void, Never> {
        Task { @MainActor in
            do {
                let result = try await presenter.present(items: ["hello"], excluded: excluded, presenter: selection)
                results.record(.success(result))
            } catch let error as ShareError {
                results.record(.failure(error))
            } catch {
                Issue.record("not a ShareError: \(error)")
            }
        }
    }

    /// Waits until `recorder`'s latest sheet is presented and its presentation has finished.
    private func waitShown(_ recorder: SheetRecorder, count: Int = 1) async throws -> UIActivityViewController {
        #expect(await waitUntil {
            guard recorder.count == count, let sheet = recorder.last else { return false }
            return sheet.presentingViewController != nil && !sheet.isBeingPresented && sheet.transitionCoordinator == nil
        }, "the share sheet is presented")
        return try #require(recorder.last)
    }

    // MARK: - The handler

    @Test func theHandlerEndsTheShareWithItsResult() async throws {
        try await withHostWindow { host in
            let sheets = SheetRecorder()
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            _ = start(ShareSheetPresenter.recording(into: sheets), into: results)
            let sheet = try await waitShown(sheets)
            #expect(sheet.presentingViewController === host.root)

            sheet.completionWithItemsHandler?(Self.copy, true, nil, nil)
            #expect(await waitUntil { results.values.count == 1 })
            guard case .success(let result)? = results.values.first else {
                Issue.record("expected a result: \(results.values)")
                return
            }
            #expect(result.completed)
            #expect(result.activityType == Self.copy.rawValue)
            #expect(results.allOnMainThread)
        }
    }

    @Test func aClosedSheetEndsAsNotCompleted() async throws {
        try await withHostWindow { _ in
            let sheets = SheetRecorder()
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            _ = start(ShareSheetPresenter.recording(into: sheets), into: results)
            let sheet = try await waitShown(sheets)
            sheet.completionWithItemsHandler?(nil, false, nil, nil)
            #expect(await waitUntil { results.values.count == 1 })
            guard case .success(let result)? = results.values.first else {
                Issue.record("expected a result: \(results.values)")
                return
            }
            #expect(!result.completed)
            #expect(result.activityType == nil)
        }
    }

    @Test func anActivityErrorEndsTheShareAsActivityFailed() async throws {
        try await withHostWindow { _ in
            let sheets = SheetRecorder()
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            _ = start(ShareSheetPresenter.recording(into: sheets), into: results)
            let sheet = try await waitShown(sheets)
            let error = NSError(domain: "TestShareDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: "not kept"])
            sheet.completionWithItemsHandler?(Self.copy, false, nil, error)
            #expect(await waitUntil { results.values.count == 1 })
            #expect(results.names == [failed(.activityFailed(FailureDetail(domain: "TestShareDomain", code: 7)))])
        }
    }

    /// Only the first end counts: the handler twice, then the sheet dismissed and freed.
    @Test func onlyTheFirstEndCounts() async throws {
        try await withHostWindow { host in
            let sheets = SheetRecorder()
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            _ = start(ShareSheetPresenter.recording(into: sheets), into: results)
            weak let sheet = try await waitShown(sheets)
            sheet?.completionWithItemsHandler?(Self.copy, true, nil, nil)
            sheet?.completionWithItemsHandler?(nil, false, nil, NSError(domain: "Second", code: 2))
            host.root.dismiss(animated: false)
            #expect(await waitUntil { sheet == nil }, "the dismissed sheet is freed")
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(results.values.count == 1)
            guard case .success(let result)? = results.values.first else {
                Issue.record("expected the first result: \(results.values)")
                return
            }
            #expect(result.completed)
        }
    }

    /// The handler closes the box on the thread UIKit calls it on, before it returns: the sheet
    /// can be freed right after the handler without the release watch taking the end.
    @Test func theHandlerClosesTheBoxOnItsOwnThreadAtOnce() async {
        let box = RequestBox()
        let closedInCall = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async {
                let handler = ShareSheetPresenter<UIKitPresentationEnvironment>.completionHandler(closing: box)
                handler(Self.copy, true, nil, nil)
                continuation.resume(returning: box.isClosed)
            }
        }
        #expect(closedInCall)
        guard case .completed(let value)? = box.outcome, let result = value as? Result<ShareResult, ShareError>,
              case .success(let share) = result else {
            Issue.record("the box holds the result: \(String(describing: box.outcome))")
            return
        }
        #expect(share.completed)
        #expect(share.activityType == Self.copy.rawValue)
    }

    // MARK: - The release watch

    /// A sheet dismissed from outside calls no handler (hand-off 1): the release watch ends it.
    @Test func aSheetDismissedFromOutsideEndsAsDismissedBySystem() async throws {
        try await withHostWindow { host in
            let sheets = SheetRecorder()
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            _ = start(ShareSheetPresenter.recording(into: sheets), into: results)
            _ = try await waitShown(sheets)
            host.root.dismiss(animated: true)
            #expect(await waitUntil(timeout: 10) { results.values.count == 1 }, "the release watch ends the share")
            #expect(results.names == [failed(.dismissedBySystem)])
            #expect(results.allOnMainThread)
        }
    }

    // MARK: - The presentation procedure

    @Test func withoutAViewControllerEachSelectionReportsItsError() async {
        await withHostScreen {
            for (selection, expected) in [(PresenterSelection.firstActiveScene, ShareError.noRootViewController),
                                          (.foreground, .notForeground),
                                          (.viewController { nil }, .notForeground)] {
                let sheets = SheetRecorder()
                let results = MainRecorder<Result<ShareResult, ShareError>>()
                _ = start(ShareSheetPresenter.recording(into: sheets), selection, into: results)
                #expect(await waitUntil { results.values.count == 1 })
                #expect(results.names == [failed(expected)], "\(selection.logName)")
                #expect(sheets.last?.presentingViewController == nil)
            }
        }
    }

    /// A presentation the (fake) UIKit declines, calling no completion: the sheet is freed at once
    /// and the release watch ends the share as `presentationFailed`. The share relies on the watch
    /// alone (`releaseWatchOnly`): UIKit sets `presentingViewController` of a share sheet only
    /// after `present` returns (MS-03).
    @Test func aDeclinedPresentationEndsAsPresentationFailed() async throws {
        let top = UIViewController()
        let results = MainRecorder<Result<ShareResult, ShareError>>()
        let presenter = ShareSheetPresenter(makeEnvironment: { DecliningPresentationEnvironment(top: top) })
        _ = start(presenter, into: results)
        #expect(await waitUntil { results.values.count == 1 })
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(results.names == [failed(.presentationFailed)])
    }

    /// The same with the real UIKit: presenting on a view controller that already presents
    /// another one is declined (UIKit calls no completion and lets the sheet go, MS-03).
    @Test func aPresentationUIKitDeclinesEndsAsPresentationFailed() async throws {
        try await withHostWindow { host in
            let other = UIViewController()
            host.root.present(other, animated: false)
            #expect(await waitUntil { other.presentingViewController != nil && !other.isBeingPresented })
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            let presenter = ShareSheetPresenter(makeEnvironment: { AlwaysSettledEnvironment() })
            _ = start(presenter, .viewController { host.root }, into: results)
            #expect(await waitUntil { results.values.count == 1 })
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(results.names == [failed(.presentationFailed)])
            #expect(host.root.presentedViewController === other, "nothing else was presented")
        }
    }

    /// A presented sheet, whose `presentingViewController` is set only some time after `present`,
    /// is not taken for a declined one (the supplement of 6.3.3 is not used for the share sheet).
    @Test func aPresentedSheetIsNotFailed() async throws {
        try await withHostWindow { _ in
            let sheets = SheetRecorder()
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            _ = start(ShareSheetPresenter.recording(into: sheets), into: results)
            let sheet = try await waitShown(sheets)
            #expect(results.values.isEmpty, "no result before the sheet ends: \(results.names)")
            sheet.completionWithItemsHandler?(nil, false, nil, nil)
            #expect(await waitUntil { results.values.count == 1 })
        }
    }

    /// `.firstActiveScene` keeps the check from before 1b: a view controller that is not stable
    /// fails the share without presenting (`requireLegacyStability`); `.foreground` does not use
    /// that check.
    @Test func firstActiveSceneKeepsTheLegacyStabilityCheck() async throws {
        try await withHostWindow { host in
            let log = PresentationLog()
            let sheets = SheetRecorder()
            let presenter = ShareSheetPresenter(makeEnvironment: { UnstableForLegacyEnvironment(log: log) },
                                                observeSheet: { sheets.record($0) })
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            _ = start(presenter, .firstActiveScene, into: results)
            #expect(await waitUntil { results.values.count == 1 })
            #expect(results.names == [failed(.presentationFailed)])
            #expect(log.count == 0, "nothing is presented")

            _ = start(presenter, .foreground, into: results)
            let sheet = try await waitShown(sheets, count: 2)
            #expect(log.count == 1)
            #expect(sheet.presentingViewController === host.root)
            sheet.completionWithItemsHandler?(nil, false, nil, nil)
            #expect(await waitUntil { results.values.count == 2 })
        }
    }

    @Test func theViewControllerSelectionPresentsFromTheReturnedViewController() async throws {
        try await withHostWindow { host in
            let other = UIViewController()
            host.root.present(other, animated: false)
            #expect(await waitUntil { other.presentingViewController != nil && !other.isBeingPresented })
            let sheets = SheetRecorder()
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            _ = start(ShareSheetPresenter.recording(into: sheets), .viewController { other }, into: results)
            let sheet = try await waitShown(sheets)
            #expect(sheet.presentingViewController === other)
            sheet.completionWithItemsHandler?(nil, false, nil, nil)
            #expect(await waitUntil { results.values.count == 1 })
        }
    }

    // MARK: - The sheet

    @Test func theExcludedActivityTypesReachTheSheet() async throws {
        try await withHostWindow { _ in
            let sheets = SheetRecorder()
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            let excluded: [UIActivity.ActivityType] = [.copyToPasteboard, .postToFacebook]
            _ = start(ShareSheetPresenter.recording(into: sheets), excluded: excluded, into: results)
            let sheet = try await waitShown(sheets)
            #expect(sheet.excludedActivityTypes == excluded)
            sheet.completionWithItemsHandler?(nil, false, nil, nil)
            #expect(await waitUntil { results.values.count == 1 })
        }
    }

    /// P1-13: the sheet's popover is anchored at the centre of the presenting view when `present`
    /// is called, with any arrow direction (as before 1b). The iPhone of iOS 26.2 then replaces
    /// the anchor with its own; an iPad keeps it.
    @Test func thePopoverIsAnchoredAtTheCentreOfThePresentingView() async throws {
        try await withHostWindow { host in
            let log = AnchorLog()
            let sheets = SheetRecorder()
            let presenter = ShareSheetPresenter(makeEnvironment: { AnchorRecordingEnvironment(log: log) },
                                                observeSheet: { sheets.record($0) })
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            _ = start(presenter, into: results)
            let sheet = try await waitShown(sheets)
            let centre = CGRect(x: host.root.view.bounds.midX, y: host.root.view.bounds.midY, width: 0, height: 0)
            #expect(log.anchors.count == 1)
            if let anchor = log.anchors.first ?? nil {
                // The iPhone of iOS 26.2 reads `sourceView` back as nil before the presentation
                // (the sheet is not shown as a popover there); an iPad reads the view.
                if UIDevice.current.userInterfaceIdiom == .pad {
                    #expect(anchor.sourceView === host.root.view)
                }
                #expect(anchor.sourceRect == centre)
                #expect(anchor.arrows == .any)
            } else {
                // Without a popover (the iPhone of iOS 18) there is nothing to anchor.
                #expect(UIDevice.current.userInterfaceIdiom == .phone)
            }
            if UIDevice.current.userInterfaceIdiom == .pad {
                #expect(sheet.popoverPresentationController?.sourceView === host.root.view)
                #expect(sheet.popoverPresentationController?.sourceRect == centre)
            }
            sheet.completionWithItemsHandler?(nil, false, nil, nil)
            #expect(await waitUntil { results.values.count == 1 })
        }
    }

    // MARK: - Task cancellation

    /// A share cannot be cancelled (P1-24): cancelling the calling task neither dismisses the
    /// sheet nor ends the call, and the result still comes. The same when the task is cancelled
    /// after the handler, before the result reached it.
    @Test func cancellingTheTaskDoesNotEndTheShare() async throws {
        try await withHostWindow { _ in
            let sheets = SheetRecorder()
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            let task = start(ShareSheetPresenter.recording(into: sheets), into: results)
            let sheet = try await waitShown(sheets)
            task.cancel()
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(results.values.isEmpty)
            #expect(sheet.presentingViewController != nil, "the sheet stays")

            sheet.completionWithItemsHandler?(Self.copy, true, nil, nil)
            #expect(await waitUntil { results.values.count == 1 })
            guard case .success(let result)? = results.values.first else {
                Issue.record("expected a result: \(results.values)")
                return
            }
            #expect(result.completed)

            // Cancelled right after the handler, in the same turn.
            dismissLast(sheets)
            #expect(await waitUntil { sheet.presentingViewController == nil })
            let second = start(ShareSheetPresenter.recording(into: sheets), into: results)
            let next = try await waitShown(sheets, count: 2)
            next.completionWithItemsHandler?(Self.copy, true, nil, nil)
            second.cancel()
            #expect(await waitUntil { results.values.count == 2 })
            guard case .success? = results.values.last else {
                Issue.record("expected a result after the late cancellation: \(results.values)")
                return
            }
        }
    }

    /// Dismisses the latest sheet so that the next one presents from the root again.
    private func dismissLast(_ sheets: SheetRecorder) {
        sheets.last?.presentingViewController?.dismiss(animated: false)
    }
}
