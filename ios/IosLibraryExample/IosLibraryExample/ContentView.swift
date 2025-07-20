//
//  ContentView.swift
//  IosLibraryExample
//
//  Created by Kim Jong Hyun on 2025/04/12.
//

import SwiftUI
import IosLibrary

struct ContentView: View {
    @State private var resultText = "結果がここに表示されます"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("IosDialogManager テスト")
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
                    IosDialogManager.shared.showAlert(title: "基本アラート", message: "これは基本的なアラートダイアログです", buttonText: "確認") { result, isSuccess, errorMessage in
                        updateResult(isSuccess: isSuccess, result: "showAlert - result: " + (result ?? "") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? ""))
                    }
                }) {
                    Text("ShowAlert")
                        .buttonStyle()
                }
                
                // ShowConfirmDialog
                Button(action: {
                    IosDialogManager.shared.showConfirmDialog(
                        title: "確認",
                        message: "この操作を実行しますか？",
                        confirmTitle: "実行",
                        cancelTitle: "キャンセル",
                        onConfirm: { result, isSuccess, errorMessage in
                            updateResult(isSuccess: isSuccess, result: "showConfirmDialog - result: " + (result ?? "") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? ""))
                        },
                        onCancel: { result, isSuccess, errorMessage in
                            updateResult(isSuccess: isSuccess, result: "showConfirmDialog - result: " + (result ?? "") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? ""))
                        }
                    )
                }) {
                    Text("ShowConfirmDialog")
                        .buttonStyle()
                }
                
                // ShowDestructiveDialog
                Button(action: {
                    IosDialogManager.shared.showDestructiveDialog(
                        title: "警告",
                        message: "この操作は取り消せません。本当に削除しますか？",
                        destructiveTitle: "削除",
                        cancelTitle: "キャンセル",
                        onDestructive: { result, isSuccess, errorMessage in
                            updateResult(isSuccess: isSuccess, result: "showDestructiveDialog - result: " + (result ?? "") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? ""))
                        },
                        onCancel: { result, isSuccess, errorMessage in
                            updateResult(isSuccess: isSuccess, result: "showDestructiveDialog - result: " + (result ?? "") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? ""))
                        }
                    )
                }) {
                    Text("ShowDestructiveDialog")
                        .buttonStyle(backgroundColor: .red)
                }
                
                // ShowActionSheet
                Button(action: {
                    let actions = [
                        UIAlertAction(title: "オプション1", style: .default) { _ in
                            updateResult(isSuccess: true, result: "showActionSheet - result: オプション1, isSuccess: true, errorMessage: nil")
                        },
                        UIAlertAction(title: "オプション2", style: .default) { _ in
                            updateResult(isSuccess: true, result: "showActionSheet - result: オプション2, isSuccess: true, errorMessage: nil")
                        },
                        UIAlertAction(title: "削除", style: .destructive) { _ in
                            updateResult(isSuccess: true, result: "showActionSheet - result: 削除, isSuccess: true, errorMessage: nil")
                        },
                        UIAlertAction(title: "キャンセル", style: .cancel) { _ in
                            updateResult(isSuccess: true, result: "showActionSheet - result: キャンセル, isSuccess: true, errorMessage: nil")
                        }
                    ]
                    
                    if let rootVC = IosDialogManager.shared.getRootViewController() {
                        IosDialogManager.shared.showActionSheet(
                            title: "選択してください",
                            message: "オプションを選択してください",
                            actions: actions,
                            sourceView: rootVC.view
                        ) { result, isSuccess, errorMessage in
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
                        title: "テキスト入力",
                        message: "名前を入力してください",
                        placeholder: "テキストを入力してください",
                        confirmTitle: "OK",
                        cancelTitle: "キャンセル",
                        enableConfirmWhenEmpty: false,
                        onConfirm: { result, inputText, isSuccess, errorMessage in
                            updateResult(isSuccess: isSuccess, result: "showTextInputDialog - result: " + (result ?? "") + ", inputText: " + (inputText ?? "") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? ""))
                        },
                        onCancel: { result, isSuccess, errorMessage in
                            updateResult(isSuccess: isSuccess, result: "showTextInputDialog - result: " + (result ?? "") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? ""))
                        }
                    )
                }) {
                    Text("ShowTextInputDialog")
                        .buttonStyle()
                }
                
                // ShowLoginDialog
                Button(action: {
                    IosDialogManager.shared.showLoginDialog(
                        title: "ログイン",
                        message: "認証情報を入力してください",
                        usernamePlaceholder: "ユーザー名",
                        passwordPlaceholder: "パスワード",
                        loginTitle: "ログイン",
                        cancelTitle: "キャンセル",
                        enableLoginWhenEmpty: false,
                        onLogin: { result, username, password, isSuccess, errorMessage in
                            updateResult(isSuccess: isSuccess, result: "showLoginDialog - result: " + (result ?? "") + ", username: " + (username ?? "") + ", password: " + (password ?? "") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? ""))
                        },
                        onCancel: { result, isSuccess, errorMessage in
                            updateResult(isSuccess: isSuccess, result: "showLoginDialog - result: " + (result ?? "") + ", isSuccess: " + (isSuccess ? "true" : "false") + ", errorMessage: " + (errorMessage ?? ""))
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
                resultText = "✅ \n結果: \(result ?? "nil")"
            } else {
                resultText = "❌ \n結果: \(result ?? "nil")"
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
