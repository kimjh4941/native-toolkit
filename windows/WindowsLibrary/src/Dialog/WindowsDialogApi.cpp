/**
 * @file WindowsDialogApi.cpp
 * @brief The C++ API of the Dialog feature (OP-01..OP-06).
 * @details
 *  Thin over the Data layer: build the Win32 shapes with the Domain helpers,
 *  call the dialog, then turn the raw outcome into a Result. No dialog logic
 *  lives here.
 *
 *  Buffers are sized once, generously, because the Data layer takes a caller
 *  buffer and reports a too-small one as a system error rather than asking for
 *  a size (DLG-17). The sizes below match what the sample has been passing.
 */
#include "pch.h"

#include <windows.h>

#include <vector>

#include "Common/CommonInternal.h"
#include "Dialog/Data/WindowsDialogWin32.h"
#include "Dialog/Domain/WindowsDialogError.h"
#include "Dialog/Domain/WindowsDialogMapping.h"
#include "NativeToolkit/Dialog.h"

namespace NativeToolkit::Dialog {

namespace {

const wchar_t* TAG = L"NativeToolkit::Dialog";

constexpr size_t kSinglePathBuffer = 1024;    ///< One full path, as the sample sizes it.
constexpr size_t kMultiPathBuffer  = 32768;   ///< Many paths; the Win32 dialogs cap well below this.

/// Turns an outcome into a failure, or nothing when it succeeded.
Domain::ClassifiedOutcome Classify(bool succeeded, DWORD rawError) noexcept
{
    return Domain::Classify(succeeded, static_cast<uint32_t>(rawError));
}

}  // namespace

Result<AlertResult> ShowAlert(const AlertRequest& request)
{
    DFLog(TAG, L"[ShowAlert] title: %ls, buttons: %d, icon: %d, extraFlags: 0x%08x",
          request.title.c_str(), static_cast<int>(request.buttons),
          static_cast<int>(request.icon), request.extraFlags);

    DWORD error = 0;
    const UINT type = Domain::ToMessageBoxType(request);
    const int pressed = WindowsDialogManager::Instance().ShowAlertDialog(
        request.title.c_str(), request.message.c_str(),
        type, 0u, 0u, 0u, &error);

    if (pressed == 0) {
        return Unexpected{Classify(false, error)};
    }
    return Domain::FromMessageBoxResult(pressed);
}

Result<std::wstring> ShowOpenFile(const FileRequest& request)
{
    DFLog(TAG, L"[ShowOpenFile] filters: %zu, fileMustExist: %d", request.filters.size(), request.fileMustExist);

    std::wstring buffer(kSinglePathBuffer, L'\0');
    const std::wstring filter = Domain::BuildFilterBlock(request.filters);
    DWORD error = 0;

    const BOOL ok = WindowsDialogManager::Instance().ShowFileDialog(
        buffer.data(), static_cast<DWORD>(buffer.size()), filter.c_str(), &error);

    const auto outcome = Classify(ok != FALSE && buffer[0] != L'\0', error);
    if (!Domain::Succeeded(outcome)) {
        return Unexpected{outcome};
    }
    return std::wstring(buffer.c_str());
}

Result<std::vector<std::wstring>> ShowOpenFiles(const FileRequest& request)
{
    DFLog(TAG, L"[ShowOpenFiles] filters: %zu", request.filters.size());

    std::wstring buffer(kMultiPathBuffer, L'\0');
    const std::wstring filter = Domain::BuildFilterBlock(request.filters);
    DWORD error = 0;

    const int count = WindowsDialogManager::Instance().ShowMultiFileDialog(
        buffer.data(), static_cast<DWORD>(buffer.size()), filter.c_str(), &error);

    // count is a number of NUL-separated strings, not of files: 0 means the
    // user cancelled and -1 means the call failed (DLG-02).
    const auto outcome = Classify(count > 0, error);
    if (!Domain::Succeeded(outcome)) {
        return Unexpected{outcome};
    }
    return Domain::ExpandMultiFileBuffer(buffer.c_str(), count);
}

Result<std::wstring> ShowSaveFile(const SaveFileRequest& request)
{
    DFLog(TAG, L"[ShowSaveFile] filters: %zu, defaultExtension: %ls",
          request.filters.size(), request.defaultExtension.c_str());

    std::wstring buffer(kSinglePathBuffer, L'\0');
    const std::wstring filter = Domain::BuildFilterBlock(request.filters);
    DWORD error = 0;

    const BOOL ok = WindowsDialogManager::Instance().ShowSaveFileDialog(
        buffer.data(), static_cast<DWORD>(buffer.size()), filter.c_str(),
        request.defaultExtension.empty() ? nullptr : request.defaultExtension.c_str(), &error);

    const auto outcome = Classify(ok != FALSE && buffer[0] != L'\0', error);
    if (!Domain::Succeeded(outcome)) {
        return Unexpected{outcome};
    }
    return std::wstring(buffer.c_str());
}

Result<std::wstring> ShowPickFolder(const FolderRequest& request)
{
    DFLog(TAG, L"[ShowPickFolder] title: %ls", request.title.c_str());

    std::wstring buffer(kSinglePathBuffer, L'\0');
    DWORD error = 0;

    const BOOL ok = WindowsDialogManager::Instance().ShowFolderDialog(
        buffer.data(), static_cast<DWORD>(buffer.size()),
        request.title.empty() ? nullptr : request.title.c_str(), &error);

    const auto outcome = Classify(ok != FALSE && buffer[0] != L'\0', error);
    if (!Domain::Succeeded(outcome)) {
        return Unexpected{outcome};
    }
    return std::wstring(buffer.c_str());
}

Result<std::vector<std::wstring>> ShowPickFolders(const FolderRequest& request)
{
    DFLog(TAG, L"[ShowPickFolders] title: %ls", request.title.c_str());

    std::wstring buffer(kMultiPathBuffer, L'\0');
    DWORD error = 0;

    const int count = WindowsDialogManager::Instance().ShowMultiFolderDialog(
        buffer.data(), static_cast<DWORD>(buffer.size()),
        request.title.empty() ? nullptr : request.title.c_str(), &error);

    // Unlike the file version this count is a folder count, and a successful
    // pick of nothing shares the value 0 with a cancellation (DLG-16), so the
    // raw error is what tells them apart.
    const auto outcome = Classify(count >= 0 && error == 0, error);
    if (!Domain::Succeeded(outcome)) {
        return Unexpected{outcome};
    }
    return Domain::ExpandMultiFolderBuffer(buffer.c_str(), count);
}

}  // namespace NativeToolkit::Dialog
