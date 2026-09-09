#include "pch.h"
#include "MainWindow.xaml.h"
#if __has_include("MainWindow.g.cpp")
#include "MainWindow.g.cpp"
#endif

#include "common.h"
#include "ClipboardPage.xaml.h"

using namespace winrt;
using namespace Microsoft::UI::Xaml;

static const wchar_t* TAG = L"MainWindow";

namespace winrt::WindowsLibraryExample::implementation
{
    MainWindow::MainWindow()
    {
        InitializeComponent();
        Title(L"Native Toolkit Example");

        // The clipboard manager outlives the page, so it is shut down here rather
        // than on navigation. Closed still runs on the UI thread with the owner
        // window alive, which is what lets WM_RENDERALLFORMATS be delivered.
        Closed([](winrt::Windows::Foundation::IInspectable const&,
                  winrt::Microsoft::UI::Xaml::WindowEventArgs const&)
        {
            ShutdownClipboardManagerForAppExit();
        });

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
