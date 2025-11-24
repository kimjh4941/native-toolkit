#include "pch.h"
#include "MainWindow.xaml.h"
#if __has_include("MainWindow.g.cpp")
#include "MainWindow.g.cpp"
#endif

#include "common.h"
#include "WindowsDialogManager.h"

using namespace winrt;
using namespace Microsoft::UI::Xaml;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

//extern "C" __declspec(dllimport)
//int ShowDialog(const wchar_t*); // DLL function import

static const wchar_t* TAG = L"MainWindow";

namespace winrt::WindowsLibraryExample::implementation
{
    int32_t MainWindow::MyProperty()
    {
        throw hresult_not_implemented();
    }

    void MainWindow::MyProperty(int32_t /* value */)
    {
        throw hresult_not_implemented();
    }

    // Add event handlers here
    void MainWindow::ShowAlertDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowAlertDialogButton_Click");
        DWORD errorCode = 0;
        int result = showAlertDialog(L"Title", L"This is a test.", MB_OKCANCEL, MB_ICONINFORMATION, MB_DEFBUTTON2, MB_APPLMODAL, &errorCode);

        std::wstring resultText;
        if (errorCode == 0) {
            DFLog(TAG, L"showAlertDialog Result: %d", result);
            resultText = L"✅\nShowAlertDialog Result: " + std::to_wstring(result);
        }
        else
        {
            DFLog(TAG, L"showAlertDialog Error Code: %lu", errorCode);
            resultText = L"❌\nShowAlertDialog Error Code: " + std::to_wstring(errorCode);
        }
        SetResultText(resultText);
    }

    void MainWindow::ShowFileDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowFileDialogButton_Click");
        wchar_t filePath[260] = { 0 };
        const wchar_t* filter = L"All Files\0*.*\0";
        DWORD errorCode = 0;
        BOOL result = showFileDialog(filePath, 260, filter, &errorCode);

        std::wstring resultText;
        if (errorCode == 0) {
            DFLog(TAG, L"showFileDialog Result: %d", result);
            resultText = L"✅\nShowFileDialog Result: " + std::to_wstring(result) + L", filePath: " + std::wstring(filePath);
        }
        else if (errorCode == -1) {
            resultText = L"ShowFileDialog was canceled.";
            DLog(TAG, resultText.c_str());
        }
        else {
            DFLog(TAG, L"showFileDialog Error Code: %lu", errorCode);
            resultText = L"❌\nShowFileDialog Error Code: " + std::to_wstring(errorCode);
        }
        SetResultText(resultText);
    }

    void MainWindow::ShowMultiFileDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowMultiFileDialogButton_Click");
        wchar_t multiBuffer[4096] = { 0 };
        const wchar_t* filter = L"All Files\0*.*\0";
        DWORD errorCode = 0;
        int result = showMultiFileDialog(multiBuffer, 4096, filter, &errorCode);

        std::wstring resultText;
        if (errorCode == 0) {
            DFLog(TAG, L"showMultiFileDialog Result: %d", result);
            resultText = L"✅\nShowMultiFileDialog Result: " + std::to_wstring(result) + L"\n";
            wchar_t* p = multiBuffer;
            int idx = 0;
            while (*p) {
                resultText += L"multiBuffer[" + std::to_wstring(idx) + L"]: " + std::wstring(p) + L"\n";
                p += wcslen(p) + 1;
                ++idx;
            }
            DFLog(TAG, L"resultText: %ls", resultText.c_str());
        }
        else if (errorCode == -1) {
            resultText = L"ShowMultiFileDialog was canceled.";
            DLog(TAG, resultText.c_str());
        }
        else {
            DFLog(TAG, L"showMultiFileDialog Error Code: %lu", errorCode);
            resultText = L"❌\nShowMultiFileDialog Error Code: " + std::to_wstring(errorCode);
        }
        SetResultText(resultText);
    }

    void MainWindow::ShowSaveFileDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowSaveFileDialogButton_Click");
        wchar_t savePath[260] = { 0 };
        const wchar_t* filter = L"All Files\0*.*\0";
        const wchar_t* def_ext = L"txt";
        DWORD errorCode = 0;
        BOOL result = showSaveFileDialog(savePath, 260, filter, def_ext, &errorCode);

        std::wstring resultText;
        if (errorCode == 0) {
            DFLog(TAG, L"showSaveFileDialog Result: %d", result);
            resultText = L"✅\nShowSaveFileDialog Result: " + std::to_wstring(result) + L", savePath: " + std::wstring(savePath);
        }
        else if (errorCode == -1) {
            resultText = L"ShowSaveFileDialog was canceled.";
            DLog(TAG, resultText.c_str());
        }
        else {
            DFLog(TAG, L"showSaveFileDialog Error Code: %lu", errorCode);
            resultText = L"❌\nShowSaveFileDialog Error Code: " + std::to_wstring(errorCode);
        }
        SetResultText(resultText);
    }

    void MainWindow::ShowFolderDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowFolderDialogButton_Click");
        wchar_t folderPath[260] = { 0 };
        const wchar_t* title = L"Select Folder";
        DWORD errorCode = 0;
        BOOL result = showFolderDialog(folderPath, 260, title, &errorCode);

        std::wstring resultText;
        if (errorCode == 0) {
            DFLog(TAG, L"showFolderDialog Result: %d", result);
            resultText = L"✅\nShowFolderDialog Result: " + std::to_wstring(result) + L", folderPath: " + std::wstring(folderPath);
        }
        else if (errorCode == -1) {
            resultText = L"ShowFolderDialog was canceled.";
            DLog(TAG, resultText.c_str());
        }
        else {
            DFLog(TAG, L"showFolderDialog Error Code: %lu", errorCode);
            resultText = L"❌\nShowFolderDialog Error Code: " + std::to_wstring(errorCode);
        }
        SetResultText(resultText);
    }

    void MainWindow::ShowMultiFolderDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowMultiFolderDialogButton_Click");
        wchar_t multiFolderBuffer[4096] = { 0 };
        const wchar_t* title = L"Select Folder";
        DWORD errorCode = 0;
        int result = showMultiFolderDialog(multiFolderBuffer, 4096, title, &errorCode);

        std::wstring resultText;
        if (errorCode == 0) {
            DFLog(TAG, L"showMultiFolderDialog Result: %d", result);
            resultText = L"✅\nShowMultiFolderDialog Result: " + std::to_wstring(result) + L"\n";
            wchar_t* p = multiFolderBuffer;
            int idx = 0;
            while (*p) {
                resultText += L"multiFolderBuffer[" + std::to_wstring(idx) + L"]: " + std::wstring(p) + L"\n";
                p += wcslen(p) + 1;
                ++idx;
            }
            DFLLog(TAG, 4096, L"resultText: %ls", resultText.c_str());
        }
        else if (errorCode == -1) {
            resultText = L"ShowMultiFolderDialog was canceled.";
            DLog(TAG, resultText.c_str());
        }
        else {
            DFLog(TAG, L"showMultiFolderDialog Error Code: %lu", errorCode);
            resultText = L"❌\nShowMultiFolderDialog Error Code: " + std::to_wstring(errorCode);
        }
        SetResultText(resultText);
    }

    void MainWindow::SetResultText(const std::wstring& text)
    {
        ResultTextBlock().Text(winrt::hstring(text));
    }
}
