/**
 * @file WindowsDialogManagerInternal.h
 * @brief Windows Dialog Manager implementation (internal)
 * @details
 *  Implements various dialogs (alert, file open/save, folder selection)
 *  using Win32 Common Dialogs and IFileOpenDialog (COM).
 *  The exported C functions live in src/Bridge/DialogBridge.cpp and call
 *  this class; library code must not include the public Dialog header for
 *  the implementation.
 */
#pragma once
#include <windows.h>
#include <commdlg.h> // GetOpenFileNameW, GetSaveFileNameW, CommDlgExtendedError
#include <string>
#include <memory>
#include <shobjidl.h> // IFileDialog, IFileOpenDialog
#include "Common/CommonInternal.h"

namespace {
const wchar_t* TAG = L"WindowsDialogManager";
}


/**
 * @class WindowsDialogManager
 * @brief Singleton class that shows Windows dialogs.
 * @details
 *  Internally used by public exported functions (showXxxDialog).
 *  Copy/assignment is disabled.
 */
class WindowsDialogManager
{
public:
    /** @brief Get singleton instance. */
    static WindowsDialogManager& Instance()
    {
        static WindowsDialogManager instance;
        return instance;
    }

    WindowsDialogManager(const WindowsDialogManager&) = delete;      ///< Non-copyable
    WindowsDialogManager& operator=(const WindowsDialogManager&) = delete; ///< Non-assignable

    /**
     * @brief Show an alert (message box).
     * @param title Dialog title.
     * @param message Dialog body text.
     * @param buttons Button flags.
     * @param icon Icon flags.
     * @param defbutton Default button.
     * @param options Additional options.
     * @param pError Optional out error code. 0 on success, GetLastError() on failure.
     * @return Button ID clicked by the user. 0 on failure.
     */
    int ShowAlertDialog(
        const wchar_t* title,
        const wchar_t* message,
        UINT buttons,
        UINT icon,
        UINT defbutton,
        UINT options,
        DWORD* pError = nullptr  // Optional
    )
    {
        DFLog(TAG, L"ShowAlertDialog title: %ls, message: %ls, buttons: %d, icon: %d, defbutton: %d, options: %d, pError: %p", title, message, buttons, icon, defbutton, options, pError);
        
        UINT type = buttons | icon | defbutton | options;
        int result = MessageBoxW(nullptr, message, title, type);

        if (result == 0) {
            DWORD lastError = GetLastError();
            if (pError) {
                *pError = lastError;
            }
            // Always log on error
            DFLog(TAG, L"ShowAlertDialog: MessageBoxW failed. GetLastError: %lu", lastError);
        }
        else if (pError) {
            *pError = 0;
        }

        return result;
    }

