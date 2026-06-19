#include "pch.h"
#include "MainWindow.xaml.h"
#if __has_include("MainWindow.g.cpp")
#include "MainWindow.g.cpp"
#endif

#include "common.h"

using namespace winrt;
using namespace Microsoft::UI::Xaml;

static const wchar_t* TAG = L"MainWindow";

namespace winrt::WindowsLibraryExample::implementation
{
    MainWindow::MainWindow()
    {
        InitializeComponent();
        Title(L"Native Toolkit Example");

        DLog(TAG, L"[MainWindow] navigating to MainMenuPage");
        winrt::Windows::UI::Xaml::Interop::TypeName pageType{
            L"WindowsLibraryExample.MainMenuPage",
            winrt::Windows::UI::Xaml::Interop::TypeKind::Custom
        };
        RootFrame().Navigate(pageType);
    }

    int32_t MainWindow::MyProperty()
    {
        throw hresult_not_implemented();
    }

    void MainWindow::MyProperty(int32_t /* value */)
    {
        throw hresult_not_implemented();
    }
}
