#pragma once

// WinRT headers must be included before this file (via pch.h or test pch.h).
// Requires: winrt/base.h, winrt/Microsoft.Windows.AppNotifications.h,
//           winrt/Microsoft.Windows.AppNotifications.Builder.h,
//           winrt/Windows.UI.Notifications.h, winrt/Windows.Data.Json.h

#include "Notification/WindowsNotificationManager.h"
#include "Notification/Application/WindowsNotificationBackend.h"
#include "NativeToolkit/Notification.h"
#include <memory>
#include <mutex>
#include <string>

class PackagedBackend;  // defined in WindowsNotificationManager.cpp

namespace WindowsNotificationManagerTest { class NotificationManagerTest; }
namespace WindowsNotificationValidationDomainTest { class NotificationValidationDomainTest; }
namespace WindowsNotificationBuilderTest { class NotificationBuilderTest; }
namespace WindowsNotificationApiTest { class NotificationApiTest; }
namespace WindowsNotificationPayloadTest { class NotificationPayloadTest; }

class WindowsNotificationManager
{
public:
    static WindowsNotificationManager& GetInstance();

    void InitWinAppSdk(uint32_t majorMinorVersion, DWORD* pError);
    void Init(NotificationInvokedCallback callback, BOOL isPackaged,
              const wchar_t* displayName, const wchar_t* iconUri, DWORD* pError);
    void Uninit();
    // A notification is described by a NotificationContent, whoever is asking:
    // the C ABI's JSON is read into one by the bridge. Both check that
    // notifications are enabled before they build, so a disabled app is told
    // it is disabled rather than told its content is wrong.
    void Show(const NativeToolkit::Notification::NotificationContent& content, DWORD* pError);
    void Schedule(const NativeToolkit::Notification::NotificationContent& content,
                  int64_t scheduledTimeMs, DWORD* pError);
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

    // Thread-safe callback relay. Called by both PackagedBackend (NotificationInvoked
    // event) and UnpackagedBackend (INotificationActivationCallback::Activate).
    void InvokeCallback(const std::wstring& argsJson);

    // Test seam: replace the backend with a mock for WinRT-free unit tests.
    void SetBackendForTest(std::unique_ptr<INotificationBackend> backend);

    // Test seam: install the activation callback without going through Init,
    // which would register this process with the OS.
    void SetCallbackForTest(NotificationInvokedCallback callback);

private:
    friend class PackagedBackend;
    friend class WindowsNotificationManagerTest::NotificationManagerTest;
    /// The Domain rules are compared against these JSON rules; see
    /// NotificationValidationDomainTest (stage 3, T-07).
    friend class WindowsNotificationValidationDomainTest::NotificationValidationDomainTest;
    /// The struct path is compared against this one, XML against XML; see
    /// NotificationBuilderTest (stage 3, T-08).
    friend class WindowsNotificationBuilderTest::NotificationBuilderTest;
    /// Drives the C++ API against a mock backend; see NotificationApiTest
    /// (stage 3, T-08).
    friend class WindowsNotificationApiTest::NotificationApiTest;
    /// Records what the JSON payload accepts today, so T-14 can move the parse
    /// without changing any of it; see NotificationPayloadTest (stage 3, T-17).
    friend class WindowsNotificationPayloadTest::NotificationPayloadTest;

    WindowsNotificationManager() = default;
    WindowsNotificationManager(const WindowsNotificationManager&) = delete;
    WindowsNotificationManager& operator=(const WindowsNotificationManager&) = delete;

    bool CheckInitialized(const wchar_t* caller, DWORD* pError) const;

    /// False, and *pError set to DISABLED, when the OS has notifications off.
    bool CheckEnabled(const wchar_t* caller, DWORD* pError);

    void OnNotificationInvoked(
        winrt::Microsoft::Windows::AppNotifications::AppNotificationManager const&,
        winrt::Microsoft::Windows::AppNotifications::AppNotificationActivatedEventArgs const& args);

    /// Validates the content against the Domain rules and captures the XML,
    /// the tag and the group, plus the expiration and progress the backend
    /// needs but the XML does not carry.
    DeliverPayload BuildPayload(const NativeToolkit::Notification::NotificationContent& content,
                                DWORD* pError);

    std::wstring ArgsToJson(
        const winrt::Windows::Foundation::Collections::IMap<winrt::hstring, winrt::hstring>& args,
        const winrt::Windows::Foundation::Collections::IMap<winrt::hstring, winrt::hstring>& userInput);

    std::unique_ptr<INotificationBackend> m_backend;
    NotificationInvokedCallback           m_callback  = nullptr;
    std::mutex                            m_callbackMutex;
    bool                                  m_launchActivationConsumed = false;
    bool                                  m_initialized = false;
};
