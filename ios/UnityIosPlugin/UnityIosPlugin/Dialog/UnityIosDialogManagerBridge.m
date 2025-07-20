//
//  UnityIosDialogManagerBridge.m
//  UnityIosPlugin
//
//  Created by Kim Jong Hyun on 2025/04/12.
//
#import "UnityIosDialogManagerBridge.h"

static NSString *const TAG = @"UnityIosDialogManagerBridge";

// 基本的なアラートダイアログ
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
                                                handler:^(NSString* buttonPressed, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showDialogWithTitle buttonPressed: %@, isSuccess: %d, errorMessage: %@", buttonPressed, isSuccess, errorMessage]];
        const char* buttonResult = buttonPressed ? buttonPressed.UTF8String : "";
        const char* errorStr = errorMessage ? errorMessage.UTF8String : "";
        callback(buttonResult, isSuccess, errorStr);
    }];
}

// 確認ダイアログ
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
                                                       handler:^(NSString* buttonPressed, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showConfirmDialogWithTitle buttonPressed: %@, isSuccess: %d, errorMessage: %@", buttonPressed, isSuccess, errorMessage]];
        const char* buttonResult = buttonPressed ? buttonPressed.UTF8String : "";
        const char* errorStr = errorMessage ? errorMessage.UTF8String : "";
        callback(buttonResult, isSuccess, errorStr);
    }];
}

// 破壊的な操作の確認ダイアログ
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
                                                           handler:^(NSString* buttonPressed, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showDestructiveDialogWithTitle buttonPressed: %@, isSuccess: %d, errorMessage: %@", buttonPressed, isSuccess, errorMessage]];
        const char* buttonResult = buttonPressed ? buttonPressed.UTF8String : "";
        const char* errorStr = errorMessage ? errorMessage.UTF8String : "";
        callback(buttonResult, isSuccess, errorStr);
    }];
}

// アクションシート
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
                                                     handler:^(NSString* buttonPressed, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showActionSheetWithTitle buttonPressed: %@, isSuccess: %d, errorMessage: %@", buttonPressed, isSuccess, errorMessage]];
        const char* buttonResult = buttonPressed ? buttonPressed.UTF8String : "";
        const char* errorStr = errorMessage ? errorMessage.UTF8String : "";
        callback(buttonResult, isSuccess, errorStr);
    }];
}

// テキスト入力ダイアログ
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
                                                         handler:^(NSString* buttonPressed, NSString* inputText, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showTextInputDialogWithTitle buttonPressed: %@, inputText: %@, isSuccess: %d, errorMessage: %@", buttonPressed, inputText, isSuccess, errorMessage]];
        const char* buttonResult = buttonPressed ? buttonPressed.UTF8String : "";
        const char* textResult = inputText ? inputText.UTF8String : "";
        const char* errorStr = errorMessage ? errorMessage.UTF8String : "";
        callback(buttonResult, textResult, isSuccess, errorStr);
    }];
}

// ログインダイアログ
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
                                                     handler:^(NSString* buttonPressed, NSString* username, NSString* password, BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"showLoginDialogWithTitle buttonPressed: %@, username: %@, password: %@, isSuccess: %d, errorMessage: %@", buttonPressed, username, password, isSuccess, errorMessage]];
        const char* buttonResult = buttonPressed ? buttonPressed.UTF8String : "";
        const char* usernameResult = username ? username.UTF8String : "";
        const char* passwordResult = password ? password.UTF8String : "";
        const char* errorStr = errorMessage ? errorMessage.UTF8String : "";
        callback(buttonResult, usernameResult, passwordResult, isSuccess, errorStr);
    }];
}
