//
//  IosDialogManager.swift
//
//
//  Created by Kim Jong Hyun on 2025/04/12.
//
import UIKit

/// # IosDialogManager
///
/// Central utility for presenting `UIAlertController` based dialogs (alerts, action sheets,
/// text input, login style) in a thread‑safe, convenience oriented way.
///
/// ## Overview
/// * Provides a singleton (`shared`) for simple global access.
/// * Wraps creation & presentation of `UIAlertController` ensuring presentation happens on the main thread.
/// * Supplies higher level helpers (alert / confirm / destructive / action sheet / text & login input).
/// * Normalizes completion / callback signatures so each result conveys:
///   * **result**: Selected button title (or `nil` if not applicable / failed before presentation)
///   * **isSuccess**: Presentation + user interaction completed (`true`) or a precondition failed (`false`).
///   * **errorMessage**: Human readable diagnostic when `isSuccess == false` (else `nil`).
///
/// ## Threading
/// The manager is `Sendable`, and the `show...` methods may be called from any thread: all UIKit
/// work, including creating the `UIAlertAction`s of the convenience methods, runs on the main
/// thread (main actor) after the call returns. ``getRootViewController()`` reads UIKit state, so it
/// is `@MainActor` and must be called on the main actor.
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
/// `completion` reports the presentation: `(true, nil)` once UIKit has presented the dialog, or
/// `(false, errorMessage)` when no view controller to present on is found. Known gaps, kept as
/// they are until the Dialog result type is reworked:
/// * ``showLoginDialog(title:message:usernamePlaceholder:passwordPlaceholder:loginTitle:cancelTitle:enableLoginWhenEmpty:onLogin:onCancel:completion:)``
///   reports the failure through `onLogin` and does not invoke `completion`.
/// * If UIKit declines the presentation (for example because the found view controller is not
///   in a window), `completion` is not invoked.
///
/// ## Popover / iPad Support
/// For action sheets or alerts with style `.actionSheet`, popover anchors (`sourceView` / `sourceRect` / `barButtonItem`) are applied when available — falling back to centering inside the root view if none supplied.
///
/// ## Root View Controller Resolution
/// The manager searches the first foreground active `UIWindowScene`, then finds the key window and walks the `presentedViewController` chain.
/// If this process fails, the completion handler is invoked with `isSuccess = false`.
///
/// ## Input Validation Helpers
/// `showTextInputDialog` & `showLoginDialog` optionally disable the primary action button until required fields are filled (via `enableConfirmWhenEmpty` / `enableLoginWhenEmpty`).
///
/// ## Memory
/// Callbacks are not retained after dialog dismissal. Avoid capturing large objects strongly in closures.
///
/// ## Example
/// ```swift
/// IosDialogManager.shared.showAlert(title: "Notice", message: "Operation finished") { result, success, error in
///     guard success else { print(error ?? "Unknown"); return }
///     print("User tapped: \(result ?? "?")")
/// }
/// ```
public final class IosDialogManager: NSObject, Sendable {
    
    private let TAG = "IosDialogManager"
    
    /// Shared singleton instance.
    public static let shared = IosDialogManager()
    
