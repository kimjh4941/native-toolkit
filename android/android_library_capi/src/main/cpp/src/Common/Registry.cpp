#include "Common/Registry.h"

#include <mutex>
#include <new>
#include <unordered_map>

#include "Common/Jni.h"
#include "Common/Log.h"
#include "Common/Main.h"

namespace nativetoolkit::registry {
namespace {

// Never destroyed (design 5.5): the process may end while other threads still use the table.
std::mutex& TableMutex() {
    static auto* mutex = new std::mutex;
    return *mutex;
}

std::unordered_map<uint64_t, Registration*>& Table() {
    static auto* table = new std::unordered_map<uint64_t, Registration*>;
    return *table;
}

std::atomic<uint64_t> g_next_id{1};

jclass g_ledger = nullptr;
jmethodID g_post_remove = nullptr;  // static boolean postRemove(long)

// The removal of design 5.7 (the 外す row), on the main thread.
void RemoveOnMain(uint64_t id) noexcept {
    NTK_LOGD("[RemoveOnMain] id: %llu", static_cast<unsigned long long>(id));
    Registration* registration = FindOnMain(id);
    if (registration == nullptr) return;
    if (registration->state.load() != static_cast<int>(State::kCancelRequested)) return;
    if (!registration->completed && registration->cancel_completion != nullptr) {
        registration->completed = true;
        registration->cancel_completion(*registration);
    }
    TryRelease(id, State::kCancelRequested);
}

// Ledger.nativeIsActive: whether the insertion should put the id in the ledger and start.
jboolean JNICALL NativeIsActive(JNIEnv* /*env*/, jclass /*type*/, jlong id) {
    NTK_LOGD("[NativeIsActive] id: %lld", static_cast<long long>(id));
    return StateOf(static_cast<uint64_t>(id)) == State::kActive ? JNI_TRUE : JNI_FALSE;
}

// Ledger.nativeRemove: the removal a cancel posted.
void JNICALL NativeRemove(JNIEnv* /*env*/, jclass /*type*/, jlong id) {
    NTK_LOGD("[NativeRemove] id: %lld", static_cast<long long>(id));
    RemoveOnMain(static_cast<uint64_t>(id));
}

bool PostRemove(uint64_t id) noexcept {
    NTK_LOGD("[PostRemove] id: %llu", static_cast<unsigned long long>(id));
    JNIEnv* env = jni::Env();
    if (env == nullptr || g_ledger == nullptr) return false;
    jni::LocalFrame frame(env, 4);
    jboolean posted = env->CallStaticBooleanMethod(g_ledger, g_post_remove, static_cast<jlong>(id));
    if (jni::TakeException(env, "Ledger.postRemove") != jni::Failure::kNone) return false;
    return posted == JNI_TRUE;
}

}  // namespace

uint64_t Add(int32_t kind, void* callback, void* user_data, ntk_release_fn release,
             CancelCompletion cancel_completion) noexcept {
    NTK_LOGD("[Add] kind: %d, callback: %p, user_data: %p, release: %p", kind, callback, user_data,
             reinterpret_cast<void*>(release));
    auto* registration = new (std::nothrow) Registration;
    if (registration == nullptr) return 0;
    registration->id = g_next_id.fetch_add(1);
    registration->kind = kind;
    registration->callback = callback;
    registration->user_data = user_data;
    registration->release = release;
    registration->cancel_completion = cancel_completion;
    try {
        std::lock_guard<std::mutex> lock(TableMutex());
        Table().emplace(registration->id, registration);
    } catch (const std::bad_alloc&) {
        delete registration;
        return 0;
    }
    return registration->id;
}

bool TryRelease(uint64_t id, State expected) noexcept {
    NTK_LOGD("[TryRelease] id: %llu, expected: %d", static_cast<unsigned long long>(id), static_cast<int>(expected));
    Registration* registration = nullptr;
    {
        std::lock_guard<std::mutex> lock(TableMutex());
        auto found = Table().find(id);
        if (found == Table().end()) return false;
        int from = static_cast<int>(expected);
        if (!found->second->state.compare_exchange_strong(from, static_cast<int>(State::kReleased))) return false;
        registration = found->second;
        Table().erase(found);
    }
    // Outside the mutex: release is the app's code and may call back into the C ABI.
    if (registration->release != nullptr) registration->release(registration->user_data);
    delete registration;
    return true;
}

void ReleaseRejected(ntk_release_fn release, void* user_data) noexcept {
    NTK_LOGD("[ReleaseRejected] release: %p, user_data: %p", reinterpret_cast<void*>(release), user_data);
    if (release != nullptr) release(user_data);
}

bool Cancel(uint64_t id) noexcept {
    NTK_LOGD("[Cancel] id: %llu", static_cast<unsigned long long>(id));
    {
        std::lock_guard<std::mutex> lock(TableMutex());
        auto found = Table().find(id);
        if (found == Table().end()) return false;
        int from = static_cast<int>(State::kActive);
        if (!found->second->state.compare_exchange_strong(from, static_cast<int>(State::kCancelRequested))) return false;
    }
    // From here the registration may be freed by the main thread at any time: only the id is used.
    // A post that fails means the main thread's looper has ended, which happens only when the
    // process ends; then nothing is released (design 1.3).
    if (!PostRemove(id)) NTK_LOGW("[Cancel] could not post the removal of %llu", static_cast<unsigned long long>(id));
    return true;
}

State StateOf(uint64_t id) noexcept {
    NTK_LOGD("[StateOf] id: %llu", static_cast<unsigned long long>(id));
    std::lock_guard<std::mutex> lock(TableMutex());
    auto found = Table().find(id);
    return found == Table().end() ? State::kReleased : static_cast<State>(found->second->state.load());
}

Registration* FindOnMain(uint64_t id) noexcept {
    NTK_LOGD("[FindOnMain] id: %llu", static_cast<unsigned long long>(id));
    if (!IsMainThread()) {
        NTK_LOGE("[FindOnMain] called off the main thread");
        return nullptr;
    }
    std::lock_guard<std::mutex> lock(TableMutex());
    auto found = Table().find(id);
    return found == Table().end() ? nullptr : found->second;
}

size_t Count() noexcept {
    NTK_LOGD("[Count]");
    std::lock_guard<std::mutex> lock(TableMutex());
    return Table().size();
}

classes::ClassSpec LedgerClassSpec() {
    NTK_LOGD("[LedgerClassSpec]");
    return {
        "com/jonghyunkim/nativetoolkit/capi/jni/Ledger",
        &g_ledger,
        {{"postRemove", "(J)Z", &g_post_remove}},
        {
            {"nativeIsActive", "(J)Z", reinterpret_cast<void*>(NativeIsActive)},
            {"nativeRemove", "(J)V", reinterpret_cast<void*>(NativeRemove)},
        },
    };
}

}  // namespace nativetoolkit::registry
