/**
 * @file WindowsNotificationManager.h
 * @brief Public C Bridge API for Windows Notification Manager.
 * @details
 *  Provides Toast notification display, scheduling, badge updates, and
 *  notification management via Windows App SDK (AppNotificationManager).
 *  Minimum OS: Windows 11.
 */
#pragma once

#ifdef WINDOWSLIBRARY_EXPORTS
#define WINDOWSNOTIFICATIONMANAGER_API __declspec(dllexport)
#else
#define WINDOWSNOTIFICATIONMANAGER_API __declspec(dllimport)
#endif

// Error codes
#define NOTIFICATION_SUCCESS                    0
#define NOTIFICATION_ERROR_NOT_INITIALIZED      1
#define NOTIFICATION_ERROR_DISABLED             2
#define NOTIFICATION_ERROR_INVALID_PAYLOAD      3
#define NOTIFICATION_ERROR_PROGRESS_NOT_FOUND   4
#define NOTIFICATION_ERROR_HRESULT_FAILURE      5
#define NOTIFICATION_ERROR_BADGE_FAILED         6
#define NOTIFICATION_ERROR_INVALID_PARAMETER    7
#define NOTIFICATION_ERROR_NOT_SUPPORTED        8  // Feature not supported for this app type (e.g. unpackaged RemoveById/GetAll)

/**
 * @brief Callback invoked when a notification is clicked or activated.
 * @param argsJson JSON string containing action arguments and user input.
 */
typedef void (*NotificationInvokedCallback)(const wchar_t* argsJson);

