#include "pch.h"
#include "Notification/WindowsNotificationManagerInternal.h"
#include "Notification/Data/WindowsClassicActivator.h"
#include "Notification/Data/WindowsNotificationBuilder.h"
#include "Notification/Domain/WindowsNotificationValidation.h"
#include "Common/CommonInternal.h"

#include <future>
#include <algorithm>
#include <cwctype>

using namespace winrt;
using namespace winrt::Microsoft::Windows::AppNotifications;
using namespace winrt::Microsoft::Windows::AppNotifications::Builder;
using namespace winrt::Windows::UI::Notifications;
using namespace winrt::Windows::Data::Xml::Dom;
using namespace winrt::Windows::Data::Json;
// NOTE: do not pull in the whole winrt::Windows::Foundation namespace — it exposes
// winrt::Windows::Foundation::IUnknown which collides with the global ::IUnknown when
// the shell headers (shobjidl) are present. Bring in only the types we use.
using winrt::Windows::Foundation::Uri;
using winrt::Windows::Foundation::IAsyncOperation;
using namespace winrt::Windows::Foundation::Collections;

static const wchar_t* TAG = L"WindowsNotificationManager";

namespace
{
    // The OS drops a notification scheduled too far ahead, so say so rather
    // than let it disappear. Shared by both Schedule overloads.
    void WarnIfOutsideDeliveryWindow(int64_t scheduledTimeMs)
    {
        const auto tp = std::chrono::system_clock::time_point{
            std::chrono::milliseconds(scheduledTimeMs)
        };
        if ((winrt::clock::from_sys(tp) - winrt::clock::now()) > std::chrono::minutes(5))
            DLog(TAG, L"[Schedule] WARNING: scheduled time exceeds 5-minute delivery window. OS may drop the notification.");
    }

    // Run a WinRT async operation to completion without blocking on the calling
    // apartment. cppwinrt's IAsyncXxx::get() asserts (!is_sta_thread) when waited
    // on from an STA thread (the WinUI UI thread), so the work is dispatched to a
    // background (non-STA) thread where blocking is allowed.
    template <typename TFunc>
    auto RunSyncOffSta(TFunc&& func) -> decltype(func())
    {
        return std::async(std::launch::async, std::forward<TFunc>(func)).get();
    }

    // Normalize a file:// URI to a plain Windows path (percent-decode + '/'→'\').
    // Plain paths are returned unchanged.
    std::wstring NormalizeIconPath(const wchar_t* iconUri)
    {
        std::wstring s{ iconUri ? iconUri : L"" };
        constexpr std::wstring_view kScheme = L"file:///";
        if (s.size() >= kScheme.size() && _wcsnicmp(s.c_str(), kScheme.data(), kScheme.size()) == 0)
        {
            s.erase(0, kScheme.size());

            auto hexVal = [](wchar_t c) -> int {
                if (c >= L'0' && c <= L'9') return c - L'0';
                return towlower(c) - L'a' + 10;
            };
            std::wstring decoded;
            decoded.reserve(s.size());
            for (size_t i = 0; i < s.size(); ++i)
            {
                if (s[i] == L'%' && i + 2 < s.size() && iswxdigit(s[i + 1]) && iswxdigit(s[i + 2]))
                {
                    decoded.push_back(static_cast<wchar_t>(hexVal(s[i + 1]) * 16 + hexVal(s[i + 2])));
                    i += 2;
                }
                else
                {
                    decoded.push_back(s[i]);
                }
            }
            std::replace(decoded.begin(), decoded.end(), L'/', L'\\');
            return decoded;
        }
        return s;
    }
}

// =============================================================================
// PackagedBackend — Windows App SDK (new API) backend
// Defined in this TU so it can access Manager internals directly.
// =============================================================================

class PackagedBackend final : public INotificationBackend
{
public:
    void RegisterActivation(DWORD* pError) override
    {
        DLog(TAG, L"[PackagedBackend::RegisterActivation]");
        auto mgr = AppNotificationManager::Default();
        m_invokedToken = mgr.NotificationInvoked(
            [](AppNotificationManager const& sender,
               AppNotificationActivatedEventArgs const& args)
            {
                WindowsNotificationManager::GetInstance().OnNotificationInvoked(sender, args);
            });
        mgr.Register();
        if (pError) *pError = NOTIFICATION_SUCCESS;
    }

