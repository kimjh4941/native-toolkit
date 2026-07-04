//
//  ShareSheetPresenter.swift
//  IosLibrary
//

import UIKit

/// Contract for presenting a configured `UIActivityViewController` and awaiting its result.
protocol ShareSheetPresenting {
    /// Presents the share sheet with the given activity items and exclusions.
    /// - Parameters:
    ///   - items: Activation items (see `ShareRepositoryImpl.buildActivityItems`).
    ///   - excluded: Activity types to exclude from the sheet.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError` if presentation preconditions fail or the system reports an error.
    func present(items: [Any], excluded: [UIActivity.ActivityType]) async throws -> ShareResult
}

/// A minimal error used when the share sheet cannot be presented because the
/// resolved root view controller is mid-transition or already presenting.
struct PresentationUnavailableError: Error, LocalizedError {
    var errorDescription: String? {
        "The root view controller is not in a stable state to present the share sheet."
    }
}

/// Presents `UIActivityViewController` and bridges its completion callback to `async/await`.
///
/// ## Root View Controller Resolution
/// Mirrors `IosDialogManager.getRootViewController()`: searches the first foreground active
/// `UIWindowScene`, then the key window, then walks the `presentedViewController` chain.
///
/// ## iPad Popover
/// Falls back to anchoring the popover at the center of the root view when no explicit
/// `sourceView` is supplied, avoiding a runtime crash on iPad.
///
/// ## Continuation Safety
/// The continuation is resumed exactly once, guarded on the main actor, only from
/// `completionWithItemsHandler` (never from the `present` completion handler).
final class ShareSheetPresenter: ShareSheetPresenting {

    private let TAG = "ShareSheetPresenter"

    @MainActor
    func present(items: [Any], excluded: [UIActivity.ActivityType]) async throws -> ShareResult {
        Log.d(TAG, "[present] items: \(items.count), excluded: \(excluded.count)")

        guard let root = getRootViewController() else {
            Log.e(TAG, "[present] no root view controller")
            throw ShareError.noRootViewController
        }
        guard !root.isBeingDismissed, !root.isBeingPresented, root.presentedViewController == nil else {
            Log.e(TAG, "[present] root view controller is not in a stable state")
            throw ShareError.presentationFailed(PresentationUnavailableError())
        }

        var hasResumed = false   // main actor 上でのみアクセス

        return try await withCheckedThrowingContinuation { continuation in
            // resume は main actor 上で 1 回だけ（guard も main isolation 内で実行）
            func resumeOnce(_ result: Result<ShareResult, Error>) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }

            let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
            activityViewController.excludedActivityTypes = excluded

            if let popover = activityViewController.popoverPresentationController {
                popover.sourceView = root.view
                popover.sourceRect = CGRect(x: root.view.bounds.midX,
                                            y: root.view.bounds.midY,
                                            width: 0, height: 0)
            }

            activityViewController.completionWithItemsHandler = { activityType, completed, _, error in
                if let error {
                    resumeOnce(.failure(ShareError.presentationFailed(error)))
                } else {
                    resumeOnce(.success(ShareResult(completed: completed,
                                                    activityType: activityType?.rawValue)))
                }
            }

            // 提示 completion では resume しない（completionWithItemsHandler のみで resume する）
            root.present(activityViewController, animated: true)
        }
    }

    /// Resolves the top-most presented `UIViewController` suitable for presenting the share sheet.
    private func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            Log.e(TAG, "[getRootViewController] failed to get window scene or key window")
            return nil
        }

        var rootViewController = window.rootViewController
        while let presentedViewController = rootViewController?.presentedViewController {
            rootViewController = presentedViewController
        }

        return rootViewController
    }
}