/**
 * @brief Initializes the Windows App SDK runtime for unpackaged apps.
 * @details Must be called once before initNotificationManager on unpackaged builds.
 *          Calls MddBootstrapInitialize to load the Framework package. Unpackaged
 *          apps rely on a system-installed Windows App Runtime and do not invoke
 *          DeploymentManager::Initialize here.
 * @param majorMinorVersion WinAppSDK major/minor version packed as 0xMMMMmmmm (e.g. 0x00010007 for 1.7).
 * @param pError            Out pointer for error code. 0 on success, 5 (HRESULT_FAILURE) on failure.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void initWinAppSdk(uint32_t majorMinorVersion, DWORD* pError);

/**
 * @brief Initializes the notification manager and registers for notification callbacks.
 * @param callback    Callback function invoked on notification activation.
 * @param isPackaged  TRUE for packaged (MSIX) apps; FALSE for unpackaged Win32 apps.
 * @param displayName Display name shown for the app in notifications (unpackaged: required; ignored if isPackaged).
 * @param iconUri     Icon path for the app (unpackaged: REQUIRED; ignored if isPackaged). Accepts a plain
 *                    Windows path ("C:\\path\\app.png") or a file URI ("file:///C:/path/app.png") — a
 *                    file URI is normalized to a plain path internally. The file must exist and be a
 *                    supported image type (.png/.jpg/.ico). Null/empty -> NOTIFICATION_ERROR_INVALID_PARAMETER.
 * @param pError      Out pointer for error code. 0 on success, 1-8 on failure.
 * @note Call initWinAppSdk before this function for unpackaged apps.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void initNotificationManager(
    NotificationInvokedCallback callback,
    BOOL isPackaged,
    const wchar_t* displayName,
    const wchar_t* iconUri,
    DWORD* pError
);

/**
 * @brief Uninitializes the notification manager and unregisters callbacks.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void uninitNotificationManager();

/**
 * @brief Displays a Toast notification described by a JSON payload.
 * @param jsonPayload JSON string. See design doc for full schema.
 * @param pError      Out pointer for error code. 0 on success, 1-8 on failure.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void showNotification(
    const wchar_t* jsonPayload,
    DWORD* pError
);

/**
 * @brief Schedules a Toast notification for delivery at a specified time.
 * @param jsonPayload         JSON string describing the notification.
 * @param scheduledTimeUnixMs Delivery time in milliseconds since Unix epoch (UTC).
 * @param pError              Out pointer for error code. 0 on success, 1-8 on failure.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void scheduleNotification(
    const wchar_t* jsonPayload,
    int64_t scheduledTimeUnixMs,
    DWORD* pError
);

/**
 * @brief Cancels a previously scheduled notification matching the given tag and group.
 * @param tag    Tag of the notification to cancel.
 * @param group  Group of the notification to cancel.
 * @param pError Out pointer for error code. 0 on success, 5 on WinRT failure.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void cancelScheduledNotification(
    const wchar_t* tag,
    const wchar_t* group,
    DWORD* pError
);

/**
 * @brief Updates the progress data of an existing progress-bar notification.
 * @param tag            Notification tag.
 * @param group          Notification group (pass empty string if not used).
 * @param value          Progress value in [0.0, 1.0].
 * @param valueStr       Display string override for the progress value.
 * @param status         Status label string.
 * @param sequenceNumber Sequence number; must be greater than the previous value.
 * @param pError         Out pointer for error code. 0 on success, 1/4/5 on failure.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void updateNotificationProgress(
    const wchar_t* tag,
    const wchar_t* group,
    double value,
    const wchar_t* valueStr,
    const wchar_t* status,
    uint32_t sequenceNumber,
    DWORD* pError
);

/**
 * @brief Sets the badge on the taskbar icon.
 * @param value  >0: numeric badge; 0: clear; -1=alert; -2=activity; -3=newMessage;
 *               -4=available; -5=busy; -6=away; <-6: invalid (NOTIFICATION_ERROR_INVALID_PARAMETER).
 * @param pError Out pointer for error code. 0 on success, 6/7 on failure,
 *               8 (NOT_SUPPORTED) for unpackaged apps (live-tile registration requires MSIX identity).
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void setBadge(int value, DWORD* pError);

/**
 * @brief Removes a notification from Notification Center by its ID.
 * @param notificationId Numeric ID of the notification.
 * @param pError         Out pointer for error code. 0 on success, 5 on WinRT failure,
 *                       8 (NOT_SUPPORTED) for unpackaged apps (classic API has no numeric ID).
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void removeNotificationById(uint32_t notificationId, DWORD* pError);

/**
 * @brief Removes all notifications matching the given tag and optional group.
 * @param tag    Tag of the notifications to remove.
 * @param group  Group filter; pass empty string to match all groups for the tag.
 * @param pError Out pointer for error code. 0 on success, 5 on WinRT failure.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void removeNotificationsByTag(
    const wchar_t* tag,
    const wchar_t* group,
    DWORD* pError
);

/**
 * @brief Removes all notifications from Notification Center.
 * @param pError Out pointer for error code. 0 on success, 5 on WinRT failure.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void removeAllNotifications(DWORD* pError);

/**
 * @brief Retrieves all current notifications as a JSON array.
 * @param outJson    Output buffer for the JSON array: [{"id":N,"tag":"...","group":"..."},...].
 * @param bufferSize Number of wchar_t elements in outJson (including null terminator).
 * @param pError     Out pointer for error code. 0 on success, 5 on WinRT failure,
 *                   8 (NOT_SUPPORTED) for unpackaged apps (classic API has no numeric ID enumeration).
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void getAllNotifications(
    wchar_t* outJson,
    uint32_t bufferSize,
    DWORD* pError
);

/**
 * @brief Returns the current AppNotificationSetting value.
 * @return 0=Enabled, 1=DisabledForApplication, 2=DisabledForUser,
 *         3=DisabledByGroupPolicy, 4=DisabledByManifest, -1=error.
 * @note This return value is independent of the NOTIFICATION_ERROR_* code space.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
int getNotificationSetting();

/**
 * @brief Opens the Windows notifications settings page.
 * @details Useful when getNotificationSetting() reports notifications are
 *          disabled (1-4): the user can re-enable them for this app from the
 *          settings page. Launches the ms-settings:notifications URI.
 * @param pError Out pointer for error code. 0 on success, 5 on WinRT failure.
 */
extern "C" WINDOWSNOTIFICATIONMANAGER_API
void openNotificationSettings(DWORD* pError);
