#include "Debug/Probe.h"

#include <atomic>

#include "Common/Accept.h"
#include "Common/Errors.h"
#include "Common/Export.h"
#include "Common/Jni.h"
#include "Common/Log.h"
#include "Common/Registry.h"
#include "Common/Runtime.h"
#include "NativeToolkitC/Common.h"

namespace nativetoolkit::probe {
namespace {

using DoneFn = void (*)(void* user_data, int32_t error, int64_t value);
using EventFn = void (*)(void* user_data, int64_t value);

constexpr int32_t kKindOperation = 900;  // ProbeBridge.KIND_OPERATION
constexpr int32_t kKindEvent = 901;      // ProbeBridge.KIND_EVENT
constexpr int32_t kCanceled = 6;         // the probe's CANCELED, as the features' 6

jclass g_bridge = nullptr;
jmethodID g_start = nullptr;
jmethodID g_finish = nullptr;
jmethodID g_add_listener = nullptr;
jmethodID g_emit = nullptr;
std::atomic<bool> g_fail_next_post{false};

void CompleteCanceled(registry::Registration& registration) {
    NTK_LOGD("[CompleteCanceled] id: %llu", static_cast<unsigned long long>(registration.id));
    reinterpret_cast<DoneFn>(registration.callback)(registration.user_data, kCanceled, 0);
}

void JNICALL NativeComplete(JNIEnv* /*env*/, jclass /*type*/, jlong id, jlong value) {
    NTK_LOGD("[NativeComplete] id: %lld, value: %lld", static_cast<long long>(id), static_cast<long long>(value));
    registry::CompleteOnMain(static_cast<uint64_t>(id), [value](registry::Registration& registration) {
        reinterpret_cast<DoneFn>(registration.callback)(registration.user_data, kErrorNone, value);
    });
}

void JNICALL NativeDeliver(JNIEnv* /*env*/, jclass /*type*/, jlong id, jlong value) {
    NTK_LOGD("[NativeDeliver] id: %lld, value: %lld", static_cast<long long>(id), static_cast<long long>(value));
    registry::DeliverOnMain(static_cast<uint64_t>(id), [value](registry::Registration& registration) {
        reinterpret_cast<EventFn>(registration.callback)(registration.user_data, value);
    });
}

// The entry checks every operation shares: the arguments, then the initialization (AC-3). A
// rejected call releases on the calling thread (design 1.3).
int32_t CheckEntry(void* callback, void* out, ntk_release_fn release, void* user_data, JNIEnv** env) {
    NTK_LOGD("[CheckEntry] callback: %p, out: %p", callback, out);
    int32_t error = kErrorNone;
    if (callback == nullptr || out == nullptr) {
        error = kErrorInvalidParameter;
    } else if (!runtime::IsReady()) {
        error = kErrorNotInitialized;
    } else if ((*env = jni::Env()) == nullptr) {
        error = kErrorUnknown;
    }
    if (error != kErrorNone) registry::ReleaseRejected(release, user_data);
    return error;
}

jboolean CallPost(JNIEnv* env, jmethodID method, jlong id) {
    NTK_LOGD("[CallPost] env: %p, id: %lld", env, static_cast<long long>(id));
    if (g_fail_next_post.exchange(false)) return JNI_FALSE;
    return env->CallStaticBooleanMethod(g_bridge, method, id);
}

}  // namespace

classes::ClassSpec ProbeClassSpec() {
    NTK_LOGD("[ProbeClassSpec]");
    return {
        "com/jonghyunkim/nativetoolkit/capi/jni/ProbeBridge",
        &g_bridge,
        {
            {"start", "(J)Z", &g_start},
            {"finish", "(JJ)Z", &g_finish},
            {"addListener", "(J)Z", &g_add_listener},
            {"emit", "(J)Z", &g_emit},
        },
        {
            {"nativeComplete", "(JJ)V", reinterpret_cast<void*>(NativeComplete)},
            {"nativeDeliver", "(JJ)V", reinterpret_cast<void*>(NativeDeliver)},
        },
    };
}

}  // namespace nativetoolkit::probe

namespace probe = nativetoolkit::probe;
namespace registry = nativetoolkit::registry;
namespace jni = nativetoolkit::jni;
using nativetoolkit::kErrorNone;
using nativetoolkit::kErrorUnknown;

