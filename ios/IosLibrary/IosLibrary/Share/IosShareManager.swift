//
//  IosShareManager.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "IosShareManager")

/// # IosShareManager
///
/// Central entry point for presenting the system share sheet.
///
/// ## Overview
/// * Provides a singleton (`shared`) for global access.
/// * ``share(content:presenter:completion:)`` reports one `Result<ShareResult, ShareError>`, and
///   ``share(content:presenter:)`` returns the ``ShareResult`` or throws a ``ShareError``. Pass a
///   ``PresenterSelection`` to choose the view controller to present from.
/// * ``share(content:completion:)`` reports the tuple `(isSuccess, completed, activityType,
///   errorMessage)`, and always presents from ``PresenterSelection/firstActiveScene``.
/// * User cancellation is not an error: `completed == false` (with `isSuccess == true`).
///
/// ## How a share ends
/// | Result | `share(content:completion:)` | When |
/// |---|---|---|
/// | ``ShareResult`` | `(true, completed, activityType, nil)` | The user chose an activity (`completed == true`) or closed the sheet (`false`) |
/// | ``ShareError/noValidItems``, ``ShareError/invalidURL(_:)``, ``ShareError/imageLoadFailed(path:)``, ``ShareError/fileNotFound(path:)`` | `(false, false, nil, <description>)` | The content could not be shared; no sheet is shown |
/// | ``ShareError/noRootViewController`` | the same | ``PresenterSelection/firstActiveScene`` found no view controller to present from |
/// | ``ShareError/notForeground`` | (not used) | ``PresenterSelection/foreground`` or ``PresenterSelection/viewController(_:)`` found no view controller in the foreground |
/// | ``ShareError/presentationFailed`` | `(false, false, nil, "Failed to present the share sheet.")` | The view controller was not settled (``PresenterSelection/firstActiveScene``: being presented or dismissed, or presenting something; the others: still so after waiting once), UIKit declined the presentation, or the sheet was freed before its presentation finished (dismissed from outside during the animation) |
/// | ``ShareError/dismissedBySystem`` | `(false, false, nil, "The share sheet was dismissed without a result.")` | The sheet went away without reporting a result: dismissed from outside the library, or its scene was disconnected and the sheet freed |
/// | ``ShareError/activityFailed(_:)`` | `(false, false, nil, "The share activity failed.")` | The chosen activity reported an error |
///
/// The result is not guaranteed when the app changes the window, its root view controller or the
/// scene while the sheet is shown, or keeps the presented `UIActivityViewController` alive, nor
/// when the sheet's scene is disconnected but the sheet is not freed. A share cannot be
/// cancelled.
///
/// ## Threading
/// The manager is `Sendable` and may be called from any thread. Each completion is invoked on the
/// main thread exactly once, never inside the call, on every path (including validation
/// failures). Two shares requested one after the other are not guaranteed to be presented in that
/// order.
///
/// ## Example
/// ```swift
/// IosShareManager.shared.share(content: ShareContent(items: [.text("Hello")]), presenter: .foreground) { result in
///     switch result {
///     case .success(let share): print(share.completed, share.activityType ?? "")
///     case .failure(let error): print(error)
///     }
/// }
/// ```
public final class IosShareManager: NSObject, Sendable {

    /// Shared singleton instance.
    public static let shared = IosShareManager()

    private let repository: ShareRepository
    private let shareUseCase: ShareContentUseCase

    private override init() {
        logger.log(level: .libraryDebug, "[init]")
        let repo = ShareRepositoryImpl()
        self.repository = repo
        self.shareUseCase = ShareContentUseCase(repository: repo)
        super.init()
    }

