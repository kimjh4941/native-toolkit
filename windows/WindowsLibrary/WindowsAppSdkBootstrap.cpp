#include "pch.h"

// WinAppSDK Bootstrap + Deployment headers are included only in this translation
// unit (not in the shared pch.h) so the unit test, which compiles
// WindowsNotificationManager.cpp, does not take a hard dependency on
// Microsoft.WindowsAppRuntime.Bootstrap.dll.
#include <MddBootstrap.h>
#include <winrt/Microsoft.Windows.ApplicationModel.WindowsAppRuntime.h>

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

    // Step 2: Best-effort provisioning of the Main/Singleton packages (which register the
    // notification COM activator). DeploymentManager requires package identity, so it only
    // works for PACKAGED apps. For unpackaged apps it throws APPMODEL_ERROR_NO_PACKAGE
    // (0x80073D54); there the Main/Singleton packages must be provided by the
    // system-installed WindowsAppRuntime (e.g. WindowsAppRuntimeInstall.exe). Treat
    // no-package-identity as non-fatal: the bootstrap above is the essential step.
    static constexpr int32_t APPMODEL_ERROR_NO_PACKAGE_HR = static_cast<int32_t>(0x80073D54);
    try
    {
        using namespace winrt::Microsoft::Windows::ApplicationModel::WindowsAppRuntime;
        auto result = DeploymentManager::Initialize();
        if (result.Status() != DeploymentStatus::Ok)
        {
            DFLog(TAG, L"[InitWinAppSdk] DeploymentManager::Initialize failed. status=%d",
                  static_cast<int>(result.Status()));
            if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
            return;
        }
        DLog(TAG, L"[InitWinAppSdk] DeploymentManager initialized");
    }
    catch (winrt::hresult_error const& ex)
    {
        if (ex.code() == APPMODEL_ERROR_NO_PACKAGE_HR)
        {
            // Unpackaged app: DeploymentManager is not applicable. Rely on the
            // system-installed WindowsAppRuntime for the Main/Singleton packages.
            DLog(TAG, L"[InitWinAppSdk] unpackaged: skipping DeploymentManager; using installed WindowsAppRuntime");
        }
        else
        {
            DFLog(TAG, L"[InitWinAppSdk] DeploymentManager exception. hr=0x%08lx", ex.code().value);
            if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
        }
    }
}

// =============================================================================
// C Bridge API
// =============================================================================

void initWinAppSdk(uint32_t majorMinorVersion, DWORD* pError)
{
    DFLog(TAG, L"[initWinAppSdk] majorMinorVersion=0x%08x", majorMinorVersion);
    WindowsNotificationManager::GetInstance().InitWinAppSdk(majorMinorVersion, pError);
}
