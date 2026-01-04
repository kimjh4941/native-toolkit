//
//  UnityIosDialogManagerBridge.m
//  UnityIosPlugin
//
//  Created by Kim Jong Hyun on 2025/04/12.
//
#import "UnityIosDialogManagerBridge.h"

static NSString *const TAG = @"UnityIosDialogManagerBridge";

/// Presents a single-button alert dialog.
///
/// - Parameters:
///   - title: UTF-8 C string for the alert title (required).
///   - message: UTF-8 C string for the alert message (required).
///   - buttonText: UTF-8 C string for the acknowledgment button label.
///   - callback: Invoked with `(buttonTitleOrNULL, isSuccess, errorMessageOrNULL)`.
///
/// - Discussion:
///   `isSuccess` is `false` only if presentation prerequisites failed (e.g. missing root VC). User interaction
///   (tapping the button) is considered success. `buttonTitleOrNULL` will be NULL on failure.
void showDialog(const char* title,
                const char* message,
                const char* buttonText,
                DialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showDialog called with title: %s, message: %s, buttonText: %s, callback: %p", title, message, buttonText, callback]];
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = [NSString stringWithUTF8String:message];
    NSString* nsButtonText = [NSString stringWithUTF8String:buttonText];
    
    [[UnityIosDialogManager shared] showDialogWithTitle:nsTitle
                                                message:nsMessage
                                           buttonText:nsButtonText
                                                handler:^(NSString* buttonText, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showDialogWithTitle buttonText: %@, isSuccess: %d, errorMessage: %@", buttonText, isSuccess, errorMessage]];
        const char* buttonResult = buttonText ? buttonText.UTF8String : nil;
        const char* errorStr = errorMessage ? errorMessage.UTF8String : nil;
        callback(buttonResult, isSuccess, errorStr);
    }];
}

/// Presents a confirmation dialog with confirm & cancel buttons.
///
/// - Parameters:
///   - title: Dialog title.
///   - message: Dialog body text.
///   - confirmButtonText: Label for the confirm action.
///   - cancelButtonText: Label for the cancel action.
///   - callback: Receives the pressed button title (confirm / cancel) or NULL on failure.
///
/// - Note: User cancellation yields `isSuccess = true` and `errorMessage = NULL`.
void showConfirmDialog(const char* title,
                       const char* message,
                       const char* confirmButtonText,
                       const char* cancelButtonText,
                       ConfirmDialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showConfirmDialog called with title: %s, message: %s, confirmButtonText: %s, cancelButtonText: %s, callback: %p", title, message, confirmButtonText, cancelButtonText, callback]];
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = [NSString stringWithUTF8String:message];
    NSString* nsConfirmText = [NSString stringWithUTF8String:confirmButtonText];
    NSString* nsCancelText = [NSString stringWithUTF8String:cancelButtonText];

    [[UnityIosDialogManager shared] showConfirmDialogWithTitle:nsTitle
                                                       message:nsMessage
                                             confirmButtonText:nsConfirmText
                                              cancelButtonText:nsCancelText
                                                       handler:^(NSString* buttonText, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showConfirmDialogWithTitle buttonText: %@, isSuccess: %d, errorMessage: %@", buttonText, isSuccess, errorMessage]];
        const char* buttonResult = buttonText ? buttonText.UTF8String : nil;
        const char* errorStr = errorMessage ? errorMessage.UTF8String : nil;
        callback(buttonResult, isSuccess, errorStr);
    }];
}

