// The values 0 to 5 that every feature's error enumeration shares (C ABI design part 2, AP-12),
// so that the shared parts can return them for any feature.
#pragma once

#include <cstdint>

#include "Common/Jni.h"

namespace nativetoolkit {

enum CommonError : int32_t {
    kErrorNone = 0,
    kErrorInvalidParameter = 1,
    kErrorNotInitialized = 2,
    kErrorNotSupported = 3,
    kErrorUnknown = 4,
    kErrorOutOfMemory = 5,
};

// The error for a JNI failure: running out of memory, or anything else (part 2, 11 chapter).
inline int32_t ErrorOf(jni::Failure failure) {
    return failure == jni::Failure::kOutOfMemory ? kErrorOutOfMemory : kErrorUnknown;
}

}  // namespace nativetoolkit
