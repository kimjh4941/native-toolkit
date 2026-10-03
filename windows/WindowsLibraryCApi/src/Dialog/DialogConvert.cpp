// From the C ABI's dialog requests to the C++ API's (stage 5 design 8.4.1).

#include "Dialog/DialogConvert.h"

#include <string>

#include "Common/StructInput.h"
#include "Common/Utf8.h"

namespace NativeToolkitC::Detail::Dialog {

namespace {

constexpr ntk_dialog_error kOk = NTK_DIALOG_ERROR_NONE;
constexpr ntk_dialog_error kInvalid = NTK_DIALOG_ERROR_INVALID_PARAMETER;

/// A string that may be NULL, which stands for "".
bool OptionalText(const char* text, std::wstring& out)
{
    if (!text) {
        out.clear();
        return true;
    }
    return Utf8ToWide(text, out);
}

/// The C ABI has no NOT_SUPPORTED for dialogs, so a struct that is longer than
/// this version knows is refused like any other malformed one (design 11.1).
template <class T>
bool ReadRequest(const T* in, T& out)
{
    return ReadInputStruct(in, out) == StructCheck::Ok;
}

HWND__* Owner(void* owner) noexcept
{
    return static_cast<HWND__*>(owner);
}

}  // namespace

ntk_dialog_error ToAlertRequest(const ntk_dialog_alert_request* in, Api::AlertRequest& out)
{
    out = Api::AlertRequest{};
    if (!in) return kOk;

    ntk_dialog_alert_request request;
    if (!ReadRequest(in, request)) return kInvalid;
    if (request.reserved0 != 0 || request.reserved1 != 0) return kInvalid;
    if (request.buttons < NTK_DIALOG_ALERT_BUTTONS_OK || request.buttons > NTK_DIALOG_ALERT_BUTTONS_CANCEL_TRY_CONTINUE) return kInvalid;
    if (request.icon < NTK_DIALOG_ALERT_ICON_NONE || request.icon > NTK_DIALOG_ALERT_ICON_QUESTION) return kInvalid;
    if (request.default_button < NTK_DIALOG_ALERT_DEFAULT_BUTTON_FIRST ||
        request.default_button > NTK_DIALOG_ALERT_DEFAULT_BUTTON_FOURTH) return kInvalid;
    if (!OptionalText(request.title, out.title)) return kInvalid;
    if (!OptionalText(request.message, out.message)) return kInvalid;

    // The C values are the C++ enumerations' declaration order (checked by T-11).
    out.buttons = static_cast<Api::AlertButtons>(request.buttons);
    out.icon = static_cast<Api::AlertIcon>(request.icon);
    out.defaultButton = static_cast<Api::AlertDefaultButton>(request.default_button);
    out.topMost = request.top_most != 0;
    out.showHelpButton = request.show_help_button != 0;
    out.owner = Owner(request.owner);
    return kOk;
}

ntk_dialog_error ToFilters(const ntk_dialog_filter* filters, size_t count, std::vector<Api::FileFilter>& out)
{
    out.clear();
    if (count == 0) return kOk;
    if (!filters) return kInvalid;

    out.reserve(count);
    for (size_t i = 0; i < count; ++i) {
        Api::FileFilter filter;
        if (!OptionalText(filters[i].name, filter.description)) return kInvalid;
        if (!filters[i].patterns) return kInvalid;

        std::wstring patterns;
        if (!Utf8ToWide(filters[i].patterns, patterns)) return kInvalid;
        size_t start = 0;
        while (start <= patterns.size()) {
            const size_t end = patterns.find(L';', start);
            const size_t stop = end == std::wstring::npos ? patterns.size() : end;
            if (stop > start) filter.patterns.push_back(patterns.substr(start, stop - start));
            if (end == std::wstring::npos) break;
            start = end + 1;
        }
        out.push_back(std::move(filter));
    }
    return kOk;
}

ntk_dialog_error ToFileRequest(const ntk_dialog_file_request* in, const ntk_dialog_filter* filters,
                               size_t filterCount, Api::FileRequest& out)
{
    out = Api::FileRequest{};
    if (ToFilters(filters, filterCount, out.filters) != kOk) return kInvalid;
    if (!in) return kOk;

    ntk_dialog_file_request request;
    if (!ReadRequest(in, request)) return kInvalid;
    if (request.reserved0 != 0 || request.reserved1 != 0) return kInvalid;
    if (!OptionalText(request.title, out.title)) return kInvalid;
    out.fileMustExist = request.allow_missing_file == 0;  // E-9: zero is the C++ default
    out.owner = Owner(request.owner);
    return kOk;
}

ntk_dialog_error ToSaveFileRequest(const ntk_dialog_save_file_request* in, const ntk_dialog_filter* filters,
                                   size_t filterCount, Api::SaveFileRequest& out)
{
    out = Api::SaveFileRequest{};
    if (ToFilters(filters, filterCount, out.filters) != kOk) return kInvalid;
    if (!in) return kOk;

    ntk_dialog_save_file_request request;
    if (!ReadRequest(in, request)) return kInvalid;
    if (request.reserved0 != 0 || request.reserved1 != 0) return kInvalid;
    if (!OptionalText(request.title, out.title)) return kInvalid;
    if (!OptionalText(request.default_extension, out.defaultExtension)) return kInvalid;
    out.overwritePrompt = request.skip_overwrite_prompt == 0;  // E-9
    out.owner = Owner(request.owner);
    return kOk;
}

ntk_dialog_error ToFolderRequest(const ntk_dialog_folder_request* in, Api::FolderRequest& out)
{
    out = Api::FolderRequest{};
    if (!in) return kOk;

    ntk_dialog_folder_request request;
    if (!ReadRequest(in, request)) return kInvalid;
    if (request.reserved0 != 0) return kInvalid;
    if (!OptionalText(request.title, out.title)) return kInvalid;
    out.owner = Owner(request.owner);
    return kOk;
}

ntk_dialog_alert_result ToAlertResult(Api::AlertResult result) noexcept
{
    return static_cast<ntk_dialog_alert_result>(result);
}

}  // namespace NativeToolkitC::Detail::Dialog