/// Presents a destructive confirmation dialog (e.g. delete) plus cancel.
///
/// - Parameters:
///   - title: Dialog title.
///   - message: Description / warning text.
///   - destructiveButtonText: Destructive action label.
///   - cancelButtonText: Cancel action label.
///   - callback: Reports which button was pressed or NULL on failure.
/// - Warning: Use descriptive destructive labels for clarity.
void showDestructiveDialog(const char* title,
                           const char* message,
                           const char* destructiveButtonText,
                           const char* cancelButtonText,
                           DestructiveDialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showDestructiveDialog called with title: %s, message: %s, destructiveButtonText: %s, cancelButtonText: %s, callback: %p", title, message, destructiveButtonText, cancelButtonText, callback]];
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = [NSString stringWithUTF8String:message];
    NSString* nsDestructiveText = [NSString stringWithUTF8String:destructiveButtonText];
    NSString* nsCancelText = [NSString stringWithUTF8String:cancelButtonText];

    [[UnityIosDialogManager shared] showDestructiveDialogWithTitle:nsTitle
                                                           message:nsMessage
                                             destructiveButtonText:nsDestructiveText
                                                  cancelButtonText:nsCancelText
                                                           handler:^(NSString* buttonText, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showDestructiveDialogWithTitle buttonText: %@, isSuccess: %d, errorMessage: %@", buttonText, isSuccess, errorMessage]];
        const char* buttonResult = buttonText ? buttonText.UTF8String : nil;
        const char* errorStr = errorMessage ? errorMessage.UTF8String : nil;
        callback(buttonResult, isSuccess, errorStr);
    }];
}

/// Presents an action sheet with multiple options plus a cancel action.
///
/// - Parameters:
///   - title: Optional sheet title (NULL -> omitted).
///   - message: Optional sheet message.
///   - options: Array of UTF-8 option strings (length `optionCount`).
///   - optionCount: Number of entries in `options`.
///   - cancelButtonText: Cancel action label (optional; if NULL an internally provided label may be used).
///   - callback: Returns chosen option or cancel label; NULL on failure.
///
/// - Note: Each non-cancel option maps directly to a button; order preserved.
void showActionSheet(const char* title,
                     const char* message,
                     const char* options[],
                     int optionCount,
                     const char* cancelButtonText,
                     ActionSheetCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showActionSheet called with title: %s, message: %s, options count: %d, cancelButtonText: %s, callback: %p", title, message, optionCount, cancelButtonText, callback]];
    NSString* nsTitle = title ? [NSString stringWithUTF8String:title] : nil;
    NSString* nsMessage = message ? [NSString stringWithUTF8String:message] : nil;

    NSMutableArray<NSString*>* nsOptions = [NSMutableArray arrayWithCapacity:optionCount];
    for (int i = 0; i < optionCount; i++) {
        [nsOptions addObject:[NSString stringWithUTF8String:options[i]]];
    }
    NSString* nsCancelText = cancelButtonText ? [NSString stringWithUTF8String:cancelButtonText] : nil;

    [[UnityIosDialogManager shared] showActionSheetWithTitle:nsTitle
                                                     message:nsMessage
                                                     options:nsOptions
                                            cancelButtonText:nsCancelText
                                                     handler:^(NSString* buttonText, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showActionSheetWithTitle buttonText: %@, isSuccess: %d, errorMessage: %@", buttonText, isSuccess, errorMessage]];
        const char* buttonResult = buttonText ? buttonText.UTF8String : nil;
        const char* errorStr = errorMessage ? errorMessage.UTF8String : nil;
        callback(buttonResult, isSuccess, errorStr);
    }];
}