    void UnregisterActivation() override
    {
        DLog(TAG, L"[PackagedBackend::UnregisterActivation]");
        try
        {
            auto mgr = AppNotificationManager::Default();
            mgr.NotificationInvoked(m_invokedToken);
            mgr.Unregister();
        }
        catch (winrt::hresult_error const& ex)
        {
            DFLog(TAG, L"[PackagedBackend::UnregisterActivation] exception. hr=0x%08lx",
                  ex.code().value);
        }
        m_invokedToken = {};
    }

    void Deliver(const DeliverPayload& payload, DWORD* pError) override
    {
        DLog(TAG, L"[PackagedBackend::Deliver]");
        AppNotification notification{ hstring{ payload.xmlPayload } };
        if (!payload.tag.empty())   notification.Tag(hstring{ payload.tag });
        if (!payload.group.empty()) notification.Group(hstring{ payload.group });

        if (payload.hasExpiration)
            notification.Expiration(winrt::clock::now() +
                                    std::chrono::seconds(payload.expirationSec));
        if (payload.expiresOnReboot)
            notification.ExpiresOnReboot(true);

        if (payload.hasProgress)
        {
            AppNotificationProgressData data{ 1 };
            data.Value(payload.progressValue);
            if (!payload.progressValueStr.empty())
                data.ValueStringOverride(hstring{ payload.progressValueStr });
            if (!payload.progressStatus.empty())
                data.Status(hstring{ payload.progressStatus });
            notification.Progress(data);
        }

        AppNotificationManager::Default().Show(notification);
    }

    void Schedule(const DeliverPayload& payload, int64_t scheduledTimeMs, DWORD* pError) override
    {
        DFLog(TAG, L"[PackagedBackend::Schedule] scheduledTimeMs=%lld", scheduledTimeMs);
        auto tp = std::chrono::system_clock::time_point{
            std::chrono::milliseconds(scheduledTimeMs)
        };
        auto scheduledTime = winrt::clock::from_sys(tp);

        XmlDocument doc;
        doc.LoadXml(hstring{ payload.xmlPayload });

        ScheduledToastNotification scheduled{ doc, scheduledTime };
        if (!payload.tag.empty())   scheduled.Tag(hstring{ payload.tag });
        if (!payload.group.empty()) scheduled.Group(hstring{ payload.group });

        // WinAppSDK has no schedule API; use classic ToastNotificationManager
        // (no AUMID — packaged apps use the parameterless notifier).
        ToastNotificationManager::CreateToastNotifier().AddToSchedule(scheduled);
    }

    void CancelSchedule(const wchar_t* tag, const wchar_t* group, DWORD* pError) override
    {
        auto notifier  = ToastNotificationManager::CreateToastNotifier();
        auto scheduled = notifier.GetScheduledToastNotifications();

        hstring tagStr  { tag   ? tag   : L"" };
        hstring groupStr{ group ? group : L"" };

        for (auto const& item : scheduled)
        {
            bool tagMatch   = tagStr.empty()   || item.Tag()   == tagStr;
            bool groupMatch = groupStr.empty() || item.Group() == groupStr;
            if (tagMatch && groupMatch)
                notifier.RemoveFromSchedule(item);
        }
    }

    void SetBadge(int value, DWORD* pError) override
    {
        DFLog(TAG, L"[PackagedBackend::SetBadge] value=%d", value);
        auto updater = BadgeUpdateManager::CreateBadgeUpdaterForApplication();
        if (value == 0) { updater.Clear(); return; }

        std::wstring xml;
        if (value > 0)
        {
            xml = L"<badge value=\"" + std::to_wstring(value) + L"\"/>";
        }
        else
        {
            static const wchar_t* glyphs[] =
                { L"", L"alert", L"activity", L"newMessage", L"available", L"busy", L"away" };
            xml = std::wstring(L"<badge value=\"") + glyphs[-value] + L"\"/>";
        }
        XmlDocument doc;
        doc.LoadXml(xml);
        updater.Update(BadgeNotification{ doc });
    }