NTK_EXPORT int32_t ntk_debug_probe_start(probe::DoneFn callback, void* user_data, ntk_release_fn release,
                                         uint64_t* out_id) {
    NTK_LOGD("[ntk_debug_probe_start] callback: %p, user_data: %p, out_id: %p", reinterpret_cast<void*>(callback),
             user_data, out_id);
    if (out_id != nullptr) *out_id = 0;
    JNIEnv* env = nullptr;
    int32_t error = probe::CheckEntry(reinterpret_cast<void*>(callback), out_id, release, user_data, &env);
    if (error != kErrorNone) return error;
    jni::LocalFrame frame(env, 8);
    return nativetoolkit::Accept(env, probe::kKindOperation, reinterpret_cast<void*>(callback), user_data, release,
                                 probe::CompleteCanceled,
                                 [](JNIEnv* e, jlong id) { return probe::CallPost(e, probe::g_start, id); }, out_id);
}

NTK_EXPORT int32_t ntk_debug_probe_finish(uint64_t id, int64_t value) {
    NTK_LOGD("[ntk_debug_probe_finish] id: %llu, value: %lld", static_cast<unsigned long long>(id),
             static_cast<long long>(value));
    if (!nativetoolkit::runtime::IsReady()) return nativetoolkit::kErrorNotInitialized;
    JNIEnv* env = jni::Env();
    if (env == nullptr) return kErrorUnknown;
    jni::LocalFrame frame(env, 4);
    jboolean posted = env->CallStaticBooleanMethod(probe::g_bridge, probe::g_finish, static_cast<jlong>(id),
                                                   static_cast<jlong>(value));
    if (jni::TakeException(env, "ProbeBridge.finish") != jni::Failure::kNone || posted != JNI_TRUE) return kErrorUnknown;
    return kErrorNone;
}

NTK_EXPORT int32_t ntk_debug_probe_cancel(uint64_t id) {
    NTK_LOGD("[ntk_debug_probe_cancel] id: %llu", static_cast<unsigned long long>(id));
    registry::Cancel(id, {probe::kKindOperation});
    return kErrorNone;
}

NTK_EXPORT int32_t ntk_debug_probe_add_listener(probe::EventFn callback, void* user_data, ntk_release_fn release,
                                                uint64_t* out_handle) {
    NTK_LOGD("[ntk_debug_probe_add_listener] callback: %p, user_data: %p, out_handle: %p",
             reinterpret_cast<void*>(callback), user_data, out_handle);
    if (out_handle != nullptr) *out_handle = 0;
    JNIEnv* env = nullptr;
    int32_t error = probe::CheckEntry(reinterpret_cast<void*>(callback), out_handle, release, user_data, &env);
    if (error != kErrorNone) return error;
    jni::LocalFrame frame(env, 8);
    return nativetoolkit::Accept(env, probe::kKindEvent, reinterpret_cast<void*>(callback), user_data, release, nullptr,
                                 [](JNIEnv* e, jlong id) { return probe::CallPost(e, probe::g_add_listener, id); },
                                 out_handle);
}

NTK_EXPORT void ntk_debug_probe_listener_remove(uint64_t handle) {
    NTK_LOGD("[ntk_debug_probe_listener_remove] handle: %llu", static_cast<unsigned long long>(handle));
    if (handle != 0) registry::Cancel(handle, {probe::kKindEvent});
}

NTK_EXPORT int32_t ntk_debug_probe_emit(int64_t value) {
    NTK_LOGD("[ntk_debug_probe_emit] value: %lld", static_cast<long long>(value));
    if (!nativetoolkit::runtime::IsReady()) return nativetoolkit::kErrorNotInitialized;
    JNIEnv* env = jni::Env();
    if (env == nullptr) return kErrorUnknown;
    jni::LocalFrame frame(env, 4);
    jboolean posted = env->CallStaticBooleanMethod(probe::g_bridge, probe::g_emit, static_cast<jlong>(value));
    if (jni::TakeException(env, "ProbeBridge.emit") != jni::Failure::kNone || posted != JNI_TRUE) return kErrorUnknown;
    return kErrorNone;
}

NTK_EXPORT void ntk_debug_probe_fail_next_post(void) {
    NTK_LOGD("[ntk_debug_probe_fail_next_post]");
    probe::g_fail_next_post.store(true);
}

NTK_EXPORT size_t ntk_debug_probe_registrations(void) {
    NTK_LOGD("[ntk_debug_probe_registrations]");
    return registry::Count();
}
