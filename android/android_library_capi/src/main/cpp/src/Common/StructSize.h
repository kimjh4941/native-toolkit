// Reading an input struct that starts with struct_size (C ABI design part 1, 1.1; the Windows C
// ABI design 7.8). One reader for every struct.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

#include "Common/Errors.h"
#include "Common/Log.h"

namespace nativetoolkit::structs {

// The largest struct_size accepted: a bigger one is an uninitialized value, and reading it could
// run past the caller's memory.
constexpr uint32_t kMaxStructSize = 4096;

// Copies *in into *out, a struct of this version whose first two fields are struct_size and
// reserved0. Returns:
//  - kErrorInvalidParameter when struct_size is below sizeof(T) (the 2.0.0 size is the minimum)
//    or above kMaxStructSize, or reserved0 is not 0;
//  - kErrorNotSupported when the part beyond sizeof(T) - a newer header's fields - has a byte
//    that is not 0, so that a newer field is never dropped silently;
//  - kErrorNone otherwise.
// When in is NULL, optional decides: *out is all zeros (the defaults) or the call is rejected.
// Other reserved fields are the caller's to check.
template <class T>
int32_t Read(const T* in, T* out, bool optional) {
    NTK_LOGD("[structs::Read] in: %p, out: %p, optional: %d, size: %zu", in, out, optional ? 1 : 0, sizeof(T));
    std::memset(out, 0, sizeof(T));
    if (in == nullptr) return optional ? kErrorNone : kErrorInvalidParameter;
    uint32_t header[2];
    std::memcpy(header, in, sizeof(header));
    uint32_t size = header[0];
    if (size < sizeof(T) || size > kMaxStructSize || header[1] != 0) return kErrorInvalidParameter;
    const auto* bytes = reinterpret_cast<const unsigned char*>(in);
    for (uint32_t i = sizeof(T); i < size; ++i) {
        if (bytes[i] != 0) return kErrorNotSupported;
    }
    std::memcpy(out, in, sizeof(T));
    return kErrorNone;
}

}  // namespace nativetoolkit::structs
