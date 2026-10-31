//
//  IosDialogManager.swift
//
//
//  Created by Kim Jong Hyun on 2025/04/12.
//
import os
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "IosDialogManager")

/// # IosDialogManager
///
/// Central utility for presenting `UIAlertController` based dialogs (alerts, action sheets,
/// text input, login style) in a thread‑safe, convenience oriented way.
///
/// ## Overview
/// * Provides a singleton (`shared`) for simple global access.
/// * ``show(_:presenter:requestBox:completion:)`` (and its `async` form) shows one
///   ``DialogRequest`` and reports one `Result<DialogAnswer, DialogError>`. Pass a
///   ``RequestBox`` to cancel the request later with ``cancel(_:)``, and a ``PresenterSelection``
///   to choose the view controller to present from.
/// * The `show...` methods (alert / confirm / destructive / action sheet / text & login input, and
///   ``showDialog(title:message:preferredStyle:actions:textFields:sourceView:sourceRect:barButtonItem:permittedArrowDirections:animated:completion:)``
///   with your own actions) report through button callbacks and a presentation `completion`:
///   * A button callback is called only when its button is pressed, with the button's title
///     (and, for text and login input, what was entered), `isSuccess == true` and
///     `errorMessage == nil`.
///   * `completion` reports the presentation: `(true, nil)` once presented, or `isSuccess == false`
///     with a human readable `errorMessage` when the dialog could not be presented (see
///     "Results of the `show...` methods" below).
///
/// Both kinds use the same presentation: each request presents its own `UIAlertController`
/// from the view controller its ``PresenterSelection`` chooses (the `show...` methods always use
/// ``PresenterSelection/firstActiveScene``).
///
/// ## Threading
/// The manager is `Sendable`, and ``show(_:presenter:requestBox:completion:)``, ``cancel(_:)`` and
/// the `show...` methods may be called from any thread: all UIKit work, including creating the
/// `UIAlertAction`s of the convenience methods, runs on the main thread (main actor) after the
/// call returns. ``getRootViewController()`` and ``foregroundViewController()`` read UIKit state,
/// so they are `@MainActor` and must be called on the main actor.
///
/// Every `completion` and every button callback (`onButton`, `onConfirm`, `onCancel`,
/// `onDestructive`, `onAction`, `onLogin`) is invoked on the main thread, asynchronously (also
/// when the method is called on the main thread), and at most once per call. Their types are
/// `@MainActor @Sendable`: `@Sendable` because the closure is carried from the calling thread to
/// the main actor, and `@MainActor` to state in the type where it runs, so that a closure written
/// on the main actor (for example in a SwiftUI view) can use main-actor state directly. The
/// `textFields` configuration closures of ``showDialog(title:message:preferredStyle:actions:textFields:sourceView:sourceRect:barButtonItem:permittedArrowDirections:animated:completion:)``
/// have the same type for the same reason.
///
/// ## Results of the `show...` methods
/// `completion` reports the presentation, once:
/// * `(true, nil)` once UIKit has presented the dialog.
/// * `(false, "Failed to get root view controller")` when no view controller to present on is
///   found.
/// * `(false, "Failed to present the dialog")` when UIKit declines the presentation (for example
///   because the found view controller is already presenting another one).
///
/// A failure is reported only through `completion`, for every method: the button callbacks
/// (including `onLogin` of
/// ``showLoginDialog(title:message:usernamePlaceholder:passwordPlaceholder:loginTitle:cancelTitle:enableLoginWhenEmpty:onLogin:onCancel:completion:)``)
/// are called only when a button is pressed. When the dialog goes away without a button being
/// pressed (dismissed from outside, or its scene was disconnected), nothing is called: these
/// methods have no result for it. Use ``show(_:presenter:requestBox:completion:)`` to be told
/// (``DialogError/dismissedBySystem``).
///
/// ## Popover / iPad Support
/// For action sheets or alerts with style `.actionSheet`, popover anchors (`sourceView` / `sourceRect` / `barButtonItem`) are applied when available — falling back to centering inside the view of the view controller presented from if none supplied. ``show(_:presenter:requestBox:completion:)`` always uses that centre.
///
/// ## Root View Controller Resolution
/// The `show...` methods search the first foreground active `UIWindowScene`, then find the key window and walk the `presentedViewController` chain (``getRootViewController()``).
/// If this process fails, the completion handler is invoked with `isSuccess = false`.
///
/// ## Input Validation Helpers
/// `showTextInputDialog` & `showLoginDialog` optionally disable the primary action button until required fields are filled (via `enableConfirmWhenEmpty` / `enableLoginWhenEmpty`).
///
/// ## Memory
/// The library holds a presented dialog weakly, and its button handlers and text-field observers
/// do not hold it; the observers are removed when the request ends. Callbacks are not retained
/// after the request ends. Avoid capturing large objects strongly in closures.
///
/// ## Example
/// ```swift
/// IosDialogManager.shared.show(.confirm(title: "Delete?", message: nil)) { result in
///     switch result {
///     case .success(let answer) where answer.button == .primary: print("confirmed")
///     case .success: print("cancelled by the user")
///     case .failure(let error): print(error)
///     }
/// }
///
/// IosDialogManager.shared.showAlert(title: "Notice", message: "Operation finished") { result, success, error in
///     guard success else { print(error ?? "Unknown"); return }
///     print("User tapped: \(result ?? "?")")
/// }
/// ```
public final class IosDialogManager: NSObject, Sendable {