    void UpdateProgress(const wchar_t* tag, const wchar_t* group,
                        double value, const wchar_t* valueStr,
                        const wchar_t* status, uint32_t seq, DWORD* pError) override
    {
        AppNotificationProgressData data{ seq };
        data.Value(value);
        if (valueStr) data.ValueStringOverride(hstring{ valueStr });
        if (status)   data.Status(hstring{ status });

        hstring tagStr  { tag   ? tag   : L"" };
        hstring groupStr{ group ? group : L"" };

        auto result = RunSyncOffSta([&]
        {
            return groupStr.empty()
                ? AppNotificationManager::Default().UpdateAsync(data, tagStr).get()
                : AppNotificationManager::Default().UpdateAsync(data, tagStr, groupStr).get();
        });
        if (result != AppNotificationProgressResult::Succeeded)
        {
            if (pError) *pError = NOTIFICATION_ERROR_PROGRESS_NOT_FOUND;
        }
    }

    void RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError) override
    {
        hstring tagStr  { tag   ? tag   : L"" };
        hstring groupStr{ group ? group : L"" };
        RunSyncOffSta([&]
        {
            if (groupStr.empty())
                AppNotificationManager::Default().RemoveByTagAsync(tagStr).get();
            else
                AppNotificationManager::Default().RemoveByTagAndGroupAsync(tagStr, groupStr).get();
        });
    }

    void RemoveAll(DWORD* pError) override
    {
        RunSyncOffSta([&] { AppNotificationManager::Default().RemoveAllAsync().get(); });
    }

    void RemoveById(uint32_t id, DWORD* pError) override
    {
        RunSyncOffSta([&] { AppNotificationManager::Default().RemoveByIdAsync(id).get(); });
    }

    void GetAll(wchar_t* outJson, uint32_t bufferSize, DWORD* pError) override
    {
        auto notifications = RunSyncOffSta([&]
        {
            return AppNotificationManager::Default().GetAllAsync().get();
        });

        JsonArray arr;
        for (auto const& n : notifications)
        {
            JsonObject obj;
            obj.Insert(L"id",    JsonValue::CreateNumberValue(static_cast<double>(n.Id())));
            obj.Insert(L"tag",   JsonValue::CreateStringValue(n.Tag()));
            obj.Insert(L"group", JsonValue::CreateStringValue(n.Group()));
            arr.Append(obj);
        }

        auto str = arr.Stringify();
        wcsncpy_s(outJson, bufferSize, str.c_str(), _TRUNCATE);
    }

    int Setting() override
    {
        auto s = AppNotificationManager::Default().Setting();
        switch (s)
        {
        case AppNotificationSetting::Enabled:                return 0;
        case AppNotificationSetting::DisabledForApplication: return 1;
        case AppNotificationSetting::DisabledForUser:        return 2;
        case AppNotificationSetting::DisabledByGroupPolicy:  return 3;
        case AppNotificationSetting::DisabledByManifest:     return 4;
        default:                                             return -1;
        }
    }

private:
    winrt::event_token m_invokedToken{};
};

// =============================================================================
// Singleton
// =============================================================================

WindowsNotificationManager& WindowsNotificationManager::GetInstance()
{
    static WindowsNotificationManager instance;
    return instance;
}

// =============================================================================
// Helper
// =============================================================================

bool WindowsNotificationManager::CheckInitialized(const wchar_t* caller, DWORD* pError) const
{
    if (!m_initialized)
    {
        DFLog(TAG, L"[%ls] not initialized", caller);
        if (pError) *pError = NOTIFICATION_ERROR_NOT_INITIALIZED;
        return false;
    }
    return true;
}

bool WindowsNotificationManager::CheckEnabled(const wchar_t* caller, DWORD* pError)
{
    const int setting = m_backend->Setting();
    if (setting != 0)
    {
        DFLog(TAG, L"[%ls] notification disabled. setting=%d", caller, setting);
        if (pError) *pError = NOTIFICATION_ERROR_DISABLED;
        return false;
    }
    return true;
}

