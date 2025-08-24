//
//  UnityMacDialogManagerBridge.h
//  UnityMacPlugin
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
#import <Foundation/Foundation.h>
#import <MacLibrary/MacLibrary-Swift.h>
#import <UnityMacPlugin/UnityMacPlugin-Swift.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Callback for alert dialogs.
///
/// Parameters delivered to the function:
/// - buttonTitle: UTF-8 C string for the selected button title (NULL on error).
/// - buttonIndex: 0-based index of the pressed button, or -1 on error.
/// - suppressionState: `true` if suppression checkbox was ON.
/// - isSuccess: `true` if dialog executed (user chose a button). `false` for runtime errors.
/// - errorMessage: UTF-8 C string describing the error (NULL or empty if none). Lifetime: valid only during the call.
typedef void (*DialogCallback)(const char* buttonTitle,
                               int buttonIndex,
                               bool suppressionState,
                               bool isSuccess,
                               const char* errorMessage);

/// Callback for single-file open panel.
///
/// - filePaths: Array of UTF-8 C strings (NULL if cancelled or error). Valid only during the call.
/// - fileCount: Number of entries in `filePaths` (0 if cancelled, -1 if error).
/// - directoryURL: UTF-8 path of the panel's final directory (empty if unavailable).
/// - isCancelled: `true` if user cancelled.
/// - isSuccess: `true` if panel ran (even if cancelled), `false` if error prevented showing or returning.
/// - errorMessage: Error message (NULL / empty if none).
typedef void (*FileDialogCallback)(const char** filePaths,
                                   int fileCount,
                                   const char* directoryURL,
                                   bool isCancelled,
                                   bool isSuccess,
                                   const char* errorMessage);

/// Callback for multi-file open panel (same semantics as FileDialogCallback, may return >1 path).
typedef void (*MultiFileDialogCallback)(const char** filePaths,
                                        int fileCount,
                                        const char* directoryURL,
                                        bool isCancelled,
                                        bool isSuccess,
                                        const char* errorMessage);

/// Callback for single-folder selection.
typedef void (*FolderDialogCallback)(const char** folderPaths,
                                     int folderCount,
                                     const char* directoryURL,
                                     bool isCancelled,
                                     bool isSuccess,
                                     const char* errorMessage);

/// Callback for multi-folder selection.
typedef void (*MultiFolderDialogCallback)(const char** folderPaths,
                                          int folderCount,
                                          const char* directoryURL,
                                          bool isCancelled,
                                          bool isSuccess,
                                          const char* errorMessage);

/// Callback for save panel.
///
/// - filePath: Chosen file path (NULL if cancelled or error).
/// - fileCount: 1 if a path chosen, 0 if cancelled, -1 on error (retained for API symmetry).
/// - directoryURL: Directory of the chosen path, empty if none.
/// - isCancelled: `true` if user cancelled.
/// - isSuccess: `true` if panel launched (even if cancelled), `false` if runtime error.
/// - errorMessage: Error description (NULL / empty if none).
typedef void (*SaveFileDialogCallback)(const char* filePath,
                                       int fileCount,
                                       const char* directoryURL,
                                       bool isCancelled,
                                       bool isSuccess,
                                       const char* errorMessage);

/// Presents an alert dialog (bridged from Swift `MacDialogManager`).
///
/// - buttonsJson: JSON describing buttons list.
/// - optionsJson: JSON describing style & suppression.
/// - callback: See `DialogCallback`.
void showDialog(const char* title,
                const char* message,
                const char* buttonsJson,
                const char* optionsJson,
                DialogCallback callback);

/// Presents a single-file open dialog.
///
/// - allowedContentTypes: Array of filename extensions (without dot). May be NULL.
/// - contentTypesCount: Number of entries in `allowedContentTypes`.
/// - directoryPath: Initial directory path (UTF-8) or NULL.
/// - callback: See `FileDialogCallback`.
void showFileDialog(const char* title,
                    const char* message,
                    const char** allowedContentTypes,
                    int contentTypesCount,
                    const char* directoryPath,
                    FileDialogCallback callback);

/// Presents a multi-file open dialog (multiple selection allowed).
void showMultiFileDialog(const char* title,
                         const char* message,
                         const char** allowedContentTypes,
                         int contentTypesCount,
                         const char* directoryPath,
                         MultiFileDialogCallback callback);

/// Presents a single-folder selection dialog.
void showFolderDialog(const char* title,
                      const char* message,
                      const char* directoryPath,
                      FolderDialogCallback callback);

/// Presents a multi-folder selection dialog.
void showMultiFolderDialog(const char* title,
                           const char* message,
                           const char* directoryPath,
                           MultiFolderDialogCallback callback);

/// Presents a save file dialog.
///
/// - nameFieldStringValue: Default proposed filename (may be NULL).
/// - allowedContentTypes: Array of extensions (may be NULL).
void showSaveFileDialog(const char* title,
                        const char* message,
                        const char* nameFieldStringValue,
                        const char** allowedContentTypes,
                        int contentTypesCount,
                        const char* directoryPath,
                        SaveFileDialogCallback callback);

#ifdef __cplusplus
}
#endif
