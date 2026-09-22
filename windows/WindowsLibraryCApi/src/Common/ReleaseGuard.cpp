// The release callback, called exactly once (stage 5 design 7.5).

#include "Common/ReleaseGuard.h"

#include "Common/Guard.h"

namespace NativeToolkitC::Detail {

void ReleaseGuard::Fire() noexcept
{
    if (fired_.exchange(true)) return;
    if (release_) {
        CallCaller([&] { release_(userData_); });
    }
}

std::shared_ptr<ReleaseGuard> NewReleaseGuard(ntk_release_fn release, void* userData)
{
    try {
        return std::make_shared<ReleaseGuard>(release, userData);
    } catch (...) {
        if (release) CallCaller([&] { release(userData); });
        throw;
    }
}

}  // namespace NativeToolkitC::Detail
