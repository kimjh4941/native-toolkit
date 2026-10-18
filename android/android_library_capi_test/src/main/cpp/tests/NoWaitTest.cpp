// No public function waits for the main thread (C ABI design part 1, 1.3 and chapter 6 "main を
// 待たない"): with the main thread held, every function of 8.2 is called from another thread and
// has to return. A function that waited would never return while the main thread is held, so the
// deadline catches it. Then the main thread runs what was posted, and the case cleans up.
#include <gtest/gtest.h>

#include <jni.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <NativeToolkitC/Android.h>
#include <NativeToolkitC/Clipboard.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>
#include <NativeToolkitC/Notification.h>
#include <NativeToolkitC/Share.h>

#include "../TestSupport.h"

namespace {

void IgnoreDialog(void*, uint64_t, ntk_dialog_error, uint32_t, ntk_dialog_result* result) {
    ntk_dialog_result_free(result);
}
void IgnoreSettings(void*, ntk_notification_error, uint32_t, ntk_notification_settings_result) {}
void IgnorePermission(void*, uint64_t, ntk_notification_error, uint32_t, ntk_notification_permission_result) {}
void IgnoreChange(void*) {}
void IgnoreInteraction(void*, ntk_notification_interaction* event) { ntk_notification_interaction_free(event); }
void IgnoreShown(void*, ntk_notification_shown* event) { ntk_notification_shown_free(event); }
void IgnoreShare(void*, ntk_share_error, uint32_t) {}
void IgnoreChooserAction(void*, ntk_string* id) { ntk_string_free(id); }
void IgnoreSelection(void*, uint64_t, ntk_string* name) { ntk_string_free(name); }

// What the calls leave behind, for the cleanup once the main thread runs again.
struct Leftovers {
    std::vector<uint64_t> dialogs;
    std::vector<ntk_clipboard_listener*> clipboard_listeners;
    std::vector<ntk_notification_listener*> notification_listeners;
    std::vector<ntk_share_listener*> share_listeners;
};

// Calls every public function once (155: Common 11, Android 2, Clipboard 27, Dialog 17,
// notifications 86, Share 12), with arguments that reach Kotlin where the function does.
void CallEverything(JNIEnv* env, jobject context, const std::string& missing, const std::vector<uint8_t>& png,
                    Leftovers* left) {
    // Common.h (11) and Android.h (2).
    ntk_version();
    ntk_last_system_code();
    ntk_string_data(nullptr);
    ntk_string_size(nullptr);
    ntk_string_free(nullptr);
    ntk_bytes_data(nullptr);
    ntk_bytes_size(nullptr);
    ntk_bytes_free(nullptr);
    ntk_string_list_count(nullptr);
    ntk_string_list_at(nullptr, 0, nullptr);
    ntk_string_list_free(nullptr);
    ntk_android_init(env, context);
    ntk_android_is_initialized();

    // Clipboard.h (27).
    const char* texts[] = {"a", "b"};
    ntk_clipboard_copy_text("no wait", nullptr);
    ntk_clipboard_copy_html("<b>no wait</b>", nullptr, nullptr);
    ntk_clipboard_copy_uri("content://com.jonghyunkim.capitest/nowait", nullptr);
    ntk_clipboard_copy_texts(texts, 2, nullptr);
    ntk_clipboard_content* content = nullptr;
    ntk_clipboard_read(&content);
    int32_t value = 0;
    ntk_clipboard_has_clip(&value);
    ntk_clipboard_description* description = nullptr;
    ntk_clipboard_get_description(&description);
    ntk_clipboard_start_observing();
    ntk_clipboard_stop_observing();
    ntk_clipboard_listener* clipboard_listener = nullptr;
    ntk_clipboard_add_change_listener(IgnoreChange, nullptr, nullptr, &clipboard_listener);
    left->clipboard_listeners.push_back(clipboard_listener);
    ntk_clipboard_content_label(content, nullptr);
    ntk_clipboard_content_mime_type_count(content);
    ntk_clipboard_content_mime_type_at(content, 0, nullptr);
    ntk_clipboard_content_item_count(content);
    ntk_clipboard_content_item_text_at(content, 0, nullptr);
    ntk_clipboard_content_item_html_at(content, 0, nullptr);
    ntk_clipboard_content_item_uri_at(content, 0, nullptr);
    ntk_clipboard_content_item_coerced_text_at(content, 0, nullptr);
    ntk_clipboard_content_free(content);
    ntk_clipboard_description_label(description, nullptr);
    ntk_clipboard_description_mime_type_count(description);
    ntk_clipboard_description_mime_type_at(description, 0, nullptr);
    ntk_clipboard_description_is_styled_text(description);
    ntk_clipboard_description_classification_status(description);
    ntk_clipboard_description_free(description);
    ntk_clipboard_clear();
    ntk_clipboard_listener_remove(nullptr);

    // Dialog.h (17).
    uint64_t id = 0;
    ntk_dialog_alert_request alert{};
    alert.struct_size = sizeof(alert);
    alert.title = "No wait";
    ntk_dialog_show_alert_async(&alert, IgnoreDialog, nullptr, nullptr, &id);
    left->dialogs.push_back(id);
    ntk_dialog_confirm_request confirm{};
    confirm.struct_size = sizeof(confirm);
    ntk_dialog_show_confirm_async(&confirm, IgnoreDialog, nullptr, nullptr, &id);
    left->dialogs.push_back(id);
    ntk_dialog_single_choice_request single{};
    single.struct_size = sizeof(single);
    single.items = texts;
    single.item_count = 2;
    single.checked_index = -1;
    ntk_dialog_show_single_choice_async(&single, IgnoreDialog, nullptr, nullptr, &id);
    left->dialogs.push_back(id);
    ntk_dialog_multi_choice_request multi{};
    multi.struct_size = sizeof(multi);
    multi.items = texts;
    multi.item_count = 2;
    ntk_dialog_show_multi_choice_async(&multi, IgnoreDialog, nullptr, nullptr, &id);
    left->dialogs.push_back(id);
    ntk_dialog_text_input_request text_input{};
    text_input.struct_size = sizeof(text_input);
    ntk_dialog_show_text_input_async(&text_input, IgnoreDialog, nullptr, nullptr, &id);
    left->dialogs.push_back(id);
    ntk_dialog_login_request login{};
    login.struct_size = sizeof(login);
    ntk_dialog_show_login_async(&login, IgnoreDialog, nullptr, nullptr, &id);
    left->dialogs.push_back(id);
    ntk_dialog_cancel(left->dialogs.front());
    ntk_dialog_result_answer(nullptr);
    ntk_dialog_result_button(nullptr);
    ntk_dialog_result_button_text(nullptr, nullptr);
    ntk_dialog_result_checked_index(nullptr);
    ntk_dialog_result_checked_count(nullptr);
    ntk_dialog_result_checked_at(nullptr, 0);
    ntk_dialog_result_text(nullptr, nullptr);
    ntk_dialog_result_username(nullptr, nullptr);
    ntk_dialog_result_password(nullptr, nullptr);
    ntk_dialog_result_free(nullptr);

    // Notification.h: the channel builder (11).
    ntk_notification_channel* channel = nullptr;
    ntk_notification_channel_create("ntk_no_wait", "No wait", 3, &channel);
    ntk_notification_channel_set_description(channel, "d");
    ntk_notification_channel_set_show_badge(channel, 1);
    ntk_notification_channel_set_enable_lights(channel, 0);
    ntk_notification_channel_set_light_color(channel, 0xFF00FF00u);
    ntk_notification_channel_set_enable_vibration(channel, 0);
    const int64_t pattern[] = {0, 100};
    ntk_notification_channel_set_vibration_pattern(channel, pattern, 2);
    ntk_notification_channel_set_sound(channel, nullptr);
    ntk_notification_channel_set_lockscreen_visibility(channel, 0);
    ntk_notification_channel_set_group(channel, nullptr, nullptr);

    // The content builder (40). The styles replace each other; the last one is a plain BigText.
    ntk_notification_content* note = nullptr;
    ntk_notification_content_create(901, "No wait", "Shown from another thread", &note);
    ntk_notification_content_set_tag(note, "no-wait");
    ntk_notification_content_set_channel(note, channel);
    ntk_notification_content_set_small_icon(note, nullptr);
    ntk_notification_content_set_large_icon(note, nullptr);
    ntk_notification_content_set_priority(note, 0);
    ntk_notification_content_set_auto_cancel(note, 1);
    ntk_notification_content_set_ongoing(note, 0);
    ntk_notification_content_set_sub_text(note, "s");
    ntk_notification_content_set_show_timestamp(note, 1);
    ntk_notification_content_set_timestamp(note, 0);
    ntk_notification_content_set_sound(note, nullptr);
    ntk_notification_content_set_category(note, nullptr);
    ntk_notification_content_set_visibility(note, 0);
    ntk_notification_content_set_color(note, 0xFF336699u);
    ntk_notification_content_set_number(note, 1);
    ntk_notification_content_set_ticker(note, "t");
    ntk_notification_content_set_group(note, nullptr);
    ntk_notification_content_set_group_summary(note, 0);
    ntk_notification_content_set_group_alert_behavior(note, 0);
    ntk_notification_content_set_sort_key(note, nullptr);
    ntk_notification_content_set_only_alert_once(note, 0);
    ntk_notification_content_set_local_only(note, 0);
    ntk_notification_content_set_silent(note, 1);
    ntk_notification_content_set_uses_chronometer(note, 0);
    ntk_notification_content_set_timeout_after(note, 60000);
    ntk_notification_content_set_progress(note, 10, 1, 0);
    ntk_notification_content_set_style_inbox(note, texts, 2, nullptr, nullptr);
    ntk_notification_content_set_style_big_picture(note, nullptr, nullptr, nullptr, nullptr, nullptr, 0);
    ntk_notification_content_set_style_messaging(note, "me", nullptr, -1);
    ntk_notification_content_add_message(note, "m", 0, nullptr);
    ntk_notification_content_set_style_custom_view(note, "ntk_test_custom", nullptr);
    ntk_notification_content_add_view_click(note, "ntk_test_button", "click");
    ntk_notification_content_set_style_big_text(note, "big", nullptr, nullptr);
    ntk_notification_content_set_tap(note, NTK_NOTIFICATION_TAP_EVENT_ONLY);
    ntk_notification_content_add_data(note, "k", "v");
    ntk_notification_content_set_dismiss_event(note, 1);
    ntk_notification_content_set_full_screen(note, 0);
    ntk_notification_action action{};
    action.struct_size = sizeof(action);
    action.title = "Act";
    action.action_id = "act";
    ntk_notification_content_add_action(note, &action);

    // The operations and the events (23), then the event readers (12).
    ntk_notification_create_channel(channel);
    ntk_notification_show(note);
    ntk_notification_update(note);
    ntk_notification_remove(901, "no-wait");
    ntk_notification_remove_all();
    ntk_notification_schedule_options schedule{};
    schedule.struct_size = sizeof(schedule);
    schedule.trigger_at_millis = 4102444800000;  // 2100-01-01
    schedule.inexact = 1;
    ntk_notification_schedule(note, &schedule);
    ntk_notification_is_scheduled(901, "no-wait", &value);
    ntk_notification_cancel_scheduled(901, "no-wait");
    ntk_notification_cancel_all_scheduled();
    ntk_notification_start_progress(note);
    ntk_notification_update_progress(note);
    ntk_notification_complete_progress(note);
    ntk_notification_stop_progress();
    ntk_notification_has_permission(&value);
    ntk_notification_are_enabled(&value);
    ntk_notification_can_schedule_exact_alarms(&value);
    ntk_notification_open_settings_async(0, IgnoreSettings, nullptr, nullptr);
    uint64_t permission = 0;
    ntk_notification_request_permission(IgnorePermission, nullptr, nullptr, &permission);
    ntk_notification_cancel_permission_request(permission);
    ntk_notification_listener* listener = nullptr;
    ntk_notification_add_interaction_listener(IgnoreInteraction, nullptr, nullptr, &listener);
    left->notification_listeners.push_back(listener);
    ntk_notification_add_shown_listener(IgnoreShown, nullptr, nullptr, &listener);
    left->notification_listeners.push_back(listener);
    ntk_notification_listener_remove(nullptr);
    ntk_notification_delete_channel("ntk_no_wait");
    ntk_notification_content_free(note);
    ntk_notification_channel_free(channel);
    ntk_notification_interaction_kind(nullptr);
    ntk_notification_interaction_notification_id(nullptr);
    ntk_notification_interaction_tag(nullptr, nullptr);
    ntk_notification_interaction_action_id(nullptr, nullptr);
    ntk_notification_interaction_data_count(nullptr);
    ntk_notification_interaction_data_key_at(nullptr, 0, nullptr);
    ntk_notification_interaction_data_value_at(nullptr, 0, nullptr);
    ntk_notification_interaction_free(nullptr);
    ntk_notification_shown_notification_id(nullptr);
    ntk_notification_shown_tag(nullptr, nullptr);
    ntk_notification_shown_channel_id(nullptr, nullptr);
    ntk_notification_shown_free(nullptr);

    // Share.h (12). The openings reach Kotlin but open no Sharesheet: a blank text (EMPTY_CONTENT)
    // and a file that is not there (FILE_NOT_FOUND). A Sharesheet left behind, closed with Back,
    // could take the next case's process down with its task.
    ntk_share_text_content share{};
    share.struct_size = sizeof(share);
    share.text = "   ";
    ntk_share_chooser_action chooser = {"nw", "No wait", png.data(), png.size()};
    ntk_share_text(&share, &chooser, 1, IgnoreShare, nullptr, nullptr);
    const char* paths[] = {missing.c_str()};
    ntk_share_image(missing.c_str(), nullptr, IgnoreShare, nullptr, nullptr);
    ntk_share_images(paths, 1, IgnoreShare, nullptr, nullptr);
    ntk_share_file(missing.c_str(), IgnoreShare, nullptr, nullptr);
    ntk_share_files(paths, 1, IgnoreShare, nullptr, nullptr);
    ntk_share_direct_target target{};
    target.struct_size = sizeof(target);
    target.id = "ntk-no-wait";
    target.label = "No wait";
    target.icon = png.data();
    target.icon_size = png.size();
    ntk_share_register_direct_target(&target);
    const char* ids[] = {"ntk-no-wait"};
    ntk_share_remove_direct_targets(ids, 1);
    uint64_t selection = 0;
    ntk_share_text_for_selection(&share, IgnoreShare, nullptr, nullptr, &selection);
    ntk_share_cancel_selection(selection);
    ntk_share_listener* share_listener = nullptr;
    ntk_share_add_chooser_action_listener(IgnoreChooserAction, nullptr, nullptr, &share_listener);
    left->share_listeners.push_back(share_listener);
    ntk_share_add_selection_listener(IgnoreSelection, nullptr, nullptr, &share_listener);
    left->share_listeners.push_back(share_listener);
    ntk_share_listener_remove(nullptr);
}

jobject Application(JNIEnv* env) {
    jclass thread = env->FindClass("android/app/ActivityThread");
    jmethodID current = env->GetStaticMethodID(thread, "currentApplication", "()Landroid/app/Application;");
    jobject app = env->CallStaticObjectMethod(thread, current);
    jobject global = env->NewGlobalRef(app);
    env->DeleteLocalRef(app);
    env->DeleteLocalRef(thread);
    return global;
}

}  // namespace

