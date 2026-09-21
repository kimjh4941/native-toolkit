/**
 * @file NotificationBridge.cpp
 * @brief Exported C functions of the Notification feature.
 * @details
 *  These sit on the C++ API of NativeToolkit::Notification, not on the manager
 *  underneath it, so that there is one implementation and the C ABI is one of
 *  its callers rather than a second path through the same code (T-14).
 *
 *  Everything a C caller can observe stays as it was. Three of the promises
 *  take work to keep:
 *
 *  initNotificationManager is idempotent and a second call swaps the callback
 *  (NTF-60), while a second Manager::Create is refused. The bridge therefore
 *  holds the one Manager this process may have and calls SetInvokedHandler on
 *  a repeat, which is what N-10 put that method there for.
 *
 *  The callback takes the activation JSON, and the C++ API takes a parsed
 *  ActivationArgs. The JSON it was parsed from is kept verbatim in
 *  rawArguments, so what reaches a C caller is the string the OS produced and
 *  not something this bridge rebuilt from the pairs.
 *
 *  initWinAppSdk has no counterpart and leaves the runtime loaded for the life
 *  of the process (N-7). A Runtime token would release it when destroyed, so
 *  the bridge never destroys one: each call leaks its token on purpose, which
 *  is exactly what the C ABI does today.
 *
 *  Two functions are deliberately still on the manager, and say so where they
 *  are defined: showNotification and scheduleNotification take JSON, which the
 *  next step of T-14 moves into this file, and getAllNotifications answers in
 *  JSON that the backend itself writes.
 *
 *  This translation unit belongs to the DLL only.
 */
#include "pch.h"

#include <optional>

#include "Common/CommonInternal.h"
#include "NativeToolkit/Notification.h"
#include "Notification/WindowsNotificationManager.h"
#include "Notification/WindowsNotificationManagerInternal.h"

namespace {

const wchar_t* TAG = L"WindowsNotificationManager";

namespace Api = NativeToolkit::Notification;

/// The one manager a process may have, held for as long as the C ABI wants it.
std::optional<Api::Manager> g_manager;

/// The raw value the C ABI reports for a typed failure. The enumerators were
/// given the values of the NOTIFICATION_* constants for exactly this.
DWORD ToCError(const Api::Error& error) noexcept
{
    return static_cast<DWORD>(error.code);
}

/**
 * @brief True when there is nothing to call, with the answer already written.
 * @details
 *  The manager answers an uninitialised call with NOT_INITIALIZED and a line
 *  in the log. The bridge can answer it without asking, so it says the same
 *  thing in the same words; what a C caller reads from pError is unchanged.
 */
bool NotInitialized(const wchar_t* caller, DWORD* pError)
{
    if (g_manager.has_value()) {
        return false;
    }
    DFLog(TAG, L"[%ls] not initialized", caller);
    if (pError) *pError = NOTIFICATION_ERROR_NOT_INITIALIZED;
    return true;
}

/// Writes the outcome where a C caller looks for it.
void Report(const Api::Result<void>& result, DWORD* pError)
{
    if (pError) *pError = result.has_value() ? NOTIFICATION_SUCCESS : ToCError(result.error());
}

/// Hands the activation on to a C callback, as the string it arrived as.
std::function<void(const Api::ActivationArgs&)> Forwarder(NotificationInvokedCallback callback)
{
    if (!callback) {
        return {};
    }
    return [callback](const Api::ActivationArgs& args) {
        callback(args.rawArguments.c_str());
    };
}

}  // namespace

// =============================================================================
// C Bridge API
// =============================================================================
//
// NOTE: initWinAppSdk lives in WindowsAppSdkBootstrap.cpp so the unit test,
// which compiles this file, does not depend on Bootstrap.dll.

void initNotificationManager(
    NotificationInvokedCallback callback,
    BOOL isPackaged,
    const wchar_t* displayName,
    const wchar_t* iconUri,
    DWORD* pError)
{
    DFLog(TAG, L"[initNotificationManager] isPackaged=%d", isPackaged);

    if (g_manager.has_value()) {
        // Already initialised: succeed, and take the new callback. The app
        // type, the display name and the icon are ignored, as they are today
        // (NTF-60).
        DLog(TAG, L"[initNotificationManager] already initialised; swapping the callback");
        g_manager->SetInvokedHandler(Forwarder(callback));
        if (pError) *pError = NOTIFICATION_SUCCESS;
        return;
    }

    Api::ManagerOptions options;
    options.onInvoked   = Forwarder(callback);
    options.isPackaged  = isPackaged != FALSE;
    options.displayName = displayName ? displayName : L"";
    options.iconUri     = iconUri ? iconUri : L"";

    auto created = Api::Manager::Create(options);
    if (!created.has_value()) {
        if (pError) *pError = ToCError(created.error());
        return;
    }
    g_manager.emplace(std::move(created).value());
    if (pError) *pError = NOTIFICATION_SUCCESS;
}