/// Presents a single text input dialog (one text field) with optional validation controlling
/// confirm button enablement.
///
/// - Parameters:
///   - title: Dialog title.
///   - message: Optional message.
///   - placeholder: Optional placeholder for the text field.
///   - confirmButtonText: Confirm action label.
///   - cancelButtonText: Cancel action label.
///   - enableConfirmWhenEmpty: When `false`, confirm disabled until text field non-empty.
///   - callback: `(buttonTitle, inputText, isSuccess, errorMessage)`; `inputText` NULL on cancel/failure.
void showTextInputDialog(const char* title,
                         const char* message,
                         const char* placeholder,
                         const char* confirmButtonText,
                         const char* cancelButtonText,
                         BOOL enableConfirmWhenEmpty,
                         TextInputDialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showTextInputDialog called with title: %s, message: %s, placeholder: %s, confirmButtonText: %s, cancelButtonText: %s, enableConfirmWhenEmpty: %d, callback: %p", title, message, placeholder, confirmButtonText, cancelButtonText, enableConfirmWhenEmpty, callback]];
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = message ? [NSString stringWithUTF8String:message] : nil;
    NSString* nsPlaceholder = placeholder ? [NSString stringWithUTF8String:placeholder] : nil;
    NSString* nsConfirmText = [NSString stringWithUTF8String:confirmButtonText];
    NSString* nsCancelText = [NSString stringWithUTF8String:cancelButtonText];

    [[UnityIosDialogManager shared] showTextInputDialogWithTitle:nsTitle
                                                         message:nsMessage
                                                     placeholder:nsPlaceholder
                                               confirmButtonText:nsConfirmText
                                                cancelButtonText:nsCancelText
                                          enableConfirmWhenEmpty:enableConfirmWhenEmpty
                                                         handler:^(NSString* buttonText, NSString* inputText, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showTextInputDialogWithTitle buttonText: %@, inputText: %@, isSuccess: %d, errorMessage: %@", buttonText, inputText, isSuccess, errorMessage]];
        const char* buttonResult = buttonText ? buttonText.UTF8String : nil;
        const char* textResult = inputText ? inputText.UTF8String : nil;
        const char* errorStr = errorMessage ? errorMessage.UTF8String : nil;
        callback(buttonResult, textResult, isSuccess, errorStr);
    }];
}

/// Presents a login dialog collecting username and password with optional validation controlling
/// login button enablement.
///
/// - Parameters:
///   - title: Dialog title.
///   - message: Optional message.
///   - usernamePlaceholder: Placeholder text for username field.
///   - passwordPlaceholder: Placeholder text for password field.
///   - loginButtonText: Login action label.
///   - cancelButtonText: Cancel action label.
///   - enableLoginWhenEmpty: When `false`, login disabled until both fields non-empty.
///   - callback: `(buttonTitle, username, password, isSuccess, errorMessage)`; username/password NULL on cancel/failure.
/// - Warning: Password is transient; do NOT log or store plaintext in production.
void showLoginDialog(const char* title,
                     const char* message,
                     const char* usernamePlaceholder,
                     const char* passwordPlaceholder,
                     const char* loginButtonText,
                     const char* cancelButtonText,
                     BOOL enableLoginWhenEmpty,
                     LoginDialogCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showLoginDialog called with title: %s, message: %s, usernamePlaceholder: %s, passwordPlaceholder: %s, loginButtonText: %s, cancelButtonText: %s, enableLoginWhenEmpty: %d, callback: %p", title, message, usernamePlaceholder, passwordPlaceholder, loginButtonText, cancelButtonText, enableLoginWhenEmpty, callback]];
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = message ? [NSString stringWithUTF8String:message] : nil;
    NSString* nsUsernamePlaceholder = [NSString stringWithUTF8String:usernamePlaceholder];
    NSString* nsPasswordPlaceholder = [NSString stringWithUTF8String:passwordPlaceholder];
    NSString* nsLoginText = [NSString stringWithUTF8String:loginButtonText];
    NSString* nsCancelText = [NSString stringWithUTF8String:cancelButtonText];

    [[UnityIosDialogManager shared] showLoginDialogWithTitle:nsTitle
                                                     message:nsMessage
                                         usernamePlaceholder:nsUsernamePlaceholder
                                         passwordPlaceholder:nsPasswordPlaceholder
                                             loginButtonText:nsLoginText
                                            cancelButtonText:nsCancelText
                                        enableLoginWhenEmpty:enableLoginWhenEmpty
                                                     handler:^(NSString* buttonText, NSString* username, NSString* password, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showLoginDialogWithTitle buttonText: %@, username: %@, password: %@, isSuccess: %d, errorMessage: %@", buttonText, username, password, isSuccess, errorMessage]];
        const char* buttonResult = buttonText ? buttonText.UTF8String : nil;
        const char* usernameResult = username ? username.UTF8String : nil;
        const char* passwordResult = password ? password.UTF8String : nil;
        const char* errorStr = errorMessage ? errorMessage.UTF8String : nil;
        callback(buttonResult, usernameResult, passwordResult, isSuccess, errorStr);
    }];
}
