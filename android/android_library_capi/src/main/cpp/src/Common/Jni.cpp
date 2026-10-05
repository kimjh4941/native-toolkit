#include "Common/Jni.h"

#include <atomic>
#include <pthread.h>

#include "Common/Log.h"

namespace nativetoolkit::jni {
namespace {

// Nothing here has a destructor: the process may end while other threads still use the VM
// (design 5.5).
std::atomic<JavaVM*> g_vm{nullptr};
pthread_key_t g_attached_key;
pthread_once_t g_key_once = PTHREAD_ONCE_INIT;

// Runs when a thread attached here ends. The app may have detached it already.
void DetachOnThreadExit(void* marker) {
    NTK_LOGD("[DetachOnThreadExit] marker: %p", marker);
    JavaVM* vm = g_vm.load();
    JNIEnv* env = nullptr;
    if (vm != nullptr && vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
        vm->DetachCurrentThread();
    }
}

void CreateKey() {
    NTK_LOGD("[CreateKey]");
    pthread_key_create(&g_attached_key, DetachOnThreadExit);
}

bool IsInstanceOfAny(JNIEnv* env, jthrowable error, const char* const* names) {
    NTK_LOGD("[IsInstanceOfAny] env: %p, error: %p", env, error);
    for (const char* const* name = names; *name != nullptr; ++name) {
        jclass type = env->FindClass(*name);
        if (type == nullptr) {
            env->ExceptionClear();
            continue;
        }
        bool matches = env->IsInstanceOf(error, type);
        env->DeleteLocalRef(type);
        if (matches) return true;
    }
    return false;
}

}  // namespace

void SetVm(JavaVM* vm) {
    NTK_LOGD("[SetVm] vm: %p", vm);
    JavaVM* expected = nullptr;
    g_vm.compare_exchange_strong(expected, vm);
}

JavaVM* Vm() {
    NTK_LOGD("[Vm]");
    return g_vm.load();
}

JNIEnv* Env() {
    NTK_LOGD("[Env]");
    JavaVM* vm = g_vm.load();
    if (vm == nullptr) return nullptr;
    JNIEnv* env = nullptr;
    jint state = vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (state == JNI_OK) return env;
    if (state != JNI_EDETACHED) {
        NTK_LOGE("[Env] GetEnv failed: %d", state);
        return nullptr;
    }
    pthread_once(&g_key_once, CreateKey);
    if (vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
        NTK_LOGE("[Env] AttachCurrentThread failed");
        return nullptr;
    }
    // Any non-null value makes the destructor run when the thread ends.
    pthread_setspecific(g_attached_key, reinterpret_cast<void*>(1));
    return env;
}

Failure TakeException(JNIEnv* env, const char* where) {
    NTK_LOGD("[TakeException] env: %p, where: %s", env, where);
    if (!env->ExceptionCheck()) return Failure::kNone;
    jthrowable error = env->ExceptionOccurred();
    env->ExceptionClear();
    static const char* const kMissing[] = {
        "java/lang/ClassNotFoundException", "java/lang/NoClassDefFoundError",
        "java/lang/NoSuchMethodError", "java/lang/NoSuchFieldError", nullptr};
    static const char* const kMemory[] = {"java/lang/OutOfMemoryError", nullptr};
    Failure failure = IsInstanceOfAny(env, error, kMissing) ? Failure::kClassNotFound
        : IsInstanceOfAny(env, error, kMemory) ? Failure::kOutOfMemory : Failure::kOther;

    // The class name only: an exception message may carry user data (design 5.12).
    jclass type = env->GetObjectClass(error);
    jclass class_class = env->FindClass("java/lang/Class");
    jmethodID get_name = class_class ? env->GetMethodID(class_class, "getName", "()Ljava/lang/String;") : nullptr;
    jstring name = get_name ? static_cast<jstring>(env->CallObjectMethod(type, get_name)) : nullptr;
    if (env->ExceptionCheck()) env->ExceptionClear();
    const char* chars = name ? env->GetStringUTFChars(name, nullptr) : nullptr;
    NTK_LOGE("[TakeException] where: %s, exception: %s", where, chars ? chars : "?");
    if (chars) env->ReleaseStringUTFChars(name, chars);
    if (name) env->DeleteLocalRef(name);
    if (class_class) env->DeleteLocalRef(class_class);
    env->DeleteLocalRef(type);
    env->DeleteLocalRef(error);
    return failure;
}

LocalFrame::LocalFrame(JNIEnv* env, jint capacity) : env_(env), pushed_(false) {
    NTK_LOGD("[LocalFrame] env: %p, capacity: %d", env, capacity);
    if (env_ == nullptr) return;
    pushed_ = env_->PushLocalFrame(capacity) == JNI_OK;
    if (!pushed_) TakeException(env_, "PushLocalFrame");
}

LocalFrame::~LocalFrame() {
    NTK_LOGD("[~LocalFrame] pushed: %d", pushed_ ? 1 : 0);
    if (pushed_) env_->PopLocalFrame(nullptr);
}

}  // namespace nativetoolkit::jni
