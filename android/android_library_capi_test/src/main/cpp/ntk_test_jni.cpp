// The JNI helpers of the C ABI tests and the GoogleTest runner (C ABI design part 1, chapter 6,
// AC-14). Each GoogleTest case is one JUnit case: NtkGoogleTest lists the cases and runs one.
#include <android/log.h>
#include <gtest/gtest.h>
#include <jni.h>
#include <ctime>
#include <unistd.h>

#include <string>
#include <vector>

#include <NativeToolkitC/Android.h>
#include <NativeToolkitC/Clipboard.h>
#include <NativeToolkitC/Dialog.h>
#include <NativeToolkitC/Notification.h>

#include "TestSupport.h"
#include "ntk_debug_probe.h"

#define TEST_LOG(...) __android_log_print(ANDROID_LOG_INFO, "ntk_test", __VA_ARGS__)

namespace {

// Sends each failure to logcat, since stdout is not visible.
class LogcatListener : public testing::EmptyTestEventListener {
    void OnTestPartResult(const testing::TestPartResult& result) override {
        if (result.failed()) {
            __android_log_print(ANDROID_LOG_ERROR, "ntk_test", "%s:%d %s", result.file_name(),
                                result.line_number(), result.summary());
        }
    }
};

void InitGoogleTestOnce(const std::string& filter) {
    static bool initialized = false;
    if (!initialized) {
        int argc = 1;
        char arg0[] = "ntk_test";
        char* argv[] = {arg0, nullptr};
        testing::InitGoogleTest(&argc, argv);
        testing::UnitTest::GetInstance()->listeners().Append(new LogcatListener);
        initialized = true;
    }
    GTEST_FLAG_SET(filter, filter);
}

}  // namespace

