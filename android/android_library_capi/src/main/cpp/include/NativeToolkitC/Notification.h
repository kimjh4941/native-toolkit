/**
 * @file Notification.h
 * @brief Notifications: content and channel builders, showing, scheduling, progress, the
 *        permission, and interaction and shown events.
 *
 * Rules for the whole C ABI (C ABI design part 1, chapter 1): every function may be called from any
 * thread and never waits for the main thread; completions, events and accepted releases arrive on
 * the main thread; strings are NUL-terminated UTF-8; this header is C99, includes only <stddef.h>
 * and <stdint.h>, and is ASCII only. The declarations are those of Appendix A of the C ABI design
 * part 2, which scripts/check_c_abi_contract_android.py compares with this file.
 */
#ifndef NATIVETOOLKITC_NOTIFICATION_H
#define NATIVETOOLKITC_NOTIFICATION_H

#include "Common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_notification_error;
enum {
    NTK_NOTIFICATION_ERROR_NONE = 0,
    NTK_NOTIFICATION_ERROR_INVALID_PARAMETER = 1,
    NTK_NOTIFICATION_ERROR_NOT_INITIALIZED = 2,
    NTK_NOTIFICATION_ERROR_NOT_SUPPORTED = 3,
    NTK_NOTIFICATION_ERROR_UNKNOWN = 4,
    NTK_NOTIFICATION_ERROR_OUT_OF_MEMORY = 5,
    NTK_NOTIFICATION_ERROR_CANCELED = 6,
    NTK_NOTIFICATION_ERROR_CANCELED_BY_SYSTEM = 7,
    NTK_NOTIFICATION_ERROR_NOT_FOREGROUND = 8,
    NTK_NOTIFICATION_ERROR_HOST_START_FAILED = 9,
    NTK_NOTIFICATION_ERROR_PERMISSION_DENIED = 10,
    NTK_NOTIFICATION_ERROR_EXACT_ALARM_NOT_ALLOWED = 11,
    NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND = 12,
    NTK_NOTIFICATION_ERROR_STORAGE_FAILED = 13,
    NTK_NOTIFICATION_ERROR_SERVICE_START_NOT_ALLOWED = 14,
    NTK_NOTIFICATION_ERROR_SETTINGS_NOT_OPENED = 15
};

typedef int32_t ntk_notification_settings_target;
enum {
    NTK_NOTIFICATION_SETTINGS_TARGET_NOTIFICATIONS = 0,
    NTK_NOTIFICATION_SETTINGS_TARGET_APP_DETAILS = 1,
    NTK_NOTIFICATION_SETTINGS_TARGET_EXACT_ALARM = 2
};

typedef int32_t ntk_notification_settings_result;
enum {
    NTK_NOTIFICATION_SETTINGS_RESULT_OPENED = 0,
    NTK_NOTIFICATION_SETTINGS_RESULT_OPENED_FALLBACK = 1
};

typedef int32_t ntk_notification_permission_result;
enum {
    NTK_NOTIFICATION_PERMISSION_RESULT_GRANTED = 0,
    NTK_NOTIFICATION_PERMISSION_RESULT_DENIED = 1
};

typedef int32_t ntk_notification_tap;
enum {
    NTK_NOTIFICATION_TAP_OPEN_APP = 0,            /**< The default: open the app and send a BODY_TAP event. */
    NTK_NOTIFICATION_TAP_EVENT_ONLY = 1,
    NTK_NOTIFICATION_TAP_NONE = 2
};

typedef int32_t ntk_notification_event_kind;
enum {
    NTK_NOTIFICATION_EVENT_KIND_BODY_TAP = 0,
    NTK_NOTIFICATION_EVENT_KIND_ACTION = 1,
    NTK_NOTIFICATION_EVENT_KIND_DISMISS = 2
};

/** A notification being built. Not thread-safe; usable before initialization. Setters copy their arguments. */
typedef struct ntk_notification_content ntk_notification_content;
/** A channel being built. Not thread-safe; usable before initialization. */
typedef struct ntk_notification_channel ntk_notification_channel;
/** An event listener registration. */
typedef struct ntk_notification_listener ntk_notification_listener;
/** A tap, an action or a dismissal. Owned by the receiver: free it. */
typedef struct ntk_notification_interaction ntk_notification_interaction;
/** A scheduled notification was shown. Owned by the receiver: free it. */
typedef struct ntk_notification_shown ntk_notification_shown;

