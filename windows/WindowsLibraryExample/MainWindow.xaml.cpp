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
//int ShowDialog(const wchar_t*); // DLL関数のインポート

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

    // ここにイベントハンドラを追加
    void MainWindow::ShowAlertDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowAlertDialogButton_Click");

        DWORD errorCode = 0;
        showAlertDialog(L"タイトル", L"テストです。", MB_OKCANCEL, MB_ICONINFORMATION, MB_DEFBUTTON2, MB_APPLMODAL, &errorCode);
        // エラーコードをログに表示
        if (errorCode != 0) {
            DFLog(TAG, L"showAlertDialog エラーコード: %lu", errorCode);
        }
        else {
            DLog(TAG, L"showAlertDialog 正常終了");
        }
    }

    void MainWindow::ShowFileDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowFileDialogButton_Click");
        // シングルファイル選択
        wchar_t filePath[260] = { 0 };
        const wchar_t* filter = L"テキストファイル\0*.txt\0すべてのファイル\0*.*\0";
        DWORD errorCode = 0;
        showFileDialog(filePath, 260, filter, &errorCode);
        // エラーコードをログに表示
        if (errorCode != 0) {
            DFLog(TAG, L"showFileDialog エラーコード: %lu", errorCode);
        }
        else {
            DLog(TAG, L"showFileDialog 正常終了");
        }
    }

    void MainWindow::ShowMultiFileDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowMultiFileDialogButton_Click");
        // 十分なバッファを用意（複数ファイル選択時は大きめに）
        wchar_t multiBuffer[4096] = { 0 };
        const wchar_t* filter = L"テキストファイル\0*.txt\0すべてのファイル\0*.*\0";
        DWORD errorCode = 0;
        showMultiFileDialog(multiBuffer, 4096, filter, &errorCode);
        // エラーコードをログに表示
        if (errorCode != 0) {
            DFLog(TAG, L"showMultiFileDialog エラーコード: %lu", errorCode);
        }
        else {
            DLog(TAG, L"showMultiFileDialog 正常終了");
        }
    }

    void MainWindow::ShowSaveFileDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowSaveFileDialogButton_Click");
        wchar_t savePath[260] = { 0 };
        // フィルタはWin32 API形式（\0区切り、最後は\0\0）
        const wchar_t* filter = L"テキストファイル\0*.txt\0すべてのファイル\0*.*\0";
        const wchar_t* def_ext = L"txt";
        DWORD errorCode = 0;
        showSaveFileDialog(savePath, 260, filter, def_ext, &errorCode);
        // エラーコードをログに表示
        if (errorCode != 0) {
            DFLog(TAG, L"showSaveFileDialog エラーコード: %lu", errorCode);
        }
        else {
            DLog(TAG, L"showSaveFileDialog 正常終了");
        }
    }

    void MainWindow::ShowFolderDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowFolderDialogButton_Click");
        // フォルダ選択
        wchar_t folderPath[260] = { 0 };
        const wchar_t* title = L"フォルダの選択";
        DWORD errorCode = 0;
        showFolderDialog(folderPath, 260, title, &errorCode);
        // エラーコードをログに表示
        if (errorCode != 0) {
            DFLog(TAG, L"showFolderDialog エラーコード: %lu", errorCode);
        }
        else {
            DLog(TAG, L"showFolderDialog 正常終了");
        }
    }

    void MainWindow::ShowMultiFolderDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowMultiFolderDialogButton_Click");
        // 複数フォルダ選択用バッファ（十分なサイズを確保）
        wchar_t multiFolderBuffer[4096] = { 0 };
        const wchar_t* title = L"フォルダの選択";
        DWORD errorCode = 0;
        showMultiFolderDialog(multiFolderBuffer, 4096, title, &errorCode);
        // エラーコードをログに表示
        if (errorCode != 0) {
            DFLog(TAG, L"showMultiFolderDialog エラーコード: %lu", errorCode);
        }
        else {
            DLog(TAG, L"showMultiFolderDialog 正常終了");
        }
    }
}
