//
//  UnityIosDialogManagerBridge.h
//
//  C ABI bridge exposing Swift dialog APIs (UnityIosDialogManager) to Unity (C# P/Invoke).
//  Provides a stable, minimal surface for alert / confirm / destructive / action sheet /
//  text input / login dialogs.
//
//  Design Notes:
//  - All strings are expected to be UTF-8 encoded `const char*` and may be NULL where documented.
//  - Callbacks are invoked on the main thread.
//  - `isSuccess` only reports presentation success (preconditions met & user could interact). User
//    cancellation still yields `isSuccess == true` with a valid button label.
//  - Optional return strings use NULL (not empty string) when absent (e.g. failure before presentation,
//    user canceled input values, etc.). Unity side should null-check before decoding.
//  - Do not retain raw pointer values past the callback; copy to managed strings immediately.
//


#import <Foundation/Foundation.h>
#import <IosLibrary/IosLibrary-Swift.h>
#import <UnityIosPlugin/UnityIosPlugin-Swift.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Callback for a simple single-button alert.
/// - Parameters:
///   - buttonText: Pressed button label (NULL on failure before presentation).
///   - isSuccess: false only if dialog failed to present.
///   - errorMessage: Human-readable diagnostic (NULL if no error).
typedef void (*DialogCallback)(const char* buttonText,
                               bool isSuccess,
                               const char* errorMessage);

/// Callback for confirm/cancel dialogs.
/// - Parameters mirror `DialogCallback` but `buttonText` will be confirm or cancel label on success.
typedef void (*ConfirmDialogCallback)(const char* buttonText,
                                      bool isSuccess,
                                      const char* errorMessage);

/// Callback for destructive + cancel dialogs.
/// - `buttonText` is destructive or cancel label when successful.
typedef void (*DestructiveDialogCallback)(const char* buttonText,
                                          bool isSuccess,
                                          const char* errorMessage);

/// Callback for action sheet selections.
/// - `buttonText` is the chosen option or the cancel label; NULL on presentation failure.
typedef void (*ActionSheetCallback)(const char* buttonText,
                                    bool isSuccess,
                                    const char* errorMessage);

/// Callback for single text input dialogs.
/// - `inputText` contains user input only when confirm tapped and success.
/// - Cancel or failure sets `inputText` to NULL.
typedef void (*TextInputDialogCallback)(const char* buttonText,
                                        const char* inputText,
                                        bool isSuccess,
                                        const char* errorMessage);

/// Callback for login (username + password) dialogs.
/// - `username` / `password` are provided only when login confirmed and success (never on cancel / failure).
/// - Never store plaintext password beyond immediate use for security.
typedef void (*LoginDialogCallback)(const char* buttonText,
                                    const char* username,
                                    const char* password,
                                    bool isSuccess,
                                    const char* errorMessage);

/// Presents a single-button alert.
/// - Parameters:
///   - title: Alert title (UTF-8, required, non-NULL).
///   - message: Alert message (UTF-8, required, non-NULL).
///   - buttonText: Acknowledgment button label (UTF-8, required, non-NULL).
///   - callback: Result callback; may be NULL if caller does not need result.
void showDialog(const char* title,
                const char* message,
                const char* buttonText,
                DialogCallback callback);

/// Presents a confirm/cancel dialog.
/// - Parameters:
///   - title: Dialog title.
///   - message: Body text.
///   - confirmButtonText: Confirm label.
///   - cancelButtonText: Cancel label.
///   - callback: Receives pressed button label or NULL on failure.
void showConfirmDialog(const char* title,
                       const char* message,
                       const char* confirmButtonText,
                       const char* cancelButtonText,
                       ConfirmDialogCallback callback);

/// Presents a destructive confirmation dialog (e.g. Delete) with cancel.
/// - Parameters:
///   - title: Dialog title.
///   - message: Warning / impact description.
///   - destructiveButtonText: Destructive action label.
///   - cancelButtonText: Cancel label.
///   - callback: Reports pressed button or NULL on failure.
void showDestructiveDialog(const char* title,
                           const char* message,
                           const char* destructiveButtonText,
                           const char* cancelButtonText,
                           DestructiveDialogCallback callback);

/// Presents an action sheet with arbitrary options plus cancel.
/// - Parameters:
///   - title: Optional title (NULL to omit).
///   - message: Optional message (NULL to omit).
///   - options: Array of `optionCount` UTF-8 option labels.
///   - optionCount: Number of entries in `options`.
///   - cancelButtonText: Cancel label (required, non-NULL).
///   - callback: Returns chosen option or cancel; NULL on failure.
void showActionSheet(const char* title,
                     const char* message,
                     const char* options[],
                     int optionCount,
                     const char* cancelButtonText,
                     ActionSheetCallback callback);

/// Presents a single text input dialog.
/// - Parameters:
///   - title: Dialog title.
///   - message: Optional message (NULL for none).
///   - placeholder: Optional text field placeholder.
///   - confirmButtonText: Confirm label.
///   - cancelButtonText: Cancel label.
///   - enableConfirmWhenEmpty: If false, confirm disabled until user enters non-empty text.
///   - callback: Provides input (if confirmed) or NULLs on cancel/failure.
void showTextInputDialog(const char* title,
                         const char* message,
                         const char* placeholder,
                         const char* confirmButtonText,
                         const char* cancelButtonText,
                         bool enableConfirmWhenEmpty,
                         TextInputDialogCallback callback);

/// Presents a login dialog with username & password fields.
/// - Parameters:
///   - title: Dialog title.
///   - message: Optional message.
///   - usernamePlaceholder: Placeholder for username field.
///   - passwordPlaceholder: Placeholder for password field.
///   - loginButtonText: Login action label.
///   - cancelButtonText: Cancel action label.
///   - enableLoginWhenEmpty: If false, login disabled until both fields contain text.
///   - callback: Returns credentials on success; NULL values on cancel/failure.
void showLoginDialog(const char* title,
                     const char* message,
                     const char* usernamePlaceholder,
                     const char* passwordPlaceholder,
                     const char* loginButtonText,
                     const char* cancelButtonText,
                     bool enableLoginWhenEmpty,
                     LoginDialogCallback callback);

#ifdef __cplusplus
}
#endif