typedef void (NTK_CALL *ntk_notification_settings_fn)(void* user_data, ntk_notification_error error,
                                                      uint32_t system_code,
                                                      ntk_notification_settings_result result);
typedef void (NTK_CALL *ntk_notification_permission_fn)(void* user_data, uint64_t request_id,
                                                        ntk_notification_error error, uint32_t system_code,
                                                        ntk_notification_permission_result result);
typedef void (NTK_CALL *ntk_notification_interaction_fn)(void* user_data, ntk_notification_interaction* event);
typedef void (NTK_CALL *ntk_notification_shown_fn)(void* user_data, ntk_notification_shown* event);

#pragma pack(push, 8)
/** A zero-filled struct with trigger_at_millis set is the default schedule. */
typedef struct ntk_notification_schedule_options {
    uint32_t struct_size;
    uint32_t reserved0;
    int64_t  trigger_at_millis;                   /**< Unix time in milliseconds; at least 1. */
    int32_t  inexact;                             /**< Nonzero: an inexact alarm. */
    int32_t  not_allow_while_idle;                /**< Nonzero: not while idle (Doze). */
    int32_t  not_persist_across_boot;             /**< Nonzero: not restored after a reboot. */
    int32_t  alarm_type;                          /**< 0 (RTC_WAKEUP) or 1 (RTC). */
} ntk_notification_schedule_options;

typedef struct ntk_notification_action {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* action_id;                        /**< Delivered in the ACTION event. */
    const char* icon_name;                        /**< NULL: no icon. */
    int32_t     launch_app;                       /**< Nonzero: open the app when pressed. */
    int32_t     allow_generated_replies;
    int32_t     semantic_action;
    int32_t     contextual;
    int32_t     no_user_interface;                /**< Nonzero: the action does not show UI. */
    uint32_t    reserved1;
} ntk_notification_action;
#pragma pack(pop)

