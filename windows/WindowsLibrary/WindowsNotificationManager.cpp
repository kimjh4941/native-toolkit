#include "pch.h"
#include "WindowsNotificationManagerInternal.h"
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
    // background (non-STA) thread where blocking is allowed. The lambda captures
    // by reference are valid because the outer get() blocks until it completes.
    template <typename TFunc>
    auto RunSyncOffSta(TFunc&& func) -> decltype(func())
    {
        return std::async(std::launch::async, std::forward<TFunc>(func)).get();
    }

    // AppNotificationManager::Register uses iconUri.RawUri() directly as a filesystem path
    // (Windows.Foundation.Uri preserves the raw input string). A "file:///C:/x.png" URI is
    // therefore rejected by std::filesystem with ERROR_INVALID_NAME (0x8007007B). Normalize a
    // file:// URI to a plain Windows path (percent-decode + '/'→'\'); pass a plain path through.
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
    m_callback = callback;

    // AppNotificationManager registration is process-wide and Register() must be
    // called only once. Re-entering the sample page and tapping InitializeManager
    // again would otherwise subscribe a second handler and call Register() twice,
    // which throws 0x80070490. Treat a repeat Init as a no-op (callback refreshed
    // above). Uninit() resets m_initialized so a later Init() can re-register.
    if (m_initialized)
    {
        DLog(TAG, L"[Init] already initialized; skipping re-registration");
        return;
    }

    // Ensure COM/WinRT is initialized on the CALLING thread (not at DLL load). Tolerate
    // RPC_E_CHANGED_MODE: if the host already established an apartment on this thread, keep it
    // — the AppNotificationManager APIs work in either STA or MTA.
    const HRESULT hrCom = ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hrCom) && hrCom != RPC_E_CHANGED_MODE)
    {
        DFLog(TAG, L"[Init] CoInitializeEx failed. hr=0x%08lx", hrCom);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
        return;
    }

    try
    {
        auto& mgr = AppNotificationManager::Default();

        m_invokedToken = mgr.NotificationInvoked(
            [this](AppNotificationManager const& sender,
                   AppNotificationActivatedEventArgs const& args)
            {
                OnNotificationInvoked(sender, args);
            });

        if (isPackaged)
        {
            mgr.Register();
        }
        else
        {
            if (!displayName || !*displayName || !iconUri || !*iconUri)
            {
                DLog(TAG, L"[Init] displayName and iconUri are required for unpackaged app");
                if (pError) *pError = NOTIFICATION_ERROR_INVALID_PARAMETER;
                return;
            }
            // Unpackaged registration: the Windows App SDK creates the COM activator and a
            // Start Menu shortcut from the display name and icon. The 2-arg AppNotificationManager
            // overload is Register(displayName, iconUri) — there is no caller-supplied CLSID.
            // Both are REQUIRED: Register() rejects a null/empty iconUri with E_INVALIDARG.
            // Register uses iconUri.RawUri() as a filesystem path, so a file:// URI must be
            // normalized to a plain Windows path (a "file:///..." RawUri is rejected by
            // std::filesystem with ERROR_INVALID_NAME). Accepts a plain path or a file:// URI.
            std::wstring iconPath = NormalizeIconPath(iconUri);
            mgr.Register(hstring{ displayName }, Uri{ iconPath });
        }

        auto setting = mgr.Setting();
        DFLog(TAG, L"[Init] NotificationSetting=%d", static_cast<int>(setting));

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
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

void WindowsNotificationManager::Uninit()
{
    DLog(TAG, L"[Uninit]");

    if (!m_initialized) return;

    try
    {
        auto& mgr = AppNotificationManager::Default();
        mgr.NotificationInvoked(m_invokedToken);
        mgr.Unregister();
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[Uninit] WinRT exception. hr=0x%08lx", ex.code().value);
    }

    m_callback    = nullptr;
    m_initialized = false;
    m_invokedToken = {};
}

// =============================================================================
// OnNotificationInvoked / ArgsToJson
// =============================================================================

void WindowsNotificationManager::OnNotificationInvoked(
    AppNotificationManager const&,
    AppNotificationActivatedEventArgs const& args)
{
    DLog(TAG, L"[OnNotificationInvoked]");

    if (!m_callback) return;

    try
    {
        auto arguments = args.Arguments();
        auto userInput  = args.UserInput();
        std::wstring json = ArgsToJson(arguments, userInput);
        m_callback(json.c_str());
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

    // Use WinRT JSON API — JsonValue::CreateStringValue auto-escapes special chars
    JsonObject root;

    for (auto const& kv : args)
        root.Insert(kv.Key(), JsonValue::CreateStringValue(kv.Value()));

    for (auto const& kv : userInput)
        root.Insert(kv.Key(), JsonValue::CreateStringValue(kv.Value()));

    return std::wstring{ root.Stringify() };
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
        auto setting = AppNotificationManager::Default().Setting();
        if (setting != AppNotificationSetting::Enabled)
        {
            DFLog(TAG, L"[Show] notification disabled. setting=%d", static_cast<int>(setting));
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

        DWORD buildError = NOTIFICATION_SUCCESS;
        auto builder = BuildFromJson(json, &buildError);
        if (buildError != NOTIFICATION_SUCCESS)
        {
            if (pError) *pError = buildError;
            return;
        }

        auto notification = builder.BuildNotification();

        // Expiration / ExpiresOnReboot are set on the AppNotification, not the builder.
        if (json.HasKey(L"expiration"))
        {
            auto sec = static_cast<int64_t>(json.GetNamedNumber(L"expiration"));
            notification.Expiration(winrt::clock::now() + std::chrono::seconds(sec));
        }

        if (json.HasKey(L"expiresOnReboot") && json.GetNamedBoolean(L"expiresOnReboot"))
            notification.ExpiresOnReboot(true);

        // Supply the initial values for the data-bound progress bar (see
        // ApplyProgress). Sequence number 1 is the baseline; later UpdateAsync
        // calls must use a higher sequence number to take effect.
        if (json.HasKey(L"progress"))
        {
            auto progressObj = json.GetNamedObject(L"progress");
            AppNotificationProgressData data{ 1 };
            data.Value(progressObj.HasKey(L"value") ? progressObj.GetNamedNumber(L"value") : 0.0);
            if (progressObj.HasKey(L"valueStr"))
                data.ValueStringOverride(progressObj.GetNamedString(L"valueStr"));
            if (progressObj.HasKey(L"status"))
                data.Status(progressObj.GetNamedString(L"status"));
            notification.Progress(data);
        }

        AppNotificationManager::Default().Show(notification);
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[Show] WinRT exception. hr=0x%08lx", ex.code().value);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}

// =============================================================================
// BuildFromJson + sub-builders
// =============================================================================

bool WindowsNotificationManager::ValidatePayload(const JsonObject& json, DWORD* pError)
{
    DLog(TAG, L"[ValidatePayload]");

    // audio.loop requires duration=long
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

    // Validate all constraints up-front from JSON only (no WinRT activation) so that
    // invalid payloads fail fast — and remain unit-testable without the AppSDK runtime.
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

    // Constraints already verified by ValidatePayload above.
    if (json.HasKey(L"buttons"))
    {
        ApplyButtons(builder, json.GetNamedArray(L"buttons"), pError);
        if (pError && *pError != NOTIFICATION_SUCCESS) return builder;
    }

    // TextBoxes — AppNotificationBuilder exposes AddTextBox overloads (no separate class)
    if (json.HasKey(L"textBoxes"))
    {
        for (auto const& item : json.GetNamedArray(L"textBoxes"))
        {
            auto box = item.GetObject();
            auto id = box.GetNamedString(L"id");
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

    // ComboBoxes
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
            DFLog(TAG, L"[BuildFromJson] validation failed. reason=button has both args and invokeUri");
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
            DFLog(TAG, L"[BuildFromJson] validation failed. reason=audio.type=uri requires uri field");
            if (pError) *pError = NOTIFICATION_ERROR_INVALID_PARAMETER;
            return;
        }
        builder.SetAudioUri(Uri{ audioObj.GetNamedString(L"uri") }, looping);
        return;
    }

    // event / default
    AppNotificationSoundEvent soundEvent = AppNotificationSoundEvent::Default;
    if (audioObj.HasKey(L"event"))
    {
        auto ev = audioObj.GetNamedString(L"event");
        // The modern AppSDK sound-event enum has no dedicated looping entries;
        // looping is controlled separately via AppNotificationAudioLooping.
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

    // Title is static. The dynamic fields are data-bound so that UpdateAsync
    // can change them on the already-displayed toast; a progress bar built with
    // literal values cannot be updated. The initial values for the bound fields
    // are supplied via AppNotification.Progress() at Show time (see Show()).
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
        auto setting = AppNotificationManager::Default().Setting();
        if (setting != AppNotificationSetting::Enabled)
        {
            DFLog(TAG, L"[Schedule] notification disabled. setting=%d", static_cast<int>(setting));
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

        DWORD buildError = NOTIFICATION_SUCCESS;
        auto builder = BuildFromJson(json, &buildError);
        if (buildError != NOTIFICATION_SUCCESS)
        {
            if (pError) *pError = buildError;
            return;
        }

        auto tp = std::chrono::system_clock::time_point{
            std::chrono::milliseconds(scheduledTimeMs)
        };
        auto scheduledTime = winrt::clock::from_sys(tp);

        // OS delivery window is 5 minutes — warn if exceeded
        if ((scheduledTime - winrt::clock::now()) > std::chrono::minutes(5))
            DLog(TAG, L"[Schedule] WARNING: scheduled time exceeds 5-minute delivery window. OS may drop the notification.");

        auto notification = builder.BuildNotification();
        // AppNotification.Payload() returns an hstring containing the toast XML;
        // load it into an XmlDocument for the legacy ScheduledToastNotification API.
        XmlDocument doc;
        doc.LoadXml(notification.Payload());

        ScheduledToastNotification scheduled{ doc, scheduledTime };
        ToastNotificationManager::CreateToastNotifier().AddToSchedule(scheduled);
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

    try
    {
        auto notifier = ToastNotificationManager::CreateToastNotifier();
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
            DFLog(TAG, L"[UpdateProgress] notification not found. tag=%ls", tag ? tag : L"null");
            if (pError) *pError = NOTIFICATION_ERROR_PROGRESS_NOT_FOUND;
        }
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

    try
    {
        auto updater = BadgeUpdateManager::CreateBadgeUpdaterForApplication();

        if (value == 0)
        {
            updater.Clear();
            return;
        }

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
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[SetBadge] badge update failed. value=%d, hr=0x%08lx", value, ex.code().value);
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

    try
    {
        RunSyncOffSta([&] { AppNotificationManager::Default().RemoveByIdAsync(id).get(); });
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

    try
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

    try
    {
        RunSyncOffSta([&] { AppNotificationManager::Default().RemoveAllAsync().get(); });
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

    try
    {
        auto notifications = RunSyncOffSta([&] { return AppNotificationManager::Default().GetAllAsync().get(); });

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

    try
    {
        return static_cast<int>(AppNotificationManager::Default().Setting());
    }
    catch (winrt::hresult_error const& ex)
    {
        DFLog(TAG, L"[GetSetting] WinRT exception. hr=0x%08lx", ex.code().value);
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

    try
    {
        // ms-settings:notifications opens the system notifications settings page,
        // where the user can re-enable notifications for this app. LaunchUriAsync
        // is waited on a background thread to stay STA-safe (see RunSyncOffSta).
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
// NOTE: InitWinAppSdk / initWinAppSdk (WinAppSDK bootstrap + deployment for
// unpackaged apps) live in WindowsAppSdkBootstrap.cpp so the unit test, which
// compiles this file, does not depend on Microsoft.WindowsAppRuntime.Bootstrap.dll.

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
