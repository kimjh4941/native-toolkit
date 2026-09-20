/**
 * @file WindowsDialogMapping.h
 * @brief Domain layer: the data shapes the file dialogs read and write.
 * @details
 *  Pure logic over strings and buffers, with no windows.h in sight, so these
 *  rules can be read and tested without the platform. The Win32 flag words
 *  live in Data/WindowsDialogFlags.h instead, because they are the API rather
 *  than a shape of data.
 *
 *  Two shapes are easy to get subtly wrong, and both are recorded in the input
 *  inventory:
 *
 *   - the filter block is a string with embedded NULs terminated by two of
 *     them, and an absent filter means "All Files" (DLG-12);
 *   - the multi-select buffer packs strings, not files: N files arrive as N+1
 *     entries led by their folder, while one file arrives as a single full
 *     path (DLG-02, DLG-04).
 */
#pragma once

#include <string>
#include <vector>

#include "NativeToolkit/Dialog.h"

namespace NativeToolkit::Dialog::Domain {

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
