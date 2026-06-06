#include "pch.h"
#include "NotificationPage.xaml.h"
#if __has_include("NotificationPage.g.cpp")
#include "NotificationPage.g.cpp"
#endif

#include "common.h"
#include "WindowsNotificationManager.h"

#include <chrono>
#include <functional>

using namespace winrt;
using namespace Microsoft::UI::Xaml;
using namespace winrt::Windows::Data::Json;

static const wchar_t* TAG = L"NotificationPage";

namespace
{
    // Process-lifetime forwarding hub. The C bridge callback is a free function pointer,
    // so it cannot capture state; it forwards to this std::function which the active
    // NotificationPage registers/unregisters. Cleared on navigation away (no leak / null-safe).
    std::function<void(winrt::hstring)> g_notificationHandler;

    void OnNotificationInvokedThunk(const wchar_t* argsJson)
    {
        DFLog(TAG, L"[OnNotificationInvokedThunk] argsJson=%ls", argsJson ? argsJson : L"null");
        if (g_notificationHandler)
        {
            g_notificationHandler(winrt::hstring{ argsJson ? argsJson : L"" });
        }
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
        if (err == NOTIFICATION_ERROR_DISABLED)
        {
            SetResultText(L"❌ [" + method + L"] Notifications are disabled. Tap \"Open Notification Settings\" to enable.");
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
        DWORD err = 0;
        // Packaged (MSIX) app -> isPackaged = TRUE, no CLSID / launchUri.
        initNotificationManager(&OnNotificationInvokedThunk, TRUE, nullptr, nullptr, &err);
        if (err == 0)
        {
            m_initialized = true;
            int setting = getNotificationSetting();
            SetResultText(L"✅ [InitializeManager] initialized. setting=" + std::to_wstring(setting));
        }
        else
        {
            ShowResult(L"InitializeManager", err);
        }
    }

    void NotificationPage::Uninitialize_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[Uninitialize_Click]");
        uninitNotificationManager();
        m_initialized = false;
        SetResultText(L"✅ [Uninitialize] done");
    }

