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

}  // namespace NativeToolkitC::Detail
