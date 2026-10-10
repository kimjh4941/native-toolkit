// The layout of every struct of Appendix A (C ABI design part 2, 12.1 構造体の配置): the size and
// the offset of every field, as consumers that redeclare the structs (C#, Dart, Rust bindings)
// rely on them. The library is 64-bit only (arm64-v8a and x86_64, both LP64), and this file is
// compiled for both, so a change of layout on either fails the build. The values were counted
// from the headers by the LP64 rules; a deliberate change updates them here and in Appendix A.
#include <gtest/gtest.h>

#include <cstddef>

#include <NativeToolkitC/Clipboard.h>
#include <NativeToolkitC/Dialog.h>
#include <NativeToolkitC/Notification.h>
#include <NativeToolkitC/Share.h>

static_assert(sizeof(void*) == 8, "the C ABI is 64-bit only (README D-10)");


static_assert(sizeof(ntk_clipboard_copy_options) == 24);
static_assert(offsetof(ntk_clipboard_copy_options, struct_size) == 0);
static_assert(offsetof(ntk_clipboard_copy_options, reserved0) == 4);
static_assert(offsetof(ntk_clipboard_copy_options, label) == 8);
static_assert(offsetof(ntk_clipboard_copy_options, sensitive) == 16);
static_assert(offsetof(ntk_clipboard_copy_options, reserved1) == 20);

static_assert(sizeof(ntk_dialog_alert_request) == 40);
static_assert(offsetof(ntk_dialog_alert_request, struct_size) == 0);
static_assert(offsetof(ntk_dialog_alert_request, reserved0) == 4);
static_assert(offsetof(ntk_dialog_alert_request, title) == 8);
static_assert(offsetof(ntk_dialog_alert_request, message) == 16);
static_assert(offsetof(ntk_dialog_alert_request, button_text) == 24);
static_assert(offsetof(ntk_dialog_alert_request, not_cancelable) == 32);
static_assert(offsetof(ntk_dialog_alert_request, not_cancelable_on_touch_outside) == 36);

static_assert(sizeof(ntk_dialog_confirm_request) == 48);
static_assert(offsetof(ntk_dialog_confirm_request, struct_size) == 0);
static_assert(offsetof(ntk_dialog_confirm_request, reserved0) == 4);
static_assert(offsetof(ntk_dialog_confirm_request, title) == 8);
static_assert(offsetof(ntk_dialog_confirm_request, message) == 16);
static_assert(offsetof(ntk_dialog_confirm_request, negative_text) == 24);
static_assert(offsetof(ntk_dialog_confirm_request, positive_text) == 32);
static_assert(offsetof(ntk_dialog_confirm_request, not_cancelable) == 40);
static_assert(offsetof(ntk_dialog_confirm_request, not_cancelable_on_touch_outside) == 44);

static_assert(sizeof(ntk_dialog_single_choice_request) == 64);
static_assert(offsetof(ntk_dialog_single_choice_request, struct_size) == 0);
static_assert(offsetof(ntk_dialog_single_choice_request, reserved0) == 4);
static_assert(offsetof(ntk_dialog_single_choice_request, title) == 8);
static_assert(offsetof(ntk_dialog_single_choice_request, items) == 16);
static_assert(offsetof(ntk_dialog_single_choice_request, item_count) == 24);
static_assert(offsetof(ntk_dialog_single_choice_request, checked_index) == 32);
static_assert(offsetof(ntk_dialog_single_choice_request, not_cancelable) == 36);
static_assert(offsetof(ntk_dialog_single_choice_request, not_cancelable_on_touch_outside) == 40);
static_assert(offsetof(ntk_dialog_single_choice_request, reserved1) == 44);
static_assert(offsetof(ntk_dialog_single_choice_request, negative_text) == 48);
static_assert(offsetof(ntk_dialog_single_choice_request, positive_text) == 56);

static_assert(sizeof(ntk_dialog_multi_choice_request) == 64);
static_assert(offsetof(ntk_dialog_multi_choice_request, struct_size) == 0);
static_assert(offsetof(ntk_dialog_multi_choice_request, reserved0) == 4);
static_assert(offsetof(ntk_dialog_multi_choice_request, title) == 8);
static_assert(offsetof(ntk_dialog_multi_choice_request, items) == 16);
static_assert(offsetof(ntk_dialog_multi_choice_request, item_count) == 24);
static_assert(offsetof(ntk_dialog_multi_choice_request, checked) == 32);
static_assert(offsetof(ntk_dialog_multi_choice_request, negative_text) == 40);
static_assert(offsetof(ntk_dialog_multi_choice_request, positive_text) == 48);
static_assert(offsetof(ntk_dialog_multi_choice_request, not_cancelable) == 56);
static_assert(offsetof(ntk_dialog_multi_choice_request, not_cancelable_on_touch_outside) == 60);

