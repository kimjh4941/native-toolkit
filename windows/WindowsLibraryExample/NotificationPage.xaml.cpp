#include "pch.h"
#include "NotificationPage.xaml.h"
#if __has_include("NotificationPage.g.cpp")
#include "NotificationPage.g.cpp"
#endif

#include "SampleLog.h"
#include "NativeToolkit/Notification.h"

#include <chrono>
#include <functional>
#include <optional>

using namespace winrt;
using namespace Microsoft::UI::Xaml;

namespace Notification = NativeToolkit::Notification;

static const wchar_t* TAG = L"NotificationPage";

namespace
{
    // The one Manager this process may have. It outlives the page: navigating
    // away does not unregister, so a notification can still be acted on.
    std::optional<Notification::Manager> g_manager;

    // Forwarding hub. The Manager's handler is installed once, at creation, and
    // forwards to this std::function, which the active NotificationPage
    // registers/unregisters. Cleared on navigation away (no leak / null-safe).
    std::function<void(winrt::hstring)> g_notificationHandler;

    void OnNotificationInvoked(Notification::ActivationArgs const& args)
    {
        DFLog(TAG, L"[OnNotificationInvoked] rawArguments=%ls", args.rawArguments.c_str());
        if (g_notificationHandler)
        {
            g_notificationHandler(winrt::hstring{ args.rawArguments });
        }
    }

    // The error code a result is reported with: 0 for success, otherwise the
    // NotificationError value (the same numbers as the C ABI's constants).
    template <class T>
    unsigned long CodeOf(Notification::Result<T> const& result)
    {
        return result.has_value() ? 0ul : static_cast<unsigned long>(result.error().code);
    }

    unsigned long NotInitializedCode()
    {
        return static_cast<unsigned long>(Notification::ErrorCode::NotInitialized);
    }

    Notification::Button MakeButton(std::wstring label, std::wstring action)
    {
        Notification::Button button;
        button.label = std::move(label);
        button.args = Notification::ArgumentPairs{ { L"action", std::move(action) } };
        return button;
    }

    Notification::NotificationContent MakeContent(std::wstring title, std::wstring body, std::wstring tag)
    {
        Notification::NotificationContent content;
        content.title = std::move(title);
        content.body = std::move(body);
        content.tag = std::move(tag);
        return content;
    }
}

namespace winrt::WindowsLibraryExample::implementation
{
    NotificationPage::NotificationPage()
    {
        InitializeComponent();
    }

    void NotificationPage::OnNavigatedTo(winrt::Microsoft::UI::Xaml::Navigation::NavigationEventArgs const&)
    {
        DLog(TAG, L"[OnNavigatedTo] register notification handler");
        // Capture a weak ref to the result TextBlock (not the page) to avoid keeping the
        // page alive and to update the UI directly on the dispatcher thread.
        auto weakText = winrt::make_weak(ResultTextBlock());
        auto dq = DispatcherQueue();
        g_notificationHandler = [weakText, dq](winrt::hstring args)
        {
            dq.TryEnqueue([weakText, args]()
            {
                if (auto text = weakText.get())
                {
                    text.Text(winrt::hstring{ L"\U0001F514 Notification invoked:\n" } + args);
                }
            });
        };
    }

    void NotificationPage::OnNavigatedFrom(winrt::Microsoft::UI::Xaml::Navigation::NavigationEventArgs const&)
    {
        DLog(TAG, L"[OnNavigatedFrom] clear notification handler");
        g_notificationHandler = nullptr;
    }

