#pragma once
// The release callback, called exactly once (stage 5 design 7.5.1, 7.5.3).

#include <atomic>

#include "NativeToolkitC/Common.h"

namespace NativeToolkitC::Detail {

/**
 * @brief Owns a caller's user_data and its release callback.
 * @details Shared through std::shared_ptr by every copy of the callback that
 *          holds the user_data. release runs exactly once: at the first
 *          Fire(), or when the last owner lets go, whichever comes first.
 *          After Fire() the guard still answers UserData(), but nothing may
 *          hand that pointer to the caller any more; IsFired() says so.
 */
class ReleaseGuard {
public:
    ReleaseGuard(ntk_release_fn release, void* userData) noexcept
        : release_(release), userData_(userData) {}
    ~ReleaseGuard() { Fire(); }

    ReleaseGuard(const ReleaseGuard&) = delete;
    ReleaseGuard& operator=(const ReleaseGuard&) = delete;

    /// Calls release now if it has not run yet. Later calls do nothing.
    void Fire() noexcept;

    bool IsFired() const noexcept { return fired_.load(); }
    void* UserData() const noexcept { return userData_; }

private:
    ntk_release_fn    release_;
    void*             userData_;
    std::atomic<bool> fired_{false};
};

}  // namespace NativeToolkitC::Detail
