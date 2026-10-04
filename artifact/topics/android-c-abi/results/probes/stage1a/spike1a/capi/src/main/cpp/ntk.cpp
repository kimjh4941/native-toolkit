#include <jni.h>
#include <android/log.h>
#include <pthread.h>
#include <string>
#include <vector>
#include "NativeToolkitC/Spike.h"

#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, "ntk", __VA_ARGS__)

namespace {
JavaVM* g_vm = nullptr;
jclass g_class = nullptr;
jmethodID g_callback = nullptr;

jstring NativeHello(JNIEnv* env, jclass, jstring input) {
    const char* chars = env->GetStringUTFChars(input, nullptr);
    std::string out = std::string("hello:") + chars;
    env->ReleaseStringUTFChars(input, chars);
    return env->NewStringUTF(out.c_str());
}

int CallKotlin(int value) {
    if (g_vm == nullptr || g_class == nullptr || g_callback == nullptr) return -1;
    JNIEnv* env = nullptr;
    bool attached = false;
    jint state = g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (state == JNI_EDETACHED) {
        if (g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return -2;
        attached = true;
    } else if (state != JNI_OK) {
        return -3;
    }
    env->CallStaticVoidMethod(g_class, g_callback, static_cast<jint>(value));
    bool failed = env->ExceptionCheck();
    if (failed) env->ExceptionClear();
    if (attached) g_vm->DetachCurrentThread();
    return failed ? -4 : 0;
}

void* ThreadMain(void* arg) {
    auto* box = static_cast<int*>(arg);
    box[1] = CallKotlin(box[0]);
    return nullptr;
}
}  // namespace

JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void*) {
    LOGD("JNI_OnLoad");
    g_vm = vm;
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    jclass local = env->FindClass("com/jonghyunkim/nativetoolkit/capi/NtkNative");
    if (local == nullptr) return JNI_ERR;
    g_class = static_cast<jclass>(env->NewGlobalRef(local));
    env->DeleteLocalRef(local);
    const JNINativeMethod methods[] = {
        {"nativeHello", "(Ljava/lang/String;)Ljava/lang/String;", reinterpret_cast<void*>(NativeHello)},
    };
    if (env->RegisterNatives(g_class, methods, 1) != JNI_OK) return JNI_ERR;
    g_callback = env->GetStaticMethodID(g_class, "onNativeCallback", "(I)V");
    if (g_callback == nullptr) return JNI_ERR;
    return JNI_VERSION_1_6;
}

extern "C" {
NTK_API int ntk_spike_onload_called(void) { return g_vm != nullptr ? 1 : 0; }

NTK_API int ntk_spike_created_vms(int* same) {
    JavaVM* vms[2] = {nullptr, nullptr};
    jsize count = 0;
    if (JNI_GetCreatedJavaVMs(vms, 2, &count) != JNI_OK) return -1;
    if (same != nullptr) *same = (count > 0 && vms[0] == g_vm) ? 1 : 0;
    return static_cast<int>(count);
}

NTK_API int ntk_spike_call_kotlin(int value) { return CallKotlin(value); }

NTK_API int ntk_spike_call_kotlin_from_new_thread(int value) {
    int box[2] = {value, -100};
    pthread_t thread;
    if (pthread_create(&thread, nullptr, ThreadMain, box) != 0) return -5;
    pthread_join(thread, nullptr);
    return box[1];
}

NTK_API int ntk_spike_cxx_check(void) {
    std::vector<std::string> v = {"a", "bb", "ccc"};
    size_t n = 0;
    for (const auto& s : v) n += s.size();
    return static_cast<int>(n);
}
}
