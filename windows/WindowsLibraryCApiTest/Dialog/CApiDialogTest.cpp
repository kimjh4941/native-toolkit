#include "pch.h"

#include "NativeToolkitC/Dialog.h"

#include "Dialog/DialogConvert.h"

#include <cstring>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace NativeToolkitC::Detail::Dialog;

// ============================================================================
// The dialog part of the C ABI (stage 5 design, T-04).
//
// A dialog cannot be shown in a unit test, so the exports are exercised only
// on the paths that return before one is shown (a NULL output, a malformed
// request), and the conversion to the C++ request is tested on its own (CT-15).
// The dialogs themselves are the C++ API's, covered by the UI tests.
// ============================================================================

namespace CApiDialogTest
{

namespace
{
    template <class T>
    T Sized()
    {
        T value{};
        value.struct_size = static_cast<uint32_t>(sizeof(T));
        return value;
    }
}

TEST_CLASS(CApiDialogTest)
{
public:

    // --- CT-15: conversion, and zero meaning the C++ default (E-9) -----------

    TEST_METHOD(Test_ANullOrZeroedRequest_IsTheCppDefault)
    {
        Api::FileRequest fromNull, fromZero;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_NONE, ToFileRequest(nullptr, nullptr, 0, fromNull));
        auto zero = Sized<ntk_dialog_file_request>();
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_NONE, ToFileRequest(&zero, nullptr, 0, fromZero));

        const Api::FileRequest cpp;
        for (const auto* converted : {&fromNull, &fromZero}) {
            Assert::IsTrue(converted->title == cpp.title);
            Assert::AreEqual(cpp.fileMustExist, converted->fileMustExist);
            Assert::IsTrue(converted->owner == cpp.owner);
            Assert::IsTrue(converted->filters.empty());
        }