void WindowsNotificationManager::InvokeCallback(const std::wstring& argsJson)
{
    NotificationInvokedCallback cb;
    {
        std::lock_guard<std::mutex> lk(m_callbackMutex);
        cb = m_callback;
    }
    if (cb) cb(argsJson.c_str());
}

void WindowsNotificationManager::SetBackendForTest(std::unique_ptr<INotificationBackend> backend)
{
    m_backend = std::move(backend);
}

void WindowsNotificationManager::SetCallbackForTest(NotificationInvokedCallback callback)
{
    std::lock_guard<std::mutex> lk(m_callbackMutex);
    m_callback = callback;
}

// =============================================================================
// Init / Uninit
// =============================================================================

void WindowsNotificationManager::Init(
    NotificationInvokedCallback callback,
    BOOL isPackaged,
    const wchar_t* displayName,
    const wchar_t* iconUri,
    DWORD* pError)
{
    DFLog(TAG, L"[Init] isPackaged=%d, displayName=%ls, iconUri=%ls",
          isPackaged,
          displayName ? displayName : L"null",
          iconUri     ? iconUri     : L"null");

    if (pError) *pError = NOTIFICATION_SUCCESS;

    // Refresh callback even on re-entry
    {
        std::lock_guard<std::mutex> lk(m_callbackMutex);
        m_callback = callback;
    }

    if (m_initialized)
    {
        DLog(TAG, L"[Init] already initialized; skipping re-registration");
        return;
    }

    const HRESULT hrCom = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hrCom) && hrCom != RPC_E_CHANGED_MODE)
    {
        DFLog(TAG, L"[Init] CoInitializeEx failed. hr=0x%08lx", hrCom);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
        return;
    }

    try
    {
        // Backend creation — the ONLY place where packaged/unpackaged branches.
        if (isPackaged)
        {
            m_backend = std::make_unique<PackagedBackend>();
        }
        else
        {
            if (!displayName || !*displayName || !iconUri || !*iconUri)
            {
                DLog(TAG, L"[Init] displayName and iconUri are required for unpackaged app");
                if (pError) *pError = NOTIFICATION_ERROR_INVALID_PARAMETER;
                return;
            }
            std::wstring iconPath = NormalizeIconPath(iconUri);
            m_backend = std::make_unique<UnpackagedBackend>(
                std::wstring{ displayName }, std::move(iconPath));
        }

        m_backend->RegisterActivation(pError);
        if (pError && *pError != NOTIFICATION_SUCCESS)
        {
            m_backend.reset();
            return;
        }

        if (!isPackaged && !m_launchActivationConsumed)
        {
            std::wstring launchArgsJson;
            if (TryGetLaunchActivationJson(&launchArgsJson))
            {
                DFLog(TAG, L"[Init] consuming launch activation fallback. argsJson=%ls",
                      launchArgsJson.c_str());
                m_launchActivationConsumed = true;
                InvokeCallback(launchArgsJson);
            }
        }

        int setting = m_backend->Setting();
        DFLog(TAG, L"[Init] NotificationSetting=%d", setting);

        // Warn if running as administrator — Show() may silently fail
        HANDLE token = nullptr;
        if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
        {
            TOKEN_ELEVATION elevation{};
            DWORD size = sizeof(elevation);
            if (GetTokenInformation(token, TokenElevation, &elevation, size, &size))
            {
                if (elevation.TokenIsElevated)
                    DLog(TAG, L"[Init] WARNING: running as administrator. Show() may silently fail.");
            }
            CloseHandle(token);
        }

        m_initialized = true;
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[Init] WinRT exception. hr=0x%08lx", ex.code().value);
        m_backend.reset();
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

void WindowsNotificationManager::Uninit()
{
    DLog(TAG, L"[Uninit]");

    if (!m_initialized) return;

    // Revoke activation first, then null the callback.
    // After revoke, no new Activate() calls will arrive, so the race window is closed.
    if (m_backend)
        m_backend->UnregisterActivation();

    {
        std::lock_guard<std::mutex> lk(m_callbackMutex);
        m_callback = nullptr;
    }

    m_backend.reset();
    m_launchActivationConsumed = false;
    m_initialized = false;
}

// =============================================================================
// OnNotificationInvoked / ArgsToJson (PackagedBackend callback path)
// =============================================================================

void WindowsNotificationManager::OnNotificationInvoked(
    AppNotificationManager const&,
    AppNotificationActivatedEventArgs const& args)
{
    DLog(TAG, L"[OnNotificationInvoked]");
    try
    {
        auto arguments = args.Arguments();
        auto userInput  = args.UserInput();
        std::wstring json = ArgsToJson(arguments, userInput);
        InvokeCallback(json);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[OnNotificationInvoked] WinRT exception. hr=0x%08lx", ex.code().value);
    }
}

std::wstring WindowsNotificationManager::ArgsToJson(
    const IMap<hstring, hstring>& args,
    const IMap<hstring, hstring>& userInput)
{
    DLog(TAG, L"[ArgsToJson]");

    JsonObject root;
    for (auto const& kv : args)
        root.Insert(kv.Key(), JsonValue::CreateStringValue(kv.Value()));
    for (auto const& kv : userInput)
        root.Insert(kv.Key(), JsonValue::CreateStringValue(kv.Value()));

    return std::wstring{ root.Stringify() };
}

// =============================================================================
// BuildPayload
//
// The payload arrives as a NotificationContent, whoever is asking: the C
// ABI builds one with its content builder. There is one way to build a
// notification here rather than one for each caller.
// =============================================================================

DeliverPayload WindowsNotificationManager::BuildPayload(
    const NativeToolkit::Notification::NotificationContent& content, DWORD* pError)
{
    DLog(TAG, L"[BuildPayload] from content");

    namespace Api = NativeToolkit::Notification;

    DeliverPayload payload;

    const auto validated = Api::Domain::Validate(content);
    if (!validated.has_value())
    {
        DLog(TAG, L"[BuildPayload] validation failed");
        if (pError) *pError = static_cast<DWORD>(validated.error().code);
        return payload;
    }

    auto notification = Api::Data::BuildFromContent(content).BuildNotification();
    payload.xmlPayload = std::wstring{ notification.Payload() };

    payload.tag   = content.tag;
    payload.group = content.group;

    if (content.expiration.has_value())
    {
        payload.hasExpiration = true;
        payload.expirationSec = content.expiration->count();
    }
    payload.expiresOnReboot = content.expiresOnReboot;

    if (content.progress.has_value())
    {
        payload.hasProgress   = true;
        payload.progressValue = content.progress->value;
        if (content.progress->valueStr.has_value())
            payload.progressValueStr = *content.progress->valueStr;
        if (content.progress->status.has_value())
            payload.progressStatus = *content.progress->status;
    }

    return payload;
}

void WindowsNotificationManager::Show(
    const NativeToolkit::Notification::NotificationContent& content, DWORD* pError)
{
    DFLog(TAG, L"[Show] content. title=%ls", content.title.value_or(L"(none)").c_str());

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"Show", pError)) return;

    try
    {
        if (!CheckEnabled(L"Show", pError)) return;

        DWORD buildErr = NOTIFICATION_SUCCESS;
        DeliverPayload payload = BuildPayload(content, &buildErr);
        if (buildErr != NOTIFICATION_SUCCESS)
        {
            if (pError) *pError = buildErr;
            return;
        }

        m_backend->Deliver(payload, pError);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[Show] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

// =============================================================================
// Schedule / CancelScheduled
// =============================================================================

void WindowsNotificationManager::Schedule(
    const NativeToolkit::Notification::NotificationContent& content,
    int64_t scheduledTimeMs,
    DWORD* pError)
{
    DFLog(TAG, L"[Schedule] content. scheduledTimeMs=%lld", scheduledTimeMs);

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"Schedule", pError)) return;

    try
    {
        if (!CheckEnabled(L"Schedule", pError)) return;

        DWORD buildErr = NOTIFICATION_SUCCESS;
        DeliverPayload payload = BuildPayload(content, &buildErr);
        if (buildErr != NOTIFICATION_SUCCESS)
        {
            if (pError) *pError = buildErr;
            return;
        }

        WarnIfOutsideDeliveryWindow(scheduledTimeMs);

        m_backend->Schedule(payload, scheduledTimeMs, pError);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[Schedule] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

void WindowsNotificationManager::CancelScheduled(
    const wchar_t* tag,
    const wchar_t* group,
    DWORD* pError)
{
    DFLog(TAG, L"[CancelScheduled] tag=%ls, group=%ls",
          tag   ? tag   : L"null",
          group ? group : L"null");

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"CancelScheduled", pError)) return;

    try
    {
        m_backend->CancelSchedule(tag, group, pError);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[CancelScheduled] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

// =============================================================================
// UpdateProgress
// =============================================================================

void WindowsNotificationManager::UpdateProgress(
    const wchar_t* tag,
    const wchar_t* group,
    double value,
    const wchar_t* valueStr,
    const wchar_t* status,
    uint32_t seq,
    DWORD* pError)
{
    DFLog(TAG, L"[UpdateProgress] tag=%ls, value=%.2f, seq=%u",
          tag ? tag : L"null", value, seq);

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"UpdateProgress", pError)) return;

    try
    {
        m_backend->UpdateProgress(tag, group, value, valueStr, status, seq, pError);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[UpdateProgress] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

// =============================================================================
// SetBadge
// =============================================================================

void WindowsNotificationManager::SetBadge(int value, DWORD* pError)
{
    DFLog(TAG, L"[SetBadge] value=%d", value);

    if (pError) *pError = NOTIFICATION_SUCCESS;

    if (value < -6)
    {
        DFLog(TAG, L"[SetBadge] validation failed. value=%d is out of range", value);
        if (pError) *pError = NOTIFICATION_ERROR_INVALID_PARAMETER;
        return;
    }

    if (!CheckInitialized(L"SetBadge", pError)) return;

    try
    {
        m_backend->SetBadge(value, pError);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[SetBadge] WinRT exception. value=%d, hr=0x%08lx", value, ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_BADGE_FAILED;
    }
}

// =============================================================================
// Remove / GetAll
// =============================================================================

void WindowsNotificationManager::RemoveById(uint32_t id, DWORD* pError)
{
    DFLog(TAG, L"[RemoveById] id=%u", id);

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"RemoveById", pError)) return;

    try
    {
        m_backend->RemoveById(id, pError);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[RemoveById] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

void WindowsNotificationManager::RemoveByTag(
    const wchar_t* tag, const wchar_t* group, DWORD* pError)
{
    DFLog(TAG, L"[RemoveByTag] tag=%ls, group=%ls",
          tag   ? tag   : L"null",
          group ? group : L"null");

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"RemoveByTag", pError)) return;

    try
    {
        m_backend->RemoveByTag(tag, group, pError);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[RemoveByTag] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

void WindowsNotificationManager::RemoveAll(DWORD* pError)
{
    DLog(TAG, L"[RemoveAll]");

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"RemoveAll", pError)) return;

    try
    {
        m_backend->RemoveAll(pError);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[RemoveAll] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

void WindowsNotificationManager::GetAll(
    wchar_t* outJson, uint32_t bufferSize, DWORD* pError)
{
    DFLog(TAG, L"[GetAll] bufferSize=%u", bufferSize);

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"GetAll", pError)) return;

    try
    {
        m_backend->GetAll(outJson, bufferSize, pError);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[GetAll] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

// =============================================================================
// GetSetting
// =============================================================================

int WindowsNotificationManager::GetSetting()
{
    DLog(TAG, L"[GetSetting]");

    if (!m_initialized || !m_backend) return -1;
    try
    {
        return m_backend->Setting();
    }
    catch (...)
    {
        return -1;
    }
}

// =============================================================================
// OpenSettings
// =============================================================================

void WindowsNotificationManager::OpenSettings(DWORD* pError)
{
    DLog(TAG, L"[OpenSettings]");

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"OpenSettings", pError)) return;

    try
    {
        Uri uri{ L"ms-settings:notifications" };
        bool launched = RunSyncOffSta([&]
        {
            return winrt::Windows::System::Launcher::LaunchUriAsync(uri).get();
        });
        if (!launched)
        {
            DLog(TAG, L"[OpenSettings] LaunchUriAsync returned false");
            if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
        }
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[OpenSettings] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}