    /// Internal initializer for tests to inject a repository.
    init(repository: ShareRepository) {
        logger.log(level: .libraryDebug, "[init:test] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
        self.shareUseCase = ShareContentUseCase(repository: repository)
        super.init()
    }

    /// Presents the share sheet for the given content, from the view controller
    /// ``PresenterSelection/firstActiveScene`` selects.
    ///
    /// - Note: `completion` is always invoked on the main thread (main actor), exactly once,
    ///   regardless of the calling thread. It is `@Sendable` because it is carried from the
    ///   calling thread to the main actor, and `@MainActor` to state in the type where it runs (the
    ///   same as the completions of `IosNotificationManager`).
    /// - Note: Swift callers should prefer ``share(content:presenter:)`` (`async throws`) or
    ///   ``share(content:presenter:completion:)`` for a typed ``ShareError``; the messages of this
    ///   method are the descriptions in the table of ``IosShareManager``.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - completion: `(isSuccess, completed, activityType, errorMessage)`.
    ///     * `isSuccess`: the sheet was presented and ended with a result (the user could
    ///       interact).
    ///     * `completed`: user finished an activity (`false` means cancelled).
    ///     * `activityType`: the selected activity's raw identifier, or `nil`.
    ///     * `errorMessage`: set only when `isSuccess == false`. When the sheet is dismissed from
    ///       outside the library (or freed with its scene) this is
    ///       `(false, false, nil, "The share sheet was dismissed without a result.")`.
    public func share(
        content: ShareContent,
        completion: (@MainActor @Sendable (Bool, Bool, String?, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "[share] \(content.logSummary, privacy: .public), completion: \(completion != nil ? "provided" : "nil", privacy: .public)")
        start(content: content, presenter: .firstActiveScene) { result in
            switch result {
            case .success(let share):
                completion?(true, share.completed, share.activityType, nil)
            case .failure(let error):
                completion?(false, false, nil, error.localizedDescription)
            }
        }
    }

    /// Presents the share sheet for the given content from the view controller `presenter`
    /// selects, and reports how it ended (the table of ``IosShareManager``).
    ///
    /// With ``PresenterSelection/foreground`` or ``PresenterSelection/viewController(_:)``, a share
    /// requested while a view controller is in a transition waits once for that transition, and
    /// fails with ``ShareError/presentationFailed`` when it is still not settled. With
    /// ``PresenterSelection/firstActiveScene`` nothing waits.
    ///
    /// `presenter` has no default, so that a call without it stays
    /// ``share(content:completion:)``.
    ///
    /// - Parameters:
    ///   - content: The content to share.
    ///   - presenter: How to choose the view controller to present from.
    ///   - completion: The result, on the main thread, exactly once, never inside this call.
    public func share(
        content: ShareContent,
        presenter: PresenterSelection,
        completion: @escaping @MainActor @Sendable (Result<ShareResult, ShareError>) -> Void
    ) {
        logger.log(level: .libraryDebug, "[share] \(content.logSummary, privacy: .public), presenter: \(presenter.logName, privacy: .public), completion: provided")
        start(content: content, presenter: presenter, completion: completion)
    }

    /// Presents the share sheet for the given content from the view controller `presenter`
    /// selects, and returns the result.
    ///
    /// The same as ``share(content:presenter:completion:)``. Cancelling the task does not end the
    /// share: the call returns when the sheet ends.
    ///
    /// - Note: Preferred entry point for native Swift callers (e.g. SwiftUI views). Surfaces
    ///   typed `ShareError` on failure instead of a string message.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - presenter: How to choose the view controller to present from. The default is the
    ///     search this method always used (no waiting).
    /// - Returns: The interaction result. `result.completed == false` means the user cancelled
    ///   (not an error).
    /// - Throws: `ShareError` (the table of ``IosShareManager``). The share manager's own
    ///   repository throws nothing else.
    @discardableResult
    public func share(content: ShareContent, presenter: PresenterSelection = .firstActiveScene) async throws -> ShareResult {
        logger.log(level: .libraryDebug, "[share async] \(content.logSummary, privacy: .public), presenter: \(presenter.logName, privacy: .public)")
        do {
            return try await shareUseCase.execute(content: content, presenter: presenter)
        } catch {
            logger.error("[share async] error: \(LogRedaction.describe(error), privacy: .public)")
            throw error
        }
    }

    /// Runs the use case and reports its result on the main thread, once, after the call.
    private func start(content: ShareContent, presenter: PresenterSelection,
                       completion: @escaping @MainActor @Sendable (Result<ShareResult, ShareError>) -> Void) {
        logger.log(level: .libraryDebug, "[start] \(content.logSummary, privacy: .public), presenter: \(presenter.logName, privacy: .public)")
        Task { @MainActor in
            let result: Result<ShareResult, ShareError>
            do {
                result = .success(try await shareUseCase.execute(content: content, presenter: presenter))
            } catch {
                logger.error("[share] error: \(LogRedaction.describe(error), privacy: .public)")
                result = .failure(Self.shareError(error))
            }
            completion(result)
        }
    }

    /// The error as a ``ShareError``. The library's repository throws only `ShareError`; another
    /// error (only the unit tests' repositories can throw one) becomes
    /// ``ShareError/presentationFailed``.
    private static func shareError(_ error: any Error) -> ShareError {
        logger.log(level: .libraryDebug, "[shareError] error: \(LogRedaction.describe(error), privacy: .public)")
        if let shareError = error as? ShareError {
            return shareError
        }
        logger.error("[shareError] not a ShareError: \(LogRedaction.describe(error), privacy: .public)")
        return .presentationFailed
    }
}
