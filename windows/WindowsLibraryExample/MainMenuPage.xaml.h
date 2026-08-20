#pragma once

#include "MainMenuPage.g.h"

namespace winrt::WindowsLibraryExample::implementation
{
    struct MainMenuPage : MainMenuPageT<MainMenuPage>
    {
        MainMenuPage();

        void DialogCard_Click(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& e);
        void NotificationCard_Click(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& e);
        void ClipboardCard_Click(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& e);

    private:
        void NavigateTo(winrt::hstring const& pageTypeName);
    };
}

namespace winrt::WindowsLibraryExample::factory_implementation
{
    struct MainMenuPage : MainMenuPageT<MainMenuPage, implementation::MainMenuPage>
    {
    };
}
