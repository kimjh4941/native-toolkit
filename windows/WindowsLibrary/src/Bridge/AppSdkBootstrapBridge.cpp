/**
 * @file AppSdkBootstrapBridge.cpp
 * @brief Exported C function that initialises the Windows App SDK runtime.
 * @details
 *  Kept apart from the notification bridge so the unit tests, which compile
 *  the manager, do not depend on the bootstrap DLL.
 *
 *  Sits on Runtime, the C++ API's token for the same call (T-14), with one
 *  difference that is the whole reason Runtime exists: destroying a token
 *  releases the runtime again, and initWinAppSdk never has. So the bridge
 *  never destroys one. Each call leaks its token deliberately, which leaves
 *  the runtime loaded for the life of the process exactly as today (N-7), and
 *  a second call bootstraps again just as a second initWinAppSdk does.
 */
#include "pch.h"

#include <new>

#include "Common/CommonInternal.h"
#include "NativeToolkit/Notification.h"
#include "Notification/WindowsNotificationManager.h"

namespace {
const wchar_t* TAG = L"WindowsNotificationManager";
}

// =============================================================================
// C Bridge API
// =============================================================================

void initWinAppSdk(uint32_t majorMinorVersion, DWORD* pError)
{
    DFLog(TAG, L"[initWinAppSdk] majorMinorVersion=0x%08x", majorMinorVersion);
    if (pError) *pError = NOTIFICATION_SUCCESS;

    namespace Api = NativeToolkit::Notification;

    auto started = Api::Runtime::Initialize(Api::RuntimeVersion{majorMinorVersion});
    if (!started.has_value()) {
        if (pError) *pError = static_cast<DWORD>(started.error().code);
        return;
    }

    // Never destroyed: see the note at the top of the file. If it cannot be
    // held, nothing owns the token and it is about to release the runtime, so
    // say so rather than report a success that is about to undo itself.
    if (!new (std::nothrow) Api::Runtime(std::move(started).value())) {
        DLog(TAG, L"[initWinAppSdk] the runtime token could not be held");
        if (pError) *pError = NOTIFICATION_ERROR_HRESULT_FAILURE;
    }
}
