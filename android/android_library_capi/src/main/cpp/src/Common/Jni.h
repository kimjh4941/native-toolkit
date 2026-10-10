// The JNI conventions of the C ABI (C ABI design part 1, 5.6): one JavaVM per process, a JNIEnv for
// any thread (attaching it and detaching it when the thread ends), an exception check after every
// call that can throw, and a local frame around every entry.
#pragma once

#include <jni.h>

namespace nativetoolkit::jni {

// Keeps the process's JavaVM. The first one stays; there is only one VM in an Android process.
void SetVm(JavaVM* vm);

// The kept JavaVM, or nullptr before JNI_OnLoad or ntk_android_init has seen one.
JavaVM* Vm();

// The JNIEnv of the calling thread. A thread the VM does not know is attached and stays attached
// until it ends; only threads attached here are detached (design 5.6). nullptr when there is no
// VM or the attach fails.
JNIEnv* Env();

// What a pending Java exception says about the failure.
enum class Failure {
    kNone,           // no exception was pending
    kClassNotFound,  // a class or member is missing: the AAR is not there or R8 renamed it
    kOutOfMemory,    // java.lang.OutOfMemoryError
    kOther,          // anything else
};

// Clears a pending exception and logs its class with where; never leaves one pending
// (design 5.6). Returns what it was.
Failure TakeException(JNIEnv* env, const char* where);

// Pushes a local frame for the entry and pops it on the way out, so that a thread that never
// returns to Java does not pile up local references (design 5.6).
class LocalFrame {
public:
    LocalFrame(JNIEnv* env, jint capacity);
    ~LocalFrame();
    LocalFrame(const LocalFrame&) = delete;
    LocalFrame& operator=(const LocalFrame&) = delete;

    // Whether the frame was pushed. When it was not, an entry that makes local references returns
    // OUT_OF_MEMORY (review K-C8); a frame around calls with primitive arguments only needs no check.
    bool ok() const { return pushed_; }

private:
    JNIEnv* env_;
    bool pushed_;
};

}  // namespace nativetoolkit::jni
