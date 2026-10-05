#include "TestSupport.h"

#include <unistd.h>

namespace ntktest {
namespace {

JavaVM* g_vm = nullptr;

jclass MainControl(JNIEnv* env) {
    static jclass control = nullptr;
    if (control == nullptr) {
        jclass local = env->FindClass("com/jonghyunkim/nativetoolkit/capitest/MainControl");
        control = static_cast<jclass>(env->NewGlobalRef(local));
        env->DeleteLocalRef(local);
    }
    return control;
}

void CallVoid(const char* name) {
    JNIEnv* env = Env();
    jclass control = MainControl(env);
    jmethodID method = env->GetStaticMethodID(control, name, "()V");
    env->CallStaticVoidMethod(control, method);
}

}  // namespace

void SetVm(JavaVM* vm) { g_vm = vm; }

JNIEnv* Env() {
    JNIEnv* env = nullptr;
    if (g_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        g_vm->AttachCurrentThread(&env, nullptr);
    }
    return env;
}

bool OnMain() { return gettid() == getpid(); }

void RunOnMain(std::function<void()> task) {
    JNIEnv* env = Env();
    jclass control = MainControl(env);
    jmethodID method = env->GetStaticMethodID(control, "runOnMain", "(J)V");
    auto* boxed = new std::function<void()>(std::move(task));
    env->CallStaticVoidMethod(control, method, reinterpret_cast<jlong>(boxed));
}

void DrainMain() { CallVoid("drain"); }
void HoldMain() { CallVoid("hold"); }
void UnholdMain() { CallVoid("unhold"); }

int LedgerSize() {
    JNIEnv* env = Env();
    jclass control = MainControl(env);
    jmethodID method = env->GetStaticMethodID(control, "ledgerSize", "()I");
    return env->CallStaticIntMethod(control, method);
}

void Recorder::Add(Record record) {
    record.on_main = OnMain();
    record.thread = gettid();
    {
        std::lock_guard<std::mutex> lock(mutex_);
        records_.push_back(std::move(record));
    }
    changed_.notify_all();
}

std::vector<Record> Recorder::Records() {
    std::lock_guard<std::mutex> lock(mutex_);
    return records_;
}

size_t Recorder::Count(const std::string& what) {
    std::lock_guard<std::mutex> lock(mutex_);
    size_t count = 0;
    for (const Record& record : records_) count += record.what == what ? 1 : 0;
    return count;
}

bool Recorder::WaitFor(const std::string& what, size_t count, std::chrono::milliseconds timeout) {
    std::unique_lock<std::mutex> lock(mutex_);
    return changed_.wait_for(lock, timeout, [&] {
        size_t seen = 0;
        for (const Record& record : records_) seen += record.what == what ? 1 : 0;
        return seen >= count;
    });
}

void Recorder::Done(void* user_data, int32_t error, int64_t value) {
    static_cast<Recorder*>(user_data)->Add({"done", error, value});
}

void Recorder::Event(void* user_data, int64_t value) {
    static_cast<Recorder*>(user_data)->Add({"event", 0, value});
}

void Recorder::Release(void* user_data) {
    static_cast<Recorder*>(user_data)->Add({"release"});
}

}  // namespace ntktest

// MainControl.nativeRun: runs a task RunOnMain boxed.
extern "C" JNIEXPORT void JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_MainControl_nativeRun(JNIEnv*, jclass, jlong task) {
    auto* boxed = reinterpret_cast<std::function<void()>*>(task);
    (*boxed)();
    delete boxed;
}
