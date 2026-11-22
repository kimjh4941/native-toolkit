//
//  StructLayoutTests.m
//  IosLibraryCApiTests
//

// The layout of every struct of the public headers, as the C compiler lays them out for the slice
// being built: a wrong number stops the build of the tests on every slice, the device's too, and no
// row can be left out by not running. C, because Swift's MemoryLayout is Swift's view of the import
// and not sizeof and offsetof (C ABI design part 2, 12.1). The numbers were worked out by hand from
// Appendix A with the LP64 rules, not printed by a compiler, and bindings in other languages declare
// the same ones. check_c_abi_contract_ios.py checks that every struct and field of the headers is
// here, and compiles this file for the three slices.

#include <stddef.h>

#include <IosLibraryCApi/NativeToolkitC/Clipboard.h>
#include <IosLibraryCApi/NativeToolkitC/Dialog.h>
#include <IosLibraryCApi/NativeToolkitC/Notification.h>
#include <IosLibraryCApi/NativeToolkitC/Share.h>

#define LAYOUT_SIZE(type, size) _Static_assert(sizeof(type) == (size), "sizeof(" #type ")")
#define LAYOUT_FIELD(type, field, offset) _Static_assert(offsetof(type, field) == (offset), "offsetof(" #type ", " #field ")")

// Clipboard.h

LAYOUT_SIZE(ntk_clipboard_scope, 24);
LAYOUT_FIELD(ntk_clipboard_scope, struct_size, 0);
LAYOUT_FIELD(ntk_clipboard_scope, reserved0, 4);
LAYOUT_FIELD(ntk_clipboard_scope, kind, 8);
LAYOUT_FIELD(ntk_clipboard_scope, reserved1, 12);
LAYOUT_FIELD(ntk_clipboard_scope, name, 16);

LAYOUT_SIZE(ntk_clipboard_representation, 32);
LAYOUT_FIELD(ntk_clipboard_representation, struct_size, 0);
LAYOUT_FIELD(ntk_clipboard_representation, reserved0, 4);
LAYOUT_FIELD(ntk_clipboard_representation, ut_type, 8);
LAYOUT_FIELD(ntk_clipboard_representation, data, 16);
LAYOUT_FIELD(ntk_clipboard_representation, data_size, 24);

LAYOUT_SIZE(ntk_clipboard_write_content, 136);
LAYOUT_FIELD(ntk_clipboard_write_content, struct_size, 0);
LAYOUT_FIELD(ntk_clipboard_write_content, reserved0, 4);
LAYOUT_FIELD(ntk_clipboard_write_content, kind, 8);
LAYOUT_FIELD(ntk_clipboard_write_content, reserved1, 12);
LAYOUT_FIELD(ntk_clipboard_write_content, text, 16);
LAYOUT_FIELD(ntk_clipboard_write_content, html, 24);
LAYOUT_FIELD(ntk_clipboard_write_content, url, 32);
LAYOUT_FIELD(ntk_clipboard_write_content, path, 40);
LAYOUT_FIELD(ntk_clipboard_write_content, data, 48);
LAYOUT_FIELD(ntk_clipboard_write_content, data_size, 56);
LAYOUT_FIELD(ntk_clipboard_write_content, ut_type, 64);
LAYOUT_FIELD(ntk_clipboard_write_content, red, 72);
LAYOUT_FIELD(ntk_clipboard_write_content, green, 80);
LAYOUT_FIELD(ntk_clipboard_write_content, blue, 88);
LAYOUT_FIELD(ntk_clipboard_write_content, alpha, 96);
LAYOUT_FIELD(ntk_clipboard_write_content, texts, 104);
LAYOUT_FIELD(ntk_clipboard_write_content, text_count, 112);
LAYOUT_FIELD(ntk_clipboard_write_content, representations, 120);
LAYOUT_FIELD(ntk_clipboard_write_content, representation_count, 128);

LAYOUT_SIZE(ntk_clipboard_copy_options, 24);
LAYOUT_FIELD(ntk_clipboard_copy_options, struct_size, 0);
LAYOUT_FIELD(ntk_clipboard_copy_options, reserved0, 4);
LAYOUT_FIELD(ntk_clipboard_copy_options, not_local_only, 8);
LAYOUT_FIELD(ntk_clipboard_copy_options, has_expiration, 12);
LAYOUT_FIELD(ntk_clipboard_copy_options, expiration_unix_seconds, 16);

