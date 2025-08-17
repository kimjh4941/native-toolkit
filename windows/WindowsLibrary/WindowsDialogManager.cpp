#include "pch.h"
#include "afxdialogex.h"
#include <windows.h>
#include <string>
#include "resource.h" // Header file containing resource IDs
#include "common.h"
#include "WindowsDialogManager.h"
#include <memory>
#include <shobjidl.h> // IFileDialog, IFileOpenDialog

static const wchar_t* TAG = L"WindowsDialogManager";

// Dialog class implementation
class WindowsDialogManager
{
public:
    // Get singleton instance
    static WindowsDialogManager& Instance()
    {
        static WindowsDialogManager instance;
        return instance;
    }

    // Disable copy and move
    WindowsDialogManager(const WindowsDialogManager&) = delete;
    WindowsDialogManager& operator=(const WindowsDialogManager&) = delete;

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

    BOOL ShowFileDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* filter,
        DWORD* pError = nullptr  // Optional
    )
    {
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

    int ShowMultiFileDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* filter,
        DWORD* pError = nullptr  // Optional
    )
    {
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

    BOOL ShowSaveFileDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* filter,
        const wchar_t* def_ext = nullptr,
        DWORD* pError = nullptr  // Optional
    )
    {
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

    BOOL ShowFolderDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* title = L"Select Folder",
        DWORD * pError = nullptr  // Optional
    )
    {
        // COM initialization (not needed if already initialized by caller)
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        bool needUninit = SUCCEEDED(hr);

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

    int ShowMultiFolderDialog(
        wchar_t* buffer,
        DWORD buffer_size,
        const wchar_t* title = L"Select Folder",
        DWORD* pError = nullptr  // Optional
    )
    {
        ZeroMemory(buffer, buffer_size * sizeof(wchar_t));

        // COM initialization (not needed if already initialized by caller)
        HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
        bool needUninit = SUCCEEDED(hr);

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

private:
    // Constructor is private
    WindowsDialogManager(CWnd* pParent = nullptr)
        : m_dialogEx(IDD_DIALOG, pParent)
    {

    }

    CDialogEx m_dialogEx;
};

int showAlertDialog(
    const wchar_t* title,
    const wchar_t* message,
    UINT buttons,
    UINT icon,
    UINT defbutton,
    UINT options,
    DWORD* pError
)
{
    DFLog(TAG, L"showAlertDialog title: %ls, message: %ls, buttons: %d, icon: %d, defbutton: %d, options: %d", title, message, buttons, icon, defbutton, options);
    DFLog(TAG, L"showAlertDialog IDD_DIALOG: %d", IDD_DIALOG);

    int result = WindowsDialogManager::Instance().ShowAlertDialog(title, message, buttons, icon, defbutton, options, pError);
    if (result == 0) {
        DLog(TAG, L"Failed to display dialog.");
    }
    else if (result == IDOK) {
        DLog(TAG, L"User clicked OK.");
    }
    else if (result == IDCANCEL) {
        DLog(TAG, L"User clicked Cancel.");
    }
    else if (result == IDYES) {
        DLog(TAG, L"User clicked Yes.");
    }
    else if (result == IDNO) {
        DLog(TAG, L"User clicked No.");
    }
    else {
        DFLog(TAG, L"Other result: %d", result);
    }
    DFLog(TAG, L"ShowAlertDialog returned %d", result);
    return result;
}

BOOL showFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    DWORD* pError
)
{
    DLog(TAG, L"showFileDialog");

    BOOL result = WindowsDialogManager::Instance().ShowFileDialog(buffer, buffer_size, filter, pError);
    if (result)
    {
        DFLog(TAG, L"Selected file: %ls", buffer);
    }
    else
    {
        DLog(TAG, L"Error occurred during file selection.");
    }
    DFLog(TAG, L"ShowFileDialog returned %d", result);
    return result;
}

int showMultiFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    DWORD* pError
)
{
    DLog(TAG, L"showMultiFileDialog");

    int count = WindowsDialogManager::Instance().ShowMultiFileDialog(buffer, buffer_size, filter, pError);
    DFLog(TAG, L"count(folder name + file count): %d", count);
    if (count > 0)
    {
        // For multi-file selection, the first is the folder name, followed by file names separated by \0
        wchar_t* p = buffer;
        if (count == 1)
        {
            DFLog(TAG, L"Selected file: %ls", p);
        }
        else
        {
            std::wstring folder = p;
            p += wcslen(p) + 1;
            for (int i = 1; i < count; ++i)
            {
                std::wstring fullpath = folder + L"\\" + p;
                DFLog(TAG, L"Selected file %d: %ls", i, fullpath.c_str());
                p += wcslen(p) + 1;
            }
        }
    }
    else
    {
        if (count < 0)
        {
            DFLog(TAG, L"Error occurred during multi-file selection.");
        }
        else
        {
            DFLog(TAG, L"Multi-file selection was canceled.");
        }
    }
    return count;
}

BOOL showSaveFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    const wchar_t* def_ext,
    DWORD* pError
)
{
    DLog(TAG, L"showSaveFileDialog");
    BOOL result = WindowsDialogManager::Instance().ShowSaveFileDialog(buffer, buffer_size, filter, def_ext, pError);
    if (result)
    {
        DFLog(TAG, L"Save file: %ls", buffer);
    }
    else
    {
        DLog(TAG, L"Error occurred during save file selection.");
    }
    DFLog(TAG, L"ShowSaveFileDialog returned %d", result);
    return result;
}

BOOL showFolderDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* title,
    DWORD* pError
) {
    DLog(TAG, L"showFolderDialog");

    BOOL result = WindowsDialogManager::Instance().ShowFolderDialog(buffer, buffer_size, title, pError);
    if (result)
    {
        DFLog(TAG, L"Selected folder: %ls", buffer);
    }
    else
    {
        DLog(TAG, L"Error occurred during folder selection.");
    }
    DFLog(TAG, L"ShowFolderDialog returned %d", result);
    return result;
}

int showMultiFolderDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* title,
    DWORD* pError
)
{
    DLog(TAG, L"showMultiFolderDialog");

    int count = WindowsDialogManager::Instance().ShowMultiFolderDialog(buffer, buffer_size, title, pError);
    DFLog(TAG, L"count(folder count): %d", count);
    if (count > 0)
    {
        // For multi-folder selection, items are separated by \0, ending with \0\0
        wchar_t* p = buffer;
        for (int i = 0; i < count; ++i)
        {
            DFLog(TAG, L"Selected folder %d: %ls", i + 1, p);
            p += wcslen(p) + 1;
        }
    }
    else
    {
        if (count < 0)
        {
            DFLog(TAG, L"Error occurred during multi-folder selection.");
        }
        else
        {
            DFLog(TAG, L"Multi-folder selection was canceled.");
        }
    }
    return count;
}