    void NotificationPage::GetSetting_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetSetting_Click]");
        int setting = getNotificationSetting();
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
        DWORD err = 0;
        openNotificationSettings(&err);
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
        DWORD err = 0;
        std::wstring payload = LR"({"title":"Hello","body":"Basic toast","tag":"sample"})";
        showNotification(payload.c_str(), &err);
        ShowResult(L"ShowBasic", err);
    }

    void NotificationPage::ShowWithButtons_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithButtons_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        std::wstring payload = LR"({"title":"Actionable","body":"Toast with buttons","tag":"sample",)"
            LR"("buttons":[{"label":"Open","args":{"action":"open"}},{"label":"Dismiss","args":{"action":"dismiss"}}]})";
        showNotification(payload.c_str(), &err);
        ShowResult(L"ShowWithButtons", err);
    }

    void NotificationPage::ShowWithImage_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithImage_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        std::wstring payload = LR"({"title":"With Image","body":"Toast with hero image","tag":"sample",)"
            LR"("heroImage":"ms-appx:///Assets/StoreLogo.png"})";
        showNotification(payload.c_str(), &err);
        ShowResult(L"ShowWithImage", err);
    }

    void NotificationPage::ShowWithInput_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithInput_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        std::wstring payload = LR"({"title":"Reply","body":"Type a reply and pick an option","tag":"sample",)"
            LR"("textBoxes":[{"id":"reply","placeholder":"Type a message"}],)"
            LR"("comboBoxes":[{"id":"opt","title":"Status","defaultSelection":"busy",)"
            LR"("items":[{"id":"free","label":"Free"},{"id":"busy","label":"Busy"}]}],)"
            LR"("buttons":[{"label":"Send","args":{"action":"send"}}]})";
        showNotification(payload.c_str(), &err);
        ShowResult(L"ShowWithInput", err);
    }

    void NotificationPage::ShowWithProgress_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithProgress_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        std::wstring payload = LR"({"title":"Downloading","body":"In progress","tag":"progress-sample",)"
            LR"("progress":{"title":"Toolkit.zip","value":0.3,"valueStr":"30%","status":"Downloading"}})";
        showNotification(payload.c_str(), &err);
        ShowResult(L"ShowWithProgress", err);
    }

    void NotificationPage::ShowWithExpiration_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithExpiration_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        std::wstring payload = LR"({"title":"Expires","body":"This toast expires in 10 seconds","tag":"sample","expiration":10})";
        showNotification(payload.c_str(), &err);
        ShowResult(L"ShowWithExpiration", err);
    }

    void NotificationPage::ShowWithAudio_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ShowWithAudio_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        std::wstring payload = LR"({"title":"Reminder","body":"Toast with reminder sound","tag":"sample",)"
            LR"("audio":{"type":"event","event":"reminder"}})";
        showNotification(payload.c_str(), &err);
        ShowResult(L"ShowWithAudio", err);
    }

    // ---- Schedule ----

    void NotificationPage::Schedule_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[Schedule_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        auto now = std::chrono::system_clock::now();
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            (now + std::chrono::seconds(60)).time_since_epoch()).count();
        std::wstring payload = LR"({"title":"Scheduled","body":"Fires in ~1 minute","tag":"scheduled"})";
        scheduleNotification(payload.c_str(), static_cast<int64_t>(ms), &err);
        ShowResult(L"Schedule", err);
    }

    void NotificationPage::CancelScheduled_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[CancelScheduled_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        cancelScheduledNotification(L"scheduled", L"", &err);
        ShowResult(L"CancelScheduled", err);
    }

    // ---- Progress ----

    void NotificationPage::UpdateProgress_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[UpdateProgress_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        updateNotificationProgress(L"progress-sample", L"", 0.6, L"60%", L"Downloading", m_progressSeq++, &err);
        // PROGRESS_NOT_FOUND: no progress notification is currently shown.
        if (err == NOTIFICATION_ERROR_PROGRESS_NOT_FOUND)
        {
            SetResultText(L"❌ [UpdateProgress] No progress notification. Tap ShowWithProgress first.");
            return;
        }
        ShowResult(L"UpdateProgress", err);
    }

    // ---- Badge ----

    void NotificationPage::SetBadge_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[SetBadge_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        setBadge(5, &err);
        ShowResult(L"SetBadge(5)", err);
    }

    void NotificationPage::SetBadgeGlyph_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[SetBadgeGlyph_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        setBadge(-1, &err); // glyph: alert
        ShowResult(L"SetBadgeGlyph(alert)", err);
    }

    void NotificationPage::ClearBadge_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[ClearBadge_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        setBadge(0, &err);
        ShowResult(L"ClearBadge", err);
    }

    // ---- Remove / Query ----

    void NotificationPage::GetAllNotifications_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[GetAllNotifications_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        wchar_t buf[4096] = { 0 };
        getAllNotifications(buf, 4096, &err);
        if (err != 0)
        {
            ShowResult(L"GetAllNotifications", err);
            return;
        }

        std::wstring ids;
        uint32_t count = 0;
        try
        {
            JsonArray arr = JsonArray::Parse(winrt::hstring{ buf });
            count = arr.Size();
            for (auto const& item : arr)
            {
                auto obj = item.GetObject();
                auto id = static_cast<uint32_t>(obj.GetNamedNumber(L"id"));
                if (!ids.empty()) ids += L", ";
                ids += std::to_wstring(id);
                m_lastNotificationId = id;
                m_hasLastId = true;
            }
        }
        catch (...)
        {
            DLog(TAG, L"[GetAllNotifications] JSON parse failed");
        }

        if (count == 0)
        {
            SetResultText(L"ℹ️ [GetAllNotifications] No active notifications. Tap a Show button first.");
            return;
        }
        SetResultText(L"✅ [GetAllNotifications] count=" + std::to_wstring(count) + L", ids=[" + ids + L"]");
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
        DWORD err = 0;
        uint32_t removedId = m_lastNotificationId;
        removeNotificationById(removedId, &err);
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
        DWORD err = 0;
        removeNotificationsByTag(L"sample", L"", &err);
        ShowResult(L"RemoveByTag(sample)", err);
    }

    void NotificationPage::RemoveAll_Click(IInspectable const&, RoutedEventArgs const&)
    {
        DLog(TAG, L"[RemoveAll_Click]");
        if (!EnsureInitialized()) return;
        DWORD err = 0;
        removeAllNotifications(&err);
        ShowResult(L"RemoveAll", err);
    }
}