    private override init() {
        Log.d(TAG, "init")
        super.init()
    }
    
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
    ///   - barButtonItem: Alternative popover anchor (takes precedence if provided).
    ///   - permittedArrowDirections: Popover arrow directions (iPad).
    ///   - animated: Whether the presentation is animated.
    ///   - completion: `(isSuccess, errorMessage)`.
    ///     * `isSuccess=false` indicates a pre‑presentation failure (e.g. no root VC).
    ///     * `errorMessage` provides human readable diagnostic when `isSuccess == false`.
    ///
    /// - Note: Custom `UIAlertAction` handlers run independently of `completion`. Use either approach—do not rely on `completion` to know which custom action was chosen.
    /// - Warning: Ensure you supply a `sourceView` / `barButtonItem` for action sheets on iPad to avoid runtime popover crashes.
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
        Log.d(TAG, "showDialog called with title: \(title ?? "nil"), message: \(message ?? "nil"), preferredStyle: \(preferredStyle), actions count: \(actions.count), textFields count: \(textFields?.count ?? 0), sourceView: \(sourceView?.description ?? "nil"), sourceRect: \(sourceRect != nil ? NSCoder.string(for: sourceRect!) : "nil"), barButtonItem: \(barButtonItem?.description ?? "nil"), permittedArrowDirections: \(permittedArrowDirections), animated: \(animated), completion: \(completion != nil ? "provided" : "nil")")
        DispatchQueue.main.async {
            self.presentDialog(
                title: title,
                message: message,
                preferredStyle: preferredStyle,
                actions: actions,
                textFields: textFields,
                sourceView: sourceView,
                sourceRect: sourceRect,
                barButtonItem: barButtonItem,
                permittedArrowDirections: permittedArrowDirections,
                animated: animated,
                completion: completion
            )
        }
    }

    /// Builds and presents the `UIAlertController` of ``showDialog(title:message:preferredStyle:actions:textFields:sourceView:sourceRect:barButtonItem:permittedArrowDirections:animated:completion:)``
    /// and of the convenience methods that take fixed actions.
    ///
    /// Runs on the main actor; the public methods call it from their `DispatchQueue.main.async` block.
    @MainActor
    private func presentDialog(
        title: String?,
        message: String?,
        preferredStyle: UIAlertController.Style = .alert,
        actions: [UIAlertAction],
        textFields: [@MainActor @Sendable (UITextField) -> Void]? = nil,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        barButtonItem: UIBarButtonItem? = nil,
        permittedArrowDirections: UIPopoverArrowDirection = .any,
        animated: Bool = true,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)?
    ) {
        guard let rootViewController = getRootViewController() else {
            Log.e(TAG, "Failed to get root view controller")
            completion?(false, "Failed to get root view controller")
            return
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: preferredStyle)

        // Add actions
        for action in actions {
            alert.addAction(action)
        }

        // Add default OK action if no actions provided
        if actions.isEmpty {
            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            alert.addAction(okAction)
        }

        // Add text fields if provided (only for .alert style)
        if let textFields = textFields, preferredStyle == .alert {
            for textFieldConfig in textFields {
                alert.addTextField(configurationHandler: textFieldConfig)
            }
        }

        // Configure popover presentation for iPad
        if let popover = alert.popoverPresentationController {
            if let sourceView = sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceRect ?? sourceView.bounds
            } else if let barButtonItem = barButtonItem {
                popover.barButtonItem = barButtonItem
            } else {
                // Fallback to center of the screen
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX,
                                            y: rootViewController.view.bounds.midY,
                                            width: 0, height: 0)
            }
            popover.permittedArrowDirections = permittedArrowDirections
        }

        // Present the alert
        rootViewController.present(alert, animated: animated) {
            completion?(true, nil)
        }
    }
    
    /// Resolves the top-most presented `UIViewController` suitable for presenting a dialog.
    ///
    /// Iterates through foreground active scenes → key window → presented chain.
    /// Returns `nil` if no active scene or key window is found.
    /// - Returns: The top view controller or `nil`.
    /// - Note: It reads UIKit state, so it is `@MainActor`: call it on the main actor.
    @MainActor
    public func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            Log.e(TAG, "Failed to get window scene or key window")
            return nil
        }
        
        var rootViewController = window.rootViewController
        while let presentedViewController = rootViewController?.presentedViewController {
            rootViewController = presentedViewController
        }
        
        return rootViewController
    }
    
    // Convenience methods for common dialog types
    
    /// Shows a simple single button alert (OK style).
    /// - Parameters:
    ///   - title: Alert title.
    ///   - message: Alert message.
    ///   - buttonText: Button label (default "OK").
    ///   - onButton: Called when button tapped with `(buttonText, true, nil)` or `(nil, false, error)` on failure.
    ///   -   - completion: Called after presentation with `(isSuccess, errorMessage)`.
    public func showAlert(
        title: String? = nil,
        message: String? = nil,
        buttonText: String? = "OK",
        onButton: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "showAlert called with title: \(title ?? "nil"), message: \(message ?? "nil"), buttonText: \(buttonText ?? "nil"), onButton: \(onButton != nil ? "provided" : "nil"), completion: \(completion != nil ? "provided" : "nil")")
        DispatchQueue.main.async {
            let okAction = UIAlertAction(title: buttonText, style: .default) { _ in
                onButton?(buttonText, true, nil)
            }
            self.presentDialog(title: title,
                               message: message,
                               actions: [okAction],
                               completion: completion)
        }
    }
    
    /// Shows a confirm / cancel dialog.
    /// - Parameters:
    ///   - title: Dialog title.
    ///   - message: Dialog message.
    ///   - confirmTitle: Confirm button title (default "OK").
    ///   - cancelTitle: Cancel button title (default "Cancel").
    ///   - onConfirm: Called when confirm tapped with `(confirmTitle, true, nil)` or `(nil, false, error)` on failure.
    ///   - onCancel: Called when cancel tapped with `(cancelTitle, true, nil)` or `(nil, false, error)` on failure.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`.
    public func showConfirmDialog(
        title: String? = nil,
        message: String? = nil,
        confirmTitle: String? = "OK",
        cancelTitle: String? = "Cancel",
        onConfirm: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        onCancel: (@MainActor @Sendable (String?, Bool, String?) -> Void)? = nil,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "showConfirmDialog called with title: \(title ?? "nil"), message: \(message ?? "nil"), confirmTitle: \(confirmTitle ?? "nil"), cancelTitle: \(cancelTitle ?? "nil"), onConfirm: \(onConfirm != nil ? "provided" : "nil"), onCancel: \(onCancel != nil ? "provided" : "nil"), completion: \(completion != nil ? "provided" : "nil")")
        DispatchQueue.main.async {
            let confirmAction = UIAlertAction(title: confirmTitle, style: .default) { _ in
                onConfirm?(confirmTitle, true, nil)
            }
            let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                onCancel?(cancelTitle, true, nil)
            }
            self.presentDialog(title: title,
                               message: message,
                               actions: [confirmAction, cancelAction],
                               completion: completion)
        }
    }
    
    /// Shows a destructive confirmation dialog (e.g., Delete action) plus cancel.
    /// - Parameters:
    ///   - title: Dialog title.
    ///   - message: Dialog message.
    ///   - destructiveTitle: Destructive button title (default "Delete").
    ///   - cancelTitle: Cancel button title.
    ///   - onDestructive: Callback for destructive tap.
    ///   - onCancel: Callback for cancel tap.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`.
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
        Log.d(TAG, "showDestructiveDialog called with title: \(title ?? "nil"), message: \(message ?? "nil"), destructiveTitle: \(destructiveTitle ?? "nil"), cancelTitle: \(cancelTitle ?? "nil"), onDestructive: \(onDestructive != nil ? "provided" : "nil"), onCancel: \(onCancel != nil ? "provided" : "nil")")
        DispatchQueue.main.async {
            let destructiveAction = UIAlertAction(title: destructiveTitle, style: .destructive) { _ in
                onDestructive?(destructiveTitle, true, nil)
            }
            let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                onCancel?(cancelTitle, true, nil)
            }
            self.presentDialog(title: title,
                               message: message,
                               actions: [destructiveAction, cancelAction],
                               completion: completion)
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
    ///   - onAction: `(selectedOption, isSuccess, errorMessage)`.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`.
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
        Log.d(TAG, "showActionSheet called with title: \(title ?? "nil"), message: \(message ?? "nil"), options: \(options), cancelTitle: \(cancelTitle), sourceView: \(sourceView.description), sourceRect: \(sourceRect != nil ? NSCoder.string(for: sourceRect!) : "nil"), animated: \(animated), completion: \(completion != nil ? "provided" : "nil")")
        DispatchQueue.main.async {
            var actions: [UIAlertAction] = []
            for option in options {
                let action = UIAlertAction(title: option, style: .default) { _ in
                    Log.d(self.TAG, "Option selected: \(option)")
                    onAction?(option, true, nil)
                }
                actions.append(action)
            }

            let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                Log.d(self.TAG, "Cancel button pressed")
                onAction?(cancelTitle, true, nil)
            }
            actions.append(cancelAction)

            self.presentDialog(title: title,
                               message: message,
                               preferredStyle: .actionSheet,
                               actions: actions,
                               sourceView: sourceView,
                               sourceRect: sourceRect,
                               animated: animated,
                               completion: completion)
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
    ///   - onConfirm: `(buttonTitle, inputText, true, nil)` or `(nil, nil, false, error)`.
    ///   - onCancel: `(cancelTitle, true, nil)` or `(nil, false, error)`.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`.
    /// - Note: Text change observation uses `UITextField.textDidChangeNotification` and is only installed if validation is needed.
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
        Log.d(TAG, "showTextInputDialog called with title: \(title ?? "nil"), message: \(message ?? "nil"), placeholder: \(placeholder ?? "nil"), confirmTitle: \(confirmTitle ?? "nil"), cancelTitle: \(cancelTitle ?? "nil"), enableConfirmWhenEmpty: \(enableConfirmWhenEmpty), onConfirm: \(onConfirm != nil ? "provided" : "nil"), onCancel: \(onCancel != nil ? "provided" : "nil"), completion: \(completion != nil ? "provided" : "nil")")
        DispatchQueue.main.async {
            guard let rootViewController = self.getRootViewController() else {
                Log.e(self.TAG, "Failed to get root view controller")
                completion?(false, "Failed to get root view controller")
                return
            }
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            
            let confirmAction = UIAlertAction(title: confirmTitle, style: .default) { _ in
                let inputText = alert.textFields?.first?.text
                onConfirm?(confirmTitle, inputText, true, nil)
            }
            
            confirmAction.isEnabled = enableConfirmWhenEmpty
            
            alert.addTextField { textField in
                textField.placeholder = placeholder
                
                if !enableConfirmWhenEmpty {
                    NotificationCenter.default.addObserver(
                        forName: UITextField.textDidChangeNotification,
                        object: textField,
                        queue: .main
                    ) { _ in
                        // The observer is registered with `queue: .main`, so the block runs on the
                        // main thread; `assumeIsolated` checks that at run time.
                        MainActor.assumeIsolated {
                            confirmAction.isEnabled = !(textField.text?.isEmpty ?? true)
                        }
                    }
                }
            }
            
            let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                onCancel?(cancelTitle, true, nil)
            }
            
            alert.addAction(confirmAction)
            alert.addAction(cancelAction)
            
            rootViewController.present(alert, animated: true) {
                completion?(true, nil)
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
    ///   - onLogin: `(loginTitle, username, password, true, nil)` or `(nil, nil, nil, false, error)`.
    ///   - onCancel: `(cancelTitle, true, nil)` or `(nil, false, error)`.
    ///   - completion: Called after presentation with `(isSuccess, errorMessage)`.
    /// - Warning: Avoid logging raw passwords in production builds.
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
        Log.d(TAG, "showLoginDialog called with title: \(title ?? "nil"), message: \(message ?? "nil"), usernamePlaceholder: \(usernamePlaceholder ?? "nil"), passwordPlaceholder: \(passwordPlaceholder ?? "nil"), loginTitle: \(loginTitle ?? "nil"), cancelTitle: \(cancelTitle ?? "nil"), enableLoginWhenEmpty: \(enableLoginWhenEmpty), onLogin: \(onLogin != nil ? "provided" : "nil"), onCancel: \(onCancel != nil ? "provided" : "nil"), completion: \(completion != nil ? "provided" : "nil")")
        DispatchQueue.main.async {
            guard let rootViewController = self.getRootViewController() else {
                Log.e(self.TAG, "Failed to get root view controller")
                onLogin?(nil, nil, nil, false, "Failed to get root view controller")
                return
            }
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            
            let loginAction = UIAlertAction(title: loginTitle, style: .default) { _ in
                let username = alert.textFields?[0].text
                let password = alert.textFields?[1].text
                onLogin?(loginTitle, username, password, true, nil)
            }
            
            loginAction.isEnabled = enableLoginWhenEmpty
            
            alert.addTextField { textField in
                textField.placeholder = usernamePlaceholder
                textField.textContentType = .username
                
                if !enableLoginWhenEmpty {
                    NotificationCenter.default.addObserver(
                        forName: UITextField.textDidChangeNotification,
                        object: textField,
                        queue: .main
                    ) { _ in
                        // Runs on the main thread (`queue: .main`); see `showTextInputDialog`.
                        MainActor.assumeIsolated {
                            let username = alert.textFields?[0].text
                            let password = alert.textFields?[1].text
                            loginAction.isEnabled = !(username?.isEmpty ?? true) && !(password?.isEmpty ?? true)
                        }
                    }
                }
            }
            
            alert.addTextField { textField in
                textField.placeholder = passwordPlaceholder
                textField.isSecureTextEntry = true
                textField.textContentType = .password
                
                if !enableLoginWhenEmpty {
                    NotificationCenter.default.addObserver(
                        forName: UITextField.textDidChangeNotification,
                        object: textField,
                        queue: .main
                    ) { _ in
                        // Runs on the main thread (`queue: .main`); see `showTextInputDialog`.
                        MainActor.assumeIsolated {
                            let username = alert.textFields?[0].text
                            let password = alert.textFields?[1].text
                            loginAction.isEnabled = !(username?.isEmpty ?? true) && !(password?.isEmpty ?? true)
                        }
                    }
                }
            }
            
            let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                onCancel?(cancelTitle, true, nil)
            }
            
            alert.addAction(loginAction)
            alert.addAction(cancelAction)
            
            rootViewController.present(alert, animated: true) {
                completion?(true, nil)
            }
        }
    }
}