    /**
     * @brief Show a single file open dialog.
     * @param buffer Output buffer for the selected file path.
     * @param buffer_size Size of buffer in wchar_t units.
     * @param filter Win32 filter string.
     * @param pError Out error code. 0=success, -1=canceled, otherwise CommDlgExtendedError.
     * @return TRUE on success or cancel, FALSE on failure.
     */
    BOOL ShowFileDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* filter,
        DWORD* pError = nullptr  // Optional
    )
    {
        DFLog(TAG, L"ShowFileDialog buffer_size: %lu, filter: %ls, pError: %p", buffer_size, filter ? filter : L"null", pError);

        ZeroMemory(buffer, buffer_size * sizeof(wchar_t));
        OPENFILENAMEW ofn = { 0 };
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = nullptr;
        ofn.lpstrFile = buffer;
        ofn.nMaxFile = buffer_size;
        ofn.lpstrFilter = filter ? filter : L"All Files\0*.*\0";
        ofn.nFilterIndex = 1;
        ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST;

        BOOL result = GetOpenFileNameW(&ofn);
        if (!result) {
            DWORD err = CommDlgExtendedError();
            if (err != 0) {
                // If an error occurred
                if (pError) {
                    *pError = err;
                }
                DFLog(TAG, L"ShowFileDialog: GetOpenFileNameW failed. CommDlgExtendedError: 0x%08lx", err);
            }
            else
            {
                // If the user canceled
                if (pError) {
                    *pError = -1;
                }
                DLog(TAG, L"File selection was canceled.");
                result = TRUE; // Return TRUE on cancel
            }
            buffer[0] = L'\0';
        }
        return result;
    }

    /**
     * @brief Show a multi-select file open dialog.
     * @param buffer Output buffer for the selection.
     * @param buffer_size Size of buffer in wchar_t units.
     * @param filter Win32 filter string.
     * @param pError Out error code. 0=success, -1=canceled, otherwise CommDlgExtendedError.
     * @return Number of selected items. 0=canceled, -1=error, otherwise >=1.
     */
    int ShowMultiFileDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* filter,
        DWORD* pError = nullptr  // Optional
    )
    {
        DFLog(TAG, L"ShowMultiFileDialog buffer_size: %lu, filter: %ls, pError: %p", buffer_size, filter ? filter : L"null", pError);

        ZeroMemory(buffer, buffer_size * sizeof(wchar_t));
        OPENFILENAMEW ofn = { 0 };
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = nullptr;
        ofn.lpstrFile = buffer;
        ofn.nMaxFile = buffer_size;
        ofn.lpstrFilter = filter ? filter : L"All Files\0*.*\0";
        ofn.nFilterIndex = 1;
        ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_ALLOWMULTISELECT | OFN_EXPLORER;

        BOOL result = GetOpenFileNameW(&ofn);
        if (!result) {
            buffer[0] = L'\0';
            DWORD err = CommDlgExtendedError();
            if (err != 0) {
                // If an error occurred
                if (pError) {
                    *pError = err;
                }
                DFLog(TAG, L"ShowMultiFileDialog: GetOpenFileNameW failed. CommDlgExtendedError: 0x%08lx", err);
                return -1; // Return -1 on error
            }
            else
            {
                // If the user canceled
                if (pError) {
                    *pError = -1;
                }
                DLog(TAG, L"Multi-file selection was canceled.");
                return 0; // Return 0 on cancel
            }
        }

        // On success
        if (pError) {
            *pError = 0;
        }

        // For multi-file selection, the first is the folder name, followed by file names separated by \0
        int count = 0;
        wchar_t* p = buffer;
        while (*p) {
            ++count;
            // Move to next string
            p += wcslen(p) + 1;
        }
        // If only one, it's the full path; if more, first is folder name, then file names
        return count;
    }

    /**
     * @brief Show a single folder selection dialog.
     * @param buffer Output buffer for the selected folder path.
     * @param buffer_size Size of buffer in wchar_t units.
     * @param title Dialog title.
     * @param pError Out error code. 0=success, -1=canceled, otherwise HRESULT.
     * @return TRUE on success or cancel, FALSE on failure.
     */
    BOOL ShowFolderDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* title = L"Select Folder",
        DWORD * pError = nullptr  // Optional
    )
    {
        DFLog(TAG, L"ShowFolderDialog buffer_size: %lu, title: %ls, pError: %p", buffer_size, title ? title : L"null", pError);

        // COM initialization (not needed if already initialized by caller)
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        bool needUninit = SUCCEEDED(hr);
        if (FAILED(hr) && hr != RPC_E_CHANGED_MODE)
        {
            buffer[0] = L'\0';
            if (pError) {
                *pError = hr;
            }
            DFLog(TAG, L"ShowFolderDialog: CoInitializeEx failed. hr=0x%08lx", hr);
            return FALSE;
        }

        IFileOpenDialog* pFileOpen = nullptr;
        hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pFileOpen));
        if (FAILED(hr)) {
            if (needUninit) CoUninitialize();
            buffer[0] = L'\0';
            if (pError) {
                *pError = hr;
            }
            DFLog(TAG, L"ShowFolderDialog: CoCreateInstance failed. hr=0x%08lx", hr);
            return FALSE;
        }

        // Set dialog title
        if (title) pFileOpen->SetTitle(title);

        // Folder selection mode
        DWORD dwOptions;
        pFileOpen->GetOptions(&dwOptions);
        pFileOpen->SetOptions(dwOptions | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM);

        // Show dialog
        hr = pFileOpen->Show(nullptr);
        if (SUCCEEDED(hr)) {
            IShellItem* pItem = nullptr;
            hr = pFileOpen->GetResult(&pItem);
            if (SUCCEEDED(hr)) {
                PWSTR pszFolderPath = nullptr;
                hr = pItem->GetDisplayName(SIGDN_FILESYSPATH, &pszFolderPath);
                if (SUCCEEDED(hr)) {
                    size_t pathLen = wcslen(pszFolderPath);
                    if (pathLen + 1 > buffer_size) {
                        // Buffer too small
                        buffer[0] = L'\0';
                        if (pError) {
                            *pError = ERROR_INSUFFICIENT_BUFFER;
                        }
                        DFLog(TAG, L"ShowFolderDialog: buffer too small. required=%zu, buffer_size=%lu", pathLen + 1, buffer_size);
                        CoTaskMemFree(pszFolderPath);
                        pItem->Release();
                        pFileOpen->Release();
                        if (needUninit) CoUninitialize();
                        return FALSE;
                    }
                    wcsncpy_s(buffer, buffer_size, pszFolderPath, _TRUNCATE);
                    if (pError) {
                        *pError = 0;
                    }
                    CoTaskMemFree(pszFolderPath);
                    pItem->Release();
                    pFileOpen->Release();
                    if (needUninit) CoUninitialize();
                    return TRUE;
                }
                if (pszFolderPath) CoTaskMemFree(pszFolderPath);
                pItem->Release();
            }
        }
        pFileOpen->Release();
        buffer[0] = L'\0';
        if (needUninit) CoUninitialize();
        // Return TRUE on cancel, FALSE on error
        if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
            if (pError) {
                *pError = -1;
            }
            DLog(TAG, L"Folder selection was canceled.");
            return TRUE;
        }
        else {
            if (pError) {
                *pError = hr;
            }
            DFLog(TAG, L"ShowFolderDialog: failed. hr=0x%08lx", hr);
            return FALSE;
        }
    }

    /**
     * @brief Show a multi-select folder dialog.
     * @param buffer Output buffer for selected folder paths (\0-separated, ends with \0\0).
     * @param buffer_size Size of buffer in wchar_t units.
     * @param title Dialog title.
     * @param pError Out error code. 0=success, -1=canceled, otherwise HRESULT.
     * @return Number of selected folders. 0=canceled, -1=error, otherwise >=1.
     */
    int ShowMultiFolderDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* title = L"Select Folder",
        DWORD* pError = nullptr  // Optional
    )
    {
        DFLog(TAG, L"ShowMultiFolderDialog buffer_size: %lu, title: %ls, pError: %p", buffer_size, title ? title : L"null", pError);

        ZeroMemory(buffer, buffer_size * sizeof(wchar_t));

        // COM initialization (not needed if already initialized by caller)
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        bool needUninit = SUCCEEDED(hr);
        if (FAILED(hr) && hr != RPC_E_CHANGED_MODE)
        {
            buffer[0] = L'\0';
            if (pError) {
                *pError = hr;
            }
            DFLog(TAG, L"ShowMultiFolderDialog: CoInitializeEx failed. hr=0x%08lx", hr);
            return -1;
        }

        IFileOpenDialog* pFileOpen = nullptr;
        hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pFileOpen));
        if (FAILED(hr)) {
            if (needUninit) CoUninitialize();
            buffer[0] = L'\0';
            if (pError) {
                *pError = hr;
            }
            DFLog(TAG, L"ShowMultiFolderDialog: CoCreateInstance failed. hr=0x%08lx", hr);
            return -1;
        }

        // Set dialog title
        if (title) pFileOpen->SetTitle(title);

        // Folder selection + multi-select
        DWORD dwOptions;
        pFileOpen->GetOptions(&dwOptions);
        pFileOpen->SetOptions(dwOptions | FOS_PICKFOLDERS | FOS_ALLOWMULTISELECT | FOS_FORCEFILESYSTEM);

        // Show dialog
        hr = pFileOpen->Show(nullptr);
        if (SUCCEEDED(hr)) {
            IShellItemArray* pItems = nullptr;
            hr = pFileOpen->GetResults(&pItems);
            if (SUCCEEDED(hr)) {
                DWORD count = 0;
                pItems->GetCount(&count);
                wchar_t* p = buffer;
                DWORD remain = buffer_size;
                bool bufferOverflow = false;
                for (DWORD i = 0; i < count; ++i) {
                    IShellItem* pItem = nullptr;
                    if (SUCCEEDED(pItems->GetItemAt(i, &pItem))) {
                        PWSTR pszPath = nullptr;
                        if (SUCCEEDED(pItem->GetDisplayName(SIGDN_FILESYSPATH, &pszPath))) {
                            size_t len = wcslen(pszPath);
                            if (len + 1 < remain) {
                                wmemcpy(p, pszPath, len + 1); // +1 for null terminator
                                p += len + 1;
                                remain -= (DWORD)(len + 1);
                            }
                            else {
                                // Buffer too small
                                bufferOverflow = true;
                                if (pError) {
                                    *pError = ERROR_INSUFFICIENT_BUFFER;
                                }
                                DFLog(TAG, L"ShowMultiFolderDialog: buffer too small for folder %lu. required=%zu, remain=%lu", i + 1, len + 1, remain);
                                CoTaskMemFree(pszPath);
                                pItem->Release();
                                break;
                            }
                            CoTaskMemFree(pszPath);
                        }
                        pItem->Release();
                    }
                }
                pItems->Release();
                if (needUninit) CoUninitialize();
                // For multi-selection, items are separated by \0, ending with \0\0
                if (!bufferOverflow && count > 0 && remain > 0) *p = L'\0';
                if (bufferOverflow) {
                    buffer[0] = L'\0';
                    return -1;
                }
                // On success
                if (pError) {
                    *pError = 0;
                }
                return (int)count;
            }
        }
        pFileOpen->Release();
        buffer[0] = L'\0';
        if (needUninit) CoUninitialize();
        // Return 0 on cancel, -1 on error
        if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
            if (pError) {
                *pError = -1;
            }
            DLog(TAG, L"Multi-folder selection was canceled.");
            return 0;
        }
        else {
            if (pError) {
                *pError = hr;
            }
            DFLog(TAG, L"ShowMultiFolderDialog: failed. hr=0x%08lx", hr);
            return -1;
        }
    }

    /**
     * @brief Show a save file dialog.
     * @param buffer Output buffer for the destination file path.
     * @param buffer_size Size of buffer in wchar_t units.
     * @param filter Win32 filter string.
     * @param def_ext Default extension.
     * @param pError Out error code. 0=success, -1=canceled, otherwise CommDlgExtendedError.
     * @return TRUE on success or cancel, FALSE on failure.
     */
    BOOL ShowSaveFileDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* filter,
        const wchar_t* def_ext = nullptr,
        DWORD* pError = nullptr  // Optional
    )
    {
        DFLog(TAG, L"ShowSaveFileDialog buffer_size: %lu, filter: %ls, def_ext: %ls, pError: %p", buffer_size, filter ? filter : L"null", def_ext ? def_ext : L"null", pError);

        ZeroMemory(buffer, buffer_size * sizeof(wchar_t));
        OPENFILENAMEW ofn = { 0 };
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = nullptr;
        ofn.lpstrFile = buffer;
        ofn.nMaxFile = buffer_size;
        ofn.lpstrFilter = filter ? filter : L"All Files\0*.*\0";
        ofn.nFilterIndex = 1;
        ofn.Flags = OFN_PATHMUSTEXIST | OFN_OVERWRITEPROMPT;
        ofn.lpstrDefExt = def_ext;

        BOOL result = GetSaveFileNameW(&ofn);
        if (!result) {
            DWORD err = CommDlgExtendedError();
            if (err != 0) {
                // If an error occurred
                if (pError) {
                    *pError = err;
                }
                DFLog(TAG, L"ShowSaveFileDialog: GetSaveFileNameW failed. CommDlgExtendedError: 0x%08lx", err);
            }
            else
            {
                // If the user canceled
                if (pError) {
                    *pError = -1;
                }
                DLog(TAG, L"Save file selection was canceled.");
                result = TRUE; // Return TRUE on cancel
            }
            buffer[0] = L'\0';
        }
        else {
            // On success
            if (pError) {
                *pError = 0;
            }
        }
        return result;
    }

private:
    // Constructor is private
    WindowsDialogManager() = default;
};