static_assert(sizeof(ntk_dialog_text_input_request) == 64);
static_assert(offsetof(ntk_dialog_text_input_request, struct_size) == 0);
static_assert(offsetof(ntk_dialog_text_input_request, reserved0) == 4);
static_assert(offsetof(ntk_dialog_text_input_request, title) == 8);
static_assert(offsetof(ntk_dialog_text_input_request, message) == 16);
static_assert(offsetof(ntk_dialog_text_input_request, hint) == 24);
static_assert(offsetof(ntk_dialog_text_input_request, negative_text) == 32);
static_assert(offsetof(ntk_dialog_text_input_request, positive_text) == 40);
static_assert(offsetof(ntk_dialog_text_input_request, enable_positive_when_empty) == 48);
static_assert(offsetof(ntk_dialog_text_input_request, not_cancelable) == 52);
static_assert(offsetof(ntk_dialog_text_input_request, not_cancelable_on_touch_outside) == 56);
static_assert(offsetof(ntk_dialog_text_input_request, reserved1) == 60);

static_assert(sizeof(ntk_dialog_login_request) == 72);
static_assert(offsetof(ntk_dialog_login_request, struct_size) == 0);
static_assert(offsetof(ntk_dialog_login_request, reserved0) == 4);
static_assert(offsetof(ntk_dialog_login_request, title) == 8);
static_assert(offsetof(ntk_dialog_login_request, message) == 16);
static_assert(offsetof(ntk_dialog_login_request, username_hint) == 24);
static_assert(offsetof(ntk_dialog_login_request, password_hint) == 32);
static_assert(offsetof(ntk_dialog_login_request, negative_text) == 40);
static_assert(offsetof(ntk_dialog_login_request, positive_text) == 48);
static_assert(offsetof(ntk_dialog_login_request, enable_positive_when_empty) == 56);
static_assert(offsetof(ntk_dialog_login_request, not_cancelable) == 60);
static_assert(offsetof(ntk_dialog_login_request, not_cancelable_on_touch_outside) == 64);
static_assert(offsetof(ntk_dialog_login_request, reserved1) == 68);

static_assert(sizeof(ntk_notification_schedule_options) == 32);
static_assert(offsetof(ntk_notification_schedule_options, struct_size) == 0);
static_assert(offsetof(ntk_notification_schedule_options, reserved0) == 4);
static_assert(offsetof(ntk_notification_schedule_options, trigger_at_millis) == 8);
static_assert(offsetof(ntk_notification_schedule_options, inexact) == 16);
static_assert(offsetof(ntk_notification_schedule_options, not_allow_while_idle) == 20);
static_assert(offsetof(ntk_notification_schedule_options, not_persist_across_boot) == 24);
static_assert(offsetof(ntk_notification_schedule_options, alarm_type) == 28);

static_assert(sizeof(ntk_notification_action) == 56);
static_assert(offsetof(ntk_notification_action, struct_size) == 0);
static_assert(offsetof(ntk_notification_action, reserved0) == 4);
static_assert(offsetof(ntk_notification_action, title) == 8);
static_assert(offsetof(ntk_notification_action, action_id) == 16);
static_assert(offsetof(ntk_notification_action, icon_name) == 24);
static_assert(offsetof(ntk_notification_action, launch_app) == 32);
static_assert(offsetof(ntk_notification_action, allow_generated_replies) == 36);
static_assert(offsetof(ntk_notification_action, semantic_action) == 40);
static_assert(offsetof(ntk_notification_action, contextual) == 44);
static_assert(offsetof(ntk_notification_action, no_user_interface) == 48);
static_assert(offsetof(ntk_notification_action, reserved1) == 52);

static_assert(sizeof(ntk_share_text_content) == 56);
static_assert(offsetof(ntk_share_text_content, struct_size) == 0);
static_assert(offsetof(ntk_share_text_content, reserved0) == 4);
static_assert(offsetof(ntk_share_text_content, text) == 8);
static_assert(offsetof(ntk_share_text_content, title) == 16);
static_assert(offsetof(ntk_share_text_content, subject) == 24);
static_assert(offsetof(ntk_share_text_content, mime_type) == 32);
static_assert(offsetof(ntk_share_text_content, preview_title) == 40);
static_assert(offsetof(ntk_share_text_content, preview_thumbnail_path) == 48);

static_assert(sizeof(ntk_share_chooser_action) == 32);
static_assert(offsetof(ntk_share_chooser_action, id) == 0);
static_assert(offsetof(ntk_share_chooser_action, label) == 8);
static_assert(offsetof(ntk_share_chooser_action, icon) == 16);
static_assert(offsetof(ntk_share_chooser_action, icon_size) == 24);

static_assert(sizeof(ntk_share_direct_target) == 48);
static_assert(offsetof(ntk_share_direct_target, struct_size) == 0);
static_assert(offsetof(ntk_share_direct_target, reserved0) == 4);
static_assert(offsetof(ntk_share_direct_target, id) == 8);
static_assert(offsetof(ntk_share_direct_target, label) == 16);
static_assert(offsetof(ntk_share_direct_target, category) == 24);
static_assert(offsetof(ntk_share_direct_target, icon) == 32);
static_assert(offsetof(ntk_share_direct_target, icon_size) == 40);

// The checks above run at compile time; this case makes the file a visible part of the run.
TEST(StructLayout, EveryAppendixAStructHasItsLayoutOnThisAbi) {
    SUCCEED() << "12 structs checked at compile time";
}