// Dialog.h

LAYOUT_SIZE(ntk_dialog_alert_request, 32);
LAYOUT_FIELD(ntk_dialog_alert_request, struct_size, 0);
LAYOUT_FIELD(ntk_dialog_alert_request, reserved0, 4);
LAYOUT_FIELD(ntk_dialog_alert_request, title, 8);
LAYOUT_FIELD(ntk_dialog_alert_request, message, 16);
LAYOUT_FIELD(ntk_dialog_alert_request, button_text, 24);

LAYOUT_SIZE(ntk_dialog_confirm_request, 40);
LAYOUT_FIELD(ntk_dialog_confirm_request, struct_size, 0);
LAYOUT_FIELD(ntk_dialog_confirm_request, reserved0, 4);
LAYOUT_FIELD(ntk_dialog_confirm_request, title, 8);
LAYOUT_FIELD(ntk_dialog_confirm_request, message, 16);
LAYOUT_FIELD(ntk_dialog_confirm_request, confirm_text, 24);
LAYOUT_FIELD(ntk_dialog_confirm_request, cancel_text, 32);

LAYOUT_SIZE(ntk_dialog_destructive_request, 40);
LAYOUT_FIELD(ntk_dialog_destructive_request, struct_size, 0);
LAYOUT_FIELD(ntk_dialog_destructive_request, reserved0, 4);
LAYOUT_FIELD(ntk_dialog_destructive_request, title, 8);
LAYOUT_FIELD(ntk_dialog_destructive_request, message, 16);
LAYOUT_FIELD(ntk_dialog_destructive_request, destructive_text, 24);
LAYOUT_FIELD(ntk_dialog_destructive_request, cancel_text, 32);

LAYOUT_SIZE(ntk_dialog_action_sheet_request, 48);
LAYOUT_FIELD(ntk_dialog_action_sheet_request, struct_size, 0);
LAYOUT_FIELD(ntk_dialog_action_sheet_request, reserved0, 4);
LAYOUT_FIELD(ntk_dialog_action_sheet_request, title, 8);
LAYOUT_FIELD(ntk_dialog_action_sheet_request, message, 16);
LAYOUT_FIELD(ntk_dialog_action_sheet_request, options, 24);
LAYOUT_FIELD(ntk_dialog_action_sheet_request, option_count, 32);
LAYOUT_FIELD(ntk_dialog_action_sheet_request, cancel_text, 40);

LAYOUT_SIZE(ntk_dialog_text_input_request, 56);
LAYOUT_FIELD(ntk_dialog_text_input_request, struct_size, 0);
LAYOUT_FIELD(ntk_dialog_text_input_request, reserved0, 4);
LAYOUT_FIELD(ntk_dialog_text_input_request, title, 8);
LAYOUT_FIELD(ntk_dialog_text_input_request, message, 16);
LAYOUT_FIELD(ntk_dialog_text_input_request, placeholder, 24);
LAYOUT_FIELD(ntk_dialog_text_input_request, confirm_text, 32);
LAYOUT_FIELD(ntk_dialog_text_input_request, cancel_text, 40);
LAYOUT_FIELD(ntk_dialog_text_input_request, confirm_disabled_when_empty, 48);
LAYOUT_FIELD(ntk_dialog_text_input_request, reserved1, 52);

LAYOUT_SIZE(ntk_dialog_login_request, 64);
LAYOUT_FIELD(ntk_dialog_login_request, struct_size, 0);
LAYOUT_FIELD(ntk_dialog_login_request, reserved0, 4);
LAYOUT_FIELD(ntk_dialog_login_request, title, 8);
LAYOUT_FIELD(ntk_dialog_login_request, message, 16);
LAYOUT_FIELD(ntk_dialog_login_request, username_placeholder, 24);
LAYOUT_FIELD(ntk_dialog_login_request, password_placeholder, 32);
LAYOUT_FIELD(ntk_dialog_login_request, login_text, 40);
LAYOUT_FIELD(ntk_dialog_login_request, cancel_text, 48);
LAYOUT_FIELD(ntk_dialog_login_request, login_disabled_when_empty, 56);
LAYOUT_FIELD(ntk_dialog_login_request, reserved1, 60);

// Notification.h

