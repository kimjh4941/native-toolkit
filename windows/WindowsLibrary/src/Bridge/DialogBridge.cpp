/**
 * @file DialogBridge.cpp
 * @brief Exported C functions of the Dialog feature.
 * @details
 *  Thin wrappers over WindowsDialogManager. This translation unit belongs to
 *  the DLL only; the implementation it calls is built into the library.
 */
#include "pch.h"
#include <windows.h>
#include "Common/CommonInternal.h"
#include "Dialog/WindowsDialogManager.h"
#include "Dialog/Data/WindowsDialogWin32.h"

/**
 * @brief Public API: Show alert dialog.
 * @copydetails WindowsDialogManager::ShowAlertDialog
 */
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
    DFLog(TAG, L"showAlertDialog title: %ls, message: %ls, buttons: %d, icon: %d, defbutton: %d, options: %d, pError: %p", title, message, buttons, icon, defbutton, options, pError);

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

/**
 * @brief Public API: Show single file open dialog.
 * @copydetails WindowsDialogManager::ShowFileDialog
 */
BOOL showFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    DWORD* pError
)
{
    DFLog(TAG, L"showFileDialog buffer_size: %lu, filter: %ls, pError: %p", buffer_size, filter ? filter : L"null", pError);

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

/**
 * @brief Public API: Show multi-select file open dialog.
 * @copydetails WindowsDialogManager::ShowMultiFileDialog
 */
int showMultiFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    DWORD* pError
)
{
    DFLog(TAG, L"showMultiFileDialog buffer_size: %lu, filter: %ls, pError: %p", buffer_size, filter ? filter : L"null", pError);

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

/**
 * @brief Public API: Show single folder selection dialog.
 * @copydetails WindowsDialogManager::ShowFolderDialog
 */
BOOL showFolderDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* title,
    DWORD* pError
) {
    DFLog(TAG, L"showFolderDialog buffer_size: %lu, title: %ls, pError: %p", buffer_size, title ? title : L"null", pError);

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

/**
 * @brief Public API: Show multi-select folder dialog.
 * @copydetails WindowsDialogManager::ShowMultiFolderDialog
 */
int showMultiFolderDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* title,
    DWORD* pError
)
{
    DFLog(TAG, L"showMultiFolderDialog buffer_size: %lu, title: %ls, pError: %p", buffer_size, title ? title : L"null", pError);

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

/**
 * @brief Public API: Show save file dialog.
 * @copydetails WindowsDialogManager::ShowSaveFileDialog
 */
BOOL showSaveFileDialog(
    wchar_t* buffer,
    DWORD buffer_size,
    const wchar_t* filter,
    const wchar_t* def_ext,
    DWORD* pError
)
{
    DFLog(TAG, L"showSaveFileDialog buffer_size: %lu, filter: %ls, def_ext: %ls, pError: %p", buffer_size, filter ? filter : L"null", def_ext ? def_ext : L"null", pError);

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
