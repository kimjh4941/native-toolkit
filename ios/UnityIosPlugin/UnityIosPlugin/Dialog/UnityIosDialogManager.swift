//
//  IosDialogManager.swift
//  
//
//  Created by Kim Jong Hyun on 2025/04/12.
//
import UIKit
import IosLibrary

@objcMembers
public class UnityIosDialogManager: NSObject {
    
    private let TAG = "UnityIosDialogManager"
    
    public static let shared = UnityIosDialogManager()
    
    private override init() {
        Log.d(TAG, "init")
        super.init()
    }
    
    // 基本的なアラートダイアログ - IosDialogManager.showAlert()を使用
    public func showDialog(
        title: String,
        message: String,
        buttonText: String = "OK",
        handler: ((String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showDialog called with title: \(title), message: \(message), buttonText: \(buttonText)")
        IosDialogManager.shared.showAlert(
            title: title,
            message: message,
            buttonText: buttonText
        ) { result, isSuccess, errorMessage in
            Log.d(self.TAG, "OK button pressed")
            handler?(result, isSuccess, errorMessage)
        }
    }
    
    // 確認ダイアログ - IosDialogManager.showConfirmDialog()を使用
    public func showConfirmDialog(
        title: String,
        message: String,
        confirmButtonText: String = "OK",
        cancelButtonText: String = "Cancel",
        handler: ((String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showConfirmDialog called")
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
            }
        )
    }

    // 破壊的な操作の確認ダイアログ - IosDialogManager.showDestructiveDialog()を使用
    public func showDestructiveDialog(
        title: String,
        message: String,
        destructiveButtonText: String = "Delete",
        cancelButtonText: String = "Cancel",
        handler: ((String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showDestructiveDialog called")
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
            }
        )
    }

    // 複数選択肢のアクションシート - IosDialogManager.showActionSheet()を使用
    public func showActionSheet(
        title: String?,
        message: String?,
        options: [String],
        cancelButtonText: String = "Cancel",
        handler: ((String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showActionSheet called with options: \(options)")

        var actions: [UIAlertAction] = []

        for option in options {
            let action = UIAlertAction(title: option, style: .default) { _ in
                Log.d(self.TAG, "Option selected: \(option)")
                handler?(option, true, nil)
            }
            actions.append(action)
        }

        // キャンセルアクションを追加
        let cancelAction = UIAlertAction(title: cancelButtonText, style: .cancel) { _ in
            Log.d(self.TAG, "Cancel button pressed")
            handler?(cancelButtonText, true, nil)
        }
        actions.append(cancelAction)

        // IosDialogManagerのshowActionSheetを使用（ソースビューの取得）
        if let rootViewController = IosDialogManager.shared.getRootViewController() {
            IosDialogManager.shared.showActionSheet(
                title: title,
                message: message,
                actions: actions,
                sourceView: rootViewController.view
            ) { result, isSuccess, errorMessage in
                if !isSuccess {
                    handler?(nil, false, errorMessage)
                }
            }
        } else {
            handler?(nil, false, "Failed to get root view controller")
        }
    }

    // テキスト入力ダイアログ - IosDialogManager.showTextInputDialog()を使用
    public func showTextInputDialog(
        title: String,
        message: String?,
        placeholder: String?,
        confirmButtonText: String = "OK",
        cancelButtonText: String = "Cancel",
        enableConfirmWhenEmpty: Bool = true,
        handler: ((String?, String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showTextInputDialog called")
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
            }
        )
    }

    // ログインダイアログ（ユーザー名とパスワード入力） - IosDialogManager.showLoginDialog()を使用
    public func showLoginDialog(
        title: String,
        message: String?,
        usernamePlaceholder: String = "Username",
        passwordPlaceholder: String = "Password",
        loginButtonText: String = "Login",
        cancelButtonText: String = "Cancel",
        enableLoginWhenEmpty: Bool = true,
        handler: ((String?, String?, String?, Bool, String?) -> Void)?
    ) {
        Log.d(TAG, "showLoginDialog called")
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
            }
        )
    }
}
