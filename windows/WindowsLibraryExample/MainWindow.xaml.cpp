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
    void MainWindow::ShowDialogButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"ShowDialogButton_Click");
        ShowAlertDialog(L"タイトル", L"テストです。", MB_OKCANCEL, MB_ICONINFORMATION, MB_DEFBUTTON2, MB_APPLMODAL); // DLLのダイアログ表示関数を呼び出し

        //ShowModal();
    }
}
