#pragma once
// From the C ABI's dialog requests to the C++ API's (stage 5 design 8.4.1).
// Separate from the exports so the conversion can be tested without showing a
// dialog (CT-15).

#include <cstddef>
#include <vector>

#include "NativeToolkit/Dialog.h"
#include "NativeToolkitC/Dialog.h"

namespace NativeToolkitC::Detail::Dialog {

namespace Api = NativeToolkit::Dialog;

/// Each returns NTK_DIALOG_ERROR_NONE or NTK_DIALOG_ERROR_INVALID_PARAMETER.
/// A NULL request is every field at its default.
ntk_dialog_error ToAlertRequest(const ntk_dialog_alert_request* in, Api::AlertRequest& out);
ntk_dialog_error ToFilters(const ntk_dialog_filter* filters, size_t count, std::vector<Api::FileFilter>& out);
ntk_dialog_error ToFileRequest(const ntk_dialog_file_request* in, const ntk_dialog_filter* filters,
                               size_t filterCount, Api::FileRequest& out);
ntk_dialog_error ToSaveFileRequest(const ntk_dialog_save_file_request* in, const ntk_dialog_filter* filters,
                                   size_t filterCount, Api::SaveFileRequest& out);
ntk_dialog_error ToFolderRequest(const ntk_dialog_folder_request* in, Api::FolderRequest& out);

ntk_dialog_alert_result ToAlertResult(Api::AlertResult result) noexcept;

}  // namespace NativeToolkitC::Detail::Dialog