    /// Shared singleton instance.
    public static let shared = IosDialogManager()

    /// The `completion` message of the `show...` methods when no view controller is found.
    static let noRootViewControllerMessage = "Failed to get root view controller"
    /// The `completion` message of the `show...` methods when UIKit declines the presentation.
    static let presentationFailedMessage = "Failed to present the dialog"

    private let core: any DialogPresentationCore
    private let showUseCase: ShowDialogUseCase

    private override init() {
        logger.log(level: .libraryDebug, "init")
        let core = AlertDialogPresenter(makeEnvironment: { UIKitPresentationEnvironment() })
        self.core = core
        self.showUseCase = ShowDialogUseCase(presenter: core)
        super.init()
    }

    /// A manager over another presentation core (unit tests).
    init(core: any DialogPresentationCore) {
        logger.log(level: .libraryDebug, "init(core:) core: \(String(describing: type(of: core)), privacy: .public)")
        self.core = core
        self.showUseCase = ShowDialogUseCase(presenter: core)
        super.init()
    }

    // MARK: - One request, one result

    /// Shows `request` and reports how it ended.
    ///
    /// | Result | When |
    /// |---|---|
    /// | `.success(answer)` | A button was pressed (``DialogAnswer``) |
    /// | ``DialogError/canceled`` | ``cancel(_:)`` closed the request. The `async` form throws `CancellationError` instead |
    /// | ``DialogError/notForeground`` | `presenter` found no view controller to present from |
    /// | ``DialogError/presentationFailed`` | The view controller was still not settled after waiting once, or UIKit declined the presentation |
    /// | ``DialogError/dismissedBySystem`` | The dialog went away without a button being pressed (dismissed from outside, or its scene was disconnected and the dialog freed) |
    /// | ``DialogError/invalidRequest`` | `requestBox` is already used by another request. The returned box is that box, so passing it to ``cancel(_:)`` cancels the first request |
    ///
    /// With ``PresenterSelection/foreground`` or ``PresenterSelection/viewController(_:)``, a
    /// request made while another dialog is in a transition waits once for that transition. A
    /// dialog being presented stays, and the new one is presented over it; a dialog being
    /// dismissed goes away, and the new one is presented from the view controller below it. Two
    /// requests made one after the other are both shown. With the default
    /// ``PresenterSelection/firstActiveScene`` nothing waits: a request made while another dialog
    /// is being presented is likely to end with ``DialogError/presentationFailed`` (UIKit declines
    /// it).
    ///
    /// The result is not guaranteed when the app changes the window, its root view controller or
    /// the scene while the dialog is shown, or keeps the presented alert alive, nor when the
    /// dialog's scene is disconnected but the dialog is not freed: cancel the request then to be
    /// told.
    ///
    /// - Parameters:
    ///   - request: The dialog to show.
    ///   - presenter: How to choose the view controller to present from. The default is the
    ///     search of the `show...` methods (no waiting).
    ///   - requestBox: The box to cancel the request with, created by you before the call. When
    ///     `nil`, a new box is created.
    ///   - completion: The result, on the main thread, exactly once, never inside this call.
    /// - Returns: The request's box (`requestBox`, or the one created): pass it to ``cancel(_:)``.
    @discardableResult
    public func show(_ request: DialogRequest, presenter: PresenterSelection = .firstActiveScene, requestBox: RequestBox? = nil,
                     completion: @escaping @MainActor @Sendable (Result<DialogAnswer, DialogError>) -> Void) -> RequestBox {
        logger.log(level: .libraryDebug, "[show] request: \(request.kindName, privacy: .public), title: \(request.logTitle ?? "nil", privacy: .private), message: \(request.logMessage ?? "nil", privacy: .private), presenter: \(presenter.logName, privacy: .public), requestBox: \(requestBox != nil ? "provided" : "nil", privacy: .public), completion: provided")
        let box = requestBox ?? RequestBox()
        showUseCase.execute(request, presenter: presenter, box: box) { result in
            switch result {
            case .success(let answer):
                logger.log(level: .libraryDebug, "[show] answer: \(answer.button.logName, privacy: .public), input: \(answer.input?.description ?? "nil", privacy: .public)")
            case .failure(let error):
                logger.log(level: .libraryDebug, "[show] failure: \(LogRedaction.describe(error), privacy: .public)")
            }
            completion(result)
        }
        return box
    }

