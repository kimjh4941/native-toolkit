// The version of the C ABI (stage 5 design 7.8).

#include "NativeToolkitC/Common.h"

static_assert(NTK_VERSION == ((NTK_VERSION_MAJOR << 16) | (NTK_VERSION_MINOR << 8) | NTK_VERSION_PATCH),
              "NTK_VERSION must spell out MAJOR, MINOR and PATCH");

extern "C" uint32_t NTK_CALL ntk_version(void)
{
    return NTK_VERSION;
}
