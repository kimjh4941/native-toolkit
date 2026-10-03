#pragma once
// No exception crosses the C ABI (stage 5 design 7.7).

#include <cstdint>
#include <new>

#include "Common/LastError.h"

namespace NativeToolkitC::Detail {

/// Runs body and turns anything it throws into an error of the feature.
/// std::bad_alloc becomes outOfMemory with outOfMemorySystemCode; anything
/// else becomes unknown with a system code of 0. body is responsible for the
/// system code on every path it returns through.
template <class Code, class F>
Code Guarded(Code unknown, Code outOfMemory, uint32_t outOfMemorySystemCode, F&& body) noexcept
{
    try {
        return body();
    } catch (const std::bad_alloc&) {
        SetLastSystemCode(outOfMemorySystemCode);
        return outOfMemory;
    } catch (...) {
        SetLastSystemCode(0);
        return unknown;
    }
}

/// Runs a caller's callback, dropping anything a C++ callback throws: the
/// library has nowhere to send it and must not unwind through the OS.
template <class F>
void CallCaller(F&& callback) noexcept
{
    try {
        callback();
    } catch (...) {
    }
}

}  // namespace NativeToolkitC::Detail
