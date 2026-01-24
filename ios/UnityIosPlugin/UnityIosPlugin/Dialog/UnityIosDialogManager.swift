//
//  UnityIosDialogManager.swift
//
//  Created by Kim Jong Hyun on 2025/04/12.
//
import UIKit
import IosLibrary

/// # UnityIosDialogManager
///
/// Swift façade exposing high‑level dialog APIs (alert / confirm / destructive / action sheet /
/// single text input / login) to Unity via Objective‑C bridge (`UnityIosDialogManagerBridge`).
/// Internally delegates to ``IosLibrary/IosDialogManager`` while normalizing callback signatures
/// for C# interop.
///
/// ## Overview
/// * Provides a singleton: ``shared``.
/// * Wraps and forwards calls to `IosDialogManager` helpers.
/// * Ensures all UI work occurs on the main thread (delegated manager already marshals).
/// * Returns unified callback tuples where `errorMessage` is only set when a *pre‑presentation* failure occurs
///   (e.g. no root view controller) — user cancellation is considered a successful interaction.
///
/// ## Callback Semantics
/// Each public method supplies a closure whose final two components are `(isSuccess, errorMessage)`.
/// * `isSuccess == false` => Dialog could not be presented (no root VC, other setup failure).
/// * User choices (including *Cancel*) produce `isSuccess == true` with `errorMessage == nil`.
/// * `result` (and any input fields) may be `nil` when failure occurs **before** presentation.
///
/// ## Threading
/// Safe to invoke from any thread; calls ultimately present on main queue.
///
/// ## Memory / Retain Cycles
/// Callbacks are not strongly retained past presentation flow; avoid strongly capturing Unity objects.
///
/// ## Example (C# P/Invoke pattern)
/// ```csharp
/// // P/Invoke signature example
/// [DllImport("__Internal")] static extern void showDialog(string title, string message, string ok, DialogCallback cb);
/// ```
@objcMembers
public class UnityIosDialogManager: NSObject {
    
    private let TAG = "UnityIosDialogManager"
    
    /// Shared singleton instance used by the Objective‑C bridge.
    public static let shared = UnityIosDialogManager()
    
    private override init() {
        Log.d(TAG, "init")
        super.init()
    }
    
