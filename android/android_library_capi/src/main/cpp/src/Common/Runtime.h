// The initialization of the C ABI (C ABI design part 1, 1.4 and 5.3): two preparations - the
// native class table and the Kotlin side - and one state that says when both are done.
#pragma once

#include <jni.h>

namespace nativetoolkit::runtime {

// The C state (design 5.3). Every change is a compare-and-swap; nothing moves back from kReady.
// The values are also what NtkRuntime.onKotlinReady and nativeState return to Kotlin.
enum class State : int {
    kUninit = 0,       // no class table yet, including after a failure that can be retried
    kNativeReady = 1,  // the class table and RegisterNatives are done; the Kotlin side is not
    kReady = 2,        // both are done: the C ABI works
    kFailed = 3,       // the app's class loader has no capi.jni classes; retrying does not help
};

State Current();

// Whether the C ABI may be used. Operations return NOT_INITIALIZED until it is (AC-3).
bool IsReady();

// The classes and methods the C ABI calls, looked up once (design 5.6). Valid once the state has
// reached kNativeReady; never freed (design 5.5).
struct ClassTable {
    jclass runtime = nullptr;                 // capi.jni.NtkRuntime
    jmethodID ensure_initialized = nullptr;   // static int ensureInitialized(Context)
};

const ClassTable& Classes();

}  // namespace nativetoolkit::runtime