    void NotificationPage::BackButton_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[BackButton_Click]");
        if (Frame() && Frame().CanGoBack())
        {
            Frame().GoBack();
        }
    }

    bool NotificationPage::EnsureInitialized()
    {
        if (!m_initialized)
        {
            SetResultText(L"❌ Not initialized. Tap InitializeManager first.");
            return false;
        }
        return true;
    }

    void NotificationPage::ShowResult(std::wstring const& method, unsigned long err)
    {
        // DISABLED: notifications are turned off for this app. Guide the user to
        // the settings page (Open Notification Settings button) to re-enable them.
        if (err == static_cast<unsigned long>(Notification::ErrorCode::Disabled))
        {
            SetResultText(L"❌ [" + method + L"] Notifications are disabled. Tap \"Open Notification Settings\" to enable.");
            return;
        }
        if (err == static_cast<unsigned long>(Notification::ErrorCode::NotSupported))
        {
            if (method.find(L"RemoveById") == 0)
            {
                SetResultText(L"❌ [" + method + L"] Not supported for unpackaged apps. Use RemoveByTag or RemoveAll instead.");
                return;
            }
            if (method == L"GetAllNotifications")
            {
                SetResultText(L"❌ [GetAllNotifications] Not supported for unpackaged apps. Use tag-based removal instead.");
                return;
            }
            SetResultText(L"❌ [" + method + L"] This operation is not supported for the current app type.");
            return;
        }
        std::wstring text = (err == 0 ? L"✅ " : L"❌ ") + std::wstring(L"[") + method + L"] errorCode=" + std::to_wstring(err);
        SetResultText(text);
    }

    void NotificationPage::SetResultText(std::wstring const& text)
    {
        ResultTextBlock().Text(winrt::hstring(text));
    }

    // ---- Init / Setting ----

    void NotificationPage::InitializeManager_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[InitializeManager_Click]");
        if (!g_manager.has_value())
        {
            // Packaged (MSIX) app -> isPackaged = true, no display name / icon.
            Notification::ManagerOptions options;
            options.onInvoked = &OnNotificationInvoked;
            options.isPackaged = true;

            auto created = Notification::Manager::Create(options);
            if (!created.has_value())
            {
                ShowResult(L"InitializeManager", CodeOf(created));
                return;
            }
            g_manager.emplace(std::move(created).value());
        }
        // Already created by an earlier visit to the page: it is still
        // registered, and its handler already forwards to the hub.

        m_initialized = true;
        const auto setting = g_manager->GetSetting();
        const int value = setting.has_value() ? static_cast<int>(setting.value()) : -1;
        SetResultText(L"✅ [InitializeManager] initialized. setting=" + std::to_wstring(value));
    }

    void NotificationPage::Uninitialize_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[Uninitialize_Click]");
        if (g_manager.has_value())
        {
            g_manager->Close();
            g_manager.reset();
        }
        m_initialized = false;
        SetResultText(L"✅ [Uninitialize] done");
    }

    void NotificationPage::GetSetting_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetSetting_Click]");
        // No manager, or the question failed: shown as -1.
        int setting = -1;
        if (g_manager.has_value())
        {
            const auto result = g_manager->GetSetting();
            if (result.has_value())
            {
                setting = static_cast<int>(result.value());
            }
        }

        std::wstring label;
        switch (setting)
        {
        case 0:  label = L"Enabled"; break;
        case 1:  label = L"DisabledForApplication"; break;
        case 2:  label = L"DisabledForUser"; break;
        case 3:  label = L"DisabledByGroupPolicy"; break;
        case 4:  label = L"DisabledByManifest"; break;
        case -1: label = L"Error(-1)"; break;
        default: label = L"Unknown(" + std::to_wstring(setting) + L")"; break;
        }
        SetResultText(L"✅ [GetSetting] " + label);
    }

    void NotificationPage::OpenSettings_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[OpenSettings_Click]");
        const unsigned long err = g_manager.has_value() ? CodeOf(g_manager->OpenSettings()) : NotInitializedCode();
        if (err == 0)
            SetResultText(L"✅ [OpenSettings] Opened notification settings. Enable notifications, then retry.");
        else
            ShowResult(L"OpenSettings", err);
    }

    // ---- Show ----

    void NotificationPage::ShowBasic_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowBasic_Click]");
        if (!EnsureInitialized()) return;
        const auto content = MakeContent(L"Hello", L"Basic toast", L"sample");
        ShowResult(L"ShowBasic", CodeOf(g_manager->Show(content)));
    }

    void NotificationPage::ShowWithButtons_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithButtons_Click]");
        if (!EnsureInitialized()) return;
        auto content = MakeContent(L"Actionable", L"Toast with buttons", L"sample");
        content.buttons = { MakeButton(L"Open", L"open"), MakeButton(L"Dismiss", L"dismiss") };
        ShowResult(L"ShowWithButtons", CodeOf(g_manager->Show(content)));
    }

    void NotificationPage::ShowWithImage_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithImage_Click]");
        if (!EnsureInitialized()) return;
        auto content = MakeContent(L"With Image", L"Toast with hero image", L"sample");
        content.heroImage = L"ms-appx:///Assets/StoreLogo.png";
        ShowResult(L"ShowWithImage", CodeOf(g_manager->Show(content)));
    }

    void NotificationPage::ShowWithInput_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithInput_Click]");
        if (!EnsureInitialized()) return;
        auto content = MakeContent(L"Reply", L"Type a reply and pick an option", L"sample");

        Notification::TextInput reply;
        reply.id = L"reply";
        reply.placeholder = L"Type a message";
        content.textInputs = { reply };

        Notification::ComboInput status;
        status.id = L"opt";
        status.title = L"Status";
        status.defaultSelection = L"busy";
        status.items = { { L"free", L"Free" }, { L"busy", L"Busy" } };
        content.comboInputs = { status };

        content.buttons = { MakeButton(L"Send", L"send") };
        ShowResult(L"ShowWithInput", CodeOf(g_manager->Show(content)));
    }

    void NotificationPage::ShowWithProgress_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithProgress_Click]");
        if (!EnsureInitialized()) return;
        auto content = MakeContent(L"Downloading", L"In progress", L"progress-sample");
        Notification::ProgressSpec progress;
        progress.title = L"Toolkit.zip";
        progress.value = 0.3;
        progress.valueStr = L"30%";
        progress.status = L"Downloading";
        content.progress = progress;
        ShowResult(L"ShowWithProgress", CodeOf(g_manager->Show(content)));
    }

    void NotificationPage::ShowWithExpiration_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithExpiration_Click]");
        if (!EnsureInitialized()) return;
        auto content = MakeContent(L"Expires", L"This toast expires in 10 seconds", L"sample");
        content.expiration = std::chrono::seconds(10);
        ShowResult(L"ShowWithExpiration", CodeOf(g_manager->Show(content)));
    }

    void NotificationPage::ShowWithAudio_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithAudio_Click]");
        if (!EnsureInitialized()) return;
        auto content = MakeContent(L"Reminder", L"Toast with reminder sound", L"sample");
        Notification::AudioSpec audio;
        audio.kind = Notification::AudioKind::Event;
        audio.eventName = L"reminder";
        content.audio = audio;
        ShowResult(L"ShowWithAudio", CodeOf(g_manager->Show(content)));
    }

    // ---- Schedule ----

    void NotificationPage::Schedule_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[Schedule_Click]");
        if (!EnsureInitialized()) return;
        const auto when = std::chrono::system_clock::now() + std::chrono::seconds(60);
        const auto content = MakeContent(L"Scheduled", L"Fires in ~1 minute", L"scheduled");
        ShowResult(L"Schedule", CodeOf(g_manager->Schedule(content, when)));
    }

    void NotificationPage::ScheduleSoon_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ScheduleSoon_Click]");
        if (!EnsureInitialized()) return;
        const auto when = std::chrono::system_clock::now() + std::chrono::seconds(5);
        const auto content = MakeContent(L"Scheduled", L"Fires in ~5 seconds", L"scheduled");
        ShowResult(L"ScheduleSoon", CodeOf(g_manager->Schedule(content, when)));
    }

    void NotificationPage::CancelScheduled_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CancelScheduled_Click]");
        if (!EnsureInitialized()) return;
        ShowResult(L"CancelScheduled", CodeOf(g_manager->CancelScheduled(L"scheduled", L"")));
    }

    // ---- Progress ----

    void NotificationPage::UpdateProgress_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[UpdateProgress_Click]");
        if (!EnsureInitialized()) return;
        Notification::ProgressUpdate update;
        update.tag = L"progress-sample";
        update.value = 0.6;
        update.valueString = L"60%";
        update.status = L"Downloading";
        update.sequenceNumber = m_progressSeq++;
        const auto result = g_manager->UpdateProgress(update);
        // ProgressNotFound: no progress notification is currently shown.
        if (!result.has_value() && result.error().code == Notification::ErrorCode::ProgressNotFound)
        {
            SetResultText(L"❌ [UpdateProgress] No progress notification. Tap ShowWithProgress first.");
            return;
        }
        ShowResult(L"UpdateProgress", CodeOf(result));
    }

    // ---- Badge ----

    void NotificationPage::SetBadge_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[SetBadge_Click]");
        if (!EnsureInitialized()) return;
        ShowResult(L"SetBadge(5)", CodeOf(g_manager->SetBadge(5)));
    }

    void NotificationPage::SetBadgeGlyph_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[SetBadgeGlyph_Click]");
        if (!EnsureInitialized()) return;
        ShowResult(L"SetBadgeGlyph(alert)", CodeOf(g_manager->SetBadge(-1))); // glyph: alert
    }

    void NotificationPage::ClearBadge_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ClearBadge_Click]");
        if (!EnsureInitialized()) return;
        ShowResult(L"ClearBadge", CodeOf(g_manager->SetBadge(0)));
    }

    // ---- Remove / Query ----

    void NotificationPage::GetAllNotifications_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetAllNotifications_Click]");
        if (!EnsureInitialized()) return;
        const auto result = g_manager->GetAll();
        if (!result.has_value())
        {
            ShowResult(L"GetAllNotifications", CodeOf(result));
            return;
        }

        const auto& notifications = result.value();
        if (notifications.empty())
        {
            SetResultText(L"ℹ️ [GetAllNotifications] No active notifications. Tap a Show button first.");
            return;
        }

        std::wstring ids;
        for (const auto& notification : notifications)
        {
            if (!ids.empty()) ids += L", ";
            ids += std::to_wstring(notification.id);
            m_lastNotificationId = notification.id;
            m_hasLastId = true;
        }
        SetResultText(L"✅ [GetAllNotifications] count=" + std::to_wstring(notifications.size()) + L", ids=[" + ids + L"]");
    }

    void NotificationPage::RemoveById_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[RemoveById_Click]");
        if (!EnsureInitialized()) return;
        if (!m_hasLastId)
        {
            SetResultText(L"❌ [RemoveById] No captured id. Tap GetAllNotifications first.");
            return;
        }
        const uint32_t removedId = m_lastNotificationId;
        const unsigned long err = CodeOf(g_manager->RemoveById(removedId));
        if (err == 0)
        {
            // The captured id is now consumed; require a fresh GetAllNotifications
            // before the next RemoveById so it does not target a stale id.
            m_hasLastId = false;
            m_lastNotificationId = 0;
        }
        ShowResult(L"RemoveById(" + std::to_wstring(removedId) + L")", err);
    }

    void NotificationPage::RemoveByTag_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[RemoveByTag_Click]");
        if (!EnsureInitialized()) return;
        ShowResult(L"RemoveByTag(sample)", CodeOf(g_manager->RemoveByTag(L"sample", L"")));
    }

    void NotificationPage::RemoveAll_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[RemoveAll_Click]");
        if (!EnsureInitialized()) return;
        ShowResult(L"RemoveAll", CodeOf(g_manager->RemoveAll()));
    }
}