/* Operations run on the calling thread unless marked asynchronous (AP-2). */
/** PERMISSION_DENIED when notifications are not allowed (checked before showing). */
ntk_notification_error NTK_CALL ntk_notification_show(const ntk_notification_content* content);
/** PERMISSION_DENIED when notifications are not allowed (checked before updating). */
ntk_notification_error NTK_CALL ntk_notification_update(const ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_remove(int32_t id, const char* tag);
ntk_notification_error NTK_CALL ntk_notification_remove_all(void);
ntk_notification_error NTK_CALL ntk_notification_create_channel(const ntk_notification_channel* channel);
ntk_notification_error NTK_CALL ntk_notification_delete_channel(const char* channel_id);
/** Writes the schedule to a file on the calling thread. A future exact schedule without the exact
    alarm permission returns EXACT_ALARM_NOT_ALLOWED; a past one without the notification permission
    returns PERMISSION_DENIED. */
ntk_notification_error NTK_CALL ntk_notification_schedule(const ntk_notification_content* content,
                                                          const ntk_notification_schedule_options* schedule);
ntk_notification_error NTK_CALL ntk_notification_cancel_scheduled(int32_t id, const char* tag);
/** Cancels only schedules persisted across boot (as in 1.x). */
ntk_notification_error NTK_CALL ntk_notification_cancel_all_scheduled(void);
ntk_notification_error NTK_CALL ntk_notification_start_progress(const ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_update_progress(const ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_complete_progress(const ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_stop_progress(void);
ntk_notification_error NTK_CALL ntk_notification_has_permission(int32_t* out_value);
ntk_notification_error NTK_CALL ntk_notification_are_enabled(int32_t* out_value);
/** Sees only schedules persisted across boot (as in 1.x). */
ntk_notification_error NTK_CALL ntk_notification_is_scheduled(int32_t id, const char* tag, int32_t* out_value);
ntk_notification_error NTK_CALL ntk_notification_can_schedule_exact_alarms(int32_t* out_value);
/** Asynchronous; needs the app in the foreground. */
ntk_notification_error NTK_CALL ntk_notification_open_settings_async(ntk_notification_settings_target target,
                                                                     ntk_notification_settings_fn callback,
                                                                     void* user_data, ntk_release_fn release);
/** Asynchronous. out_request_id may be NULL. */
ntk_notification_error NTK_CALL ntk_notification_request_permission(ntk_notification_permission_fn callback,
                                                                    void* user_data, ntk_release_fn release,
                                                                    uint64_t* out_request_id);
/** Never waits. Does nothing after completion or for an unknown ID. */
ntk_notification_error NTK_CALL ntk_notification_cancel_permission_request(uint64_t request_id);
ntk_notification_error NTK_CALL ntk_notification_add_interaction_listener(ntk_notification_interaction_fn callback,
                                                                          void* user_data, ntk_release_fn release,
                                                                          ntk_notification_listener** out_listener);
ntk_notification_error NTK_CALL ntk_notification_add_shown_listener(ntk_notification_shown_fn callback,
                                                                    void* user_data, ntk_release_fn release,
                                                                    ntk_notification_listener** out_listener);
/** The handle is invalid afterwards. Does nothing for NULL. */
void NTK_CALL ntk_notification_listener_remove(ntk_notification_listener* listener);

/* Content builder. Starts from the library's defaults. */
ntk_notification_error NTK_CALL ntk_notification_content_create(int32_t id, const char* title, const char* message,
                                                                ntk_notification_content** out_content);
void NTK_CALL ntk_notification_content_free(ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_content_set_tag(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_channel(ntk_notification_content* content,
                                                                     const ntk_notification_channel* channel);
ntk_notification_error NTK_CALL ntk_notification_content_set_small_icon(ntk_notification_content* content,
                                                                        const char* name);
ntk_notification_error NTK_CALL ntk_notification_content_set_large_icon(ntk_notification_content* content,
                                                                        const char* name);
ntk_notification_error NTK_CALL ntk_notification_content_set_priority(ntk_notification_content* content, int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_auto_cancel(ntk_notification_content* content,
                                                                         int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_ongoing(ntk_notification_content* content, int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_sub_text(ntk_notification_content* content,
                                                                      const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_show_timestamp(ntk_notification_content* content,
                                                                            int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_timestamp(ntk_notification_content* content,
                                                                       int64_t unix_ms);
ntk_notification_error NTK_CALL ntk_notification_content_set_sound(ntk_notification_content* content,
                                                                   const char* uri);
ntk_notification_error NTK_CALL ntk_notification_content_set_category(ntk_notification_content* content,
                                                                      const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_visibility(ntk_notification_content* content,
                                                                        int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_color(ntk_notification_content* content, uint32_t argb);
ntk_notification_error NTK_CALL ntk_notification_content_set_number(ntk_notification_content* content, int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_ticker(ntk_notification_content* content,
                                                                    const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_group(ntk_notification_content* content, const char* key);
ntk_notification_error NTK_CALL ntk_notification_content_set_group_summary(ntk_notification_content* content,
                                                                           int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_group_alert_behavior(ntk_notification_content* content,
                                                                                  int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_sort_key(ntk_notification_content* content,
                                                                      const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_only_alert_once(ntk_notification_content* content,
                                                                             int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_local_only(ntk_notification_content* content,
                                                                        int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_silent(ntk_notification_content* content, int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_uses_chronometer(ntk_notification_content* content,
                                                                              int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_timeout_after(ntk_notification_content* content,
                                                                           int64_t millis);
ntk_notification_error NTK_CALL ntk_notification_content_set_progress(ntk_notification_content* content,
                                                                      int32_t max, int32_t current,
                                                                      int32_t indeterminate);
ntk_notification_error NTK_CALL ntk_notification_content_set_style_big_text(ntk_notification_content* content,
                                                                            const char* big_text,
                                                                            const char* summary_text,
                                                                            const char* big_content_title);
ntk_notification_error NTK_CALL ntk_notification_content_set_style_inbox(ntk_notification_content* content,
                                                                         const char* const* lines, size_t line_count,
                                                                         const char* summary_text,
                                                                         const char* big_content_title);
ntk_notification_error NTK_CALL ntk_notification_content_set_style_big_picture(ntk_notification_content* content,
                                                                               const char* picture_name,
                                                                               const char* picture_uri,
                                                                               const char* summary_text,
                                                                               const char* big_content_title,
                                                                               const char* large_icon_name,
                                                                               int32_t hide_expanded_large_icon);
/** group_conversation: -1 leaves it unset, 0 or 1 sets it. */
ntk_notification_error NTK_CALL ntk_notification_content_set_style_messaging(ntk_notification_content* content,
                                                                             const char* user_display_name,
                                                                             const char* conversation_title,
                                                                             int32_t group_conversation);
ntk_notification_error NTK_CALL ntk_notification_content_add_message(ntk_notification_content* content,
                                                                     const char* text, int64_t timestamp_ms,
                                                                     const char* sender_name);
ntk_notification_error NTK_CALL ntk_notification_content_set_style_custom_view(ntk_notification_content* content,
                                                                               const char* layout_name,
                                                                               const char* big_layout_name);
ntk_notification_error NTK_CALL ntk_notification_content_add_view_click(ntk_notification_content* content,
                                                                        const char* view_id_name,
                                                                        const char* action_id);
ntk_notification_error NTK_CALL ntk_notification_content_set_tap(ntk_notification_content* content,
                                                                 ntk_notification_tap mode);
ntk_notification_error NTK_CALL ntk_notification_content_add_data(ntk_notification_content* content, const char* key,
                                                                  const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_dismiss_event(ntk_notification_content* content,
                                                                           int32_t enabled);
ntk_notification_error NTK_CALL ntk_notification_content_set_full_screen(ntk_notification_content* content,
                                                                         int32_t enabled);
ntk_notification_error NTK_CALL ntk_notification_content_add_action(ntk_notification_content* content,
                                                                    const ntk_notification_action* action);

/* Channel builder. Starts from the library's defaults. importance is 0..4 (5 is rejected because
   the library would silently lower it to 3). */
ntk_notification_error NTK_CALL ntk_notification_channel_create(const char* id, const char* name, int32_t importance,
                                                                ntk_notification_channel** out_channel);
void NTK_CALL ntk_notification_channel_free(ntk_notification_channel* channel);
ntk_notification_error NTK_CALL ntk_notification_channel_set_description(ntk_notification_channel* channel,
                                                                         const char* value);
ntk_notification_error NTK_CALL ntk_notification_channel_set_show_badge(ntk_notification_channel* channel,
                                                                        int32_t value);
ntk_notification_error NTK_CALL ntk_notification_channel_set_enable_lights(ntk_notification_channel* channel,
                                                                           int32_t value);
ntk_notification_error NTK_CALL ntk_notification_channel_set_light_color(ntk_notification_channel* channel,
                                                                         uint32_t argb);
ntk_notification_error NTK_CALL ntk_notification_channel_set_enable_vibration(ntk_notification_channel* channel,
                                                                              int32_t value);
ntk_notification_error NTK_CALL ntk_notification_channel_set_vibration_pattern(ntk_notification_channel* channel,
                                                                               const int64_t* pattern, size_t count);
ntk_notification_error NTK_CALL ntk_notification_channel_set_sound(ntk_notification_channel* channel, const char* uri);
ntk_notification_error NTK_CALL ntk_notification_channel_set_lockscreen_visibility(ntk_notification_channel* channel,
                                                                                   int32_t value);
ntk_notification_error NTK_CALL ntk_notification_channel_set_group(ntk_notification_channel* channel,
                                                                   const char* group_id, const char* group_name);

/* Event readers: pointers stay valid until the event is freed. out_size may be NULL. */
ntk_notification_event_kind NTK_CALL ntk_notification_interaction_kind(const ntk_notification_interaction* event);
int32_t     NTK_CALL ntk_notification_interaction_notification_id(const ntk_notification_interaction* event);
/** NULL when the notification has no tag. */
const char* NTK_CALL ntk_notification_interaction_tag(const ntk_notification_interaction* event, size_t* out_size);
/** NULL unless the kind is ACTION. */
const char* NTK_CALL ntk_notification_interaction_action_id(const ntk_notification_interaction* event,
                                                            size_t* out_size);
size_t      NTK_CALL ntk_notification_interaction_data_count(const ntk_notification_interaction* event);
const char* NTK_CALL ntk_notification_interaction_data_key_at(const ntk_notification_interaction* event, size_t index,
                                                              size_t* out_size);
const char* NTK_CALL ntk_notification_interaction_data_value_at(const ntk_notification_interaction* event,
                                                                size_t index, size_t* out_size);
void        NTK_CALL ntk_notification_interaction_free(ntk_notification_interaction* event);

int32_t     NTK_CALL ntk_notification_shown_notification_id(const ntk_notification_shown* event);
const char* NTK_CALL ntk_notification_shown_tag(const ntk_notification_shown* event, size_t* out_size);
const char* NTK_CALL ntk_notification_shown_channel_id(const ntk_notification_shown* event, size_t* out_size);
void        NTK_CALL ntk_notification_shown_free(ntk_notification_shown* event);

#ifdef __cplusplus
}
#endif
#endif