TEST(NoWait, EveryPublicFunctionReturnsWhileTheMainThreadIsHeld) {
    ntktest::GrantNotifications();
    JNIEnv* env = ntktest::Env();
    jobject context = Application(env);
    std::string missing = ntktest::MakeShareFile("ntk_no_wait.png", true) + ".missing";
    std::vector<uint8_t> png = ntktest::PngBytes();
    // Never freed: if a call did wait, the thread outlives the case (see Leaked in TestSupport.h).
    auto* left = new Leftovers;
    auto* done = new std::atomic<bool>(false);

    ntktest::HoldMain();
    std::thread caller([context, missing, png, left, done] {
        JNIEnv* thread_env = ntktest::Env();
        CallEverything(thread_env, context, missing, png, left);
        done->store(true);
        // Attached by ntktest::Env above, so the C ABI did not attach it: detach before exiting.
        JavaVM* vm = nullptr;
        thread_env->GetJavaVM(&vm);
        vm->DetachCurrentThread();
    });
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(20);
    while (!done->load() && std::chrono::steady_clock::now() < deadline) {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    bool returned = done->load();
    ntktest::UnholdMain();
    EXPECT_TRUE(returned) << "a public function waited for the main thread";
    if (!returned) {
        caller.detach();
        return;
    }
    caller.join();

    // What was posted runs now: close what it opened.
    ntktest::DrainMain();
    for (uint64_t id : left->dialogs) ntk_dialog_cancel(id);
    for (auto* listener : left->clipboard_listeners) ntk_clipboard_listener_remove(listener);
    for (auto* listener : left->notification_listeners) ntk_notification_listener_remove(listener);
    for (auto* listener : left->share_listeners) ntk_share_listener_remove(listener);
    ntk_notification_stop_progress();
    ntk_notification_remove_all();
    ntk_notification_cancel_all_scheduled();
    ntktest::DrainMain();
    // The settings screen opened above, which shows after the call returned: wait for it, close
    // it and wait until it is gone, so that the next case does not start while its task changes.
    EXPECT_TRUE(ntktest::UiClosePackage("com.android.settings"));
    ntktest::UiBackToApp();
    env->DeleteGlobalRef(context);
}
