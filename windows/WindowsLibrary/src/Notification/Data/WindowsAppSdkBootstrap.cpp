#include "pch.h"

// WinAppSDK Bootstrap + Deployment headers are included only in this translation
// unit (not in the shared pch.h) so the unit test, which compiles
// WindowsNotificationManager.cpp, does not take a hard dependency on
// Microsoft.WindowsAppRuntime.Bootstrap.dll.
#include <MddBootstrap.h>
#include "Notification/WindowsNotificationManagerInternal.h"
#include "Common/CommonInternal.h"
#include "NativeToolkit/Notification.h"

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
// Runtime — the C++ API of OP-07
//
// Kept in this translation unit because this is the one place that is allowed
// to know about MddBootstrap: the unit tests compile the manager but not this
// file, and that is what keeps them independent of the bootstrap DLL.
//
// The difference from initWinAppSdk is the shutdown. The C ABI has no
// counterpart to initWinAppSdk and leaves the runtime loaded for the life of
// the process; that stays true for C callers, while a C++ caller gets a token
// whose destruction releases it (N-7).
// =============================================================================

namespace NativeToolkit::Notification {

namespace
{
    const wchar_t* API_TAG = L"NativeToolkit::Notification";
}

Result<Runtime> Runtime::Initialize(RuntimeVersion version)
{
    DFLog(API_TAG, L"[Runtime::Initialize] majorMinor=0x%08x", version.majorMinor);

    PACKAGE_VERSION minVersion{};
    const HRESULT hr = MddBootstrapInitialize(version.majorMinor, nullptr, minVersion);
    if (FAILED(hr))
    {
        DFLog(API_TAG, L"[Runtime::Initialize] MddBootstrapInitialize failed. hr=0x%08lx", hr);
        return Unexpected{Error{ErrorCode::HResultFailure, static_cast<uint32_t>(hr)}};
    }

    Runtime runtime;
    runtime.held_ = true;
    return runtime;
}

Runtime::Runtime(Runtime&& other) noexcept : held_(other.held_)
{
    other.held_ = false;
}

Runtime& Runtime::operator=(Runtime&& other) noexcept
{
    if (this != &other)
    {
        Close();
        held_ = other.held_;
        other.held_ = false;
    }
    return *this;
}

Runtime::~Runtime()
{
    Close();
}

void Runtime::Close() noexcept
{
    if (!held_) return;
    DLog(API_TAG, L"[Runtime::Close]");
    MddBootstrapShutdown();
    held_ = false;
}

}  // namespace NativeToolkit::Notification
