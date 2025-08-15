//
//  UnityMacDialogManagerBridge.h
//  UnityMacPlugin
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
#import <Foundation/Foundation.h>
#import <MacLibrary/MacLibrary-Swift.h> // MacLibrary の Swift ヘッダーをインポート
#import <UnityMacPlugin/UnityMacPlugin-Swift.h> // 自動生成されるSwiftヘッダーをインポート

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*DialogCallback)(const char* buttonTitle,
                               int buttonIndex,
                               bool suppressionState,
                               bool isSuccess,
                               const char* errorMessage);

typedef void (*FileDialogCallback)(const char** filePaths,
                                   int fileCount,
                                   const char* directoryURL,
                                   bool isCancelled,
                                   bool isSuccess,
                                   const char* errorMessage);

typedef void (*MultiFileDialogCallback)(const char** filePaths,
                                        int fileCount,
                                        const char* directoryURL,
                                        bool isCancelled,
                                        bool isSuccess,
                                        const char* errorMessage);

typedef void (*FolderDialogCallback)(const char** folderPaths,
                                     int folderCount,
                                     const char* directoryURL,
                                     bool isCancelled,
                                     bool isSuccess,
                                     const char* errorMessage);

typedef void (*MultiFolderDialogCallback)(const char** folderPaths,
                                          int folderCount,
                                          const char* directoryURL,
                                          bool isCancelled,
                                          bool isSuccess,
                                          const char* errorMessage);

typedef void (*SaveFileDialogCallback)(const char* filePath,
                                       int fileCount,
                                       const char* directoryURL,
                                       bool isCancelled,
                                       bool isSuccess,
                                       const char* errorMessage);

void showDialog(const char* title,
                const char* message,
                const char* buttonsJson,  // JSON形式のボタン設定
                const char* optionsJson,  // JSON形式のオプション設定
                DialogCallback callback);

void showFileDialog(const char* title,
                    const char* message,
                    const char** allowedContentTypes,  // 許可されるファイル拡張子の配列（nullptrも可）
                    int contentTypesCount,             // 配列の要素数
                    const char* directoryPath,         // 初期ディレクトリパス（nullptrも可）
                    FileDialogCallback callback);

void showMultiFileDialog(const char* title,
                         const char* message,
                         const char** allowedContentTypes,  // 許可されるファイル拡張子の配列（nullptrも可）
                         int contentTypesCount,             // 配列の要素数
                         const char* directoryPath,         // 初期ディレクトリパス（nullptrも可）
                         MultiFileDialogCallback callback);

void showFolderDialog(const char* title,
                      const char* message,
                      const char* directoryPath,         // 初期ディレクトリパス（nullptrも可）
                      FolderDialogCallback callback);

void showMultiFolderDialog(const char* title,
                           const char* message,
                           const char* directoryPath,      // 初期ディレクトリパス（nullptrも可）
                           MultiFolderDialogCallback callback);

void showSaveFileDialog(const char* title,
                        const char* message,
                        const char* nameFieldStringValue,  // デフォルトファイル名（nullptrも可）
                        const char** allowedContentTypes,  // 許可されるファイル拡張子の配列（nullptrも可）
                        int contentTypesCount,             // 配列の要素数
                        const char* directoryPath,         // 初期ディレクトリパス（nullptrも可）
                        SaveFileDialogCallback callback);

#ifdef __cplusplus
}
#endif