LAYOUT_SIZE(ntk_notification_trigger, 96);
LAYOUT_FIELD(ntk_notification_trigger, struct_size, 0);
LAYOUT_FIELD(ntk_notification_trigger, reserved0, 4);
LAYOUT_FIELD(ntk_notification_trigger, kind, 8);
LAYOUT_FIELD(ntk_notification_trigger, repeats, 12);
LAYOUT_FIELD(ntk_notification_trigger, interval_seconds, 16);
LAYOUT_FIELD(ntk_notification_trigger, calendar_fields, 24);
LAYOUT_FIELD(ntk_notification_trigger, year, 28);
LAYOUT_FIELD(ntk_notification_trigger, month, 32);
LAYOUT_FIELD(ntk_notification_trigger, day, 36);
LAYOUT_FIELD(ntk_notification_trigger, hour, 40);
LAYOUT_FIELD(ntk_notification_trigger, minute, 44);
LAYOUT_FIELD(ntk_notification_trigger, second, 48);
LAYOUT_FIELD(ntk_notification_trigger, reserved1, 52);
LAYOUT_FIELD(ntk_notification_trigger, location_identifier, 56);
LAYOUT_FIELD(ntk_notification_trigger, latitude, 64);
LAYOUT_FIELD(ntk_notification_trigger, longitude, 72);
LAYOUT_FIELD(ntk_notification_trigger, radius, 80);
LAYOUT_FIELD(ntk_notification_trigger, not_notify_on_entry, 88);
LAYOUT_FIELD(ntk_notification_trigger, notify_on_exit, 92);

LAYOUT_SIZE(ntk_notification_action, 40);
LAYOUT_FIELD(ntk_notification_action, struct_size, 0);
LAYOUT_FIELD(ntk_notification_action, reserved0, 4);
LAYOUT_FIELD(ntk_notification_action, identifier, 8);
LAYOUT_FIELD(ntk_notification_action, title, 16);
LAYOUT_FIELD(ntk_notification_action, sf_symbol_name, 24);
LAYOUT_FIELD(ntk_notification_action, options, 32);
LAYOUT_FIELD(ntk_notification_action, reserved1, 36);

LAYOUT_SIZE(ntk_notification_text_input_action, 40);
LAYOUT_FIELD(ntk_notification_text_input_action, struct_size, 0);
LAYOUT_FIELD(ntk_notification_text_input_action, reserved0, 4);
LAYOUT_FIELD(ntk_notification_text_input_action, identifier, 8);
LAYOUT_FIELD(ntk_notification_text_input_action, title, 16);
LAYOUT_FIELD(ntk_notification_text_input_action, button_title, 24);
LAYOUT_FIELD(ntk_notification_text_input_action, placeholder, 32);

LAYOUT_SIZE(ntk_notification_category, 56);
LAYOUT_FIELD(ntk_notification_category, struct_size, 0);
LAYOUT_FIELD(ntk_notification_category, reserved0, 4);
LAYOUT_FIELD(ntk_notification_category, options, 8);
LAYOUT_FIELD(ntk_notification_category, reserved1, 12);
LAYOUT_FIELD(ntk_notification_category, identifier, 16);
LAYOUT_FIELD(ntk_notification_category, actions, 24);
LAYOUT_FIELD(ntk_notification_category, action_count, 32);
LAYOUT_FIELD(ntk_notification_category, text_input_actions, 40);
LAYOUT_FIELD(ntk_notification_category, text_input_action_count, 48);

// Share.h

LAYOUT_SIZE(ntk_share_item, 24);
LAYOUT_FIELD(ntk_share_item, struct_size, 0);
LAYOUT_FIELD(ntk_share_item, reserved0, 4);
LAYOUT_FIELD(ntk_share_item, kind, 8);
LAYOUT_FIELD(ntk_share_item, reserved1, 12);
LAYOUT_FIELD(ntk_share_item, value, 16);

LAYOUT_SIZE(ntk_share_request, 56);
LAYOUT_FIELD(ntk_share_request, struct_size, 0);
LAYOUT_FIELD(ntk_share_request, reserved0, 4);
LAYOUT_FIELD(ntk_share_request, items, 8);
LAYOUT_FIELD(ntk_share_request, item_count, 16);
LAYOUT_FIELD(ntk_share_request, subject, 24);
LAYOUT_FIELD(ntk_share_request, preview_title, 32);
LAYOUT_FIELD(ntk_share_request, excluded_activity_types, 40);
LAYOUT_FIELD(ntk_share_request, excluded_activity_type_count, 48);
