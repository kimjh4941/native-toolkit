#include "Common/Runtime.h"

#include <atomic>
#include <cstdlib>
#include <string>
#include <vector>

#include "Common/Classes.h"

#include "Common/Export.h"
#include "Common/Jni.h"
#include "Common/Log.h"
#include "NativeToolkitC/Android.h"

namespace nativetoolkit::runtime {
namespace {

#ifndef NDEBUG
// Debug builds only, for the races in a set order (design part 1, chapter 6): runs in JNI_OnLoad
// and ntk_android_init between building the class table and MarkNativeDone, where the Kotlin side
// can report that it is done first. Not in a release build.
std::atomic<void (*)()> g_before_native_done{nullptr};
#endif

constexpr const char* kRuntimeClass = "com/jonghyunkim/nativetoolkit/capi/jni/NtkRuntime";

// What NtkRuntime.ensureInitialized returns: LibraryRuntime.InitState by ordinal.
constexpr jint kKotlinDone = 0;
constexpr jint kKotlinInProgress = 1;

// Nothing here has a destructor (design 5.5). The two marks and the state are read and written
// with the default (sequentially consistent) order, so that whichever side sets its mark last
// sees the other's and moves the state to kReady exactly once (design 5.3).
std::atomic<int> g_state{static_cast<int>(State::kUninit)};
std::atomic<bool> g_native_done{false};
std::atomic<bool> g_kotlin_done{false};
// Guards building the class table only. Taken with a try, never waited on: JNI_OnLoad runs on the
// main thread holding the runtime's library lock, and waiting here could wait on it (AC-16).
std::atomic<bool> g_building{false};
ClassTable g_classes;

bool TryLockBuilding() {
    NTK_LOGD("[TryLockBuilding]");
    bool expected = false;
    return g_building.compare_exchange_strong(expected, true);
}

void UnlockBuilding() {
    NTK_LOGD("[UnlockBuilding]");
    g_building.store(false);
}

bool Promote(State from, State to) {
    NTK_LOGD("[Promote] from: %d, to: %d", static_cast<int>(from), static_cast<int>(to));
    int expected = static_cast<int>(from);
    return g_state.compare_exchange_strong(expected, static_cast<int>(to));
}

void MarkNativeDone() {
    NTK_LOGD("[MarkNativeDone]");
    g_native_done.store(true);
    Promote(State::kUninit, State::kNativeReady);
    if (g_kotlin_done.load()) Promote(State::kNativeReady, State::kReady);
}

State MarkKotlinDone() {
    NTK_LOGD("[MarkKotlinDone]");
    g_kotlin_done.store(true);
    if (g_native_done.load()) Promote(State::kNativeReady, State::kReady);
    return Current();
}

// NtkRuntime.onKotlinReady: the Kotlin side reports that LibraryRuntime is done.
jint JNICALL OnKotlinReady(JNIEnv* /*env*/, jclass /*type*/) {
    NTK_LOGD("[OnKotlinReady]");
    return static_cast<jint>(MarkKotlinDone());
}

// NtkRuntime.nativeState: the C state, for NativeToolkitCApi.isInitialized.
jint JNICALL NativeState(JNIEnv* /*env*/, jclass /*type*/) {
    NTK_LOGD("[NativeState]");
    return static_cast<jint>(Current());
}

enum class Build { kOk, kClassNotFound, kTransient };

Build FailureToBuild(jni::Failure failure) {
    NTK_LOGD("[FailureToBuild] failure: %d", static_cast<int>(failure));
    return failure == jni::Failure::kClassNotFound ? Build::kClassNotFound : Build::kTransient;
}

// Loads a class (slash form) through loader, or with FindClass when loader is null (JNI_OnLoad,
// where FindClass uses the class loader of the code that called System.loadLibrary).
jclass LoadClass(JNIEnv* env, jobject loader, const char* name, jni::Failure* failure) {
    NTK_LOGD("[LoadClass] env: %p, loader: %p, name: %s", env, loader, name);
    *failure = jni::Failure::kNone;
    if (loader == nullptr) {
        jclass found = env->FindClass(name);
        *failure = jni::TakeException(env, "FindClass");
        return *failure == jni::Failure::kNone ? found : nullptr;
    }
    jclass loader_class = env->FindClass("java/lang/ClassLoader");
    jmethodID load_class = loader_class == nullptr ? nullptr
        : env->GetMethodID(loader_class, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;");
    if ((*failure = jni::TakeException(env, "ClassLoader.loadClass lookup")) != jni::Failure::kNone) return nullptr;
    std::string dotted(name);
    for (char& c : dotted) {
        if (c == '/') c = '.';
    }
    // Class names are ASCII, so NewStringUTF's Modified UTF-8 is the same as UTF-8 (design 5.10).
    jstring java_name = env->NewStringUTF(dotted.c_str());
    if ((*failure = jni::TakeException(env, "NewStringUTF")) != jni::Failure::kNone) return nullptr;
    auto found = static_cast<jclass>(env->CallObjectMethod(loader, load_class, java_name));
    *failure = jni::TakeException(env, "ClassLoader.loadClass");
    return *failure == jni::Failure::kNone ? found : nullptr;
}

// Builds the whole class table - every class, method and native of classes::All() - or none of
// it: on a failure the global references made so far are deleted and nothing is published.
// Called with g_building held and the state kUninit; the state change publishes the table.
Build BuildTable(JNIEnv* env, jobject loader) {
    NTK_LOGD("[BuildTable] env: %p, loader: %p", env, loader);
    std::vector<classes::ClassSpec> specs = classes::All();
    std::vector<jclass> globals;
    auto fail = [&](jni::Failure failure) {
        for (jclass global : globals) env->DeleteGlobalRef(global);
        return FailureToBuild(failure == jni::Failure::kNone ? jni::Failure::kOther : failure);
    };
    for (const classes::ClassSpec& spec : specs) {
        jni::Failure failure = jni::Failure::kNone;
        jclass local = LoadClass(env, loader, spec.name, &failure);
        if (local == nullptr) return fail(failure);
        // The failure names the class and the member, so that a wrong signature is found at once:
        // any one of them leaves the whole C ABI NOT_INITIALIZED.
        for (const classes::StaticMethod& method : spec.methods) {
            *method.out = env->GetStaticMethodID(local, method.name, method.signature);
            std::string where = std::string(spec.name) + "." + method.name + method.signature;
            if ((failure = jni::TakeException(env, where.c_str())) != jni::Failure::kNone) return fail(failure);
        }
        for (const JNINativeMethod& native : spec.natives) {
            env->RegisterNatives(local, &native, 1);
            std::string where = std::string("RegisterNatives ") + spec.name + "." + native.name + native.signature;
            if ((failure = jni::TakeException(env, where.c_str())) != jni::Failure::kNone) return fail(failure);
        }
        auto global = static_cast<jclass>(env->NewGlobalRef(local));
        env->DeleteLocalRef(local);
        if (global == nullptr) {
            jni::TakeException(env, "NewGlobalRef");
            return fail(jni::Failure::kOutOfMemory);
        }
        globals.push_back(global);
    }
    for (size_t i = 0; i < specs.size(); ++i) *specs[i].out = globals[i];
    return Build::kOk;
}

// Calls NtkRuntime.ensureInitialized(context) without the class table, for a caller that lost the
// race to build it: an Activity passed in is still taken as the foreground (design 5.3). Failures
// are only logged; the winner reports the result.
void EnsureInitializedWithoutTable(JNIEnv* env, jobject context) {
    NTK_LOGD("[EnsureInitializedWithoutTable] env: %p, context: %p", env, context);
    jclass context_class = env->GetObjectClass(context);
    jmethodID get_loader = env->GetMethodID(context_class, "getClassLoader", "()Ljava/lang/ClassLoader;");
    if (jni::TakeException(env, "Context.getClassLoader lookup") != jni::Failure::kNone) return;
    jobject loader = env->CallObjectMethod(context, get_loader);
    if (jni::TakeException(env, "Context.getClassLoader") != jni::Failure::kNone || loader == nullptr) return;
    jni::Failure failure = jni::Failure::kNone;
    jclass runtime = LoadClass(env, loader, kRuntimeClass, &failure);
    if (runtime == nullptr) return;
    jmethodID ensure = env->GetStaticMethodID(runtime, "ensureInitialized", "(Landroid/content/Context;)I");
    if (jni::TakeException(env, "GetStaticMethodID ensureInitialized") != jni::Failure::kNone) return;
    env->CallStaticIntMethod(runtime, ensure, context);
    jni::TakeException(env, "NtkRuntime.ensureInitialized");
}

// The NATIVE_READY column of design 5.3: the class table exists; run the Kotlin side.
ntk_android_error InitKotlinSide(JNIEnv* env, jobject context) {
    NTK_LOGD("[InitKotlinSide] env: %p, context: %p", env, context);
    jint result = env->CallStaticIntMethod(g_classes.runtime, g_classes.ensure_initialized, context);
    if (jni::TakeException(env, "NtkRuntime.ensureInitialized") != jni::Failure::kNone) {
        return NTK_ANDROID_ERROR_JNI_FAILURE;
    }
    if (result == kKotlinDone) {
        return MarkKotlinDone() == State::kReady ? NTK_ANDROID_ERROR_NONE : NTK_ANDROID_ERROR_IN_PROGRESS;
    }
    // In progress or failed: NtkRuntime has asked LibraryRuntime to report when it is done.
    return result == kKotlinInProgress ? NTK_ANDROID_ERROR_IN_PROGRESS : NTK_ANDROID_ERROR_JNI_FAILURE;
}

ntk_android_error Init(JNIEnv* env, jobject context) {
    NTK_LOGD("[Init] env: %p, context: %p", env, context);
    switch (Current()) {
        case State::kReady:
            return NTK_ANDROID_ERROR_NONE;
        case State::kFailed:
            return NTK_ANDROID_ERROR_CLASS_NOT_FOUND;
        case State::kNativeReady:
            return InitKotlinSide(env, context);
        case State::kUninit:
            break;
    }
    if (!TryLockBuilding()) {
        EnsureInitializedWithoutTable(env, context);
        return NTK_ANDROID_ERROR_IN_PROGRESS;
    }
    ntk_android_error error = NTK_ANDROID_ERROR_NONE;
    if (Current() == State::kUninit) {
        jclass context_class = env->GetObjectClass(context);
        jmethodID get_loader = env->GetMethodID(context_class, "getClassLoader", "()Ljava/lang/ClassLoader;");
        jobject loader = nullptr;
        jni::Failure failure = jni::TakeException(env, "Context.getClassLoader lookup");
        if (failure == jni::Failure::kNone) {
            loader = env->CallObjectMethod(context, get_loader);
            failure = jni::TakeException(env, "Context.getClassLoader");
        }
        Build built = failure != jni::Failure::kNone || loader == nullptr ? Build::kTransient : BuildTable(env, loader);
        if (built == Build::kOk) {
#ifndef NDEBUG
            BeforeNativeDone();
#endif
            MarkNativeDone();
        } else if (built == Build::kClassNotFound) {
            // Only the app's own class loader can tell that the classes are not there (design 5.3).
            Promote(State::kUninit, State::kFailed);
            error = NTK_ANDROID_ERROR_CLASS_NOT_FOUND;
        } else {
            error = NTK_ANDROID_ERROR_JNI_FAILURE;
        }
    }
    UnlockBuilding();
    if (error != NTK_ANDROID_ERROR_NONE) return error;
    // The table is built (here or by another thread in between): carry on outside the lock.
    switch (Current()) {
        case State::kReady:
            return NTK_ANDROID_ERROR_NONE;
        case State::kNativeReady:
            return InitKotlinSide(env, context);
        case State::kFailed:
            return NTK_ANDROID_ERROR_CLASS_NOT_FOUND;
        case State::kUninit:
            break;
    }
    return NTK_ANDROID_ERROR_JNI_FAILURE;
}

}  // namespace

State Current() {
    NTK_LOGD("[Current]");
    return static_cast<State>(g_state.load());
}

bool IsReady() {
    NTK_LOGD("[IsReady]");
    return Current() == State::kReady;
}

const ClassTable& Classes() {
    NTK_LOGD("[Classes]");
    return g_classes;
}

classes::ClassSpec RuntimeClassSpec() {
    NTK_LOGD("[RuntimeClassSpec]");
    return {
        kRuntimeClass,
        &g_classes.runtime,
        {{"ensureInitialized", "(Landroid/content/Context;)I", &g_classes.ensure_initialized}},
        {
            {"onKotlinReady", "()I", reinterpret_cast<void*>(OnKotlinReady)},
            {"nativeState", "()I", reinterpret_cast<void*>(NativeState)},
        },
    };
}

#ifndef NDEBUG
void SetBeforeNativeDone(void (*hook)()) {
    NTK_LOGD("[SetBeforeNativeDone] hook: %p", reinterpret_cast<void*>(hook));
    g_before_native_done.store(hook);
}

void BeforeNativeDone() {
    NTK_LOGD("[BeforeNativeDone]");
    if (void (*hook)() = g_before_native_done.load(); hook != nullptr) hook();
}
#endif

}  // namespace nativetoolkit::runtime

using nativetoolkit::runtime::State;
namespace jni = nativetoolkit::jni;
namespace runtime = nativetoolkit::runtime;

// Idempotent and never waits (AC-16): an app that System.loadLibrary's its own .so, which depends
// on libntk.so and has no JNI_OnLoad of its own, runs this again (stage 1a 3.2). A failure is not
// reported as JNI_ERR, which would make that app's System.loadLibrary fail, and is not counted as
// kFailed: ntk_android_init, with the app's class loader, is the one to decide that.
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    NTK_LOGD("[JNI_OnLoad] vm: %p, reserved: %p", vm, reserved);
    jni::SetVm(vm);
#ifndef NDEBUG
    // Debug builds only, for the initialization tests (design part 1, chapter 6): behaves as a
    // JNI_OnLoad whose class loader cannot see the C ABI's classes. Not in a release build.
    if (const char* fail = std::getenv("NTK_TEST_FAIL_JNI_ONLOAD"); fail != nullptr && fail[0] == '1') {
        NTK_LOGW("[JNI_OnLoad] failing on purpose (NTK_TEST_FAIL_JNI_ONLOAD)");
        return JNI_VERSION_1_6;
    }
#endif
    if (runtime::Current() != State::kUninit || !runtime::TryLockBuilding()) return JNI_VERSION_1_6;
    if (runtime::Current() == State::kUninit) {
        JNIEnv* env = nullptr;
        if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) == JNI_OK) {
            jni::LocalFrame frame(env, 16);
            if (frame.ok() && runtime::BuildTable(env, nullptr) == runtime::Build::kOk) {
#ifndef NDEBUG
                runtime::BeforeNativeDone();
#endif
                runtime::MarkNativeDone();
            } else {
                NTK_LOGW("[JNI_OnLoad] the class table is not built; ntk_android_init can build it");
            }
        }
    }
    runtime::UnlockBuilding();
    return JNI_VERSION_1_6;
}