void uninitNotificationManager()
{
    DLog(TAG, L"[uninitNotificationManager]");
    if (!g_manager.has_value()) {
        return;
    }
    g_manager->Close();
    g_manager.reset();
}

void showNotification(const wchar_t* jsonPayload, DWORD* pError)
{
    // Still on the manager: the payload is JSON, and moving the parse into
    // this file is the second step of T-14.
    DFLog(TAG, L"[showNotification] jsonPayload=%ls", jsonPayload ? jsonPayload : L"null");
    WindowsNotificationManager::GetInstance().Show(jsonPayload, pError);
}

void scheduleNotification(
    const wchar_t* jsonPayload, int64_t scheduledTimeUnixMs, DWORD* pError)
{
    // Still on the manager, for the same reason as showNotification.
    DFLog(TAG, L"[scheduleNotification] scheduledTimeUnixMs=%lld", scheduledTimeUnixMs);
    WindowsNotificationManager::GetInstance().Schedule(
        jsonPayload, scheduledTimeUnixMs, pError);
}

void cancelScheduledNotification(
    const wchar_t* tag, const wchar_t* group, DWORD* pError)
{
    DFLog(TAG, L"[cancelScheduledNotification] tag=%ls, group=%ls",
          tag ? tag : L"null", group ? group : L"null");

    if (NotInitialized(L"CancelScheduled", pError)) return;
    Report(g_manager->CancelScheduled(tag ? tag : L"", group ? group : L""), pError);
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

    if (NotInitialized(L"UpdateProgress", pError)) return;
    Api::ProgressUpdate update;
    update.tag            = tag ? tag : L"";
    update.group          = group ? group : L"";
    update.value          = value;
    update.valueString    = valueStr ? valueStr : L"";
    update.status         = status ? status : L"";
    update.sequenceNumber = sequenceNumber;
    Report(g_manager->UpdateProgress(update), pError);
}

void setBadge(int value, DWORD* pError)
{
    DFLog(TAG, L"[setBadge] value=%d", value);

    if (!g_manager.has_value()) {
        // The range check comes before the initialisation check today, so a
        // value below the glyph range is InvalidParameter either way (NTF-65).
        WindowsNotificationManager::GetInstance().SetBadge(value, pError);
        return;
    }
    Report(g_manager->SetBadge(value), pError);
}

void removeNotificationById(uint32_t notificationId, DWORD* pError)
{
    DFLog(TAG, L"[removeNotificationById] id=%u", notificationId);

    if (NotInitialized(L"RemoveById", pError)) return;
    Report(g_manager->RemoveById(notificationId), pError);
}

void removeNotificationsByTag(
    const wchar_t* tag, const wchar_t* group, DWORD* pError)
{
    DFLog(TAG, L"[removeNotificationsByTag] tag=%ls, group=%ls",
          tag ? tag : L"null", group ? group : L"null");

    if (NotInitialized(L"RemoveByTag", pError)) return;
    Report(g_manager->RemoveByTag(tag ? tag : L"", group ? group : L""), pError);
}

void removeAllNotifications(DWORD* pError)
{
    DLog(TAG, L"[removeAllNotifications]");

    if (NotInitialized(L"RemoveAll", pError)) return;
    Report(g_manager->RemoveAll(), pError);
}

void getAllNotifications(wchar_t* outJson, uint32_t bufferSize, DWORD* pError)
{
    // Still on the manager on purpose. The backend writes this JSON itself, so
    // going through the C++ API would parse it and write it out again - a
    // round trip with nothing to gain and a serialiser to trust.
    DFLog(TAG, L"[getAllNotifications] bufferSize=%u", bufferSize);
    WindowsNotificationManager::GetInstance().GetAll(outJson, bufferSize, pError);
}

int getNotificationSetting()
{
    DLog(TAG, L"[getNotificationSetting]");

    if (!g_manager.has_value()) {
        // -1 is what "could not ask" has always been here.
        return -1;
    }
    const auto setting = g_manager->GetSetting();
    return setting.has_value() ? static_cast<int>(setting.value()) : -1;
}

void openNotificationSettings(DWORD* pError)
{
    DLog(TAG, L"[openNotificationSettings]");

    if (NotInitialized(L"OpenSettings", pError)) return;
    Report(g_manager->OpenSettings(), pError);
}
