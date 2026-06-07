#pragma once

// WinRT headers must be included before this file (via pch.h or test pch.h).
// Requires: winrt/base.h, winrt/Microsoft.Windows.AppNotifications.h,
//           winrt/Microsoft.Windows.AppNotifications.Builder.h,
//           winrt/Windows.UI.Notifications.h, winrt/Windows.Data.Json.h

#include "WindowsNotificationManager.h"
#include <string>

namespace WindowsNotificationManagerTest { class NotificationManagerTest; }

class WindowsNotificationManager
{
public:
    static WindowsNotificationManager& GetInstance();

    void InitWinAppSdk(uint32_t majorMinorVersion, DWORD* pError);
    void Init(NotificationInvokedCallback callback, BOOL isPackaged,
              const wchar_t* displayName, const wchar_t* iconUri, DWORD* pError);
    void Uninit();
    void Show(const wchar_t* jsonPayload, DWORD* pError);
    void Schedule(const wchar_t* jsonPayload, int64_t scheduledTimeMs, DWORD* pError);
    void CancelScheduled(const wchar_t* tag, const wchar_t* group, DWORD* pError);
    void UpdateProgress(const wchar_t* tag, const wchar_t* group,
                        double value, const wchar_t* valueStr,
                        const wchar_t* status, uint32_t seq, DWORD* pError);
    void SetBadge(int value, DWORD* pError);
    void RemoveById(uint32_t id, DWORD* pError);
    void RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError);
    void RemoveAll(DWORD* pError);
    void GetAll(wchar_t* outJson, uint32_t bufferSize, DWORD* pError);
    int  GetSetting();
    void OpenSettings(DWORD* pError);

private:
    friend class WindowsNotificationManagerTest::NotificationManagerTest;

    WindowsNotificationManager() = default;
    WindowsNotificationManager(const WindowsNotificationManager&) = delete;
    WindowsNotificationManager& operator=(const WindowsNotificationManager&) = delete;

    bool CheckInitialized(const wchar_t* caller, DWORD* pError) const;

    void OnNotificationInvoked(
        winrt::Microsoft::Windows::AppNotifications::AppNotificationManager const&,
        winrt::Microsoft::Windows::AppNotifications::AppNotificationActivatedEventArgs const& args);

    // Pure JSON validation of payload constraints (no WinRT activation required).
    // Returns false and sets *pError on the first constraint violation.
    bool ValidatePayload(const winrt::Windows::Data::Json::JsonObject& json, DWORD* pError);

    winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder
        BuildFromJson(const winrt::Windows::Data::Json::JsonObject& json, DWORD* pError);

    void ApplyButtons(
        winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder& builder,
        const winrt::Windows::Data::Json::JsonArray& buttons, DWORD* pError);
    void ApplyComboBoxes(
        winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder& builder,
        const winrt::Windows::Data::Json::JsonArray& combos, DWORD* pError);
    void ApplyImages(
        winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder& builder,
        const winrt::Windows::Data::Json::JsonObject& json);
    void ApplyAudio(
        winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder& builder,
        const winrt::Windows::Data::Json::JsonObject& audioObj, DWORD* pError);
    void ApplyProgress(
        winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder& builder,
        const winrt::Windows::Data::Json::JsonObject& progressObj);

    std::wstring ArgsToJson(
        const winrt::Windows::Foundation::Collections::IMap<winrt::hstring, winrt::hstring>& args,
        const winrt::Windows::Foundation::Collections::IMap<winrt::hstring, winrt::hstring>& userInput);

    NotificationInvokedCallback m_callback = nullptr;
    bool m_initialized = false;
    winrt::event_token m_invokedToken{};
};
