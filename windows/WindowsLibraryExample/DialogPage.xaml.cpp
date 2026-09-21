#include "pch.h"
#include "DialogPage.xaml.h"
#if __has_include("DialogPage.g.cpp")
#include "DialogPage.g.cpp"
#endif

#include "SampleLog.h"
#include "NativeToolkit/Dialog.h"

using namespace winrt;
using namespace Microsoft::UI::Xaml;

namespace Dialog = NativeToolkit::Dialog;

static const wchar_t* TAG = L"DialogPage";

namespace
{
    // Every picker in the sample offers the same single filter.
    std::vector<Dialog::FileFilter> AllFiles()
    {
        return { Dialog::FileFilter{ L"All Files", { L"*.*" } } };
    }

    // The page reports an alert's answer as the MessageBox ID it stands for, so
    // the result reads the same as the button's Win32 name (IDOK is 1).
    int ToMessageBoxId(Dialog::AlertResult result)
    {
        switch (result)
        {
        case Dialog::AlertResult::Ok:       return IDOK;
        case Dialog::AlertResult::Cancel:   return IDCANCEL;
        case Dialog::AlertResult::Yes:      return IDYES;
        case Dialog::AlertResult::No:       return IDNO;
        case Dialog::AlertResult::Retry:    return IDRETRY;
        case Dialog::AlertResult::Abort:    return IDABORT;
        case Dialog::AlertResult::Ignore:   return IDIGNORE;
        case Dialog::AlertResult::TryAgain: return IDTRYAGAIN;
        case Dialog::AlertResult::Continue: return IDCONTINUE;
        case Dialog::AlertResult::Close:    return IDCLOSE;
        case Dialog::AlertResult::Help:     return IDHELP;
        }
        return 0;
    }

    std::wstring ErrorText(Dialog::Error const& error)
    {
        return std::to_wstring(static_cast<uint32_t>(error.code)) +
               L" (system code " + std::to_wstring(error.systemCode) + L")";
    }

    // The text shown when a picker returns without a path: canceled, or failed.
    std::wstring FailureText(std::wstring const& method, Dialog::Error const& error)
    {
        if (error.code == Dialog::ErrorCode::Canceled)
        {
            std::wstring text = method + L" was canceled.";
            DLog(TAG, text.c_str());
            return text;
        }
        DFLog(TAG, L"%ls Error Code: %u, system code: %u", method.c_str(),
              static_cast<uint32_t>(error.code), error.systemCode);
        return L"❌\n" + method + L" Error Code: " + ErrorText(error);
    }

    // Each entry is a full path, and the count is the number of entries.
    std::wstring ListText(std::wstring const& method, std::wstring const& label,
                          std::vector<std::wstring> const& paths)
    {
        std::wstring text = L"✅\n" + method + L" Result: " + std::to_wstring(paths.size()) + L"\n";
        for (size_t i = 0; i < paths.size(); ++i)
        {
            text += label + L"[" + std::to_wstring(i) + L"]: " + paths[i] + L"\n";
        }
        return text;
    }
}

namespace winrt::WindowsLibraryExample::implementation
{
    DialogPage::DialogPage()
    {
        InitializeComponent();
    }

    void DialogPage::BackButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[BackButton_Click]");
        if (Frame() && Frame().CanGoBack())
        {
            Frame().GoBack();
        }
    }

    void DialogPage::ShowAlertDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowAlertDialogButton_Click]");
        Dialog::AlertRequest request;
        request.title = L"Native Windows Dialog";
        request.message = L"This is a native Windows dialog!";
        request.buttons = Dialog::AlertButtons::OkCancel;
        request.icon = Dialog::AlertIcon::Information;
        request.defaultButton = Dialog::AlertDefaultButton::Second;

        const auto result = Dialog::ShowAlert(request);
        if (result.has_value())
        {
            const int id = ToMessageBoxId(result.value());
            DFLog(TAG, L"ShowAlert Result: %d", id);
            SetResultText(L"✅\nShowAlertDialog Result: " + std::to_wstring(id));
        }
        else
        {
            DFLog(TAG, L"ShowAlert Error Code: %u", static_cast<uint32_t>(result.error().code));
            SetResultText(L"❌\nShowAlertDialog Error Code: " + ErrorText(result.error()));
        }
    }

    void DialogPage::ShowFileDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowFileDialogButton_Click]");
        Dialog::FileRequest request;
        request.filters = AllFiles();

        const auto result = Dialog::ShowOpenFile(request);
        if (result.has_value())
        {
            DFLog(TAG, L"ShowOpenFile: %ls", result.value().c_str());
            SetResultText(L"✅\nShowFileDialog Result: 1, filePath: " + result.value());
        }
        else
        {
            SetResultText(FailureText(L"ShowFileDialog", result.error()));
        }
    }

    void DialogPage::ShowMultiFileDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowMultiFileDialogButton_Click]");
        Dialog::FileRequest request;
        request.filters = AllFiles();

        const auto result = Dialog::ShowOpenFiles(request);
        if (result.has_value())
        {
            DFLog(TAG, L"ShowOpenFiles count: %zu", result.value().size());
            SetResultText(ListText(L"ShowMultiFileDialog", L"multiBuffer", result.value()));
        }
        else
        {
            SetResultText(FailureText(L"ShowMultiFileDialog", result.error()));
        }
    }

    void DialogPage::ShowFolderDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowFolderDialogButton_Click]");
        Dialog::FolderRequest request;
        request.title = L"Select Folder";

        const auto result = Dialog::ShowPickFolder(request);
        if (result.has_value())
        {
            DFLog(TAG, L"ShowPickFolder: %ls", result.value().c_str());
            SetResultText(L"✅\nShowFolderDialog Result: 1, folderPath: " + result.value());
        }
        else
        {
            SetResultText(FailureText(L"ShowFolderDialog", result.error()));
        }
    }

    void DialogPage::ShowMultiFolderDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowMultiFolderDialogButton_Click]");
        Dialog::FolderRequest request;
        request.title = L"Select Folders";

        const auto result = Dialog::ShowPickFolders(request);
        if (result.has_value())
        {
            DFLog(TAG, L"ShowPickFolders count: %zu", result.value().size());
            SetResultText(ListText(L"ShowMultiFolderDialog", L"multiFolderBuffer", result.value()));
        }
        else
        {
            SetResultText(FailureText(L"ShowMultiFolderDialog", result.error()));
        }
    }

    void DialogPage::ShowSaveFileDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowSaveFileDialogButton_Click]");
        Dialog::SaveFileRequest request;
        request.filters = AllFiles();
        request.defaultExtension = L"txt";

        const auto result = Dialog::ShowSaveFile(request);
        if (result.has_value())
        {
            DFLog(TAG, L"ShowSaveFile: %ls", result.value().c_str());
            SetResultText(L"✅\nShowSaveFileDialog Result: 1, savePath: " + result.value());
        }
        else
        {
            SetResultText(FailureText(L"ShowSaveFileDialog", result.error()));
        }
    }

    void DialogPage::SetResultText(const std::wstring& text)
    {
        ResultTextBlock().Text(winrt::hstring(text));
    }
}