        Api::SaveFileRequest save;
        auto zeroSave = Sized<ntk_dialog_save_file_request>();
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_NONE, ToSaveFileRequest(&zeroSave, nullptr, 0, save));
        Assert::AreEqual(Api::SaveFileRequest{}.overwritePrompt, save.overwritePrompt);

        Api::AlertRequest alert;
        auto zeroAlert = Sized<ntk_dialog_alert_request>();
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_NONE, ToAlertRequest(&zeroAlert, alert));
        Assert::IsTrue(Api::AlertButtons::Ok == alert.buttons);
        Assert::IsTrue(Api::AlertIcon::None == alert.icon);
        Assert::IsTrue(Api::AlertDefaultButton::First == alert.defaultButton);
        Assert::IsFalse(alert.topMost);
    }

    TEST_METHOD(Test_TheInvertedFlags_ReachTheCppRequest)
    {
        auto file = Sized<ntk_dialog_file_request>();
        file.allow_missing_file = 1;
        Api::FileRequest converted;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_NONE, ToFileRequest(&file, nullptr, 0, converted));
        Assert::IsFalse(converted.fileMustExist);

        auto save = Sized<ntk_dialog_save_file_request>();
        save.skip_overwrite_prompt = 1;
        Api::SaveFileRequest convertedSave;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_NONE, ToSaveFileRequest(&save, nullptr, 0, convertedSave));
        Assert::IsFalse(convertedSave.overwritePrompt);
    }

    TEST_METHOD(Test_AnAlertRequest_CarriesEveryField)
    {
        auto in = Sized<ntk_dialog_alert_request>();
        in.title = "T\xC3\xAFtle";
        in.message = "Body";
        in.buttons = NTK_DIALOG_ALERT_BUTTONS_YES_NO_CANCEL;
        in.icon = NTK_DIALOG_ALERT_ICON_QUESTION;
        in.default_button = NTK_DIALOG_ALERT_DEFAULT_BUTTON_THIRD;
        in.top_most = 1;
        in.show_help_button = 1;
        int window = 0;
        in.owner = &window;

        Api::AlertRequest out;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_NONE, ToAlertRequest(&in, out));
        Assert::AreEqual(std::wstring(L"T\u00eftle"), out.title);
        Assert::AreEqual(std::wstring(L"Body"), out.message);
        Assert::IsTrue(Api::AlertButtons::YesNoCancel == out.buttons);
        Assert::IsTrue(Api::AlertIcon::Question == out.icon);
        Assert::IsTrue(Api::AlertDefaultButton::Third == out.defaultButton);
        Assert::IsTrue(out.topMost);
        Assert::IsTrue(out.showHelpButton);
        Assert::IsTrue(static_cast<void*>(out.owner) == static_cast<void*>(&window));
    }

    TEST_METHOD(Test_FilterPatterns_AreSplitOnSemicolons)
    {
        const ntk_dialog_filter filters[] = {
            {"Text", "*.txt;*.log"},
            {nullptr, "*.*"},
            {"Odd", ";*.a;;*.b;"},
        };
        std::vector<Api::FileFilter> out;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_NONE, ToFilters(filters, 3, out));
        Assert::AreEqual<size_t>(3, out.size());
        Assert::AreEqual(std::wstring(L"Text"), out[0].description);
        Assert::AreEqual<size_t>(2, out[0].patterns.size());
        Assert::AreEqual(std::wstring(L"*.log"), out[0].patterns[1]);
        Assert::IsTrue(out[1].description.empty(), L"a NULL name is not \"\"");
        Assert::AreEqual<size_t>(2, out[2].patterns.size(), L"empty patterns were kept");
    }

    TEST_METHOD(Test_EveryAlertResult_MapsToItsCValue)
    {
        Assert::AreEqual<int32_t>(NTK_DIALOG_ALERT_RESULT_OK, ToAlertResult(Api::AlertResult::Ok));
        Assert::AreEqual<int32_t>(NTK_DIALOG_ALERT_RESULT_CANCEL, ToAlertResult(Api::AlertResult::Cancel));
        Assert::AreEqual<int32_t>(NTK_DIALOG_ALERT_RESULT_CONTINUE, ToAlertResult(Api::AlertResult::Continue));
        Assert::AreEqual<int32_t>(NTK_DIALOG_ALERT_RESULT_HELP, ToAlertResult(Api::AlertResult::Help));
    }

    // --- CT-06: malformed input ------------------------------------------------

    TEST_METHOD(Test_ReservedFieldsNotZero_AreRefused)
    {
        auto alert = Sized<ntk_dialog_alert_request>();
        alert.reserved1 = 1;
        Api::AlertRequest out;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToAlertRequest(&alert, out));

        auto folder = Sized<ntk_dialog_folder_request>();
        folder.reserved0 = 1;
        Api::FolderRequest outFolder;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToFolderRequest(&folder, outFolder));
    }

    TEST_METHOD(Test_OutOfRangeEnumerations_AreRefused)
    {
        Api::AlertRequest out;
        auto alert = Sized<ntk_dialog_alert_request>();
        alert.buttons = 7;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToAlertRequest(&alert, out));
        alert = Sized<ntk_dialog_alert_request>();
        alert.icon = -1;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToAlertRequest(&alert, out));
        alert = Sized<ntk_dialog_alert_request>();
        alert.default_button = 4;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToAlertRequest(&alert, out));
    }

    TEST_METHOD(Test_InvalidUtf8_IsRefused)
    {
        auto folder = Sized<ntk_dialog_folder_request>();
        folder.title = "\xC3\x28";
        Api::FolderRequest out;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToFolderRequest(&folder, out));

        const ntk_dialog_filter badName[] = {{"\xFF", "*.*"}};
        std::vector<Api::FileFilter> filters;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToFilters(badName, 1, filters));
    }

    TEST_METHOD(Test_AFilterWithoutPatternsOrAMissingArray_IsRefused)
    {
        std::vector<Api::FileFilter> out;
        const ntk_dialog_filter noPatterns[] = {{"All", nullptr}};
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToFilters(noPatterns, 1, out));
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToFilters(nullptr, 2, out));
    }

    // --- CT-07: struct versions --------------------------------------------------

    TEST_METHOD(Test_AStructThatIsTooSmallOrHasUnknownContent_IsRefused)
    {
        Api::FolderRequest out;
        auto tooSmall = Sized<ntk_dialog_folder_request>();
        tooSmall.struct_size -= 8;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToFolderRequest(&tooSmall, out));

        // A caller built against a longer struct than this version knows.
        struct { ntk_dialog_folder_request known; uint64_t added; } longer{};
        longer.known.struct_size = sizeof(longer);
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_NONE, ToFolderRequest(&longer.known, out), L"an all-zero tail was refused");
        longer.added = 1;
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ToFolderRequest(&longer.known, out),
                         L"a field this version does not know was silently dropped");
    }

    // --- CT-05: the exports refuse a missing output before showing anything ----

    TEST_METHOD(Test_TheExports_RefuseANullOutputWithoutShowingADialog)
    {
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ntk_dialog_show_alert(nullptr, nullptr));
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ntk_dialog_show_open_file(nullptr, nullptr, 0, nullptr));
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ntk_dialog_show_open_files(nullptr, nullptr, 0, nullptr));
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ntk_dialog_show_save_file(nullptr, nullptr, 0, nullptr));
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ntk_dialog_show_pick_folder(nullptr, nullptr));
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ntk_dialog_show_pick_folders(nullptr, nullptr));
        Assert::AreEqual<uint32_t>(0, ntk_last_system_code());
    }

    TEST_METHOD(Test_AMalformedRequest_ClearsTheOutputAndShowsNothing)
    {
        const ntk_dialog_filter noPatterns[] = {{"All", nullptr}};
        ntk_string* path = reinterpret_cast<ntk_string*>(this);  // anything but NULL
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ntk_dialog_show_open_file(nullptr, noPatterns, 1, &path));
        Assert::IsNull(path, L"the output was not cleared on failure");

        auto folder = Sized<ntk_dialog_folder_request>();
        folder.reserved0 = 1;
        ntk_string_list* paths = reinterpret_cast<ntk_string_list*>(this);
        Assert::AreEqual<int32_t>(NTK_DIALOG_ERROR_INVALID_PARAMETER, ntk_dialog_show_pick_folders(&folder, &paths));
        Assert::IsNull(paths, L"the output was not cleared on failure");
    }
};

}  // namespace CApiDialogTest
