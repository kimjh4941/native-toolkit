//
//  ShareSheetPresenter.swift
//  IosLibrary
//

import os
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ShareSheetPresenter")

/// Contract for presenting a configured `UIActivityViewController` and awaiting its result.
///
/// The requirement is `@MainActor` because presenting is UIKit work. The activity items are not
/// `Sendable` (`[Any]`), so the caller hands over a fresh array it no longer uses and the compiler
/// checks that transfer (region-based isolation) instead of an unchecked assertion.
protocol ShareSheetPresenting: Sendable {
    /// Presents the share sheet with the given activity items and exclusions.
    /// - Parameters:
    ///   - items: Activation items (see `ShareRepositoryImpl.buildActivityItems`).
    ///   - excluded: Activity types to exclude from the sheet.
    ///   - presenter: How to choose the view controller to present from.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError` if presentation preconditions fail, the system reports an error, or
    ///   the sheet goes away without a result.
    @MainActor
    func present(items: [Any], excluded: [UIActivity.ActivityType], presenter: PresenterSelection) async throws -> ShareResult
}

/// Presents `UIActivityViewController` through ``PresentationProcedure`` and bridges its end to
/// `async/await`.
///
/// ## One request, one box
/// Every call makes its own sheet and its own ``RequestBox``. The first of these closes the box,
/// and the call returns what it closed with:
///
/// | Closed by | Result |
/// |---|---|
/// | `completionWithItemsHandler` without an error | The ``ShareResult`` (`completed`, `activityType`) |
/// | `completionWithItemsHandler` with an error | ``ShareError/activityFailed(_:)`` |
/// | The procedure: no view controller | ``ShareError/noRootViewController`` (`.firstActiveScene`) or ``ShareError/notForeground`` |
/// | The procedure: not settled, or UIKit declined the presentation | ``ShareError/presentationFailed`` |
/// | The release watch: the sheet was freed without the handler | ``ShareError/dismissedBySystem`` (after `present`'s completion) or ``ShareError/presentationFailed`` |
///
/// `.firstActiveScene` keeps the checks the share sheet made before 1b
/// (`FirstActiveScenePolicy.requireLegacyStability`): it fails when the found view controller is
/// being presented or dismissed or is presenting something, and never waits.
///
/// ## Continuation Safety
/// The continuation is resumed exactly once, on the main actor, by the box's close handler (which
/// runs once). The handler closes the box on whatever thread UIKit calls it, before anything else
/// can free the sheet, and captures only the box: the sheet, its release watch and the box do not
/// keep one another alive. Cancelling the calling task does not end the share (a share cannot be
/// cancelled, P1-24): the call returns when the sheet ends.
///
/// ## iPad Popover
/// The procedure anchors the popover at the center of the presenting view (P1-13), with the arrow
/// directions left as they are (`.any`).
struct ShareSheetPresenter<Environment: PresentationEnvironment>: ShareSheetPresenting where Environment.Node == UIViewController {
    private let makeEnvironment: @MainActor @Sendable () -> Environment
    /// Sees each sheet once it is built, before it is presented (unit tests only).
    private let observeSheet: (@MainActor @Sendable (UIActivityViewController) -> Void)?

    init(makeEnvironment: @escaping @MainActor @Sendable () -> Environment,
         observeSheet: (@MainActor @Sendable (UIActivityViewController) -> Void)? = nil) {
        logger.log(level: .libraryDebug, "[init] observeSheet: \(observeSheet != nil ? "provided" : "nil", privacy: .public)")
        self.makeEnvironment = makeEnvironment
        self.observeSheet = observeSheet
    }

