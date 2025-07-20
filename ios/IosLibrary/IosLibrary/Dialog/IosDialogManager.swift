//
//  IosDialogManager.swift
//  
//
//  Created by Kim Jong Hyun on 2025/04/12.
//
import UIKit

public class IosDialogManager: NSObject {
    
    private let TAG = "IosDialogManager"
    
    public static let shared = IosDialogManager()
    
    private override init() {
        Log.d(TAG, "init")
        super.init()
    }
    
    public func showDialog(
        title: String? = nil,
        message: String? = nil,
        preferredStyle: UIAlertController.Style = .alert,
        actions: [UIAlertAction] = [],
        textFields: [(UITextField) -> Void]? = nil,
        sourceView: UIView? = nil,
        sourceRect: CGRect? = nil,
        barButtonItem: UIBarButtonItem? = nil,
        permittedArrowDirections: UIPopoverArrowDirection = .any,
        animated: Bool = true,
        completion: ((String?, Bool, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "showDialog called with title: \(title ?? "nil"), message: \(message ?? "nil"), style: \(preferredStyle), actions: \(actions.map { $0.title ?? "nil" })")
        
        DispatchQueue.main.async {
            guard let rootViewController = self.getRootViewController() else {
                Log.e(self.TAG, "Failed to get root view controller")
                completion?(nil, false, "Failed to get root view controller")
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
                completion?(nil, true, nil)
            }
        }
    }
    
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
    public func showAlert(
        title: String?,
        message: String?,
        buttonText: String = "OK",
        completion: ((String?, Bool, String?) -> Void)? = nil
    ) {
        let okAction = UIAlertAction(title: buttonText, style: .default) { _ in
            completion?(buttonText, true, nil)
        }
        showDialog(title: title, message: message, actions: [okAction]) { result, isSuccess, errorMessage in
            if !isSuccess {
                completion?(nil, false, errorMessage)
            }
        }
    }
    
    public func showConfirmDialog(
        title: String?,
        message: String?,
        confirmTitle: String = "OK",
        cancelTitle: String = "Cancel",
        onConfirm: ((String?, Bool, String?) -> Void)? = nil,
        onCancel: ((String?, Bool, String?) -> Void)? = nil
    ) {
        let confirmAction = UIAlertAction(title: confirmTitle, style: .default) { _ in
            onConfirm?(confirmTitle, true, nil)
        }
        let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
            onCancel?(cancelTitle, true, nil)
        }
        showDialog(title: title, message: message, actions: [confirmAction, cancelAction]) { result, isSuccess, errorMessage in
            if !isSuccess {
                onConfirm?(nil, false, errorMessage)
            }
        }
    }
    
    public func showDestructiveDialog(
        title: String?,
        message: String?,
        destructiveTitle: String = "Delete",
        cancelTitle: String = "Cancel",
        onDestructive: ((String?, Bool, String?) -> Void)? = nil,
        onCancel: ((String?, Bool, String?) -> Void)? = nil
    ) {
        let destructiveAction = UIAlertAction(title: destructiveTitle, style: .destructive) { _ in
            onDestructive?(destructiveTitle, true, nil)
        }
        let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
            onCancel?(cancelTitle, true, nil)
        }
        showDialog(title: title, message: message, actions: [destructiveAction, cancelAction]) { result, isSuccess, errorMessage in
            if !isSuccess {
                onDestructive?(nil, false, errorMessage)
            }
        }
    }
    
    public func showActionSheet(
        title: String? = nil,
        message: String? = nil,
        actions: [UIAlertAction],
        sourceView: UIView,
        sourceRect: CGRect? = nil,
        animated: Bool = true,
        completion: ((String?, Bool, String?) -> Void)? = nil
    ) {
        showDialog(
            title: title,
            message: message,
            preferredStyle: .actionSheet,
            actions: actions,
            sourceView: sourceView,
            sourceRect: sourceRect,
            animated: animated,
            completion: completion
        )
    }
    
    public func showTextInputDialog(
        title: String?,
        message: String?,
        placeholder: String? = nil,
        confirmTitle: String = "OK",
        cancelTitle: String = "Cancel",
        enableConfirmWhenEmpty: Bool = true,
        onConfirm: ((String?, String?, Bool, String?) -> Void)? = nil,
        onCancel: ((String?, Bool, String?) -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            guard let rootViewController = self.getRootViewController() else {
                Log.e(self.TAG, "Failed to get root view controller")
                onConfirm?(nil, nil, false, "Failed to get root view controller")
                return
            }
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            
            let confirmAction = UIAlertAction(title: confirmTitle, style: .default) { _ in
                let inputText = alert.textFields?.first?.text
                onConfirm?(confirmTitle, inputText, true, nil)
            }
            
            // 初期状態での確認ボタンの有効/無効を設定
            confirmAction.isEnabled = enableConfirmWhenEmpty
            
            alert.addTextField { textField in
                textField.placeholder = placeholder
                
                // テキスト変更を監視してボタンの有効/無効を切り替え
                if !enableConfirmWhenEmpty {
                    NotificationCenter.default.addObserver(
                        forName: UITextField.textDidChangeNotification,
                        object: textField,
                        queue: .main
                    ) { _ in
                        confirmAction.isEnabled = !(textField.text?.isEmpty ?? true)
                    }
                }
            }
            
            let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                onCancel?(cancelTitle, true, nil)
            }
            
            alert.addAction(confirmAction)
            alert.addAction(cancelAction)
            
            rootViewController.present(alert, animated: true)
        }
    }

    public func showLoginDialog(
        title: String?,
        message: String?,
        usernamePlaceholder: String = "Username",
        passwordPlaceholder: String = "Password",
        loginTitle: String = "Login",
        cancelTitle: String = "Cancel",
        enableLoginWhenEmpty: Bool = true,
        onLogin: ((String?, String?, String?, Bool, String?) -> Void)? = nil,
        onCancel: ((String?, Bool, String?) -> Void)? = nil
    ) {
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
            
            // 初期状態でのログインボタンの有効/無効を設定
            loginAction.isEnabled = enableLoginWhenEmpty
            
            // Add username text field
            alert.addTextField { textField in
                textField.placeholder = usernamePlaceholder
                textField.textContentType = .username
                
                if !enableLoginWhenEmpty {
                    NotificationCenter.default.addObserver(
                        forName: UITextField.textDidChangeNotification,
                        object: textField,
                        queue: .main
                    ) { _ in
                        let username = alert.textFields?[0].text
                        let password = alert.textFields?[1].text
                        loginAction.isEnabled = !(username?.isEmpty ?? true) && !(password?.isEmpty ?? true)
                    }
                }
            }
            
            // Add password text field
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
                        let username = alert.textFields?[0].text
                        let password = alert.textFields?[1].text
                        loginAction.isEnabled = !(username?.isEmpty ?? true) && !(password?.isEmpty ?? true)
                    }
                }
            }
            
            let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
                onCancel?(cancelTitle, true, nil)
            }
            
            alert.addAction(loginAction)
            alert.addAction(cancelAction)
            
            rootViewController.present(alert, animated: true)
        }
    }
}
