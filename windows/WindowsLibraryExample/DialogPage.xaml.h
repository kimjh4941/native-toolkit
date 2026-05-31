#pragma once

#include "DialogPage.g.h"

#include <string>

namespace winrt::WindowsLibraryExample::implementation
{
    struct DialogPage : DialogPageT<DialogPage>
    {
        DialogPage();

        void BackButton_Click(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& e);

        void ShowAlertDialogButton_Click(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& e);
        void ShowFileDialogButton_Click(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& e);
        void ShowMultiFileDialogButton_Click(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& e);
        void ShowFolderDialogButton_Click(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& e);
        void ShowMultiFolderDialogButton_Click(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& e);
        void ShowSaveFileDialogButton_Click(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& e);

        void SetResultText(const std::wstring& text);
    };
}

namespace winrt::WindowsLibraryExample::factory_implementation
{
    struct DialogPage : DialogPageT<DialogPage, implementation::DialogPage>
    {
    };
}
