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

namespace {

jclass UiDriverClass(JNIEnv* env) {
    static jclass driver = nullptr;
    if (driver == nullptr) {
        jclass local = env->FindClass("com/jonghyunkim/nativetoolkit/capitest/UiDriver");
        driver = static_cast<jclass>(env->NewGlobalRef(local));
        env->DeleteLocalRef(local);
    }
    return driver;
}

bool CallWithText(const char* method, const char* text) {
    JNIEnv* env = Env();
    jclass driver = UiDriverClass(env);
    jmethodID id = env->GetStaticMethodID(driver, method, "(Ljava/lang/String;)Z");
    jstring value = env->NewStringUTF(text);
    bool result = env->CallStaticBooleanMethod(driver, id, value) == JNI_TRUE;
    env->DeleteLocalRef(value);
    return result;
}

bool CallBoolean(const char* method) {
    JNIEnv* env = Env();
    jclass driver = UiDriverClass(env);
    return env->CallStaticBooleanMethod(driver, env->GetStaticMethodID(driver, method, "()Z")) == JNI_TRUE;
}

}  // namespace

bool UiWaitText(const char* text) { return CallWithText("waitText", text); }
bool UiGone(const char* text) { return CallWithText("gone", text); }
bool UiClick(const char* text) { return CallWithText("click", text); }
bool UiHome() { return CallBoolean("home"); }
bool UiOpenShade(const char* text) { return CallWithText("openShade", text); }
bool UiSwipeAway(const char* text) { return CallWithText("swipeAway", text); }

void UiCloseShade() {
    JNIEnv* env = Env();
    jclass driver = UiDriverClass(env);
    env->CallStaticVoidMethod(driver, env->GetStaticMethodID(driver, "closeShade", "()V"));
}

std::string UiForegroundActivity() {
    JNIEnv* env = Env();
    jclass driver = UiDriverClass(env);
    auto name = static_cast<jstring>(
        env->CallStaticObjectMethod(driver, env->GetStaticMethodID(driver, "foregroundActivity", "()Ljava/lang/String;")));
    const char* chars = env->GetStringUTFChars(name, nullptr);
    std::string result(chars);
    env->ReleaseStringUTFChars(name, chars);
    env->DeleteLocalRef(name);
    return result;
}
bool UiFinishForeground() { return CallBoolean("finishForeground"); }

int32_t ActivitiesCreated() {
    JNIEnv* env = Env();
    jclass driver = UiDriverClass(env);
    return env->CallStaticIntMethod(driver, env->GetStaticMethodID(driver, "activitiesCreated", "()I"));
}

bool UiStaysAway(const char* text, int64_t ms) {
    JNIEnv* env = Env();
    jclass driver = UiDriverClass(env);
    jmethodID id = env->GetStaticMethodID(driver, "staysAway", "(Ljava/lang/String;J)Z");
    jstring value = env->NewStringUTF(text);
    bool result = env->CallStaticBooleanMethod(driver, id, value, static_cast<jlong>(ms)) == JNI_TRUE;
    env->DeleteLocalRef(value);
    return result;
}

bool UiType(int32_t index, const char* text) {
    JNIEnv* env = Env();
    jclass driver = UiDriverClass(env);
    jmethodID id = env->GetStaticMethodID(driver, "type", "(ILjava/lang/String;)Z");
    jstring value = env->NewStringUTF(text);
    bool result = env->CallStaticBooleanMethod(driver, id, static_cast<jint>(index), value) == JNI_TRUE;
    env->DeleteLocalRef(value);
    return result;
}

void UiBack() {
    JNIEnv* env = Env();
    jclass driver = UiDriverClass(env);
    env->CallStaticVoidMethod(driver, env->GetStaticMethodID(driver, "back", "()V"));
}

