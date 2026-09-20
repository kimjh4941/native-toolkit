/**
 * @file WindowsDialogMapping.h
 * @brief Domain layer: turns the public request types into the Win32 shapes.
 * @details
 *  Pure logic - no Win32 call - so every rule here is testable without showing
 *  a dialog. Three things live in this file, and each one is a place where a
 *  rewrite could quietly lose what the C ABI accepts today:
 *
 *   - the flag words of MessageBoxW, including the escape hatch for bits the
 *     enumerations do not name (design N-9);
 *   - the filter block, which is a string with embedded NULs terminated by two
 *     of them, and the "All Files" default the C ABI falls back to (DLG-12);
 *   - the packed result of the multi-select dialogs, where the count is of
 *     NUL-separated strings rather than of files, so N files come back as N+1
 *     entries with the folder first (DLG-02, DLG-04).
 */
#pragma once

#include <windows.h>
#include <commdlg.h>

#include <string>
#include <vector>

#include "NativeToolkit/Dialog.h"

namespace NativeToolkit::Dialog::Domain {

/// The MessageBoxW uType for a request, including any raw bits it carries.
inline UINT ToMessageBoxType(const AlertRequest& request) noexcept
{
    UINT type = 0;
    switch (request.buttons) {
        case AlertButtons::Ok:                type |= MB_OK; break;
        case AlertButtons::OkCancel:          type |= MB_OKCANCEL; break;
        case AlertButtons::YesNo:             type |= MB_YESNO; break;
        case AlertButtons::YesNoCancel:       type |= MB_YESNOCANCEL; break;
        case AlertButtons::RetryCancel:       type |= MB_RETRYCANCEL; break;
        case AlertButtons::AbortRetryIgnore:  type |= MB_ABORTRETRYIGNORE; break;
        case AlertButtons::CancelTryContinue: type |= MB_CANCELTRYCONTINUE; break;
    }
    switch (request.icon) {
        case AlertIcon::None:        break;
        case AlertIcon::Information: type |= MB_ICONINFORMATION; break;
        case AlertIcon::Warning:     type |= MB_ICONWARNING; break;
        case AlertIcon::Error:       type |= MB_ICONERROR; break;
        case AlertIcon::Question:    type |= MB_ICONQUESTION; break;
    }
    switch (request.defaultButton) {
        case AlertDefaultButton::First:  type |= MB_DEFBUTTON1; break;
        case AlertDefaultButton::Second: type |= MB_DEFBUTTON2; break;
        case AlertDefaultButton::Third:  type |= MB_DEFBUTTON3; break;
        case AlertDefaultButton::Fourth: type |= MB_DEFBUTTON4; break;
    }
    if (request.topMost)        type |= MB_TOPMOST;
    if (request.showHelpButton) type |= MB_HELP;
    return type | request.extraFlags;
}

/// The button id MessageBoxW returned, as the public enumeration.
inline AlertResult FromMessageBoxResult(int id) noexcept
{
    switch (id) {
        case IDOK:       return AlertResult::Ok;
        case IDCANCEL:   return AlertResult::Cancel;
        case IDYES:      return AlertResult::Yes;
        case IDNO:       return AlertResult::No;
        case IDRETRY:    return AlertResult::Retry;
        case IDABORT:    return AlertResult::Abort;
        case IDIGNORE:   return AlertResult::Ignore;
        case IDTRYAGAIN: return AlertResult::TryAgain;
        case IDCONTINUE: return AlertResult::Continue;
        case IDCLOSE:    return AlertResult::Close;
        case IDHELP:     return AlertResult::Help;
        default:         return AlertResult::Cancel;
    }
}

/**
 * @brief Builds the Win32 filter block: "desc\0pattern;pattern\0...\0\0".
 * @details
 *  An empty list gives the same block the C ABI uses when it is handed no
 *  filter: "All Files\0*.*\0\0" (DLG-12). An entry with no patterns matches
 *  everything, which is what a bare description would otherwise mean.
 */
inline std::wstring BuildFilterBlock(const std::vector<FileFilter>& filters)
{
    std::wstring block;
    if (filters.empty()) {
        block.append(L"All Files");
        block.push_back(L'\0');
        block.append(L"*.*");
        block.push_back(L'\0');
        block.push_back(L'\0');
        return block;
    }
    for (const auto& filter : filters) {
        block.append(filter.description);
        block.push_back(L'\0');
        if (filter.patterns.empty()) {
            block.append(L"*.*");
        } else {
            for (size_t i = 0; i < filter.patterns.size(); ++i) {
                if (i != 0) block.push_back(L';');
                block.append(filter.patterns[i]);
            }
        }
        block.push_back(L'\0');
    }
    block.push_back(L'\0');
    return block;
}

/**
 * @brief Expands what showMultiFileDialog packs into a buffer.
 * @param buffer The NUL-separated block the dialog filled in.
 * @param count  What the C ABI returns: the number of strings, not of files.
 * @return The full paths, in the order the dialog gave them.
 * @details
 *  One selected file comes back as a single full path and a count of 1. Two or
 *  more come back as the folder followed by the file names, so the count is
 *  N+1 for N files and each name has to be joined to that folder (DLG-02,
 *  DLG-04). Reading the count as a file count is the mistake this function
 *  exists to prevent.
 */
inline std::vector<std::wstring> ExpandMultiFileBuffer(const wchar_t* buffer, int count)
{
    std::vector<std::wstring> paths;
    if (buffer == nullptr || count <= 0 || *buffer == L'\0') {
        return paths;
    }

    std::vector<std::wstring> parts;
    const wchar_t* cursor = buffer;
    while (*cursor != L'\0') {
        parts.emplace_back(cursor);
        cursor += parts.back().size() + 1;
    }
    if (parts.empty()) {
        return paths;
    }
    if (parts.size() == 1) {
        paths.push_back(parts.front());   // one selection: already a full path
        return paths;
    }

    const std::wstring& directory = parts.front();
    const bool endsWithSeparator = !directory.empty() && directory.back() == L'\\';
    for (size_t i = 1; i < parts.size(); ++i) {
        paths.push_back(endsWithSeparator ? directory + parts[i]
                                          : directory + L'\\' + parts[i]);
    }
    return paths;
}

/// Expands the block showMultiFolderDialog fills in: full paths, one after another.
inline std::vector<std::wstring> ExpandMultiFolderBuffer(const wchar_t* buffer, int count)
{
    std::vector<std::wstring> paths;
    if (buffer == nullptr || count <= 0) {
        return paths;
    }
    const wchar_t* cursor = buffer;
    while (*cursor != L'\0') {
        paths.emplace_back(cursor);
        cursor += paths.back().size() + 1;
    }
    return paths;
}

}  // namespace NativeToolkit::Dialog::Domain
