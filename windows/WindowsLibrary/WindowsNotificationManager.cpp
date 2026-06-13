#include "pch.h"
#include "WindowsNotificationManagerInternal.h"
#include "WindowsClassicActivator.h"
#include "common.h"

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
// MFC's shell headers (shobjidl) are present. Bring in only the types we use.
using winrt::Windows::Foundation::Uri;
using winrt::Windows::Foundation::IAsyncOperation;
using namespace winrt::Windows::Foundation::Collections;

static const wchar_t* TAG = L"WindowsNotificationManager";

namespace
{
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
        auto& mgr = AppNotificationManager::Default();
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
            auto& mgr = AppNotificationManager::Default();
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
// BuildFromJson + BuildPayload + sub-builders
// =============================================================================

bool WindowsNotificationManager::ValidatePayload(const JsonObject& json, DWORD* pError)
{
    DLog(TAG, L"[ValidatePayload]");

    bool isDurationLong = json.HasKey(L"duration") && json.GetNamedString(L"duration") == L"long";
    if (json.HasKey(L"audio"))
    {
        auto audioObj = json.GetNamedObject(L"audio");
        if (audioObj.HasKey(L"loop") && audioObj.GetNamedBoolean(L"loop") && !isDurationLong)
        {
            DFLog(TAG, L"[ValidatePayload] validation failed. reason=audio.loop requires duration=long");
            if (pError) *pError = NOTIFICATION_ERROR_INVALID_PARAMETER;
            return false;
        }
    }

    if (json.HasKey(L"buttons"))
    {
        auto buttons = json.GetNamedArray(L"buttons");
        if (buttons.Size() > 5)
        {
            DFLog(TAG, L"[ValidatePayload] validation failed. reason=buttons count exceeds 5 (count=%u)",
                  buttons.Size());
            if (pError) *pError = NOTIFICATION_ERROR_INVALID_PARAMETER;
            return false;
        }
        for (auto const& item : buttons)
        {
            auto btn = item.GetObject();
            if (btn.HasKey(L"args") && btn.HasKey(L"invokeUri"))
            {
                DFLog(TAG, L"[ValidatePayload] validation failed. reason=button has both args and invokeUri");
                if (pError) *pError = NOTIFICATION_ERROR_INVALID_PARAMETER;
                return false;
            }
        }
    }

    return true;
}

AppNotificationBuilder WindowsNotificationManager::BuildFromJson(
    const JsonObject& json, DWORD* pError)
{
    DLog(TAG, L"[BuildFromJson]");

    if (!ValidatePayload(json, pError))
        return nullptr;

    AppNotificationBuilder builder;

    if (json.HasKey(L"title"))
        builder.AddText(json.GetNamedString(L"title"));
    if (json.HasKey(L"body"))
        builder.AddText(json.GetNamedString(L"body"));
    if (json.HasKey(L"tag"))
        builder.SetTag(json.GetNamedString(L"tag"));
    if (json.HasKey(L"group"))
        builder.SetGroup(json.GetNamedString(L"group"));

    if (json.HasKey(L"scenario"))
    {
        auto s = json.GetNamedString(L"scenario");
        if      (s == L"reminder")    builder.SetScenario(AppNotificationScenario::Reminder);
        else if (s == L"alarm")       builder.SetScenario(AppNotificationScenario::Alarm);
        else if (s == L"urgent")      builder.SetScenario(AppNotificationScenario::Urgent);
        else if (s == L"incomingCall")builder.SetScenario(AppNotificationScenario::IncomingCall);
    }

    bool isDurationLong = json.HasKey(L"duration") && json.GetNamedString(L"duration") == L"long";
    if (isDurationLong)
        builder.SetDuration(AppNotificationDuration::Long);

    if (json.HasKey(L"buttons"))
    {
        ApplyButtons(builder, json.GetNamedArray(L"buttons"), pError);
        if (pError && *pError != NOTIFICATION_SUCCESS) return builder;
    }

    if (json.HasKey(L"textBoxes"))
    {
        for (auto const& item : json.GetNamedArray(L"textBoxes"))
        {
            auto box = item.GetObject();
            auto id  = box.GetNamedString(L"id");
            if (box.HasKey(L"placeholder") || box.HasKey(L"title"))
            {
                hstring placeholder = box.HasKey(L"placeholder") ? box.GetNamedString(L"placeholder") : hstring{};
                hstring title       = box.HasKey(L"title")       ? box.GetNamedString(L"title")       : hstring{};
                builder.AddTextBox(id, placeholder, title);
            }
            else
            {
                builder.AddTextBox(id);
            }
        }
    }

    if (json.HasKey(L"comboBoxes"))
    {
        ApplyComboBoxes(builder, json.GetNamedArray(L"comboBoxes"), pError);
        if (pError && *pError != NOTIFICATION_SUCCESS) return builder;
    }

    ApplyImages(builder, json);

    if (json.HasKey(L"audio"))
    {
        ApplyAudio(builder, json.GetNamedObject(L"audio"), pError);
        if (pError && *pError != NOTIFICATION_SUCCESS) return builder;
    }

    if (json.HasKey(L"progress"))
        ApplyProgress(builder, json.GetNamedObject(L"progress"));

    if (json.HasKey(L"attribution"))
        builder.SetAttributionText(json.GetNamedString(L"attribution"));

    if (json.HasKey(L"timestamp"))
    {
        auto unixSec = static_cast<time_t>(json.GetNamedNumber(L"timestamp"));
        auto tp = std::chrono::system_clock::from_time_t(unixSec);
        builder.SetTimeStamp(winrt::clock::from_sys(tp));
    }

    return builder;
}

DeliverPayload WindowsNotificationManager::BuildPayload(const JsonObject& json, DWORD* pError)
{
    DeliverPayload payload;

    DWORD buildErr = NOTIFICATION_SUCCESS;
    auto builder = BuildFromJson(json, &buildErr);
    if (buildErr != NOTIFICATION_SUCCESS)
    {
        if (pError) *pError = buildErr;
        return payload;
    }

    auto notification = builder.BuildNotification();
    payload.xmlPayload = std::wstring{ notification.Payload() };

    if (json.HasKey(L"tag"))
        payload.tag = std::wstring{ json.GetNamedString(L"tag") };
    if (json.HasKey(L"group"))
        payload.group = std::wstring{ json.GetNamedString(L"group") };

    if (json.HasKey(L"expiration"))
    {
        payload.hasExpiration = true;
        payload.expirationSec = static_cast<int64_t>(json.GetNamedNumber(L"expiration"));
    }
    if (json.HasKey(L"expiresOnReboot") && json.GetNamedBoolean(L"expiresOnReboot"))
        payload.expiresOnReboot = true;

    if (json.HasKey(L"progress"))
    {
        payload.hasProgress = true;
        auto progressObj = json.GetNamedObject(L"progress");
        payload.progressValue = progressObj.HasKey(L"value")
            ? progressObj.GetNamedNumber(L"value") : 0.0;
        if (progressObj.HasKey(L"valueStr"))
            payload.progressValueStr = std::wstring{ progressObj.GetNamedString(L"valueStr") };
        if (progressObj.HasKey(L"status"))
            payload.progressStatus = std::wstring{ progressObj.GetNamedString(L"status") };
    }

    return payload;
}

void WindowsNotificationManager::ApplyButtons(
    AppNotificationBuilder& builder,
    const JsonArray& buttons,
    DWORD* pError)
{
    DLog(TAG, L"[ApplyButtons]");

    for (auto const& item : buttons)
    {
        auto btn     = item.GetObject();
        auto label   = btn.GetNamedString(L"label");
        bool hasArgs = btn.HasKey(L"args");
        bool hasUri  = btn.HasKey(L"invokeUri");

        if (hasArgs && hasUri)
        {
            DFLog(TAG, L"[ApplyButtons] validation failed. reason=button has both args and invokeUri");
            if (pError) *pError = NOTIFICATION_ERROR_INVALID_PARAMETER;
            return;
        }

        AppNotificationButton button{ label };

        if (hasUri)
        {
            button.InvokeUri(Uri{ btn.GetNamedString(L"invokeUri") });
        }
        else if (hasArgs)
        {
            for (auto const& kv : btn.GetNamedObject(L"args"))
                button.AddArgument(kv.Key(), kv.Value().GetString());
        }

        builder.AddButton(button);
    }
}

void WindowsNotificationManager::ApplyComboBoxes(
    AppNotificationBuilder& builder,
    const JsonArray& combos,
    DWORD* pError)
{
    DLog(TAG, L"[ApplyComboBoxes]");

    for (auto const& item : combos)
    {
        auto combo = item.GetObject();
        AppNotificationComboBox comboBox{ combo.GetNamedString(L"id") };

        if (combo.HasKey(L"title"))
            comboBox.Title(combo.GetNamedString(L"title"));

        if (combo.HasKey(L"items"))
        {
            for (auto const& entry : combo.GetNamedArray(L"items"))
            {
                auto e = entry.GetObject();
                comboBox.AddItem(e.GetNamedString(L"id"), e.GetNamedString(L"label"));
            }
        }

        if (combo.HasKey(L"defaultSelection"))
            comboBox.SelectedItem(combo.GetNamedString(L"defaultSelection"));

        builder.AddComboBox(comboBox);
    }
}

void WindowsNotificationManager::ApplyImages(
    AppNotificationBuilder& builder,
    const JsonObject& json)
{
    DLog(TAG, L"[ApplyImages]");

    if (json.HasKey(L"appLogo"))
    {
        auto logo = json.GetNamedObject(L"appLogo");
        auto crop = (logo.HasKey(L"crop") && logo.GetNamedString(L"crop") == L"circle")
                    ? AppNotificationImageCrop::Circle
                    : AppNotificationImageCrop::Default;
        builder.SetAppLogoOverride(Uri{ logo.GetNamedString(L"uri") }, crop);
    }

    if (json.HasKey(L"heroImage"))
        builder.SetHeroImage(Uri{ json.GetNamedString(L"heroImage") });

    if (json.HasKey(L"inlineImage"))
        builder.SetInlineImage(Uri{ json.GetNamedString(L"inlineImage") });
}

void WindowsNotificationManager::ApplyAudio(
    AppNotificationBuilder& builder,
    const JsonObject& audioObj,
    DWORD* pError)
{
    DLog(TAG, L"[ApplyAudio]");

    hstring type = audioObj.HasKey(L"type") ? audioObj.GetNamedString(L"type") : L"event";

    if (type == L"mute")
    {
        builder.MuteAudio();
        return;
    }

    bool loops = audioObj.HasKey(L"loop") && audioObj.GetNamedBoolean(L"loop");
    auto looping = loops ? AppNotificationAudioLooping::Loop
                         : AppNotificationAudioLooping::None;

    if (type == L"uri")
    {
        if (!audioObj.HasKey(L"uri"))
        {
            DFLog(TAG, L"[ApplyAudio] validation failed. reason=audio.type=uri requires uri field");
            if (pError) *pError = NOTIFICATION_ERROR_INVALID_PARAMETER;
            return;
        }
        builder.SetAudioUri(Uri{ audioObj.GetNamedString(L"uri") }, looping);
        return;
    }

    AppNotificationSoundEvent soundEvent = AppNotificationSoundEvent::Default;
    if (audioObj.HasKey(L"event"))
    {
        auto ev = audioObj.GetNamedString(L"event");
        if      (ev == L"reminder")    soundEvent = AppNotificationSoundEvent::Reminder;
        else if (ev == L"alarm")       soundEvent = AppNotificationSoundEvent::Alarm;
        else if (ev == L"loopingAlarm")soundEvent = AppNotificationSoundEvent::Alarm;
        else if (ev == L"loopingCall") soundEvent = AppNotificationSoundEvent::Call;
    }

    builder.SetAudioEvent(soundEvent, looping);
}

void WindowsNotificationManager::ApplyProgress(
    AppNotificationBuilder& builder,
    const JsonObject& progressObj)
{
    DLog(TAG, L"[ApplyProgress]");

    AppNotificationProgressBar progressBar;

    if (progressObj.HasKey(L"title"))
        progressBar.Title(progressObj.GetNamedString(L"title"));

    progressBar.BindValue();
    if (progressObj.HasKey(L"valueStr"))
        progressBar.BindValueStringOverride();
    if (progressObj.HasKey(L"status"))
        progressBar.BindStatus();

    builder.AddProgressBar(progressBar);
}

// =============================================================================
// Show
// =============================================================================

void WindowsNotificationManager::Show(const wchar_t* jsonPayload, DWORD* pError)
{
    DFLog(TAG, L"[Show] jsonPayload=%ls", jsonPayload ? jsonPayload : L"null");

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"Show", pError)) return;

    try
    {
        int setting = m_backend->Setting();
        if (setting != 0)
        {
            DFLog(TAG, L"[Show] notification disabled. setting=%d", setting);
            if (pError) *pError = NOTIFICATION_ERROR_DISABLED;
            return;
        }

        JsonObject json;
        if (!JsonObject::TryParse(hstring{ jsonPayload }, json))
        {
            DLog(TAG, L"[Show] invalid JSON payload");
            if (pError) *pError = NOTIFICATION_ERROR_INVALID_PAYLOAD;
            return;
        }

        DWORD buildErr = NOTIFICATION_SUCCESS;
        DeliverPayload payload = BuildPayload(json, &buildErr);
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
    const wchar_t* jsonPayload,
    int64_t scheduledTimeMs,
    DWORD* pError)
{
    DFLog(TAG, L"[Schedule] scheduledTimeMs=%lld", scheduledTimeMs);

    if (pError) *pError = NOTIFICATION_SUCCESS;
    if (!CheckInitialized(L"Schedule", pError)) return;

    try
    {
        int setting = m_backend->Setting();
        if (setting != 0)
        {
            DFLog(TAG, L"[Schedule] notification disabled. setting=%d", setting);
            if (pError) *pError = NOTIFICATION_ERROR_DISABLED;
            return;
        }

        JsonObject json;
        if (!JsonObject::TryParse(hstring{ jsonPayload }, json))
        {
            DLog(TAG, L"[Schedule] invalid JSON payload");
            if (pError) *pError = NOTIFICATION_ERROR_INVALID_PAYLOAD;
            return;
        }

        DWORD buildErr = NOTIFICATION_SUCCESS;
        DeliverPayload payload = BuildPayload(json, &buildErr);
        if (buildErr != NOTIFICATION_SUCCESS)
        {
            if (pError) *pError = buildErr;
            return;
        }

        // Warn if scheduled time is far in the future (OS delivery window)
        {
            auto tp = std::chrono::system_clock::time_point{
                std::chrono::milliseconds(scheduledTimeMs)
            };
            auto scheduledTime = winrt::clock::from_sys(tp);
            if ((scheduledTime - winrt::clock::now()) > std::chrono::minutes(5))
                DLog(TAG, L"[Schedule] WARNING: scheduled time exceeds 5-minute delivery window. OS may drop the notification.");
        }

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

// =============================================================================
// C Bridge API
// =============================================================================
//
// NOTE: InitWinAppSdk / initWinAppSdk live in WindowsAppSdkBootstrap.cpp so
// the unit test (which compiles this file) does not depend on Bootstrap.dll.

void initNotificationManager(
    NotificationInvokedCallback callback,
    BOOL isPackaged,
    const wchar_t* displayName,
    const wchar_t* iconUri,
    DWORD* pError)
{
    DFLog(TAG, L"[initNotificationManager] isPackaged=%d", isPackaged);
    WindowsNotificationManager::GetInstance().Init(
        callback, isPackaged, displayName, iconUri, pError);
}

void uninitNotificationManager()
{
    DLog(TAG, L"[uninitNotificationManager]");
    WindowsNotificationManager::GetInstance().Uninit();
}

void showNotification(const wchar_t* jsonPayload, DWORD* pError)
{
    DFLog(TAG, L"[showNotification] jsonPayload=%ls", jsonPayload ? jsonPayload : L"null");
    WindowsNotificationManager::GetInstance().Show(jsonPayload, pError);
}

void scheduleNotification(
    const wchar_t* jsonPayload, int64_t scheduledTimeUnixMs, DWORD* pError)
{
    DFLog(TAG, L"[scheduleNotification] scheduledTimeUnixMs=%lld", scheduledTimeUnixMs);
    WindowsNotificationManager::GetInstance().Schedule(
        jsonPayload, scheduledTimeUnixMs, pError);
}

void cancelScheduledNotification(
    const wchar_t* tag, const wchar_t* group, DWORD* pError)
{
    DFLog(TAG, L"[cancelScheduledNotification] tag=%ls, group=%ls",
          tag ? tag : L"null", group ? group : L"null");
    WindowsNotificationManager::GetInstance().CancelScheduled(tag, group, pError);
}

void updateNotificationProgress(
    const wchar_t* tag,
    const wchar_t* group,
    double value,
    const wchar_t* valueStr,
    const wchar_t* status,
    uint32_t sequenceNumber,
    DWORD* pError)
{
    DFLog(TAG, L"[updateNotificationProgress] tag=%ls, value=%.2f, seq=%u",
          tag ? tag : L"null", value, sequenceNumber);
    WindowsNotificationManager::GetInstance().UpdateProgress(
        tag, group, value, valueStr, status, sequenceNumber, pError);
}

void setBadge(int value, DWORD* pError)
{
    DFLog(TAG, L"[setBadge] value=%d", value);
    WindowsNotificationManager::GetInstance().SetBadge(value, pError);
}

void removeNotificationById(uint32_t notificationId, DWORD* pError)
{
    DFLog(TAG, L"[removeNotificationById] id=%u", notificationId);
    WindowsNotificationManager::GetInstance().RemoveById(notificationId, pError);
}

void removeNotificationsByTag(
    const wchar_t* tag, const wchar_t* group, DWORD* pError)
{
    DFLog(TAG, L"[removeNotificationsByTag] tag=%ls, group=%ls",
          tag ? tag : L"null", group ? group : L"null");
    WindowsNotificationManager::GetInstance().RemoveByTag(tag, group, pError);
}

void removeAllNotifications(DWORD* pError)
{
    DLog(TAG, L"[removeAllNotifications]");
    WindowsNotificationManager::GetInstance().RemoveAll(pError);
}

void getAllNotifications(wchar_t* outJson, uint32_t bufferSize, DWORD* pError)
{
    DFLog(TAG, L"[getAllNotifications] bufferSize=%u", bufferSize);
    WindowsNotificationManager::GetInstance().GetAll(outJson, bufferSize, pError);
}

int getNotificationSetting()
{
    DLog(TAG, L"[getNotificationSetting]");
    return WindowsNotificationManager::GetInstance().GetSetting();
}

void openNotificationSettings(DWORD* pError)
{
    DLog(TAG, L"[openNotificationSettings]");
    WindowsNotificationManager::GetInstance().OpenSettings(pError);
}
