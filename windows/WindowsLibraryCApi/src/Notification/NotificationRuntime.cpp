// The runtime of the C ABI (stage 5 design 7.4, 10).

#include "Notification/NotificationRuntime.h"

#include <mutex>
#include <optional>

#include "NativeToolkit/Notification.h"

namespace NativeToolkitC::Detail::Notification {

namespace {

namespace Api = NativeToolkit::Notification;

/// The C++ token while the default hooks have the runtime loaded.
std::optional<Api::Runtime> g_token;

ntk_notification_error InitializeCpp(uint32_t majorMinor, uint32_t* systemCode)
{
    auto runtime = Api::Runtime::Initialize(Api::RuntimeVersion{majorMinor});
    if (!runtime.has_value()) {
        *systemCode = runtime.error().systemCode;
        return static_cast<ntk_notification_error>(runtime.error().code);
    }
    g_token.emplace(std::move(runtime.value()));
    return NTK_NOTIFICATION_ERROR_NONE;
}

void ShutdownCpp()
{
    g_token.reset();
}

constexpr RuntimeHooks kCppHooks{&InitializeCpp, &ShutdownCpp};

std::mutex   g_mutex;
RuntimeHooks g_hooks = kCppHooks;
bool         g_loaded = false;         ///< Loaded, whether or not its handle is still held.
bool         g_shutdownPending = false;///< The handle is freed; waiting for the managers.
int          g_liveManagers = 0;

/// Called with g_mutex held.
void ShutdownIfUnused() noexcept
{
    if (!g_shutdownPending || g_liveManagers > 0) return;
    g_hooks.shutdown();
    g_loaded = false;
    g_shutdownPending = false;
}

}  // namespace

ntk_notification_error InitializeRuntime(uint32_t majorMinor, uint32_t* systemCode)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    *systemCode = 0;
    if (g_loaded) return NTK_NOTIFICATION_ERROR_NOT_SUPPORTED;
    const auto result = g_hooks.initialize(majorMinor, systemCode);
    if (result == NTK_NOTIFICATION_ERROR_NONE) g_loaded = true;
    return result;
}

void ReleaseRuntime() noexcept
{
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_loaded) return;
    g_shutdownPending = true;
    ShutdownIfUnused();
}

void ManagerOpened() noexcept
{
    std::lock_guard<std::mutex> lock(g_mutex);
    ++g_liveManagers;
}

void ManagerClosed() noexcept
{
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_liveManagers > 0) --g_liveManagers;
    ShutdownIfUnused();
}

void SetRuntimeHooksForTest(const RuntimeHooks* hooks) noexcept
{
    std::lock_guard<std::mutex> lock(g_mutex);
    g_hooks = hooks ? *hooks : kCppHooks;
    g_loaded = false;
    g_shutdownPending = false;
    g_liveManagers = 0;
}

}  // namespace NativeToolkitC::Detail::Notification