    /// Shows `request` and returns the answer.
    ///
    /// The same as ``show(_:presenter:requestBox:completion:)``, with a box of its own. When the
    /// task is cancelled, the request is cancelled as by ``cancel(_:)`` and this throws
    /// `CancellationError` (unless a button was pressed before). Every other failure throws a
    /// ``DialogError``.
    ///
    /// - Parameters:
    ///   - request: The dialog to show.
    ///   - presenter: How to choose the view controller to present from.
    /// - Returns: The answer.
    @discardableResult
    public func show(_ request: DialogRequest, presenter: PresenterSelection = .firstActiveScene) async throws -> DialogAnswer {
        logger.log(level: .libraryDebug, "[show async] request: \(request.kindName, privacy: .public), title: \(request.logTitle ?? "nil", privacy: .private), message: \(request.logMessage ?? "nil", privacy: .private), presenter: \(presenter.logName, privacy: .public)")
        let box = RequestBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DialogAnswer, any Error>) in
                self.show(request, presenter: presenter, requestBox: box) { result in
                    switch result {
                    case .success(let answer):
                        continuation.resume(returning: answer)
                    case .failure(.canceled):
                        // Only the task's cancellation cancels this box.
                        continuation.resume(throwing: CancellationError())
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            logger.log(level: .libraryDebug, "[show async] the task was cancelled")
            self.cancel(box)
        }
    }

    /// Cancels the request of `box`: its result is ``DialogError/canceled``, and its dialog is
    /// dismissed.
    ///
    /// The request ends at once (the result follows on the main thread); the dialog is dismissed
    /// on the main thread, after `present` has finished when it is still being presented. When
    /// another view controller is presented over the dialog, the dialog is not dismissed (that
    /// would dismiss the view controller over it too): it stays until that view controller goes
    /// away, and its buttons then do nothing.
    ///
    /// A request that has already ended is not changed. A box that no request uses yet is closed,
    /// so a request started with it later ends at once as cancelled without showing anything.
    ///
    /// Any thread; never waits.
    /// - Parameter box: The box of the request (from ``show(_:presenter:requestBox:completion:)``,
    ///   or the one you passed to it).
    public func cancel(_ box: RequestBox) {
        logger.log(level: .libraryDebug, "[cancel] box closed: \(box.isClosed, privacy: .public)")
        let closed = box.close(.canceled)
        logger.log(level: .libraryDebug, "[cancel] closed by this call: \(closed, privacy: .public)")
    }

