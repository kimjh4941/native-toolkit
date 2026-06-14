#include "pch.h"

// WinAppSDK Bootstrap + Deployment headers are included only in this translation
// unit (not in the shared pch.h) so the unit test, which compiles
// WindowsNotificationManager.cpp, does not take a hard dependency on
// Microsoft.WindowsAppRuntime.Bootstrap.dll.
#include <MddBootstrap.h>
#include "WindowsNotificationManagerInternal.h"
#include "common.h"

namespace
{
    const wchar_t* TAG = L"WindowsNotificationManager";
}

// =============================================================================
// InitWinAppSdk — load the WinAppSDK runtime for unpackaged (Win32) apps
// =============================================================================

void WindowsNotificationManager::InitWinAppSdk(uint32_t majorMinorVersion, DWORD* pError)
{
    DFLog(TAG, L"[InitWinAppSdk] majorMinorVersion=0x%08x", majorMinorVersion);
    if (pError) *pError = NOTIFICATION_SUCCESS;

    // Step 1: Load the WinAppSDK Framework package via the bootstrapper.
    PACKAGE_VERSION minVersion{};
    const HRESULT hrBootstrap = MddBootstrapInitialize(majorMinorVersion, nullptr, minVersion);
    if (FAILED(hrBootstrap))
    {
        DFLog(TAG, L"[InitWinAppSdk] MddBootstrapInitialize failed. hr=0x%08lx", hrBootstrap);
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
        return;
    }
    DLog(TAG, L"[InitWinAppSdk] Bootstrap initialized");

    // Step 2: Unpackaged apps rely on the system-installed Windows App Runtime.
    // DeploymentManager requires package identity, so the bootstrapper above is the
    // only runtime action performed here.
    DLog(TAG, L"[InitWinAppSdk] DeploymentManager skipped for unpackaged bootstrap");
}

// =============================================================================
// C Bridge API
// =============================================================================

void initWinAppSdk(uint32_t majorMinorVersion, DWORD* pError)
{
    DFLog(TAG, L"[initWinAppSdk] majorMinorVersion=0x%08x", majorMinorVersion);
    WindowsNotificationManager::GetInstance().InitWinAppSdk(majorMinorVersion, pError);
}