    @MainActor
    func present(items: [Any], excluded: [UIActivity.ActivityType], presenter: PresenterSelection) async throws -> ShareResult {
        logger.log(level: .libraryDebug, "[present] items: \(items.count, privacy: .public), excluded: \(excluded.count, privacy: .public), presenter: \(presenter.logName, privacy: .public)")
        let box = RequestBox()
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<ShareResult, ShareError>, Never>) in
            // The close handler runs once, on the main thread, never inside `attach`: the only
            // place that resumes the continuation.
            let attached = box.attach { outcome in
                let result = Self.result(of: outcome, presenter: presenter)
                logger.log(level: .libraryDebug, "[present] closed: \(outcome.logName, privacy: .public), result: \(Self.logName(of: result), privacy: .public)")
                continuation.resume(returning: result)
            }
            guard attached else {
                // A new box is never attached elsewhere.
                logger.fault("[present] a new box was already attached")
                continuation.resume(returning: .failure(.presentationFailed))
                return
            }
            let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
            sheet.excludedActivityTypes = excluded
            sheet.completionWithItemsHandler = Self.completionHandler(closing: box)
            observeSheet?(sheet)
            // UIKit sets the sheet's `presentingViewController` only after `present` returns
            // (MS-03, C3): a declined share sheet is noticed by the release watch alone.
            PresentationProcedure.present(sheet, presenter: presenter, box: box, firstActiveScenePolicy: .requireLegacyStability,
                                          environment: makeEnvironment(), declineCheck: .releaseWatchOnly)
        }
        return try result.get()
    }

    /// The sheet's `completionWithItemsHandler`. Built outside the main actor so that UIKit may
    /// call it on any thread; it closes the box there at once (the box can be closed from any
    /// thread), so the sheet cannot be freed first and be taken for a sheet dismissed from outside.
    nonisolated static func completionHandler(closing box: RequestBox) -> UIActivityViewController.CompletionWithItemsHandler {
        logger.log(level: .libraryDebug, "[completionHandler] box closed: \(box.isClosed, privacy: .public)")
        return { activityType, completed, returnedItems, error in
            logger.log(level: .libraryDebug, "[completionWithItemsHandler] activityType: \(activityType?.rawValue ?? "nil", privacy: .private), completed: \(completed, privacy: .public), returnedItems: \(returnedItems?.count ?? 0, privacy: .public), error: \(error.map { LogRedaction.describe($0) } ?? "nil", privacy: .public), isMainThread: \(Thread.isMainThread, privacy: .public)")
            let result: Result<ShareResult, ShareError>
            if let error {
                result = .failure(.activityFailed(FailureDetail(systemError: error)))
            } else {
                result = .success(ShareResult(completed: completed, activityType: activityType?.rawValue))
            }
            box.close(.completed(result))
        }
    }

    /// The box's outcome as the result of the share.
    static func result(of outcome: RequestBoxOutcome, presenter: PresenterSelection) -> Result<ShareResult, ShareError> {
        logger.log(level: .libraryDebug, "[result] outcome: \(outcome.logName, privacy: .public), presenter: \(presenter.logName, privacy: .public)")
        switch outcome {
        case .completed(let value):
            guard let result = value as? Result<ShareResult, ShareError> else {
                logger.fault("[result] the box was completed with another type")
                return .failure(.presentationFailed)
            }
            return result
        case .notForeground:
            // `.firstActiveScene` keeps the error of the search it has always used.
            if case .firstActiveScene = presenter.kind {
                return .failure(.noRootViewController)
            }
            return .failure(.notForeground)
        case .presentationFailed:
            return .failure(.presentationFailed)
        case .dismissedBySystem:
            return .failure(.dismissedBySystem)
        case .canceled:
            // A share cannot be cancelled: nothing closes its box this way.
            logger.fault("[result] a share box was cancelled")
            return .failure(.presentationFailed)
        }
    }

    private static func logName(of result: Result<ShareResult, ShareError>) -> String {
        switch result {
        case .success(let value): return "success(completed: \(value.completed))"
        case .failure(let error): return LogRedaction.describe(error)
        }
    }
}

extension ShareSheetPresenter where Environment == UIKitPresentationEnvironment {
    /// The presenter over UIKit.
    init() {
        self.init(makeEnvironment: { UIKitPresentationEnvironment() })
    }
}
