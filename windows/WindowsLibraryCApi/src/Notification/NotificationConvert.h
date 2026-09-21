#pragma once
// The notification handles of the C ABI and the conversions to and from the
// C++ API (stage 5 design 8.4.2, 7.5.1, E-12). Separate from the exports so
// they can be tested without registering with the OS.

#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "Common/ReleaseGuard.h"
#include "NativeToolkit/Notification.h"
#include "NativeToolkitC/Notification.h"

struct ntk_notification_manager {
    explicit ntk_notification_manager(NativeToolkit::Notification::Manager created,
                                      std::shared_ptr<NativeToolkitC::Detail::ReleaseGuard> handlerGuard) noexcept
        : manager(std::move(created)), guard(std::move(handlerGuard)) {}

    NativeToolkit::Notification::Manager manager;
    /// Serialises the handler replacements; the operations do not take it.
    std::mutex mutex;
    /// The current handler's user_data and release. The C++ handler holds a
    /// share too, and so does every delivery in flight; this one is let go
    /// only after the C++ call that drops the handler has returned, so the
    /// last share never goes inside a C++ lock (E-12).
    std::shared_ptr<NativeToolkitC::Detail::ReleaseGuard> guard;
    bool open = true;
};

struct ntk_notification_list {
    struct Entry {
        uint32_t    id = 0;
        std::string tag;
        std::string group;
    };
    std::vector<Entry> entries;
};

struct ntk_notification_activation {
    std::string raw;
    std::vector<std::pair<std::string, std::string>> values;
};

namespace NativeToolkitC::Detail::Notification {

namespace Api = NativeToolkit::Notification;

/**
 * @brief A guard for release and user_data.
 * @details If the guard cannot be allocated, release is called here and
 *          std::bad_alloc is rethrown: release runs exactly once whatever
 *          happens (7.5.1).
 */
std::shared_ptr<ReleaseGuard> NewGuard(ntk_release_fn release, void* userData);

/// The C++ handler that calls fn with the guard's user_data, or an empty one
/// for a NULL fn. Every copy holds a share of the guard. Nothing it does
/// throws back into the delivery.
std::function<void(const Api::ActivationArgs&)> MakeHandler(ntk_notification_invoked_fn fn,
                                                             std::shared_ptr<ReleaseGuard> guard);

/// The activation handed to a handler. Throws std::bad_alloc.
ntk_notification_activation ToActivation(const Api::ActivationArgs& args);

/// A new list handle. Throws std::bad_alloc.
ntk_notification_list* NewList(const std::vector<Api::NotificationRef>& refs);

/// Reads the manager options: NONE, INVALID_PARAMETER or NOT_SUPPORTED. The
/// release and user_data are in *raw whenever they could be read, which is
/// every result but a NULL, too small or too large struct.
ntk_notification_error ReadManagerOptions(const ntk_notification_manager_options* in,
                                          ntk_notification_manager_options& raw);

/// The C++ options for raw, apart from the handler. NONE or INVALID_PARAMETER.
ntk_notification_error ToManagerOptions(const ntk_notification_manager_options& raw,
                                        Api::ManagerOptions& out);

/// NONE, INVALID_PARAMETER or NOT_SUPPORTED.
ntk_notification_error ToProgressUpdate(const ntk_notification_progress_update* in,
                                        Api::ProgressUpdate& out);

}  // namespace NativeToolkitC::Detail::Notification
