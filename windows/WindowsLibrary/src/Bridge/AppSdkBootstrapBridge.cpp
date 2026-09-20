/**
 * @file AppSdkBootstrapBridge.cpp
 * @brief Exported C function that initialises the Windows App SDK runtime.
 * @details
 *  Kept apart from the notification bridge so the unit tests, which compile the
 *  manager, do not depend on the bootstrap DLL.
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

void initWinAppSdk(uint32_t majorMinorVersion, DWORD* pError)
{
    DFLog(TAG, L"[initWinAppSdk] majorMinorVersion=0x%08x", majorMinorVersion);
    WindowsNotificationManager::GetInstance().InitWinAppSdk(majorMinorVersion, pError);
}
