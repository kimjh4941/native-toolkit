/**
 * @file NotificationBridge.cpp
 * @brief Exported C functions of the Notification feature.
 * @details
 *  Thin wrappers over WindowsNotificationManager. This translation unit belongs
 *  to the DLL only; the implementation it calls is built into the library.
 */
#include "pch.h"
#include "Notification/WindowsNotificationManager.h"
#include "Notification/WindowsNotificationManagerInternal.h"
#include "Common/CommonInternal.h"

namespace {
const wchar_t* TAG = L"WindowsNotificationManager";
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
