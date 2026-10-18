// Accepting an operation that completes later, or an event registration (C ABI design part 1,
// 5.7, 受け付け). The entry has checked its arguments; this makes the registration ACTIVE, has the
// Kotlin bridge post the insertion (and the start) to the main thread, and releases on the
// calling thread when nothing was posted, so that release runs exactly once either way.
#pragma once

#include <jni.h>

#include <cstdint>

#include "Common/Errors.h"
#include "Common/Jni.h"
#include "Common/Log.h"
#include "Common/Registry.h"

namespace nativetoolkit {

// post(env, id) calls the bridge and returns whether it posted; it may leave a Java exception.
// *out_id (may be null) is written only once accepted, from a local copy: after acceptance the
// registration belongs to the main thread and is not touched here (design 5.7, step 4).
template <class Post>
int32_t Accept(JNIEnv* env, int32_t kind, void* callback, void* user_data, ntk_release_fn release,
               registry::CancelCompletion cancel_completion, Post&& post, uint64_t* out_id) noexcept {
    NTK_LOGD("[Accept] env: %p, kind: %d, callback: %p, user_data: %p", env, kind, callback, user_data);
    uint64_t id = registry::Add(kind, callback, user_data, release, cancel_completion);
    if (id == 0) {
        registry::ReleaseRejected(release, user_data);
        return kErrorOutOfMemory;
    }
    jboolean posted = post(env, static_cast<jlong>(id));
    jni::Failure failure = jni::TakeException(env, "Accept post");
    if (failure != jni::Failure::kNone || posted != JNI_TRUE) {
        // Nothing reached the main thread, so the id is known to no one else.
        registry::TryRelease(id, registry::State::kActive);
        return failure != jni::Failure::kNone ? ErrorOf(failure) : kErrorUnknown;
    }
    if (out_id != nullptr) *out_id = id;
    return kErrorNone;
}

}  // namespace nativetoolkit