// libntk_test.so has a JNI_OnLoad of its own. Without one, ART would find libntk.so's through
// the dependency and run it (stage 1a 3.2); with it, loading this library leaves libntk.so opened
// by the linker only, as an app that opens it with dlopen does (design part 1, 1.4).
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* /*reserved*/) {
    TEST_LOG("[JNI_OnLoad] libntk_test.so");
    ntktest::SetVm(vm);
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_init(JNIEnv* env, jclass, jobject context) {
    return ntk_android_init(env, context);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_initWithoutEnv(JNIEnv*, jclass, jobject context) {
    return ntk_android_init(nullptr, context);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_isInitialized(JNIEnv*, jclass) {
    return ntk_android_is_initialized();
}

extern "C" JNIEXPORT jobjectArray JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_listCases(JNIEnv* env, jclass) {
    InitGoogleTestOnce("*");
    std::vector<std::string> names;
    testing::UnitTest* unit = testing::UnitTest::GetInstance();
    for (int i = 0; i < unit->total_test_suite_count(); ++i) {
        const testing::TestSuite* suite = unit->GetTestSuite(i);
        for (int j = 0; j < suite->total_test_count(); ++j) {
            names.push_back(std::string(suite->name()) + "." + suite->GetTestInfo(j)->name());
        }
    }
    jclass string_class = env->FindClass("java/lang/String");
    jobjectArray result = env->NewObjectArray(static_cast<jsize>(names.size()), string_class, nullptr);
    for (size_t i = 0; i < names.size(); ++i) {
        jstring name = env->NewStringUTF(names[i].c_str());
        env->SetObjectArrayElement(result, static_cast<jsize>(i), name);
        env->DeleteLocalRef(name);
    }
    return result;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_runCase(JNIEnv* env, jclass, jstring name) {
    const char* chars = env->GetStringUTFChars(name, nullptr);
    std::string filter = chars;
    env->ReleaseStringUTFChars(name, chars);
    InitGoogleTestOnce(filter);
    int failed = RUN_ALL_TESTS();
    const testing::UnitTest* unit = testing::UnitTest::GetInstance();
    TEST_LOG("[runCase] %s ran %d, failed %d", filter.c_str(), unit->test_to_run_count(), failed);
    return unit->test_to_run_count() == 1 && failed == 0 ? JNI_TRUE : JNI_FALSE;
}

// For the uninitialized case of the probe (noStartup): the error, and whether release ran on the
// calling thread before the call returned (design part 1, 1.3, 1.4).
extern "C" JNIEXPORT jintArray JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_probeStartRejected(JNIEnv* env, jclass) {
    ntktest::Recorder recorder;
    uint64_t id = 99;
    int32_t error = ntk_debug_probe_start(ntktest::Recorder::Done, &recorder, ntktest::Recorder::Release, &id);
    std::vector<ntktest::Record> records = recorder.Records();
    bool released_here = records.size() == 1 && records[0].what == "release" && records[0].thread == gettid();
    jint values[] = {error, released_here ? 1 : 0, static_cast<jint>(id)};
    jintArray result = env->NewIntArray(3);
    env->SetIntArrayRegion(result, 0, 3, values);
    return result;
}

// Clipboard operations before initialization (noStartup; design part 1, chapter 6 and part 2,
// 12.1 未初期化): [copy_text, read, read's output cleared, add_change_listener, released on this
// thread before it returned, its output cleared, the readers and frees of NULL ran].
extern "C" JNIEXPORT jintArray JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_clipboardUninitialized(JNIEnv* env, jclass) {
    int32_t copy = ntk_clipboard_copy_text("x", nullptr);
    auto* content = reinterpret_cast<ntk_clipboard_content*>(0x1);
    int32_t read = ntk_clipboard_read(&content);
    ntktest::Recorder recorder;
    auto* listener = reinterpret_cast<ntk_clipboard_listener*>(0x1);
    int32_t add = ntk_clipboard_add_change_listener(
        [](void*) {}, &recorder, ntktest::Recorder::Release, &listener);
    std::vector<ntktest::Record> records = recorder.Records();
    bool released_here = records.size() == 1 && records[0].what == "release" && records[0].thread == gettid();
    size_t size = 99;
    bool readers = ntk_clipboard_content_item_count(nullptr) == 0 &&
                   ntk_clipboard_content_label(nullptr, &size) == nullptr && size == 0;
    ntk_clipboard_content_free(nullptr);
    ntk_clipboard_listener_remove(nullptr);
    jint values[] = {copy, read, content == nullptr ? 1 : 0, add, released_here ? 1 : 0, listener == nullptr ? 1 : 0,
                     readers ? 1 : 0};
    jintArray result = env->NewIntArray(7);
    env->SetIntArrayRegion(result, 0, 7, values);
    return result;
}

// An alert for the Kotlin tests of the manual paths (noStartup): shown with ntk_dialog_show_alert_async,
// its completion recorded until awaitAlert reads it.
namespace {
ntktest::Recorder* AlertRecorder() {
    static auto* recorder = new ntktest::Recorder;
    return recorder;
}
void OnAlert(void* user_data, uint64_t, ntk_dialog_error error, uint32_t, ntk_dialog_result* result) {
    ntk_dialog_result_free(result);
    static_cast<ntktest::Recorder*>(user_data)->Add({"done", error});
}
}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_showAlert(JNIEnv* env, jclass, jstring message) {
    const char* chars = env->GetStringUTFChars(message, nullptr);
    ntk_dialog_alert_request request{};
    request.struct_size = sizeof(request);
    request.message = chars;
    int32_t error = ntk_dialog_show_alert_async(&request, OnAlert, AlertRecorder(), ntktest::Recorder::Release, nullptr);
    env->ReleaseStringUTFChars(message, chars);
    return error;
}

// [the completion's error, 1 when the release followed it], or [-1, 0] on a timeout.
extern "C" JNIEXPORT jintArray JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_awaitAlert(JNIEnv* env, jclass) {
    ntktest::Recorder* recorder = AlertRecorder();
    jint values[] = {-1, 0};
    if (recorder->WaitFor("release", 1, std::chrono::seconds(10))) {
        std::vector<ntktest::Record> records = recorder->Records();
        if (!records.empty() && records[0].what == "done") values[0] = records[0].error;
        values[1] = records.size() == 2 && records[1].what == "release" ? 1 : 0;
    }
    jintArray result = env->NewIntArray(2);
    env->SetIntArrayRegion(result, 0, 2, values);
    return result;
}

// The builders before initialization (noStartup; part 2, 6.3: usable before initialization):
// the errors of create, a setter and the channel create, all expected to be NONE.
extern "C" JNIEXPORT jintArray JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_buildersUninitialized(JNIEnv* env, jclass) {
    ntk_notification_content* content = nullptr;
    ntk_notification_channel* channel = nullptr;
    jint values[] = {ntk_notification_content_create(1, "t", "m", &content),
                     ntk_notification_content_set_priority(content, 1),
                     ntk_notification_channel_create("id", "Name", 3, &channel),
                     ntk_notification_content_set_channel(content, channel)};
    ntk_notification_channel_free(channel);
    ntk_notification_content_free(content);
    jintArray result = env->NewIntArray(4);
    env->SetIntArrayRegion(result, 0, 4, values);
    return result;
}

// Notifications without the permission (noStartup, a fresh install that never grants it; part 2,
// AP-16): [has_permission, are_enabled, show, a past schedule, a future inexact schedule,
// can_schedule_exact_alarms, a future exact schedule].
extern "C" JNIEXPORT jintArray JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_notificationsWithoutPermission(JNIEnv* env, jclass) {
    timespec now{};
    clock_gettime(CLOCK_REALTIME, &now);
    int64_t now_ms = static_cast<int64_t>(now.tv_sec) * 1000 + now.tv_nsec / 1000000;
    ntk_notification_content* content = nullptr;
    ntk_notification_content_create(301, "Denied", "m", &content);
    int32_t has = -1;
    int32_t enabled = -1;
    int32_t exact = -1;
    ntk_notification_has_permission(&has);
    ntk_notification_are_enabled(&enabled);
    int32_t show = ntk_notification_show(content);
    ntk_notification_schedule_options schedule{};
    schedule.struct_size = sizeof(schedule);
    schedule.trigger_at_millis = now_ms - 1000;
    int32_t past = ntk_notification_schedule(content, &schedule);
    schedule.trigger_at_millis = now_ms + 600000;
    schedule.inexact = 1;
    int32_t future_inexact = ntk_notification_schedule(content, &schedule);
    ntk_notification_can_schedule_exact_alarms(&exact);
    schedule.inexact = 0;
    int32_t future_exact = ntk_notification_schedule(content, &schedule);
    ntk_notification_cancel_all_scheduled();
    ntk_notification_content_free(content);
    jint values[] = {has, enabled, show, past, future_inexact, exact, future_exact};
    jintArray result = env->NewIntArray(7);
    env->SetIntArrayRegion(result, 0, 7, values);
    return result;
}

// The permission request for the Kotlin test that presses the system dialog (noNtkInitializer).
namespace {
ntktest::Recorder* PermissionRecorder() {
    static auto* recorder = new ntktest::Recorder;
    return recorder;
}
void OnPermissionResult(void* user_data, uint64_t, ntk_notification_error error, uint32_t,
                        ntk_notification_permission_result result) {
    static_cast<ntktest::Recorder*>(user_data)->Add({"done", error, result});
}
}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_requestPermission(JNIEnv*, jclass) {
    uint64_t id = 0;
    int32_t error = ntk_notification_request_permission(OnPermissionResult, PermissionRecorder(),
                                                        ntktest::Recorder::Release, &id);
    return error == 0 ? static_cast<jlong>(id) : -error;
}

extern "C" JNIEXPORT void JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_cancelPermission(JNIEnv*, jclass, jlong id) {
    ntk_notification_cancel_permission_request(static_cast<uint64_t>(id));
}

// The [error, result] of the count-th completion, once its release has also run; [-1, -1] on a timeout.
extern "C" JNIEXPORT jintArray JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_awaitPermission(JNIEnv* env, jclass, jint count) {
    ntktest::Recorder* recorder = PermissionRecorder();
    jint values[] = {-1, -1};
    if (recorder->WaitFor("release", static_cast<size_t>(count), std::chrono::seconds(10))) {
        int seen = 0;
        for (const auto& record : recorder->Records()) {
            if (record.what == "done" && ++seen == count) {
                values[0] = record.error;
                values[1] = static_cast<jint>(record.value);
            }
        }
    }
    jintArray result = env->NewIntArray(2);
    env->SetIntArrayRegion(result, 0, 2, values);
    return result;
}
