//
//  UnityIosDialogManagerBridge.h
//
//
//  Created by Kim Jong Hyun on 2025/04/12.
//

#import <Foundation/Foundation.h>
#import <IosLibrary/IosLibrary-Swift.h> // IosLibrary の Swift ヘッダーをインポート
#import <UnityIosPlugin/UnityIosPlugin-Swift.h> // 自動生成されるSwiftヘッダーをインポート

#ifdef __cplusplus
extern "C" {
#endif

// コールバック型定義
typedef void (*DialogCallback)(const char* buttonText,
                               bool isSuccess,
                               const char* errorMessage);

typedef void (*ConfirmDialogCallback)(const char* buttonText,
                                      bool isSuccess,
                                      const char* errorMessage);

typedef void (*DestructiveDialogCallback)(const char* buttonText,
                                          bool isSuccess,
                                          const char* errorMessage);

typedef void (*ActionSheetCallback)(const char* buttonText,
                                    bool isSuccess,
                                    const char* errorMessage);

typedef void (*TextInputDialogCallback)(const char* buttonText,
                                        const char* inputText,
                                        bool isSuccess,
                                        const char* errorMessage);

typedef void (*LoginDialogCallback)(const char* buttonText,
                                    const char* username,
                                    const char* password,
                                    bool isSuccess,
                                    const char* errorMessage);

// 基本的なアラートダイアログ
void showDialog(const char* title,
                const char* message,
                const char* buttonText,
                DialogCallback callback);

// 確認ダイアログ
void showConfirmDialog(const char* title,
                       const char* message,
                       const char* confirmButtonText,
                       const char* cancelButtonText,
                       ConfirmDialogCallback callback);

// 破壊的な操作の確認ダイアログ
void showDestructiveDialog(const char* title,
                           const char* message,
                           const char* destructiveButtonText,
                           const char* cancelButtonText,
                           DestructiveDialogCallback callback);

// アクションシート
void showActionSheet(const char* title,
                     const char* message,
                     const char* options[],
                     int optionCount,
                     const char* cancelButtonText,
                     ActionSheetCallback callback);

// テキスト入力ダイアログ
void showTextInputDialog(const char* title,
                         const char* message,
                         const char* placeholder,
                         const char* confirmButtonText,
                         const char* cancelButtonText,
                         bool enableConfirmWhenEmpty,
                         TextInputDialogCallback callback);

// ログインダイアログ
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
