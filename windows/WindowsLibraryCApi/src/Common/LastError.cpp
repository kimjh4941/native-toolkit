// ntk_last_system_code (stage 5 design 7.3, E-4).

#include "Common/LastError.h"

#include "NativeToolkitC/Common.h"

namespace {

thread_local uint32_t t_lastSystemCode = 0;

}  // namespace

namespace NativeToolkitC::Detail {

void SetLastSystemCode(uint32_t code) noexcept
{
    t_lastSystemCode = code;
}

}  // namespace NativeToolkitC::Detail

extern "C" uint32_t NTK_CALL ntk_last_system_code(void)
{
    return t_lastSystemCode;
}
