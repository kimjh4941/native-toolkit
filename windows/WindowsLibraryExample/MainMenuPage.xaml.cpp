#include "pch.h"
#include "MainMenuPage.xaml.h"
#if __has_include("MainMenuPage.g.cpp")
#include "MainMenuPage.g.cpp"
#endif

#include "common.h"

using namespace winrt;
using namespace Microsoft::UI::Xaml;

static const wchar_t* TAG = L"MainMenuPage";

namespace winrt::WindowsLibraryExample::implementation
{
    MainMenuPage::MainMenuPage()
    {
        InitializeComponent();
    }

    void MainMenuPage::NavigateTo(winrt::hstring const& pageTypeName)
    {
        DFLog(TAG, L"[NavigateTo] %ls", pageTypeName.c_str());
        if (!Frame())
        {
            return;
        }
        winrt::Windows::UI::Xaml::Interop::TypeName pageType{
            pageTypeName,
            winrt::Windows::UI::Xaml::Interop::TypeKind::Custom
        };
        Frame().Navigate(pageType);
    }

    void MainMenuPage::DialogCard_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[DialogCard_Click]");
        NavigateTo(L"WindowsLibraryExample.DialogPage");
    }

    void MainMenuPage::NotificationCard_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[NotificationCard_Click]");
        NavigateTo(L"WindowsLibraryExample.NotificationPage");
    }
}