namespace {

jclass InspectorClass(JNIEnv* env) {
    static jclass inspector = nullptr;
    if (inspector == nullptr) {
        jclass local = env->FindClass("com/jonghyunkim/nativetoolkit/capitest/NotificationInspector");
        inspector = static_cast<jclass>(env->NewGlobalRef(local));
        env->DeleteLocalRef(local);
    }
    return inspector;
}

jstring Java(JNIEnv* env, const char* text) { return text == nullptr ? nullptr : env->NewStringUTF(text); }

std::string Native(JNIEnv* env, jstring value) {
    if (value == nullptr) return "<null>";
    const char* chars = env->GetStringUTFChars(value, nullptr);
    std::string result = chars;
    env->ReleaseStringUTFChars(value, chars);
    env->DeleteLocalRef(value);
    return result;
}

}  // namespace

void GrantNotifications() {
    JNIEnv* env = Env();
    jclass inspector = InspectorClass(env);
    env->CallStaticVoidMethod(inspector, env->GetStaticMethodID(inspector, "grantNotifications", "()V"));
}

void AllowExactAlarms() {
    JNIEnv* env = Env();
    jclass inspector = InspectorClass(env);
    env->CallStaticVoidMethod(inspector, env->GetStaticMethodID(inspector, "allowExactAlarms", "()V"));
}

bool WaitShown(int32_t id, const char* tag, int64_t ms) {
    JNIEnv* env = Env();
    jclass inspector = InspectorClass(env);
    jmethodID method = env->GetStaticMethodID(inspector, "waitShown", "(ILjava/lang/String;J)Z");
    return env->CallStaticBooleanMethod(inspector, method, id, Java(env, tag), static_cast<jlong>(ms)) == JNI_TRUE;
}

bool FireIntent(int32_t id, const char* tag, const char* which) {
    JNIEnv* env = Env();
    jclass inspector = InspectorClass(env);
    jmethodID method = env->GetStaticMethodID(inspector, "fire", "(ILjava/lang/String;Ljava/lang/String;)Z");
    return env->CallStaticBooleanMethod(inspector, method, id, Java(env, tag), Java(env, which)) == JNI_TRUE;
}

bool WaitGone(int32_t id, const char* tag, int64_t ms) {
    JNIEnv* env = Env();
    jclass inspector = InspectorClass(env);
    jmethodID method = env->GetStaticMethodID(inspector, "waitGone", "(ILjava/lang/String;J)Z");
    return env->CallStaticBooleanMethod(inspector, method, id, Java(env, tag), static_cast<jlong>(ms)) == JNI_TRUE;
}

std::string NotificationField(int32_t id, const char* tag, const char* name) {
    JNIEnv* env = Env();
    jclass inspector = InspectorClass(env);
    jmethodID method =
        env->GetStaticMethodID(inspector, "field", "(ILjava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    return Native(env, static_cast<jstring>(env->CallStaticObjectMethod(inspector, method, id, Java(env, tag),
                                                                        Java(env, name))));
}

std::string ChannelField(const char* channel_id, const char* name) {
    JNIEnv* env = Env();
    jclass inspector = InspectorClass(env);
    jmethodID method =
        env->GetStaticMethodID(inspector, "channelField", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    return Native(env, static_cast<jstring>(env->CallStaticObjectMethod(inspector, method, Java(env, channel_id),
                                                                        Java(env, name))));
}

std::string ResourceId(const char* name, const char* type) {
    JNIEnv* env = Env();
    jclass inspector = InspectorClass(env);
    jmethodID method =
        env->GetStaticMethodID(inspector, "resourceId", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    return Native(env, static_cast<jstring>(env->CallStaticObjectMethod(inspector, method, Java(env, name),
                                                                        Java(env, type))));
}

void SetClipboardText(const std::u16string& text) {
    JNIEnv* env = Env();
    jclass control = env->FindClass("com/jonghyunkim/nativetoolkit/capitest/ClipboardControl");
    jmethodID method = env->GetStaticMethodID(control, "setText", "(Ljava/lang/String;)V");
    jstring value = env->NewString(reinterpret_cast<const jchar*>(text.data()), static_cast<jsize>(text.size()));
    env->CallStaticVoidMethod(control, method, value);
    env->DeleteLocalRef(value);
    env->DeleteLocalRef(control);
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
