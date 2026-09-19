/**
 * @file WindowsDialogManager.h
 * @brief Public API declarations for the Windows Dialog Manager
 * @details
 *  Provides C-style exported APIs to display common Windows dialogs
 *  (alert, file open/save, and folder selection). Intended to be consumed
 *  from C++/WinRT (WinUI 3) and other languages.
 */
#pragma once

#ifdef WINDOWSLIBRARY_EXPORTS
#define WINDOWSDIALOGMANAGER_API __declspec(dllexport)
#else
#define WINDOWSDIALOGMANAGER_API __declspec(dllimport)
#endif

/**
 * @brief Displays a message box (alert dialog).
 * @param title   The dialog title string.
 * @param message The dialog message/body string.
 * @param buttons Button flags (e.g., MB_OK, MB_OKCANCEL, MB_YESNO).
 * @param icon    Icon flags (e.g., MB_ICONINFORMATION, MB_ICONWARNING).
 * @param defbutton Default button (e.g., MB_DEFBUTTON1, MB_DEFBUTTON2).
 * @param options Additional options (e.g., MB_APPLMODAL).
 * @param pError  Optional out pointer for an error code.
 *                - On success: 0
 *                - On failure: GetLastError() value
 * @return The identifier of the button the user clicked (IDOK/IDCANCEL/IDYES/IDNO, etc.). 0 on failure.
 */
extern "C" WINDOWSDIALOGMANAGER_API
int showAlertDialog(
    const wchar_t* title,
    const wchar_t* message,
    UINT buttons,
    UINT icon,
    UINT defbutton,
    UINT options,
    DWORD* pError
);

/**
 * @brief Displays a single file open dialog.
 * @param buffer       Output buffer to receive the selected file's full path.
 * @param buffer_size  Number of wchar_t elements in buffer (including terminator).
 * @param filter       Win32 filter string (e.g., L"Text Files\0*.txt\0All Files\0*.*\0").
 * @param pError       Optional out pointer for an error code.
 *                     - Success: 0
 *                     - Canceled: -1 (0xFFFFFFFF)
 *                     - Failure: CommDlgExtendedError() value
 * @return TRUE on success or cancel, FALSE on failure.
 * @note The function also returns TRUE when the dialog is canceled. Check pError to distinguish.
 */
extern "C" WINDOWSDIALOGMANAGER_API
BOOL showFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    DWORD* pError
);

/**
 * @brief Displays a multi-select file open dialog.
 * @param buffer       Output buffer for the selection.
 *                     - Multi-select: folder\0file1\0file2\0...\0\0
 *                     - Single-select: fullpath\0
 * @param buffer_size  Number of wchar_t elements in buffer (including terminator).
 * @param filter       Win32 filter string.
 * @param pError       Optional out pointer for an error code.
 *                     - Success: 0
 *                     - Canceled: -1 (0xFFFFFFFF)
 *                     - Failure: CommDlgExtendedError() value
 * @return Count of selected items. 0 if canceled, -1 on failure, otherwise >= 1.
 */
extern "C" WINDOWSDIALOGMANAGER_API
int showMultiFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    DWORD* pError
);

/**
 * @brief Displays a save file dialog.
 * @param buffer       Output buffer to receive the destination file path.
 * @param buffer_size  Number of wchar_t elements in buffer (including terminator).
 * @param filter       Win32 filter string.
 * @param def_ext      Default file extension (e.g., L"txt").
 * @param pError       Optional out pointer for an error code.
 *                     - Success: 0
 *                     - Canceled: -1 (0xFFFFFFFF)
 *                     - Failure: CommDlgExtendedError() value
 * @return TRUE on success or cancel, FALSE on failure.
 */
extern "C" WINDOWSDIALOGMANAGER_API
BOOL showSaveFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    const wchar_t* def_ext,
    DWORD* pError
);

/**
 * @brief Displays a single folder selection dialog.
 * @param buffer       Output buffer to receive the selected folder path.
 * @param buffer_size  Number of wchar_t elements in buffer (including terminator).
 * @param title        Dialog title.
 * @param pError       Optional out pointer for an error code.
 *                     - Success: 0
 *                     - Canceled: -1 (0xFFFFFFFF)
 *                     - Failure: HRESULT or ERROR_INSUFFICIENT_BUFFER
 * @return TRUE on success or cancel, FALSE on failure.
 */
extern "C" WINDOWSDIALOGMANAGER_API
BOOL showFolderDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* title,
    DWORD* pError
);

/**
 * @brief Displays a multi-select folder dialog.
 * @param buffer       Output buffer for selected folder paths (\0-separated, ends with \0\0).
 * @param buffer_size  Number of wchar_t elements in buffer (including terminator).
 * @param title        Dialog title.
 * @param pError       Optional out pointer for an error code.
 *                     - Success: 0
 *                     - Canceled: -1 (0xFFFFFFFF)
 *                     - Failure: HRESULT or ERROR_INSUFFICIENT_BUFFER
 * @return Count of selected folders. 0 if canceled, -1 on failure, otherwise >= 1.
 */
extern "C" WINDOWSDIALOGMANAGER_API
int showMultiFolderDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* title,
    DWORD* pError
);