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
                    IosDialogManager.shared.showAlert(title: "Basic Alert", message: "This is a basic alert dialog", buttonText: "Confirm") { result, isSuccess, errorMessage in
                        Log.d(TAG, "showAlert - result: \(result ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                        updateResult(isSuccess: isSuccess, result: "showAlert - result: " + (result ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                    }
                }) {
                    Text("ShowAlert")
                        .buttonStyle()
                }
                
                // ShowConfirmDialog
                Button(action: {
                    IosDialogManager.shared.showConfirmDialog(
                        title: "Confirm",
                        message: "Do you want to proceed with this action?",
                        confirmTitle: "Proceed",
                        cancelTitle: "Cancel",
                        onConfirm: { result, isSuccess, errorMessage in
                            Log.d(TAG, "showConfirmDialog - result: \(result ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "showConfirmDialog - result: " + (result ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { result, isSuccess, errorMessage in
                            Log.d(TAG, "showConfirmDialog - result: \(result ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "showConfirmDialog - result: " + (result ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowConfirmDialog")
                        .buttonStyle()
                }
                
                // ShowDestructiveDialog
                Button(action: {
                    IosDialogManager.shared.showDestructiveDialog(
                        title: "Warning",
                        message: "This action cannot be undone. Are you sure you want to delete?",
                        destructiveTitle: "Delete",
                        cancelTitle: "Cancel",
                        onDestructive: { result, isSuccess, errorMessage in
                            Log.d(TAG, "showDestructiveDialog - result: \(result ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "showDestructiveDialog - result: " + (result ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { result, isSuccess, errorMessage in
                            Log.d(TAG, "showDestructiveDialog - result: \(result ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "showDestructiveDialog - result: " + (result ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowDestructiveDialog")
                        .buttonStyle(backgroundColor: .red)
                }
                
                // ShowActionSheet
                Button(action: {
                    let actions = [
                        UIAlertAction(title: "Option 1", style: .default) { _ in
                            Log.d(TAG, "showActionSheet - Option 1 selected")
                            updateResult(isSuccess: true, result: "showActionSheet - result: Option 1, isSuccess: true, errorMessage: nil")
                        },
                        UIAlertAction(title: "Option 2", style: .default) { _ in
                            Log.d(TAG, "showActionSheet - Option 2 selected")
                            updateResult(isSuccess: true, result: "showActionSheet - result: Option 2, isSuccess: true, errorMessage: nil")
                        },
                        UIAlertAction(title: "Delete", style: .destructive) { _ in
                            Log.d(TAG, "showActionSheet - Delete selected")
                            updateResult(isSuccess: true, result: "showActionSheet - result: Delete, isSuccess: true, errorMessage: nil")
                        },
                        UIAlertAction(title: "Cancel", style: .cancel) { _ in
                            Log.d(TAG, "showActionSheet - Cancel selected")
                            updateResult(isSuccess: true, result: "showActionSheet - result: Cancel, isSuccess: true, errorMessage: nil")
                        }
                    ]
                    
                    if let rootVC = IosDialogManager.shared.getRootViewController() {
                        IosDialogManager.shared.showActionSheet(
                            title: "Please select",
                            message: "Please choose an option",
                            actions: actions,
                            sourceView: rootVC.view
                        ) { result, isSuccess, errorMessage in
                            Log.d(TAG, "showActionSheet - result: \(result ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            if !isSuccess {
                                updateResult(isSuccess: isSuccess, result: "showActionSheet - Error: \(errorMessage ?? "Unknown error")")
                            }
                        }
                    }
                }) {
                    Text("ShowActionSheet")
                        .buttonStyle()
                }
                
                // ShowTextInputDialog
                Button(action: {
                    IosDialogManager.shared.showTextInputDialog(
                        title: "Text Input",
                        message: "Please enter your name",
                        placeholder: "Enter text",
                        confirmTitle: "OK",
                        cancelTitle: "Cancel",
                        enableConfirmWhenEmpty: false,
                        onConfirm: { result, inputText, isSuccess, errorMessage in
                            Log.d(TAG, "showTextInputDialog - result: \(result ?? "nil"), inputText: \(inputText ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "showTextInputDialog - result: " + (result ?? "nil") + ", inputText: " + (inputText ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { result, isSuccess, errorMessage in
                            Log.d(TAG, "showTextInputDialog - result: \(result ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "showTextInputDialog - result: " + (result ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        }
                    )
                }) {
                    Text("ShowTextInputDialog")
                        .buttonStyle()
                }
                
                // ShowLoginDialog
                Button(action: {
                    IosDialogManager.shared.showLoginDialog(
                        title: "Login",
                        message: "Please enter your credentials",
                        usernamePlaceholder: "Username",
                        passwordPlaceholder: "Password",
                        loginTitle: "Login",
                        cancelTitle: "Cancel",
                        enableLoginWhenEmpty: false,
                        onLogin: { result, username, password, isSuccess, errorMessage in
                            Log.d(TAG, "showLoginDialog - result: \(result  ?? "nil"), username: \(username ?? "nil"), password: \(password ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "showLoginDialog - result: " + (result ?? "nil") + ", username: " + (username ?? "nil") + ", password: " + (password ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
                        },
                        onCancel: { result, isSuccess, errorMessage in
                            Log.d(TAG, "showLoginDialog - result: \(result ?? "nil"), isSuccess: \(isSuccess), errorMessage: \(errorMessage ?? "nil")")
                            updateResult(isSuccess: isSuccess, result: "showLoginDialog - result: " + (result ?? "nil") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? "nil"))
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
