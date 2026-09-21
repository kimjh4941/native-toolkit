// The dialog functions of the C ABI (OP-01..OP-06). Each converts the request,
// calls the C++ API and hands the result back as a handle; the C++ API decides
// everything else.

#include "NativeToolkitC/Dialog.h"

#include "Common/Guard.h"
#include "Common/Handles.h"
#include "Common/LastError.h"
#include "Dialog/DialogConvert.h"

using namespace NativeToolkitC::Detail;
using namespace NativeToolkitC::Detail::Dialog;

namespace {

ntk_dialog_error Succeed() noexcept
{
    SetLastSystemCode(0);
    return NTK_DIALOG_ERROR_NONE;
}

ntk_dialog_error Fail(ntk_dialog_error code, uint32_t systemCode = 0) noexcept
{
    SetLastSystemCode(systemCode);
    return code;
}

ntk_dialog_error Fail(const Api::Error& error) noexcept
{
    // The C values are the C++ enumeration's (checked by T-11).
    return Fail(static_cast<ntk_dialog_error>(error.code), error.systemCode);
}

/// Everything below runs inside this: no exception leaves the C ABI.
template <class F>
ntk_dialog_error Run(F&& body) noexcept
{
    return Guarded<ntk_dialog_error>(NTK_DIALOG_ERROR_UNKNOWN, NTK_DIALOG_ERROR_UNKNOWN,
                                     NTK_SYSTEM_CODE_E_OUTOFMEMORY, body);
}

}  // namespace

extern "C" ntk_dialog_error NTK_CALL ntk_dialog_show_alert(
    const ntk_dialog_alert_request* request, ntk_dialog_alert_result* out_result)
{
    return Run([&]() -> ntk_dialog_error {
        if (!out_result) return Fail(NTK_DIALOG_ERROR_INVALID_PARAMETER);
        Api::AlertRequest converted;
        if (const auto e = ToAlertRequest(request, converted); e != NTK_DIALOG_ERROR_NONE) return Fail(e);

        const auto result = Api::ShowAlert(converted);
        if (!result.has_value()) return Fail(result.error());
        *out_result = ToAlertResult(result.value());
        return Succeed();
    });
}

extern "C" ntk_dialog_error NTK_CALL ntk_dialog_show_open_file(
    const ntk_dialog_file_request* request, const ntk_dialog_filter* filters, size_t filter_count,
    ntk_string** out_path)
{
    return Run([&]() -> ntk_dialog_error {
        if (!out_path) return Fail(NTK_DIALOG_ERROR_INVALID_PARAMETER);
        *out_path = nullptr;
        Api::FileRequest converted;
        if (const auto e = ToFileRequest(request, filters, filter_count, converted); e != NTK_DIALOG_ERROR_NONE) return Fail(e);

        const auto result = Api::ShowOpenFile(converted);
        if (!result.has_value()) return Fail(result.error());
        *out_path = NewString(result.value());
        return Succeed();
    });
}

extern "C" ntk_dialog_error NTK_CALL ntk_dialog_show_open_files(
    const ntk_dialog_file_request* request, const ntk_dialog_filter* filters, size_t filter_count,
    ntk_string_list** out_paths)
{
    return Run([&]() -> ntk_dialog_error {
        if (!out_paths) return Fail(NTK_DIALOG_ERROR_INVALID_PARAMETER);
        *out_paths = nullptr;
        Api::FileRequest converted;
        if (const auto e = ToFileRequest(request, filters, filter_count, converted); e != NTK_DIALOG_ERROR_NONE) return Fail(e);

        const auto result = Api::ShowOpenFiles(converted);
        if (!result.has_value()) return Fail(result.error());
        *out_paths = NewStringList(result.value());
        return Succeed();
    });
}

extern "C" ntk_dialog_error NTK_CALL ntk_dialog_show_save_file(
    const ntk_dialog_save_file_request* request, const ntk_dialog_filter* filters, size_t filter_count,
    ntk_string** out_path)
{
    return Run([&]() -> ntk_dialog_error {
        if (!out_path) return Fail(NTK_DIALOG_ERROR_INVALID_PARAMETER);
        *out_path = nullptr;
        Api::SaveFileRequest converted;
        if (const auto e = ToSaveFileRequest(request, filters, filter_count, converted); e != NTK_DIALOG_ERROR_NONE) return Fail(e);

        const auto result = Api::ShowSaveFile(converted);
        if (!result.has_value()) return Fail(result.error());
        *out_path = NewString(result.value());
        return Succeed();
    });
}

extern "C" ntk_dialog_error NTK_CALL ntk_dialog_show_pick_folder(
    const ntk_dialog_folder_request* request, ntk_string** out_path)
{
    return Run([&]() -> ntk_dialog_error {
        if (!out_path) return Fail(NTK_DIALOG_ERROR_INVALID_PARAMETER);
        *out_path = nullptr;
        Api::FolderRequest converted;
        if (const auto e = ToFolderRequest(request, converted); e != NTK_DIALOG_ERROR_NONE) return Fail(e);

        const auto result = Api::ShowPickFolder(converted);
        if (!result.has_value()) return Fail(result.error());
        *out_path = NewString(result.value());
        return Succeed();
    });
}

extern "C" ntk_dialog_error NTK_CALL ntk_dialog_show_pick_folders(
    const ntk_dialog_folder_request* request, ntk_string_list** out_paths)
{
    return Run([&]() -> ntk_dialog_error {
        if (!out_paths) return Fail(NTK_DIALOG_ERROR_INVALID_PARAMETER);
        *out_paths = nullptr;
        Api::FolderRequest converted;
        if (const auto e = ToFolderRequest(request, converted); e != NTK_DIALOG_ERROR_NONE) return Fail(e);

        const auto result = Api::ShowPickFolders(converted);
        if (!result.has_value()) return Fail(result.error());
        *out_paths = NewStringList(result.value());
        return Succeed();
    });
}
