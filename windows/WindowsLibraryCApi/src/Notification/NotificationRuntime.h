#pragma once
// The runtime of the C ABI (stage 5 design 7.4, 10): one per process, and its
// shutdown waits for the last manager to close.
//
// The C++ API leaves that ordering to the caller (N-7: hold the Runtime for as
// long as any Manager is used). A C caller frees handles in whatever order its
// language's finalisers run, so the C ABI keeps the count itself.

#include <cstdint>

#include "NativeToolkitC/Notification.h"

struct ntk_notification_runtime {
    // Nothing of its own: there is one runtime per process, and its state is
    // in NotificationRuntime.cpp. The handle is what the caller frees.
};

namespace NativeToolkitC::Detail::Notification {

/// Loads the runtime unless one is loaded or waiting to shut down.
/// NTK_NOTIFICATION_ERROR_NONE, NOT_SUPPORTED, or the bootstrap's failure
/// with its system code in *systemCode.
ntk_notification_error InitializeRuntime(uint32_t majorMinor, uint32_t* systemCode);

/// The caller freed its runtime handle: shut down now, or once the last
/// manager closes.
void ReleaseRuntime() noexcept;

/// A manager was created. Every call is paired with one ManagerClosed.
void ManagerOpened() noexcept;

/// A manager was closed; the runtime shuts down if it was waiting for this.
void ManagerClosed() noexcept;

/// What loading and unloading the runtime does. The C++ Runtime by default;
/// a test puts counters in their place (CT-19).
struct RuntimeHooks {
    ntk_notification_error (*initialize)(uint32_t majorMinor, uint32_t* systemCode);
    void (*shutdown)();
};

/// Test seam: replaces the hooks; nullptr restores the C++ Runtime. Also
/// forgets any runtime and managers counted so far.
void SetRuntimeHooksForTest(const RuntimeHooks* hooks) noexcept;

}  // namespace NativeToolkitC::Detail::Notification