    // MARK: - Finding the view controller

    /// Resolves the top-most presented `UIViewController` suitable for presenting a dialog.
    ///
    /// Takes the first foreground active scene → key window → presented chain (every presented
    /// view controller, also one being dismissed). Returns `nil` if no active scene or key window
    /// is found. This is the search of `PresenterSelection.firstActiveScene` and of the `show...`
    /// methods.
    ///
    /// On an iPad with two of the app's scenes side by side, both can be `foregroundActive` with a
    /// key window each; "first" is the order of `UIApplication.connectedScenes`, so the result may
    /// be in the scene the user is not looking at.
    ///
    /// ``foregroundViewController()`` differs in two ways: it also accepts a scene that is in the
    /// foreground but not active (`foregroundInactive`: right after launch, or while Control
    /// Center is pulled over the app), and it stops below a view controller that is being
    /// dismissed.
    /// - Returns: The top view controller or `nil`.
    /// - Note: It reads UIKit state, so it is `@MainActor`: call it on the main actor.
    @MainActor
    public func getRootViewController() -> UIViewController? {
        logger.log(level: .libraryDebug, "[getRootViewController]")
        return ForegroundLocator.firstActiveScene()
    }

    /// The view controller in the foreground: the one ``PresenterSelection/foreground`` presents
    /// from.
    ///
    /// The key window of a window scene that is `foregroundActive` or `foregroundInactive`, then
    /// its presented view controllers from the root, stopping below one that is being dismissed.
    /// When more than one scene qualifies, an active one is preferred (on an iPad with two of the
    /// app's scenes side by side, both can be active: see ``PresenterSelection/foreground``).
    /// `nil` when the app has no such scene or key window.
    ///
    /// Unlike ``getRootViewController()``, it accepts a scene that is visible but not active
    /// (right after launch, or while Control Center or Notification Center is pulled over the
    /// app), and it does not return a view controller that is going away.
    /// - Returns: The view controller, or `nil` when the app is not in the foreground.
    @MainActor
    public func foregroundViewController() -> UIViewController? {
        logger.log(level: .libraryDebug, "[foregroundViewController]")
        return ForegroundLocator.foreground()
    }

    // MARK: - The show... methods

