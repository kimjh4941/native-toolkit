import SwiftUI
import IosLibrary

struct ContentView: View {
    
    private let TAG = "ContentView"
    
    @State private var resultText = "Result will be displayed here"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("IosDialogManager Example")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding()
                
                Text(resultText)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .multilineTextAlignment(.center)
                
                // ShowAlert
                Button(action: {
                    IosDialogManager.shared.showAlert(
                        title: "Hello from iOS",
                        message: "This is a native iOS dialog!",
                        buttonText: "OK",
                        onButton: { buttonText, isSuccess, errorMessage in
                            Log.d(TAG, "[showAlert][onButton] buttonText: \(buttonText ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showAlert][onButton] buttonText: " + (buttonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        completion: { isSuccess, errorMessage in
                            Log.d(TAG, "[showAlert][completion] isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showAlert][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowAlert")
                        .buttonStyle()
                }
                
                // ShowConfirmDialog
                Button(action: {
                    IosDialogManager.shared.showConfirmDialog(
                        title: "Confirm Action",
                        message: "Are you sure you want to proceed?",
                        confirmTitle: "Yes",
                        cancelTitle: "No",
                        onConfirm: { confirmButtonText, isSuccess, errorMessage in
                            Log.d(TAG, "[showConfirmDialog][onConfirm] confirmButtonText: \(confirmButtonText ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showConfirmDialog][onConfirm] confirmButtonText: " + (confirmButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { cancelButtonText, isSuccess, errorMessage in
                            Log.d(TAG, "[showConfirmDialog][onCancel] cancelButtonText: \(cancelButtonText ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showConfirmDialog][onCancel] cancelButtonText: " + (cancelButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        completion: { isSuccess, errorMessage in
                            Log.d(TAG, "[showConfirmDialog][completion] isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showConfirmDialog][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowConfirmDialog")
                        .buttonStyle()
                }
                
                // ShowDestructiveDialog
                Button(action: {
                    IosDialogManager.shared.showDestructiveDialog(
                        title: "Delete File",
                        message: "This action cannot be undone. Are you sure?",
                        destructiveTitle: "Delete",
                        cancelTitle: "Cancel",
                        onDestructive: { destructiveButtonText, isSuccess, errorMessage in
                            Log.d(TAG, "[showDestructiveDialog][onDestructive] destructiveButtonText: \(destructiveButtonText ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showDestructiveDialog][onDestructive] destructiveButtonText: " + (destructiveButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { cancelButtonText, isSuccess, errorMessage in
                            Log.d(TAG, "[showDestructiveDialog][onCancel] cancelButtonText: \(cancelButtonText ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showDestructiveDialog][onCancel] cancelButtonText: " + (cancelButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        completion: { isSuccess, errorMessage in
                            Log.d(TAG, "[showDestructiveDialog][completion] isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showDestructiveDialog][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowDestructiveDialog")
                        .buttonStyle(backgroundColor: .red)
                }
                
                // ShowActionSheet
                Button(action: {
                    if let rootVC = IosDialogManager.shared.getRootViewController() {
                        IosDialogManager.shared.showActionSheet(
                            title: "Please select",
                            message: "Please choose an option",
                            options: ["Camera", "Photo Library", "Documents"],
                            cancelTitle: "Cancel",
                            sourceView: rootVC.view,
                            sourceRect: nil,
                            animated: true,
                            onAction: { action, isSuccess, errorMessage in
                                Log.d(TAG, "[showActionSheet][onAction] action: \(action ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                                updateResult(isSuccess: isSuccess, result: "[showActionSheet][onAction] action: " + (action ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                            },
                            completion: { isSuccess, errorMessage in
                                Log.d(TAG, "[showActionSheet][completion] isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                                updateResult(isSuccess: isSuccess, result: "[showActionSheet][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                            }
                        )
                    }
                }) {
                    Text("ShowActionSheet")
                        .buttonStyle()
                }
                
                // ShowTextInputDialog
                Button(action: {
                    IosDialogManager.shared.showTextInputDialog(
                        title: "Enter Name",
                        message: "Please enter your name",
                        placeholder: "Your name here",
                        confirmTitle: "OK",
                        cancelTitle: "Cancel",
                        enableConfirmWhenEmpty: false,
                        onConfirm: { confirmButtonText, inputText, isSuccess, errorMessage in
                            Log.d(TAG, "[showTextInputDialog][onConfirm] confirmButtonText: \(confirmButtonText ?? "nil"), inputText: \(inputText ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showTextInputDialog][onConfirm] confirmButtonText: " + (confirmButtonText ?? "nil") + ", inputText: " + (inputText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { cancelButtonText, isSuccess, errorMessage in
                            Log.d(TAG, "[showTextInputDialog][onCancel] cancelButtonText: \(cancelButtonText ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showTextInputDialog][onCancel] cancelButtonText: " + (cancelButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        completion: { isSuccess, errorMessage in
                            Log.d(TAG, "[showTextInputDialog][completion] isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showTextInputDialog][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowTextInputDialog")
                        .buttonStyle()
                }
                
                // ShowLoginDialog
                Button(action: {
                    IosDialogManager.shared.showLoginDialog(
                        title: "Login Required",
                        message: "Please enter your credentials",
                        usernamePlaceholder: "Username",
                        passwordPlaceholder: "Password",
                        loginTitle: "Login",
                        cancelTitle: "Cancel",
                        enableLoginWhenEmpty: false,
                        onLogin: { loginButtonText, username, password, isSuccess, errorMessage in
                            Log.d(TAG, "[showLoginDialog][onLogin] loginButtonText: \(loginButtonText ?? "nil"), username: \(username ?? "nil"), password: \(password ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showLoginDialog][onLogin] loginButtonText: " + (loginButtonText ?? "nil") + ", username: " + (username ?? "nil") + ", password: " + (password ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { cancelButtonText, isSuccess, errorMessage in
                            Log.d(TAG, "[showLoginDialog][onCancel] cancelButtonText: \(cancelButtonText ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showLoginDialog][onCancel] cancelButtonText: " + (cancelButtonText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        completion: { isSuccess, errorMessage in
                            Log.d(TAG, "[showLoginDialog][completion] isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "[showLoginDialog][completion] isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowLoginDialog")
                        .buttonStyle()
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func updateResult(isSuccess: Bool, result: String? ) {
        DispatchQueue.main.async {
            if isSuccess {
                resultText = "✅ \nResult: \(result ?? "nil")"
            } else {
                resultText = "❌ \nResult: \(result ?? "nil")"
            }
        }
    }
}

extension Text {
    func buttonStyle(backgroundColor: Color = .blue) -> some View {
        self.padding()
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}

#Preview {
    ContentView()
}
