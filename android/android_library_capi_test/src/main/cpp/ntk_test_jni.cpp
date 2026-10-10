// The JNI helpers of the C ABI tests and the GoogleTest runner (C ABI design part 1, chapter 6,
// AC-14). Each GoogleTest case is one JUnit case: NtkGoogleTest lists the cases and runs one.
#include <android/log.h>
#include <gtest/gtest.h>
#include <jni.h>
#include <ctime>
#include <unistd.h>

#include <atomic>
#include <string>
#include <vector>

#include <NativeToolkitC/Android.h>
#include <NativeToolkitC/Clipboard.h>
#include <NativeToolkitC/Dialog.h>
#include <NativeToolkitC/Notification.h>
#include <NativeToolkitC/Share.h>

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

// Every operation of Clipboard, Dialog, notifications and Share before initialization (noStartup; part 2,
// 12.1 未初期化): the names of those that did not return NOT_INITIALIZED, then of the asynchronous
// ones whose release did not run once on the calling thread. Empty when all is as designed.
namespace {
void IgnoreDialog(void*, uint64_t, ntk_dialog_error, uint32_t, ntk_dialog_result*) {}
void IgnoreSettings(void*, ntk_notification_error, uint32_t, ntk_notification_settings_result) {}
void IgnorePermission(void*, uint64_t, ntk_notification_error, uint32_t, ntk_notification_permission_result) {}
void IgnoreChange(void*) {}
void IgnoreInteraction(void*, ntk_notification_interaction*) {}
void IgnoreShown(void*, ntk_notification_shown*) {}
void IgnoreShare(void*, ntk_share_error, uint32_t) {}
void IgnoreChooserAction(void*, ntk_string*) {}
void IgnoreSelection(void*, uint64_t, ntk_string*) {}

struct ReleaseSlot {
    std::atomic<int> count{0};
    std::atomic<pid_t> thread{0};
};

void CountRelease(void* user_data) {
    auto* slot = static_cast<ReleaseSlot*>(user_data);
    slot->count.fetch_add(1);
    slot->thread.store(gettid());
}
}  // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_operationsUninitialized(JNIEnv* env, jclass) {
    std::string failed;
    auto expect = [&failed](const char* name, int32_t error, int32_t not_initialized) {
        if (error != not_initialized) failed += std::string(name) + "=" + std::to_string(error) + " ";
    };
    auto clipboard = [&expect](const char* name, int32_t error) {
        expect(name, error, NTK_CLIPBOARD_ERROR_NOT_INITIALIZED);
    };
    auto dialog = [&expect](const char* name, int32_t error) { expect(name, error, NTK_DIALOG_ERROR_NOT_INITIALIZED); };
    auto notification = [&expect](const char* name, int32_t error) {
        expect(name, error, NTK_NOTIFICATION_ERROR_NOT_INITIALIZED);
    };
    // One counter per asynchronous call, so that each is checked to release exactly once (review v3,
    // S-X3). Never freed: see Leaked in TestSupport.h.
    std::vector<ReleaseSlot*> slots;
    auto slot = [&slots] {
        slots.push_back(new ReleaseSlot);
        return slots.back();
    };
    const char* texts[] = {"a", "b"};

    // Clipboard (OP-01 to OP-11).
    clipboard("copy_text", ntk_clipboard_copy_text("x", nullptr));
    clipboard("copy_html", ntk_clipboard_copy_html("<b>x</b>", nullptr, nullptr));
    clipboard("copy_uri", ntk_clipboard_copy_uri("content://x/1", nullptr));
    clipboard("copy_texts", ntk_clipboard_copy_texts(texts, 2, nullptr));
    clipboard("clear", ntk_clipboard_clear());
    ntk_clipboard_content* content = nullptr;
    clipboard("read", ntk_clipboard_read(&content));
    int32_t value = 0;
    clipboard("has_clip", ntk_clipboard_has_clip(&value));
    ntk_clipboard_description* description = nullptr;
    clipboard("get_description", ntk_clipboard_get_description(&description));
    clipboard("start_observing", ntk_clipboard_start_observing());
    clipboard("stop_observing", ntk_clipboard_stop_observing());
    ntk_clipboard_listener* clipboard_listener = nullptr;
    clipboard("add_change_listener",
              ntk_clipboard_add_change_listener(IgnoreChange, slot(), CountRelease, &clipboard_listener));

    // Dialog (OP-13 to OP-18).
    ntk_dialog_alert_request alert{};
    alert.struct_size = sizeof(alert);
    dialog("show_alert_async", ntk_dialog_show_alert_async(&alert, IgnoreDialog, slot(), CountRelease, nullptr));
    ntk_dialog_confirm_request confirm{};
    confirm.struct_size = sizeof(confirm);
    dialog("show_confirm_async",
           ntk_dialog_show_confirm_async(&confirm, IgnoreDialog, slot(), CountRelease, nullptr));
    ntk_dialog_single_choice_request single{};
    single.struct_size = sizeof(single);
    single.items = texts;
    single.item_count = 2;
    single.checked_index = -1;
    dialog("show_single_choice_async",
           ntk_dialog_show_single_choice_async(&single, IgnoreDialog, slot(), CountRelease, nullptr));
    ntk_dialog_multi_choice_request multi{};
    multi.struct_size = sizeof(multi);
    multi.items = texts;
    multi.item_count = 2;
    dialog("show_multi_choice_async",
           ntk_dialog_show_multi_choice_async(&multi, IgnoreDialog, slot(), CountRelease, nullptr));
    ntk_dialog_text_input_request text_input{};
    text_input.struct_size = sizeof(text_input);
    dialog("show_text_input_async",
           ntk_dialog_show_text_input_async(&text_input, IgnoreDialog, slot(), CountRelease, nullptr));
    ntk_dialog_login_request login{};
    login.struct_size = sizeof(login);
    dialog("show_login_async", ntk_dialog_show_login_async(&login, IgnoreDialog, slot(), CountRelease, nullptr));

    // Notifications (OP-20 to OP-41).
    ntk_notification_content* note = nullptr;
    ntk_notification_content_create(1, "t", "m", &note);
    ntk_notification_content_set_progress(note, 10, 1, 0);
    ntk_notification_channel* channel = nullptr;
    ntk_notification_channel_create("ch", "Channel", 3, &channel);
    notification("show", ntk_notification_show(note));
    notification("update", ntk_notification_update(note));
    notification("remove", ntk_notification_remove(1, nullptr));
    notification("remove_all", ntk_notification_remove_all());
    notification("create_channel", ntk_notification_create_channel(channel));
    notification("delete_channel", ntk_notification_delete_channel("ch"));
    ntk_notification_schedule_options schedule{};
    schedule.struct_size = sizeof(schedule);
    schedule.trigger_at_millis = 4102444800000;  // 2100-01-01
    notification("schedule", ntk_notification_schedule(note, &schedule));
    notification("cancel_scheduled", ntk_notification_cancel_scheduled(1, nullptr));
    notification("cancel_all_scheduled", ntk_notification_cancel_all_scheduled());
    notification("start_progress", ntk_notification_start_progress(note));
    notification("update_progress", ntk_notification_update_progress(note));
    notification("complete_progress", ntk_notification_complete_progress(note));
    notification("stop_progress", ntk_notification_stop_progress());
    notification("has_permission", ntk_notification_has_permission(&value));
    notification("are_enabled", ntk_notification_are_enabled(&value));
    notification("is_scheduled", ntk_notification_is_scheduled(1, nullptr, &value));
    notification("can_schedule_exact_alarms", ntk_notification_can_schedule_exact_alarms(&value));
    notification("open_settings_async",
                 ntk_notification_open_settings_async(0, IgnoreSettings, slot(), CountRelease));
    notification("request_permission",
                 ntk_notification_request_permission(IgnorePermission, slot(), CountRelease, nullptr));
    ntk_notification_listener* listener = nullptr;
    notification("add_interaction_listener",
                 ntk_notification_add_interaction_listener(IgnoreInteraction, slot(), CountRelease, &listener));
    notification("add_shown_listener",
                 ntk_notification_add_shown_listener(IgnoreShown, slot(), CountRelease, &listener));
    ntk_notification_channel_free(channel);
    ntk_notification_content_free(note);

    // Share (OP-43 to OP-53).
    auto share = [&expect](const char* name, int32_t error) { expect(name, error, NTK_SHARE_ERROR_NOT_INITIALIZED); };
    ntk_share_text_content text{};
    text.struct_size = sizeof(text);
    text.text = "x";
    share("share_text", ntk_share_text(&text, nullptr, 0, IgnoreShare, slot(), CountRelease));
    share("share_image", ntk_share_image("/a.png", nullptr, IgnoreShare, slot(), CountRelease));
    share("share_images", ntk_share_images(texts, 2, IgnoreShare, slot(), CountRelease));
    share("share_file", ntk_share_file("/a", IgnoreShare, slot(), CountRelease));
    share("share_files", ntk_share_files(texts, 2, IgnoreShare, slot(), CountRelease));
    const uint8_t icon[] = {1};
    ntk_share_direct_target target{};
    target.struct_size = sizeof(target);
    target.id = "t";
    target.label = "T";
    target.icon = icon;
    target.icon_size = 1;
    share("register_direct_target", ntk_share_register_direct_target(&target));
    share("remove_direct_targets", ntk_share_remove_direct_targets(texts, 2));
    share("share_text_for_selection",
          ntk_share_text_for_selection(&text, IgnoreShare, slot(), CountRelease, nullptr));
    ntk_share_listener* share_listener = nullptr;
    share("add_chooser_action_listener", ntk_share_add_chooser_action_listener(IgnoreChooserAction, slot(),
                                                                               CountRelease,
                                                                               &share_listener));
    share("add_selection_listener",
          ntk_share_add_selection_listener(IgnoreSelection, slot(), CountRelease, &share_listener));
    // The cancels find no request (none can exist yet), so they do nothing and return NONE (6.2,
    // 6.3); the removals do nothing.
    expect("dialog_cancel", ntk_dialog_cancel(1), NTK_DIALOG_ERROR_NONE);
    expect("cancel_permission_request", ntk_notification_cancel_permission_request(1), NTK_NOTIFICATION_ERROR_NONE);
    expect("share_cancel_selection", ntk_share_cancel_selection(1), NTK_SHARE_ERROR_NONE);
    ntk_share_listener_remove(nullptr);
    ntk_notification_listener_remove(nullptr);
    ntk_clipboard_listener_remove(nullptr);

    // The arguments are checked before the initialization (part 2, chapter 11; review v2, R-C2):
    // what the entry finds wrong comes first, also the entry values of AP-19.
    expect("copy_text invalid UTF-8", ntk_clipboard_copy_text("\xFF", nullptr), NTK_CLIPBOARD_ERROR_INVALID_PARAMETER);
    expect("copy_texts none", ntk_clipboard_copy_texts(texts, 0, nullptr), NTK_CLIPBOARD_ERROR_EMPTY_ITEMS);
    expect("remove invalid tag", ntk_notification_remove(1, "\xFF"), NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);
    expect("delete_channel invalid id", ntk_notification_delete_channel("\xFF"),
           NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);
    expect("is_scheduled no output", ntk_notification_is_scheduled(1, nullptr, nullptr),
           NTK_NOTIFICATION_ERROR_INVALID_PARAMETER);
    ntk_dialog_alert_request small{};  // struct_size 0
    expect("show_alert_async small struct",
           ntk_dialog_show_alert_async(&small, IgnoreDialog, slot(), CountRelease, nullptr),
           NTK_DIALOG_ERROR_INVALID_PARAMETER);
    expect("share_files none", ntk_share_files(texts, 0, IgnoreShare, slot(), CountRelease),
           NTK_SHARE_ERROR_EMPTY_FILE_LIST);

    // 1 + 6 + 4 + 8 asynchronous calls, and 2 rejected for their arguments, each released at once
    // on this thread (part 1, 1.3).
    if (slots.size() != 21) failed += "calls=" + std::to_string(slots.size()) + " ";
    for (size_t i = 0; i < slots.size(); ++i) {
        if (slots[i]->count.load() != 1) failed += "release#" + std::to_string(i) + "=" + std::to_string(slots[i]->count.load()) + " ";
        if (slots[i]->thread.load() != gettid()) failed += "release#" + std::to_string(i) + "-off-thread ";
    }
    return env->NewStringUTF(failed.c_str());
}

// The Kotlin side reports that it is done after the class table is built but before the native
// side is marked done (part 1, chapter 6: the races in a set order; 5.3): the hook calls
// NtkRuntime.onKotlinReady there. noStartup only, before System.loadLibrary("ntk").
namespace {
void KotlinReportsFirst() {
    JNIEnv* env = ntktest::Env();
    jclass runtime = env->FindClass("com/jonghyunkim/nativetoolkit/capi/jni/NtkRuntime");
    jmethodID ready = env->GetStaticMethodID(runtime, "onKotlinReady", "()I");
    env->CallStaticIntMethod(runtime, ready);
    env->DeleteLocalRef(runtime);
}
}  // namespace

extern "C" JNIEXPORT void JNICALL
Java_com_jonghyunkim_nativetoolkit_capitest_NtkTestNative_kotlinReportsFirst(JNIEnv*, jclass, jboolean on) {
    ntk_debug_runtime_before_native_done(on == JNI_TRUE ? KotlinReportsFirst : nullptr);
}