    /// Presents a generic alert / action sheet with optional text fields and custom actions.
    ///
    /// - Parameters:
    ///   - title: Dialog title (optional).
    ///   - message: Dialog message (optional).
    ///   - preferredStyle: `.alert` or `.actionSheet`.
    ///   - actions: Custom `UIAlertAction`s. If empty, a default OK action is added.
    ///   - textFields: Array of configuration closures (applied only when `preferredStyle == .alert`).
    ///   - sourceView: Anchor view for iPad popover (action sheets / alerts in sheet style).
    ///   - sourceRect: Specific rect within `sourceView` (defaults to its bounds if nil).
    ///   - barButtonItem: Alternative popover anchor (used when `sourceView` is nil).
    ///   - permittedArrowDirections: Popover arrow directions (iPad).
    ///   - animated: Whether the presentation is animated.
    ///   - completion: `(isSuccess, errorMessage)`.
    ///     * `isSuccess=false` indicates that the dialog was not presented (no root VC, or UIKit
    ///       declined it).
    ///     * `errorMessage` provides human readable diagnostic when `isSuccess == false`.
    ///
    /// - Note: Custom `UIAlertAction` handlers run independently of `completion`. Use either approach—do not rely on `completion` to know which custom action was chosen.
    /// - Note: Without `sourceView` and `barButtonItem`, an action sheet's popover is anchored at the centre of the presenting view.
    public func showDialog(
        title: String? = nil,
        message: String? = nil,
        preferredStyle: UIAlertController.Style = .alert,
        actions: [UIAlertAction] = [],
        textFields: [@MainActor @Sendable (UITextField) -> Void]? = nil,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        barButtonItem: UIBarButtonItem? = nil,
        permittedArrowDirections: UIPopoverArrowDirection = .any,
        animated: Bool = true,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "showDialog called with title: \(title ?? "nil", privacy: .private), message: \(message ?? "nil", privacy: .private), preferredStyle: \(String(describing: preferredStyle), privacy: .public), actions count: \(actions.count, privacy: .public), textFields count: \(textFields?.count ?? 0, privacy: .public), sourceView: \(sourceView?.description ?? "nil", privacy: .private), sourceRect: \(sourceRect != nil ? NSCoder.string(for: sourceRect!) : "nil", privacy: .private), barButtonItem: \(barButtonItem?.description ?? "nil", privacy: .private), permittedArrowDirections: \(String(describing: permittedArrowDirections), privacy: .public), animated: \(animated, privacy: .public), completion: \(completion != nil ? "provided" : "nil", privacy: .public)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let spec = AlertSpec(
                    title: title, message: message, style: preferredStyle,
                    buttons: .custom(actions), fields: .custom(textFields ?? []),
                    anchor: AlertSpec.Anchor(sourceView: sourceView, sourceRect: sourceRect, barButtonItem: barButtonItem,
                                             permittedArrowDirections: permittedArrowDirections),
                    animated: animated
                )
                self.presentLegacy("showDialog", spec, completion: completion) { _ in }
            }
        }
    }

    /// Shows a simple single button alert (OK style).
    /// - Parameters:
    ///   - title: Alert title.
    ///   - message: Alert message.
    ///   - buttonText: Button label (default "OK").
    ///   - onButton: Called when the button is tapped with `(buttonText, true, nil)`.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`; a failure is
    ///     reported only here.
    public func showAlert(
        title: String? = nil,
        message: String? = nil,
        buttonText: String? = "OK",
        onButton: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "showAlert called with title: \(title ?? "nil", privacy: .private), message: \(message ?? "nil", privacy: .private), buttonText: \(buttonText ?? "nil", privacy: .private), onButton: \(onButton != nil ? "provided" : "nil", privacy: .public), completion: \(completion != nil ? "provided" : "nil", privacy: .public)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let spec = AlertSpec(title: title, message: message, style: .alert,
                                     buttons: .library([.init(title: buttonText, style: .default, role: .primary)]),
                                     fields: .library([]))
                self.presentLegacy("showAlert", spec, completion: completion) { _ in
                    onButton?(buttonText, true, nil)
                }
            }
        }
    }

    /// Shows a confirm / cancel dialog.
    /// - Parameters:
    ///   - title: Dialog title.
    ///   - message: Dialog message.
    ///   - confirmTitle: Confirm button title (default "OK").
    ///   - cancelTitle: Cancel button title (default "Cancel").
    ///   - onConfirm: Called when confirm is tapped with `(confirmTitle, true, nil)`.
    ///   - onCancel: Called when cancel is tapped with `(cancelTitle, true, nil)`.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`; a failure is
    ///     reported only here.
    public func showConfirmDialog(
        title: String? = nil,
        message: String? = nil,
        confirmTitle: String? = "OK",
        cancelTitle: String? = "Cancel",
        onConfirm: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        onCancel: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "showConfirmDialog called with title: \(title ?? "nil", privacy: .private), message: \(message ?? "nil", privacy: .private), confirmTitle: \(confirmTitle ?? "nil", privacy: .private), cancelTitle: \(cancelTitle ?? "nil", privacy: .private), onConfirm: \(onConfirm != nil ? "provided" : "nil", privacy: .public), onCancel: \(onCancel != nil ? "provided" : "nil", privacy: .public), completion: \(completion != nil ? "provided" : "nil", privacy: .public)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let spec = AlertSpec(title: title, message: message, style: .alert,
                                     buttons: .library([.init(title: confirmTitle, style: .default, role: .primary),
                                                        .init(title: cancelTitle, style: .cancel, role: .cancel)]),
                                     fields: .library([]))
                self.presentLegacy("showConfirmDialog", spec, completion: completion) { answer in
                    if answer.button == .cancel {
                        onCancel?(cancelTitle, true, nil)
                    } else {
                        onConfirm?(confirmTitle, true, nil)
                    }
                }
            }
        }
    }

    /// Shows a destructive confirmation dialog (e.g., Delete action) plus cancel.
    /// - Parameters:
    ///   - title: Dialog title.
    ///   - message: Dialog message.
    ///   - destructiveTitle: Destructive button title (default "Delete").
    ///   - cancelTitle: Cancel button title.
    ///   - onDestructive: Callback for destructive tap: `(destructiveTitle, true, nil)`.
    ///   - onCancel: Callback for cancel tap: `(cancelTitle, true, nil)`.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`; a failure is
    ///     reported only here.
    /// - Note: Destructive button uses `.destructive` style (red on iOS).
    public func showDestructiveDialog(
        title: String? = nil,
        message: String? = nil,
        destructiveTitle: String? = "Delete",
        cancelTitle: String? = "Cancel",
        onDestructive: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        onCancel: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "showDestructiveDialog called with title: \(title ?? "nil", privacy: .private), message: \(message ?? "nil", privacy: .private), destructiveTitle: \(destructiveTitle ?? "nil", privacy: .private), cancelTitle: \(cancelTitle ?? "nil", privacy: .private), onDestructive: \(onDestructive != nil ? "provided" : "nil", privacy: .public), onCancel: \(onCancel != nil ? "provided" : "nil", privacy: .public), completion: \(completion != nil ? "provided" : "nil", privacy: .public)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let spec = AlertSpec(title: title, message: message, style: .alert,
                                     buttons: .library([.init(title: destructiveTitle, style: .destructive, role: .destructive),
                                                        .init(title: cancelTitle, style: .cancel, role: .cancel)]),
                                     fields: .library([]))
                self.presentLegacy("showDestructiveDialog", spec, completion: completion) { answer in
                    if answer.button == .cancel {
                        onCancel?(cancelTitle, true, nil)
                    } else {
                        onDestructive?(destructiveTitle, true, nil)
                    }
                }
            }
        }
    }

    /// Presents an action sheet with custom actions.
    /// - Parameters:
    ///   - title: Optional title.
    ///   - message: Optional message.
    ///   - options: Array of option titles.
    ///   - cancelTitle: Cancel button title (default "Cancel").
    ///   - sourceView: Mandatory for iPad to anchor the popover.
    ///   - sourceRect: Optional rect inside `sourceView`.
    ///   - animated: Animate presentation flag.
    ///   - onAction: `(selectedOption, true, nil)`; the cancel button gives `(cancelTitle, true, nil)`.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`; a failure is
    ///     reported only here.
    public func showActionSheet(
        title: String? = nil,
        message: String? = nil,
        options: [String],
        cancelTitle: String = "Cancel",
        sourceView: UIView,
        sourceRect: CGRect? = nil,
        animated: Bool = true,
        onAction: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "showActionSheet called with title: \(title ?? "nil", privacy: .private), message: \(message ?? "nil", privacy: .private), options: \(options, privacy: .private), cancelTitle: \(cancelTitle, privacy: .private), sourceView: \(sourceView.description, privacy: .private), sourceRect: \(sourceRect != nil ? NSCoder.string(for: sourceRect!) : "nil", privacy: .private), animated: \(animated, privacy: .public), onAction: \(onAction != nil ? "provided" : "nil", privacy: .public), completion: \(completion != nil ? "provided" : "nil", privacy: .public)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let optionButtons = options.enumerated().map {
                    AlertSpec.Button(title: $0.element, style: .default, role: .option(index: $0.offset))
                }
                let spec = AlertSpec(title: title, message: message, style: .actionSheet,
                                     buttons: .library(optionButtons + [.init(title: cancelTitle, style: .cancel, role: .cancel)]),
                                     fields: .library([]),
                                     anchor: AlertSpec.Anchor(sourceView: sourceView, sourceRect: sourceRect, barButtonItem: nil,
                                                              permittedArrowDirections: .any),
                                     animated: animated)
                self.presentLegacy("showActionSheet", spec, completion: completion) { answer in
                    if case .option(let index) = answer.button, options.indices.contains(index) {
                        logger.log(level: .libraryDebug, "Option selected: \(options[index], privacy: .private)")
                        onAction?(options[index], true, nil)
                    } else {
                        logger.log(level: .libraryDebug, "Cancel button pressed")
                        onAction?(cancelTitle, true, nil)
                    }
                }
            }
        }
    }

    /// Shows a single text input dialog with optional validation (disabling confirm while empty).
    /// - Parameters:
    ///   - title: Dialog title.
    ///   - message: Dialog message.
    ///   - placeholder: Placeholder text for the single text field.
    ///   - confirmTitle: Confirm button label.
    ///   - cancelTitle: Cancel button label.
    ///   - enableConfirmWhenEmpty: If `false`, confirm button disabled until user enters non‑empty text.
    ///   - onConfirm: `(buttonTitle, inputText, true, nil)`.
    ///   - onCancel: `(cancelTitle, true, nil)`.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`; a failure is
    ///     reported only here.
    /// - Note: Text change observation uses `UITextField.textDidChangeNotification`; it is only installed if validation is needed, and removed when the dialog closes.
    public func showTextInputDialog(
        title: String? = nil,
        message: String? = nil,
        placeholder: String? = nil,
        confirmTitle: String? = "OK",
        cancelTitle: String? = "Cancel",
        enableConfirmWhenEmpty: Bool = true,
        onConfirm: (@MainActor @Sendable (String?, String?, Bool, String?) -> Void)? = nil,
        onCancel: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "showTextInputDialog called with title: \(title ?? "nil", privacy: .private), message: \(message ?? "nil", privacy: .private), placeholder: \(placeholder ?? "nil", privacy: .private), confirmTitle: \(confirmTitle ?? "nil", privacy: .private), cancelTitle: \(cancelTitle ?? "nil", privacy: .private), enableConfirmWhenEmpty: \(enableConfirmWhenEmpty, privacy: .public), onConfirm: \(onConfirm != nil ? "provided" : "nil", privacy: .public), onCancel: \(onCancel != nil ? "provided" : "nil", privacy: .public), completion: \(completion != nil ? "provided" : "nil", privacy: .public)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let spec = AlertSpec(title: title, message: message, style: .alert,
                                     buttons: .library([.init(title: confirmTitle, style: .default, role: .primary),
                                                        .init(title: cancelTitle, style: .cancel, role: .cancel)]),
                                     fields: .library([.init(placeholder: placeholder, isSecure: false, contentType: nil)]),
                                     input: .text, requiresInput: !enableConfirmWhenEmpty)
                self.presentLegacy("showTextInputDialog", spec, completion: completion) { answer in
                    if answer.button == .cancel {
                        onCancel?(cancelTitle, true, nil)
                    } else {
                        var inputText: String?
                        if case .text(let text)? = answer.input {
                            inputText = text
                        }
                        onConfirm?(confirmTitle, inputText, true, nil)
                    }
                }
            }
        }
    }

    /// Shows a login style dialog with username & password fields and optional validation.
    /// - Parameters:
    ///   - title: Dialog title.
    ///   - message: Dialog message.
    ///   - usernamePlaceholder: Placeholder for username field.
    ///   - passwordPlaceholder: Placeholder for password field.
    ///   - loginTitle: Login (primary) button title.
    ///   - cancelTitle: Cancel button title.
    ///   - enableLoginWhenEmpty: If `false`, login button disabled until both fields are non‑empty.
    ///   - onLogin: `(loginTitle, username, password, true, nil)`, called only when the login
    ///     button is pressed.
    ///   - onCancel: `(cancelTitle, true, nil)`.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`; a failure is
    ///     reported only here (not through `onLogin`).
    /// - Warning: Avoid logging raw passwords in production builds. The library never logs them.
    public func showLoginDialog(
        title: String? = nil,
        message: String? = nil,
        usernamePlaceholder: String? = "Username",
        passwordPlaceholder: String? = "Password",
        loginTitle: String? = "Login",
        cancelTitle: String? = "Cancel",
        enableLoginWhenEmpty: Bool = true,
        onLogin: (@MainActor @Sendable (String?, String?, String?, Bool, String?) -> Void)? = nil,
        onCancel: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "showLoginDialog called with title: \(title ?? "nil", privacy: .private), message: \(message ?? "nil", privacy: .private), usernamePlaceholder: \(usernamePlaceholder ?? "nil", privacy: .private), passwordPlaceholder: \(passwordPlaceholder ?? "nil", privacy: .private), loginTitle: \(loginTitle ?? "nil", privacy: .private), cancelTitle: \(cancelTitle ?? "nil", privacy: .private), enableLoginWhenEmpty: \(enableLoginWhenEmpty, privacy: .public), onLogin: \(onLogin != nil ? "provided" : "nil", privacy: .public), onCancel: \(onCancel != nil ? "provided" : "nil", privacy: .public), completion: \(completion != nil ? "provided" : "nil", privacy: .public)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let spec = AlertSpec(title: title, message: message, style: .alert,
                                     buttons: .library([.init(title: loginTitle, style: .default, role: .primary),
                                                        .init(title: cancelTitle, style: .cancel, role: .cancel)]),
                                     fields: .library([.init(placeholder: usernamePlaceholder, isSecure: false, contentType: .username),
                                                       .init(placeholder: passwordPlaceholder, isSecure: true, contentType: .password)]),
                                     input: .login, requiresInput: !enableLoginWhenEmpty)
                self.presentLegacy("showLoginDialog", spec, completion: completion) { answer in
                    if answer.button == .cancel {
                        onCancel?(cancelTitle, true, nil)
                    } else {
                        var username: String?
                        var password: String?
                        if case .login(let enteredUsername, let enteredPassword)? = answer.input {
                            username = enteredUsername
                            password = enteredPassword
                        }
                        onLogin?(loginTitle, username, password, true, nil)
                    }
                }
            }
        }
    }

    /// Presents `spec` for one of the `show...` methods and maps its events to the method's
    /// callbacks: `completion(true, nil)` when presented, `completion(false, <message>)` on a
    /// failure (the only failure path), `onAnswer` when a button is pressed.
    @MainActor
    private func presentLegacy(_ method: String, _ spec: AlertSpec, completion: (@MainActor @Sendable (Bool, String?) -> Void)?,
                               onAnswer: @escaping @MainActor @Sendable (DialogAnswer) -> Void) {
        logger.log(level: .libraryDebug, "[presentLegacy] method: \(method, privacy: .public)")
        core.presentLegacy(spec) { event in
            switch event {
            case .presented:
                completion?(true, nil)
            case .failed(.notForeground):
                logger.error("[\(method, privacy: .public)] Failed to get root view controller")
                completion?(false, Self.noRootViewControllerMessage)
            case .failed(let error):
                logger.error("[\(method, privacy: .public)] Failed to present the dialog: \(LogRedaction.describe(error), privacy: .public)")
                completion?(false, Self.presentationFailedMessage)
            case .answered(let answer):
                logger.log(level: .libraryDebug, "[\(method, privacy: .public)] answer: \(answer.button.logName, privacy: .public), input: \(answer.input?.description ?? "nil", privacy: .public)")
                onAnswer(answer)
            }
        }
    }
}