    /// Shows a simple single‑button alert.
    /// - Parameters:
    ///   - title: Alert title (non‑optional for Unity convenience).
    ///   - message: Alert message.
    ///   - buttonText: Label for the acknowledgment button (default: "OK").
    ///   - handler: `(buttonTitle, isSuccess, errorMessage)`.
    ///     * `buttonTitle` echoes `buttonText` on success; `nil` on failure.
    ///     * `isSuccess=false` only when presentation failed.
    public func showDialog(
        title: String,
        message: String,
        buttonText: String = "OK",
        handler: ((String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showDialog called with title: \(title), message: \(message), buttonText: \(buttonText), handler: \(handler != nil ? "provided" : "nil")")
        IosDialogManager.shared.showAlert(
            title: title,
            message: message,
            buttonText: buttonText,
            onButton: { result, isSuccess, errorMessage in
                Log.d(self.TAG, "Alert button pressed")
                handler?(result, isSuccess, errorMessage)
            },
            completion: { isSuccess, errorMessage in
                if !isSuccess {
                    Log.d(self.TAG, "Alert presentation failed")
                    handler?(nil, false, errorMessage)
                }
            }
        )
    }
    
    /// Shows a confirmation dialog with confirm & cancel actions.
    /// - Parameters:
    ///   - title: Dialog title.
    ///   - message: Dialog message.
    ///   - confirmButtonText: Confirm action title (default: "OK").
    ///   - cancelButtonText: Cancel action title (default: "Cancel").
    ///   - handler: Unified callback for either button; `buttonTitle` reflects pressed button.
    /// - Note: Distinguish user choice via the `buttonTitle` value.
    public func showConfirmDialog(
        title: String,
        message: String,
        confirmButtonText: String = "OK",
        cancelButtonText: String = "Cancel",
        handler: ((String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showConfirmDialog called with title: \(title), message: \(message), confirmButtonText: \(confirmButtonText), cancelButtonText: \(cancelButtonText), handler: \(handler != nil ? "provided" : "nil")")
        IosDialogManager.shared.showConfirmDialog(
            title: title,
            message: message,
            confirmTitle: confirmButtonText,
            cancelTitle: cancelButtonText,
            onConfirm: { result, isSuccess, errorMessage in
                Log.d(self.TAG, "Confirm button pressed")
                handler?(result, isSuccess, errorMessage)
            },
            onCancel: { result, isSuccess, errorMessage in
                Log.d(self.TAG, "Cancel button pressed")
                handler?(result, isSuccess, errorMessage)
            },
            completion: { isSuccess, errorMessage in
                if !isSuccess {
                    Log.d(self.TAG, "Confirm dialog presentation failed")
                    handler?(nil, false, errorMessage)
                }
            }
        )
    }

    /// Shows a destructive confirmation dialog (e.g. irreversible deletion) plus cancel.
    /// - Parameters:
    ///   - title: Dialog title.
    ///   - message: Dialog message describing the impact.
    ///   - destructiveButtonText: Destructive action label (default: "Delete").
    ///   - cancelButtonText: Cancel action label.
    ///   - handler: Callback returning the pressed button label or failure info.
    /// - Warning: Use meaningful destructive labels (e.g. "Delete", "Remove") to ensure clarity in Unity UI flows.
    public func showDestructiveDialog(
        title: String,
        message: String,
        destructiveButtonText: String = "Delete",
        cancelButtonText: String = "Cancel",
        handler: ((String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showDestructiveDialog called with title: \(title), message: \(message), destructiveButtonText: \(destructiveButtonText), cancelButtonText: \(cancelButtonText), handler: \(handler != nil ? "provided" : "nil")")
        IosDialogManager.shared.showDestructiveDialog(
            title: title,
            message: message,
            destructiveTitle: destructiveButtonText,
            cancelTitle: cancelButtonText,
            onDestructive: { result, isSuccess, errorMessage in
                Log.d(self.TAG, "Destructive button pressed")
                handler?(result, isSuccess, errorMessage)
            },
            onCancel: { result, isSuccess, errorMessage in
                Log.d(self.TAG, "Cancel button pressed")
                handler?(result, isSuccess, errorMessage)
            },
            completion: { isSuccess, errorMessage in
                if !isSuccess {
                    Log.d(self.TAG, "Destructive dialog presentation failed")
                    handler?(nil, false, errorMessage)
                }
            }
        )
    }

    /// Presents an action sheet with a dynamic list of options plus a cancel action.
    /// - Parameters:
    ///   - title: Optional sheet title.
    ///   - message: Optional sheet message.
    ///   - options: List of selectable non‑destructive option titles.
    ///   - cancelButtonText: Cancel title (default: "Cancel").
    ///   - handler: `(selectedOptionOrCancel, true, nil)` or `(nil, false, error)` if presentation failed.
    /// - Note: For iPad, underlying manager anchors the popover using the root view; customize if a specific anchor is required.
    public func showActionSheet(
        title: String,
        message: String,
        options: [String],
        cancelButtonText: String = "Cancel",
        handler: ((String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showActionSheet called with title: \(title), message: \(message), options: \(options), cancelButtonText: \(cancelButtonText), handler: \(handler != nil ? "provided" : "nil")")
        if let rootViewController = IosDialogManager.shared.getRootViewController() {
            IosDialogManager.shared.showActionSheet(
                title: title,
                message: message,
                options: options,
                cancelTitle: cancelButtonText,
                sourceView: rootViewController.view,
                onAction: { result, isSuccess, errorMessage in
                    Log.d(self.TAG, "Action sheet option selected")
                    handler?(result, isSuccess, errorMessage)
                },
                completion: { isSuccess, errorMessage in
                    if !isSuccess {
                        Log.d(self.TAG, "Action sheet presentation failed")
                        handler?(nil, false, errorMessage)
                    }
                }
            )
        } else {
            handler?(nil, false, "Failed to get root view controller")
        }
    }

    /// Shows a single text input dialog.
    /// - Parameters:
    ///   - title: Dialog title.
    ///   - message: Optional message.
    ///   - placeholder: Placeholder for the input field.
    ///   - confirmButtonText: Confirm button label.
    ///   - cancelButtonText: Cancel button label.
    ///   - enableConfirmWhenEmpty: If `false`, confirm is disabled until user enters non‑empty text.
    ///   - handler: `(buttonTitle, inputText, isSuccess, errorMessage)`.
    ///     * `inputText` is only non‑nil when confirm pressed & success.
    public func showTextInputDialog(
        title: String,
        message: String,
        placeholder: String = "",
        confirmButtonText: String = "OK",
        cancelButtonText: String = "Cancel",
        enableConfirmWhenEmpty: Bool = false,
        handler: ((String?, String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showTextInputDialog called with title: \(title), message: \(message), placeholder: \(placeholder), confirmButtonText: \(confirmButtonText), cancelButtonText: \(cancelButtonText), enableConfirmWhenEmpty: \(enableConfirmWhenEmpty), handler: \(handler != nil ? "provided" : "nil")")
        IosDialogManager.shared.showTextInputDialog(
            title: title,
            message: message,
            placeholder: placeholder,
            confirmTitle: confirmButtonText,
            cancelTitle: cancelButtonText,
            enableConfirmWhenEmpty: enableConfirmWhenEmpty,
            onConfirm: { result, inputText, isSuccess, errorMessage in
                Log.d(self.TAG, "Text input confirmed")
                handler?(result, inputText, isSuccess, errorMessage)
            },
            onCancel: { result, isSuccess, errorMessage in
                Log.d(self.TAG, "Text input cancelled")
                handler?(result, nil, isSuccess, errorMessage)
            },
            completion: { isSuccess, errorMessage in
                if !isSuccess {
                    Log.d(self.TAG, "Text input dialog presentation failed")
                    handler?(nil, nil, false, errorMessage)
                }
            }
        )
    }

    /// Shows a login dialog (username + password).
    /// - Parameters:
    ///   - title: Dialog title.
    ///   - message: Optional message.
    ///   - usernamePlaceholder: Username field placeholder.
    ///   - passwordPlaceholder: Password field placeholder.
    ///   - loginButtonText: Login (primary) button title.
    ///   - cancelButtonText: Cancel button title.
    ///   - enableLoginWhenEmpty: If `false`, login disabled until both fields non‑empty.
    ///   - handler: `(buttonTitle, username, password, isSuccess, errorMessage)`; username / password only present on login success.
    /// - Warning: Do not persist plaintext passwords in logs or analytics.
    public func showLoginDialog(
        title: String,
        message: String,
        usernamePlaceholder: String = "Username",
        passwordPlaceholder: String = "Password",
        loginButtonText: String = "Login",
        cancelButtonText: String = "Cancel",
        enableLoginWhenEmpty: Bool = false,
        handler: ((String?, String?, String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showLoginDialog called with title: \(title), message: \(message), usernamePlaceholder: \(usernamePlaceholder), passwordPlaceholder: \(passwordPlaceholder), loginButtonText: \(loginButtonText), cancelButtonText: \(cancelButtonText), enableLoginWhenEmpty: \(enableLoginWhenEmpty), handler: \(handler != nil ? "provided" : "nil")")
        IosDialogManager.shared.showLoginDialog(
            title: title,
            message: message,
            usernamePlaceholder: usernamePlaceholder,
            passwordPlaceholder: passwordPlaceholder,
            loginTitle: loginButtonText,
            cancelTitle: cancelButtonText,
            enableLoginWhenEmpty: enableLoginWhenEmpty,
            onLogin: { result, username, password, isSuccess, errorMessage in
                Log.d(self.TAG, "Login attempted")
                handler?(result, username, password, isSuccess, errorMessage)
            },
            onCancel: { result, isSuccess, errorMessage in
                Log.d(self.TAG, "Login cancelled")
                handler?(result, nil, nil, isSuccess, errorMessage)
            },
            completion: { isSuccess, errorMessage in
                if !isSuccess {
                    Log.d(self.TAG, "Login dialog presentation failed")
                    handler?(nil, nil, nil, false, errorMessage)
                }
            }
        )
    }
}