NTK_EXPORT ntk_android_error NTK_CALL ntk_android_init(void* env, void* context) {
    NTK_LOGD("[ntk_android_init] env: %p, context: %p", env, context);
    if (env == nullptr || context == nullptr) return NTK_ANDROID_ERROR_INVALID_PARAMETER;
    auto* jenv = static_cast<JNIEnv*>(env);
    JavaVM* vm = nullptr;
    if (jenv->GetJavaVM(&vm) != JNI_OK) return NTK_ANDROID_ERROR_JNI_FAILURE;
    jni::SetVm(vm);
    if (runtime::Current() == State::kReady) return NTK_ANDROID_ERROR_NONE;
    jni::LocalFrame frame(jenv, 32);
    if (!frame.ok()) return NTK_ANDROID_ERROR_JNI_FAILURE;
    return runtime::Init(jenv, static_cast<jobject>(context));
}

NTK_EXPORT int32_t NTK_CALL ntk_android_is_initialized(void) {
    NTK_LOGD("[ntk_android_is_initialized]");
    return runtime::IsReady() ? 1 : 0;
}

#ifndef NDEBUG
// Debug builds only: see g_before_native_done. Not part of the C ABI.
NTK_EXPORT void ntk_debug_runtime_before_native_done(void (*hook)(void)) {
    NTK_LOGD("[ntk_debug_runtime_before_native_done] hook: %p", reinterpret_cast<void*>(hook));
    runtime::SetBeforeNativeDone(hook);
}
#endif
