#pragma once
// The per-thread value behind ntk_last_system_code() (stage 5 design 7.3, E-4).

#include <cstdint>

namespace NativeToolkitC::Detail {

/// Records the raw OS value of the call that is about to return on this
/// thread: 0 for a success, Failure::systemCode (or 0) for a failure. Every
/// function that returns an error calls this exactly once on the way out;
/// readers, _free and asynchronous completions do not.
void SetLastSystemCode(uint32_t code) noexcept;

}  // namespace NativeToolkitC::Detail
