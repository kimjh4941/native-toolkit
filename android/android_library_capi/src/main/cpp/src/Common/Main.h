// Whether the calling thread is the main thread. On Android the main thread's id is the pid.
#pragma once

#include <unistd.h>

namespace nativetoolkit {

inline bool IsMainThread() {
    return gettid() == getpid();
}

}  // namespace nativetoolkit
